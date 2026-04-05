# create-omo-cc-compatible-skill

Use this skill when creating Claude Code hooks (PreToolUse/PostToolUse) that must work in both Claude Code native and OpenCode+OMO (oh-my-openagent) environments, writing shell-command hooks for `.claude/settings.json`, debugging hooks that fire in one client but not the other, or converting hookify declarative rules to cross-platform shell scripts.

## Overview

Write shell-command hooks for `.claude/settings.json` that execute correctly in **both** Claude Code and OpenCode+OMO. The bridge exists but has subtle behavioral differences that cause silent failures if you follow CC-only patterns.

**Core principle**: OMO bridges CC hooks via `claude-code-hooks` module, but stdin JSON structure, env vars, and timing differ. Write to the intersection.

## When To Use

```
Need a hook?
├── Only Claude Code ever? → Use any CC hook pattern
├── Both CC and OMO? → Follow this skill
├── PostToolUse needed? → Extra caution (see Common Mistakes)
└── Converting hookify rules? → Must become shell script (hookify NOT bridged)
```

**Trigger symptoms**:
- Hook fires in Claude Code but not in opencode
- Hook blocks/warns correctly in one client, silently passes in the other
- Exit code 2 doesn't block the operation in opencode
- `$CLAUDE_FILE_PATH` is empty at runtime
- `jq` returns empty for fields that look correct
- "Hook not firing" after opencode restart

**When NOT to use**:
- Pure CC-only environments (no OMO)
- OMO-native features (agent permissions, `permission.edit: deny`)
- Prompt-type hooks (context injection works identically in both)

## The stdin JSON Contract

This is the #1 source of cross-platform bugs. **Both clients send JSON on stdin**, but the field names changed in CC 2.x:

### Correct Structure (CC 2.x + OMO)

```json
{
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/path/to/file.gd",
    "content": "extends Node\n..."
  }
}
```

### Wrong Structure (CC 1.x / outdated docs)

```json
{
  "tool_name": "Write",
  "input": {
    "file_path": "/path/to/file.gd",
    "content": "..."
  }
}
```

**Always use `.tool_input.*` path. Never `.input.*`.**

## Mandatory Shell Pattern

Every hook script MUST follow this exact skeleton:

```bash
#!/usr/bin/env bash
# <event> hook: <one-line description>
# Exit 0 = allow, exit 2 = deny (PreToolUse only)
#
# Stdin JSON: {"tool_name":"<Tool>","tool_input":{"file_path":"...","content":"..."}}

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }

# Read stdin ONLY ONCE — stdin is single-use pipe
INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""')

# --- your logic here ---

exit 0
```

### Critical Rules

| Rule | Why |
|------|-----|
| `INPUT=$(cat)` once, then use `$INPUT` | Two `$(cat \| jq)` calls = second reads empty pipe (silent failure!) |
| `jq -r '.tool_input.file_path'` | Not `.input.file_path` — field renamed in CC 2.x |
| `// empty` default | Prevents `null` literal in string comparisons |
| `>&2` on block messages | stderr becomes Claude's feedback text |

### Anti-Patterns That Silently Fail

```bash
# ❌ Double-consumption — second jq always gets empty stdin
FILE_PATH=$(jq -r '.tool_input.file_path // empty')
CONTENT=$(jq -r '.tool_input.content // ""')   # ← ALWAYS EMPTY

# ❌ Wrong field name (CC 1.x era)
FILE_PATH=$(jq -r '.input.file_path // empty')  # ← ALWAYS EMPTY in CC 2.x+/OMO

# ❌ $CLAUDE_FILE_PATH env var — NOT set by OMO's hook bridge
if echo "$CLAUDE_FILE_PATH" | grep -qE "\.gd$"; then  # ← NEVER MATCHES
```

## PreToolUse vs PostToolUse Cross-Platform Matrix

| Feature | PreToolUse | PostToolUse |
|--------|-----------|-------------|
| Bridged by OMO | ✅ `tool.execute.before` | ✅ `tool.execute.after` |
| Exit 0 = allow | ✅ | ✅ (informational) |
| Exit 2 = deny/block | ✅ Throws error | ❌ Operation already done |
| Stdin JSON format | Same | Same (+ `tool_output` field) |
| Real-world reliability | ✅ Battle-tested | ⚠️ Verify after each restart |

