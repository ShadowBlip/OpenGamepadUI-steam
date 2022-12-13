extends Node

@export var url: String = "ws://localhost:5000"

signal logged_in()
signal steam_client_started()
signal steam_client_ready()

const enums := preload("res://plugins/steam/core/steam/enums.gd")

var scripts := [
	"res://plugins/steam/scripts/server/env.pex",
	"res://plugins/steam/scripts/server/server.py",
]
var scripts_dir := "user://scripts/steam"
var data_dir := "user://data/steam"
var credentials_dir := "/".join([data_dir, "credentials"])
var server_pid: int
var client_started: bool = false
var client_ready: bool = false
var retry_timer := Timer.new()

var logger := Log.get_logger("SteamClient", Log.LEVEL.DEBUG)

@onready var client := $WebsocketRPCClient

func _ready():
	add_to_group("steam_client")
	# Connect to signals indicating that the Steam Client has started
	var on_client_started := func ():
		add_child(retry_timer)
		retry_timer.timeout.connect(connect_to_client)
		retry_timer.start(1)
	steam_client_started.connect(on_client_started)
	
	# After the steam client is running and connected
	client.socket_connected.connect(_on_connected)
	
	# Start the websockets server Steam Client
	_start_client()


# Starts the steam client websocket server
func _start_client():
	# Load the server scripts from the virtual filesystem and save them to the
	# user directory.
	DirAccess.make_dir_recursive_absolute(scripts_dir)
	for script in scripts:
		var filename := script.split("/")[-1]
		var file := FileAccess.open(script, FileAccess.READ)
		var buffer := PackedByteArray()
		while not file.eof_reached():
			buffer.append_array(file.get_buffer(1024))
		
		var out_file_path := "/".join([scripts_dir, filename])
		var out := FileAccess.open(out_file_path, FileAccess.WRITE_READ)
		out.store_buffer(buffer)
		out.flush()
		var real_path := ProjectSettings.globalize_path(out_file_path)
		OS.execute("chmod", ["+x", real_path])

	# Check to see if there is a pid file for the server
	var pid_file := "/".join([scripts_dir, "server.pid"])
	if FileAccess.file_exists(pid_file):
		var file := FileAccess.open(pid_file, FileAccess.READ)
		var pid_str := file.get_as_text(true).strip_edges()
		var pid := pid_str.to_int()
		if DirAccess.dir_exists_absolute("/proc/{0}".format([pid])):
			logger.info("Steam websocket server already running with pid: {0}".format([pid]))
			# Keep the server running
			#server_pid = pid
			#client_started = true
			#steam_client_started.emit()
			#return
			
			# Kill the server
			OS.kill(pid)
	
	# If it's not already running, start it.
	var env_script := ProjectSettings.globalize_path("/".join([scripts_dir, "env.pex"]))
	var server_script := ProjectSettings.globalize_path("/".join([scripts_dir, "server.py"]))
	var pid := OS.create_process(env_script, ["--", server_script])
	logger.info("Started Steam Websocket server with pid: {0}".format([pid]))
	server_pid = pid
	var file := FileAccess.open(pid_file, FileAccess.WRITE_READ)
	file.store_line("{0}".format([pid]))
	file.flush()
	client_started = true
	steam_client_started.emit()


func _on_connected():
	logger.info("Connected to Steam Client RPC server")
	# Stop trying to connect and set ready
	retry_timer.stop()
	client_ready = true
	steam_client_ready.emit()
	
	# Check to see if we're already logged in, if so, emit our logged in signal
	var is_logged_in = await is_logged_in()
	logger.debug("Logged in: {0}".format([is_logged_in]))
	if is_logged_in:
		logged_in.emit()


func connect_to_client() -> int:
	var status: int = client.open(url)
	if status != OK:
		logger.error("Unable to connect to socket!")
	return status


func load_vdf(path: String) -> Variant:
	return await client.make_request("load_vdf", [path])


func is_logged_in() -> bool:
	return await client.make_request("is_logged_in", [])


func set_credential_location(path: String):
	await client.make_request("set_credential_location", [path])


func relogin_available() -> bool:
	return await client.make_request("relogin_available", [])
	

func relogin() -> Variant:
	var result = await client.make_request("relogin", [])
	if result == enums.EResult.OK:
		logged_in.emit()
	return result


func login(user: String, passwd: String = "", login_key = null, auth_code = null, two_factor_code = null, login_id = null) -> Variant:
	var result = await client.make_request("login", [user, passwd, login_key, auth_code, two_factor_code, login_id])
	if result == enums.EResult.OK:
		logged_in.emit()
	return result


func list_apps() -> Variant:
	return await client.make_request("list_apps", [])


func get_product_info(apps: Array = [], packages: Array = [], meta_data_only: bool = false, auto_access_tokens: bool = true, timeout: int = 15):
	return await client.make_request("get_product_info", [apps, packages, meta_data_only, auto_access_tokens, timeout])


func get_product_name(apps: Array = []):
	return await client.make_request("get_product_name", [apps])
