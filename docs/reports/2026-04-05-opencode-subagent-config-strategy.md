# Report: OpenCode / OMO Subagent Configuration Strategy

Date: 2026-04-05
Scope: Cross-client compatible project-scoped subagent definitions (OpenCode + Claude Code)

## User Request

> "oh my opencode recommand how to add subagents? using categories or opencode's subagent config, or inherit claude"

> "the omo support compatibility of claude code's mechanism, so it may support the claude's defined subagent profiles. also I hope to compatible cross-client to define my own subagent at project scope, include model settings, custom prompt, or tools permissions control."

## Goal

Design a cross-client compatible strategy for defining project-scoped custom subagents that work in both **Claude Code** and **OpenCode+OMO**, with full control over model assignment, custom prompts, and tool permissions.

---

## Findings

### 1. Three Configuration Layers Exist in Current Setup

| Layer | Location | What It Controls | Read By |
|---|---|---|---|
| **OMO `agents`** | `~/.config/opencode/oh-my-opencode.json` → `agents{}` | Model override only (per agent name) | OMO plugin |
| **OMO `categories`** | Same file → `categories{}` | Domain-based model routing | OMO plugin |
| **OpenCode native `agent`** | `opencode.json` → `agent{}` or `.opencode/agents/*.md` | Full agent schema: model, prompt, permissions, mode, temperature, steps, color, etc. | OpenCode core |

### 2. OMO v3.14.0 Has Built-In Claude Code Agent Compatibility ✅

**Source verified**: OMO bundled source (`oh-my-opencode@3.14.0`, 4.2MB `dist/index.js`)

OMO contains a dedicated **`claude-code-agent-loader`** module that:

- **Scans `~/.claude/agents/*.md`** (user-level) via `loadUserAgents()` — line 136057
- **Scans `<project>/.claude/agents/*.md`** (project-level) via `loadProjectAgents()` — line 136066
- Parses YAML frontmatter for: `name`, `description`, `model`, `mode`, `tools`
- Auto-maps Claude model aliases (`sonnet` → `anthropic/claude-sonnet-4-6`, `opus`, `haiku`)
- Body text after `---` becomes the agent's `prompt`
- Defaults `mode` to `"subagent"` if unspecified

### 3. OMO Also Loads Claude Code Plugins (PR #240, merged Dec 2025)

- Reads from `~/.claude/plugins/installed_plugins.json`
- Loads plugin components: commands, agents, skills, MCP servers
- Namespaces them as `plugin-name:component`
- Supports `${CLAUDE_PLUGIN_ROOT}` variable expansion
- Toggle via `claude_code.plugins` config option (default: `true`)

### 4. Agent Merge Priority Order (from OMO source)

```
1. Builtin agents     → sisyphus, oracle, metis, momus, prometheus, atlas, hephaestus... (highest)
2. Config agents      → oh-my-opencode.json → agents{}
3. User agents        → ~/.claude/agents/*.md
4. Project agents     → <project>/.claude/agents/*.md
5. Plugin agents      → From installed CC plugins (namespaced)
```

Custom agents colliding with protected builtin names are filtered out.

### 5. Project-Level OMO Config Is Supported

```
~/.config/opencode/oh-my-opencode.json    ← User level (default)
.opencode/oh-my-opencode.jsonc            ← Project level (HIGHEST priority)
```

Merge behavior:
- Object fields → deep merge (e.g., `agents`, `categories`)
- Array fields → set union
- Primitives → project overrides user

Supports JSONC (comments + trailing commas).

### 6. Feature Matrix: What Each Format Supports

