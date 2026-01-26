extends Control

## Debug Menu
## Provides debugging tools and cheats with pagination

@onready var panel: PanelContainer = $Panel
var vbox: VBoxContainer = null

# Pagination system
var current_page: int = 0
var total_pages: int = 5  # Added bot AI status page (v5.0)
var page_title: Label = null
var page_indicator: Label = null
var prev_button: Button = null
var next_button: Button = null
var page_content: VBoxContainer = null

# State variables
var is_visible: bool = false
var god_mode_enabled: bool = false
var collision_shapes_visible: bool = false
var speed_multiplier: float = 1.0
var nametags_enabled: bool = false
var nametag_script = preload("res://scripts/debug_nametag.gd")
var direction_arrows_enabled: bool = false
var direction_arrow_script = preload("res://scripts/debug_direction_arrow.gd")

# Dynamic button references (will be created per page)
var god_mode_button: Button = null
var collision_shapes_button: Button = null
var nametags_button: Button = null
var direction_arrows_button: Button = null
var bot_count_label: Label = null
var speed_label: Label = null

func _ready() -> void:
	visible = false
	panel.visible = false

	# Clear existing VBoxContainer and rebuild with pagination
	vbox = panel.get_node("VBoxContainer")
	if vbox:
		# Clear all existing children
		for child in vbox.get_children():
			child.queue_free()

	# Wait a frame for cleanup
	await get_tree().process_frame

	# Build pagination structure
	build_pagination_ui()

	# Show first page
	show_page(0)

func _input(event: InputEvent) -> void:
	# Toggle debug menu with F3
	if event is InputEventKey and event.keycode == KEY_F3 and event.pressed and not event.echo:
		toggle_menu()

	# Pagination shortcuts (only when menu is visible)
	if is_visible and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_PAGEUP:
				_on_prev_page()
			KEY_RIGHT, KEY_PAGEDOWN:
				_on_next_page()

func toggle_menu() -> void:
	"""Toggle debug menu visibility"""
	is_visible = !is_visible
	visible = is_visible
	panel.visible = is_visible

	# Only change mouse mode during active gameplay
	var world: Node = get_tree().get_root().get_node_or_null("World")
	var in_gameplay: bool = world and world.get("game_active")

	if in_gameplay:
		if is_visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ============================================================================
# PAGINATION SYSTEM
# ============================================================================

func build_pagination_ui() -> void:
	"""Build the pagination structure"""
	if not vbox:
		return

	# Title
	page_title = Label.new()
	page_title.text = "DEBUG MENU (F3)"
	page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(page_title)

	# Page indicator
	page_indicator = Label.new()
	page_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_indicator.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(page_indicator)

	var separator1 = HSeparator.new()
	vbox.add_child(separator1)

	# Navigation buttons
	var nav_hbox = HBoxContainer.new()
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(nav_hbox)

	prev_button = Button.new()
	prev_button.text = "< Previous"
	prev_button.custom_minimum_size = Vector2(80, 0)
	prev_button.pressed.connect(_on_prev_page)
	nav_hbox.add_child(prev_button)

	next_button = Button.new()
	next_button.text = "Next >"
	next_button.custom_minimum_size = Vector2(80, 0)
	next_button.pressed.connect(_on_next_page)
	nav_hbox.add_child(next_button)

	var separator2 = HSeparator.new()
	vbox.add_child(separator2)

	# Content container (will be filled per page)
	page_content = VBoxContainer.new()
	page_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(page_content)

func show_page(page: int) -> void:
	"""Show a specific page of debug options"""
	current_page = clamp(page, 0, total_pages - 1)

	# Update page indicator
	if page_indicator:
		page_indicator.text = "Page %d/%d" % [current_page + 1, total_pages]

	# Update navigation button states
	if prev_button:
		prev_button.disabled = (current_page == 0)
	if next_button:
		next_button.disabled = (current_page == total_pages - 1)

	# Clear current page content
	if page_content:
		for child in page_content.get_children():
			child.queue_free()

	# Wait a frame for cleanup
	await get_tree().process_frame

	# Build page content
	match current_page:
		0:
			build_page_0()  # Player & Bot Controls
		1:
			build_page_1()  # Match & World Controls
		2:
			build_page_2()  # Expansion & Advanced Controls
		3:
			build_page_3()  # Debug Logging Controls
		4:
			build_page_4()  # Bot AI Status (v5.0)

