import assert from 'node:assert/strict';
import test from 'node:test';

import {
  collectChangedGdscriptPaths,
  compactUnavailableReason,
  formatDiagnosticsReport,
  parseLspMessages,
} from '../gdscript-lsp-check.mjs';

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
