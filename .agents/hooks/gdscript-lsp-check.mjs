#!/usr/bin/env node
import { spawn, execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, isAbsolute, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const DEFAULT_TIMEOUT_MS = 8000;
const DIAGNOSTIC_REQUEST_ID = 2;
const INITIALIZE_REQUEST_ID = 1;
const SEVERITY_LABELS = {
  1: 'error',
  2: 'warning',
  3: 'info',
  4: 'hint',
};

export function collectChangedGdscriptPaths(input) {
  const paths = [];
  const addPath = (value) => {
    if (typeof value !== 'string' || !value.endsWith('.gd')) return;
    if (!paths.includes(value)) paths.push(value);
  };

  const toolInput = input?.tool_input ?? {};
  addPath(toolInput.file_path);
  addPath(toolInput.filePath);
  addPath(toolInput.path);

  const command = typeof toolInput.command === 'string' ? toolInput.command : '';
  for (const line of command.split('\n')) {
    const match = line.match(/^\*\*\* (Add|Update) File: (.+)$/);
    if (match) addPath(match[2].trim());
  }

  return paths;
}

export function parseLspMessages(buffer) {
  const messages = [];
  let offset = 0;

  while (offset < buffer.length) {
    const headerEnd = buffer.indexOf('\r\n\r\n', offset, 'utf8');
    if (headerEnd === -1) break;

    const header = buffer.subarray(offset, headerEnd).toString('utf8');
    const match = header.match(/Content-Length:\s*(\d+)/i);
    if (!match) {
      offset = headerEnd + 4;
      continue;
    }

    const length = Number.parseInt(match[1], 10);
    const bodyStart = headerEnd + 4;
    const bodyEnd = bodyStart + length;
    if (buffer.length < bodyEnd) break;

    const body = buffer.subarray(bodyStart, bodyEnd).toString('utf8');
    messages.push(JSON.parse(body));
    offset = bodyEnd;
  }

  return { messages, remaining: buffer.subarray(offset) };
}

export function formatDiagnosticsReport(filePath, diagnostics) {
  const lines = [filePath];
  for (const diagnostic of diagnostics) {
    const severity = SEVERITY_LABELS[diagnostic.severity] ?? 'diagnostic';
    const line = (diagnostic.range?.start?.line ?? 0) + 1;
    const column = (diagnostic.range?.start?.character ?? 0) + 1;
    const source = diagnostic.source ? `${diagnostic.source} ` : '';
    lines.push(`  ${severity} ${line}:${column} ${source}${diagnostic.message}`);
  }
  return lines.join('\n');
}

export function compactUnavailableReason(stderr) {
  if (stderr.includes('Could not connect to Godot LSP')) {
    return 'Could not connect to Godot LSP';
  }
  return stderr.trim() || 'Timed out waiting for Godot LSP diagnostics';
}

function lspFrame(message) {
  const json = JSON.stringify(message);
  return `Content-Length: ${Buffer.byteLength(json)}\r\n\r\n${json}`;
}

function readStdin() {
  return new Promise((resolveRead) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => {
      data += chunk;
    });
    process.stdin.on('end', () => resolveRead(data));
  });
}

