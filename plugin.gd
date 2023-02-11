extends Plugin

const settings_menu := preload("res://plugins/steam/core/ui/steam_settings.tscn")
const SteamClient := preload("res://plugins/steam/core/steam/client.gd")
const icon := preload("res://plugins/steam/assets/steam.svg")

var steam: SteamClient


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logger = Log.get_logger("Steam", Log.LEVEL.DEBUG)

	# Load the Steam client
	steam = load(plugin_base + "/core/steam/client.tscn").instantiate()
	steam.steam_client_ready.connect(_on_client_ready)
	steam.logged_in.connect(_on_client_logged_in)
	add_child(steam)

	# Load the Steam Store implementation
	#var store: Node = load(plugin_base + "/core/store.tscn").instantiate()
	#add_child(store)

	# Load the boxart implementation
	var boxart: BoxArtProvider = load(plugin_base + "/core/boxart_steam.tscn").instantiate()
	add_child(boxart)

	# Load the Library implementation
	var library: Library = load(plugin_base + "/core/library_steam.tscn").instantiate()
	add_child(library)


# Triggers when the Steam Client is ready
func _on_client_ready():
	# If the client isn't logged in, try to log in using saved credentials
	if not await steam.is_logged_in():
		logger.debug("Currently not logged in to Steam. Checking if relogin is available.")
		if await steam.relogin_available():
			logger.info("Relogin is available. Trying to login.")
			var relogin_status = await steam.relogin()
			logger.info("Got relogin response: {0}".format([relogin_status]))
		else:
			logger.debug("Relogin is not available.")

	# If we're still not logged in, show a notification that a login is required.
	if not await steam.is_logged_in():
		logger.info("Steam login required")
		var notify := Notification.new("Steam login required")
		notify.icon = icon
		NotificationManager.show(notify)
	else:
		var notify := Notification.new("Logged in to Steam")
		notify.icon = icon
		logger.info("Steam is already logged in!")


# Triggers when the Steam Client is logged in
func _on_client_logged_in():
	logger.info("Successfully logged in to Steam")


# Return the settings menu scene
func get_settings_menu() -> Control:
	return settings_menu.instantiate()
