# Repository Map: Marble Physics Deathmatch (Godot 4.5.1)

**Version:** Godot 4.5.1 (GL Compatibility Renderer)
**Genre:** Physics-based Multiplayer Deathmatch
**Inspiration:** Sonic Adventure 2 movement + Kirby ability system
**Platform:** Web (CrazyGames), Desktop

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Directory Structure](#directory-structure)
3. [Core Game Systems](#core-game-systems)
4. [Scene Hierarchy](#scene-hierarchy)
5. [Script Reference](#script-reference)
6. [Game Mechanics](#game-mechanics)
7. [Asset Catalog](#asset-catalog)
8. [Multiplayer Architecture](#multiplayer-architecture)
9. [AI System](#ai-system)
10. [Quick Reference](#quick-reference)

---

## Project Overview

### What is This Game?

A **Sonic-inspired physics-based multiplayer deathmatch game** where players control marbles with advanced movement mechanics (spin dash, bounce attack, rail grinding) and Kirby-style pickup abilities in procedurally generated arenas.

### Key Features

- ✅ **Sonic-inspired movement** (spin dash, bounce attack, rail grinding, double jump)
- ✅ **Kirby-style abilities** (pickup one at a time, drop on death)
- ✅ **Level-up system** (collect orbs for stat boosts, 3 levels max)
- ✅ **Deathmatch mode** (5-minute matches, K/D tracking)
- ✅ **Multiplayer** (up to 16 players, room code-based matchmaking)
- ✅ **Advanced Bot AI** (state machine, combat tactics, obstacle avoidance)
- ✅ **Procedural level generation** (platforms, ramps, grind rails)
- ✅ **CrazyGames integration** (profiles, friends, ads)
- ✅ **Music playlist system** (auto-load from directory, shuffle)

### Technology Stack

- **Engine:** Godot 4.5.1 (GL Compatibility)
- **Language:** GDScript
- **Networking:** WebSocket (browser), ENet (desktop)
- **Physics:** RigidBody3D with force-based movement
- **Rendering:** GL Compatibility (for web compatibility)

---

## Directory Structure

```
/home/user/realmarble2/
├── abilities/                      # Ability scene files (.tscn)
│   ├── dash_attack.tscn           # Dash attack ability
│   ├── explosion.tscn             # AoE explosion ability
│   ├── gun.tscn                   # Ranged projectile weapon
│   └── sword.tscn                 # Melee sword ability
│
├── audio/                          # Sound effects
│   ├── *.wav, *.ogg, *.mp3        # Jump, spin, bounce, hit, death sounds
│   └── 661248__magmadiverrr__video-game-menu-music.ogg  # Menu music
│
├── music/                          # Game music files
│   └── impulse.mp3                # Default gameplay track
│
├── scripts/                        # All GDScript files
│   ├── abilities/                 # Ability system scripts
│   │   ├── ability_base.gd       # Base ability class (charging, cooldown)
│   │   ├── dash_attack.gd        # Dash attack implementation
│   │   ├── explosion.gd          # Explosion ability implementation
│   │   ├── gun.gd                # Gun ability implementation
│   │   └── sword.gd              # Sword ability implementation
│   │
│   ├── html/                      # HTML templates for web export
│   │   └── crazygames_template.html  # CrazyGames SDK integration
│   │
│   ├── shaders/                   # Custom shader files
│   │   └── plasma_glow.gdshader  # Animated plasma glow effect
│   │
│   ├── ui/                        # UI-related scripts
│   │   ├── menu/                 # Menu system
│   │   │   ├── options/          # Options submenu scripts
│   │   │   └── pause/            # Pause menu scripts
│   │   ├── crosshair.gd          # Dynamic crosshair
│   │   ├── fps_counter.gd        # FPS display
│   │   ├── friends_panel.gd      # Friends list panel
│   │   ├── game_hud.gd           # In-game HUD
│   │   ├── music_notification.gd # Track name notifications
│   │   ├── profile_panel.gd      # Profile panel (stats, XP, login)
│   │   ├── rl_menu_button.gd     # Menu button behavior
│   │   ├── rocket_menu.gd        # Main menu controller
│   │   └── sound_generator.gd    # Procedural UI sounds
│   │
│   ├── audio_metadata_parser.gd  # Audio file metadata parser
│   ├── bot_ai.gd                 # Advanced bot AI (1,043 lines)
│   ├── camera_occlusion.gd       # Camera anti-clipping
│   ├── crazygames_sdk.gd         # CrazyGames SDK bridge
│   ├── friends_manager.gd        # Friends system manager
│   ├── global.gd                 # Global singleton (settings)
│   ├── grind_rail.gd             # Rail grinding system
│   ├── level_generator.gd        # Procedural arena generator
│   ├── lobby_ui.gd               # Multiplayer lobby interface
│   ├── multiplayer_manager.gd    # Networking manager
│   ├── music_playlist.gd         # Music playlist system
│   ├── player.gd                 # Player marble controller (1,695 lines)
│   ├── profile_manager.gd        # User profile system
│   ├── scoreboard.gd             # Scoreboard display
│   ├── skybox_generator.gd       # Procedural skybox
│   ├── world.gd                  # Main game controller (1,646 lines)
│   ├── ability_spawner.gd        # Ability pickup spawner
│   └── orb_spawner.gd            # Collectible orb spawner
│
├── textures/                       # Texture assets
│   ├── kenney_particle_pack/      # Particle textures (circles, stars)
│   └── kenney_prototype_textures/ # Prototype textures (orange, dark, grid)
│
├── *.tscn                          # Scene files (root level)
│   ├── world.tscn                 # Main game scene
│   ├── marble_player.tscn         # Player marble prefab
│   ├── rl_main_menu.tscn         # Main menu (Rocket League style)
│   ├── lobby_ui.tscn             # Multiplayer lobby
│   ├── scoreboard.tscn           # In-game scoreboard
│   ├── collectible_orb.tscn      # Level-up orb
│   └── ability_pickup.tscn       # Ability pickup
│
├── *.md                            # Documentation files
│   ├── REPOSITORY_MAP.md         # This file
│   ├── MULTIPLAYER_README.md     # Networking system guide
│   ├── MUSIC_PLAYLIST.md         # Music system documentation
│   ├── ROCKET_LEAGUE_MENU.md     # Menu system overview
│   ├── STYLE_GUIDE.md            # UI design standards
│   └── CRAZYGAMES_DEPLOYMENT.md  # Deployment guide
│
└── project.godot                   # Main project configuration
```

---

## Core Game Systems

### 1. Physics System

**Location:** `scripts/player.gd` (movement), RigidBody3D configuration
**Implementation:** Force-based marble physics

**Physics Properties:**
```gdscript
Mass: 8.0          # Dense marbles
Gravity: 2.5x      # Stronger than normal
Linear Damp: 0.5   # Air resistance
Angular Damp: 0.3  # Rotation damping
Friction: 0.4      # Ground friction
Bounce: 0.6        # Bouncy marbles
```

**Key Features:**
- RigidBody3D-based player marbles
- Force-based movement (no torque rolling)
- Continuous collision detection
- Ground detection via raycast
- Camera-relative controls
- Rotation locked (Y-axis only for camera)

**See:** `scripts/player.gd:_physics_process()` for movement implementation

---

### 2. Movement System (Sonic-Inspired)

**Location:** `scripts/player.gd`
**Lines:** 1-1695

#### Core Mechanics

| Mechanic | Key | Description | Cooldown | Implementation |
|----------|-----|-------------|----------|----------------|
| **Rolling** | WASD | Force-based movement, camera-relative | None | `_physics_process()` |
| **Jump** | Space | Standard jump with double jump | None | `_input()` → `jump()` |
| **Spin Dash** | Shift (hold) | Charge & release dash toward camera | 0.8s | `_input()` → `_spin_dash()` |
| **Bounce Attack** | Ctrl | Plunge down, bounce up on impact | 0.3s | `_input()` → `bounce_attack()` |
| **Rail Grinding** | Auto | Auto-attach to rails, gravity affects speed | None | `_on_grind_rail_entered()` |
| **Double Jump** | Space (x2) | Air jump | None | `jump()` + `has_double_jumped` |

#### Spin Dash Details
- **Charge time:** Up to 1.5 seconds
- **Direction:** Always toward camera/reticle (not player facing)
- **Visual:** Player spins during charge
- **Force:** 100.0 base + 400.0 max charge = 500.0 total
- **Cooldown:** 0.8 seconds

**See:** `scripts/player.gd:_spin_dash()` (lines ~400-450)

#### Bounce Attack Details
- **Mechanic:** Cancel horizontal velocity, plunge downward (300 force)
- **Bounce:** Strong upward impulse on impact (150 base)
- **Consecutive bounces:** Scale up to 3x multiplier
- **Cooldown:** 0.3 seconds
- **Inspiration:** Sonic Adventure 2 bounce bracelet

**See:** `scripts/player.gd:bounce_attack()` (lines ~500-550)

#### Rail Grinding (Sonic-Style)
- **Auto-attach:** When player collides with rail area
- **Physics:** Follows rail path, gravity affects speed
- **Jump off:** Can jump from rails
- **Visual:** Spark particles while grinding
- **Rails:** 12 total (8 curved perimeter, 4 vertical/spiral)

**See:**
- `scripts/grind_rail.gd` (rail logic)
- `scripts/player.gd:_on_grind_rail_entered()` (player interaction)
- `scripts/level_generator.gd:_generate_grind_rails()` (rail generation)

---

### 3. Level-Up System

**Location:** `scripts/player.gd`
**Trigger:** Collect orbs (CollectibleOrb nodes)

#### Progression

| Level | Speed Boost | Jump Boost | Spin Dash Boost | Bounce Boost |
|-------|-------------|------------|-----------------|--------------|
| 1     | +20.0       | +15.0      | +50.0           | +20.0        |
| 2     | +40.0       | +30.0      | +100.0          | +40.0        |
| 3 (Max)| +60.0      | +45.0      | +150.0          | +60.0        |

**Behavior:**
- Reset to Level 0 on death
- Orbs drop on death (placed on ground)
- Visual/audio feedback on collection
- Particle effect (collection aura)

**See:** `scripts/player.gd:_on_collectible_orb_collected()` (lines ~800-850)

---

### 4. Ability System (Kirby-Style)

**Location:** `scripts/abilities/ability_base.gd` (base class)
**Player Integration:** `scripts/player.gd`

#### Abilities Available

| Ability | Type | Range | Charge Levels | Damage Scaling |
|---------|------|-------|---------------|----------------|
| **Dash Attack** | Melee | Close | 3 (weak/medium/max) | Scales with charge |
| **Explosion** | AoE | Medium radius | 3 | Scales with charge |
| **Gun** | Ranged | Long | 3 | Scales with charge |
| **Sword** | Melee | Short | 3 | Scales with charge |

#### Charging System
- **Hold E** to charge (up to 3 levels)
- **Visual:** Particle effects grow with charge level
- **UI:** Charge meter in HUD
- **Release E** to fire

**Behavior:**
- **Pickup:** Press E near ability pickup (replaces current ability)
- **Drop:** Press O to drop (or automatic on death)
- **One at a time:** Can only hold one ability
- **Spawning:** Abilities spawn at random locations via `ability_spawner.gd`

**See:**
- `scripts/abilities/ability_base.gd` (base class, charging system)
- `scripts/player.gd:_handle_ability_input()` (player integration)
- Individual ability scripts in `scripts/abilities/`

---

### 5. Combat System

**Location:** `scripts/player.gd` (health), `scripts/world.gd` (scoring)

#### Health & Death
- **Health:** 3 hits
- **Death triggers:**
  - Health reaches 0
  - Fall below Y = -20.0 (death zone)
- **On death:**
  - Drop ability (if holding one)
  - Drop orbs (level progress lost)
  - Explosion particle effect
  - Death sound
  - Respawn after 3 seconds

**See:** `scripts/player.gd:take_damage()`, `die()`

#### Scoring (Deathmatch)
- **Kill:** +1 to killer's score
- **Death:** +1 to death count
- **K/D Ratio:** Calculated and displayed
- **Winner:** Most kills after 5-minute timer

**See:** `scripts/world.gd:_on_player_killed()` (lines ~1000-1050)

---

### 6. Multiplayer System

**Location:** `scripts/multiplayer_manager.gd`
**Lines:** Full networking implementation

#### Network Modes

| Mode | Protocol | Use Case |
|------|----------|----------|
| **WebSocket** | WSS | Browser play (CrazyGames) |
| **ENet** | UDP | Desktop/local testing |

#### Features
- **Room codes:** 6-character codes for matchmaking
- **Lobby system:** Create, join, quick play
- **Player capacity:** Up to 16 players per match
- **Ready system:** Players must ready up before host can start
- **Host controls:** Add bots, start game
- **Host migration:** Supports host leaving

#### Room Code Format
```
Example: "A3X9K2"
- 6 characters
- Uppercase alphanumeric
- Generated by server
```

**See:**
- `scripts/multiplayer_manager.gd` (networking logic)
- `scripts/lobby_ui.gd` (lobby UI)
- `MULTIPLAYER_README.md` (full documentation)

---

### 7. Bot AI System

**Location:** `scripts/bot_ai.gd`
**Lines:** 1,043 lines of advanced AI

#### State Machine

```
WANDER ──→ CHASE ──→ ATTACK
   ↑         ↑          ↓
   └────── RETREAT ←────┘
           ↓
   COLLECT_ABILITY / COLLECT_ORB
```

#### AI States

| State | Behavior | Triggers |
|-------|----------|----------|
| **WANDER** | Search for targets, move randomly | No targets nearby |
| **CHASE** | Pursue target player | Player in range, has ability |
| **ATTACK** | Combat target (strafe, use ability) | In optimal range for ability |
| **RETREAT** | Flee to health pickup/safe area | Health < 2, no ability |
| **COLLECT_ABILITY** | Get ability pickup (critical priority) | No ability equipped |
| **COLLECT_ORB** | Collect level-up orbs | Has ability, low priority |

#### Advanced Features

**Combat Tactics:**
- **Ability-specific optimal ranges:**
  - Sword: 2.0-5.0 units (close)
  - Dash: 5.0-10.0 units (medium)
  - Gun: 10.0-20.0 units (long)
  - Explosion: 3.0-8.0 units (medium)
- **Strafing:** Circle around targets while attacking
- **Charging:** Hold charge for max damage (70% chance)
- **Tactical jumping:** Jump when target is above/below
- **Prediction:** Lead targets for projectiles

**Obstacle Avoidance:**
- **Edge detection:** Raycasts prevent falling off map
- **Wall detection:** Front raycasts detect walls
- **Slope detection:** Avoid steep slopes
- **Stuck recovery:** Detect lack of movement, jump/spin dash to escape

**Target Prioritization:**
1. **Critical:** Get abilities (can't fight without them)
2. **High:** Combat players (kill for score)
3. **Medium:** Collect orbs (level up for advantage)
4. **Low:** Wander and search

**Personality Variety:**
- **Aggression:** Randomized per bot (affects chase distance)
- **Reaction time:** 0.5-1.5 second delay (prevents instant reactions)
- **Ability usage:** Varied timing and charging decisions

**See:** `scripts/bot_ai.gd` for full implementation

---

### 8. Level Generation System

**Location:** `scripts/level_generator.gd`

#### Generated Elements

| Element | Quantity | Description |
|---------|----------|-------------|
| **Main Floor** | 1 | 100x100 unit platform |
| **Floating Platforms** | 24 | Varied heights, random positions |
| **Ramps** | 12 | Vertical movement aids |
| **Grind Rails** | 12 | 8 curved perimeter + 4 vertical/spiral |
| **Perimeter Walls** | 4 | Prevent falling off edges |
| **Death Zone** | 1 | Below Y = -20.0 |
| **Spawn Points** | 16 | Dynamic positions for players/bots |

#### Grind Rails (Sonic-Style)
- **Curved rails:** 8 rails around map perimeter
  - Radius: 60 units
  - Height: 10-20 units
  - Arc: 45 degrees each
- **Vertical rails:** 4 spiral rails
  - Height: 30 units
  - Spiral pattern
- **Visual:** Metallic cylinders with glow material
- **Physics:** Area3D for grinding detection

**Procedural Texturing:**
- Kenney prototype textures (orange, dark)
- Randomized per platform
- Consistent color scheme

**See:** `scripts/level_generator.gd:generate_level()`

---

### 9. Menu System (Rocket League-Style)

**Location:** `scripts/ui/menu/rocket_menu.gd`, `rl_main_menu.tscn`

#### Features
- **Animated logo:** Plasma glow shader effect
- **Card-style buttons:**
  - "Play" (with bots)
  - "Multiplayer"
  - "Quit"
- **Glow effects:** Buttons light up on hover
- **Orbiting camera:** Dynamic camera movement
- **XP/Level system:** Progress bar at bottom
- **Profile panel:** Stats, login, XP display
- **Friends panel:** Friends list with online status

**Visual Style:**
- **Colors:** Dark background, blue accents, orange highlights
- **Fonts:** Bold headers, clean body text
- **Effects:** Bloom, glow, particles

**See:**
- `ROCKET_LEAGUE_MENU.md` (full documentation)
- `STYLE_GUIDE.md` (design standards)

---

### 10. CrazyGames Integration

**Location:** `scripts/crazygames_sdk.gd`

#### SDK Features
- **JavaScript Bridge:** Connects to CrazyGames SDK v3
- **User Authentication:** Login/logout, token management
- **Profile System:** Stats, XP, preferences (via `profile_manager.gd`)
- **Friends System:** Friends list, online status (via `friends_manager.gd`)
- **Ad Support:** Midgame, rewarded, banner ads
- **Game Events:** `gameplayStart()`, `gameplayStop()`, `happyTime()`, `gameLoadingStop()`

#### Mock Mode
- **Local testing:** Works without CrazyGames SDK
- **Fake data:** Mock user, friends list
- **Console logs:** Debug output for all SDK calls

**See:**
- `scripts/crazygames_sdk.gd` (SDK bridge)
- `scripts/profile_manager.gd` (profile system)
- `scripts/friends_manager.gd` (friends system)
- `CRAZYGAMES_DEPLOYMENT.md` (deployment guide)

---

## Scene Hierarchy

### Main Game Scene (`world.tscn`)

```
World (Node3D) ──────────────────┐
│                                │ scripts/world.gd (1,646 lines)
├─ WorldEnvironment             │ Sky, fog, lighting
├─ DirectionalLight3D           │ Main light source
├─ MenuSystem (CanvasLayer)     │ Main menu, pause, options
│  ├─ RLMainMenu                │ Rocket League-style menu
│  │  ├─ AnimatedLogo           │ Plasma glow shader
│  │  ├─ PlayButton             │ Practice with bots
│  │  ├─ MultiplayerButton      │ Join/create rooms
│  │  ├─ QuitButton             │ Exit game
│  │  ├─ ProfilePanel           │ Stats, XP, login
│  │  └─ FriendsPanel           │ Friends list
│  ├─ PauseMenu                 │ Resume, quit
│  └─ OptionsMenu               │ Fullscreen, sensitivity
├─ UI (CanvasLayer)             │ In-game UI
│  ├─ GameHUD                   │ Health, timer, score
│  ├─ Scoreboard                │ K/D ratios (Tab to show)
│  ├─ LobbyUI                   │ Multiplayer lobby
│  ├─ Crosshair                 │ Center reticle
│  ├─ FPSCounter                │ Performance display
│  └─ MusicNotification         │ Track name display
├─ MenuMusicPlayer              │ Menu background music
├─ GameplayMusicPlayer          │ In-game music
├─ LevelGenerator (Node3D)      │ Procedural arena
├─ SkyboxGenerator (Node3D)     │ Procedural skybox
├─ AbilitySpawner (Node3D)      │ Manages ability pickups
├─ OrbSpawner (Node3D)          │ Manages collectible orbs
└─ Players (Node3D)             │ Container for player/bot instances
   └─ MarblePlayer (instances)  │ Spawned dynamically
```

---

### Player Marble Scene (`marble_player.tscn`)

```
MarblePlayer (RigidBody3D) ──────┐
│                                 │ scripts/player.gd (1,695 lines)
├─ CollisionShape3D              │ Sphere collision
├─ MeshInstance3D                │ Sphere visual
├─ Camera3D                      │ 3rd-person shooter style
│  └─ CameraOcclusion            │ Anti-clipping system
├─ GroundDetector (RayCast3D)   │ Ground check
├─ AudioPlayers (multiple)       │ Jump, spin, bounce, hit, death
├─ Particles (multiple)          │ Death, collection, jump trails
├─ SpotLight3D                   │ Player light
├─ AnimationPlayer               │ Animation controller
├─ MultiplayerSynchronizer       │ Network sync
└─ AbilityAttachPoint (Node3D)   │ Ability attachment point
```

---

### Ability Scenes (e.g., `abilities/sword.tscn`)

```
Sword (Node3D) ──────────────────┐
│                                │ scripts/abilities/sword.gd
├─ MeshInstance3D               │ Sword visual
├─ AnimationPlayer              │ Swing animation
├─ HitArea (Area3D)             │ Damage detection
│  └─ CollisionShape3D          │ Sword hitbox
└─ ParticleEffects              │ Charge particles
```

---

## Script Reference

### Core Scripts

#### `scripts/global.gd` (Global Singleton)
**Purpose:** Global settings and persistence
**Key Variables:**
- `player_name: String` - Player display name
- `mouse_sensitivity: float` - Camera sensitivity (0.1-1.0)
- `music_directory: String` - Custom music folder path

**Key Functions:**
- `save_settings()` - Save to user://settings.cfg
- `load_settings()` - Load from user://settings.cfg

---

#### `scripts/world.gd` (Main Game Controller)
**Lines:** 1,646
**Purpose:** Game state management, deathmatch logic, menu system

**Key States:**
```gdscript
enum GameState { MENU, COUNTDOWN, ACTIVE, ENDED }
```

**Key Variables:**
- `match_duration: float = 300.0` - 5-minute matches
- `countdown_duration: float = 3.0` - "READY, SET, GO!"
- `players: Dictionary` - Player instances and scores
- `game_state: GameState` - Current game state

**Key Functions:**
- `start_game(bot_count: int)` - Start practice match
- `start_multiplayer_game()` - Start online match
- `spawn_player(peer_id: int, is_bot: bool)` - Spawn player/bot
- `_on_player_killed(killer_id: int, victim_id: int)` - Handle kills
- `end_game()` - Show final scoreboard, return to menu
- `_update_timer()` - Countdown match timer
- `add_bot()` - Add AI bot to match

**See:** Lines 1-1646 for full implementation

---

#### `scripts/player.gd` (Player Marble Controller)
**Lines:** 1,695
**Purpose:** Player physics, movement, abilities, health

**Key Variables:**
```gdscript
# Movement
var speed: float = 80.0
var jump_force: float = 25.0
var spin_dash_force: float = 100.0
var bounce_impulse: float = 150.0

# State
var health: int = 3
var level: int = 0
var current_ability: Node = null
var is_grinding: bool = false
var is_spin_dashing: bool = false
```

**Key Functions:**
- `_physics_process(delta)` - Movement and physics
- `_input(event)` - Input handling
- `jump()` - Jump and double jump
- `_spin_dash()` - Charge and release spin dash
- `bounce_attack()` - Bounce attack with consecutive multiplier
- `take_damage(amount: int, attacker: Node)` - Health system
- `die()` - Death and respawn
- `_on_collectible_orb_collected()` - Level up
- `_handle_ability_input()` - Ability usage and charging
- `_on_grind_rail_entered(rail: Node)` - Start rail grinding

**Movement Code Example:**
```gdscript
# scripts/player.gd ~lines 300-350
func _physics_process(delta):
    # Get camera-relative input
    var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var camera_basis = camera.global_transform.basis
    var direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

    # Apply force-based movement
    if is_on_ground and direction:
        apply_central_force(direction * speed)
```

**See:** Lines 1-1695 for full implementation

---

#### `scripts/bot_ai.gd` (Advanced Bot AI)
**Lines:** 1,043
**Purpose:** AI state machine, combat tactics, obstacle avoidance

**Key States:**
```gdscript
enum AIState { WANDER, CHASE, ATTACK, RETREAT, COLLECT_ABILITY, COLLECT_ORB }
```

**Key Variables:**
```gdscript
var current_state: AIState = AIState.WANDER
var target_player: Node = null
var target_collectible: Node = null
var aggression: float = randf_range(0.5, 1.5)  # Personality
var reaction_delay: float = randf_range(0.5, 1.5)
```

**Key Functions:**
- `_physics_process(delta)` - State machine execution
- `_find_target()` - Target prioritization
- `_move_towards(target: Vector3)` - Navigation with obstacle avoidance
- `_attack_target()` - Combat tactics (strafe, charge, fire)
- `_check_obstacles()` - Edge/wall detection
- `_get_optimal_range()` - Ability-specific combat distance

**Combat Tactics Example:**
```gdscript
# scripts/bot_ai.gd ~lines 500-550
func _attack_target():
    if not target_player:
        current_state = AIState.WANDER
        return

    var distance = global_position.distance_to(target_player.global_position)
    var optimal_range = _get_optimal_range()

    # Strafe around target
    var strafe_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
    _move_towards(target_player.global_position + strafe_dir * optimal_range)

    # Use ability if in range
    if distance <= optimal_range and player.current_ability:
        if randf() > 0.7:  # 30% chance to charge
            player._handle_ability_input()  # Charge and fire
```

**See:** Lines 1-1043 for full implementation

---

#### `scripts/multiplayer_manager.gd` (Networking Manager)
**Purpose:** WebSocket/ENet networking, room management

**Key Variables:**
```gdscript
var network_mode: String = "websocket"  # or "enet"
var current_room_code: String = ""
var players_in_lobby: Array = []
```

**Key Functions:**
- `create_room() -> String` - Create new room, return code
- `join_room(room_code: String)` - Join existing room
- `quick_play()` - Find available room or create new one
- `start_game()` - Host starts the match
- `_handle_player_connected(peer_id: int)` - New player joins
- `_handle_player_disconnected(peer_id: int)` - Player leaves

**See:** `MULTIPLAYER_README.md` for full networking documentation

---

#### `scripts/level_generator.gd` (Procedural Level Generator)
**Purpose:** Generate arenas with platforms, ramps, grind rails

**Key Functions:**
- `generate_level()` - Main generation function
- `_generate_main_floor()` - 100x100 base platform
- `_generate_floating_platforms()` - 24 platforms at varied heights
- `_generate_ramps()` - 12 ramps for vertical movement
- `_generate_grind_rails()` - 12 Sonic-style rails
- `_generate_perimeter_walls()` - 4 walls to prevent falling
- `_generate_spawn_points()` - 16 spawn positions

**Generation Example:**
```gdscript
# scripts/level_generator.gd ~lines 200-250
func _generate_grind_rails():
    # Curved perimeter rails
    for i in range(8):
        var angle = i * (TAU / 8)
        var rail = create_curved_rail(
            Vector3(cos(angle) * 60, 15, sin(angle) * 60),
            45.0  # degrees of arc
        )
        add_child(rail)

    # Vertical spiral rails
    for i in range(4):
        var rail = create_spiral_rail(
            Vector3(randf_range(-40, 40), 0, randf_range(-40, 40)),
            30.0  # height
        )
        add_child(rail)
```

---

### Ability Scripts

#### `scripts/abilities/ability_base.gd` (Base Ability Class)
**Purpose:** Shared ability functionality (charging, cooldown)

**Key Variables:**
```gdscript
var charge_level: int = 0  # 0=none, 1=weak, 2=medium, 3=max
var is_charging: bool = false
var cooldown_timer: float = 0.0
```

**Key Functions:**
- `start_charging()` - Begin charge sequence
- `update_charge(delta: float)` - Increment charge level
- `release_charge()` - Fire ability at current charge level
- `_on_cooldown_finished()` - Reset cooldown

---

#### `scripts/abilities/dash_attack.gd`
**Purpose:** Forward dash attack

**Key Variables:**
```gdscript
var dash_force: float = 200.0
var damage: int = 1  # Base damage
```

**Key Functions:**
- `use(charge_level: int)` - Execute dash based on charge level

---

#### `scripts/abilities/explosion.gd`
**Purpose:** AoE explosion around player

**Key Variables:**
```gdscript
var explosion_radius: float = 10.0
var damage: int = 2  # Base damage
```

---

#### `scripts/abilities/gun.gd`
**Purpose:** Ranged projectile weapon

**Key Variables:**
```gdscript
var projectile_speed: float = 50.0
var damage: int = 1  # Per projectile
```

---

#### `scripts/abilities/sword.gd`
**Purpose:** Melee sword swings

**Key Variables:**
```gdscript
var swing_range: float = 3.0
var damage: int = 1  # Per hit
```

---

### UI Scripts

#### `scripts/ui/game_hud.gd`
**Purpose:** In-game HUD display

**Displays:**
- Health bar (3 hearts)
- Match timer (5:00 countdown)
- Kill/Death counters
- Ability charge meter
- Level indicator

---

#### `scripts/ui/menu/rocket_menu.gd`
**Purpose:** Main menu controller

**Key Functions:**
- `_on_play_pressed()` - Show bot selection
- `_on_multiplayer_pressed()` - Show lobby UI
- `_on_quit_pressed()` - Exit game
- `_update_profile()` - Refresh stats, XP

---

#### `scripts/ui/profile_panel.gd`
**Purpose:** Profile panel (stats, XP, login)

**Displays:**
- Username
- Level and XP progress
- Total kills, deaths, K/D
- Matches played, win rate
- Login/logout button (CrazyGames)

---

#### `scripts/ui/friends_panel.gd`
**Purpose:** Friends list panel

**Displays:**
- Friends list with online status
- Invite buttons (send room code)
- Empty state ("No friends yet")

---

### CrazyGames Scripts

#### `scripts/crazygames_sdk.gd`
**Purpose:** JavaScript bridge to CrazyGames SDK v3

**Key Functions:**
- `init()` - Initialize SDK
- `gameplayStart()` - Notify gameplay started
- `gameplayStop()` - Notify gameplay stopped
- `happyTime()` - Positive event (level up, kill)
- `showAd(type: String)` - Show midgame/rewarded/banner ad
- `getUserToken() -> String` - Get CrazyGames auth token
- `requestInviteLink(room_code: String)` - Share room with friends

**Mock Mode:**
```gdscript
# scripts/crazygames_sdk.gd ~lines 50-100
if Engine.has_singleton("JavaScriptBridge"):
    # Real SDK
    JavaScriptBridge.eval("CrazyGames.SDK.init()")
else:
    # Mock mode for local testing
    print("[CrazyGames Mock] SDK initialized")
```

---

#### `scripts/profile_manager.gd`
**Purpose:** User profile system (stats, preferences)

**Key Variables:**
```gdscript
var profile_data: Dictionary = {
    "username": "Guest",
    "xp": 0,
    "level": 1,
    "kills": 0,
    "deaths": 0,
    "matches": 0,
    "wins": 0
}
```

**Key Functions:**
- `load_profile()` - Load from CrazyGames/local
- `save_profile()` - Save to user://profile.save
- `add_match_stats(kills: int, deaths: int, won: bool)` - Update stats
- `add_xp(amount: int)` - Add XP, check for level up

---

#### `scripts/friends_manager.gd`
**Purpose:** Friends system integration

**Key Functions:**
- `fetch_friends_list()` - Get friends from CrazyGames
- `send_invite(friend_id: String, room_code: String)` - Invite to room
- `update_online_status()` - Refresh friend statuses

---

## Game Mechanics

### Deathmatch Rules

**Match Duration:** 5 minutes (300 seconds)
**Victory Condition:** Most kills at timer end
**Scoring:**
- Kill: +1 point
- Death: +1 death count (tracked separately)
- K/D ratio calculated for leaderboard

**Match Flow:**
1. **Countdown:** 3 seconds ("READY", "SET", "GO!")
2. **Active Play:** 5-minute timer counts down
3. **Match End:** Timer expires, show scoreboard for 10 seconds
4. **Return to Menu:** Automatic return to main menu

**See:** `scripts/world.gd` for deathmatch implementation

---

### Movement Controls

| Key | Action | Notes |
|-----|--------|-------|
| **W/A/S/D** | Move | Camera-relative |
| **Mouse** | Look | Adjust camera |
| **Space** | Jump | Double jump available |
| **Space (x2)** | Double Jump | Uses double jump |
| **Shift (hold)** | Spin Dash | Charge up to 1.5s, release to dash |
| **Ctrl** | Bounce Attack | Plunge down, bounce up |
| **E (tap)** | Use Ability | Fire current ability |
| **E (hold)** | Charge Ability | Up to 3 charge levels |
| **O** | Drop Ability | Manual drop |
| **F** | Respawn | Force respawn (debug) |
| **Tab (hold)** | Scoreboard | Show K/D ratios |
| **Esc** | Pause | Open pause menu |

---

### Physics Formulas

#### Movement Force
```gdscript
force = direction * speed
# Base speed: 80.0
# Level 1: 100.0
# Level 2: 120.0
# Level 3: 140.0
```

#### Jump Impulse
```gdscript
impulse = Vector3.UP * jump_force
# Base: 25.0
# Level 1: 40.0
# Level 2: 55.0
# Level 3: 70.0
```

#### Spin Dash Force
```gdscript
force = dash_direction * (spin_dash_force + charge_amount * 400.0)
# Base: 100.0
# Max charge: 100.0 + 400.0 = 500.0
# Level 1 base: 150.0
# Level 3 max: 250.0 + 400.0 = 650.0
```

#### Bounce Attack
```gdscript
# Down force (applied immediately)
down_force = Vector3.DOWN * 300.0

# Up impulse (applied on collision)
up_impulse = Vector3.UP * bounce_impulse * bounce_multiplier
# Base: 150.0
# Consecutive x2: 300.0
# Consecutive x3: 450.0
```

---

### Ability Damage Scaling

| Ability | Charge 0 | Charge 1 | Charge 2 | Charge 3 (Max) |
|---------|----------|----------|----------|----------------|
| **Dash** | 1 damage | 1 damage | 2 damage | 3 damage |
| **Explosion** | 2 damage (radius 10) | 2 damage | 3 damage (radius 15) | 4 damage (radius 20) |
| **Gun** | 1 damage/bullet | 1 damage | 2 damage | 3 damage (3 bullets) |
| **Sword** | 1 damage | 1 damage | 2 damage | 3 damage (AOE swing) |

---

### XP and Leveling

**XP Sources:**
- Kill: +100 XP
- Win match: +500 XP
- Match participation: +50 XP

**Level Requirements:**
- Level 1: 0 XP
- Level 2: 500 XP
- Level 3: 1,500 XP
- Level 4: 3,000 XP
- Level 5: 5,000 XP
- (Continues scaling)

**Profile XP is separate from match level-up orbs!**

---

## Asset Catalog

### Audio Files

#### Sound Effects (`audio/`)

| File | Usage | Format |
|------|-------|--------|
| `jump_*.wav` | Jump sounds (multiple variations) | WAV |
| `spin_charge.ogg` | Spin dash charging loop | OGG |
| `spin_release.wav` | Spin dash release | WAV |
| `bounce.wav` | Bounce attack sound | WAV |
| `hit_*.wav` | Damage/impact sounds | WAV |
| `death.ogg` | Player death | OGG |
| `spawn.wav` | Respawn sound | WAV |
| `collect_orb.wav` | Orb collection | WAV |
| `ability_pickup.wav` | Ability pickup | WAV |
| `gun_fire.wav` | Gun shot | WAV |
| `sword_swing.wav` | Sword swing | WAV |
| `explosion.ogg` | Explosion ability | OGG |

#### Music (`audio/`, `music/`)

| File | Usage | Format |
|------|-------|--------|
| `661248__magmadiverrr__video-game-menu-music.ogg` | Main menu background | OGG |
| `impulse.mp3` | Gameplay music | MP3 |
| (User music folder) | Custom playlist | MP3/OGG/WAV |

**See:** `MUSIC_PLAYLIST.md` for music system documentation

---

### Textures

#### Kenney Particle Pack (`textures/kenney_particle_pack/`)
- `circle_05.png` - Crosshair, circular particles
- `star_05.png` - Star particles (death effect, collection)

#### Kenney Prototype Textures (`textures/kenney_prototype_textures/`)
- Orange textures (platforms)
- Dark textures (walls, ramps)
- Grid textures (debug/prototype)

---

### Shaders

#### `scripts/shaders/plasma_glow.gdshader`
**Purpose:** Animated plasma glow effect for logo

**Features:**
- Animated color cycling
- Glow intensity pulsing
- UV distortion
- Bloom-friendly emission

**Usage:** Main menu logo (`rl_main_menu.tscn`)

---

## Multiplayer Architecture

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

**Room Creation:**
1. Host calls `MultiplayerManager.create_room()`
2. Server generates 6-character room code (e.g., "A3X9K2")
3. Room added to available rooms list
4. Host waits in lobby for players

**Room Joining:**
1. Client enters room code
2. Client calls `MultiplayerManager.join_room(code)`
3. Server validates code, adds client to room
4. Client enters lobby, sees player list

**Quick Play:**
1. Client calls `MultiplayerManager.quick_play()`
2. Server finds available room with <16 players
3. If none found, create new room automatically
4. Join found/created room

### Lobby Flow

```
Lobby UI
├─ Display room code (host only)
├─ Show player list (names, ready status)
├─ Ready button (all players)
├─ Start button (host only, requires all ready)
├─ Add Bot button (host only)
└─ Leave button (all players)

Ready System:
- All players must click "Ready"
- Host can only start when all players ready
- Bots are automatically ready
- Unready players prevent game start
```

### Synchronization

**Player Sync:**
- Position, rotation (via MultiplayerSynchronizer)
- Health, level, score (RPC calls)
- Ability usage, death/respawn (RPC calls)
- 20 Hz update rate (configurable)

**Game State Sync:**
- Match timer (host-authoritative)
- Kills/deaths (RPC to all clients)
- Game state (countdown, active, ended)
- Scoreboard updates

**See:** `MULTIPLAYER_README.md` for detailed networking documentation

---

## AI System

### Bot Behavior Summary

**Combat Effectiveness:**
- Bots can compete with human players
- Use abilities intelligently (charging, timing)
- Avoid obstacles and map edges
- Prioritize targets strategically

**Limitations (By Design):**
- Reaction delay (0.5-1.5s) for fairness
- Occasional "mistakes" (70% charge rate, not 100%)
- Varied aggression levels (some bots more passive)

### State Transition Logic

```
Start: WANDER
│
├─ No ability? → COLLECT_ABILITY (critical priority)
│
├─ Has ability + player nearby → CHASE
│  └─ In optimal range → ATTACK
│     └─ Health < 2 → RETREAT
│
├─ Has ability + no players → COLLECT_ORB or WANDER
│
└─ RETREAT → Find health/safe area → WANDER
```

### Obstacle Avoidance System

**Edge Detection:**
```gdscript
# Raycasts at feet to detect ledges
var forward_ray = RayCast3D.new()
forward_ray.target_position = Vector3.FORWARD * 2.0 + Vector3.DOWN * 3.0

if not forward_ray.is_colliding():
    # Ledge detected, turn away
    turn_away_from_edge()
```

**Wall Detection:**
```gdscript
# Front raycasts to detect walls
var wall_ray = RayCast3D.new()
wall_ray.target_position = Vector3.FORWARD * 3.0

if wall_ray.is_colliding():
    # Wall detected, find alternate path
    strafe_around_wall()
```

**Stuck Detection:**
```gdscript
# Track movement over time
if velocity.length() < 1.0 and desired_velocity > 5.0:
    stuck_time += delta
    if stuck_time > 2.0:
        # Stuck! Try jump or spin dash
        attempt_unstuck_maneuver()
```

**See:** `scripts/bot_ai.gd:_check_obstacles()` (lines ~700-800)

---

## Quick Reference

### File Locations Cheat Sheet

| What You Need | Where To Look |
|---------------|---------------|
| **Player movement** | `scripts/player.gd:_physics_process()` |
| **Spin dash** | `scripts/player.gd:_spin_dash()` (~line 400) |
| **Bounce attack** | `scripts/player.gd:bounce_attack()` (~line 500) |
| **Rail grinding** | `scripts/grind_rail.gd`, `scripts/player.gd:_on_grind_rail_entered()` |
| **Health/damage** | `scripts/player.gd:take_damage()`, `die()` |
| **Level-up system** | `scripts/player.gd:_on_collectible_orb_collected()` (~line 800) |
| **Ability system** | `scripts/abilities/ability_base.gd` (base class) |
| **Bot AI** | `scripts/bot_ai.gd` (1,043 lines) |
| **Multiplayer** | `scripts/multiplayer_manager.gd`, `MULTIPLAYER_README.md` |
| **Match logic** | `scripts/world.gd` (1,646 lines) |
| **Level generation** | `scripts/level_generator.gd` |
| **Main menu** | `scripts/ui/menu/rocket_menu.gd`, `rl_main_menu.tscn` |
| **CrazyGames SDK** | `scripts/crazygames_sdk.gd` |
| **Profile system** | `scripts/profile_manager.gd` |
| **Music system** | `scripts/music_playlist.gd`, `MUSIC_PLAYLIST.md` |
| **UI styling** | `STYLE_GUIDE.md` |
| **Deployment** | `CRAZYGAMES_DEPLOYMENT.md` |

---

### Common Tasks

#### Add New Ability
1. Create scene in `abilities/` (duplicate existing ability)
2. Create script in `scripts/abilities/` (extend `ability_base.gd`)
3. Implement `use(charge_level: int)` function
4. Add to ability spawner pool in `scripts/ability_spawner.gd`

#### Modify Movement Physics
1. Open `scripts/player.gd`
2. Find physics variables at top (lines 20-50)
3. Adjust `speed`, `jump_force`, `spin_dash_force`, etc.
4. Test in-game

#### Change Match Duration
1. Open `scripts/world.gd`
2. Find `match_duration` variable (line ~50)
3. Change value (currently 300.0 seconds = 5 minutes)

#### Add New Bot Behavior
1. Open `scripts/bot_ai.gd`
2. Add new state to `AIState` enum (line ~20)
3. Implement state logic in `_physics_process()` (line ~100)
4. Add transition conditions

#### Customize Level Generation
1. Open `scripts/level_generator.gd`
2. Modify platform count, sizes, heights
3. Adjust grind rail positions/quantities
4. Change procedural texturing

---

### Debug Tips

**Enable Debug Menu:**
- Set `debug_enabled = true` in `world.gd`
- Press ` (backtick) to toggle debug overlay

**Debug Tools:**
- FPS counter (always visible)
- Player position/velocity
- Current game state
- Player health/level
- Ability charge level
- Bot AI state (for each bot)

**Console Commands:**
- `F` - Force respawn (dev feature)
- `Tab` - Show scoreboard
- `` ` `` - Toggle debug menu

**Performance Monitoring:**
- Check `scripts/ui/fps_counter.gd` for FPS display
- Monitor physics process time in profiler
- Check network bandwidth in multiplayer

---

### Architecture Decisions

#### Why Force-Based Movement (Not Torque)?
- **Reason:** Sonic-inspired games use direct movement, not realistic rolling
- **Benefit:** Instant response, better game feel
- **Trade-off:** Less realistic physics simulation

#### Why Room Codes (Not Matchmaking Queue)?
- **Reason:** Friends can easily join together
- **Benefit:** Social play, no waiting in queue
- **Trade-off:** Less "quick play" friendly (added Quick Play button to mitigate)

#### Why Procedural Generation (Not Pre-Made Maps)?
- **Reason:** Variety, replayability, no asset creation needed
- **Benefit:** Every match feels different
- **Trade-off:** Less hand-crafted design, potential balance issues

#### Why Kirby-Style Abilities (Not Loadouts)?
- **Reason:** Encourages map movement and combat for pickups
- **Benefit:** Dynamic gameplay, risk/reward for powerful abilities
- **Trade-off:** Players can't choose their preferred ability

---

## Conclusion

This repository contains a **feature-complete, polished multiplayer marble physics game** ready for browser deployment on CrazyGames. The codebase demonstrates:

✅ **Advanced game systems** (physics, AI, networking, procedural generation)
✅ **Excellent code organization** (modular, well-documented)
✅ **Modern Godot 4 practices** (signals, autoloads, scenes)
✅ **Production readiness** (CrazyGames integration, deployment guides)

**Key Strengths:**
- **Player movement** feels great (Sonic-inspired mechanics)
- **Bot AI** is sophisticated and challenging
- **Multiplayer** supports up to 16 players smoothly
- **Menu system** is polished (Rocket League-style)
- **Level generation** provides variety

**Potential Improvements:**
- Additional abilities (more variety)
- More game modes (team deathmatch, capture the flag)
- Map editor (let players create custom arenas)
- Cosmetic customization (marble skins, trails)

---

**Last Updated:** 2026-01-18
**Godot Version:** 4.5.1
**Author:** Claude Code Repository Mapping Agent
