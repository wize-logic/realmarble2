extends Control

## Production-ready Game HUD - displays timer, score, level, ability, and health

# Style guide colors
const COLOR_WHITE := Color(1, 1, 1, 1)
const COLOR_ACCENT_BLUE := Color(0.3, 0.7, 1, 1)
const COLOR_SECONDARY := Color(0.7, 0.8, 0.9, 1)
const COLOR_HEALTH_FULL := Color(1, 1, 1, 1)
const COLOR_HEALTH_MID := Color(1, 0.7, 0.2, 1)
const COLOR_HEALTH_LOW := Color(1, 0.25, 0.25, 1)
const COLOR_ABILITY_READY := Color(0.3, 0.7, 1, 1)
const COLOR_OUTLINE := Color(0, 0, 0, 0.6)
const COLOR_SHADOW := Color(0, 0, 0, 0.4)

@onready var timer_label: Label = $MarginContainer/VBoxContainer/TimerLabel
@onready var score_label: Label = $MarginContainer/VBoxContainer/ScoreLabel
@onready var level_label: Label = $MarginContainer/VBoxContainer/LevelLabel
@onready var ability_label: Label = $MarginContainer/VBoxContainer/AbilityLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthLabel

var world: Node = null
var player: Node = null

# Fonts
var font_bold: Font = null
var font_semibold: Font = null

# Expansion notification
var expansion_notification_label: Label = null
var expansion_flash_timer: float = 0.0
var expansion_flash_duration: float = 5.0
var is_expansion_flashing: bool = false

# Kill notification
var kill_notification_label: Label = null
var kill_notification_timer: float = 0.0
var kill_notification_duration: float = 2.0

# Killstreak notification
var killstreak_notification_label: Label = null
var killstreak_notification_timer: float = 0.0
var killstreak_notification_duration: float = 3.0
var killstreak_sound: AudioStreamPlayer = null

# Ult bar
var ult_container: Control = null
var ult_label: Label = null
var ult_bar: ProgressBar = null
var ult_bar_fill_style: StyleBoxFlat = null
var ult_pulse_time: float = 0.0

# Throttle heavy label updates — strings and score don't change every frame
var _hud_update_timer: float = 0.0
const HUD_UPDATE_INTERVAL: float = 0.15  # ~7 Hz (was 60 Hz)

func _ready() -> void:
	# Load custom fonts
	font_bold = load("res://fonts/Rajdhani-Bold.ttf")
	font_semibold = load("res://fonts/Rajdhani-SemiBold.ttf")

	# Find world and player references
	world = get_tree().root.get_node_or_null("World")

	# Create notification overlays
	create_expansion_notification()
	create_kill_notification()
	create_killstreak_notification()
	create_killstreak_sound()
	create_ult_bar()

	# Try to find the local player
	call_deferred("find_local_player")

func find_local_player() -> void:
	if not world:
		return

	var peer_id: int = 1
	if multiplayer.has_multiplayer_peer():
		peer_id = multiplayer.get_unique_id()

	player = world.get_node_or_null(str(peer_id))

	if not player:
		await get_tree().create_timer(0.5).timeout
		find_local_player()

func reset_hud() -> void:
	player = null
	world = get_tree().root.get_node_or_null("World")
	call_deferred("find_local_player")

func _process(delta: float) -> void:
	# Throttle the expensive string-formatting path (timer/score/level/ability/HP labels)
	_hud_update_timer += delta
	if _hud_update_timer >= HUD_UPDATE_INTERVAL:
		_hud_update_timer = 0.0
		update_hud()
		update_ult_bar(delta)
	# Notifications still tick every frame for smooth fading
	update_expansion_notification(delta)
	update_kill_notification(delta)
	update_killstreak_notification(delta)

