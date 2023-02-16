extends Node

## Godot interface for steamcmd
##
## Provides a Godot interface to the steamcmd command. This class relies on 
## [InteractiveProcess] to spawn steamcmd in a psuedo terminal to read and write 
## to its stdout/stdin.

const VDF = preload("res://plugins/steam/core/vdf.gd")

enum STATE {
	BOOT,
	PROMPT,
	EXECUTING,
}

enum LOGIN_STATUS {
	OK,
	FAILED,
	INVALID_PASSWORD,
	TFA_REQUIRED,
}

signal prompt_available
signal command_finished(cmd: String, output: Array[String])
signal command_progressed(cmd: String, output: Array[String], finished: bool)
signal logged_in(status: LOGIN_STATUS)
signal app_installed(app_id: String, success: bool)
signal app_updated(app_id: String, success: bool)
signal app_uninstalled(app_id: String, success: bool)
signal install_progressed(app_id: String, current: int, total: int)

var is_logged_in := false
var proc: InteractiveProcess
var state: STATE = STATE.BOOT

var cmd_queue: Array[String] = []
var current_cmd := ""
var current_output: Array[String] = []

var logger := Log.get_logger("SteamClient", Log.LEVEL.DEBUG)


func _ready() -> void:
	proc = InteractiveProcess.new("steamcmd", ["+@ShutdownOnFailedCommand", "0"])
	proc.start()


## Log in to Steam. This method will fire the 'logged_in' signal with the login 
## status. This should be called again if TFA is required.
func login(user: String, password := "", tfa := "") -> void:
	# Build the command arguments
	var cmd_args := [user]
	if password != "":
		cmd_args.append(password)
	if tfa != "":
		cmd_args.append(tfa)
	var cmd := "login " + " ".join(cmd_args) + "\n"

	# Queue up the login command so we can follow its output
	_queue_command(cmd)
	var status := []

	# This method will get called each time new lines of output are 
	# available from the command we run.
	var on_progress := func(output: Array):
		for line in output:
			# Send the user's password if prompted
			if line.contains("password:"):
				proc.send(password + "\n")
				continue
			# Send the TFA if prompted 
			if line.contains("Steam Guard code:") or line.contains("Two-factor code:"):
				proc.send(tfa + "\n")
				continue
			# Set success if we see we logged in 
			if line.contains("Logged in OK") or line.begins_with("OK"):
				status.append(LOGIN_STATUS.OK)
				is_logged_in = true
				continue

			# Set invalid password status
			if line.contains("Invalid Password"):
				status.append(LOGIN_STATUS.INVALID_PASSWORD)
				continue

			# Set TFA failure status
			if line.contains("need two-factor code"):
				status.append(LOGIN_STATUS.TFA_REQUIRED)
				continue

			# Handle all other failures
			if line.contains("FAILED"):
				status.append(LOGIN_STATUS.FAILED)
				continue

	# Pass the callback which will watch our command output
	await _follow_command(cmd, on_progress)

	# Emit the logged_in signal 
	var login_status := LOGIN_STATUS.FAILED 
	if status.size() > 0:
		login_status = status[-1]
	logged_in.emit(login_status)


## Log the user out of Steam
func logout() -> void:
	await _wait_for_command("logout\n")
	is_logged_in = false


## Returns an array of installed apps
## E.g. [{"id": "1779200", "name": "Thrive", "path": "~/.local/share/Steam/steamapps/common/Thrive"}]
#steamcmd +login <user> +apps_installed +quit
func get_installed_apps() -> Array[Dictionary]:
	var lines := await _wait_for_command("apps_installed\n")
	var apps: Array[Dictionary] = []
	for line in lines:
		# Example line:
		#   "AppID 1779200 : \"Thrive\" : ~/.local/share/.../Thrive "
		if not line.begins_with("AppID"):
			continue
		var app := {}
		var parts := line.split(" : ")
		var id_part := parts[0].strip_edges()
		app["id"] = id_part.split(" ")[-1]
		var name_part := parts[1].strip_edges().trim_prefix('"').trim_suffix('"')
		app["name"] = name_part
		var path_part := parts[2].strip_edges()
		app["path"] = path_part
		apps.append(app)

	return apps


## Returns an array of app ids available to the user
func get_available_apps() -> Array:
	var app_ids := []
	var lines := await _wait_for_command("licenses_print\n")
	for line in lines:
		# Example line:
		# - Apps : 1604030, 1829350,  (2 in total)
		if not line.begins_with(" - Apps"):
			continue

		# Remove the line prefix 
		line = line.split(":")[-1]

		# Remove the line suffix
		line = line.split("(")[0]

		# Split the line into an array by ','
		var parts := line.split(",")
		for part in parts:
			var app_id := part.strip_edges()
			if not app_id.is_valid_int():
				continue
			if app_id in app_ids:
				continue
			app_ids.append(app_id)

	return app_ids


