# create-omo-cc-compatible-agent

Use this skill when creating or editing Claude Code agent definitions (`.claude/agents/*.md`) that must load and run correctly in both Claude Code native and OpenCode+OMO (oh-my-openagent), configuring OMO agent permissions/model fallback for CC-loaded agents, debugging agents that work in one client but misbehave in the other, or writing platform-neutral agent definitions with tool permissions.

## Overview

Write `.claude/agents/*.md` files that Claude Code loads natively **and** OMO bridges via `claude-code-agent-loader`. Both platforms read the same frontmatter + body, but interpret `tools:` field differently, handle model selection separately, and have different permission semantics.

**Core principle**: Write the agent body as platform-neutral instructions. Put all platform-specific config (model, fallback chain, extra restrictions) in OMO's `oh-my-openagent.jsonc`, not in the `.md` file.

## When To Use

```
Need an agent?
├── Only ever runs in Claude Code? → Use any CC agent pattern
├── Must work in both CC and OMO? → Follow this skill
├── Needs model/fallback config? → .md omits model, OMO jsonc sets it
└── Needs strict permission control? → Set in OMO jsonc, NOT tools: allowlist
```

**Trigger symptoms**:
- Agent works in Claude Code but has wrong permissions in opencode
- Agent can't use certain tools (or uses too many) in opencode
- Model doesn't match expectations in opencode
- Fallback chain doesn't activate when primary model fails
- Agent body references tools by wrong name

## The Two-Layer Architecture

```
┌─────────────────────────────────┐  ┌──────────────────────────────┐
│  .claude/agents/<name>.md       │  │  .opencode/oh-my-openagent.jsonc │
│  (Shared by both platforms)     │  │  (OMO-only overrides)          │
│                                 │  │                               │
│  - name (frontmatter)           │  │  - model + fallback_models     │
│  - description                  │  │  - permission.* overrides      │
│  - tools: (CC allowlist)        │  │  - variant / temperature       │
│  - body instructions            │  │  - thinking budget             │
│  - domain knowledge (~150 lines)│  │  - claude_code bridge flags    │
└─────────────────────────────────┘  └──────────────────────────────┘
                   │                              │
                   ▼                              ▼
          ┌──────────────────────────────────────────┐
          │         OMO claude-code-agent-loader       │
          │  Parses .md frontmatter → merges with     │
          │  jsonc overrides → spawns agent           │
          └──────────────────────────────────────────┘
```

## Frontmatter Fields: Cross-Platform Reference

### Fields That Work Identically

| Field | Type | CC Behavior | OMO Behavior | Notes |
|-------|------|-------------|--------------|-------|
| `name` | string | Agent ID | Agent ID | Same identifier |
| `description` | string | Ignored by CC | Ignored by OMO | Metadata only |
| `tools` | string | **Allowlist**: only listed tools available | Lowercased → individual `allow` grants, unlisted default to `allow` | ⚠️ Semantic gap! |

### Fields OMO Ignores from .md (set in jsonc instead)

| Field | Where It Belongs | Why |
|-------|-----------------|-----|
| `model` | `oh-my-openagent.jsonc` | Platform-specific model routing |
| `fallback_models` | `oh-my-openagent.jsonc` | OMO-only feature |
| `variant` | `oh-my-openagent.jsonc` | OMO parameter control |
| `temperature` | `oh-my-openagent.jsonc` | OMO parameter control |
| `thinking.budgetTokens` | `oh-my-openagent.jsonc` | OMO thinking config |

## The `tools:` Semantic Gap (Critical)

This is the #2 source of cross-platform bugs after hook stdin issues:

| Aspect | Claude Code | OpenCode + OMO |
|--------|-------------|----------------|
| `tools: Read, Write, Bash` means | **Only** these 3 tools available | These 3 allowed, **everything else also allowed** |
| Unlisted tool (e.g., Edit) | **Denied** | **Allowed** (permissive default) |
| `tools:` omitted | All tools available | All tools available (same) |

### Mitigation Strategy

For restrictive agents that MUST be denied access to certain tools:

```jsonc
// oh-my-openagent.jsonc
{
  "agents": {
    "test-runner": {
      "model": "codebuddy/kimi-k2.5-ioa",
      "permission": {
        "edit": "deny",    // ← explicit deny compensates gap
        "write": "deny",   // ← explicit deny compensates gap
        "task": "deny"     // ← prevent subagent spawning
      }
    }
  }
}
```

**Rule**: If an agent's `tools:` field in .md is meant to restrict capabilities, ALWAYS add corresponding `"deny"` rules in OMO's `permission` block.

## Agent Template (.md)

```markdown
---
name: <kebab-case-name>
description: <What this agent does>. Self-contained expert.
tools: <comma-separated CC tool names>
---

You are **<PascalCaseName>** — a specialist for <domain>.

## Mission
- <Primary outcome>.
- <Quality bar>.

## Use This Agent When
- <Scenario 1>.
- <Scenario 2>.

Do **not** use this for <out-of-scope cases>.

## Domain Knowledge
<Embed critical patterns, APIs, schemas here. ~150 lines max.>

## Workflow
1. <Step 1>.
2. <Step 2>.
3. <Step 3>.
```

## OMO Config Template (jsonc)

```jsonc
{
  "agents": {
    "<agent-name-from-md>": {
      "model": "<primary-model>",
      "fallback_models": [
        "<fallback-1>",
        "<fallback-2>"
      ],
      "variant": "<high|medium|low>",
      "temperature": 0.05,
      "thinking": {
        "type": "enabled",
        "budgetTokens": 15000
      },
      "permission": {
        "edit": "<allow|deny>",
        "write": "<allow|deny>",
        "bash": {
          "<pattern-to-allow>": "allow",
          "*": "<ask|deny>"
        },
        "task": "<allow|deny>"
      }
    }
  },
  "claude_code": {
    "agents": true,
    "hooks": true
  }
}
```

