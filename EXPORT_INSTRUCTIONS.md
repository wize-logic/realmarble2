# HTML5 Export Instructions for CrazyGames

## ✅ Pre-Export Setup Complete

The project has been configured for HTML5 export with the following changes:

### Changes Made

1. **Renderer Updated**: Changed from "Forward Plus" to "GL Compatibility"
   - Forward Plus is NOT web-compatible
   - GL Compatibility works in all browsers

2. **Export Preset Created**: HTML5 export preset configured in `project.godot`
   - Export path: `build/web/index.html`
   - Thread support: Enabled
   - Custom HTML template: `res://scripts/html/full-size.html`
   - Canvas resize policy: Adaptive
   - VRAM compression: Enabled for desktop

3. **CrazyGames SDK Integration**: Already configured in HTML template
   - SDK v3 integration complete
   - Auto-initialization on page load
   - User authentication support
   - Friends system support
   - Ad support (midgame, rewarded, banner)
   - Gameplay lifecycle events

## How to Export

### Option 1: Using Godot Editor (Recommended)

1. **Open the project in Godot 4.5.1**
   ```bash
   godot --editor .
   ```

2. **Verify Export Templates are Installed**
   - Go to `Editor` → `Manage Export Templates`
   - Make sure Godot 4.5.1 templates are installed
   - If not, click "Download and Install"

3. **Export the Project**
   - Go to `Project` → `Export`
   - Select "HTML5" preset (already configured)
   - Click "Export Project"
   - Choose location: `build/web/index.html`
   - Click "Save"

4. **Test Locally**
   ```bash
   cd build/web
   python3 -m http.server 8000
   ```
   - Open browser to `http://localhost:8000`
   - Test gameplay, multiplayer, SDK integration

### Option 2: Using Command Line

```bash
# Make sure you're in the project directory
cd /home/user/realmarble2

# Export using Godot headless
godot --headless --export-release "HTML5" build/web/index.html

# If you need debug build
godot --headless --export-debug "HTML5" build/web/index.html
```

## Post-Export Checklist

After exporting, verify the following files exist in `build/web/`:

```
build/web/
├── index.html          # Main HTML file (using custom template)
├── index.js            # Godot engine JavaScript
├── index.wasm          # WebAssembly binary
├── index.pck           # Packed game resources
├── index.worker.js     # Web worker (if threads enabled)
└── index.audio.worklet.js  # Audio worklet
```

## Testing Checklist

### ✅ Local Testing

Before uploading to CrazyGames, test locally:

1. **Basic Functionality**
   - [ ] Game loads without errors
   - [ ] Main menu displays correctly
   - [ ] Can start a practice match with bots
   - [ ] Player controls work (WASD, mouse, Space, Shift, Ctrl, E)
   - [ ] Physics feel correct (movement, spin dash, bounce)

2. **Multiplayer**
   - [ ] Can create a room
   - [ ] Room code is displayed
   - [ ] Can add bots in lobby
   - [ ] Can start match from lobby
   - [ ] Match timer works (5 minutes)
   - [ ] Scoreboard displays correctly

3. **CrazyGames SDK**
   - [ ] Check browser console for "CrazyGames SDK initialized successfully"
   - [ ] Check for SDK errors in console
   - [ ] Profile panel displays (main menu)
   - [ ] Friends panel displays (main menu)
   - [ ] SDK mock data works locally

4. **Performance**
   - [ ] Game runs at 60 FPS (check FPS counter)
   - [ ] No lag during gameplay
   - [ ] Audio plays correctly
   - [ ] Textures load properly
   - [ ] Particles render smoothly

5. **Browser Compatibility**
   - [ ] Chrome (latest)
   - [ ] Firefox (latest)
   - [ ] Safari (latest)
   - [ ] Edge (latest)

### ⚠️ Known Limitations

1. **Renderer Change Impact**
   - GL Compatibility has fewer features than Forward Plus
   - Some visual effects may look different
   - Lighting might be simpler
   - Shadows might be different quality

2. **Audio Compression**
   - WAV files should be converted to OGG for smaller size
   - MP3 files are supported but OGG is preferred
   - Consider reducing audio quality for web

3. **File Size Optimization**
   - Current build may be large (30-100 MB)
   - Consider compressing textures more aggressively
   - Consider reducing audio quality
   - Remove unused assets

## Pre-Deployment Requirements

### 1. Update Multiplayer Settings

The game currently uses ENet for local testing. For web deployment:

**File**: `scripts/multiplayer_manager.gd`

Find and update:
```gdscript
var use_websocket: bool = false  # Change to true
var relay_server_url: String = "ws://localhost:9080"  # Update to production server
```

**Important**: You need a WebSocket relay server for multiplayer to work in the browser!

### 2. WebSocket Server Options

**Option A: Simple Signaling Server** (Recommended for starting)
- See `CRAZYGAMES_DEPLOYMENT.md` for Node.js example
- Deploy to Heroku, Railway, or DigitalOcean
- Update `relay_server_url` to your server address