func _on_prev_page() -> void:
	"""Go to previous page"""
	if current_page > 0:
		show_page(current_page - 1)

func _on_next_page() -> void:
	"""Go to next page"""
	if current_page < total_pages - 1:
		show_page(current_page + 1)

# ============================================================================
# PAGE BUILDERS
# ============================================================================

func build_page_0() -> void:
	"""Build Page 0: Player & Bot Controls"""
	if not page_content:
		return

	# Section label
	var section_label = Label.new()
	section_label.text = "PLAYER & BOT CONTROLS"
	section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	page_content.add_child(section_label)

	page_content.add_child(HSeparator.new())

	# Bot controls
	var spawn_bot_btn = Button.new()
	spawn_bot_btn.text = "Spawn Bot"
	spawn_bot_btn.pressed.connect(_on_spawn_bot_pressed)
	page_content.add_child(spawn_bot_btn)

	var bot_count_hbox = HBoxContainer.new()
	page_content.add_child(bot_count_hbox)

	bot_count_label = Label.new()
	bot_count_label.text = "Bots: 0"
	bot_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_count_hbox.add_child(bot_count_label)

	var remove_bot_btn = Button.new()
	remove_bot_btn.text = "-"
	remove_bot_btn.pressed.connect(_on_remove_bot_pressed)
	bot_count_hbox.add_child(remove_bot_btn)

	var add_bot_btn = Button.new()
	add_bot_btn.text = "+"
	add_bot_btn.pressed.connect(_on_add_bot_pressed)
	bot_count_hbox.add_child(add_bot_btn)

	update_bot_count()

	# Player controls
	god_mode_button = Button.new()
	god_mode_button.text = "God Mode: OFF"
	god_mode_button.pressed.connect(_on_god_mode_pressed)
	page_content.add_child(god_mode_button)

	var max_level_btn = Button.new()
	max_level_btn.text = "Max Level"
	max_level_btn.pressed.connect(_on_max_level_pressed)
	page_content.add_child(max_level_btn)

	var teleport_btn = Button.new()
	teleport_btn.text = "Teleport"
	teleport_btn.pressed.connect(_on_teleport_pressed)
	page_content.add_child(teleport_btn)

	var kill_player_btn = Button.new()
	kill_player_btn.text = "Kill Player (Respawn)"
	kill_player_btn.pressed.connect(_on_kill_player_pressed)
	page_content.add_child(kill_player_btn)

	var kill_all_btn = Button.new()
	kill_all_btn.text = "Kill All Other Players/Bots"
	kill_all_btn.pressed.connect(_on_kill_all_pressed)
	page_content.add_child(kill_all_btn)

	var add_score_btn = Button.new()
	add_score_btn.text = "Add 5 Score"
	add_score_btn.pressed.connect(_on_add_score_pressed)
	page_content.add_child(add_score_btn)

func build_page_1() -> void:
	"""Build Page 1: Match & World Controls"""
	if not page_content:
		return

	# Section label
	var section_label = Label.new()
	section_label.text = "MATCH & WORLD CONTROLS"
	section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	page_content.add_child(section_label)

	page_content.add_child(HSeparator.new())

	# Ability controls
	var clear_abilities_btn = Button.new()
	clear_abilities_btn.text = "Clear All Abilities"
	clear_abilities_btn.pressed.connect(_on_clear_abilities_pressed)
	page_content.add_child(clear_abilities_btn)

	var spawn_ability_btn = Button.new()
	spawn_ability_btn.text = "Spawn Random Ability"
	spawn_ability_btn.pressed.connect(_on_spawn_ability_pressed)
	page_content.add_child(spawn_ability_btn)

	# Match controls
	var reset_timer_btn = Button.new()
	reset_timer_btn.text = "Reset Match Timer"
	reset_timer_btn.pressed.connect(_on_reset_timer_pressed)
	page_content.add_child(reset_timer_btn)

	var end_match_btn = Button.new()
	end_match_btn.text = "End Match Immediately"
	end_match_btn.pressed.connect(_on_end_match_pressed)
	page_content.add_child(end_match_btn)

	# World controls
	var regenerate_level_btn = Button.new()
	regenerate_level_btn.text = "Regenerate Level"
	regenerate_level_btn.pressed.connect(_on_regenerate_level_pressed)
	page_content.add_child(regenerate_level_btn)

	var change_skybox_btn = Button.new()
	change_skybox_btn.text = "Change Skybox Colors"
	change_skybox_btn.pressed.connect(_on_change_skybox_pressed)
	page_content.add_child(change_skybox_btn)

	# Speed multiplier
	page_content.add_child(HSeparator.new())

	var speed_hbox = HBoxContainer.new()
	page_content.add_child(speed_hbox)

	speed_label = Label.new()
	speed_label.text = "Speed: 1.0x"
	speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_hbox.add_child(speed_label)

	var speed_slider = HSlider.new()
	speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_slider.min_value = 0.1
	speed_slider.max_value = 3.0
	speed_slider.step = 0.1
	speed_slider.value = 1.0
	speed_slider.value_changed.connect(_on_speed_changed)
	speed_hbox.add_child(speed_slider)

