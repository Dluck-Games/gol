# GOL Agent Assets

This directory is the canonical source for project-scoped agent assets that should be shared across coding-agent clients.

- `skills/` is the only hand-edited source for GOL project skills.
- `.claude/skills` is a symlink to `../.agents/skills`.
- `.codex/skills` is a symlink to `../.agents/skills`.
- OpenCode/OMO should continue using its Claude compatibility layer and project `.opencode/oh-my-openagent.json` settings.
- Hooks are not centralized here yet; keep the existing `.claude/hooks` and `.codex/hooks.json` setup until hook churn justifies moving them.

When changing a skill, edit files under `.agents/skills/<skill-name>/`.
