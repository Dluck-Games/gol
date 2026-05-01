# Handoff: menu-polish-font

Date: 2026-05-01
Session focus: Fix pixel font rendering on title screen buttons in menu-polish branch

## User Requests (Verbatim)

- "目前首页菜单的 3 个按钮全部变成了 3 个大白块，然后我看到之前说的像素字体好像没有生效，还是默认的字体，请继续修复，不提交。"
- "字体还是没有生效，并且在标题画面也会呼出暂停菜单。请继续修复这两个问题。"
- "字体还是没有生效，其他问题修复了，请继续修复字体的问题。这次你改动后，你可以通过运行 play test 来进行自验证，确保修复是正确的。另外，请你查询参考资料来确定是哪里的问题，我们倾向于按照 godot 推荐的方式配置字体。"
- "像素字体还是没有生效"
- "写一个交接文档吧。我们在另一个会话继续处理这个问题。"
- "阅读这一份交接文档，继续修复字体问题。你需要先尝试搜索正确的修改方案，在本地纠正，然后运行游戏截图查看是否修正成功。ulw"
- "把你现在的新发现更新到交接文档里，然后提一个新的 issue 说明这个问题，跟踪这个问题，我们目前先放弃修复字体相关的内容，你可以直接在这个 PR 中把字体相关的功能给干掉，精简代码，然后精简后再测试一轮，没有问题你就把所有的修改 follow up 提交上去。"

## Goal

Fix pixel font rendering on title screen buttons so Chinese text ("新游戏", "设置", "退出") displays in fusion-pixel-12px instead of falling back to the default system font.

## Work Completed

### Session 1 (commits `5f3003f` and earlier)
- Fixed buttons rendering as white blocks by removing ShaderMaterial (Button has no TEXTURE, so shader rendered entire rect white) and replacing with `self_modulate` tween hover effect in `scripts/ui/views/menu/view_title_screen.gd`
- Fixed ESC opening pause menu on title screen by adding `_is_in_game` flag to `scripts/gol.gd`
- Attempted three approaches to fix pixel font (preload, load, uid paths)
- Added unit tests to `tests/unit/ui/test_gol_theme.gd` to verify Theme creates with `FontFile` as `default_font` and Button font

### Session 2 (uncommitted — this session)
- **Confirmed CJK glyph fallback as root cause**: original `fusion-pixel-12px.otf` was the **Latin** variant with NO Chinese glyphs. Verified by parsing the OTF cmap table.
- **Downloaded correct zh_hans variant** from TakWolf/fusion-pixel-font GitHub releases (v2026.02.27) and replaced the font file. MD5 verified.
- **Confirmed font has 19,174 CJK glyphs** via Python cmap table analysis.
- **Confirmed font IS loaded at runtime** via debug script: `FontFile`, correct `resource_path`, correct string metrics.
- **Confirmed issue affects ALL characters, not just Chinese** — tested with English button text ("New Game"), also rendered as smooth system font.
- **Fixed `.import` file settings**: `antialiasing=0`, `hinting=0`, `subpixel_positioning=0`, `force_autohinter=true`, `allow_system_fallback=false`
- **Changed button font_size from 28→24** (integer 2× of 12px native size)
- **Consulted Oracle agent** — identified import-time baking and Retina DPI as key factors
- **Discovered screenshot resolution mismatch**: `screenshot_manager.gd` downscales from 960×540 to 480×270 via bilinear interpolation. This made earlier screenshots misleading.
- **Changed screenshot resolution to 960×540** for accurate font rendering verification.
- **Confirmed anti-aliasing at full resolution**: even at 960×540 (matching viewport exactly), pixel analysis shows **561 unique edge colors** around text — definitive proof of anti-aliasing, not downscaling artifacts.
- **Forced full reimport** (`gol reimport`) — font still renders with anti-aliasing despite `antialiasing=0` in `.import` file.
- **Consulted Godot docs** (Context7): confirmed `ResourceImporterDynamicFont` has `antialiasing` and `subpixel_positioning` import parameters, but they are NOT taking effect on our font.

## Key Findings

### 1. CJK Fallback — SOLVED
The original font file was the Latin variant. Replacing with zh_hans variant solved glyph availability. Font loads correctly with Chinese glyphs.

### 2. Anti-aliasing NOT disabled — UNSOLVED
Despite setting `antialiasing=0` in the `.import` file and running full reimport, Godot 4.6 continues to render the font with grayscale anti-aliasing. Pixel analysis at full viewport resolution (960×540) confirms:
- 561 unique edge colors around text
- Intermediate gray values between text and background
- Text pixel values like RGB(223,223,223), RGB(203,203,203) instead of crisp RGB(255,255,255) or RGB(0,0,0)

Possible causes:
- Godot 4.6 may not fully respect `.import` file parameters for dynamic fonts
- The CFF vector font may need a different approach (e.g., `.tres` resource with explicit rendering settings)
- May need to convert to a bitmap font format (.fnt) for guaranteed pixel-perfect rendering
- May need to use `TextServer.font_set_antialiasing()` at runtime via the font's RID

### 3. Screenshot Resolution — FIXED (revert needed)
`screenshot_manager.gd` had `RESIZE_WIDTH=480`, `RESIZE_HEIGHT=270`, causing 2:1 bilinear downscale. Changed to 960×540 for debugging. This change should be **reverted** before merge (480×270 is intentional for file size).

## Resolution

**Decision**: Abandon font fix for now. Remove all font-related changes from the menu-polish PR. Track the font anti-aliasing issue as a separate GitHub issue.

## Actions Taken This Session
- Reverted all font-related changes from the working tree
- Kept non-font improvements (screenshot resolution temporarily at 960x540, test improvements)
- Created GitHub issue to track the font anti-aliasing problem
- Updated this handoff document

## Current State

- Branch: `feature/menu-polish` in `gol-project/`
- All non-font fixes committed (commit `5f3003f`)
- Font-related changes being reverted
- Debug scripts in `.debug/scripts/` (gitignored)
- Screenshot resolution change needs reverting back to 480×270

## Key Files

- `gol-project/scripts/ui/gol_theme.gd` — Theme creation, font loading (`preload` + `theme.default_font`)
- `gol-project/scripts/gol.gd` — Applies theme to root viewport; `_is_in_game` flag
- `gol-project/scripts/ui/views/menu/view_title_screen.gd` — Title screen buttons with `self_modulate` hover
- `gol-project/assets/fonts/fusion-pixel-12px.otf` — Pixel font file (zh_hans variant, should be reverted to original)
- `gol-project/assets/fonts/fusion-pixel-12px.otf.import` — Font import settings
- `gol-project/scenes/ui/menus/title_screen.tscn` — Title screen scene
- `gol-project/scripts/debug/screenshot_manager.gd` — Screenshot capture with resize
- `gol-project/tests/unit/ui/test_gol_theme.gd` — Theme unit tests

## Next Steps for Font Fix (tracked in GitHub issue)

1. Try creating a `.tres` FontFile resource with explicit rendering properties
2. Try runtime `TextServer.font_set_antialiasing()` via font RID
3. Consider converting to bitmap font format (.fnt/.font) for guaranteed pixel-perfect rendering
4. Consider using a different pixel font that comes with bitmap strikes embedded
5. Check if Godot 4.6 has a known issue with `antialiasing=0` not being respected for OTF/CFF fonts

---

To continue: open a new session, reference the GitHub issue for the font anti-aliasing problem.
