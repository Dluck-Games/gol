# GOL Agent Assets

This directory is the canonical source for project-scoped agent assets that should be shared across coding-agent clients.

- `skills/` is the only hand-edited source for GOL project skills.
- `hooks/` is the only hand-edited source for GOL project hook scripts.
- `.claude/skills` is a symlink to `../.agents/skills`.
- `.codex/skills` is a symlink to `../.agents/skills`.
- `.codex/hooks.json` is the primary hook registration surface.
- `.claude/settings.json` and OpenCode/OMO compatibility may keep lightweight hook registrations, but should not contain hook implementation logic.
- Client-specific hook config files should only register hooks and point at `.agents/hooks`.

When changing a skill, edit files under `.agents/skills/<skill-name>/`.
When changing a hook, edit files under `.agents/hooks/`.
