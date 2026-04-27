---
name: gol-fix-issue
description: "(project - Skill) Fix a GitHub issue and submit a PR for god-of-lego. Use this skill whenever the user provides an issue number and wants to fix it — triggers: 'fix issue', '修 issue', '修个 bug', 'fix #N', 'gol fix', 'issue N', plus ULW keyword activation. Reads the issue, creates a worktree, explores code, implements the fix, runs tests, submits PR, and cleans up. Full autonomous workflow from issue to PR."
---

# gol-fix-issue

Autonomous issue-fixing workflow for God of Lego. Given an issue number, go from reading the issue to a submitted PR — no intermediate artifacts, no handoff docs, no workspace pollution.

## What This Skill Does

Read a GitHub issue, fix it in an isolated worktree, verify with tests, submit a PR that closes the issue, and clean up. The entire lifecycle runs without touching the main working copy.

## Prerequisites

- Issue number must be provided by the user (e.g., "fix #188", "修 issue 42")
- `gh` CLI must be authenticated for `Dluck-Games/god-of-lego`
- `gol-project/` submodule must be initialized and on `main`

## Phase Plan

```
1. Read Issue    → gh issue view
2. Setup         → worktree + branch from main
3. Explore       → understand codebase context for the fix
4. Implement     → apply the fix
5. Test          → verify via gol-test-runner
6. Submit PR     → push + gh pr create (Chinese title, Closes #N)
7. Cleanup       → remove worktree
```

After Phase 1 (Read Issue), proceed autonomously. Do not ask further questions unless the issue is ambiguous to the point of being unimplementable.

## Phase 1 — Read Issue

```bash
gh issue view <N> -R Dluck-Games/god-of-lego
```

Extract from the issue:

- **Type**: bug fix, feature implementation, config adjustment, refactoring — determines commit prefix
- **Scope**: which subsystem (gameplay, ECS, UI, service, PCG)
- **Specifics**: file paths, class names, method names mentioned in the issue body
- **Labels**: reuse for PR labels when applicable

If the issue references gol-tools (not gol-project), stop and ask the user — this skill only handles `gol-project` issues.

## Phase 2 — Setup

### Create Worktree

Run from inside `gol-project/`:

```bash
cd gol-project/
git worktree prune
git worktree add -b fix/issue-<N> \
  /Users/dluck/Documents/GitHub/gol/.worktrees/manual/issue-<N> \
  origin/main
```

All subsequent work uses the worktree path as the project root:

```
/Users/dluck/Documents/GitHub/gol/.worktrees/manual/issue-<N>
```

### Confirm State

```bash
# Inside the worktree
git branch --show-current  # Should be fix/issue-<N>
```

## Phase 3 — Explore

Read `references/explore-prompt.md`. Dispatch an explore subagent with the issue context.

Template for the explore dispatch:

```text
<prompt-template>
{contents of references/explore-prompt.md}
</prompt-template>

<task>
Issue #{N}: {issue title}
Issue body summary: {key points from issue}
Issue type: {bug/feature/adjustment/refactor}
Working directory: /Users/dluck/Documents/GitHub/gol/.worktrees/manual/issue-<N>
Parent repo: /Users/dluck/Documents/GitHub/gol
</task>
```

Require a structured explore report: root cause or implementation target, relevant code files, existing patterns to follow, files to modify/create, risks.

## Phase 4 — Implement

Read `references/implement-prompt.md`. Dispatch an implementation subagent with the explore report.

Template for the implement dispatch:

```text
<prompt-template>
{contents of references/implement-prompt.md}
</prompt-template>

<task>
Issue #{N}: {issue title}
Fix summary: {what needs to change, based on issue + explore report}
Working directory: /Users/dluck/Documents/GitHub/gol/.worktrees/manual/issue-<N>

<explore-report>
{full structured explore report}
</explore-report>
</task>
```

Require an implementation report: changed files, behavior implemented, patterns followed, validation performed, risks.

### Architecture Rules

- **ECS**: components are pure data (`scripts/components/c_*.gd`), systems contain logic (`scripts/systems/s_*.gd`)
- **MVVM**: UI changes flow through ViewModel + View + scene
- **Service access**: through `ServiceContext.*`
- **Never touch** `addons/gecs/` — that is the ECS addon, not game code
- Match naming, file placement, typing, and class structure from nearby existing files
- Keep changes minimal — fix the issue, do not refactor surrounding code