func build_page_2() -> void:
	"""Build Page 2: Expansion & Advanced Controls"""
	if not page_content:
		return

	# Section label
	var section_label = Label.new()
	section_label.text = "EXPANSION & ADVANCED"
	section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	page_content.add_child(section_label)

	page_content.add_child(HSeparator.new())

	# MID-ROUND EXPANSION BUTTON (NEW!)
	var trigger_expansion_btn = Button.new()
	trigger_expansion_btn.text = "⚡ Trigger Map Expansion NOW"
	trigger_expansion_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))  # Gold color
	trigger_expansion_btn.pressed.connect(_on_trigger_expansion_pressed)
	page_content.add_child(trigger_expansion_btn)

	var expansion_info = Label.new()
	expansion_info.text = "Creates 2nd arena 1000ft away"
	expansion_info.add_theme_font_size_override("font_size", 10)
	expansion_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	expansion_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_content.add_child(expansion_info)

	page_content.add_child(HSeparator.new())

	# Debug visualization
	collision_shapes_button = Button.new()
	collision_shapes_button.text = "Show Collision: OFF"
	collision_shapes_button.pressed.connect(_on_collision_shapes_pressed)
	page_content.add_child(collision_shapes_button)

	nametags_button = Button.new()
	nametags_button.text = "Show Nametags: " + ("ON" if nametags_enabled else "OFF")
	nametags_button.pressed.connect(_on_nametags_pressed)
	page_content.add_child(nametags_button)

	direction_arrows_button = Button.new()
	direction_arrows_button.text = "Bot Direction Arrows: " + ("ON" if direction_arrows_enabled else "OFF")
	direction_arrows_button.pressed.connect(_on_direction_arrows_pressed)
	page_content.add_child(direction_arrows_button)

	# Info section
	page_content.add_child(HSeparator.new())

	var info_label = Label.new()
	info_label.text = "F3: Toggle Debug Menu\nArrows/Page Keys: Navigate"
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_content.add_child(info_label)

