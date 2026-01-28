# Video Walls Guide

## Supported Format

Godot 4 only supports **Theora (.ogv)** video files.

## Converting Videos

Convert any video to the correct format using ffmpeg:

```bash
ffmpeg -i input.mp4 -c:v libtheora -q:v 10 -g 1 -an -r 30 output.ogv
```

| Flag | Purpose |
|------|---------|
| `-c:v libtheora` | Theora video codec (required for Godot) |
| `-q:v 10` | Maximum quality (scale 0-10) |
| `-g 1` | Every frame is a keyframe (prevents motion artifacts) |
| `-an` | Strip audio (walls are muted) |
| `-r 30` | 30fps output |

## File Placement

Place your `.ogv` file in the `videos/` directory:

```
res://videos/arena_bg.ogv
```

The default video path is configured in `scripts/level_generator_q3.gd`:

```gdscript
const VIDEO_WALL_PATH: String = "res://videos/arena_bg.ogv"
```

## Resolution

The video viewport renders at **1920x1080** by default. Videos at this resolution or higher will look best. Lower resolution videos will be upscaled with linear filtering.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Block artifacts during motion | Re-encode with `-g 1` (all keyframes) |
| Washed out / wrong colors | Shader already handles this — ensure you're using the latest `video_wall.gdshader` |
| Video not loading | Confirm file is `.ogv` format and exists at the configured path |
| No video on walls | Check that `enable_video_walls = true` on the level generator |
