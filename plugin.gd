extends Plugin

const SteamClient := preload("res://plugins/steam/core/steam_client.gd")

var settings_manager := load("res://core/global/settings_manager.tres") as SettingsManager
var notification_manager := load("res://core/global/notification_manager.tres") as NotificationManager
var launch_manager := load("res://core/global/launch_manager.tres") as LaunchManager
var settings_menu := load("res://plugins/steam/core/steam_settings.tscn") as PackedScene
var icon := preload("res://plugins/steam/assets/steam.svg")

var steam: SteamClient
var user := settings_manager.get_value("plugin.steam", "user", "") as String


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logger = Log.get_logger("Steam", Log.LEVEL.INFO)

	# Load the Steam client
	@warning_ignore("unsafe_method_access")
	steam = load("res://plugins/steam/core/steam_client.tscn").instantiate()
	steam.bootstrap_finished.connect(_on_client_start)
	steam.client_ready.connect(_on_client_ready)
	steam.logged_in.connect(_on_client_logged_in)
	add_child(steam)

	# Load the Steam Store implementation
	#var store: Node = load(plugin_base + "/core/store.tscn").instantiate()
	#add_child(store)

	# Load the Library implementation
	@warning_ignore("unsafe_method_access")
	var library: Library = load("res://plugins/steam/core/library_steam.tscn").instantiate()
	add_child(library)

	# Load the boxart implementation
	@warning_ignore("unsafe_method_access")
	var boxart: BoxArtProvider = load("res://plugins/steam/core/boxart_steam.tscn").instantiate()
	add_child(boxart)


# Triggers when Steam has started
func _on_client_start():
	# Ensure the client was started
	if steam.client_started:
		return
	_ui_notification("Unable to start steam client")


# Triggers when the Steam Client is ready
func _on_client_ready():
	# Check our settings to see if we have logged in before
	if user == "" or not steam.has_steamcmd_session():
		_ui_notification("Steam login required")
		return

	if not steam.has_steamcmd_session():
		return

	# If we have logged in before, try logging in with saved credentials
	logger.info("Previous session exists. Trying to log in with existing session.")
	if steam.restore_steamcmd_session() != OK:
		logger.error("Failed to restore previous steam session")
		return
	logger.info("Session restored successfully")
	steam.login(user)


# Triggers when the Steam Client is logged in
func _on_client_logged_in(status: SteamClient.LOGIN_STATUS):
	if status == SteamClient.LOGIN_STATUS.OK:
		# After successful login, save the credentials so they can be restored if needed
		steam.save_steamcmd_session()
		steam.enable_proton()
		_ui_notification("Successfully logged in to Steam")
		await _ensure_tools_installed()
		if not steam.has_steam_run():
			_on_first_boot.call_deferred()

	if status == SteamClient.LOGIN_STATUS.WAITING_GUARD_CONFIRM:
		_ui_notification("Please confirm the login in the Steam Mobile app on your phone.")

	if status == SteamClient.LOGIN_STATUS.INVALID_PASSWORD:
		_ui_notification("Steam login required")

	if status == SteamClient.LOGIN_STATUS.TFA_REQUIRED:
		_ui_notification("SteamGuard code required")

	if status == SteamClient.LOGIN_STATUS.FAILED:
		_ui_notification("Failed to login to Steam")


## Ensure tool dependencies are installed
func _ensure_tools_installed() -> void:
	# Get list of currently installed apps
	logger.debug("Fetching installed apps")
	var installed_apps := await steam.get_installed_apps()
	var installed_app_ids := []
	for app in installed_apps:
		if not "id" in app:
			continue
		installed_app_ids.push_back(app["id"])

	# Linux Runtime
	const SNIPER_APP_ID := "1628350"
	if not SNIPER_APP_ID in installed_app_ids:
		_ui_notification("Installing Sniper Linux Runtime")
		var completed := await _install_tool(SNIPER_APP_ID) as bool
		if not completed:
			_ui_notification("Failed to install Sniper Linux Runtime")

	# Proton
	const PROTON_APP_ID := "1493710"
	if not PROTON_APP_ID in installed_app_ids:
		_ui_notification("Installing Proton Experimental")
		var completed := await _install_tool(PROTON_APP_ID) as bool
		if not completed:
			_ui_notification("Failed to install Proton Experimental")

	# Common Redistributables
	const REDIST_APP_ID := "228980"
	if not REDIST_APP_ID in installed_app_ids:
		_ui_notification("Installing Steamworks Common Redistributables")
		var completed := await _install_tool(REDIST_APP_ID) as bool
		if not completed:
			_ui_notification("Failed to install Steamworks Common Redistributables")


## Triggers if Steam has never been run on the system
func _on_first_boot() -> void:
	var display := OS.get_environment("DISPLAY")
	if display.is_empty():
		display = ":0"
	var home := OS.get_environment("HOME")

	# Launch steam in a pty
	var pty := Pty.new()
	var cmd := "env"
	var args := ["-i", "HOME=" + home, "DISPLAY=" + display, "steam", "-silent"]
	pty.exec(cmd, PackedStringArray(args))
	add_child(pty)

	# Read the output from the command
	var on_output := func(line: String):
		logger.info("STEAM BOOTSTRAP:", line)
		if line.contains("Update complete, launching"):
			pty.kill()
	pty.line_written.connect(on_output)

	# Wait until the command has finished
	await pty.finished
	remove_child(pty)
	pty.queue_free()
	logger.info("STEAM BOOTSTRAP: finished")


## Installs the given tool
func _install_tool(app_id: String) -> bool:
	# Start installing
	steam.install(app_id)
	
	# Wait for the app_installed signal
	var success := false
	var installed_app := ""
	while installed_app != app_id:
		var results = await steam.app_installed
		installed_app = results[0]
		success = results[1]
	logger.info("Install of tool " + app_id + " completed with status: " + str(success))
	return success


## Show a UI notification with the given message
func _ui_notification(msg: String) -> void:
	logger.info(msg)
	var notify := Notification.new(msg)
	notify.icon = icon
	notification_manager.show(notify)


# Return the settings menu scene
func get_settings_menu() -> Control:
	return settings_menu.instantiate()
