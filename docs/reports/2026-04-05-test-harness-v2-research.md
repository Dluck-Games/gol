# Test Harness v2 — R1 & R2 Research Report

Date: 2026-04-05
Source Plan: `docs/superpowers/plans/2026-04-05-test-harness-v2.md`
Status: Complete

## Scope

Research two pending items from the Test Harness v2 plan:
- **R1**: OMO hook/rules compatibility — Can hooks enforce rules across both Claude Code and OpenCode+OMO?
- **R2**: OMO tool name compatibility — Does OMO translate Claude Code tool names in agent definitions?

---

## R1: OMO Hook/Rules Compatibility

### Question

> Does OMO respect Claude Code's hook configuration (PreToolUse/PostToolUse in settings.json) and rules? Hook enforcement for hard rules (e.g., block `extends GdUnitTestSuite` in `tests/integration/`) must work in both clients.

### Answer: Partially Compatible — Shell-Command Hooks ✅, Hookify Rules ❌

### 1.1 OMO's `claude-code-hooks` Bridge

OMO (oh-my-openagent, formerly oh-my-opencode) includes a dedicated **`claude-code-hooks`** module that reads Claude Code's `settings.json` and executes those same hooks inside OpenCode. This is a full protocol bridge, not a partial shim.

**Evidence** — Hook factory ([source](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/hooks/claude-code-hooks/claude-code-hooks-hook.ts#L13-L27)):

```typescript
export function createClaudeCodeHooksHook(ctx, config = {}, contextCollector?) {
  return {
    "experimental.session.compacting": createPreCompactHandler(ctx, config),
    "chat.message": createChatMessageHandler(ctx, config, contextCollector),
    "tool.execute.before": createToolExecuteBeforeHandler(ctx, config),   // ← PreToolUse
    "tool.execute.after": createToolExecuteAfterHandler(ctx, config),      // ← PostToolUse
    event: createSessionEventHandler(ctx, config, contextCollector),
  }
}
```

**Evidence** — Config loader reads all standard CC settings paths ([source](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/hooks/claude-code-hooks/config.ts#L55-69)):

```typescript
export function getClaudeSettingsPaths(customPath?: string): string[] {
  return [
    join(claudeConfigDir, "settings.json"),           // user-level
    join(process.cwd(), ".claude", "settings.json"),   // project-level
    join(process.cwd(), ".claude", "settings.local.json"),
  ]
}
```

### 1.2 Event Mapping

| Claude Code Event | OMO Mapped Event | Status |
|-------------------|------------------|--------|
| `PreToolUse` | `tool.execute.before` | Fully implemented |
| `PostToolUse` | `tool.execute.after` | Fully implemented |
| `Stop` | `event` + re-activation via `injectPrompt` | Fully implemented |
| `UserPromptSubmit` | `chat.message` | Fully implemented |
| `PreCompact` | `experimental.session.compacting` | Fully implemented |

### 1.3 PreToolUse Deny Protocol

The exit code protocol matches Claude Code exactly:

**Evidence** ([source](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/hooks/claude-code-hooks/handlers/tool-execute-before-handler.ts#L71-87)):

```typescript
const result = await executePreToolUseHooks(preCtx, claudeConfig, extendedConfig)
if (result.decision === "deny") {
  ctx.client.tui.showToast({
    body: { title: "PreToolUse Hook Executed",
      message: `[BLOCKED] ${result.toolName}...`,
      variant: "error" as const,
    },
  })
  throw new Error(result.reason ?? "Hook blocked the operation")
}
```

Exit codes: **0=allow, 1=ask/prompt, 2=block(deny)**. Identical to CC.

### 1.4 What Works Cross-Platform

| Mechanism | Claude Code | OpenCode + OMO | Verdict |
|-----------|-------------|----------------|---------|
| Shell-command PreToolUse hooks (`settings.json`) | Native | ✅ Bridged by `claude-code-hooks` | **Cross-platform** |
| Shell-command PostToolUse hooks | Native | ✅ Bridged | **Cross-platform** |
| HTTP hooks | Native | ✅ Supported | **Cross-platform** |
| Stop hooks with re-activation | Native | ✅ `injectPrompt` mechanism | **Cross-platform** |
| `.claude/rules/` context injection | Native | ✅ Via `rules-injector` hook | **Cross-platform** (inject only) |
| OMO agent permissions (`permission.edit: deny`) | N/A | Native | **OpenCode-only** |

### 1.5 What Does NOT Work Cross-Platform

| Mechanism | Claude Code | OpenCode + OMO | Verdict |
|-----------|-------------|----------------|---------|
| **Hookify declarative rules** (`.claude/hookify.*.md`) | Native plugin | ❌ **Not bridged** | **Claude Code only** |

### 1.6 Current Hookify Rules Inventory

The project has **5 active hookify rules**, all using `action: warn` (not block):

| Rule File | Event | Trigger | Action |
|-----------|-------|---------|--------|
| `hookify.block-gdunit-in-integration.local.md` | file | `extends GdUnitTestSuite` in `tests/integration/` | warn |
| `hookify.block-sceneconfig-in-unit.local.md` | file | `extends SceneConfig` in `tests/unit/` | warn |
| `hookify.check-integration-test-completeness.local.md` | stop | Always fires | warn (checklist) |
| `hookify.warn-manual-entity-in-integration.local.md` | file | `Entity.new()` in integration tests | warn |
| `hookify.warn-null-systems-in-integration.local.md` | file | `systems()` returning null | warn |

**Critical observation**: All 5 rules are advisory only. Even in Claude Code, they can be ignored by the agent. None use `action: block`.

### 1.7 Existing settings.json Hooks

One shell-command hook exists at user level:

**Evidence** (`~/.claude/settings.json`):
```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "/Users/dluckdu/.claude/hooks/rtk-rewrite.sh"
      }]
    }]
  }
}
```

This RTK rewrite hook already works cross-platform — it's a shell command that OMO's bridge executes identically. No project-level `settings.json` or `settings.local.json` exists under `.claude/`.

### 1.8 Enabling the Bridge

In OMO config, ensure:
```jsonc
{
  "claude_code": { "hooks": true }  // enables claude-code-hooks bridge
}
```

The GOL project's current config has `"claude_code": { "agents": true }` but does **not** explicitly set `"hooks": true`. The default behavior when `claude_code` is enabled needs verification — if hooks default to `false`, they must be explicitly enabled.

**Known bug**: Issue [#1707](https://github.com/code-yeongyu/oh-my-openagent/issues/1707) reported hooks not firing; fixed in PR [#1790](https://github.com/code-yeongyu/oh-my-openagent/pull/1790). Ensure latest OMO version.

### 1.9 Recommendation for v2

**For cross-platform hard rule enforcement, convert critical hookify rules into shell-command PreToolUse hooks in `settings.json`:**

| Current Hookify Rule | Replacement Strategy |
|---------------------|---------------------|
| Block `GdUnitTestSuite` in `tests/integration/` | Shell script: check filepath + grep for pattern → exit 2 on match |
| Block `SceneConfig` in `tests/unit/` | Same approach, inverted paths |
| Warn `Entity.new()` in integration | Keep as agent `prompt_append` text (advisory, not blocking) |
| Warn null `systems()` in integration | Keep as agent `prompt_append` text (advisory) |
| Completeness checklist on stop | Convert to Stop hook shell script → exit 2 if checklist fails |

**OMO agent permissions provide complementary enforcement** for OpenCode-specific constraints:
- `test-runner` already has `"edit": "deny", "write": "deny"` — this is hard enforcement
- Add similar restrictions for writer agents if needed

---

## R2: OMO Tool Name Compatibility

### Question

> Does OMO translate Claude Code tool names (Read, Write, Glob, Grep, Bash) in agent body text? Agent definitions reference tools by name in workflow descriptions. If OMO doesn't map these, agents may behave differently across platforms.

### Answer: No Translation Needed — Names Are Identical ✅

### 2.1 Tool Name Identity

Claude Code and OpenCode use the **exact same tool names** (case difference only):

| Claude Code Name | OpenCode Permission Key | Match? |
|-----------------|----------------------|--------|
| `Read` | `read` | Same (case diff) |
| `Write` | `write` | Same (case diff) |
| `Edit` | `edit` | Same (case diff) |
| `Glob` | `glob` | Same (case diff) |
| `Grep` | `grep` | Same (case diff) |
| `Bash` | `bash` | Same (case diff) |

Full OpenCode permission key list (from [permissions docs](https://opencode.ai/docs/permissions/#available-permissions)):
`read`, `edit`, `glob`, `grep`, `list`, `bash`, `task`, `skill`, `lsp`, `question`, `webfetch`, `websearch`, `codesearch`, `external_directory`, `doom_loop`

### 2.2 How OMO Handles CC Agent Loading

OMO's `claude-code-agent-loader` parses CC frontmatter and converts the `tools:` field:

**Evidence** ([source](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/features/claude-code-agent-loader/loader.ts#L9-L20)):

```typescript
function parseToolsConfig(toolsStr?: string): Record<string, boolean> | undefined {
  if (!toolsStr) return undefined
  const tools = toolsStr.split(",").map((t) => t.trim()).filter(Boolean)
  const result: Record<string, boolean> = {}
  for (const tool of tools) {
    result[tool.toLowerCase()] = true   // ← lowercases each name
  }
  return result
}
```

Pipeline:
```
CC frontmatter:  tools: Read, Write, Glob, Grep, Bash
       ↓ split by comma
       ["Read", "Write", "Glob", "Grep", "Bash"]
       ↓ lowercase each
       { read: true, write: true, glob: true, grep: true, bash: true }
       ↓ migrateToolsToPermission()
       { read: "allow", write: "allow", glob: "allow", grep: "allow", bash: "allow" }
```

**Evidence** — Permission migration ([source](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/shared/permission-compat.ts#L46-55)):

```typescript
export function migrateToolsToPermission(
  tools: Record<string, boolean>
): Record<string, PermissionValue> {
  return Object.fromEntries(
    Object.entries(tools).map(([key, value]) => [
      key, value ? ("allow" as const) : ("deny" as const)
    ])
  )
}
```

### 2.3 Agent Body Text References

When an agent body says "Use Read to examine files" or "Use Bash to run commands" — **this works identically in both platforms** because:

1. Both platforms present tools to the LLM with their actual names (Read, Bash, etc.)
2. The LLM invokes tools through the tool-calling interface, not by parsing prompt text
3. OpenCode's built-in tool list matches CC's exactly

**Evidence** ([OpenCode tools docs](https://opencode.ai/docs/tools/#built-in)): Lists built-in tools as `bash`, `edit`, `write`, `read`, `grep`, `glob`, `list`, `lsp`, `apply_patch`, `skill`, `todowrite`, `webfetch`, `websearch`, `question`.

### 2.4 ⚠️ Semantic Gap: Allowlist Behavior

While tool names are identical, the **semantics of the `tools:` field differ** between platforms:

| Aspect | Claude Code Behavior | OpenCode/OMO Behavior |
|--------|--------------------|----------------------|
| `tools: Read, Write` | **Allowlist**: ONLY these tools available, everything else denied | **Individual grants**: These allowed, **unlisted tools default to "allow"** |
| Unlisted tools (e.g., `webfetch`) | **Denied** (not in allowlist) | **Allowed** (permissive default) |
| `tools:` omitted | All tools available | All tools available (same) |

**Impact**: A CC agent with `tools: Read, Bash, Glob, Grep` is **more restrictive in CC** than in OMO. In OMO, unlisted tools like `edit`, `write`, `webfetch` remain allowed unless explicitly denied.

**Mitigation**: The OMO config override (`oh-my-opencode.jsonc`) merges with loaded CC agent config and can add explicit `deny` rules. The existing `test-runner` already does this:

```jsonc
"test-runner": {
  "permission": {
    "edit": "deny",      // ← explicit denial compensates for gap
    "write": "deny",     // ← explicit denial compensates for gap
    "task": "deny"
  }
}
```

### 2.5 The `tools:` Field Is Deprecated in OpenCode

From [OpenCode docs](https://opencode.ai/docs/agents/#tools-deprecated):

> `tools` is **deprecated**. Prefer the agent's [`permission`](#permissions) field for new configs.

This does NOT affect compatibility — OMO's loader auto-migrates `tools` → `permission`. But it means future OpenCode versions may emit deprecation warnings for the legacy format. Not urgent for v2.

### 2.6 Verification: Existing Agents Work on Both Platforms

The project's current v1 agents demonstrate this works today:

| Agent | CC Definition | OMO Config Override | Result |
|-------|--------------|-------------------|--------|
| `test-writer` | `tools: Read, Write, Glob, Grep, Bash` | `permission.edit: "allow", .write: "allow"` | Both platforms functional |
| `test-runner` | `tools: Read, Bash, Glob, Grep` | `permission.edit: "deny", .write: "deny"` | Both platforms functional |

---

## Cross-Platform Compatibility Summary Matrix

| Feature | Claude Code | OpenCode + OMO | v2 Strategy |
|---------|-------------|----------------|-------------|
| Agent definitions (`.claude/agents/*.md`) | Native | Loaded via `claude-code-agent-loader` | Single shared definition |
| PascalCase `tools:` in frontmatter | Native (allowlist) | Lowercased → individual permissions | Works; add OMO deny overrides for strictness |
| Agent body tool name references | Works | Works (same names) | No changes needed |
| `model:` field in frontmatter | Supported | Mapped via `model alias table` | **Omit per D5** — platform-specific selection |
| Shell-command hooks (`settings.json`) | Native | ✅ Bridged by `claude-code-hooks` | Use for hard rule enforcement |
| Hookify declarative rules (`.md`) | Native (plugin) | ❌ Not bridged | **Migrate to shell hooks or agent prompts** |
| `.claude/rules/` context injection | Native | ✅ Via `rules-injector` | Informational only, works both sides |
| OMO agent permissions | N/A | Native | Use for OC-specific restrictions |
| Stop hook with re-activation | Native | ✅ `injectPrompt` | Works for completeness checks |

## Recommendations for Implementation

### Immediate (v2 Implementation)

1. **Agent definitions**: Single `.claude/agents/*.md` files, no `model` field, PascalCase `tools:` — confirmed compatible.
2. **OMO config** (`oh-my-opencode.jsonc`): Add per-agent `permission.deny` for any tool that must be restricted beyond what CC's allowlist semantics provide. Especially important for `test-runner` (read-only) and `test-writer-unit` (no ECS).
3. **Enable hooks bridge**: Ensure `claude_code.hooks: true` (or verify default-on behavior) in OMO config.
4. **Do NOT invest further in hookify rules** for cross-platform goals — they are CC-only.

### Deferred (Post-v2)

5. **Convert critical hookify rules to shell-command hooks**: The 2 block-rules (wrong base class in wrong tier) should become `PreToolUse` shell scripts in `settings.json`. This gives hard enforcement on both platforms.
6. **Migrate advisory rules to agent prompts**: The 3 warn-rules (Entity.new, null systems, completeness) become `prompt_append` text on the relevant agents. Advisory enforcement doesn't need hooks.

## Evidence Index

| # | Source | Reference |
|---|--------|-----------|
| 1 | OMO `claude-code-hooks` factory | [GitHub source L13-27](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/hooks/claude-code-hooks/claude-code-hooks-hook.ts#L13-L27) |
| 2 | OMO settings path loader | [GitHub config.ts L55-69](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/hooks/claude-code-hooks/config.ts#L55-69) |
| 3 | OMO PreToolUse deny handler | [GitHub tool-execute-before-handler.ts L71-87](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/hooks/claude-code-hooks/handlers/tool-execute-before-handler.ts#L71-87) |
| 4 | OMO tool name parser (lowercases) | [GitHub loader.ts L9-20](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/features/claude-code-agent-loader/loader.ts#L9-L20) |
| 5 | OMO tools→permission migration | [GitHub permission-compat.ts L46-55](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/shared/permission-compat.ts#L46-55) |
| 6 | OMO rules-injector constants | [GitHub constants.ts L14-29](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/hooks/rules-injector/constants.ts#L14-29) |
| 7 | OMO tool-guard skip control | [GitHub create-tool-guard-hooks.ts L93-96](https://github.com/code-yeongyu/oh-my-openagent/blob/97ccbf1da379d9330ced0815ff52dd5187c77d32/src/plugin/hooks/create-tool-guard-hooks.ts#L93-96) |
| 8 | OMO architecture documentation | [Mintlify - System Architecture](https://www.mintlify.com/code-yeongyu/oh-my-opencode/concepts/architecture) |
| 9 | OpenCode permissions docs | [Permissions - Available Permissions](https://opencode.ai/docs/permissions/#available-permissions) |
| 10 | OpenCode agents docs (tools deprecated) | [Agents - Tools Deprecated](https://opencode.ai/docs/agents/#tools-deprecated) |
| 11 | OpenCode tools docs (built-in) | [Tools - Built-in](https://opencode.ai/docs/tools/#built-in) |
| 12 | Project OMO config | `gol/.opencode/oh-my-opencode.jsonc` |
| 13 | User-level CC settings | `~/.claude/settings.json` (RTK hook) |
| 14 | RTK hook script | `~/.claude/hooks/rtk-rewrite.sh` |
| 15 | RTK OpenCode plugin | `~/.config/opencode/plugins/rtk.ts` |
| 16 | OMO bug #1707 / fix PR #1790 | [Issue #1707](https://github.com/code-yeongyu/oh-my-openagent/issues/1707), [PR #1790](https://github.com/code-yeongyu/oh-my-openagent/pull/1790) |
| 17 | OpenCode CC hooks feature request | [Issue #12472](https://github.com/anomalyco/opencode/issues/12472) |
| 18 | Hookify rule: block-gdunit | `gol/.claude/hookify.block-gdunit-in-integration.local.md` |
| 19 | Hookify rule: block-sceneconfig | `gol/.claude/hookify.block-sceneconfig-in-unit.local.md` |
| 20 | Hookify rule: completeness | `gol/.claude/hookify.check-integration-test-completeness.local.md` |
| 21 | Hookify rule: warn-entity | `gol/.claude/hookify.warn-manual-entity-in-integration.local.md` |
| 22 | Hookify rule: warn-null-systems | `gol/.claude/hookify.warn-null-systems-in-integration.local.md` |
| 23 | OMO repo HEAD SHA | `97ccbf1da379d9330ced0815ff52dd5187c77d32` |