## Phase 5 — Test

Delegate through existing GOL test skills. Do not write or run tests directly.

1. Load `gol-test-writer` skill
2. Use test routing matrix to choose unit or integration:

| Question | Yes → | No → |
|---|---|---|
| Needs `World` or `ECS.world`? | Integration | Unit |
| Tests multiple systems together? | Integration | Unit |
| Uses `GOL.setup()` / services? | Integration | Unit |

3. Dispatch the writer skill for test coverage of the fix
4. Load `gol-test-runner` skill
5. Dispatch the runner skill to execute tests
6. On FAIL: fix the implementation (not the test), retry up to 2 times
7. After 2 retries still failing: report the failure with full context and stop

## Phase 6 — Submit PR

### Commit

Load `git-master` skill before any git operation.

Inside the worktree:

```bash
# Stage only relevant changes
git add <changed files>

# Commit with semantic style, Chinese description
# Prefix from issue type:
#   bug → fix(module): 描述
#   feature → feat(module): 描述
#   adjustment → adjust(module): 描述
#   refactor → refactor(module): 描述
git commit -m "fix(module): 一句话描述修复内容"
```

### Push

```bash
git push -u origin fix/issue-<N>
```

### Create PR

```bash
gh pr create -R Dluck-Games/god-of-lego \
  --base main \
  --head fix/issue-<N> \
  --title "{类型}：{简短描述}" \
  --body "$(cat <<'EOF'
## 修复内容
{一句话说明修了什么}

## 改动
- `{文件路径}`: {改动说明}
- ...

## 测试
- {测试方式与结果}

Closes #<N>
EOF
)"
```

PR title format follows `gol-issue` conventions:

| Issue type | Title prefix | Example |
|---|---|---|
| Bug | `修复：` | `修复：箱子会阻挡并消耗子弹` |
| Feature | `开发：` | `开发：实现 spawn 控制台命令` |
| Adjustment | `调整：` | `调整：快速小僵尸体型缩小` |
| Refactor | `重构：` | `重构：提取 buff 应用逻辑为独立系统` |

Rules:
- Type prefix + full-width colon `：` + space + description
- Description under 20 characters, say what was done
- Keep technical terms in English (spawn, buff, collision, etc.)
- Body ends with `Closes #<N>` on its own line

## Phase 7 — Cleanup

After PR is submitted successfully:

```bash
# Return to gol-project main working copy
cd /Users/dluck/Documents/GitHub/gol/gol-project/

# Remove the worktree
git worktree remove /Users/dluck/Documents/GitHub/gol/.worktrees/manual/issue-<N>

# Prune any stale worktree references
git worktree prune
```

If cleanup fails (e.g., worktree has uncommitted changes), force-remove only after confirming the PR was submitted:

```bash
git worktree remove --force /Users/dluck/Documents/GitHub/gol/.worktrees/manual/issue-<N>
```

Report the PR URL to the user.

## What This Skill Does NOT Do

- Create handoff docs, iteration notes, or decision records
- Create files in `docs/` (handoff, superpowers, reports — none)
- Create branches in the management repo (`gol/`)
- Create worktrees from the management repo
- Modify `addons/gecs/`
- Refactor code beyond what the issue requires
- Write or run tests directly (always delegate to `gol-test-writer` / `gol-test-runner`)
- Push the management repo submodule pointer (the PR merge handles that)
- Ask questions after reading the issue (proceed autonomously unless issue is genuinely ambiguous)

## Resources

- `references/explore-prompt.md` — Phase 3 research prompt template
- `references/implement-prompt.md` — Phase 4 implementation prompt template
- Reuse existing skills: `git-master`, `gol-test-writer`, `gol-test-runner`

## Validation Checklist

- [ ] Read issue via `gh issue view`
- [ ] Created worktree `fix/issue-<N>` from `origin/main` inside `gol-project/`
- [ ] All changes confined to the worktree — main working copy untouched
- [ ] Dispatched explore phase with reference prompt
- [ ] Dispatched implement phase with explore report
- [ ] Delegated testing through `gol-test-writer` and `gol-test-runner`
- [ ] Committed with semantic prefix matching issue type
- [ ] Pushed branch and created PR with Chinese title + `Closes #<N>`
- [ ] Cleaned up worktree after PR submission
- [ ] No handoff docs, no `docs/` files created
- [ ] No edits to `addons/gecs/`