func build_page_3() -> void:
	"""Build Page 3: Debug Logging Controls"""
	if not page_content:
		return

	# Section label
	var section_label = Label.new()
	section_label.text = "DEBUG LOGGING"
	section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	page_content.add_child(section_label)

	page_content.add_child(HSeparator.new())

	# Master toggle
	var master_toggle = Button.new()
	master_toggle.text = "Master Debug: " + ("ON" if DebugLogger.debug_enabled else "OFF")
	master_toggle.pressed.connect(_on_master_debug_toggle)
	page_content.add_child(master_toggle)

	# Quick actions
	var quick_actions_hbox = HBoxContainer.new()
	page_content.add_child(quick_actions_hbox)

	var enable_all_btn = Button.new()
	enable_all_btn.text = "Enable All"
	enable_all_btn.pressed.connect(_on_enable_all_categories)
	quick_actions_hbox.add_child(enable_all_btn)

	var disable_all_btn = Button.new()
	disable_all_btn.text = "Disable All"
	disable_all_btn.pressed.connect(_on_disable_all_categories)
	quick_actions_hbox.add_child(disable_all_btn)

	page_content.add_child(HSeparator.new())

	# Entity filtering section
	var entity_filter_label = Label.new()
	var watched_entity_text: String = "All entities"
	if DebugLogger.watched_entity_id != null:
		var entity_id: int = int(DebugLogger.watched_entity_id)
		if entity_id >= 9000:
			watched_entity_text = "Bot_%d" % (entity_id - 9000)
		else:
			watched_entity_text = "Player"
	entity_filter_label.text = "Watching: " + watched_entity_text
	entity_filter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entity_filter_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	page_content.add_child(entity_filter_label)

	# Entity filter buttons
	var entity_buttons_hbox = HBoxContainer.new()
	entity_buttons_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	page_content.add_child(entity_buttons_hbox)

	var watch_all_btn = Button.new()
	watch_all_btn.text = "Watch All"
	watch_all_btn.pressed.connect(_on_watch_entity.bind(null))
	entity_buttons_hbox.add_child(watch_all_btn)

	var watch_player_btn = Button.new()
	watch_player_btn.text = "Watch Player"
	watch_player_btn.pressed.connect(_on_watch_player)
	entity_buttons_hbox.add_child(watch_player_btn)

	# Bot watch buttons (dynamically add for each bot)
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	var bot_ids: Array[int] = []
	for player in players:
		var player_id: int = player.name.to_int()
		if player_id >= 9000:
			bot_ids.append(player_id)
	bot_ids.sort()

	if bot_ids.size() > 0:
		var bot_buttons_hbox = HBoxContainer.new()
		bot_buttons_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		page_content.add_child(bot_buttons_hbox)

		for bot_id in bot_ids:
			var watch_bot_btn = Button.new()
			watch_bot_btn.text = "Bot_%d" % (bot_id - 9000)
			watch_bot_btn.pressed.connect(_on_watch_entity.bind(bot_id))
			bot_buttons_hbox.add_child(watch_bot_btn)

	page_content.add_child(HSeparator.new())

	# Category toggles in a scroll container for many categories
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_content.add_child(scroll)

	var categories_vbox = VBoxContainer.new()
	categories_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(categories_vbox)

	# Add toggle for each category
	for category in DebugLogger.Category.values():
		var category_hbox = HBoxContainer.new()
		categories_vbox.add_child(category_hbox)

		var check_button = CheckButton.new()
		check_button.button_pressed = DebugLogger.is_category_enabled(category)
		check_button.toggled.connect(_on_category_toggled.bind(category))
		category_hbox.add_child(check_button)

		var category_label = Label.new()
		category_label.text = DebugLogger.CATEGORY_NAMES.get(category, "Unknown")
		category_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		category_hbox.add_child(category_label)

	# Info
	page_content.add_child(HSeparator.new())
	var info_label = Label.new()
	info_label.text = "Enable categories to see debug output\nin the console/terminal"
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_content.add_child(info_label)

