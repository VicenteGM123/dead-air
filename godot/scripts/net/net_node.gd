# Net node (MP_SPEC §3): the Node child of Game named "Net" (/root/Game/Net, the same NodePath on every peer) that
# carries the @rpc functions of the net system (scripts/net/net.gd, game.net). It holds no state: every RPC hands its
# payload to net._recv(kind, from, a, b), which queues it (simulated network conditions, see net.gd) and dispatches
# it at the start of the next frame (net.update, first thing in Game._tick). The sender id is the original peer even
# for packets relayed by the host (SceneMultiplayer server relay keeps it in get_remote_sender_id()).
#   _m(sys, method, args)   reliable, channel 0: messages (net.toHost / toAll / everyone / toPeer / toOthers)
#   _s(channel, data)       unreliable ordered, channel 1: streams (net.stream, the 30 Hz player state stream)
#   _ping(t) / _pong(t)     unreliable ordered, channel 2: RTT probes (host -> client -> host)
# Arguments arrive untyped and are validated by net.gd (a malformed packet is dropped, never an error).
extends Node

var net = null   # scripts/net/net.gd (set by net.init)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

@rpc("any_peer", "call_remote", "reliable", 0)
func _m(sys, method, args) -> void:
	if net != null:
		net._recv(0, multiplayer.get_remote_sender_id(), sys, method, args)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _s(channel, data) -> void:
	if net != null:
		net._recv(1, multiplayer.get_remote_sender_id(), channel, data, null)

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _ping(t) -> void:
	if net != null:
		net._recv(2, multiplayer.get_remote_sender_id(), t, null, null)

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _pong(t) -> void:
	if net != null:
		net._recv(3, multiplayer.get_remote_sender_id(), t, null, null)