**PostToolUse caveat**: OMO's source code bridges it (`createToolExecuteAfterHandler`), but real-world testing shows intermittent failures. Always test with actual Write/Edit calls, not just manual `echo ... \| script.sh`.

## Settings.json Registration

### File Locations OMO Reads (in priority order):

1. `~/.claude/settings.json` — user-level
2. `<project>/.claude/settings.json` — project-level ← **put project hooks here**
3. `<project>/.claude/settings.local.json` — project-local

### Registration Format

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{
          "type": "command",
          "command": ".claude/hooks/my-hook.sh"
        }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [{
          "type": "command",
          "command": ".claude/hooks/my-post-hook.sh"
        }]
      }
    ]
  }
}
```

### Key Registration Rules

- **Matcher is regex-like**: `"Write|Edit"` matches either, case-sensitive (`"write"` ≠ `"Write"`)
- **Command is relative to project root**: `.claude/hooks/script.sh` resolves from CWD
- **Script MUST be executable**: `chmod +x .claude/hooks/script.sh`
- **OMO requires `"claude_code": { "hooks": true }`** in `.opencode/oh-my-openagent.jsonc`
- **After editing settings.json, RESTART opencode** — OMO caches settings at startup

## Converting Hookify Rules → Shell Scripts

Hookify declarative rules (`.claude/hookify.*.md`) are **NOT bridged** by OMO — they're Claude Code plugin-only. Convert critical ones to shell scripts:

### Example: Block GdUnitTestSuite in integration/

```bash
#!/usr/bin/env bash
# PreToolUse: Block GdUnitTestSuite in tests/integration/
# Exit 0 = allow, exit 2 = deny

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 1; }
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""')

if [[ "$FILE_PATH" == *tests/integration/* ]] && echo "$CONTENT" | grep -q "extends GdUnitTestSuite"; then
  echo "BLOCKED: GdUnitTestSuite not allowed in tests/integration/ (use SceneConfig instead)" >&2
  exit 2
fi
exit 0
```

## Debugging Checklist (in order)

When a hook doesn't fire in opencode:

1. **Stdin pattern correct?** Using `$(cat)` once + `.tool_input.*` paths?
2. **Settings file location correct?** `.claude/settings.json` (not `.local.json`)?
3. **OMO config enabled?** `"claude_code": { "hooks": true }` present?
4. **Restarted opencode after settings change?** OMO caches at startup.
5. **Test standalone first?** `echo '{"tool_name":"Write",...}' | bash .claude/hooks/script.sh`
6. **JSON valid?** `python3 -c "import json; json.load(open('.claude/settings.json'))"`
7. **PostToolUse specifically?** Try as PreToolUse first to isolate bridge vs event issue

## Complete Working Example: Godot Auto-UID PostToolUse

Hook script (`.claude/hooks/godot-auto-uid.sh`):

```bash
#!/usr/bin/env bash
# PostToolUse: Auto-generate .uid for new .gd files via godot-import.mjs

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not installed" >&2; exit 0; }

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[[ "$FILE_PATH" != *.gd ]] && exit 0

GODOT_IMPORT="/path/to/gol-tools/ai-debug/lib/godot-import.mjs"
GOL_PROJECT="/path/to/gol-project"

[[ ! -f "$GODOT_IMPORT" ]] && exit 0

node "$GODOT_IMPORT" ensure "$GOL_PROJECT" --force 2>&1 | while IFS= read -r line; do
  echo "[godot-import] $line" >&2
done

exit 0
```

Settings registration:

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write",
      "hooks": [{ "type": "command", "command": ".claude/hooks/godot-auto-uid.sh" }]
    }]
  }
}
```

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `$(jq < stdin)` twice | Second always empty | Use `INPUT=$(cat)` once |
| `.input.file_path` | jq returns null/empty | Use `.tool_input.file_path` |
| `$CLAUDE_FILE_PATH` env var | Pattern never matches | Parse from stdin JSON instead |
| Inline `bash -c '...'` command | Escaping hell, untestable | Extract to `.sh` file |
| `2>/dev/null` everywhere | Silent failures impossible to debug | Log to `>&2`, remove suppressions during dev |
| Editing settings without restarting | Old config still active | Restart opencode after every settings change |
| Using `.local.json` for project hooks | OMO may not read it | Use `settings.json` for project-level |