func build_page_4() -> void:
	"""Build Page 4: Bot AI Status (v5.0)"""
	if not page_content:
		return

	# Section label
	var section_label = Label.new()
	section_label.text = "BOT AI STATUS (v5.0)"
	section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_label.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	page_content.add_child(section_label)

	page_content.add_child(HSeparator.new())

	# Get all bots
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	var bots: Array[Node] = []

	for player in players:
		var player_id: int = player.name.to_int()
		if player_id >= 9000:  # Bot IDs start at 9000
			bots.append(player)

	# Sort by ID
	bots.sort_custom(func(a, b): return a.name.to_int() < b.name.to_int())

	if bots.is_empty():
		var no_bots_label = Label.new()
		no_bots_label.text = "No bots spawned"
		no_bots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_bots_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		page_content.add_child(no_bots_label)
	else:
		# Create scrollable container for bot list
		var scroll = ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 300)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page_content.add_child(scroll)

		var bots_vbox = VBoxContainer.new()
		bots_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(bots_vbox)

		# Display each bot's status
		for bot in bots:
			var bot_id: int = bot.name.to_int()
			var bot_ai: Node = bot.get_node_or_null("BotAI")

			# Bot container
			var bot_container = PanelContainer.new()
			bot_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bots_vbox.add_child(bot_container)

			var bot_vbox = VBoxContainer.new()
			bot_container.add_child(bot_vbox)

			# Bot name and type
			var bot_name_label = Label.new()
			var ai_type_text: String = ""
			if bot_ai and bot_ai.has_method("get_ai_type"):
				ai_type_text = " [%s]" % bot_ai.get_ai_type()
			bot_name_label.text = "Bot_%d%s" % [bot_id - 9000, ai_type_text]
			bot_name_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
			bot_vbox.add_child(bot_name_label)

			# State
			if bot_ai and "state" in bot_ai:
				var state_label = Label.new()
				var state: String = bot_ai.state

				# Color-code by state
				var state_color: Color = Color(0.8, 0.8, 0.8)
				match state:
					"ATTACK":
						state_color = Color(1.0, 0.3, 0.3)
					"RETREAT":
						state_color = Color(0.3, 0.5, 1.0)
					"COLLECT_ABILITY":
						state_color = Color(1.0, 0.5, 1.0)
					"CHASE":
						state_color = Color(1.0, 0.6, 0.2)
					"COLLECT_ORB":
						state_color = Color(0.3, 1.0, 1.0)
					"WANDER":
						state_color = Color(1.0, 1.0, 0.3)

				state_label.text = "State: %s" % state
				state_label.add_theme_color_override("font_color", state_color)
				bot_vbox.add_child(state_label)

			# Health
			if "health" in bot:
				var health_label = Label.new()
				health_label.text = "Health: %d/3" % bot.health
				bot_vbox.add_child(health_label)

			# Ability
			if "current_ability" in bot:
				var ability_label = Label.new()
				if bot.current_ability and "ability_name" in bot.current_ability:
					ability_label.text = "Ability: %s" % bot.current_ability.ability_name
					ability_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
				else:
					ability_label.text = "Ability: None"
					ability_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
				bot_vbox.add_child(ability_label)

			# Target
			if bot_ai and "target_player" in bot_ai:
				var target_label = Label.new()
				if bot_ai.target_player and is_instance_valid(bot_ai.target_player):
					var target_name: String = bot_ai.target_player.name
					var target_id: int = target_name.to_int()
					if target_id >= 9000:
						target_label.text = "Target: Bot_%d" % (target_id - 9000)
					else:
						target_label.text = "Target: Player"
					target_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
				else:
					target_label.text = "Target: None"
					target_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
				bot_vbox.add_child(target_label)

			# Personality (v5.0)
			if bot_ai and "strategic_preference" in bot_ai:
				var personality_label = Label.new()
				var strategy: String = bot_ai.strategic_preference
				var aggression: float = bot_ai.get("aggression_level") if "aggression_level" in bot_ai else 0.0
				var skill: float = bot_ai.get("bot_skill") if "bot_skill" in bot_ai else 0.0
				personality_label.text = "Personality: %s (Skill: %.0f%%, Aggro: %.0f%%)" % [
					strategy.capitalize(),
					skill * 100,
					aggression * 100
				]
				personality_label.add_theme_font_size_override("font_size", 10)
				personality_label.add_theme_color_override("font_color", Color(0.7, 0.7, 1.0))
				bot_vbox.add_child(personality_label)

			# v5.0 specific info
			if bot_ai:
				var v5_info_label = Label.new()
				var info_parts: Array[String] = []

				# Retreat status
				if bot_ai.has_method("should_retreat"):
					if bot_ai.call("should_retreat"):
						info_parts.append("⚠ Should Retreat")

				# Collection info
				if "target_ability" in bot_ai and bot_ai.target_ability and is_instance_valid(bot_ai.target_ability):
					info_parts.append("🎯 Seeking Ability")

				# Stuck status
				if "is_stuck" in bot_ai and bot_ai.is_stuck:
					info_parts.append("🚫 Stuck")

				# Rail grinding (Type A)
				if "is_grinding" in bot_ai and bot_ai.is_grinding:
					info_parts.append("🛤️ Grinding Rail")

				# Post-rail launch (Type A)
				if "post_rail_launch" in bot_ai and bot_ai.post_rail_launch:
					info_parts.append("✈️ Aerial Recovery")

				if not info_parts.is_empty():
					v5_info_label.text = " ".join(info_parts)
					v5_info_label.add_theme_font_size_override("font_size", 10)
					v5_info_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
					bot_vbox.add_child(v5_info_label)

	# Legend
	page_content.add_child(HSeparator.new())
	var legend_label = Label.new()
	legend_label.text = "Colors: Red=Attack, Blue=Retreat, Magenta=Ability\nOrange=Chase, Cyan=Orb, Yellow=Wander"
	legend_label.add_theme_font_size_override("font_size", 10)
	legend_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	legend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_content.add_child(legend_label)

