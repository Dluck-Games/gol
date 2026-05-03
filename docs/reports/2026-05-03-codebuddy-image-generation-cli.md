# CodeBuddy CLI Image Generation Research

Date: 2026-05-03

## Summary

Local CodeBuddy can generate images from the command line through headless mode (`codebuddy -p`) when the built-in deferred `ImageGen` tool is enabled and allowed.

The working path is not a standalone `codebuddy imagegen ...` subcommand. It is a prompt-driven agent run that discovers `ImageGen` via `ToolSearch`, invokes it through `DeferExecuteTool`, and writes the generated image to a local file.

Verified local version:

```bash
codebuddy --version
# 2.95.0
```

## Supported Image Generation Models

Official CodeBuddy release notes list three Gemini image generation models supporting both text-to-image and image-to-image generation:

| Official display name | Recommended CLI model ID | Status |
| --- | --- | --- |
| `Gemini-3.0-Pro-Image` | `gemini-3.0-pro-image` | Officially documented; not locally verified in this session |
| `Gemini-3.1-Flash-Image` | `gemini-3.1-flash-image` | Officially documented; locally verified working |
| `Gemini-2.5-Flash-Image` | `gemini-2.5-flash-image` | Officially documented; not locally verified in this session |

Notes:

- CodeBuddy documentation uses display names such as `Gemini-3.1-Flash-Image`.
- The local CLI test succeeded with the lowercase model ID `gemini-3.1-flash-image`.
- Prefer lowercase IDs in shell commands because CodeBuddy CLI model IDs are generally lowercase in `codebuddy --help` output.

## Relevant CodeBuddy Capabilities

Official documentation confirms the following pieces:

- `ImageGen`: built-in tool that generates images from text descriptions.
- `ImageEdit`: built-in tool that edits existing images from text instructions.
- `ToolSearch`: discovers deferred tools such as `ImageGen`.
- `DeferExecuteTool`: invokes a deferred tool discovered by `ToolSearch`.
- `--text-to-image-model`: sets the default model for text-to-image generation.
- `--image-to-image-model`: sets the default model for image-to-image editing.
- `textToImageModel`: settings key for default text-to-image model.
- `imageToImageModel`: settings key for default image-to-image model.
- `CODEBUDDY_IMAGE_GEN_ENABLED`: feature toggle; set to `false` or `0` to disable image generation.
- `CODEBUDDY_IMAGE_EDIT_ENABLED`: feature toggle; set to `false` or `0` to disable image editing.
- `CODEBUDDY_REHYDRATE_IMAGE_BLOB_REFS`: useful in `-p` streaming output when downstream integrations need full image blob data.
- `CODEBUDDY_IMAGE_TO_IMAGE_MODEL`: release-note documented environment variable for default image-to-image model.

Primary references:

- Tools reference: https://www.codebuddy.ai/docs/cli/tools-reference
- CLI reference: https://www.codebuddy.ai/docs/cli/cli-reference
- Headless mode: https://www.codebuddy.ai/docs/cli/headless
- Settings: https://www.codebuddy.ai/docs/cli/settings
- Environment variables: https://www.codebuddy.ai/docs/cli/env-vars
- ImageGen release note: https://www.codebuddy.ai/docs/cli/release-notes/v2.39.0
- ImageEdit release note: https://www.codebuddy.ai/docs/cli/release-notes/v2.48.0
- Gemini image models release note: https://www.codebuddy.ai/docs/cli/release-notes/v2.52.3

## Minimal Working Command

This command was verified locally and generated an image file:

```bash
CODEBUDDY_IMAGE_GEN_ENABLED=true \
CODEBUDDY_REHYDRATE_IMAGE_BLOB_REFS=true \
codebuddy -p "Use ImageGen to generate one 512x512 image: a single blue circle centered on a white background. Return only the generated image path, URL, or image blob reference." \
  --model gemini-3.1-pro \
  --text-to-image-model gemini-3.1-flash-image \
  --allowedTools ImageGen \
  -y \
  --output-format json \
  --max-turns 8
```

Observed result:

```text
/Users/dluck/Documents/GitHub/gol/generated-images/a_single_blue_circle_centered__2026-05-03T07-25-36.png
```

The important tool trace was:

```text
ToolSearch -> ImageGen
DeferExecuteTool(toolName="ImageGen", params={"prompt":"a single blue circle centered on a white background","size":"512x512"})
```

## Recommended Command Template

For one-off text-to-image generation:

```bash
CODEBUDDY_IMAGE_GEN_ENABLED=true \
codebuddy -p "Use ImageGen to generate one image. Prompt: <YOUR_IMAGE_PROMPT>. Size: 1024x1024. Return only the generated image path or URL." \
  --model gemini-3.1-pro \
  --text-to-image-model gemini-3.1-flash-image \
  --allowedTools ImageGen \
  -y \
  --output-format json \
  --max-turns 8
```

For prompts stored in a file:

```bash
PROMPT_PATH="gol-arts/artworks/sprites/items/carrot.prompt"

CODEBUDDY_IMAGE_GEN_ENABLED=true \
codebuddy -p "Use ImageGen to generate one 1024x1024 image from this prompt. Return only the generated image path or URL. Prompt: $(cat "$PROMPT_PATH")" \
  --model gemini-3.1-pro \
  --text-to-image-model gemini-3.1-flash-image \
  --allowedTools ImageGen \
  -y \
  --output-format json \
  --max-turns 8
```

