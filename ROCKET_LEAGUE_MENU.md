# Rocket League-Style Main Menu

This project now features a completely revamped main menu inspired by Rocket League's homescreen.

## Features

### Visual Elements
- **Animated Logo**: Top-centered logo with plasma glow shader effect that pulses and animates
- **Glowing Card Buttons**: Large, Rocket League-style menu buttons with:
  - Neon glow edges that pulse
  - Scale-up hover effect (105% on hover/focus)
  - Smooth animations
  - "Play" button is extra large for emphasis
- **XP Progress Bar**: Bottom-aligned progress bar showing level and XP
  - Animated fill effect
  - Clean, modern design

### Menu Options
- **PLAY** - Start practice mode with bots (extra large button)
- **MULTIPLAYER** - Join online games
- **GARAGE** - (Placeholder)
- **PROFILE** - (Placeholder)
- **ITEM SHOP** - (Placeholder)
- **SEASON PASS** - (Placeholder)
- **SETTINGS** - Opens settings menu
- **QUIT** - Exit game

### Camera System
- **Orbiting Camera**: Slow, cinematic orbit around the 3D arena
  - 15-unit radius orbit
  - 5-unit height with vertical bob
  - Smooth circular motion
  - Always looks at center of arena

### Input Controls
- **Keyboard**: Arrow keys (up/down) to navigate, Enter to select
- **Gamepad**: D-pad or left stick to navigate, A button to select
- **Mouse**: Click or hover over buttons

### Audio
- Procedurally generated placeholder sound effects:
  - Hover sound: 800Hz beep with fade-out
  - Select sound: Pitch-sweep from 600Hz to 800Hz

### Preserved Features
- All existing 3D world and procedural arena generation
- Background blur shader effect
- Menu music system
- Settings/options menu
- Multiplayer functionality

## File Structure

```
scripts/
├── orbit_camera.gd                    # Orbiting camera controller
├── shaders/
│   ├── plasma_glow.gdshader          # Logo animation shader
│   └── card_glow.gdshader            # Button glow shader
└── ui/menu/
    ├── rocket_menu.gd                # Main menu controller
    ├── menu_card_button.gd           # Card button component
    └── sound_generator.gd            # Procedural sound effects

rocket_league_menu.tscn               # Main menu scene
menu_card_button.tscn                 # Reusable button component
```

## Technical Details

### Shaders
- **plasma_glow.gdshader**: Creates animated plasma effect with configurable colors and animation speed
- **card_glow.gdshader**: Edge-based glow with pulsing effect, responds to hover state

### Navigation System
- Focus-based navigation using `ui_up`, `ui_down`, and `ui_accept` input actions
- Smooth transitions between menu items
- Visual feedback for focused/hovered items

### Integration
The menu is integrated into `world.tscn` and connects to the existing game flow:
- Play button → Practice mode with bots
- Multiplayer button → Multiplayer lobby
- Settings button → Options menu
- Quit button → Exit game

## Customization

To customize the menu:
1. Edit shader parameters in `rocket_league_menu.tscn`
2. Modify button text in the scene's button nodes
3. Adjust camera orbit parameters in the DollyCamera node
4. Change XP values in `rocket_menu.gd`