function repoRoot() {
  if (process.env.CODEX_PROJECT_DIR) return process.env.CODEX_PROJECT_DIR;
  if (process.env.CLAUDE_PROJECT_DIR) return process.env.CLAUDE_PROJECT_DIR;
  try {
    return execFileSync('git', ['rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return process.cwd();
  }
}

function resolvePath(root, filePath) {
  return isAbsolute(filePath) ? filePath : resolve(root, filePath);
}

function projectPath(root) {
  if (existsSync(join(root, 'project.godot'))) return root;
  return join(root, 'gol-project');
}

function buildInitialize(root) {
  const project = projectPath(root);
  return {
    jsonrpc: '2.0',
    id: INITIALIZE_REQUEST_ID,
    method: 'initialize',
    params: {
      processId: process.pid,
      rootUri: pathToFileURL(project).href,
      capabilities: {
        textDocument: {
          publishDiagnostics: {},
          diagnostic: {},
        },
      },
      clientInfo: {
        name: 'gol-codex-gdscript-hook',
      },
    },
  };
}

function buildDidOpen(filePath, text) {
  const uri = pathToFileURL(filePath).href;
  return {
    jsonrpc: '2.0',
    method: 'textDocument/didOpen',
    params: {
      textDocument: {
        uri,
        languageId: 'gdscript',
        version: 1,
        text,
      },
    },
  };
}

function buildDiagnosticRequest(filePath) {
  return {
    jsonrpc: '2.0',
    id: DIAGNOSTIC_REQUEST_ID,
    method: 'textDocument/diagnostic',
    params: {
      textDocument: {
        uri: pathToFileURL(filePath).href,
      },
    },
  };
}

async function runBridgeDiagnostics(root, filePath, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const bridgePath = join(root, 'gol-tools', 'gds-lsp', 'index.mjs');
  if (!existsSync(bridgePath)) {
    return { status: 'unavailable', reason: `GDScript LSP bridge not found at ${bridgePath}` };
  }

  const text = readFileSync(filePath, 'utf8');
  const uri = pathToFileURL(filePath).href;
  const child = spawn(process.execPath, [bridgePath], {
    cwd: root,
    env: {
      ...process.env,
      GODOT_PROJECT_PATH: projectPath(root),
      GODOT_LSP_AUTO_START: 'false',
    },
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  let stdoutBuffer = Buffer.alloc(0);
  let stderr = '';
  let initialized = false;
  let finished = false;

  return await new Promise((resolveCheck) => {
    const finish = (result) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      child.kill('SIGTERM');
      resolveCheck(result);
    };

    const timer = setTimeout(() => {
      const reason = compactUnavailableReason(stderr);
      finish({ status: 'unavailable', reason });
    }, timeoutMs);

    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
    });

    child.on('error', (error) => {
      finish({ status: 'unavailable', reason: error.message });
    });

    child.on('exit', (code) => {
      if (!finished && code !== 0) {
        const reason = stderr.trim() || `GDScript LSP bridge exited with code ${code}`;
        finish({ status: 'unavailable', reason });
      }
    });

    child.stdout.on('data', (chunk) => {
      stdoutBuffer = Buffer.concat([stdoutBuffer, chunk]);
      const parsed = parseLspMessages(stdoutBuffer);
      stdoutBuffer = parsed.remaining;

      for (const message of parsed.messages) {
        if (message.id === INITIALIZE_REQUEST_ID && !initialized) {
          initialized = true;
          child.stdin.write(lspFrame({ jsonrpc: '2.0', method: 'initialized', params: {} }));
          child.stdin.write(lspFrame(buildDidOpen(filePath, text)));
          child.stdin.write(lspFrame(buildDiagnosticRequest(filePath)));
          continue;
        }

        if (message.method === 'textDocument/publishDiagnostics' && message.params?.uri === uri) {
          finish({ status: 'ok', diagnostics: message.params.diagnostics ?? [] });
          return;
        }

        if (message.id === DIAGNOSTIC_REQUEST_ID) {
          finish({ status: 'ok', diagnostics: message.result?.items ?? [] });
          return;
        }
      }
    });

    child.stdin.write(lspFrame(buildInitialize(root)));
  });
}

function codexFeedback(message, block = false) {
  const payload = {
    hookSpecificOutput: {
      hookEventName: 'PostToolUse',
      additionalContext: message,
    },
  };

  if (block) {
    payload.decision = 'block';
    payload.reason = message;
  }

  return `${JSON.stringify(payload)}\n`;
}

async function main() {
  const raw = await readStdin();
  const input = raw.trim() ? JSON.parse(raw) : {};
  const root = repoRoot();
  const paths = collectChangedGdscriptPaths(input)
    .map((filePath) => resolvePath(root, filePath))
    .filter((filePath) => existsSync(filePath));

  if (paths.length === 0) return;

  const unavailable = [];
  const reports = [];

  for (const filePath of paths) {
    const result = await runBridgeDiagnostics(root, filePath);
    if (result.status === 'unavailable') {
      unavailable.push(`${filePath}: ${result.reason}`);
      continue;
    }

    const diagnostics = (result.diagnostics ?? []).filter((diagnostic) => {
      const severity = diagnostic.severity ?? 1;
      return severity <= 2;
    });
    if (diagnostics.length > 0) {
      reports.push(formatDiagnosticsReport(filePath, diagnostics));
    }
  }

  if (reports.length > 0) {
    process.stdout.write(codexFeedback(
      [
        'GDScript LSP diagnostics found after editing .gd files:',
        '',
        reports.join('\n\n'),
        '',
        'Fix these diagnostics before continuing.',
      ].join('\n'),
      true,
    ));
    return;
  }

  if (unavailable.length > 0) {
    process.stdout.write(codexFeedback(
      [
        'GDScript LSP check skipped because the Godot LSP bridge was unavailable.',
        'Start the Godot editor or run `gol run editor` to enable live .gd diagnostics.',
        '',
        unavailable.join('\n'),
      ].join('\n'),
    ));
  }
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  main().catch((error) => {
    process.stderr.write(`GDScript LSP hook failed: ${error.message}\n`);
    process.exit(1);
  });
}