# ============================================================================
# BUTTON HANDLERS
# ============================================================================

func _on_spawn_bot_pressed() -> void:
	"""Spawn a bot player"""
	# Check if we're already at max capacity (8 total: 1 player + 7 bots)
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	if players.size() >= 8:
		print("Cannot spawn bot - max 8 total (1 player + 7 bots) reached!")
		return

	print("Spawning bot...")
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and world.has_method("spawn_bot"):
		world.spawn_bot()
		update_bot_count()

		# Wait a frame for the bot to be fully initialized
		await get_tree().process_frame

		# Add debug visualizations to new bot if enabled
		players = get_tree().get_nodes_in_group("players")
		if players.size() > 0:
			var new_bot: Node = players[players.size() - 1]  # Last spawned
			var player_id: int = new_bot.name.to_int()

			if player_id >= 9000:  # Verify it's a bot
				# Add nametag if enabled
				if nametags_enabled and not new_bot.get_node_or_null("DebugNametag"):
					var nametag = nametag_script.new()
					nametag.name = "DebugNametag"
					nametag.setup(new_bot)
					new_bot.add_child(nametag)

				# Add direction arrow if enabled
				if direction_arrows_enabled and not new_bot.get_node_or_null("DebugDirectionArrow"):
					var arrow = direction_arrow_script.new()
					arrow.name = "DebugDirectionArrow"
					arrow.setup(new_bot)
					new_bot.add_child(arrow)
	else:
		print("Error: Could not spawn bot - World node not found or missing spawn_bot method")

func _on_add_bot_pressed() -> void:
	"""Add a bot"""
	_on_spawn_bot_pressed()

func _on_remove_bot_pressed() -> void:
	"""Remove the last bot"""
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	var bot_removed: bool = false

	# Find and remove the last bot (ID >= 9000)
	for i in range(players.size() - 1, -1, -1):
		var player: Node = players[i]
		var player_id: int = player.name.to_int()
		if player_id >= 9000:  # Bot IDs start at 9000
			print("Removing bot: ", player_id)
			player.queue_free()
			bot_removed = true
			break

	if bot_removed:
		update_bot_count()
	else:
		print("No bots to remove")

func update_bot_count() -> void:
	"""Update the bot count label"""
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	var bot_count: int = 0

	for player in players:
		var player_id: int = player.name.to_int()
		if player_id >= 9000:  # Bot IDs start at 9000
			bot_count += 1

	if bot_count_label:
		bot_count_label.text = "Bots: %d" % bot_count

func _on_god_mode_pressed() -> void:
	"""Toggle god mode for local player"""
	god_mode_enabled = !god_mode_enabled

	var player: Node = get_local_player()
	if player:
		if god_mode_enabled:
			player.set("god_mode", true)
			god_mode_button.text = "God Mode: ON"
			print("God mode enabled")
		else:
			player.set("god_mode", false)
			god_mode_button.text = "God Mode: OFF"
			print("God mode disabled")

func _on_max_level_pressed() -> void:
	"""Set player to max level"""
	var player: Node = get_local_player()
	if player and player.has_method("collect_orb"):
		while player.level < player.MAX_LEVEL:
			player.collect_orb()
		print("Set player to max level")

func _on_teleport_pressed() -> void:
	"""Teleport player to random spawn"""
	var player: Node = get_local_player()
	if player:
		var spawn_pos: Vector3 = player.spawns[randi() % player.spawns.size()]
		player.global_position = spawn_pos
		player.linear_velocity = Vector3.ZERO
		print("Teleported to: ", spawn_pos)

func _on_clear_abilities_pressed() -> void:
	"""Remove all abilities from map"""
	var pickups: Array[Node] = get_tree().get_nodes_in_group("ability_pickups")
	for pickup in pickups:
		pickup.queue_free()
	print("Cleared all ability pickups")

func _on_speed_changed(value: float) -> void:
	"""Change game speed multiplier"""
	speed_multiplier = value
	Engine.time_scale = value
	if speed_label:
		speed_label.text = "Speed: %.1fx" % value
	print("Game speed set to: %.1fx" % value)

