extends Node

# This script loaded globally is a singleton:
# Project > Project Settings > Globals > WebSocketServer


signal message_received(msg : String)
signal message_sent(msg : String)
signal peer_connected(peer_id : int)
signal peer_disconnected(peer_id : int)
signal peer_count_changed(count : int)


@export var port : int = 8080
@export var websocket_url := "ws://localhost"

const PEER_CLOSE_TIMEOUT_SEC := 10

var _tcp_server : TCPServer
var _peers : Dictionary[int, WebSocketPeer] = {}
var _last_peer_id := 1


func _enter_tree() -> void:
	_tcp_server = TCPServer.new()
	var err = _tcp_server.listen(port)
	if err == OK:
		print("Server started.")
	else:
		push_error("Unable to start server.")
		set_process(false)


func _exit_tree() -> void:
	await shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		var tree := get_tree()
		tree.auto_accept_quit = false
		await shutdown()
		tree.auto_accept_quit = true
		tree.quit()


func shutdown() -> void:
	var queued := is_queued_for_deletion()
	if queued: cancel_free()
	
	if _tcp_server and is_instance_valid(_tcp_server):
		if _tcp_server.is_listening():
			_tcp_server.stop()
		for peer : WebSocketPeer in _peers.values():
			peer.close(1001, "Going Away") #RFC 6455 compliant
		
		var tree := get_tree()
		var initial_time := Time.get_ticks_msec()
		var total_num_peers := _peers.size()
		
		while not _peers.is_empty() and ((Time.get_ticks_msec() - initial_time) / 1000) < PEER_CLOSE_TIMEOUT_SEC:
			var closed_ids : Array[int] = []
			for peer : WebSocketPeer in _peers.values():
				peer.poll()
				if peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
					closed_ids.append(_peers.find_key(peer))
			for peer_id : int in closed_ids:
				_peers.erase(peer_id)
		
		if not _peers.is_empty():
			var feedback := "%d out of %d peers did not close cleanly:" % [_peers.size(), total_num_peers]
			for peer : WebSocketPeer in _peers.values():
				feedback += "\n\t- " + peer.get_connected_host()
			print(feedback)
		_peers.clear()
		_tcp_server.unreference()
		print("Server shutdown properly.")
		
		# allows print to flush to terminal before exiting (it's often too quick otherwise)
		await tree.create_timer(0.1).timeout
	
	if queued: queue_free()


func _process(delta: float) -> void:
	while _tcp_server.is_connection_available():
		_last_peer_id += 1
		print("+ Peer %d connected." % _last_peer_id)
		var ws = WebSocketPeer.new()
		ws.accept_stream(_tcp_server.take_connection())
		_peers[_last_peer_id] = ws
		
		# Send signals so any attached callbacks get triggered
		peer_connected.emit(_last_peer_id)
		peer_count_changed.emit(_peers.size())
	
	for peer_id in _peers.keys():
		var peer := _peers[peer_id]
		
		peer.poll()
		
		var peer_state = peer.get_ready_state()
		if peer_state == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count():
				var packet = peer.get_packet()
				if peer.was_string_packet():
					var packet_text = packet.get_string_from_utf8()
					print("< Got text data from peer %d: %s ... inverting and echoing" % [peer_id, packet_text])
					message_received.emit(packet_text)
					var response := packet_text.reverse()
					peer.send_text(response)
					message_sent.emit(response)
				else:
					print("< Got binary data from peer %d... echoing" % [peer_id, packet.size()])
					var packet_as_str := JSON.stringify(packet)
					message_received.emit(packet_as_str)
					peer.send(packet)
					message_sent.emit(packet_as_str)
		elif peer_state == WebSocketPeer.STATE_CLOSED:
			_peers.erase(peer_id)
			
			var code = peer.get_close_code()
			var reason = peer.get_close_reason().strip_edges()
			var feedback := "- Peer %s closed with code: %d" % [peer_id, code]
			feedback += "; Reason: %s" % ("No Reason Provided" if reason.is_empty() else reason)
			feedback += "; Clean: %s" % (code != -1)
			print(feedback)
			
			peer_disconnected.emit(peer_id)
			peer_count_changed.emit(_peers.size())


func is_active() -> bool:
	return _tcp_server.is_listening() or not _peers.is_empty()


func get_peer_count() -> int:
	return _peers.size()
