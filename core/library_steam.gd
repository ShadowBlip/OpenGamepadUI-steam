extends Library

# Other interesting commands
# steamcmd +login shadowapex +apps_installed +quit

const SteamClient := preload("res://plugins/steam/core/steam/client.gd")
const _apps_cache_file: String = "apps.json"
var steam_dir: String = "/".join([OS.get_environment("HOME"), ".steam"])
var steam_libraryfolders: String = steam_dir + "/steam/steamapps/libraryfolders.vdf"

@onready var steam_client: SteamClient = get_tree().get_first_node_in_group("steam_client")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	logger = Log.get_logger("Steam", Log.LEVEL.DEBUG)
	logger.info("Steam Library loaded")
	steam_client.logged_in.connect(_on_logged_in)


# Re-load our library when we've logged in
func _on_logged_in():
	# Upon login, fetch the user's library without loading it from cache and 
	# reconcile it with the library manager.
	logger.debug("Logged in. Updating library cache from Steam.")
	var items: Array = await _load_library(Cache.FLAGS.SAVE)
	for i in items:
		var item: LibraryLaunchItem = i
		# TODO: add/remove instead of reloading the whole library
		if not library_manager.has_app(item.name):
			logger.debug("App {0} was not loaded. Re-loading library from updated cache.".format([item.name]))
			library_manager.reload_library()
			return
			
	logger.debug("Library is already up-to-date")


# Return a list of installed steam apps. Called by the LibraryManager.
func get_library_launch_items() -> Array:
	return await _load_library(Cache.FLAGS.LOAD|Cache.FLAGS.SAVE)


# Return a list of installed steam apps. Optionally caching flags can be passed to
# determine caching behavior.
# Example:
#   _load_library(Cache.FLAGS.LOAD|Cache.FLAGS.SAVE)
func _load_library(caching_flags: int = Cache.FLAGS.LOAD|Cache.FLAGS.SAVE) -> Array:
	# Check to see if our library was cached. If it was, return the cached
	# items.
	if caching_flags & Cache.FLAGS.LOAD and Cache.is_cached(_cache_dir, _apps_cache_file):
		var json_items = Cache.get_json(_cache_dir, _apps_cache_file)
		if json_items != null:
			logger.debug("Available apps exist in cache. Using cache.")
			var items := []
			for i in json_items:
				var item: Dictionary = i
				items.append(LibraryLaunchItem.from_dict(item))
			return items
	
	# Wait for the steam client if it's not ready
	if not steam_client.client_ready:
		logger.info("Steam client is not ready yet.")
		return []
		
	if not await steam_client.is_logged_in():
		logger.info("Steam client is not logged in yet.")
		return []
	
	logger.info("Fetching Steam library...")
	# Get all available apps
	var app_ids: PackedInt64Array = await _get_available_apps()
	var app_info: Dictionary = await _get_app_info(app_ids)

	# Load the local Steam library folders
	var library_folders: Dictionary = await _load_library_folders(steam_libraryfolders)

	# Generate launch items for each game
	var items := []
	for app_id in app_info.keys():
		var item: LibraryLaunchItem = LibraryLaunchItem.new()
		item.provider_app_id = "{0}".format([app_id])
		item.name = app_info[app_id]
		item.command = "steam"
		item.args = ["-silent", "-applaunch", item.provider_app_id]
		item.tags = ["steam"]
		item.installed = _is_installed(library_folders, item.provider_app_id)
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
	var app_ids = await steam_client.list_apps()
	return app_ids


# Returns the app information for the given app ids
func _get_app_info(app_ids: Array) -> Dictionary:
	var app_info = await steam_client.get_product_name(app_ids)
	return app_info


func _load_library_folders(libraryfolders_vdf: String) -> Dictionary:
	var libraryfolders: Dictionary = await steam_client.load_vdf(libraryfolders_vdf)
	return libraryfolders


func _is_installed(library_folders: Dictionary, app_id: String) -> bool:
	for folder in library_folders['libraryfolders']:
		var apps: Array = library_folders['libraryfolders'][folder]['apps'].keys()
		if apps.has(app_id):
			return true
	return false
