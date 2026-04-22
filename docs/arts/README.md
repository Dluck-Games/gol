# GOL Art Standards

Single source of truth for God of Lego visual asset specifications. The `gol-pixel-art` skill references this directory — update these docs to evolve art standards without modifying the skill itself.

## Contents

| Document | Purpose |
|----------|---------|
| [style-guide.md](style-guide.md) | Color palette, aesthetic rules, animation conventions |
| [asset-paths.md](asset-paths.md) | Where each asset type belongs in gol-project/ |
| [commit-convention.md](commit-convention.md) | Commit message format for art changes |
| [prompts/](prompts/) | Per-category prompt templates for AI generation |

## Prompt Templates

Each file in `prompts/` is a self-contained template for generating assets of that category. They include:
- Target dimensions and format
- Style constraints specific to the category
- Example prompts based on existing assets
- Common variations and poses

## Workflow

1. Choose the asset category → read the matching `prompts/*.md`
2. Craft a prompt using the template
3. Generate via `node gol-tools/pixel-art/pixel-art.mjs pipeline`
4. Output goes to `.debug/art-workspace/` (gitignored temp space)
5. Review and accept → move final .png to the path specified in `asset-paths.md`
6. Commit following `commit-convention.md`

## Relationship to Skill

The `gol-pixel-art` skill (`.claude/skills/gol-pixel-art/SKILL.md`) references this directory for art standards. To update art conventions:
- Edit files here in `docs/arts/`
- The skill automatically picks up changes on next load
- No need to modify SKILL.md for standard updates
