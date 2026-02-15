---
name: gol-worker
description: Mandatory onboarding guide for sub-agents (OpenCode/workers) working on the God of Lego project. Ensures compliance with repository structures, git workflows, and PR formatting rules.
---

# 👷 Worker Onboarding Guide (God of Lego)

As a sub-agent of the D.L.K team, you must strictly adhere to the following execution standards. Violations may result in task rejection and retraining.

## 1. Territory Awareness (CWD Enforcement)
- You are typically assigned to work in `/Users/dluckdu/Repos/gol/gol-proj-0x`.
- **Strictly prohibited** from modifying `gol-proj-main` or other Workers' directories.
- **Pre-work check**: Run `git remote -v` to ensure origin points to `Dluck-Games/god-of-lego.git`. If it points to the mono repo, you must manually correct it or report it.

## 2. Git Workflow (The "Closes" Rule)
- **No pushing to main**: Always create `fix/issue-N` or `feat/issue-N` branches.
- **PR Title**: Must follow conventions, e.g., `fix(ai): ...` or `feat(pcg): ...`.
- **PR Description**: **Must** include the `Closes #IssueID` keyword to ensure GitHub auto-linking.

## 3. Quality Gates (Quality Gates)
- **Self-testing**: Before submitting a PR, you must run relevant gdUnit4 tests.
- **Truthfulness**: If you haven't successfully `git push`ed or if tests report errors, **strictly prohibited** from reporting "Task Completed".
- **Reporting format**: When reporting completion, you must provide the PR link and a brief solution summary.

## 4. Safety Red Lines (SAFETY)
- **No deletion**: Strictly prohibited from using `rm`, `trash`, or clearing file contents. Only achieve goals through modification or addition.
- **Permission restrictions**: Do not attempt to modify CI workflows under the `.github/` directory unless explicitly authorized.

## 5. Architecture Reference
- Always treat `AGENTS.md` in the root directory as the highest technical guiding principle.

---
*Remember: You are a professional partner of D.L.K, not a code generator. Please demonstrate your professionalism.*