## Returns the app info for the given app
func get_app_info(app_id: String) -> Dictionary:
	var cmd := " ".join(["app_info_print", app_id + "\n"])
	var lines := await _wait_for_command(cmd)

	# Extract the VDF output from the command
	var vdf_string := ""
	var is_vdf_output := false
	for line in lines:
		# Start of the vdf output looks like: "1234"
		if line.begins_with('"') and line.ends_with('"'):
			is_vdf_output = true

		# Skip non-vdf output and append the data if it is
		if not is_vdf_output:
			continue
		vdf_string += line + "\n"

		# End of VDF output
		if line.begins_with("}"):
			break

	# Parse the VDF output
	var vdf: VDF = VDF.new()
	if vdf.parse(vdf_string) != OK:
		var err_line := vdf.get_error_line()
		logger.debug("Error parsing vdf output on line " + str(err_line) + ": " + vdf.get_error_message())
		return {}
	var app_info := vdf.get_data()
	return app_info


## Install the given app. This will emit the 'install_progressed' signal to 
## show install progress and emit the 'app_installed' signal with the status 
## of the installation.
func install(app_id: String) -> void:
	var success := await _update(app_id)
	app_installed.emit(app_id, success)


## Install the given app. This will emit the 'install_progressed' signal to 
## show install progress and emit the 'app_updated' signal with the status 
## of the installation.
func update(app_id: String) -> void:
	var success := await _update(app_id)
	app_updated.emit(app_id, success)


# Shared functionality between app install and app update
func _update(app_id: String) -> bool:
	var cmd := "app_update " + app_id + "\n"
	_queue_command(cmd)
	var success := [] # Needs to be an array to be updated from lambda
	var on_progress := func(output: Array):
		# [" Update state (0x61) downloading, progress: 84.45 (1421013576 / 1682619731)", ""]
		logger.debug("Install progress: " + str(output))
		for line in output:
			if line.contains("Success! "):
				success.append(true)
				continue
			if not line.contains("Update state"):
				continue

			# Look for the pattern: (0 / 1000)
			var regex := RegEx.new()
			regex.compile("\\((\\d+) / (\\d+)\\)")
			var result := regex.search(line)
			if not result:
				continue
			line = result.get_string().trim_prefix("(").trim_suffix(")")
			var parts := line.split("/") as PackedStringArray
			var bytes_cur := (parts[0] as String).strip_edges().to_int()
			var bytes_total := (parts[1] as String).strip_edges().to_int()
			install_progressed.emit(app_id, bytes_cur, bytes_total)

	await _follow_command(cmd, on_progress)
	logger.debug("Install finished with success: " + str(true in success))
	return true in success


## Uninstalls the given app. Will emit the 'app_uninstalled' signal when 
## completed.
func uninstall(app_id: String) -> void:
	await _wait_for_command("app_uninstall " + app_id + "\n")
	app_uninstalled.emit(app_id, true)


# Waits for the given command to finish running and returns the output as an 
# array of lines.
func _wait_for_command(cmd: String) -> Array[String]:
	_queue_command(cmd)
	var out: Array = [""]
	while out[0] != cmd:
		out = await command_finished
	return out[1] as Array[String]


# Waits for the given command to produce some output and executes the given 
# callback with the output.
func _follow_command(cmd: String, callback: Callable) -> void:
	# Signal output: [cmd, output, finished]
	var out: Array = [""]
	var finished = false
	while not finished:
		while out[0] != cmd:
			out = await command_progressed 
		var output := out[1] as Array
		finished = out[2]
		callback.call(output)
		# Clear the inner loop condition to fetch progress again
		out[0] = "" 


# Queues the given command
func _queue_command(cmd: String) -> void:
	cmd_queue.push_back(cmd)


func _process(_delta: float) -> void:
	# Process our command queue
	_process_command_queue()

	# Read the output from the process
	var output := proc.read()

	# Return if there is no output from the process
	if output == "":
		return

	# Split the output into lines
	var lines := output.split("\n")
	current_output.append_array(lines)

	# Print the output of steamcmd, except during login for security reasons
	if not current_cmd.begins_with("login"):
		for line in lines:
			logger.debug("steamcmd: " + line)

	# Signal when command progress has been made 
	if current_cmd != "":
		var out := lines.duplicate()
		command_progressed.emit(current_cmd, out, false)

	# Signal that a steamcmd prompt is available
	if lines[-1].begins_with("Steam>"):
		state = STATE.PROMPT
		prompt_available.emit()

		# If a command was executing, emit its output
		if current_cmd == "":
			return
		var out := current_output.duplicate()
		command_progressed.emit(current_cmd, [], true)
		command_finished.emit(current_cmd, out)
		current_cmd = ""
		current_output.clear()


# Processes commands in the queue by popping the first item in the queue and 
# setting our state to EXECUTING.
func _process_command_queue() -> void:
	if state != STATE.PROMPT or cmd_queue.size() == 0:
		return
	var cmd := cmd_queue.pop_front() as String
	state = STATE.EXECUTING
	current_cmd = cmd
	current_output.clear()
	proc.send(cmd)


func _input(event: InputEvent) -> void:
	if event.is_action_released("ogui_east"):
		proc.send("quit\n")
		proc.stop()
		get_tree().quit()


func _exit_tree() -> void:
	proc.send("quit\n")
	proc.stop()
