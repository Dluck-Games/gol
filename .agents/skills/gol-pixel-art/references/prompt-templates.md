> **Superseded by `docs/arts/prompts/`.** Per-category templates now live in individual files under `docs/arts/prompts/`. See `docs/arts/README.md` for the current SSOT.

# Prompt Templates for GOL Pixel Art

## Base Template

All prompts follow this structure:
```
[Subject description]. [Specific details].
Render as a single sprite on a transparent/solid-color background.
Target resolution: 1024x1024 pixels.
Use a muted, desaturated palette similar to Game Boy-style indie pixel art.
Simple geometric shape, strong silhouette, no background.
Subtle shading using 3-5 tones only.
Elegant, minimalist, consistent with a restrained pixel-art style.
```

The style suffix is automatically appended by the CLI tool.

## Per-Asset-Type Templates

### Character (32×32)
```
A [adjective] [character type] for a 2D survival game.
[Pose description]. [Clothing/equipment details].
Clear readable silhouette at small scale.
Front-facing or 3/4 view.
```

Example:
```
A rugged survivor wearing a tattered jacket and carrying a makeshift backpack.
Standing idle pose, slightly hunched. Visible tool belt with small items.
Clear readable silhouette at small scale. 3/4 view facing right.
```

### Enemy (32×32)
```
A [threat level] [enemy type] creature for a 2D survival game.
[Distinctive feature]. [Movement pose].
Menacing but readable silhouette. Distinct from player character.
```

Example:
```
A shambling undead figure with torn clothing and exposed bones.
Lurching forward with arms slightly raised. Glowing eyes.
Menacing but readable silhouette. Distinct from player character.
```

### Box/Container (64×64)
```
A [condition] [container type] for a 2D survival game.
[Material details]. [Wear/damage description].
Light wear: small pixel chips, faded edges, nothing noisy.
Variants optional: [list variants if needed].
```

Example (from existing box.prompt):
```
A clean, readable pixel-art supply crate for a 2D survival game.
Use a muted, desaturated palette similar to Game Boy-style indie pixel art.
Simple geometric shape, strong silhouette, no background.
Subtle shading using 3-5 tones only.
Light wear: small pixel chips, faded edges, nothing noisy.
Variants optional: wooden crate, metal crate, medical supply box, food box.
Elegant, minimalist, consistent with a restrained pixel-art style.
```

### Tile (64×32)
```
A [surface type] ground tile for a 2D top-down survival game.
Seamless edges for tiling. [Surface details].
Flat perspective, viewed from above at slight angle.
Subtle texture variation, not busy or noisy.
```

Example:
```
A cracked asphalt road tile for a 2D top-down survival game.
Seamless edges for tiling. Faded lane markings, small debris.
Flat perspective, viewed from above at slight angle.
Subtle texture variation, not busy or noisy.
```

### VFX (100×100)
```
A [effect type] visual effect sprite for a 2D survival game.
[Motion/energy description]. [Color emphasis].
Transparent background. Bright against dark backgrounds.
Single frame of a [duration] animation.
```

Example:
```
A fiery explosion burst visual effect sprite for a 2D survival game.
Radiating energy with debris particles. Warm orange-red emphasis.
Transparent background. Bright against dark backgrounds.
Single frame of a short burst animation.
```

### Bullet (32×32)
```
A [projectile type] for a 2D survival game.
[Shape and trail description]. Small and fast-looking.
Clear direction of travel. Minimal detail, maximum readability.
```

### Icon (16×16)
```
A [resource/status] icon for a 2D survival game UI.
Extremely simple, 2-3 colors maximum. Instantly recognizable.
Must be readable at 16x16 pixels. No fine detail.
```

### Item (32×32)
```
A [item type] pickup item for a 2D survival game.
[Distinctive shape]. Ground-level perspective.
Clear silhouette, identifiable at small scale.
```

## Prompt Iteration Tips

1. Start with a simple, direct description
2. If the result is too complex, add "minimal detail" or "fewer elements"
3. If colors are wrong, explicitly state "using only dark blues, teals, and warm browns"
4. If the silhouette is weak, add "strong contrast between subject and background"
5. For consistency across frames, keep the same structural description and only change the pose