### Model Fallback Chain Format

```jsonc
// ✅ CORRECT
{
  "model": "codebuddy/kimi-k2.5-ioa",        // string only
  "fallback_models": [                        // array of strings
    "codebuddy/minimax-m2.7-ioa",
    "kimi-for-coding/k2p5"
  ]
}

// ❌ WRONG — common mistakes
{ "models": ["..."] }       // NOT models (plural)
{ "model": ["..."] }        // NOT array for model
{ "model": "...", "fallback": "..." }  // NOT fallback singular
```

## Tool Name Compatibility

Tool names are **identical** between both platforms (case differs only):

| CC Name | OMO Permission Key | Match? |
|---------|-------------------|--------|
| `Read` | `read` | ✅ Same |
| `Write` | `write` | ✅ Same |
| `Edit` | `edit` | ✅ Same |
| `Bash` | `bash` | ✅ Same |
| `Glob` | `glob` | ✅ Same |
| `Grep` | `grep` | ✅ Same |
| `Task` | `task` | ✅ Same |

Agent body text can reference tools by either casing — LLM invokes them through the tool-calling interface, not by parsing prompt text.

## Agent Body Best Practices

### Embed Knowledge, Don't Reference Docs

- **DO**: Embed API signatures, component fields, system behaviors directly in the .md (~150 lines max)
- **DON'T**: Reference external docs (`"see SKILL.md for details"`) — causes stale-reference problem
- **WHY**: Skills get updated independently; agents with stale references produce wrong code

### Platform-Neutral Body Text

- Don't mention "Claude Code" or "opencode" in agent instructions
- Refer to tools by name without client assumptions
- Use `Read`/`Write`/`Edit`/`Bash`/`Glob`/`Grep` — both platforms understand them
- Keep workflow steps generic enough for either runtime

### Size Limit

Keep `.md` under ~200 lines. OMO's loader reads the full file into context. Larger agents:
- Burn context window budget
- Risk truncation
- Should split knowledge into referenced skills instead

## Complete Working Example: Test Writer Integration

File: `.claude/agents/test-writer-integration.md`

```markdown
---
name: test-writer-integration
description: Write SceneConfig integration tests for GOL Godot 4.6.
  Self-contained expert. Discovers system/recipe/component details from codebase.
tools: Read, Write, Glob, Grep, Bash
---

You are **TestWriterIntegration** — a specialist for complete, runnable SceneConfig integration tests in GOL.

## Mission
- Produce one finished `test_*.gd` file.
- Target real ECS behavior in a realized `GOLWorld`.
- Deliver code that compiles, runs headless, and uses recipe-spawned entities.

## SceneConfig API
Base class members defined in `scene_config.gd`:

| Member | Signature | Notes |
|---|---|---|
| `scene_name()` | `-> String` | Scene identifier |
| `systems()` | `-> Variant` | `null` or array of system paths |
| `entities()` | `-> Variant` | `null` or entity dict array |
| `test_run(world)` | `-> TestResult` | Execute scenario |

## Runtime Discovery Rules
Before writing, discover concrete details from code:
1. **Systems** → read `scripts/systems/AGENTS.md`, then needed `s_*.gd` files.
2. **Similar tests** → glob `tests/integration/**/*.gd`, read 1-2 nearby tests.
3. **Recipes** → glob `resources/recipes/*.tres`.
4. **Components** → read specific `c_*.gd` files used by the scenario.

Never guess recipe contents or component fields when the codebase confirms them.
```

OMO override in `.opencode/oh-my-openagent.jsonc`:

```jsonc
{
  "agents": {
    "test-writer-integration": {
      "model": "codebuddy/kimi-k2.5-ioa",
      "fallback_models": [
        "codebuddy/minimax-m2.7-ioa",
        "kimi-for-coding/k2p5"
      ],
      "variant": "high",
      "temperature": 0.05,
      "thinking": { "type": "enabled", "budgetTokens": 15000 },
      "permission": {
        "edit": "allow",
        "write": "allow",
        "bash": { "godot* *--headless*": "allow", "*": "ask" },
        "task": "deny"
      }
    }
  },
  "claude_code": { "agents": true, "hooks": true }
}
```

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| `model:` field in .md frontmatter | Ignored by OMO; model may differ | Remove from .md, set in jsonc only |
| `tools:` meant as deny-list | Unlisted tools still allowed in OMO | Add explicit `permission.deny` in jsonc |
| Agent body >300 lines | Context bloat, slow loading | Extract domain knowledge; reference via skill |
| Referencing external SKILL.md | Stale references after skill updates | Embed critical knowledge directly |
| Wrong config filename | Settings not loaded | It's `oh-my-openagent.jsonc` (not `oh-my-opencode.jsonc`) |
| Missing `claude_code.agents: true` | Agents don't load from .claude/agents/ | Enable bridge flag in jsonc |
| Array for `model` field | Model parse error | `model` is string only; use `fallback_models` for chain |

## Debugging Checklist

When an agent behaves differently in opencode vs Claude Code:

1. **Agent file found?** Check `.claude/agents/<name>.md` exists and parses valid YAML frontmatter
2. **Bridge enabled?** `claude_code.agents: true` in jsonc
3. **Model resolving?** Check jsonc `model` field matches a configured alias
4. **Permission gaps?** Compare `tools:` in .md vs `permission.*` in jsonc — missing denies?
5. **Agent name mismatch?** jsonc key must match `name:` from .md frontmatter exactly (kebab-case)
