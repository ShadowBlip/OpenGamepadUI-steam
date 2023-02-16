extends Library

# Other interesting commands
# steamcmd +login shadowapex +apps_installed +quit
# Steam Overlay Config is in:
# ~/.steam/steam/userdata/<user_id>/config/localconfig.vdf

const SteamClient := preload("res://plugins/steam/core/steam_client.gd")
const _apps_cache_file: String = "apps.json"

@onready var steam: SteamClient = get_tree().get_first_node_in_group("steam_client")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	logger = Log.get_logger("Steam", Log.LEVEL.DEBUG)
	logger.info("Steam Library loaded")
	steam.logged_in.connect(_on_logged_in)


# Re-load our library when we've logged in
func _on_logged_in(status: SteamClient.LOGIN_STATUS):
	if status != SteamClient.LOGIN_STATUS.OK:
		return

	# Upon login, fetch the user's library without loading it from cache and
	# reconcile it with the library manager.
	logger.debug("Logged in. Updating library cache from Steam.")
	var items: Array = await _load_library(Cache.FLAGS.SAVE)
	for i in items:
		var item: LibraryLaunchItem = i
		# TODO: add/remove instead of reloading the whole library
		if not LibraryManager.has_app(item.name):
			var msg := "App {0} was not loaded. Reloading from cache"
			logger.debug(msg.format([item.name]))
			LibraryManager.reload_library()
			return

	logger.debug("Library is already up-to-date")


# Return a list of installed steam apps. Called by the LibraryManager.
func get_library_launch_items() -> Array[LibraryLaunchItem]:
	return await _load_library(Cache.FLAGS.LOAD | Cache.FLAGS.SAVE)


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
			logger.debug("Available apps exist in cache. Using cache.")
			var items := [] as Array[LibraryLaunchItem]
			for i in json_items:
				var item: Dictionary = i
				items.append(LibraryLaunchItem.from_dict(item))
			return items

	# Wait for the steam client if it's not ready
	if steam.state == steam.STATE.BOOT:
		logger.info("Steam client is not ready yet.")
		return []

	if not steam.is_logged_in:
		logger.info("Steam client is not logged in yet.")
		return []

	logger.info("Fetching Steam library...")
	# Get all available apps
	var app_ids: PackedInt64Array = await _get_available_apps()
	var app_info: Dictionary = await _get_app_info(app_ids)
	var apps_installed: Array = await steam.get_installed_apps()
	var app_ids_installed := PackedStringArray()
	for app in apps_installed:
		app_ids_installed.append(app["id"])

	# Generate launch items for each game
	var items := [] as Array[LibraryLaunchItem]
	for app_id in app_info.keys():
		var item: LibraryLaunchItem = LibraryLaunchItem.new()
		item.provider_app_id = "{0}".format([app_id])
		item.name = app_info[app_id]
		item.command = "steam"
		item.args = ["-silent", "steam://rungameid/" + item.provider_app_id]
		item.tags = ["steam"]
		item.installed = app_id in app_ids_installed
		items.append(item)

	# Cache the discovered apps
	if caching_flags & Cache.FLAGS.SAVE:
		logger.debug("Saving available apps to cache.")
		var json_items := []
		for i in items:
			var item: LibraryLaunchItem = i
			json_items.append(item.to_dict())
		if Cache.save_json(_cache_dir, _apps_cache_file, json_items) != OK:
			logger.warn("Unable to save Steam apps cache")

	return items


# Returns an array of available steamAppIds
func _get_available_apps() -> Array:
	var app_ids = await steam.get_available_apps()
	return app_ids


# Returns the app information for the given app ids
func _get_app_info(app_ids: Array) -> Dictionary:
	var app_info := {}
	for app_id in app_ids:
		var info := await steam.get_app_info(str(app_id))
		if not app_id in info:
			continue
		if not "common" in info[app_id]:
			continue
		if not "type" in info[app_id]["common"]:
			continue
		if info[app_id]["common"]["type"] != "Game":  # Skip non-games
			continue
		if not "name" in info[app_id]["common"]:
			continue
		app_info[app_id] = info[app_id]["common"]["name"]
	return app_info
