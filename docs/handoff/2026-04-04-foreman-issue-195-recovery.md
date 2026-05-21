# Handoff: Foreman Issue 195 Recovery

Date: 2026-04-04
Session focus: Debugged and stabilized Foreman orchestration around gol-tools issues #10/#11 and the live rerun/recovery flow for issue #195.

## User Requests (Verbatim)

- "fix gol-tools submodule's issue #10 and #11. before you started, read docs and history to make sure understanding what the realy meaning it is."
- "修复代码合入到 main，然后 reload 部署，收尾工作。关闭已修复的 issue"
- "我正在 issue 195 进行测试，发现 planner 将 plan 写进了 superpowers/plans 当中，而不是 foreman/<issue_num>/plans，请继续修正此问题，直接提交到 main，并且 raload 部署 foreman。理想的方案是限制 planner 仅能写入 issue 目录中 plans 和 iterations 两个目录，其他目录仅开放读取。并且修正提示词和错误引导内容。"
- "经过对 195 工作的持续观察，还有两个问题，iterations 文档没有产出 + coder 无法提交代码。请继续深入分析原因，修复。"
- "ok 修掉这个 stale task 问题"
- "I have just cleaned the docs files of issue 195 and run foreman-ctl reset 195, then ran foreman-ctl list, the task seems been blocked to marked as dead letter. please continue address the issue of it."
- "I saw tl see the reviewer has been apporved the work, but tl decide to rework just because the handoff doc not fill some conditions. I think this doesn't need, find out why and tring to avoid tl keep ask coder to rework for just a handoff doc improvement, that's even not a delivered source code, shoudn't be asked for rework. rework is only happened on task hasn't been finished to fit the issue's goal. also, there are 4 decisions md doc showed that this is first decision, that means some how tl do 4th first decisiton, defenitiy not right. but it maybe caused by we launched or reseted this issue work multiply times, not a real bug. anyway, if you located it's a issue, fix it."
- "today's bug is so much, work is done, record things into handoff doc"

## Goal

Preserve the final state of the Foreman recovery work so the next session can quickly continue only if new live rerun bugs appear, instead of re-discovering the same orchestration failures.

## Work Completed

- I investigated and fixed the original gol-tools planner-path regression, then corrected it back to the intended issue-local model: planner detailed plans now belong under `docs/foreman/<issue>/plans/`, and planner handoff docs belong under `docs/foreman/<issue>/iterations/`.
- I updated `gol-tools/foreman/foreman-daemon.mjs`, `gol-tools/foreman/lib/doc-manager.mjs`, and the planner/coder/reviewer/tester/TL prompts so planner only writes inside the current issue docs area and downstream roles read the issue-local planner docs.
- I fixed the coder git failure by making the framework attach coder workspaces to the issue branch before commit/push, instead of letting commit happen on detached HEAD.
- I fixed stale reset behavior by moving `foreman-ctl reset` from direct `state.json` mutation into daemon-owned control flow. The daemon now clears task state, pending ops, dead-letter state, and runtime caches consistently.
- I fixed rerun dead-lettering caused by Git worktree collisions by teaching `gol-tools/foreman/lib/workspace-manager.mjs` to reuse an existing worktree for a branch that is already checked out, instead of trying to add a duplicate worktree for `foreman/issue-195`.
- I fixed the policy bug where reviewer-approved work could still be sent back to coder purely because reviewer/coder/tester handoff docs were missing required section headers. Non-planner handoff section gaps are now treated as non-blocking warnings, and reviewer-approved work is protected from coder rework when the issue goal is already met.
- I fixed a real orchestration docs bug: `gol-tools/foreman/lib/doc-manager.mjs` now makes decision index appends idempotent, so `docs/foreman/<issue>/orchestration.md` stops duplicating decision rows when both TL and daemon touch the index.
- I updated `gol-tools/foreman/prompts/tasks/tl/decision.md` so TL is explicitly told not to reopen coder work for handoff-doc polish and not to describe resets/reruns as a “first dispatch.”
- I pushed all gol-tools fixes to `main`, updated the management repo submodule pointer multiple times as the fixes landed, reloaded Foreman after each major deployment, and closed gol-tools issues #10 and #11 once those were actually fixed and deployed.

## Current State

- `gol-tools/main` includes the full stack of issue-195 recovery fixes, including:
  - `437b901` `fix(state): reset stale foreman issue state atomically`
  - `91d9fd0` `fix(foreman): route resets through the daemon`
  - `078115a` `fix(workspace): reuse branch worktrees during reset reruns`
  - `59fc822` `fix(foreman): stop doc-only review warnings from reopening coder work`
  - `9639f4f` `fix(tl): distinguish reruns from first-dispatch doc followups`
  - `d88e8a4` `fix(docs): make decision index updates idempotent`
- `gol/main` points at the deployed submodule state via `e72936f` (`chore: update gol-tools submodule for TL doc policy fixes`).
- Final verification I ran in this session:
  - `node --test tests/state-manager.test.mjs`
  - `node --test tests/workspace-manager.test.mjs`
  - `node --test tests/daemon-runtime-utils.test.mjs tests/doc-manager.test.mjs`
  - `npm test` in `gol-tools/foreman`
