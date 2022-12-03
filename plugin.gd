extends Plugin


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#var store: Node = load(plugin_base + "/core/store.tscn").instantiate()
	#add_child(store)
	var library: Library = load(plugin_base + "/core/library_steam.tscn").instantiate()
	add_child(library)
	var boxart: BoxArtProvider = load(plugin_base + "/core/boxart_steam.tscn").instantiate()
	add_child(boxart)
