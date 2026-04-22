# Art Asset Commit Convention

## Format

```
art(<category>): <description>
```

## Categories

| Category | Scope | Example |
|----------|-------|---------|
| character | Player/NPC sprites | `art(character): add survivor idle sprite` |
| enemy | Enemy sprites | `art(enemy): add zombie walk animation` |
| box | Containers | `art(box): add medical supply crate variant` |
| tile | Map tiles | `art(tile): add cracked road transition tiles` |
| vfx | Visual effects | `art(vfx): add explosion burst frames` |
| bullet | Projectiles | `art(bullet): add fire bullet sprite` |
| icon | UI icons | `art(icon): add wood resource icon` |
| item | Inventory items | `art(item): add potion bottle pickup` |
| background | Scene backgrounds | `art(background): add ruins environment` |
| artwork | Title/menu art | `art(artwork): update title screen` |
| ui | Interface elements | `art(ui): add minimap pin marker` |

## Rules

1. One commit per asset category change
2. Include the asset type in the scope
3. Description should name the specific asset
4. If updating existing art, use "update" not "add"
5. If removing art, use "remove"

## Examples

```
art(box): add destroyed crate variant
art(character): update survivor walk animation to 4 frames
art(tile): add sidewalk-to-grass corner transitions
art(icon): add component_point resource icon
art(vfx): remove placeholder claw effect frames
```

## Multi-Asset Commits

When adding multiple related assets in one commit:
```
art(enemy): add zombie idle and walk sprite sheets
art(tile): add road dashed line variants (thin, thick, crosswalk)
```
