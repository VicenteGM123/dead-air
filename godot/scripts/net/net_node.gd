# Net node (MP_SPEC §3): the Node child of Game named "Net" (/root/Game/Net, the same NodePath on every peer) that
# carries the @rpc functions of the net system (scripts/net/net.gd, game.net). It holds no state: every RPC hands its
# payload to net._recv(kind, from, a, b, c, d), which queues it (simulated network conditions, see net.gd) and
# dispatches it at the start of the next frame (net.update, first thing in Game._tick).
# Star topology with an EXPLICIT host relay (SceneMultiplayer's automatic server relay is off): clients only talk to
# the host; a client message / stream meant for other peers goes to the host once (_rq / _sq) and the host forwards
# it to the session members with the original sender id (_rl / _sl).
#   _m(sys, method, args)                reliable ch0   direct message (host -> client, client -> host)
#   _rq(target, sys, method, args)       reliable ch0   client -> host: deliver to `target` (0 = every other peer)
#   _rl(origin, sys, method, args)       reliable ch0   host -> client: a message relayed from peer `origin`
#   _s(channel, data)                    unreliable ordered ch1   direct stream (host -> client, client -> host)
#   _sq(channel, data)                   unreliable ordered ch1   client -> host: a stream for every other peer
#   _sl(origin, channel, data)           unreliable ordered ch1   host -> client: a stream relayed from `origin`
#   _ping(t) / _pong(t)                  unreliable ordered ch2   RTT probes (host -> client -> host)
# Arguments arrive untyped and are validated by net.gd (a malformed packet is dropped, never an error).
extends Node

var net = null   # scripts/net/net.gd (set by net.init)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

@rpc("any_peer", "call_remote", "reliable", 0)
func _m(sys, method, args) -> void:
	if net != null:
		net._recv(0, multiplayer.get_remote_sender_id(), sys, method, args, null)

@rpc("any_peer", "call_remote", "reliable", 0)
func _rq(target, sys, method, args) -> void:
	if net != null:
		net._recv(5, multiplayer.get_remote_sender_id(), target, sys, method, args)

@rpc("any_peer", "call_remote", "reliable", 0)
func _rl(origin, sys, method, args) -> void:
	if net != null:
		net._recv(6, multiplayer.get_remote_sender_id(), origin, sys, method, args)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _s(channel, data) -> void:
	if net != null:
		net._recv(1, multiplayer.get_remote_sender_id(), channel, data, null, null)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _sq(channel, data) -> void:
	if net != null:
		net._recv(7, multiplayer.get_remote_sender_id(), channel, data, null, null)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _sl(origin, channel, data) -> void:
	if net != null:
		net._recv(8, multiplayer.get_remote_sender_id(), origin, channel, data, null)

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _ping(t) -> void:
	if net != null:
		net._recv(2, multiplayer.get_remote_sender_id(), t, null, null, null)

@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _pong(t) -> void:
	if net != null:
		net._recv(3, multiplayer.get_remote_sender_id(), t, null, null, null)