For a custom output directory, ask the agent to pass `output_dir` to `ImageGen`:

```bash
CODEBUDDY_IMAGE_GEN_ENABLED=true \
codebuddy -p "Use ImageGen to generate one image with output_dir set to gol-arts/artworks/sprites/items. Prompt: <YOUR_IMAGE_PROMPT>. Return only the generated local path." \
  --model gemini-3.1-pro \
  --text-to-image-model gemini-3.1-flash-image \
  --allowedTools ImageGen \
  -y \
  --output-format json \
  --max-turns 8
```

For streaming output that downstream scripts can parse while the run is still active:

```bash
CODEBUDDY_IMAGE_GEN_ENABLED=true \
CODEBUDDY_REHYDRATE_IMAGE_BLOB_REFS=true \
codebuddy -p "Use ImageGen to generate one image. Prompt: <YOUR_IMAGE_PROMPT>. Return the generated image path." \
  --model gemini-3.1-pro \
  --text-to-image-model gemini-3.1-flash-image \
  --allowedTools ImageGen \
  -y \
  --output-format stream-json \
  --max-turns 8
```

For image-to-image editing, use `ImageEdit` and the image-to-image model flag:

```bash
CODEBUDDY_IMAGE_EDIT_ENABLED=true \
codebuddy -p "Use ImageEdit to edit the provided image: <EDIT_INSTRUCTION>. Return only the generated image path or URL." \
  --model gemini-3.1-pro \
  --image-to-image-model gemini-3.1-flash-image \
  --allowedTools ImageEdit \
  -y \
  --output-format json \
  --max-turns 8
```

## ImageGen Parameters

When `ToolSearch` found `ImageGen`, the returned schema included these parameters:

| Parameter | Meaning |
| --- | --- |
| `prompt` | Required text description of the image |
| `size` | Image size, for example `1024x1024` or `1024x1536` |
| `n` | Number of images to generate, 1-10, default 1 |
| `quality` | `low`, `medium`, or `high` |
| `style` | Image style instruction |
| `background` | `transparent` or `opaque` |
| `footnote` | Watermark text, max 16 characters for Hunyuan |
| `revise` | Whether to revise the prompt for Hunyuan |
| `output_dir` | Custom output directory; defaults to `generated-images` in the workspace |

Because `ImageGen` is a deferred tool, the prompt should explicitly say which parameters matter, especially `size`, `background`, and `output_dir`.

## Pitfalls Found During Testing

### Do Not Restrict `--tools` to Only `ImageGen`

This failed:

```bash
codebuddy -p "Use ImageGen ..." \
  --text-to-image-model Gemini-3.1-Flash-Image \
  --tools ImageGen \
  --allowedTools ImageGen \
  -y
```

The assistant reported that `ImageGen` was unavailable. The likely reason is that `ImageGen` is deferred and must first be discovered by `ToolSearch`, then executed by `DeferExecuteTool`. Restricting `--tools` to only `ImageGen` can hide the deferred-tool discovery path.

Use `--allowedTools ImageGen` instead, and avoid `--tools ImageGen` unless also allowing the deferred-tool machinery.

### Slash Commands Are Not Reliable in `-p`

This did not execute as an actual slash command in the headless test:

```bash
codebuddy -p "/model:text-to-image list"
```

The model treated it as normal text. For automation, prefer startup flags such as `--text-to-image-model` over slash commands.

### Lowercase Model IDs Are Safer for CLI

The successful command used:

```bash
--text-to-image-model gemini-3.1-flash-image
```

Earlier failed attempts used the display-style model name together with the restrictive `--tools ImageGen` flag. The failure cannot be attributed solely to casing, but lowercase IDs are the safer CLI convention.

## Configuration Options

Set default image models in CodeBuddy settings:

```json
{
  "textToImageModel": "gemini-3.1-flash-image",
  "imageToImageModel": "gemini-3.1-flash-image"
}
```

Settings file locations:

- User-level: `~/.codebuddy/settings.json`
- Project-level: `<project>/.codebuddy/settings.json`
- Local project override: `<project>/.codebuddy/settings.local.json`

Runtime environment toggles:

```bash
export CODEBUDDY_IMAGE_GEN_ENABLED=true
export CODEBUDDY_IMAGE_EDIT_ENABLED=true
export CODEBUDDY_REHYDRATE_IMAGE_BLOB_REFS=true
```

## Recommendations for GOL Art Workflow

For GOL concept generation, use CodeBuddy ImageGen as a quick concept-art source, not as the final production sprite pipeline.

Recommended flow:

1. Store the prompt in `gol-arts/artworks/<category>/<name>.prompt`.
2. Run CodeBuddy ImageGen with `output_dir` set to the matching `gol-arts/artworks/<category>/` directory.
3. Review the generated concept image.
4. Normalize through the existing pixel-art pipeline or manual Aseprite workflow.
5. Save production `.aseprite` sources under `gol-arts/assets/<matching-game-path>/`.
6. Export final production PNGs through the existing export workflow into `gol-project/assets/`.

This keeps CodeBuddy ImageGen as a concept-generation helper while preserving the existing GOL art asset ownership rules.