| Feature | `.claude/agents/*.md` | `.opencode/agents/*.md` | OMO `oh-my-opencode.json` |
|---|---|---|---|
| model | ✅ (alias or provider/model) | ✅ | ✅ (+ category, fallback_models) |
| prompt (body text) | ✅ | ✅ ({file:..}) | ✅ (prompt / prompt_append with file:// URI) |
| permission | ✅ (tools allow/deny) | ✅ (ask/allow/deny + glob patterns) | ✅ (ask/allow/deny + glob + per-command bash) |
| temperature | ❌ | ✅ | ✅ |
| mode (primary/subagent/all) | ✅ | ✅ | ✅ (built-in per agent) |
| steps / maxIterations | ✅ | ✅ | ❌ |
| color | ❌ | ✅ | ✅ |
| hidden | ❌ | ✅ | ❌ |
| variant (thinking budget) | ❌ | ❌ | ✅ (max/xhigh/high/medium/low) |
| skills injection | ❌ | ❌ | ✅ |
| ultrawork override | ❌ | ❌ | ✅ |
| thinking budget tokens | ❌ | ✅ via `additional` | ✅ explicit |
| reasoningEffort | ❌ | ✅ via `additional` | ✅ |
| toggle on/off | ❌ | ❌ | ✅ (disable) |

### 7. Recommended Architecture: Dual-Layer Definition

```
gol/
├── .claude/
│   └── agents/
│       ├── oracle.md           # ← Base definition: BOTH CC & OMO read this
│       ├── explore.md
│       └── code-reviewer.md    # (add more as needed)
├── .opencode/
│   └── oh-my-opencode.jsonc    # ← OMO enhancement layer: variant, skills,
                                 #    fine-grained permissions, thinking budget
```

**How it works**: `.claude/agents/*.md` provides shared identity + prompt (read by both clients). `.opencode/oh-my-opencode.jsonc` adds OMO-specific runtime tuning on top.

#### Example: `.claude/agents/oracle.md`

```markdown
---
name: oracle
description: Expert architect for read-only consultation on complex systems
model: codebuddy/glm-5v-turbo-ioa
mode: subagent
tools: read,bash,grep,glob,webfetch
---

You are Oracle — a read-only high-IQ consultant for architecture decisions.
[Full prompt body here...]
```

#### Example: `.opencode/oh-my-opencode.jsonc`

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json",

  "agents": {
    "oracle": {
      "variant": "high",
      "temperature": 0.05,
      "thinking": { "type": "enabled", "budgetTokens": 100000 },
      "permission": {
        "edit": "deny",
        "write": "deny",
        "bash": { "git log*": "allow", "grep *": "allow", "*": "ask" },
        "task": "deny"
      },
      "prompt_append": "Always respond in English. Use tables for comparisons."
    }
  },

  "claude_code": {
    "agents": true
  }
}
```

### 8. Current System State

- No `.claude/agents/` directory exists anywhere (global or project)
- No `.opencode/` directory exists at project root
- All current agent config is in global `~/.config/opencode/oh-my-opencode.json` (14 named agents + 8 categories)
- Default model: `kimi-for-coding/k2p5` (via CodeBuddy provider)
- OMO version: 3.14.0
- Plugin SDK: @opencode-ai/plugin@1.3.13

---

## References

| Source | URL |
|---|---|
| OpenCode Agents Documentation | https://opencode.ai/docs/agents/ |
| OMO Configuration Overview | https://mintlify.com/code-yeongyu/oh-my-opencode/configuration/overview |
| OMO Agents Documentation | https://mintlify.com/code-yeongyu/oh-my-opencode/configuration/agents |
| OMO Claude Code Plugin Support PR | https://github.com/code-yeongyu/oh-my-openagent/pull/240 |
| OMO Package (npm) | https://www.npmjs.com/package/oh-my-opencode |
| OMO Repo | https://github.com/code-yeongyu/oh-my-openagent |
| joelhooks opencode-config (324⭐ reference) | https://github.com/joelhooks/opencode-config |

## Next Steps

1. Create `.claude/agents/` directory at project root with initial agent definitions
2. Create `.opencode/oh-my-opencode.jsonc` for project-scoped OMO enhancements
3. Test agent loading in both clients (if available)
4. Migrate existing OMO global agent configs to use the dual-layer pattern where appropriate
