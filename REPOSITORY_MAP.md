# Repository Map: Marble Physics Deathmatch

**Version:** Godot 4.5.1 (GL Compatibility - Required for HTML5)
**Genre:** Physics-based Multiplayer Deathmatch
**Platform:** Web (CrazyGames) - PRIMARY, Desktop - SECONDARY

## ⚠️ HTML5 COMPATIBILITY REQUIREMENTS

**This game MUST run in browsers. HTML5 compatibility is the #1 priority!**

**Critical Requirements:**
- ✅ **Renderer:** GL Compatibility (NEVER Forward+ or Mobile)
- ✅ **Networking:** WebSocket for HTML5, ENet desktop only
- ✅ **Audio:** OGG, WAV, MP3 formats only
- ✅ **Performance:** Optimize for 60 FPS in browsers
- ❌ **NO threading** (not supported in HTML5)
- ❌ **NO direct file I/O** (use JavaScriptBridge or user://)
- ❌ **NO ENet for web** (WebSocket only)
- ⚠️ **Bot limit:** Max 7 bots (8 total with player)
- ⚠️ **Shaders:** WebGL2/GLES3 compatible only

**Always check `OS.has_feature("web")` before using platform-specific features!**

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Directory Structure](#directory-structure)
3. [Core Game Systems](#core-game-systems)
4. [Scene Hierarchy](#scene-hierarchy)
5. [Script Reference](#script-reference)
6. [Game Mechanics](#game-mechanics)
7. [GUI & HUD System](#gui--hud-system)
8. [Asset Catalog](#asset-catalog)
9. [Multiplayer & AI](#multiplayer--ai)
10. [Quick Reference](#quick-reference)

---

## Project Overview

### What is This Game?

A **Sonic-inspired physics-based multiplayer deathmatch** where players control marbles with advanced movement (spin dash, bounce attack, rail grinding) and Kirby-style pickup abilities in procedurally generated arenas.

### Key Features

- **Sonic-inspired movement** (spin dash, bounce attack, rail grinding, double jump)
- **Kirby-style abilities** (pickup one at a time, drop on death)
- **Level-up system** (collect orbs for stat boosts, 3 levels max)
- **Deathmatch mode** (5-minute matches, K/D tracking)
- **Multiplayer** (up to 8 players total: you + 7 others, room code-based matchmaking)
- **Advanced Bot AI** (state machine, combat tactics, obstacle avoidance)
- **Dual arena types**
  - **Type A:** Sonic-style with grind rails and floating platforms
  - **Type B:** Quake 3-style with jump pads, teleporters, rooms, corridors
- **Procedural level generation**
- **CrazyGames integration** (profiles, friends, ads)
- **Music playlist system** (auto-load from directory, shuffle)

### Technology Stack

- **Engine:** Godot 4.5.1
- **Language:** GDScript
- **Networking:** WebSocket (browser), ENet (desktop)
- **Physics:** RigidBody3D with force-based movement
- **Rendering:** GL Compatibility (HTML5-required)

---

## Directory Structure

```
/home/user/realmarble2/
├── abilities/                      # Ability scenes
│   ├── dash_attack.tscn
│   ├── explosion.tscn
│   └── sword.tscn
│
├── audio/                          # Sound effects (WAV, OGG, MP3)
│   └── *.wav, *.ogg, *.mp3
│
├── music/                          # Game music
│   └── impulse.mp3
│
├── scripts/                        # All GDScript files
│   ├── abilities/
│   │   ├── ability_base.gd        # Base ability class
│   │   ├── cannon.gd              # Cannon ability (instant-fire explosive projectiles, forward-facing only)
│   │   ├── dash_attack.gd
│   │   ├── explosion.gd
│   │   └── sword.gd
│   │
│   ├── html/
│   │   └── full-size.html         # CrazyGames template
│   │
│   ├── shaders/
│   │   ├── blur.gdshader
│   │   ├── card_glow.gdshader
│   │   ├── marble_shader.gdshader       # Marble visual shader (swirls, bubbles, fresnel)
│   │   ├── plasma_glow.gdshader
│   │   └── procedural_surface.gdshader  # Procedural level geometry shader
│   │
│   ├── ui/
│   │   ├── menu/
│   │   │   ├── options/           # Options menu scripts
│   │   │   ├── pause/             # Pause menu scripts
│   │   │   ├── host_button.gd
│   │   │   ├── menu_card_button.gd
│   │   │   ├── options_button.gd
│   │   │   ├── rl_main_menu.gd
│   │   │   ├── rl_menu_button.gd
│   │   │   ├── rocket_menu.gd
│   │   │   └── sound_generator.gd
│   │   ├── crosshair.gd
│   │   ├── expansion_notification.gd  # Expansion notifications
│   │   ├── fps_counter.gd
│   │   ├── friends_panel.gd
│   │   ├── game_hud.gd
│   │   ├── music_notification.gd
│   │   └── profile_panel.gd
│   │
│   ├── ability_pickup.gd          # Ability pickup logic
│   ├── ability_spawner.gd
│   ├── audio_metadata_parser.gd
│   ├── beam_spawn_effect.gd       # Star Trek-style transporter beam spawn effect
│   ├── bot_ai.gd                  # Advanced bot AI (1,043 lines)
│   ├── camera_occlusion.gd
│   ├── collectible_orb.gd         # Collectible orb logic
│   ├── crazygames_sdk.gd
│   ├── debug_menu.gd              # Debug menu with cheats
│   ├── friends_manager.gd
│   ├── global.gd                  # Global singleton
│   ├── grind_rail.gd
│   ├── level_generator.gd         # Type A arena generator
│   ├── level_generator_q3.gd      # Type B arena generator
│   ├── lobby_ui.gd
│   ├── marble_material_manager.gd # Creates unique marble materials (27 color schemes)
│   ├── multiplayer_manager.gd
│   ├── music_playlist.gd
│   ├── orb_spawner.gd
│   ├── orbit_camera.gd            # Orbiting camera for menus
│   ├── player.gd                  # Player controller (1,695 lines)
│   ├── procedural_material_manager.gd  # Context-aware level geometry materials
│   ├── poof_particle_effect.gd    # Particle effect system
│   ├── profile_manager.gd
│   ├── scoreboard.gd
│   ├── skybox_generator.gd
│   └── world.gd                   # Main game controller (1,646 lines)
│
├── textures/
│   ├── kenney_particle_pack/      # Particle textures
│   └── kenney_prototype_textures/ # Prototype textures
│
├── *.tscn                          # Scene files (root)
│   ├── world.tscn                 # Main game scene
│   ├── marble_player.tscn         # Player marble prefab
│   ├── rl_main_menu.tscn          # Main menu
│   ├── lobby_ui.tscn              # Multiplayer lobby
│   ├── scoreboard.tscn
│   ├── collectible_orb.tscn
│   ├── ability_pickup.tscn
│   ├── debug_menu.tscn            # Debug menu overlay
│   ├── menu_card_button.tscn      # Menu button prefab
│   ├── rl_menu_button.tscn        # Another menu button variant
│   └── rocket_league_menu.tscn    # Alternative menu scene
│
├── *.md                            # Documentation
│   ├── REPOSITORY_MAP.md          # This file
│   ├── MULTIPLAYER_README.md      # Networking guide
│   ├── MUSIC_PLAYLIST.md          # Music system docs
│   ├── ROCKET_LEAGUE_MENU.md      # Menu system overview
│   ├── STYLE_GUIDE.md             # UI design standards
│   ├── CRAZYGAMES_DEPLOYMENT.md   # Deployment guide
│   ├── EXPORT_INSTRUCTIONS.md     # HTML5 export guide
│   └── RENDERER_COMPATIBILITY.md  # GL Compatibility migration guide
│
├── default_bus_layout.tres         # Audio bus configuration
├── world.tres                      # World configuration resource
├── icon.svg                        # Project icon
├── LICENSE                         # Project license
├── .gitignore                      # Git ignore rules
├── .gitattributes                  # Git configuration
└── project.godot                   # Main project config
```

---

## Core Game Systems

### 1. Physics & Movement System

**Location:** `scripts/player.gd`
**Implementation:** Force-based RigidBody3D physics

**Core Mechanics:**

| Mechanic | Key | Description | Cooldown |
|----------|-----|-------------|----------|
| **Rolling** | WASD | Force-based movement, camera-relative | None |
| **Jump** | Space | Standard jump + double jump | None |
| **Spin Dash** | Shift (hold) | Charge & release dash toward camera | 0.8s |
| **Bounce Attack** | Ctrl | Plunge down, bounce up on impact | 0.3s |
| **Rail Grinding** | E | Attach to rails, gravity affects speed | None |

**Physics Properties:**
```gdscript
Mass: 8.0          # Dense marbles
Gravity: 2.5x      # Stronger than default
Speed: 80.0        # Base movement speed
Jump Force: 25.0   # Base jump impulse
Spin Dash: 100.0 + (charge * 400.0)  # Up to 500.0
Bounce: 150.0 * multiplier  # Up to 3x consecutive
```

### 2. Level-Up System

**Trigger:** Collect orbs
**Max Level:** 3
**Reset:** On death

| Level | Speed | Jump | Spin Dash | Bounce |
|-------|-------|------|-----------|--------|
| 1 | +20 | +15 | +50 | +20 |
| 2 | +40 | +30 | +100 | +40 |
| 3 | +60 | +45 | +150 | +60 |

**Orbs drop on death and are placed on the ground.**

### 3. Ability System (Kirby-Style)

**Location:** `scripts/abilities/`

**Available Abilities:**

| Ability | Type | Damage | Special |
|---------|------|--------|---------|
| **Cannon** | Ranged | 1 | Instant-fire explosive projectiles, forward-facing only, 1.5s cooldown |
| **Dash Attack** | Melee | 1-3 | Forward dash with damage scaling |
| **Explosion** | AoE | 2-4 | Radius scales with charge |
| **Sword** | Melee | 1-3 | Swing attack with AoE at max charge |

**Charging System:**
- Hold **E** to charge (3 levels: weak, medium, max) - for abilities that support charging
- Visual: Particle effects grow with charge
- Release **E** to fire (or tap **E** for instant-fire abilities like Cannon)
- Press **O** to drop ability
- **Note:** Cannon fires instantly without charging

**Behavior:**
- Can only hold one ability at a time
- Pickup replaces current ability
- Automatic drop on death
- Random spawning via `ability_spawner.gd`

### 4. Combat & Health

**Health:** 3 hits
**Death Triggers:**
- Health reaches 0
- Fall below Y = -20.0 (Type A) or Y = -50.0 (Type B)

**Death Consequences:**
- Drop ability
- Drop orbs (lose all level progress)
- Explosion particle effect
- Respawn after 3 seconds

**Scoring:**
- Kill: +1 point
- Death: +1 death count
- K/D ratio calculated and displayed

### 5. Level Generation

#### Type A: Sonic-Style Arena (`level_generator.gd`)

**Elements:**
- 100x100 main floor
- 24 floating platforms (varied heights)
- 12 ramps
- 12 grind rails (8 curved perimeter + 4 vertical/spiral)
- 4 perimeter walls
- 16 spawn points (for up to 8 players)

#### Type B: Quake 3 Arena (`level_generator_q3.gd`)

**Elements:**
- 84x84 main arena floor with pillars and cover
- **3-tier platforms:** Tier 1 (4 large @ height 8), Tier 2 (8 medium @ height 15), Tier 3 (4 small @ height 22)
- **4 side rooms** with doorways (16x10x16 units each)
- **4 connecting corridors**
- **5 jump pads** (green, boost force 300.0)
- **4 teleporters** (blue/purple, 2 bidirectional pairs)
- Taller perimeter walls (25 units)
- 16+ spawn points (for up to 8 players)

**Arena Selection:** Players choose type in pre-game menu via `scripts/world.gd:current_level_type`

### 6. Jump Pads (Type B Only)

**Location:** `scripts/player.gd:activate_jump_pad()` (lines 2083-2116)

**Properties:**
- Visual: Bright green glowing cylinder
- Boost: 300.0 vertical force
- Cooldown: 1.0 second
- Effect: Cancels horizontal velocity, applies upward impulse

**Locations:** Center + 4 corners (NE, NW, SE, SW at ±30 units)

### 7. Teleporters (Type B Only)

**Location:** `scripts/player.gd:activate_teleporter()` (lines 2118-2146)

**Properties:**
- Visual: Blue/purple glowing cylinder
- Cooldown: 2.0 seconds
- Behavior: Instant teleport, preserves vertical velocity, cancels horizontal

**Pairs:**
- Pair 1: (35, 0, 35) ↔ (-35, 0, -35)
- Pair 2: (-35, 0, 35) ↔ (35, 0, -35)

### 8. Multiplayer System

**Location:** `scripts/multiplayer_manager.gd`

**Network Modes:**
- **WebSocket:** HTML5/browser (REQUIRED for web)
- **ENet:** Desktop only (NOT supported in HTML5)

**Features:**
- Room codes (6-character alphanumeric, e.g., "A3X9K2")
- Lobby system (create, join, quick play)
- Up to 8 players per match (you + 7 bots/others)
- Ready system (all players must ready before start)
- Host controls (add bots, start game)
- Host migration support

**See:** `MULTIPLAYER_README.md` for full details

### 9. Bot AI System

**Location:** `scripts/bot_ai.gd` (1,043 lines)

**State Machine:**
```
WANDER → CHASE → ATTACK
   ↑       ↑        ↓
   └─── RETREAT ←──┘
          ↓
  COLLECT_ABILITY / COLLECT_ORB
```

**AI Features:**
- **Combat tactics:** Ability-specific optimal ranges, strafing, charging
- **Obstacle avoidance:** Edge detection, wall detection, stuck recovery
- **Target prioritization:** Abilities > Combat > Orbs > Wander
- **Personality variety:** Randomized aggression and reaction times

**Optimal Combat Ranges:**
- Sword: 2-5 units (melee)
- Dash: 5-10 units (melee dash)
- Explosion: 3-8 units (AoE)
- Cannon: 8-15 units (forward-facing only, 120° cone)

### 10. Menu System

**Location:** `scripts/ui/menu/`

**Features:**
- Rocket League-style animated menu
- Profile panel (stats, XP, login)
- Friends panel (online status, invites)
- Options menu (fullscreen, sensitivity)
- Pause menu
- Orbiting camera
- Plasma glow shader on logo

**See:** `ROCKET_LEAGUE_MENU.md` and `STYLE_GUIDE.md`

### 11. CrazyGames Integration

**Location:** `scripts/crazygames_sdk.gd`

**SDK Features:**
- JavaScript bridge (HTML5 only via JavaScriptBridge)
- User authentication
- Profile system (via `profile_manager.gd`)
- Friends system (via `friends_manager.gd`)
- Ad support (midgame, rewarded, banner)
- Game events (gameplayStart, gameplayStop, happyTime)

**Mock Mode:** Works locally without SDK for testing

**See:** `CRAZYGAMES_DEPLOYMENT.md`

### 12. Music System

**Location:** `scripts/music_playlist.gd`

**Features:**
- Auto-load MP3/OGG files from music directory
- Shuffle mode
- Track metadata display
- Seamless transitions
- Menu vs gameplay music

**See:** `MUSIC_PLAYLIST.md`

### 13. Debug System

**Location:** `scripts/debug_menu.gd`, `debug_menu.tscn`

**Features:**
- Paginated debug menu (3 pages)
- God mode toggle
- Collision shape visibility
- Speed multiplier
- Bot spawning/removal
- Force respawn
- Toggle with backtick (`)

### 14. Visual Systems

#### Marble Material Manager (`marble_material_manager.gd`)

**Purpose:** Creates unique, beautiful marble materials for each player

**Features:**
- 27 predefined color schemes (Ruby Red, Sapphire Blue, Emerald Green, etc.)
- Procedural marble patterns using custom shader
- Automatic color distribution to avoid duplicates
- Hue-based material generation
- Randomized properties (glossiness, swirl scale, bubble density)

**Color Schemes Include:**
- Vibrant primaries (red, blue, green, purple, orange, pink, cyan, yellow)
- Pure colors (blood red, deep blue, poison green)
- Dark tones (midnight black, navy blue, chocolate brown)
- Pastels and uniques (salmon pink, jade green, lavender, mint green)
- Metallics (bright gold, chrome silver)
- Electric colors (magenta, lime, teal, indigo)

**Usage:** `create_marble_material(index)` or `get_random_marble_material()`

#### Procedural Material Manager (`procedural_material_manager.gd`)

**Purpose:** Applies context-aware procedural materials to level geometry

**Material Presets:**
- **Floor:** Cool gray, industrial look
- **Wall:** Warm concrete texture
- **Platform:** Blue-gray metallic
- **Ramp:** Rust/copper finish
- **Pillar:** Dark stone texture
- **Cover:** Military gray-brown
- **Room Floor:** Cool industrial (for Type B rooms)
- **Room Wall:** Tech facility look
- **Corridor:** Neutral industrial

**Shader Properties:**
- Triplanar mapping for seamless textures
- Fractal Brownian Motion (FBM) for complex patterns
- Voronoi cellular patterns
- Wear/weathering effects
- Dynamic roughness and metallic properties
- Normal map detail

**Usage:** `apply_material_by_name(mesh)` or `apply_materials_to_level(generator)`

#### Beam Spawn Effect (`beam_spawn_effect.gd`)

**Purpose:** Star Trek-style transporter beam effect for player spawning

**Features:**
- Rising column of light particles
- Secondary glow particles for enhanced effect
- Additive blending for bright appearance
- HTML5-optimized (reduced particle counts)
- Auto-cleanup after effect completes
- Blue-white color scheme

**Properties:**
- Main beam: 50 particles, 1.0s lifetime
- Glow particles: 25 particles, 1.0s lifetime
- Upward velocity with convergence
- Scale curves for smooth fade in/out

**Usage:** `play_at_position(pos)` - plays beam at position and auto-destroys

---

## Scene Hierarchy

### Main Game Scene (`world.tscn`)

```
World (Node3D) [scripts/world.gd]
├── WorldEnvironment
├── DirectionalLight3D
├── MenuSystem (CanvasLayer)
│   ├── RLMainMenu (AnimatedLogo, PlayButton, MultiplayerButton, ProfilePanel, FriendsPanel)
│   ├── PauseMenu
│   └── OptionsMenu
├── UI (CanvasLayer)
│   ├── GameHUD
│   ├── Scoreboard
│   ├── LobbyUI
│   ├── Crosshair
│   ├── FPSCounter
│   └── MusicNotification
├── MenuMusicPlayer
├── GameplayMusicPlayer
├── LevelGenerator (Type A or Type B)
├── SkyboxGenerator
├── AbilitySpawner
├── OrbSpawner
└── Players (container for MarblePlayer instances)
```

### Player Marble Scene (`marble_player.tscn`)

```
MarblePlayer (RigidBody3D) [scripts/player.gd]
├── CollisionShape3D
├── MeshInstance3D
├── Camera3D
│   └── CameraOcclusion [scripts/camera_occlusion.gd]
├── GroundDetector (RayCast3D)
├── AudioPlayers (jump, spin, bounce, hit, death)
├── Particles (death, collection, trails)
├── SpotLight3D
├── AnimationPlayer
├── MultiplayerSynchronizer
└── AbilityAttachPoint
```

### Ability Scenes (e.g., `abilities/sword.tscn`)

```
Sword (Node3D) [scripts/abilities/sword.gd]
├── MeshInstance3D
├── AnimationPlayer
├── HitArea (Area3D)
│   └── CollisionShape3D
└── ParticleEffects
```

---

## Script Reference

### Core Scripts

| Script | Lines | Purpose |
|--------|-------|---------|
| `global.gd` | - | Global singleton (settings, persistence) |
| `world.gd` | 1,646 | Main game controller, match logic, menu system |
| `player.gd` | 1,695 | Player physics, movement, abilities, health |
| `bot_ai.gd` | 1,043 | Advanced bot AI state machine |
| `multiplayer_manager.gd` | - | WebSocket/ENet networking, room management |
| `level_generator.gd` | - | Type A arena generation |
| `level_generator_q3.gd` | 765 | Type B arena generation |

### Ability Scripts

| Script | Purpose |
|--------|---------|
| `abilities/ability_base.gd` | Base class (charging, cooldown) |
| `abilities/cannon.gd` | Explosive projectile weapon |
| `abilities/dash_attack.gd` | Forward dash attack |
| `abilities/explosion.gd` | AoE explosion |
| `abilities/sword.gd` | Melee sword swings |

### UI Scripts

| Script | Purpose |
|--------|---------|
| `ui/game_hud.gd` | In-game HUD (health, timer, score) |
| `ui/crosshair.gd` | Dynamic crosshair |
| `ui/fps_counter.gd` | FPS display |
| `ui/profile_panel.gd` | Profile stats, XP, login |
| `ui/friends_panel.gd` | Friends list with online status |
| `ui/music_notification.gd` | Track name display |
| `ui/expansion_notification.gd` | Expansion notifications |
| `ui/menu/rocket_menu.gd` | Main menu controller |
| `ui/menu/rl_main_menu.gd` | Main menu scene controller |
| `ui/menu/sound_generator.gd` | Procedural UI sounds |

### Utility Scripts

| Script | Purpose |
|--------|---------|
| `ability_pickup.gd` | Ability pickup logic (bobbing, respawn) |
| `ability_spawner.gd` | Manages ability pickup spawning |
| `audio_metadata_parser.gd` | Audio file metadata extraction |
| `beam_spawn_effect.gd` | Star Trek-style transporter beam spawn effect |
| `camera_occlusion.gd` | Camera anti-clipping |
| `collectible_orb.gd` | Orb pickup logic |
| `crazygames_sdk.gd` | CrazyGames SDK bridge |
| `debug_menu.gd` | Debug menu with cheats |
| `friends_manager.gd` | Friends system manager |
| `grind_rail.gd` | Rail grinding mechanics |
| `lobby_ui.gd` | Multiplayer lobby interface |
| `marble_material_manager.gd` | Creates unique marble materials (27 schemes) |
| `music_playlist.gd` | Music playlist system |
| `orbit_camera.gd` | Orbiting camera for menus |
| `orb_spawner.gd` | Manages orb spawning |
| `poof_particle_effect.gd` | Particle effect system |
| `procedural_material_manager.gd` | Context-aware level geometry materials |
| `profile_manager.gd` | User profile management |
| `scoreboard.gd` | Scoreboard display |
| `skybox_generator.gd` | Procedural skybox generation |

---

## Game Mechanics

### Movement Controls

| Key | Action | Notes |
|-----|--------|-------|
| WASD | Move | Camera-relative |
| Mouse | Look | Adjust camera |
| Space | Jump | Double jump available |
| Shift (hold) | Spin Dash | Charge up to 1.5s |
| Ctrl | Bounce Attack | Plunge + bounce |
| E (tap) | Use Ability | Fire at current charge |
| E (hold) | Charge Ability | Up to 3 levels |
| O | Drop Ability | Manual drop |
| F | Force Respawn | Debug only |
| Tab (hold) | Scoreboard | Show K/D ratios |
| Esc | Pause | Open pause menu |
| ` (backtick) | Debug Menu | Toggle debug overlay |

### Type B Arena Mechanics

| Mechanic | Visual | Effect |
|----------|--------|--------|
| **Jump Pads** | Bright green cylinder | Vertical boost (300 force), 1s cooldown |
| **Teleporters** | Blue/purple cylinder | Instant teleport, 2s cooldown |

### Deathmatch Rules

- **Duration:** 5 minutes
- **Victory:** Most kills
- **Countdown:** 3 seconds ("READY", "SET", "GO!")
- **Match End:** 10-second scoreboard, return to menu

### Physics Formulas

```gdscript
# Movement
force = direction * (speed + level_bonus)

# Jump
impulse = Vector3.UP * (jump_force + level_bonus)

# Spin Dash
force = dash_dir * (spin_dash_force + level_bonus + charge * 400.0)

# Bounce Attack
down_force = Vector3.DOWN * 300.0
up_impulse = Vector3.UP * bounce_impulse * bounce_multiplier  # Up to 3x
```

### XP and Leveling (Profile System)

**XP Sources:**
- Kill: +100 XP
- Win match: +500 XP
- Match participation: +50 XP

**Level Requirements:**
- Level 2: 500 XP
- Level 3: 1,500 XP
- Level 4: 3,000 XP
- Level 5: 5,000 XP
- (Continues scaling)

**Note:** Profile XP is separate from match level-up orbs!

---

## GUI & HUD System

### In-Game HUD (`scripts/ui/game_hud.gd`)

**Location:** GameHUD/HUD node in world scene
**Purpose:** Real-time player information and notifications during gameplay

#### Core HUD Elements

| Element | Display | Update Rate |
|---------|---------|-------------|
| **Timer** | Match time remaining (MM:SS) | Real-time |
| **Kills** | Player's kill count | Per kill |
| **Level** | Current level / max level (0-3) | Per orb collected |
| **Health** | Current health points (0-3) | Per damage taken |
| **Ability** | Current ability + cooldown/ready status | Real-time |

#### Kill Notification System

**Visual:** Red text with skull symbol (💀)
**Position:** Center of screen (anchors 0.3-0.7 horizontal, 0.4-0.45 vertical)
**Duration:** 2 seconds with fade-out effect
**Trigger:** Every kill (direct damage or knockoff)

**Format:**
- Bots: `💀 Bot`
- Players: `💀 Player X`

**Implementation:**
```gdscript
# Called from player.gd when kill is confirmed
game_hud.show_kill_notification(victim_name)
```

**Features:**
- Displays immediately upon kill
- Fades out in last 0.5 seconds
- Only visible to the player who earned the kill
- Works in both practice and multiplayer modes

#### Killstreak Notification System

**Visual:** Large golden text with pulse animation
**Position:** Top-center of screen (anchor_top: 0.25)
**Duration:** 3 seconds with pulse + fade effects
**Trigger:** 5 and 10 kill milestones

**Messages:**
- **5 kills:** "KILLING SPREE!"
- **10 kills:** "UNSTOPPABLE!"
- **Other:** "KILLSTREAK: X" (fallback)

**Animation Effects:**
- Pulse: Oscillating scale (1.0 ± 0.1) at 3 Hz
- Fade: Linear fade in last 1 second

**Implementation:**
```gdscript
# Called from player.gd when killstreak milestone reached
if attacker.killstreak == 5 or attacker.killstreak == 10:
    game_hud.show_killstreak_notification(attacker.killstreak)
```

#### Expansion Notification System

**Visual:** Gold text with flash effect
**Position:** Top-wide (anchor_top: 0.15)
**Duration:** 5 seconds with oscillating alpha
**Trigger:** Called by world.gd for level expansions

**Text:** "NEW AREA AVAILABLE"

#### Killstreak Tracking (`scripts/player.gd`)

**Variables:**
```gdscript
var killstreak: int = 0                 # Current consecutive kills
var last_attacker_id: int = -1         # ID of last attacker
var last_attacker_time: float = 0.0    # Timestamp of last attack
const ATTACKER_TIMEOUT: float = 5.0    # Knockoff credit window
```

**Features:**
- Tracks consecutive kills without dying
- Resets to 0 on death (respawn)
- Increments on direct damage kills
- Increments on knockoff kills (within 5-second window)

**Knockoff Kill System:**
- Tracks last player who damaged you
- 5-second timeout window for knockoff credit
- If you fall off stage within timeout, attacker gets kill credit
- Properly resets on respawn or timeout

**Example Flow:**
1. Player A damages Player B → `last_attacker_id = A`, `last_attacker_time = current_time`
2. Player B falls off stage 3 seconds later
3. `fall_death()` checks: `(current_time - last_attacker_time) <= 5.0` → TRUE
4. Player A gets kill credit and killstreak increment
5. Kill notification shows on Player A's screen

### HUD Path Structure

**IMPORTANT:** The HUD is accessed via `"GameHUD/HUD"` path (defined in world.gd line 11)

**Correct Usage:**
```gdscript
var world = get_parent()
var game_hud = world.get_node_or_null("GameHUD/HUD")
if game_hud:
    game_hud.show_kill_notification(victim_name)
```

**Incorrect Usage:**
```gdscript
# ❌ WRONG - UI/GameHUD doesn't exist
var ui_layer = world.get_node_or_null("UI")
var game_hud = ui_layer.get_node_or_null("GameHUD")
```

### HUD Visibility States

| Game State | HUD Visible | Elements Shown |
|------------|-------------|----------------|
| Menu | Hidden | None |
| Match Active | Visible | All core elements + notifications |
| Paused | Visible | Background only (pause menu overlays) |
| Match End | Hidden | Scoreboard replaces HUD |

### Debug Output

All HUD notifications include debug prints for troubleshooting:
```
[KILL] Looking for attacker node: 1 - Found: true
[KILL] Attacker killstreak is now: 1
[NOTIFY_KILL] Called with killer_id: 1, victim_id: 9009
[NOTIFY_KILL] GameHUD found: true
[HUD] show_kill_notification called with: Bot
[HUD] Kill notification shown - visible: true, text: 💀 Bot
```

---

## Asset Catalog

### Audio Files

#### Sound Effects (`audio/`)

All sound effects use web-compatible formats (WAV, OGG, MP3).

**Key Files:**
- Jump: `jump.mp3`, `nr_name26.dsp.wav`, `nr_name2c.dsp.wav`
- Spin: `017.Synth_MLT_se_ch_sn_Spindash Charge with Ancient Light Begin.wav`, `017.Synth_MLT_se_ch_sn_Spindash Charge with Ancient Light Loop.wav`, `revup.mp3`
- Bounce: `SonicBOUNCE.wav`, `bouncehard2.wav`
- Hit: `hitmarker_2.mp3`, `011.Synth_MLT_se_ch_kn_punch.wav`
- Death: `KO'ed.wav`
- Spawn: `spawn.wav`
- Orb: `Ring.wav`, `ChaosDrive.wav`
- Ability pickup: (various)
- Projectile: `Fox - Laser Gun.wav`, `Raygun.wav`, `Shooting.wav`
- Sword: `Small Sword Hit.wav`, `Moderate Sword Hit.wav`, `Strong Sword Smack.wav`
- Explosion: `Explosion.wav`, `017.Synth_MLT_se_ac_bf_metallic explode.wav`
- UI/Effects: `645317__darkshroom__m9_noisegate-1780.ogg`

#### Music (`audio/`, `music/`)

- Menu: `661248__magmadiverrr__video-game-menu-music.ogg`
- Gameplay: `impulse.mp3`
- Custom: User-specified directory (MP3/OGG/WAV)

### Textures (`textures/`)

- **Kenney Particle Pack:** `circle_05.png` (crosshair, particles), `star_05.png` (effects)
- **Kenney Prototype Textures:** Orange, dark, grid patterns for platforms/walls

### Shaders (`scripts/shaders/`)

All shaders are WebGL2/GLES3 compatible:
- `plasma_glow.gdshader` - Animated plasma glow (menu logo)
- `card_glow.gdshader` - Button glow effect
- `blur.gdshader` - Blur effect
- `marble_shader.gdshader` - Marble visual shader with swirls, bubbles, fresnel effects, and emission
- `procedural_surface.gdshader` - Procedural level geometry shader with triplanar mapping, FBM noise, and voronoi patterns

---

## Multiplayer & AI

### Network Topology

```
Host (Peer 1)
├─ Authority over game state
├─ Spawns players/bots
├─ Runs match timer
├─ Syncs kills/deaths
└─ Can add bots

Clients (Peer 2-16)
├─ Control own player
├─ Receive game state updates
├─ Send input to host
└─ Spectate if dead
```

### Room System

**Creation:** Host calls `create_room()` → Server generates 6-char code → Room added to list

**Joining:** Client enters code → Server validates → Client joins lobby

**Quick Play:** Find available room (<8 players) or create new

### Lobby Flow

1. Display room code (host only)
2. Show player list with ready status
3. All players click "Ready"
4. Host clicks "Start" (requires all ready)
5. Match begins

### Synchronization

- **Position/rotation:** MultiplayerSynchronizer (20 Hz)
- **Health/level/score:** RPC calls
- **Ability usage:** RPC calls
- **Match timer:** Host-authoritative
- **Game state:** RPC to all clients

### Bot AI Summary

**State Priority:**
1. **COLLECT_ABILITY** (critical - can't fight without one)
2. **ATTACK** (in optimal range with ability)
3. **CHASE** (target nearby, has ability)
4. **RETREAT** (health < 2, no ability)
5. **COLLECT_ORB** (has ability, low priority)
6. **WANDER** (default state)

**Combat Effectiveness:**
- Uses abilities intelligently (70% charge rate)
- Avoids obstacles and edges
- Varied aggression levels
- Reaction delay (0.5-1.5s) for fairness

---

## Quick Reference

### Key File Locations

| Need | Location |
|------|----------|
| Player movement | `player.gd:_physics_process()` |
| Spin dash | `player.gd:_spin_dash()` (~400) |
| Bounce attack | `player.gd:bounce_attack()` (~500) |
| Rail grinding | `grind_rail.gd`, `player.gd:_on_grind_rail_entered()` |
| Health/damage | `player.gd:take_damage()`, `die()` |
| Level-up | `player.gd:_on_collectible_orb_collected()` (~800) |
| Ability system | `abilities/ability_base.gd` |
| Bot AI | `bot_ai.gd` |
| Multiplayer | `multiplayer_manager.gd` |
| Match logic | `world.gd` |
| Type A arena | `level_generator.gd` |
| Type B arena | `level_generator_q3.gd` |
| Jump pads | `player.gd:activate_jump_pad()` (2083-2116) |
| Teleporters | `player.gd:activate_teleporter()` (2118-2146) |
| Main menu | `ui/menu/rocket_menu.gd` |
| CrazyGames | `crazygames_sdk.gd` |
| Profile | `profile_manager.gd` |
| Music | `music_playlist.gd` |
| Marble materials | `marble_material_manager.gd` |
| Level materials | `procedural_material_manager.gd` |
| Spawn effects | `beam_spawn_effect.gd` |

### Common Tasks

**Add New Ability:**
1. Duplicate existing ability scene in `abilities/`
2. Create script in `scripts/abilities/` extending `ability_base.gd`
3. Implement `activate()` function
4. Add to spawner pool in `ability_spawner.gd`

**Modify Physics:**
1. Open `player.gd`
2. Edit physics variables at top (lines 20-50)
3. Test in-game

**Change Match Duration:**
1. Open `world.gd`
2. Edit `match_duration` variable (~50)

**Add Bot Behavior:**
1. Open `bot_ai.gd`
2. Add state to `AIState` enum
3. Implement logic in `_physics_process()`
4. Add transitions

**Customize Level Generation:**
- **Type A:** Edit `level_generator.gd` (platforms, rails, ramps)
- **Type B:** Edit `level_generator_q3.gd` (tiers, rooms, pads, teleporters)

**Switch Default Arena:**
1. Open `world.gd`
2. Change `generate_procedural_level("A")` to `"B"` (line ~96)

### Debug Tools

**Enable Debug:**
- Press ` (backtick) to toggle debug overlay

**Debug Features:**
- God mode
- Collision shape visibility
- Speed multiplier
- Bot spawning
- FPS counter
- Player position/velocity
- AI state display

### Architecture Decisions

**Why Force-Based Movement?**
- Sonic-inspired instant response
- Better game feel than realistic rolling
- Less CPU-intensive for browsers

**Why Room Codes?**
- Friends can easily play together
- No matchmaking server needed
- Quick Play button available for solo players

**Why Procedural Generation?**
- Variety and replayability
- No asset creation needed
- Happens once at match start (minimal web impact)

**Why Kirby-Style Abilities?**
- Encourages map movement
- Dynamic risk/reward gameplay
- No complex loadout UI (faster loading)

**Why GL Compatibility?**
- HTML5 export REQUIRES it
- Works in all web browsers via WebGL2
- Non-negotiable for web deployment

---

## Documentation Files

- **REPOSITORY_MAP.md** - This file (comprehensive overview)
- **MULTIPLAYER_README.md** - Detailed networking guide
- **MUSIC_PLAYLIST.md** - Music system documentation
- **ROCKET_LEAGUE_MENU.md** - Menu system overview
- **STYLE_GUIDE.md** - UI design standards
- **CRAZYGAMES_DEPLOYMENT.md** - Deployment guide
- **EXPORT_INSTRUCTIONS.md** - HTML5 export step-by-step
- **RENDERER_COMPATIBILITY.md** - GL Compatibility migration details

---

## Key Strengths

✅ **Advanced game systems** (physics, AI, networking, procedural generation)
✅ **Excellent code organization** (modular, well-documented)
✅ **Modern Godot 4 practices** (signals, autoloads, scenes)
✅ **Production ready** (CrazyGames integration, deployment guides)
✅ **HTML5 compatible** (WebSocket, GL Compatibility, optimized)

---

**Last Updated:** 2026-01-19
**Godot Version:** 4.5.1 (GL Compatibility)
**Primary Platform:** HTML5/Web (CrazyGames)

---

**Remember:** This is a web-first game. Always verify HTML5 compatibility before making changes!
