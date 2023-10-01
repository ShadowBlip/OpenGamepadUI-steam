extends Library

# Other interesting commands
# steamcmd +login shadowapex +apps_installed +quit
# Steam Overlay Config is in:
# ~/.steam/steam/userdata/<user_id>/config/localconfig.vdf

const VDF = preload("res://plugins/steam/core/vdf.gd")
const SteamClient := preload("res://plugins/steam/core/steam_client.gd")
const SteamAPIClient := preload("res://plugins/steam/core/steam_api_client.gd")
const _apps_cache_file: String = "apps.json"
const _local_apps_cache_file: String = "local_apps.json"

var thread_pool := load("res://core/systems/threading/thread_pool.tres") as ThreadPool
var steam_api_client := SteamAPIClient.new()
var libraryfolders_path := "/".join([OS.get_environment("HOME"), ".steam/steam/steamapps/libraryfolders.vdf"])

@onready var steam: SteamClient = get_tree().get_first_node_in_group("steam_client")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	add_child(steam_api_client)
	logger = Log.get_logger("Steam", Log.LEVEL.DEBUG)
	logger.info("Steam Library loaded")
	steam.logged_in.connect(_on_logged_in)


# Return a list of installed steam apps. Called by the LibraryManager.
func get_library_launch_items() -> Array[LibraryLaunchItem]:
	return await _load_library(Cache.FLAGS.LOAD | Cache.FLAGS.SAVE)


# Installs the given library item.
func install(item: LibraryLaunchItem) -> void:
	# Start the install
	var app_id := item.provider_app_id
	logger.info("Installing " + item.name + " with app ID: " + app_id)
	# Check if title supports Linux or Windows
	if await _app_supports_linux(app_id):
		await steam.set_platform_type("linux")
	else:
		await steam.set_platform_type("windows")
	steam.install(app_id)

	# Connect to progress updates
	var on_progress := func(id: String, bytes_cur: int, bytes_total: int):
		if id != app_id:
			return
		logger.info("Install progressing: " + str(bytes_cur) + "/" + str(bytes_total))
		var progress: float = float(bytes_cur) / float(bytes_total)
		if bytes_total == 0:
			progress = 0
		install_progressed.emit(item, progress)
	steam.install_progressed.connect(on_progress)

	# Wait for the app_installed signal
	var success := false
	var installed_app := ""
	while installed_app != app_id:
		var results = await steam.app_installed
		installed_app = results[0]
		success = results[1]
	install_completed.emit(item, success)
	logger.info("Install of " + item.name + " completed with status: " + str(success))

	# Disconnect from progress updates 
	steam.install_progressed.disconnect(on_progress)


# Updates the given library item.
func update(item: LibraryLaunchItem) -> void:
	# Start the install
	var app_id := item.provider_app_id
	logger.info("Updating " + item.name + " with app ID: " + app_id)
	steam.install(app_id)

	# Connect to progress updates
	var on_progress := func(id: String, bytes_cur: int, bytes_total: int):
		if id != app_id:
			return
		logger.info("Update progressing: " + str(bytes_cur) + "/" + str(bytes_total))
		install_progressed.emit(item, float(bytes_total)/float(bytes_cur))
	steam.install_progressed.connect(on_progress)

	# Wait for the app_updated signal
	var success := false
	var installed_app := ""
	while installed_app != app_id:
		var results = await steam.app_updated
		installed_app = results[0]
		success = results[1]
	update_completed.emit(item, success)
	logger.info("Update of " + item.name + " completed with status: " + str(success))

	# Disconnect from progress updates 
	steam.install_progressed.disconnect(on_progress)


# Uninstalls the given library item.
func uninstall(item: LibraryLaunchItem) -> void:
	# Start the uninstall
	var app_id := item.provider_app_id
	logger.info("Uninstalling " + item.name + " with app ID: " + app_id)
	steam.uninstall(app_id)

	# Wait for the app_uninstalled signal
	var success := false
	var installed_app := ""
	while installed_app != app_id:
		var results = await steam.app_uninstalled
		installed_app = results[0]
		success = results[1]
	uninstall_completed.emit(item, success)
	logger.info("Uninstall of " + item.name + " completed with status: " + str(success))


# Should return true if the given library item has an update available
func has_update(item: LibraryLaunchItem) -> bool:
	return false


