import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  collectChangedGdscriptPaths,
  compactUnavailableReason,
  formatDiagnosticsReport,
  parseLspMessages,
} from '../gdscript-lsp-check.mjs';

const HOOK_DIR = dirname(fileURLToPath(new URL('../gdscript-lsp-check.mjs', import.meta.url)));
const REPO_ROOT = join(HOOK_DIR, '..', '..');

test('codex registration calls the shell wrapper instead of node directly', () => {
  const hooks = JSON.parse(readFileSync(join(REPO_ROOT, '.codex/hooks.json'), 'utf8'));
  const postHooks = hooks.hooks.PostToolUse.flatMap((entry) => entry.hooks);
  const lspHook = postHooks.find((hook) => hook.statusMessage === 'Checking GDScript diagnostics');

  assert.ok(lspHook, 'expected GDScript LSP hook registration');
  assert.match(lspHook.command, /gdscript-lsp-check\.sh/);
  assert.doesNotMatch(lspHook.command, /^node\b/);
});

test('shell wrapper starts when Codex GUI PATH cannot find Homebrew node', () => {
  const result = spawnSync(join(HOOK_DIR, 'gdscript-lsp-check.sh'), {
    cwd: REPO_ROOT,
    input: JSON.stringify({
      tool_name: 'Write',
      tool_input: { file_path: 'README.md' },
    }),
    encoding: 'utf8',
    env: {
      CODEX_PROJECT_DIR: REPO_ROOT,
      PATH: '/usr/bin:/bin:/usr/sbin:/sbin',
    },
  });

  assert.equal(result.status, 0, result.stderr || result.error?.message);
  assert.equal(result.stdout, '');
});

test('collects changed gdscript paths from a Codex apply_patch payload', () => {
  const input = {
    tool_name: 'apply_patch',
    tool_input: {
      command: [
        '*** Begin Patch',
        '*** Update File: gol-project/scripts/player.gd',
        '@@',
        '+func _ready():',
        '+    pass',
        '*** Add File: gol-project/scripts/new_enemy.gd',
        '+extends Node',
        '*** Delete File: gol-project/scripts/old_enemy.gd',
        '*** End Patch',
      ].join('\n'),
    },
  };

  assert.deepEqual(collectChangedGdscriptPaths(input), [
    'gol-project/scripts/player.gd',
    'gol-project/scripts/new_enemy.gd',
  ]);
});

test('collects gdscript paths from write-style payloads', () => {
  assert.deepEqual(
    collectChangedGdscriptPaths({
      tool_name: 'Write',
      tool_input: { file_path: '/repo/gol-project/scripts/player.gd' },
    }),
    ['/repo/gol-project/scripts/player.gd'],
  );
});

test('formats diagnostics with severity, location, and message', () => {
  const report = formatDiagnosticsReport('/repo/gol-project/scripts/player.gd', [
    {
      severity: 1,
      range: { start: { line: 4, character: 2 } },
      message: 'Unexpected token',
      source: 'gdscript',
    },
    {
      severity: 2,
      range: { start: { line: 7, character: 0 } },
      message: 'Unused variable',
    },
  ]);

  assert.equal(
    report,
    [
      '/repo/gol-project/scripts/player.gd',
      '  error 5:3 gdscript Unexpected token',
      '  warning 8:1 Unused variable',
    ].join('\n'),
  );
});

test('parses concatenated LSP messages from a buffer', () => {
  const one = JSON.stringify({ method: 'initialized' });
  const two = JSON.stringify({ id: 1, result: {} });
  const buffer = Buffer.from(
    `Content-Length: ${Buffer.byteLength(one)}\r\n\r\n${one}` +
      `Content-Length: ${Buffer.byteLength(two)}\r\n\r\n${two}`,
  );

  const { messages, remaining } = parseLspMessages(buffer);

  assert.deepEqual(messages, [{ method: 'initialized' }, { id: 1, result: {} }]);
  assert.equal(remaining.length, 0);
});

test('compacts repeated bridge connection errors for hook feedback', () => {
  assert.equal(
    compactUnavailableReason([
      'Could not connect to Godot LSP. Waiting for Godot to become available...',
      'Connection to Godot LSP closed. Reconnecting in 5s... (attempt 1)',
    ].join('\n')),
    'Could not connect to Godot LSP',
  );
});