func _on_spawn_ability_pressed() -> void:
	"""Spawn a random ability pickup at player location"""
	var player: Node = get_local_player()
	if not player:
		print("Error: No local player found")
		return

	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world:
		print("Error: World node not found")
		return

	var ability_spawner: Node = world.get_node_or_null("AbilitySpawner")
	if not ability_spawner or not ability_spawner.has_method("spawn_random_ability"):
		print("Error: AbilitySpawner not found")
		return

	# Spawn at player position with slight offset
	var spawn_pos: Vector3 = player.global_position + Vector3(randf_range(-2, 2), 2, randf_range(-2, 2))
	ability_spawner.spawn_random_ability(spawn_pos)
	print("Spawned random ability at: ", spawn_pos)

func _on_kill_player_pressed() -> void:
	"""Kill and respawn the local player"""
	var player: Node = get_local_player()
	if player and player.has_method("respawn"):
		player.respawn()
		DebugLogger.dlog(DebugLogger.Category.UI, "Player killed - respawning...")

func _on_kill_all_pressed() -> void:
	"""Kill all players except the local player"""
	var local_player: Node = get_local_player()
	var players: Array[Node] = get_tree().get_nodes_in_group("players")

	for player in players:
		if player != local_player and player.has_method("receive_damage"):
			# Deal massive damage to kill them instantly
			player.receive_damage(999)

	print("Killed all other players/bots")

func _on_add_score_pressed() -> void:
	"""Add score to local player"""
	var player: Node = get_local_player()
	if player:
		var player_id: int = player.name.to_int()
		var world: Node = get_tree().get_root().get_node_or_null("World")
		if world and world.has_method("add_score"):
			world.add_score(player_id, 5)
			print("Added 5 score to player")

func _on_reset_timer_pressed() -> void:
	"""Reset the match timer"""
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world:
		world.game_time_remaining = 300.0
		print("Match timer reset to 5 minutes")

func _on_end_match_pressed() -> void:
	"""End the match immediately"""
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and world.has_method("end_deathmatch"):
		world.end_deathmatch()
		print("Match ended manually via debug menu")

func _on_collision_shapes_pressed() -> void:
	"""Toggle collision shape visualization"""
	collision_shapes_visible = !collision_shapes_visible

	# Use the setter method instead of direct assignment
	var tree: SceneTree = get_tree()
	tree.set_debug_collisions_hint(collision_shapes_visible)

	if collision_shapes_visible:
		collision_shapes_button.text = "Show Collision: ON"
		print("Collision shapes visible")
	else:
		collision_shapes_button.text = "Show Collision: OFF"
		print("Collision shapes hidden")

func _on_nametags_pressed() -> void:
	"""Toggle debug nametags above players/bots"""
	nametags_enabled = not nametags_enabled

	if nametags_enabled:
		# Spawn nametags for all players/bots
		var players: Array[Node] = get_tree().get_nodes_in_group("players")
		for player in players:
			if not player.get_node_or_null("DebugNametag"):
				var nametag = nametag_script.new()
				nametag.name = "DebugNametag"
				nametag.setup(player)
				player.add_child(nametag)
		print("Debug nametags enabled - showing names above all players/bots")
	else:
		# Remove all nametags
		var players: Array[Node] = get_tree().get_nodes_in_group("players")
		for player in players:
			var nametag = player.get_node_or_null("DebugNametag")
			if nametag:
				nametag.queue_free()
		print("Debug nametags disabled")

	# Update button text
	if nametags_button:
		nametags_button.text = "Show Nametags: " + ("ON" if nametags_enabled else "OFF")

