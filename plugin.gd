extends Plugin

const SteamClient := preload("res://plugins/steam/core/steam_client.gd")
const SettingsManager := preload("res://core/global/settings_manager.tres")
const NotificationManager := preload("res://core/global/notification_manager.tres")
const settings_menu := preload("res://plugins/steam/core/steam_settings.tscn")
const icon := preload("res://plugins/steam/assets/steam.svg")

var steam: SteamClient
var user := SettingsManager.get_value("plugin.steam", "user", "") as String


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logger = Log.get_logger("Steam", Log.LEVEL.DEBUG)

	# Load the Steam client
	steam = load("res://plugins/steam/core/steam_client.tscn").instantiate()
	steam.ready.connect(_on_client_start)
	steam.client_ready.connect(_on_client_ready)
	steam.logged_in.connect(_on_client_logged_in)
	add_child(steam)

	# Load the Steam Store implementation
	#var store: Node = load(plugin_base + "/core/store.tscn").instantiate()
	#add_child(store)

	# Load the boxart implementation
	var boxart: BoxArtProvider = load("res://plugins/steam/core/boxart_steam.tscn").instantiate()
	add_child(boxart)

	# Load the Library implementation
	var library: Library = load("res://plugins/steam/core/library_steam.tscn").instantiate()
	add_child(library)


# Triggers when Steam has started
func _on_client_start():
	# Ensure the client was started
	if not steam.client_started:
		var notify := Notification.new("Unable to start steam client")
		notify.icon = icon
		logger.error(notify.text)
		NotificationManager.show(notify)
		return


# Triggers when the Steam Client is ready
func _on_client_ready():
	# Check our settings to see if we have logged in before
	if user == "":
		var notify := Notification.new("Steam login required")
		notify.icon = icon
		logger.info(notify.text)
		NotificationManager.show(notify)
		return

	# If we have logged in before, try logging in with saved credentials
	steam.login(user)


# Triggers when the Steam Client is logged in
func _on_client_logged_in(status: SteamClient.LOGIN_STATUS):
	var notify := Notification.new("")
	notify.icon = icon

	if status == SteamClient.LOGIN_STATUS.OK:
		notify.text = "Successfully logged in to Steam"
		logger.info(notify.text)
		return

	if status == SteamClient.LOGIN_STATUS.INVALID_PASSWORD:
		notify.text = "Steam login required"
		logger.info(notify.text)
		return

	if status == SteamClient.LOGIN_STATUS.TFA_REQUIRED:
		notify.text = "SteamGuard code required"
		logger.info(notify.text)
		return

	if status == SteamClient.LOGIN_STATUS.FAILED:
		notify.text = "Failed to login to Steam"
		logger.info(notify.text)
		return


# Return the settings menu scene
func get_settings_menu() -> Control:
	return settings_menu.instantiate()
