---
name: gol-quick-feature-dev
description: "(project - Skill) Full feature development workflow for GOL. Use when implementing a new feature, gameplay change, system addition, or component modification from a short description. Handles exploration, implementation, testing, and commit/push. Triggers: 'implement feature', 'add feature', 'new feature', 'quick feature', 'feature dev', 'develop feature', '做功能', '加功能', '实现功能'"
---

# gol-quick-feature-dev

Coordinator skill for turning a short feature description into a full GOL delivery workflow.

## You Are the Coordinator

Act as the main agent. Never implement directly. Never run tests directly. Orchestrate the workflow, preserve repo boundaries, and keep all code changes inside `gol-project/` or its worktree.

Start by asking exactly one question:

```text
Confirm feature scope in one sentence, and state whether to use a worktree (`yes` or `no`).
```

After that answer, proceed autonomously.

## Decision Matrix

### Setup routing

| Condition | Action |
|---|---|
| User requested worktree | Create worktree from `gol-project/`, then work inside it |
| No worktree requested | Work directly in `gol-project/` |
| Current branch in `gol-project/` is `main` | Create feature branch before edits |
| Current branch is already a feature branch | Reuse it if it matches the task |

### Test routing

| Question | Yes → | No → |
|---|---|---|
| Needs `World` or `ECS.world`? | Integration | Unit |
| Tests multiple systems together? | Integration | Unit |
| Uses `GOL.setup()` / services? | Integration | Unit |

## Phase Plan

1. **Setup** — load `git-master`, decide branch/worktree mode, and prepare the working copy.
2. **Explore** — read `references/explore-prompt.md`, dispatch an explore subagent, and receive a report covering what to build and how to build it.
3. **Implement** — read `references/implement-prompt.md`, dispatch an implementation subagent with the explore report, and receive changed files plus notes.
4. **Test** — delegate test writing to `gol-test-writer`, then delegate execution to `gol-test-runner`; on FAIL, fix and retry up to 2 times.
5. **Commit + Push** — use `git-master`, commit in `gol-project/`, push the submodule branch, then update the parent repo pointer only when not using a worktree.
6. **Cleanup** — summarize work and optionally remove a temporary worktree after completion.

## Setup Protocol

Load `git-master` before any git operation. Never create branches in the management repo.

### In-repo mode

- Work inside `gol-project/`
- If branch is `main`, create `feat/<feature-name>` in `gol-project/`
- If branch is already feature-scoped, continue there

### Worktree mode

Run from inside `gol-project/` only. Prune first, then create the worktree with this exact pattern:

```bash
git worktree prune
git worktree add -b feat/<feature-name> \
  /Users/dluck/Documents/GitHub/gol/.worktrees/manual/<feature-name> \
  origin/main
```

Then switch all later work to the new worktree path.

## Dispatch Protocol

### Phase 1 — Explore

1. Read `references/explore-prompt.md`
2. Dispatch an explore subagent with this template:

```text
<prompt-template>
{contents of references/explore-prompt.md}
</prompt-template>

<task>
Feature request: {short user description}
Confirmed scope: {single-sentence scope}
Working directory: {current CWD}
Project directory: {gol-project/ or worktree path}
Parent repo: /Users/dluck/Documents/GitHub/gol
</task>
```

3. Require a structured report: goal, relevant notes/docs, relevant code, files to modify/create, patterns to follow, risks, and implementation plan.

### Phase 2 — Implement

1. Read `references/implement-prompt.md`
2. Dispatch an implementation subagent with this template:

```text
<prompt-template>
{contents of references/implement-prompt.md}
</prompt-template>

<task>
Feature request: {short user description}
Confirmed scope: {single-sentence scope}
Working directory: {current CWD}
Project directory: {gol-project/ or worktree path}

<explore-report>
{full structured explore report}
</explore-report>
</task>
```

3. Require a result report listing files changed, key behaviors implemented, follow-up risks, and anything still missing.

## Test Protocol

Delegate only. Do not invent new test prompts.

1. Load `gol-test-writer`
2. Use the test routing matrix to choose unit or integration
3. Dispatch the writer skill for missing coverage
4. Load `gol-test-runner`
5. Dispatch the runner skill for verification
6. If FAIL, fix implementation or test mismatch and retry up to 2 times
7. If still failing after 2 retries, escalate with the full failure report

Use playtest only when the feature needs live rendered verification.

## Commit + Push Protocol

Load `git-master` again before committing.

- Stage changes only inside `gol-project/` or the worktree
- Use semantic commit style: `feat(module): description` or `fix(module): description`
- Push the submodule branch first
- If working directly in `gol-project/`, return to `gol/`, update the `gol-project` submodule pointer, commit, and push the parent repo
- If working in a worktree, push only the feature branch; parent repo pointer update happens after merge

## What You Do NOT Do

- Write feature code directly
- Run tests directly
- Create branches in `gol/`
- Create worktrees from `gol/`
- Create files outside `gol-project/` during implementation
- Create game files in the management repo
- Duplicate `gol-test-writer` or `gol-test-runner` logic
- Skip the submodule-first push order

## Resources

- `references/explore-prompt.md` — Phase 1 research prompt
- `references/implement-prompt.md` — Phase 2 implementation prompt
- Reuse existing skills: `git-master`, `gol-test-writer`, `gol-test-runner`

## Validation Checklist

- [ ] Asked the single startup question, then proceeded autonomously
- [ ] Chose the correct setup path: in-repo or worktree
- [ ] Kept all implementation changes inside `gol-project/` or its worktree
- [ ] Dispatched explore and implement phases with the reference prompts
- [ ] Delegated testing through existing GOL test skills
- [ ] Committed and pushed in the correct repo order
