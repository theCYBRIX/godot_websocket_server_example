extends Control


@onready var status_text: Label = $VBoxContainer/CenterContainer/VBoxContainer/Status/StatusText
@onready var peers_text: Label = $VBoxContainer/CenterContainer/VBoxContainer/PeerCount/PeersText
@onready var sent_text: Label = $VBoxContainer/CenterContainer/VBoxContainer/Sent/SentText
@onready var received_text: Label = $VBoxContainer/CenterContainer/VBoxContainer/Received/ReceivedText


var _server_active : bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if WebSocketServer.is_active() != _server_active:
		_server_active = !_server_active
		status_text.text = "Active" if _server_active else "Inactive"
		_on_peer_count_changed(WebSocketServer.get_peer_count())


func _on_peer_count_changed(count : int) -> void:
		peers_text.text = "%d" % count if _server_active else "N/A"


func _on_message_sent(msg : String) -> void:
	sent_text.text = msg


func _on_message_received(msg : String) -> void:
	received_text.text = msg


func _enter_tree() -> void:
	WebSocketServer.message_received.connect(_on_message_received)
	WebSocketServer.message_sent.connect(_on_message_sent)
	WebSocketServer.peer_count_changed.connect(_on_peer_count_changed)


func _exit_tree() -> void:
	WebSocketServer.message_received.disconnect(_on_message_received)
	WebSocketServer.message_sent.disconnect(_on_message_sent)
	WebSocketServer.peer_count_changed.disconnect(_on_peer_count_changed)
