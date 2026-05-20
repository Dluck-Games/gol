# GOL Agent Assets

This directory is the canonical source for project-scoped agent assets that should be shared across coding-agent clients.

- `skills/` is the only hand-edited source for GOL project skills.
- `hooks/` is the only hand-edited source for GOL project hook scripts.
- `.claude/skills` is a symlink to `../.agents/skills`.
- `.codex/skills` is a symlink to `../.agents/skills`.
- OpenCode/OMO should continue using its Claude compatibility layer and project `.opencode/oh-my-openagent.json` settings.
- `.claude/settings.json` and `.codex/hooks.json` only register hooks and should point at `.agents/hooks`.

When changing a skill, edit files under `.agents/skills/<skill-name>/`.
When changing a hook, edit files under `.agents/hooks/`.
