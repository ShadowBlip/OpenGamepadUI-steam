extends BoxArtProvider

const _boxart_dir = "user://boxart/steam"
const _supported_ext = [".jpg", ".png", ".jpeg"]

@export var use_caching: bool = true
var http_image := HTTPImageFetcher.new()

# Maps the layout to a file suffix for caching
var layout_map: Dictionary = {
	LAYOUT.GRID_PORTRAIT: "-portrait",
	LAYOUT.GRID_LANDSCAPE: "-landscape",
	LAYOUT.BANNER: "-banner",
	LAYOUT.LOGO: "-logo",
}

# Maps the layout to the Steam CDN url
var layout_url_map: Dictionary = {
	LAYOUT.GRID_PORTRAIT: "https://steamcdn-a.akamaihd.net/steam/apps/{0}/library_600x900.jpg",
	LAYOUT.GRID_LANDSCAPE: "https://steamcdn-a.akamaihd.net/steam/apps/{0}/header.jpg",
	LAYOUT.BANNER: "https://steamcdn-a.akamaihd.net/steam/apps/{0}/library_hero.jpg",
	LAYOUT.LOGO: "https://steamcdn-a.akamaihd.net/steam/apps/{0}/logo.png",
}


func _init() -> void:
	super()
	# Create the data directory if it doesn't exist
	DirAccess.make_dir_recursive_absolute(_boxart_dir)
	provider_id = "steam"
	logger_name = "BoxArtSteam"


func _ready() -> void:
	super()
	logger.info("Steam BoxArt provider loaded")
	logger._level = Log.LEVEL.INFO
	add_child(http_image)


# Looks for boxart in the local user directory based on the app name
func get_boxart(item: LibraryItem, kind: LAYOUT) -> Texture2D:
	if not kind in layout_map:
		logger.error("Unsupported boxart layout: {0}".format([kind]))
		return null

	# Look for a Steam App ID in the library item
	var steamAppID: String = ""
	for l in item.launch_items:
		var launch_item: LibraryLaunchItem = l
		if launch_item._provider_id == "steam":
			steamAppID = launch_item.provider_app_id
		for arg in launch_item.args:
			if not arg.contains("steam://rungameid/"):
				continue
			steamAppID = arg.split("/")[-1]
	if steamAppID == "":
		logger.debug("No Steam App ID found in library item")
		return null

	# Set our caching flags
	var cache_flags = Cache.FLAGS.NONE
	if use_caching:
		cache_flags = Cache.FLAGS.LOAD | Cache.FLAGS.SAVE

	# Try to fetch the artwork
	logger.debug("Fetching steam box art for: " + item.name)
	var url: String = layout_url_map[kind].format([steamAppID])
	var texture: Texture2D = await http_image.fetch(url, cache_flags)
	if texture == null:
		logger.debug("Image couldn't be downloaded for: " + item.name)
	
	return texture
