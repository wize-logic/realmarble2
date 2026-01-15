extends PanelContainer

## Profile Panel UI
## Displays user profile information and stats

@onready var username_label: Label = $MarginContainer/VBox/Header/Username
@onready var profile_picture: TextureRect = $MarginContainer/VBox/Header/ProfilePicture
@onready var auth_status_label: Label = $MarginContainer/VBox/Header/AuthStatus
@onready var login_button: Button = $MarginContainer/VBox/Header/LoginButton
@onready var link_account_button: Button = $MarginContainer/VBox/Header/LinkAccountButton

# Stats labels
@onready var total_kills_label: Label = $MarginContainer/VBox/Stats/KillsValue
@onready var total_deaths_label: Label = $MarginContainer/VBox/Stats/DeathsValue
@onready var kd_ratio_label: Label = $MarginContainer/VBox/Stats/KDValue
@onready var total_matches_label: Label = $MarginContainer/VBox/Stats/MatchesValue
@onready var total_wins_label: Label = $MarginContainer/VBox/Stats/WinsValue
@onready var win_rate_label: Label = $MarginContainer/VBox/Stats/WinRateValue

@onready var close_button: Button = $MarginContainer/VBox/Header/CloseButton

signal closed

func _ready() -> void:
	# Connect signals
	if ProfileManager:
		ProfileManager.profile_loaded.connect(_on_profile_loaded)
		ProfileManager.profile_updated.connect(_on_profile_updated)

	# Connect button signals
	if login_button:
		login_button.pressed.connect(_on_login_pressed)
	if link_account_button:
		link_account_button.pressed.connect(_on_link_account_pressed)
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Load initial profile
	_update_profile_display()

func _on_profile_loaded(profile: Dictionary) -> void:
	_update_profile_display()

func _on_profile_updated(profile: Dictionary) -> void:
	_update_profile_display()

func _update_profile_display() -> void:
	if not ProfileManager:
		return

	var profile = ProfileManager.get_profile()

	# Update username
	if username_label:
		username_label.text = profile.get("username", "Guest")

	# Update auth status
	var is_authenticated = profile.get("isAuthenticated", false)
	if auth_status_label:
		auth_status_label.text = "Authenticated" if is_authenticated else "Guest"
		auth_status_label.modulate = Color.GREEN if is_authenticated else Color.GRAY

	# Show/hide login buttons
	if login_button:
		login_button.visible = not is_authenticated
	if link_account_button:
		link_account_button.visible = is_authenticated

	# Update stats
	var stats = profile.get("stats", {})

	if total_kills_label:
		total_kills_label.text = str(stats.get("total_kills", 0))

	if total_deaths_label:
		total_deaths_label.text = str(stats.get("total_deaths", 0))

	if kd_ratio_label:
		var kd = ProfileManager.get_kd_ratio()
		kd_ratio_label.text = "%.2f" % kd

	if total_matches_label:
		total_matches_label.text = str(stats.get("total_matches", 0))

	if total_wins_label:
		total_wins_label.text = str(stats.get("total_wins", 0))

	if win_rate_label:
		var matches = stats.get("total_matches", 0)
		var wins = stats.get("total_wins", 0)
		var win_rate = 0.0
		if matches > 0:
			win_rate = (float(wins) / float(matches)) * 100.0
		win_rate_label.text = "%.1f%%" % win_rate

func _on_login_pressed() -> void:
	if ProfileManager:
		ProfileManager.show_login()

func _on_link_account_pressed() -> void:
	if ProfileManager:
		ProfileManager.show_account_link()

func _on_close_pressed() -> void:
	closed.emit()
	hide()

func show_panel() -> void:
	_update_profile_display()
	# Show the backdrop (which contains this panel)
	if has_meta("backdrop"):
		var backdrop = get_meta("backdrop")
		backdrop.show()
	else:
		show()
