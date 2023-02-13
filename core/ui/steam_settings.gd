extends Control

const SteamClient := preload("res://plugins/steam/core/steam/client.gd")
const enums := preload("res://plugins/steam/core/steam/enums.gd")
const icon := preload("res://plugins/steam/assets/steam.svg")

var NotificationManager := (
	load("res://core/global/notification_manager.tres") as NotificationManager
)

@onready var status := $%Status
@onready var connected_status := $%ConnectedStatus
@onready var logged_in_status := $%LoggedInStatus
@onready var user_box := $%UsernameTextInput as ComponentTextInput
@onready var pass_box := $%PasswordTextInput
@onready var tfa_box := $%TFATextInput
@onready var login_button := $%LoginButton

@onready var steam_client: SteamClient = get_tree().get_first_node_in_group("steam_client")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Set the status label
	status.status = status.STATUS.CANCELLED
	status.color = "red"
	var set_running := func():
		status.status = status.STATUS.ACTIVE
		status.color = "green"
	if steam_client.client_started:
		set_running.call()
	steam_client.steam_client_started.connect(set_running)
	
	# Set the connection label
	connected_status.status = connected_status.STATUS.ACTIVE
	if steam_client.client_ready:
		_on_client_ready()
	steam_client.steam_client_ready.connect(_on_client_ready)
	
	# Set our label if we log in
	var on_login := func():
		logged_in_status.status = logged_in_status.STATUS.CLOSED
		logged_in_status.color = "green"
	steam_client.logged_in.connect(on_login)

	# Connect the login button
	login_button.pressed.connect(_on_login)

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


func _on_client_ready():
	connected_status.color = "green"


func _on_login():
	var username: String = user_box.text
	var password: String = pass_box.text
	var tfa_code = null
	if tfa_box.text != "":
		tfa_code = tfa_box.text
	var response = await steam_client.login(username, password, null, null, tfa_code)
	
	# Un-hide the 2fa box if we require two-factor auth
	if response == enums.EResult.AccountLoginDeniedNeedTwoFactor:
		var notify := Notification.new("Please enter your Steam Guard code to log in")
		notify.icon = icon
		NotificationManager.show(notify)
		tfa_box.visible = true
		tfa_box.grab_focus.call_deferred()
		return

	# If we logged, woo!
	if response == enums.EResult.OK:
		var notify := Notification.new("Logged in successfully!")
		notify.icon = icon
		NotificationManager.show(notify)
		logged_in_status.status = logged_in_status.STATUS.CLOSED
		logged_in_status.color = "green"
		return

