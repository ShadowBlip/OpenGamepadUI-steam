extends Control

const SteamClient := preload("res://plugins/steam/core/steam_client.gd")
var settings_manager := load("res://core/global/settings_manager.tres") as SettingsManager
var notification_manager := load("res://core/global/notification_manager.tres") as NotificationManager
const icon := preload("res://plugins/steam/assets/steam.svg")

@onready var status := $%Status
@onready var connected_status := $%ConnectedStatus
@onready var logged_in_status := $%LoggedInStatus
@onready var user_box := $%UsernameTextInput
@onready var pass_box := $%PasswordTextInput
@onready var tfa_box := $%TFATextInput
@onready var login_button := $%LoginButton

@onready var steam: SteamClient = get_tree().get_first_node_in_group("steam_client")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# If we have logged in before, populate the username box
	var user := settings_manager.get_value("plugin.steam", "user", "") as String
	user_box.text = user

	# Set the status label based on the steam client status
	status.status = status.STATUS.CANCELLED
	status.color = "red"
	var set_running := func():
		if not steam.client_started:
			return
		status.status = status.STATUS.ACTIVE
		status.color = "green"
	if steam.client_started:
		set_running.call()
	steam.bootstrap_finished.connect(set_running)
	
	# Set the connection label based on the steam client status
	connected_status.status = connected_status.STATUS.ACTIVE
	if steam.state != steam.STATE.BOOT:
		_on_client_ready()
	steam.client_ready.connect(_on_client_ready)
	
	# Set our label if we log in
	var update_login_status := func(steam_status: SteamClient.LOGIN_STATUS):
		if steam_status != SteamClient.LOGIN_STATUS.OK:
			logged_in_status.status = logged_in_status.STATUS.ACTIVE
			logged_in_status.color = "gray"
			return
		logged_in_status.status = logged_in_status.STATUS.CLOSED
		logged_in_status.color = "green"
	steam.logged_in.connect(update_login_status)
	steam.logged_in.connect(_on_login)

	# Connect the login button
	login_button.pressed.connect(_on_login_button)

	# Focus on the next input when username or password is submitted 
	var on_user_submitted := func():
		pass_box.grab_focus.call_deferred()
	user_box.keyboard_context.submitted.connect(on_user_submitted)
	var on_pass_submitted := func():
		if tfa_box.visible:
			tfa_box.grab_focus.call_deferred()
			return
		login_button.grab_focus.call_deferred()
	pass_box.keyboard_context.submitted.connect(on_pass_submitted)


func _on_client_ready() -> void:
	connected_status.color = "green"


func _on_login(login_status: SteamClient.LOGIN_STATUS) -> void:
	# Un-hide the 2fa box if we require two-factor auth
	if login_status == SteamClient.LOGIN_STATUS.TFA_REQUIRED:
		tfa_box.visible = true
		tfa_box.grab_focus.call_deferred()

		var notify := Notification.new("Two-factor authentication required")
		notify.icon = icon
		notification_manager.show(notify)

		return

	# If we logged, woo!
	if login_status == SteamClient.LOGIN_STATUS.OK:
		logged_in_status.status = logged_in_status.STATUS.CLOSED
		logged_in_status.color = "green"
		
		var notify := Notification.new("Successfully logged in to Steam")
		notify.icon = icon
		notification_manager.show(notify)
		
		return


# Called when the login button is pressed
func _on_login_button() -> void:
	var username: String = user_box.text
	var password: String = pass_box.text
	var tfa_code: String = tfa_box.text
	settings_manager.set_value("plugin.steam", "user", username)
	steam.login(username, password, tfa_code)