func update_hud() -> void:
	# Timer - clean time display, no prefix
	if world and world.has_method("get_time_remaining_formatted"):
		if world.game_active:
			timer_label.text = world.get_time_remaining_formatted()
		else:
			timer_label.text = "--:--"
	else:
		timer_label.text = "--:--"

	# Score
	if world and world.has_method("get_score"):
		var peer_id: int = 1
		if multiplayer.has_multiplayer_peer():
			peer_id = multiplayer.get_unique_id()
		var score: int = world.get_score(peer_id)
		score_label.text = "KILLS  %d" % score
	else:
		score_label.text = "KILLS  0"

	# Level - accent blue, shows progression
	if player and "level" in player:
		level_label.text = "LVL  %d/%d" % [player.level, player.MAX_LEVEL]
	else:
		level_label.text = "LVL  0/3"

	# Ability
	if player and "current_ability" in player and player.current_ability:
		if "ability_name" in player.current_ability:
			var name_upper: String = player.current_ability.ability_name.to_upper()
			if player.current_ability.has_method("is_ready"):
				if player.current_ability.is_ready():
					ability_label.text = "%s  READY" % name_upper
					ability_label.add_theme_color_override("font_color", COLOR_ABILITY_READY)
				else:
					var cooldown: float = player.current_ability.cooldown_timer if "cooldown_timer" in player.current_ability else 0.0
					ability_label.text = "%s  %.1fS" % [name_upper, cooldown]
					ability_label.add_theme_color_override("font_color", COLOR_SECONDARY)
			else:
				ability_label.text = name_upper
				ability_label.add_theme_color_override("font_color", COLOR_SECONDARY)
		else:
			ability_label.text = "UNKNOWN"
			ability_label.add_theme_color_override("font_color", COLOR_SECONDARY)
	else:
		ability_label.text = "NO ABILITY"
		ability_label.add_theme_color_override("font_color", COLOR_SECONDARY)

	# Health - color transitions based on HP
	if player and "health" in player:
		var hp: int = player.health
		health_label.text = "HP  %d" % hp
		if hp >= 3:
			health_label.add_theme_color_override("font_color", COLOR_HEALTH_FULL)
		elif hp == 2:
			health_label.add_theme_color_override("font_color", COLOR_HEALTH_MID)
		else:
			health_label.add_theme_color_override("font_color", COLOR_HEALTH_LOW)
	else:
		health_label.text = "HP  3"
		health_label.add_theme_color_override("font_color", COLOR_HEALTH_FULL)


# --- Notification helpers ---

func _style_notification_label(label: Label, font_size: int, color: Color, outline_size: int = 3) -> void:
	if font_bold:
		label.add_theme_font_override("font", font_bold)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_color_override("font_shadow_color", COLOR_SHADOW)
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)


# --- Expansion notification ---

func create_expansion_notification() -> void:
	expansion_notification_label = Label.new()
	expansion_notification_label.name = "ExpansionNotification"
	expansion_notification_label.text = "NEW AREA AVAILABLE"
	expansion_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	expansion_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	expansion_notification_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	expansion_notification_label.anchor_top = 0.15
	expansion_notification_label.anchor_bottom = 0.15
	expansion_notification_label.offset_top = -30
	expansion_notification_label.offset_bottom = 30

	_style_notification_label(expansion_notification_label, 44, COLOR_ACCENT_BLUE, 4)

	expansion_notification_label.visible = false
	add_child(expansion_notification_label)

func update_expansion_notification(delta: float) -> void:
	if not is_expansion_flashing or not expansion_notification_label:
		return

	expansion_flash_timer -= delta

	var flash_frequency: float = 4.0
	var alpha: float = 0.5 + 0.5 * sin(expansion_flash_timer * flash_frequency * TAU)

	var color := COLOR_ACCENT_BLUE
	color.a = alpha
	expansion_notification_label.add_theme_color_override("font_color", color)

	if expansion_flash_timer <= 0:
		stop_expansion_notification()

func show_expansion_notification() -> void:
	if not expansion_notification_label:
		return
	expansion_notification_label.visible = true
	is_expansion_flashing = true
	expansion_flash_timer = expansion_flash_duration

func stop_expansion_notification() -> void:
	if not expansion_notification_label:
		return
	is_expansion_flashing = false
	expansion_notification_label.visible = false


# --- Kill notification ---

func create_kill_notification() -> void:
	kill_notification_label = Label.new()
	kill_notification_label.name = "KillNotification"
	kill_notification_label.text = ""
	kill_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kill_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	kill_notification_label.set_anchors_preset(Control.PRESET_CENTER)
	kill_notification_label.anchor_left = 0.3
	kill_notification_label.anchor_right = 0.7
	kill_notification_label.anchor_top = 0.4
	kill_notification_label.anchor_bottom = 0.45
	kill_notification_label.offset_left = 0
	kill_notification_label.offset_right = 0
	kill_notification_label.offset_top = 0
	kill_notification_label.offset_bottom = 0

	_style_notification_label(kill_notification_label, 32, COLOR_WHITE, 3)

	kill_notification_label.visible = false
	add_child(kill_notification_label)