func _on_direction_arrows_pressed() -> void:
	"""Toggle debug direction arrows for bots"""
	direction_arrows_enabled = not direction_arrows_enabled

	if direction_arrows_enabled:
		# Spawn direction arrows for all bots (not players)
		var players: Array[Node] = get_tree().get_nodes_in_group("players")
		for player in players:
			# Only add arrows to bots (ID >= 9000)
			var player_id: int = player.name.to_int()
			if player_id >= 9000:  # It's a bot
				if not player.get_node_or_null("DebugDirectionArrow"):
					var arrow = direction_arrow_script.new()
					arrow.name = "DebugDirectionArrow"
					arrow.setup(player)
					player.add_child(arrow)
		print("Debug direction arrows enabled - showing arrows in front of bots")
	else:
		# Remove all direction arrows
		var players: Array[Node] = get_tree().get_nodes_in_group("players")
		for player in players:
			var arrow = player.get_node_or_null("DebugDirectionArrow")
			if arrow:
				arrow.queue_free()
		print("Debug direction arrows disabled")

	# Update button text
	if direction_arrows_button:
		direction_arrows_button.text = "Bot Direction Arrows: " + ("ON" if direction_arrows_enabled else "OFF")

func _on_regenerate_level_pressed() -> void:
	"""Regenerate the procedural level using current settings"""
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and world.has_method("generate_procedural_level"):
		# Get current level type and size from world
		var level_type: String = world.get("current_level_type") if "current_level_type" in world else "A"
		var level_size: int = world.get("current_level_size") if "current_level_size" in world else 2
		print("Regenerating level (Type: %s, Size: %d)..." % [level_type, level_size])
		world.generate_procedural_level(level_type, true, level_size)

func _on_change_skybox_pressed() -> void:
	"""Change skybox color palette"""
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if world and "skybox_generator" in world:
		var skybox: Node = world.skybox_generator
		if skybox and skybox.has_method("randomize_colors"):
			skybox.randomize_colors()
			print("Skybox colors randomized!")

func _on_trigger_expansion_pressed() -> void:
	"""Trigger mid-round expansion immediately"""
	var world: Node = get_tree().get_root().get_node_or_null("World")
	if not world:
		print("Error: World node not found")
		return

	# Check if game is active
	if not world.game_active:
		print("Error: Cannot trigger expansion - match is not active!")
		print("Start a match first, then trigger the expansion.")
		return

	# Check if already triggered
	if world.expansion_triggered:
		print("Error: Expansion already triggered for this match!")
		return

	print("Debug: Triggering mid-round expansion immediately...")
	if world.has_method("trigger_mid_round_expansion"):
		world.trigger_mid_round_expansion()
	else:
		print("Error: trigger_mid_round_expansion method not found on World")

func get_local_player() -> Node:
	"""Get the local player"""
	var players: Array[Node] = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.is_multiplayer_authority():
			return player
	return null

# ============================================================================
# DEBUG LOGGING HANDLERS
# ============================================================================

func _on_master_debug_toggle() -> void:
	"""Toggle master debug setting"""
	DebugLogger.debug_enabled = not DebugLogger.debug_enabled
	DebugLogger.save_preferences()
	# Rebuild page to update button text
	show_page(current_page)
	print("Master debug logging: ", "ENABLED" if DebugLogger.debug_enabled else "DISABLED")

func _on_enable_all_categories() -> void:
	"""Enable all debug categories"""
	DebugLogger.enable_all()
	# Rebuild page to update checkboxes
	show_page(current_page)
	print("All debug categories enabled")

func _on_disable_all_categories() -> void:
	"""Disable all debug categories"""
	DebugLogger.disable_all()
	# Rebuild page to update checkboxes
	show_page(current_page)
	print("All debug categories disabled")

func _on_category_toggled(enabled: bool, category: int) -> void:
	"""Toggle a specific debug category"""
	if enabled:
		DebugLogger.enable_category(category)
		print("Enabled debug category: ", DebugLogger.CATEGORY_NAMES.get(category, "Unknown"))
	else:
		DebugLogger.disable_category(category)
		print("Disabled debug category: ", DebugLogger.CATEGORY_NAMES.get(category, "Unknown"))

func _on_watch_entity(entity_id: Variant) -> void:
	"""Set which entity to watch (null = all)"""
	if entity_id == null:
		DebugLogger.clear_watched_entity()
	else:
		DebugLogger.set_watched_entity(int(entity_id))
	# Rebuild page to update the "Watching:" label
	show_page(current_page)

func _on_watch_player() -> void:
	"""Watch the human player"""
	var player: Node = get_local_player()
	if player:
		var player_id: int = player.name.to_int()
		DebugLogger.set_watched_entity(player_id)
		# Rebuild page to update the "Watching:" label
		show_page(current_page)
	else:
		print("Error: No local player found")