# Re-load our library when we've logged in
func _on_logged_in(status: SteamClient.LOGIN_STATUS):
	if status != SteamClient.LOGIN_STATUS.OK:
		return

	# Upon login, fetch the user's library without loading it from cache and
	# reconcile it with the library manager.
	logger.info("Logged in. Updating library cache from Steam.")
	var cmd := func():
		return await _load_library(Cache.FLAGS.SAVE)
	var items: Array = await thread_pool.exec(cmd)
	for i in items:
		var item: LibraryLaunchItem = i
		if not LibraryManager.has_app(item.name):
			var msg := "App {0} was not loaded. Adding item".format([item.name])
			logger.info(msg)
			launch_item_added.emit(item)
			#LibraryManager.add_library_launch_item(library_id, item)
		# TODO: Update installed status
	
	# TODO: Remove library items that have been deleted

	logger.info("Library is up-to-date")


# Return a list of installed steam apps. Optionally caching flags can be passed to
# determine caching behavior.
# Example:
#   _load_library(Cache.FLAGS.LOAD|Cache.FLAGS.SAVE)
func _load_library(
	caching_flags: int = Cache.FLAGS.LOAD | Cache.FLAGS.SAVE
) -> Array[LibraryLaunchItem]:
	# Check to see if our library was cached. If it was, return the cached
	# items.
	if caching_flags & Cache.FLAGS.LOAD and Cache.is_cached(_cache_dir, _apps_cache_file):
		var json_items = Cache.get_json(_cache_dir, _apps_cache_file)
		if json_items != null:
			logger.info("Available apps exist in cache. Using cache.")
			var items := [] as Array[LibraryLaunchItem]
			for i in json_items:
				var item: Dictionary = i
				var launch_item := LibraryLaunchItem.from_dict(item)
				items.append(LibraryLaunchItem.from_dict(item))
				launch_item_added.emit(launch_item)
			return items

	# Wait for the steam client if it's not ready
	if steam.state == steam.STATE.BOOT:
		logger.info("Steam client is not ready yet.")
		return await _load_local_library(caching_flags)

	if not steam.is_logged_in:
		logger.info("Steam client is not logged in yet.")
		return await _load_local_library(caching_flags)

	logger.info("Fetching Steam library...")
	
	# Get all available apps
	var app_ids: PackedInt64Array = await get_available_apps()

	# Get installed apps
	var apps_installed: Array = await steam.get_installed_apps()
	var app_ids_installed := PackedStringArray()
	for app in apps_installed:
		app_ids_installed.append(app["id"])

	# Get the app info for each discovered game and create a launch item for
	# it.
	var items := [] as Array[LibraryLaunchItem]
	for app_id in app_ids:
		var id := str(app_id)
		var info := await get_app_info(id, caching_flags)
		
		if not id in info:
			continue

		var item := _app_info_to_launch_item(info, str(app_id) in app_ids_installed)
		if not item:
			logger.debug("Unable to create launch item for: " + str(app_id))
			continue
		items.append(item)
		launch_item_added.emit(item)

	# Cache the discovered apps
	if caching_flags & Cache.FLAGS.SAVE:
		logger.debug("Saving available apps to cache.")
		var json_items := []
		for i in items:
			var item: LibraryLaunchItem = i
			json_items.append(item.to_dict())
		if Cache.save_json(_cache_dir, _apps_cache_file, json_items) != OK:
			logger.warn("Unable to save Steam apps cache")

	logger.info("Steam library loaded")

	return items