func update_kill_notification(delta: float) -> void:
	if not kill_notification_label or not kill_notification_label.visible:
		return

	kill_notification_timer -= delta

	if kill_notification_timer <= 0.5:
		var alpha: float = kill_notification_timer / 0.5
		var color := COLOR_WHITE
		color.a = alpha
		kill_notification_label.add_theme_color_override("font_color", color)

	if kill_notification_timer <= 0:
		kill_notification_label.visible = false
		kill_notification_label.add_theme_color_override("font_color", COLOR_WHITE)

func show_kill_notification(victim_name: String) -> void:
	if not kill_notification_label:
		return
	kill_notification_label.text = "ELIMINATED  %s" % victim_name.to_upper()
	kill_notification_label.visible = true
	kill_notification_timer = kill_notification_duration


# --- Killstreak notification ---

func create_killstreak_notification() -> void:
	killstreak_notification_label = Label.new()
	killstreak_notification_label.name = "KillstreakNotification"
	killstreak_notification_label.text = ""
	killstreak_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	killstreak_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	killstreak_notification_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	killstreak_notification_label.anchor_top = 0.25
	killstreak_notification_label.anchor_bottom = 0.30
	killstreak_notification_label.offset_top = 0
	killstreak_notification_label.offset_bottom = 0

	_style_notification_label(killstreak_notification_label, 48, COLOR_ACCENT_BLUE, 4)

	killstreak_notification_label.visible = false
	add_child(killstreak_notification_label)

func create_killstreak_sound() -> void:
	killstreak_sound = AudioStreamPlayer.new()
	killstreak_sound.name = "KillstreakSound"
	killstreak_sound.volume_db = -3.0
	add_child(killstreak_sound)

func update_killstreak_notification(delta: float) -> void:
	if not killstreak_notification_label or not killstreak_notification_label.visible:
		return

	killstreak_notification_timer -= delta

	var pulse_frequency: float = 3.0
	var scale_factor: float = 1.0 + 0.1 * sin(killstreak_notification_timer * pulse_frequency * TAU)
	killstreak_notification_label.scale = Vector2(scale_factor, scale_factor)

	if killstreak_notification_timer <= 1.0:
		var alpha: float = killstreak_notification_timer / 1.0
		var color := COLOR_ACCENT_BLUE
		color.a = alpha
		killstreak_notification_label.add_theme_color_override("font_color", color)

	if killstreak_notification_timer <= 0:
		killstreak_notification_label.visible = false
		killstreak_notification_label.scale = Vector2.ONE
		killstreak_notification_label.add_theme_color_override("font_color", COLOR_ACCENT_BLUE)

func show_killstreak_notification(streak: int) -> void:
	if not killstreak_notification_label:
		return

	var message: String = ""
	if streak == 5:
		message = "KILLING SPREE"
	elif streak == 10:
		message = "UNSTOPPABLE"
	else:
		message = "KILLSTREAK  %d" % streak

	killstreak_notification_label.text = message
	killstreak_notification_label.visible = true
	killstreak_notification_timer = killstreak_notification_duration

	play_killstreak_sound(streak)

# --- Ult bar ---

func create_ult_bar() -> void:
	# Container anchored to bottom-center
	ult_container = Control.new()
	ult_container.name = "UltBar"
	ult_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ult_container.anchor_left = 0.5
	ult_container.anchor_right = 0.5
	ult_container.anchor_top = 1.0
	ult_container.anchor_bottom = 1.0
	ult_container.offset_left = -140
	ult_container.offset_right = 140
	ult_container.offset_top = -58
	ult_container.offset_bottom = -28
	ult_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ult_container)

	# Label above bar
	ult_label = Label.new()
	ult_label.name = "UltLabel"
	ult_label.text = "ULT  0%"
	ult_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ult_label.position = Vector2(0, 0)
	ult_label.size = Vector2(280, 20)
	ult_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font_semibold:
		ult_label.add_theme_font_override("font", font_semibold)
	ult_label.add_theme_font_size_override("font_size", 16)
	ult_label.add_theme_color_override("font_color", COLOR_WHITE)
	ult_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	ult_label.add_theme_color_override("font_shadow_color", COLOR_SHADOW)
	ult_label.add_theme_constant_override("outline_size", 2)
	ult_label.add_theme_constant_override("shadow_offset_x", 1)
	ult_label.add_theme_constant_override("shadow_offset_y", 1)
	ult_container.add_child(ult_label)

	# Progress bar
	ult_bar = ProgressBar.new()
	ult_bar.name = "UltProgress"
	ult_bar.min_value = 0.0
	ult_bar.max_value = 100.0
	ult_bar.value = 0.0
	ult_bar.show_percentage = false
	ult_bar.position = Vector2(0, 22)
	ult_bar.size = Vector2(280, 6)
	ult_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Background style - minimal, no borders
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.12, 0.18, 0.5)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_left = 3
	bg_style.corner_radius_bottom_right = 3
	ult_bar.add_theme_stylebox_override("background", bg_style)

	# Fill style - accent blue progression
	ult_bar_fill_style = StyleBoxFlat.new()
	ult_bar_fill_style.bg_color = Color(0.2, 0.35, 0.5, 0.8)
	ult_bar_fill_style.corner_radius_top_left = 3
	ult_bar_fill_style.corner_radius_top_right = 3
	ult_bar_fill_style.corner_radius_bottom_left = 3
	ult_bar_fill_style.corner_radius_bottom_right = 3
	ult_bar.add_theme_stylebox_override("fill", ult_bar_fill_style)

	ult_container.add_child(ult_bar)

