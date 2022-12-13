extends Control

const SteamClient := preload("res://plugins/steam/core/steam/client.gd")
const enums := preload("res://plugins/steam/core/steam/enums.gd")

@onready var status_label := $ContentContainer/StatusContainer/CurrentStatusLabel
@onready var connected_label := $ContentContainer/StatusContainer/CurrentConnectedLabel
@onready var logged_in_label := $ContentContainer/StatusContainer/CurrentLoggedInLabel
@onready var user_box := $ContentContainer/StatusContainer/UsernameBox
@onready var pass_box := $ContentContainer/StatusContainer/PasswordBox
@onready var tfa_label := $ContentContainer/StatusContainer/TFALabel
@onready var tfa_box := $ContentContainer/StatusContainer/TFABox
@onready var login_button := $ContentContainer/HBoxContainer/LoginButton
@onready var info_label := $ContentContainer/InfoLabel

@onready var steam_client: SteamClient = get_tree().get_first_node_in_group("steam_client")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Set the status label
	status_label.text = "Not running"
	var set_running := func():
		status_label.text = "Running"
	if steam_client.client_started:
		set_running.call()
	steam_client.steam_client_started.connect(set_running)
	
	# Set the connection label
	connected_label.text = "No"
	if steam_client.client_ready:
		_on_client_ready()
	steam_client.steam_client_ready.connect(_on_client_ready)
	
	# Set our label if we log in
	var on_login := func():
		logged_in_label.text = "Yes"
	steam_client.logged_in.connect(on_login)

	# Connect the login button
	login_button.pressed.connect(_on_login)


func _on_client_ready():
	connected_label.text = "Yes"


func _on_login():
	info_label.text = ""
	var username: String = user_box.text
	var password: String = pass_box.text
	var tfa_code = null
	if tfa_box.text != "":
		tfa_code = tfa_box.text
	var response = await steam_client.login(username, password, null, null, tfa_code)
	
	# Un-hide the 2fa box if we require two-factor auth
	if response == enums.EResult.AccountLoginDeniedNeedTwoFactor:
		tfa_box.visible = true
		tfa_label.visible = true
		info_label.text = "Please enter your Steam Guard code and login"
		info_label.visible = true
		return

	# If we logged, woo!
	if response == enums.EResult.OK:
		info_label.text = "Logged in!"
		logged_in_label.text = "Yes"
		return