**Option B: Use CrazyGames Multiplayer** (If available)
- Check if CrazyGames provides multiplayer infrastructure
- Integrate their multiplayer SDK if available

**Option C: Disable Multiplayer** (Not recommended)
- Remove multiplayer button from main menu
- Only allow "Play with Bots" mode

### 3. File Size Optimization

If the build is too large (>50 MB), consider:

1. **Compress Textures**
   - Reduce texture resolution
   - Use more aggressive compression
   - Remove high-res textures

2. **Compress Audio**
   - Convert WAV to OGG
   - Reduce audio bitrate to 128 kbps or lower
   - Remove unused audio files

3. **Remove Unused Assets**
   - Check for unused scenes
   - Remove test/debug files
   - Clean up unused scripts

4. **Enable Additional Compression**
   - In export settings, enable PCK compression
   - Use smaller VRAM compression format

## Uploading to CrazyGames

### Preparation

1. **Create Build Folder**
   ```bash
   cd build/web
   zip -r marble-multiplayer.zip .
   ```

2. **Upload to CrazyGames**
   - Go to CrazyGames developer portal
   - Create new game or update existing
   - Upload `marble-multiplayer.zip`
   - Wait for processing

3. **Configure Game Settings**
   - Title: "Marble Multiplayer Deathmatch"
   - Description: [Write compelling description]
   - Category: Action, Multiplayer, Physics
   - Tags: marble, multiplayer, deathmatch, physics, sonic
   - Controls: Keyboard + Mouse
   - Orientation: Landscape

4. **Submit for Review**
   - Test the game on CrazyGames preview
   - Check SDK integration works
   - Verify ads display correctly
   - Submit for approval

### Post-Upload Testing

Once uploaded to CrazyGames:

1. **SDK Integration**
   - [ ] Check browser console for SDK initialization
   - [ ] Test user login
   - [ ] Test friends list (with real CrazyGames account)
   - [ ] Test ads display

2. **Gameplay**
   - [ ] Test all game modes
   - [ ] Verify multiplayer works (if server is running)
   - [ ] Check performance on CrazyGames domain
   - [ ] Test on different devices/browsers

3. **Monitor Console**
   - Watch for JavaScript errors
   - Check for SDK warnings
   - Monitor network requests
   - Verify WebSocket connections (if using multiplayer)

## Troubleshooting

### Issue: Game won't load

**Solution**:
- Check browser console for errors
- Verify all files uploaded correctly
- Check MIME types are correct
- Try different browser

### Issue: SDK not initializing

**Solution**:
- Check console for SDK errors
- Verify CrazyGames SDK script is loading
- Test on CrazyGames domain (SDK may not work on other domains)
- Check for CORS errors

### Issue: Multiplayer not working

**Solution**:
- Verify `use_websocket = true` in multiplayer_manager.gd
- Check WebSocket server is running
- Test WebSocket URL in browser console
- Verify CORS headers on server
- Check for mixed content warnings (HTTP vs HTTPS)

### Issue: Poor performance

**Solution**:
- Reduce graphics quality
- Lower particle count
- Reduce physics update rate
- Optimize bot AI (reduce frequency)
- Enable more aggressive compression

### Issue: Audio not playing

**Solution**:
- Check browser audio policy (user interaction required)
- Verify audio files are OGG or MP3
- Check audio import settings
- Test in different browsers

### Issue: Controls not working

**Solution**:
- Check canvas has focus
- Verify input events are captured
- Test with different input devices
- Check for conflicting browser shortcuts

## Export Settings Summary

Current export preset configuration:

```ini
[preset.0]
name="HTML5"
platform="Web"
runnable=true
export_path="build/web/index.html"

[preset.0.options]
variant/thread_support=true
vram_texture_compression/for_desktop=true
html/export_icon=true
html/custom_html_shell="res://scripts/html/full-size.html"
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/ensure_cross_origin_isolation_headers=true
progressive_web_app/orientation=1
```

## Additional Resources

- **Godot Web Export Docs**: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html
- **CrazyGames Developer Docs**: https://docs.crazygames.com/
- **CrazyGames SDK v3**: https://docs.crazygames.com/sdk/html5/
- **WebSocket Server Guide**: See `CRAZYGAMES_DEPLOYMENT.md`

## Support

For issues with:
- **Godot Export**: Check Godot documentation and forums
- **CrazyGames SDK**: Contact CrazyGames developer support
- **Multiplayer**: See `MULTIPLAYER_README.md` and `CRAZYGAMES_DEPLOYMENT.md`

## Final Notes

✅ **The project is now configured for HTML5 export!**

The main steps remaining are:

1. **Export the project** using Godot editor or command line
2. **Test locally** to ensure everything works
3. **Set up WebSocket server** if you want multiplayer (optional)
4. **Update multiplayer settings** to use WebSocket (optional)
5. **Optimize file size** if needed
6. **Upload to CrazyGames** and test
7. **Submit for review**

Good luck with your deployment! 🎮🚀