func update_ult_bar(delta: float) -> void:
	if not ult_container or not ult_bar or not ult_label:
		return

	# Get ult charge from player's ult system
	var ult_system: Node = null
	if player and "ult_system" in player:
		ult_system = player.ult_system

	if not ult_system or not "ult_charge" in ult_system:
		ult_bar.value = 0.0
		ult_label.text = "ULT  0%"
		ult_label.add_theme_color_override("font_color", COLOR_SECONDARY)
		if ult_bar_fill_style:
			ult_bar_fill_style.bg_color = Color(0.2, 0.35, 0.5, 0.8)
		return

	var charge: float = ult_system.ult_charge
	var max_charge: float = ult_system.MAX_ULT_CHARGE
	var percent: float = (charge / max_charge) * 100.0
	ult_bar.value = percent

	var is_ready: bool = charge >= max_charge

	if is_ready:
		# Pulsing accent blue when ready
		ult_pulse_time += delta * 3.0
		var pulse: float = 0.8 + 0.2 * sin(ult_pulse_time * TAU)
		var ready_color := Color(0.3 * pulse, 0.7 * pulse, 1.0 * pulse, 1.0)

		ult_label.text = "ULTIMATE  READY"
		ult_label.add_theme_color_override("font_color", COLOR_ACCENT_BLUE)
		if font_bold:
			ult_label.add_theme_font_override("font", font_bold)

		if ult_bar_fill_style:
			ult_bar_fill_style.bg_color = ready_color
	else:
		ult_pulse_time = 0.0
		ult_label.text = "ULT  %d%%" % int(percent)
		ult_label.add_theme_color_override("font_color", COLOR_WHITE)
		if font_semibold:
			ult_label.add_theme_font_override("font", font_semibold)

		# Fill color ramps from muted to brighter blue as charge increases
		if ult_bar_fill_style:
			var t: float = percent / 100.0
			var fill_color := Color(
				lerp(0.15, 0.3, t),
				lerp(0.25, 0.6, t),
				lerp(0.4, 0.95, t),
				lerp(0.7, 1.0, t)
			)
			ult_bar_fill_style.bg_color = fill_color


func play_killstreak_sound(streak: int) -> void:
	if not killstreak_sound:
		return

	var audio_stream = AudioStreamGenerator.new()
	audio_stream.mix_rate = 22050.0
	audio_stream.buffer_length = 0.3

	killstreak_sound.stream = audio_stream
	killstreak_sound.volume_db = -3.0
	killstreak_sound.pitch_scale = 1.0

	killstreak_sound.play()

	var playback: AudioStreamGeneratorPlayback = killstreak_sound.get_stream_playback()
	if playback:
		var sample_hz = audio_stream.mix_rate
		var samples_to_fill = int(sample_hz * 0.5)

		for i in range(samples_to_fill):
			var t = float(i) / sample_hz
			var frequency = 400.0
			if t < 0.15:
				frequency = 400.0
			elif t < 0.3:
				frequency = 500.0
			else:
				frequency = 650.0

			var phase = t * frequency * TAU
			var amplitude = 0.4 * (1.0 - min(t / 0.5, 1.0))
			var value = sin(phase) * amplitude
			value += sin(phase * 2.0) * amplitude * 0.3
			value += sin(phase * 3.0) * amplitude * 0.15

			playback.push_frame(Vector2(value, value))