- Current live runtime snapshot at handoff time:
  - `foreman-ctl status` showed daemon PID `17681`, running, `0` active tasks, `5` dead-letter tasks unrelated to the current fix.
  - `gh issue view 195` showed issue `#195` still OPEN but labeled `foreman:done`.
- Uncommitted changes (from git status): none in `gol-tools/` and none in the management repo at the moment I generated this handoff.

## Pending Tasks

- No mandatory code fix remains from this session.
- The next logical step is only to monitor the next real live rerun/review cycle and confirm the new TL/doc policy behaves as intended when a reviewer-approved handoff doc is imperfect.
- If a new orchestration bug appears, start from the latest daemon logs after PID `17681` and the current `gol-tools/main` state rather than reusing older issue-195 conclusions blindly.
- If someone wants historical cleanliness, they can normalize or archive older `docs/foreman/195/decisions/*.md` content, but that is not required for current runtime correctness.

## Key Files

- `gol-tools/foreman/foreman-daemon.mjs` — Main orchestration logic; now contains planner-handoff handling, reset control handling, worktree reuse usage, and doc-only rework bypass logic.
- `gol-tools/foreman/lib/doc-manager.mjs` — Issue docs layout, planner/iteration doc lookup, decision file writing, and idempotent orchestration index updates.
- `gol-tools/foreman/lib/state-manager.mjs` — Atomic reset of tasks/pending ops/dead-letter state.
- `gol-tools/foreman/lib/workspace-manager.mjs` — Branch worktree reuse logic for reruns and PR-branch recovery.
- `gol-tools/foreman/lib/daemon-runtime-utils.mjs` — Runtime policy helpers for respawn reuse and doc-warning/reviewer-approval decisions.
- `gol-tools/foreman/bin/foreman-ctl.mjs` — CLI reset flow now writes daemon control requests instead of mutating state out-of-band.
- `gol-tools/foreman/prompts/tasks/tl/decision.md` — TL rules for reruns, coder rework scope, and orchestration ownership.
- `gol-tools/foreman/tests/workspace-manager.test.mjs` — Regression coverage for reusing an existing worktree on rerun.
- `gol-tools/foreman/tests/state-manager.test.mjs` — Regression coverage for atomic reset behavior.
- `docs/foreman/195/orchestration.md` — Useful historical artifact for issue-195 decisions, but contains pre-fix history and should not be treated as proof of current live behavior.

## Important Decisions

- I decided that planner detailed plans and planner handoff docs are different artifacts and must live in different issue-local directories (`plans/` vs `iterations/`).
- I decided that reset must be daemon-owned instead of CLI-owned because state file edits alone cannot safely update in-memory task maps, retry state, or pending process ownership.
- I decided that reruns must reuse an existing issue branch worktree if one already exists, following the Git worktree model rather than fighting it.
- I decided that documentation completeness and code correctness are different acceptance dimensions: handoff-doc section mismatches for coder/reviewer/tester are warnings unless they reveal a real implementation failure.
- I decided that coder rework should only be used when the issue goal is still unmet, not when reviewer-approved work merely has handoff-doc polish problems.
- I decided that `orchestration.md` index ownership belongs to the daemon and must be idempotent, because TL + daemon double-writing created misleading duplicate decision history.

## Constraints

- "理想的方案是限制 planner 仅能写入 issue 目录中 plans 和 iterations 两个目录，其他目录仅开放读取。并且修正提示词和错误引导内容。"
- "rework is only happened on task hasn't been finished to fit the issue's goal."
- "also, there are 4 decisions md doc showed that this is first decision, that means some how tl do 4th first decisiton, defenitiy not right. but it maybe caused by we launched or reseted this issue work multiply times, not a real bug. anyway, if you located it's a issue, fix it."

## Context for Continuation

- The biggest trap in this area is mixing **historical issue-195 docs** with **current runtime behavior**. Many of the older decision files and orchestration rows were produced before the reset/worktree/doc-policy fixes; they are useful forensic evidence but not a specification of the current system.
- The freshest reliable behavior comes from the deployed code plus the daemon log evidence after the final reload. In particular, the worktree collision was resolved when the log changed from `Worktree creation failed ... already used by worktree` to `Reusing worktree for branch foreman/issue-195` followed by `queued -> planning`.
- Another important nuance: the current fix prevents the framework from reopening coder work for doc-only gaps, but I did not get a brand-new end-to-end reviewer-approved-then-doc-warning cycle after that exact policy deploy, because `#195` ended up at `foreman:done` by the time the last daemon came up. If someone reports that behavior again, that is the next live acceptance path to inspect.
- External references gathered during this session supported two design choices I already implemented: (1) code acceptance and documentation completeness should be separate dimensions, and (2) Git worktree reruns should discover and reuse existing branch attachments instead of calling `git worktree add` blindly.

---

To continue: open a new session and paste this file's content as the first message, then add your next task.