# Return a list of installed locally installed steam apps. Optionally caching 
# flags can be passed to determine caching behavior.
# Example:
#   _load_local_library(Cache.FLAGS.LOAD|Cache.FLAGS.SAVE)
func _load_local_library(
	caching_flags: int = Cache.FLAGS.LOAD | Cache.FLAGS.SAVE
) -> Array[LibraryLaunchItem]:
	# Ensure there is a libraryfolders file
	if not FileAccess.file_exists(libraryfolders_path):
		logger.warn("The libraryfolders.vdf file was not found at: " + libraryfolders_path)
		return []
	
	# Check to see if our library was cached. If it was, return the cached
	# items.
	if caching_flags & Cache.FLAGS.LOAD and Cache.is_cached(_cache_dir, _local_apps_cache_file):
		var json_items = Cache.get_json(_cache_dir, _local_apps_cache_file)
		if json_items != null:
			logger.info("Local apps exist in cache. Using cache.")
			var items := [] as Array[LibraryLaunchItem]
			for i in json_items:
				var item: Dictionary = i
				var launch_item := LibraryLaunchItem.from_dict(item)
				items.append(LibraryLaunchItem.from_dict(item))
				launch_item_added.emit(launch_item)
			return items

	logger.info("Parsing local Steam library...")
	var vdf_string := FileAccess.get_file_as_string(libraryfolders_path)
	var vdf: VDF = VDF.new()
	if vdf.parse(vdf_string) != OK:
		var err_line := vdf.get_error_line()
		logger.debug("Error parsing vdf output on line " + str(err_line) + ": " + vdf.get_error_message())
		return []
	var libraryfolders := vdf.get_data()
	
	# Parse the library folders
	if not "libraryfolders" in libraryfolders:
		return []
	var app_ids := PackedStringArray()
	var entries := libraryfolders["libraryfolders"] as Dictionary
	for folder in entries.values():
		if not "apps" in folder:
			continue
		var apps := folder["apps"] as Dictionary
		for app_id in apps.keys():
			app_ids.append(app_id)
	
	# Get the app info for each discovered game and create a launch item for
	# it.
	var items := [] as Array[LibraryLaunchItem]
	for app_id in app_ids:
		var id := str(app_id)
		var info := await get_app_info(id, caching_flags)
		
		if not id in info:
			continue

		var item := _app_info_to_launch_item(info, true)
		if not item:
			logger.debug("Unable to create launch item for: " + str(app_id))
			continue
		items.append(item)
		launch_item_added.emit(item)

	# Cache the discovered apps
	if caching_flags & Cache.FLAGS.SAVE:
		logger.debug("Saving local apps to cache.")
		var json_items := []
		for i in items:
			var item: LibraryLaunchItem = i
			json_items.append(item.to_dict())
		if Cache.save_json(_cache_dir, _local_apps_cache_file, json_items) != OK:
			logger.warn("Unable to save Steam apps cache")

	logger.info("Local Steam library loaded")

	return items


# Returns an array of available steamAppIds
func get_available_apps() -> Array:
	var app_ids = await steam.get_available_apps()
	return app_ids


## Returns the app information for the given app ids. This is returned as a
## dictionary where the key is the app ID, and the value is the app info.
func get_apps_info(app_ids: Array, caching_flags: int = Cache.FLAGS.LOAD | Cache.FLAGS.SAVE) -> Dictionary:
	var app_info := {}
	for app_id in app_ids:
		var id := str(app_id)
		var info := await get_app_info(id, caching_flags)
		
		if not id in info:
			continue

		app_info[id] = info
		
	return app_info


## Returns the app info dictionary parsed from the VDF
func get_app_info(app_id: String, caching_flags: int = Cache.FLAGS.LOAD | Cache.FLAGS.SAVE) -> Dictionary:
	# Load the app info from cache if requested
	var cache_key := app_id + ".app_info"
	if caching_flags & Cache.FLAGS.LOAD and Cache.is_cached(_cache_dir, cache_key):
		return Cache.get_json(_cache_dir, cache_key)
	else:
		var info = await steam_api_client.get_app_details(app_id)
		logger.debug("Found app info for " + app_id + ": " + str(info))
		if info == null:
			return {}
		if caching_flags & Cache.FLAGS.SAVE:
			Cache.save_json(_cache_dir, cache_key, info)
		return info


## Builds a library launch item from the given Steam app information from the store API.
func _app_info_to_launch_item(info: Dictionary, is_installed: bool) -> LibraryLaunchItem:
	if info.size() == 0:
		return null

	var app_id := info.keys()[0] as String
	var details := info[app_id] as Dictionary
	if not "data" in details:
		return null
	var data := details["data"] as Dictionary
	if not "type" in data:
		return null
	if not data["type"] == "game":
		return null
	var categories := PackedStringArray()
	if "categories" in data:
		for category in data["categories"]:
			categories.append(category["description"])
	var tags := PackedStringArray()
	if "genres" in data:
		for genre in data["genres"]:
			tags.append((genre["description"] as String).to_lower())

	var item := LibraryLaunchItem.new()
	item.provider_app_id = app_id
	item.name = data["name"]
	item.command = "steam"
	item.args = ["-gamepadui", "-steamos3", "-steampal", "-steamdeck", "-silent", "steam://rungameid/" + app_id]
	item.categories = categories
	item.tags = ["steam"]
	item.tags.append_array(tags)
	item.installed = is_installed
	
	return item


# Returns whether or not the given app id has a Linux binary
func _app_supports_linux(app_id: String) -> bool:
	var info = await steam_api_client.get_app_details(app_id)
	if not app_id in info:
		return false
	if not "data" in info[app_id]:
		return false
	if not "platform" in info[app_id]["data"]:
		return false
	if not "linux" in info[app_id]["data"]["platform"]:
		return false
	
	return info[app_id]["data"]["platform"]["linux"]
