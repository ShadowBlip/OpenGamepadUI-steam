extends Library

# Other interesting commands
# steamcmd +login shadowapex +apps_installed +quit

@export var use_caching: bool = true

const SteamClient := preload("res://plugins/steam/core/steam/client.gd")
const _apps_cache_file: String = "apps.json"
const _app_info_cache_file: String = "app_info.json"
var _steam_dir: String = "/".join([OS.get_environment("HOME"), ".steam"])
var _steam_registry: String = _steam_dir + "/registry.vdf"

@onready var steam_client: SteamClient = get_tree().get_first_node_in_group("steam_client")
@onready var library_manager: LibraryManager = get_tree().get_first_node_in_group("library_manager")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	logger = Log.get_logger("Steam", Log.LEVEL.DEBUG)
	logger.info("Steam Library loaded")
	steam_client.logged_in.connect(_on_logged_in)


# Re-load our library when we've logged in
func _on_logged_in():
	library_manager.reload_library()


# Return a list of installed steam apps
# TODO: Figure out Steam auth
func get_library_launch_items() -> Array:
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

	# Load the local Steam registry
	var registry: Dictionary = _load_registry(_steam_registry)

	# Generate launch items for each game
	var items := []
	for app_id in app_info.keys():
		var item: LibraryLaunchItem = LibraryLaunchItem.new()
		item.provider_app_id = "{0}".format([app_id])
		item.name = app_info[app_id]
		item.command = "steam"
		item.args = ["-silent", "-applaunch", item.provider_app_id]
		item.tags = ["steam"]
		item.installed = _is_installed(registry, item.provider_app_id)
		items.append(item)

	return items


# Returns an array of available steamAppIds
func _get_available_apps() -> Array:
	var app_ids = await steam_client.list_apps()
	return app_ids
#	# Check to see if we've cached available apps
#	if use_caching:
#		var cached = load_cache_json(_apps_cache_file)
#		if cached != null:
#			return cached
#
#	var output: Array = []
#	var code = OS.execute("steamctl", ["-l", "quiet", "apps", "list"], output)
#	if code != OK:
#		logger.error("Error executing steamctl")
#		return PackedStringArray()
#
#	var app_ids: PackedStringArray = PackedStringArray([])
#	for out in output:
#		var lines: Array = out.split("\n")
#		for line in lines:
#			if line == "":
#				continue
#			var app: Array = line.split(" ")
#			var appId: String = app[0]
#			app.pop_front()
#			var appName: String = " ".join(app)
#			if appName.contains("Unknown App"):
#				continue
#
#			app_ids.append(appId)
#
#	# Save our apps to cache
#	if use_caching:
#		save_cache_json(_apps_cache_file, app_ids)
#
#	return app_ids
	

# Returns the app information for the given app ids
func _get_app_info(app_ids: Array) -> Dictionary:
	var app_info = await steam_client.get_product_name(app_ids)
	return app_info
	
#	# Check to see if we've cached available apps
#	if use_caching:
#		var cached = load_cache_json(_app_info_cache_file)
#		if cached != null:
#			return cached
#
#	var output: Array = []
#	var args: Array = ["-l", "quiet", "apps", "product_info"]
#	args.append_array(app_ids)
#	var code = OS.execute("steamctl", args, output)
#
#	for out in output:
#		var parsed = JSON.parse_string(out)
#		if parsed == null:
#			logger.error("Error parsing app info")
#			return {}
#
#		if use_caching:
#			save_cache_json(_app_info_cache_file, parsed)
#
#		return parsed
#
#	return {}
	

func _load_registry(registry_vdf: String) -> Dictionary:
	if OS.execute("vdf2json", [registry_vdf, "/tmp/steam_registry.json"]) != OK:
		logger.error("Error converting " + registry_vdf + " vdf registry to json")
		return {}
	
	var file: FileAccess = FileAccess.open("/tmp/steam_registry.json", FileAccess.READ)
	var text: String = file.get_as_text()
	
	return JSON.parse_string(text)


func _is_game(app_info: Dictionary) -> bool:
	if not "common" in app_info:
		return false
	if not "type" in app_info["common"]:
		return false
	if app_info["common"]["type"] != "Game":
		return false
	return true


func _is_installed(registry: Dictionary, app_id: String) -> bool:
	if not "Registry" in registry:
		return false
	if not "HKCU" in registry["Registry"]:
		return false
	if not "Software" in registry["Registry"]["HKCU"]:
		return false
	if not "Valve" in registry["Registry"]["HKCU"]["Software"]:
		return false
	if not "Steam" in registry["Registry"]["HKCU"]["Software"]["Valve"]:
		return false
	if not "apps" in registry["Registry"]["HKCU"]["Software"]["Valve"]["Steam"]:
		return false
	if not app_id in registry["Registry"]["HKCU"]["Software"]["Valve"]["Steam"]["apps"]:
		return false
	if not "installed" in registry["Registry"]["HKCU"]["Software"]["Valve"]["Steam"]["apps"][app_id]:
		return false
	if registry["Registry"]["HKCU"]["Software"]["Valve"]["Steam"]["apps"][app_id]["installed"] == "1":
		return true
	return false
