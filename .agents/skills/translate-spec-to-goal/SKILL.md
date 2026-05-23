---
name: translate-spec-to-goal
description: Convert a design spec into a GOAL.md for implementation handoff. Triggers - 'translate spec', 'spec to goal', 'write goal', 'make goal', 'handoff goal', '写 GOAL', '转 GOAL'
allowed-tools: Bash, Read, Write
---

## Purpose

Read a design spec and produce a `GOAL.md` at the project root that an implementation agent can pick up cold. The GOAL defines **what must be true when the work is done** — not how to get there.

## Input

User provides one of:
- A spec file path (e.g., `docs/superpowers/specs/2026-05-23-xxx-design.md`)
- A spec file name (skill searches `docs/superpowers/specs/` for it)
- "the latest spec" (skill picks the most recent by date prefix)

## Process

1. Read the spec file in full.
2. Extract acceptance criteria — conditions that are **binary, observable, and automatable**:
   - Commands that must succeed (with expected exit code)
   - Files that must exist or be deleted
   - Behaviors that must be demonstrable (output contains X, UI shows Y)
   - Existing tests that must still pass (regression)
3. Write `GOAL.md` to the project root with the format below.
4. Commit and push.

## Output Format

```markdown
# GOAL: <short title>

## Spec

[<relative path to spec>](<relative path to spec>)

## Task

<1-2 sentences: what to implement, referencing the spec for details.>

## Acceptance Criteria

<Numbered list. Each item is a single pass/fail condition.>
```

## Rules

- Each criterion must be **directly verifiable** — no subjective judgment ("code is clean"), no vague scope ("all edge cases handled").
- Prefer executable checks: commands with expected exit codes, file existence, grep patterns.
- Include regression criteria: existing tests that must continue to pass.
- If the spec has an "Affected Files Inventory", add a criterion that all listed files are updated.
- Keep the list to 8-15 items. Fewer means you missed something; more means you're over-specifying implementation details.
- Do NOT include implementation steps, architecture descriptions, or design rationale — that's in the spec.
- If `GOAL.md` already exists, ask the user before overwriting.
