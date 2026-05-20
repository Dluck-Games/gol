> **Archived legacy guide.** The active workflow is in `../SKILL.md` and `docs/arts/`.

# Pipeline Guide

This file is kept only as a compatibility pointer for older references.

Current concept paths:
- `--backend gpt` for GPT semi-manual handoff
- `--backend comfyui` for local ComfyUI generation

The old direct Gemini and CodeBuddy ImageGen paths are intentionally disabled in the public CLI. Their implementation files remain in `gol-tools/pixel-art/pixel_art/` for future re-enable work, but agents should not offer or call them.

Do not create or ask users to maintain repo-local `.env` files. API keys and provider credentials belong in the user's system environment.
