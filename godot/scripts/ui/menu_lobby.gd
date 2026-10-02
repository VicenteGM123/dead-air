# DEAD AIR — the MP lobby on the dial (MP_SPEC §3.5; added for online co-op). A helper of menu.gd (game.menu): while
# the character-select dial is the lobby of an MP session, menu._lobby is this object (null in solo, so every solo
# path of the dial is unchanged). It owns no Nodes; menu.gd paints it on the panel pn.lobby (over the dial's UI).
#   Each player tunes their own channel locally. Every peer holds a unique hero (mp-core gives a free one at join,
#   our solo pick when free); a channel whose hero another player holds shows ON AIR: <NAME> on the TV's chyron
#   (menu._drawUI asks claimText()) and the Dymo reads TAKEN BY <NAME>; E / A / a click there is denied (bzzt, the
#   hero pouts). Tuning in a free channel = net.setHero(hero) (when not ours yet; READY waits for the host's echo, a
#   refusal arrives as net:hero) + net.setReady(true): the hero kicks and smiles, the roster's ON AIR lamp lights, the
#   chyron reads ON AIR: YOU. Turning the dial while ready un-readies first. Esc / B: ready ->
#   un-ready; not ready -> leave (net.leave) back to the MULTIPLAYER card (a host with guests is asked once: CLOSE
#   THE STATION?). Tuning in needs game.loaded (always true past the title) and a lobby that is not still on air.
#   Roster (a TV GUIDE card right of the TV, "Tonight's Cast"): up to 4 rows (channel badge, name, hero, ON AIR lamp =
#   ready, ping, HOST / YOU tags), empty channels dashed; for the host the addresses to share (UPnP external IP:port
#   on a Dymo tape, the LAN address under it); joins / leaves toast at its foot.
#   START (host, everyone ready, or the host alone): Enter / E / A / Start / a click on the Dymo -> net.startGame().
#   mp-core broadcasts lobby.phase 'starting' (+ lobby.countdown): every TV plays a 3-2-1 film leader (ui_round_dial
#   ticks), then the 'start' message -> menu.mpStart(hero) -> goLive(): the dive into the screen on every peer, then
#   startNow() -> game.newGame(hero) (mp-core already set game.seed_value).
# API (menu.gd): enter(), tuneIn(), canTune() -> bool, key(e) -> bool, pad(btn) -> bool, update(dt), draw(ci),
#   onNet(event, payload), goLive(heroId) -> bool, startNow(heroId), claimText(heroId) -> String, leader() -> Dictionary,
#   dymo() -> {w1, kc, w2}.
extends RefCounted

const HudScript = preload("res://scripts/ui/hud.gd")

const RX := 1440.0                 # roster card (stage px)
const RY := 150.0
const RW := 450.0
const ROW := 74.0

var m                              # menu.gd
var game
var t := 0.0
var armLeave := -1.0               # host with guests: "CLOSE THE STATION?" armed
var deny := 0.0                    # Dymo shake after a denied tune-in
var cd := -1.0                     # countdown clock (lobby phase 'starting'), -1 = none
var cdDur := 3.0
var cdLast := -1
var live := false                  # goLive() ran: the dive is on
var want := {"ready": false, "hero": "", "t": 99.0, "sent": false}   # our request in flight (the host's echo confirms it)
var lanIp := ""
var upnp := {"state": "pending", "ip": "", "port": 0}
var toast := {"text": "", "t": 99.0}
var msg := {"w1": "", "w2": "", "t": 99.0}   # a transient Dymo line (denied reasons)
var _names := {}                   # peer id -> name (the SIGNED OFF toast of a peer already gone)

func _init(menu) -> void:
	m = menu
	game = menu.game

func _net():
	return game.get("net")

static func _f(pi, k: String, d = null):
	if pi is Dictionary:
		return (pi as Dictionary).get(k, d)
	if pi is Object:
		var v = (pi as Object).get(k)
		return v if v != null else d
	return d

# -------------------------------------------------------------------------------------------- session queries
func isHost() -> bool:
	var n = _net()
	return n != null and n.get("isHost") == true

func localId() -> int:
	var n = _net()
	var v = n.get("localId") if n != null else null
	return int(v) if v != null else 1

func phase() -> String:
	var n = _net()
	var lb = n.get("lobby") if n != null else null
	var ph = _f(lb, "phase", "lobby")
	return str(ph) if ph != null else "lobby"

# Every peer in join order (the host's slot 0 first): [{id, name, hero, ready, ping, me, host}].
func peers() -> Array:
	var n = _net()
	var P = n.get("peers") if n != null else null
	var out: Array = []
	if not (P is Dictionary):
		return out
	var me := localId()
	for id in P:
		var pi = P[id]
		var hero = _f(pi, "hero", "")
		var slot = _f(pi, "slot", null)
		out.append({"id": int(id), "name": str(_f(pi, "name", "PLAYER %d" % int(id))), "hero": str(hero) if hero != null else "",
			"ready": _f(pi, "ready", false) == true, "ping": _f(pi, "ping", -1), "me": int(id) == me, "host": int(id) == 1,
			"slot": int(slot) if slot != null else int(id)})
	out.sort_custom(func(a, b): return a.slot < b.slot if a.slot != b.slot else a.id < b.id)
	return out

func _mine() -> Dictionary:
	for p in peers():
		if p.me:
			return p
	return {}

# Our ready state (a request in flight counts for 2 s, until the host's lobby echo lands).
func ready() -> bool:
	if want.t < 2.0:
		return want.ready
	return _mine().get("ready", false) == true

# The hero we hold (mp-core gives every peer a free hero at join; setHero swaps it, the host keeps them unique).
func held() -> String:
	var h = _mine().get("hero", "")
	return str(h) if h != null else ""

# The other player holding this hero (or {}): that channel can't be tuned in.
func claimant(hero: String) -> Dictionary:
	for p in peers():
		if not p.me and p.hero == hero and hero != "":
			return p
	return {}

# Host: everyone else loaded + ready (net.canStart) and we tuned in ourselves.
func allReady() -> bool:
	var n = _net()
	if n == null or not ready():
		return false
	if n.has_method("canStart"):
		return n.canStart() == true
	for p in peers():
		if not p.me and not p.ready:
			return false
	return true

# The chyron's claim tab for a channel (menu._drawUI): ON AIR: NAME (held by another player), or ON AIR: YOU on our
# own channel once we tuned in.
func claimText(hero: String) -> String:
	var c := claimant(hero)
	if not c.is_empty():
		return "ON AIR: %s" % str(c.name).to_upper()
	if ready() and held() == hero:
		return "ON AIR: YOU"
	return ""

# The countdown's film leader on the TV picture (menu._drawUI): {n, frac} or {}.
func leader() -> Dictionary:
	if cd < 0.0 or live:
		return {}
	var left := maxf(0.0, cdDur - cd)
	var nn := int(ceilf(left))
	if nn < 1:
		return {"n": 1, "frac": 1.0}
	return {"n": nn, "frac": 1.0 - (left - float(nn - 1))}

# -------------------------------------------------------------------------------------------- flow
func enter() -> void:
	t = 0.0
	armLeave = -1.0
	deny = 0.0
	cd = -1.0
	cdLast = -1
	live = false
	want = {"ready": false, "hero": "", "t": 99.0, "sent": false}
	toast.t = 99.0
	msg.t = 99.0
	m._session = true
	lanIp = _localIp()
	var n = _net()
	var u = n.get("upnp") if n != null else null
	if u is Dictionary:
		_upnp(u)
	# the dial starts on the hero we hold (our pick when it was free, else mp-core gave us a free one)
	var h := held()
	if h != "" and h != m.selected:
		var i: int = m._chanIndex(h)
		if i >= 0:
			m._tuneTo(i, true)
	_sync()

func _localIp() -> String:
	var n = _net()
	for k in ["lanIp", "localIp", "lanAddress"]:
		var v = n.get(k) if n != null else null
		if v is String and v != "":
			return v
	var best := ""
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10.") or (a.begins_with("172.") and a.split(".").size() == 4 and int(a.split(".")[1]) >= 16 and int(a.split(".")[1]) <= 31):
			return a
		if best == "":
			best = a
	return best

func _port() -> int:
	var n = _net()
	var p = n.get("port") if n != null else null
	return int(p) if p != null else 31313

# net.upnp {state: off | working | ok | failed, externalIp} or the net:upnp payload {ok, ip}.
func _upnp(u: Dictionary) -> void:
	if u.has("state"):
		var st := str(u.state)
		upnp.state = "ok" if st == "ok" else ("pending" if st == "working" else ("off" if st == "off" else "failed"))
		upnp.ip = str(u.get("externalIp", "")) if u.get("externalIp") != null else ""
	elif u.get("ok") != null:
		upnp.state = "ok" if u.ok == true else "failed"
		upnp.ip = str(u.get("ip", "")) if u.get("ip") != null else ""
	else:
		return
	if upnp.state == "ok" and upnp.ip == "":
		upnp.state = "failed"
	upnp.port = int(u.get("port", _port())) if u.get("port") != null else _port()

func tuneIn() -> void:
	if live or cd >= 0.0:
		return
	var n = _net()
	if n == null:
		return
	if game.loaded == false:
		_deny("PLEASE", "STAND BY")
		return
	if n.get("inGame") == true or phase() != "lobby":
		_deny("STILL", "ON THE AIR")
		return
	if ready():
		if isHost():
			_start()
		else:
			m._play("ui_denied", {"vol": 0.3})
		return
	var hero: String = m.selected
	var c := claimant(hero)
	if not c.is_empty():
		_deny("TAKEN BY", str(c.name).to_upper())
		var h = m._heroOnSet()
		if h:
			m._faceExpr(h, "pout", 1.0)
		return
	armLeave = -1.0
	msg.t = 99.0
	want = {"ready": true, "hero": hero, "t": 0.0}
	if held() != hero:
		# swap our hero first; READY goes out once the host's lobby echo shows it ours (_sync), a refusal is net:hero
		if n.has_method("setHero") and n.setHero(hero) == false:
			want.t = 99.0
			_deny("CAN'T TUNE", "IN NOW")
			return
		_sync()
	else:
		_sendReady(true)
	m._css.dymo.go = 0.0
	m._play("ui_tune_in", {"vol": 0.8})
	m._play("onair_clack", {"vol": 0.6})
	var h2 = m._heroOnSet()
	if h2:
		var an = h2.get("animator")
		if an and an.has_method("kick"):
			an.kick(1.2)
		m._faceExpr(h2, "smile", 1.0)

func _sendReady(on: bool) -> void:
	var n = _net()
	if n == null or not n.has_method("setReady"):
		return
	if n.setReady(on) == false and on:
		want.t = 99.0
		_deny("PLEASE", "STAND BY")
		return
	want.ready = on
	want.sent = true

func _unready() -> void:
	want = {"ready": false, "hero": held(), "t": 0.0, "sent": true}
	var n = _net()
	if n != null and n.has_method("setReady"):
		n.setReady(false)

func _deny(w1: String = "", w2: String = "") -> void:
	deny = 0.3
	m._play("ui_denied", {"vol": 0.6})
	if w1 != "" or w2 != "":
		msg = {"w1": w1, "w2": w2, "t": 0.0}

func _start() -> void:
	var n = _net()
	if n == null or not isHost():
		return
	if not allReady():
		_deny("WAITING FOR", "THE CAST")
		return
	var r = n.startGame() if n.has_method("startGame") else false
	if (r is bool and r == false) or (r is int and r != OK):
		_deny("CAN'T START", "YET")
		return
	m._play("ui_menu_clack")
	m._css.dymo.go = 0.0

# Turning the dial (menu.tune): locked while counting down; while ready it un-readies first.
func canTune() -> bool:
	if live or cd >= 0.0:
		return false
	if ready():
		_unready()
	armLeave = -1.0
	msg.t = 99.0
	return true

func key(e: Dictionary) -> bool:
	if live or cd >= 0.0:
		e.stop = e.code == "Escape"
		return true   # the countdown / the dive own the keys
	if e.code != "Escape":
		return false
	e.stop = true
	if ready():
		_unready()
		m._play("ui_menu_clack", {"vol": 0.7})
		return true
	if isHost() and peers().size() > 1 and armLeave < 0.0:
		armLeave = 2.5
		msg.t = 99.0
		m._play("ui_denied", {"vol": 0.5})
		return true
	m._play("ui_menu_clack", {"vol": 0.7})
	m._leaveSession("mp")
	return true

func pad(_btn: String) -> bool:
	return live or cd >= 0.0   # swallowed while counting down; else the dial's own mapping (B = Esc, A / Start = E)

# 'start' landed (menu.mpStart): the dive into the screen, then startNow().
func goLive(heroId) -> bool:
	if live:
		return true
	live = true
	cd = -1.0
	if heroId is String and m._chanIndex(heroId) >= 0 and heroId != m.selected:
		m._tuneTo(m._chanIndex(heroId), true)
	m._camBlend = 1.0
	m._dive()
	return true

# End of the dive (menu._startGame, after hideAll): the session's newGame (seed already set by mp-core).
func startNow(heroId) -> void:
	live = false
	game.newGame(heroId)

func onNet(ev: String, p) -> void:
	var d: Dictionary = p if p is Dictionary else {}
	match ev:
		"net:lobby":
			_sync()
		"net:peer":
			var id := int(d.get("id", 0))
			var nm: String = _names.get(id, "PLAYER %d" % id)
			for q in peers():
				if q.id == id:
					nm = str(q.name)
			if d.get("name") != null:
				nm = str(d.name)
			if d.get("joined") == true:
				toast = {"text": "%s TUNED IN" % nm.to_upper(), "t": 0.0}
				m._play("telly_ploop", {"vol": 0.6})
			else:
				toast = {"text": "%s SIGNED OFF" % nm.to_upper(), "t": 0.0}
				m._play("crt_power_off", {"vol": 0.35})
			armLeave = -1.0
		"net:upnp":
			_upnp(d)
		"net:hero":
			# the host refused our hero (someone was faster): no READY goes out
			if d.get("ok") == false and want.t < 2.0 and want.ready:
				want.t = 99.0
				_deny("TAKEN", "TRY ANOTHER")

# The lobby state changed (net:lobby): the countdown starts / stops, our request is confirmed or refused.
func _sync() -> void:
	var ph := phase()
	if ph == "starting" and cd < 0.0 and not live:
		cd = 0.0
		cdLast = -1
		var n = _net()
		var lb = n.get("lobby") if n != null else null
		var c = _f(lb, "countdown", 3.0)
		cdDur = clampf(float(c) if c != null else 3.0, 1.0, 30.0)
		m._css.selbar.on.set_(0.0)
		armLeave = -1.0
	elif ph == "lobby" and cd >= 0.0 and not live:
		cd = -1.0
		m._css.selbar.on.set_(1.0)
		_deny("START", "CANCELLED")
	var p := _mine()
	if want.t < 2.0 and want.ready and not want.get("sent", false) and held() == want.hero:
		_sendReady(true)   # our new hero landed: now READY
	if want.t < 2.0 and not p.is_empty() and want.get("sent", false) and p.ready == want.ready and (not want.ready or p.hero == want.hero):
		want.t = 99.0   # confirmed

# -------------------------------------------------------------------------------------------- per frame
func update(dt: float) -> void:
	t += dt
	for p in peers():
		_names[p.id] = p.name
	toast.t += dt
	msg.t += dt
	if deny > 0.0:
		deny = maxf(0.0, deny - dt)
	if armLeave > 0.0:
		armLeave -= dt
		if armLeave <= 0.0:
			armLeave = -1.0
	if want.t < 2.0:
		want.t += dt
		if want.t >= 2.0 and want.ready and not (_mine().get("ready", false) == true):
			_deny("NO ANSWER", "TRY AGAIN")   # the host never confirmed
	if cd >= 0.0 and not live:
		cd += dt
		var L := leader()
		if not L.is_empty() and int(L.n) != cdLast and cd > 0.02:
			cdLast = int(L.n)
			m._play("ui_round_dial", {"vol": 0.8})
		m._css.selbar.on.set_(0.0)
	# the Dymo's words (and so its width) follow the lobby state: keep the click regions in step
	m._hits.clear()
	m._selectHits()

# The Dymo under the TV: [w1, key cap, w2] (menu._selbarLayout / _drawSelect).
func dymo() -> Dictionary:
	var pad: bool = m._padMode()
	var kc := "A" if pad else "E"
	if cd >= 0.0 or live or phase() == "starting":
		return {"w1": "STAND BY", "kc": "", "w2": "FOR AIRTIME"}
	if armLeave > 0.0:
		return {"w1": "CLOSE THE STATION?", "kc": "B" if pad else "ESC", "w2": "SURE"}
	if msg.t < 1.6:
		return {"w1": msg.w1, "kc": "", "w2": msg.w2}
	if ready():
		if isHost():
			if allReady():
				return {"w1": "", "kc": kc, "w2": "START THE SHOW"}
			return {"w1": "WAITING FOR", "kc": "", "w2": "THE CAST"}
		return {"w1": "ON AIR", "kc": "", "w2": "STAND BY"}
	var c := claimant(m.selected)
	if not c.is_empty():
		return {"w1": "TAKEN BY", "kc": "", "w2": str(c.name).to_upper()}
	return {"w1": "CHANNEL", "kc": kc, "w2": "TUNE IN"}

# -------------------------------------------------------------------------------------------- paint
func draw(ci: Control) -> void:
	var ps := peers()
	var n = _net()
	var mx := 4
	var mxv = n.get("maxPlayers") if n != null else null
	if mxv != null:
		mx = clampi(int(mxv), 1, 4)
	var a: float = m.easeOut(m.clamp_((t - 0.5) / 0.5, 0.0, 1.0))
	if a <= 0.001:
		return
	var dx: float = (1.0 - m.easeOutBack(m.clamp_((t - 0.5) / 0.5, 0.0, 1.0), 1.3)) * 120.0
	var X := RX + dx
	var lh: float = m._lh(m._fonts.logo, 40)
	var foot := 0.0
	if isHost():
		foot = 150.0
	else:
		foot = 54.0
	var H := 22.0 + lh + 12.0 + mx * (ROW + 8.0) + foot + 24.0
	m._paintBox(ci, "lobbyCard%d" % int(H), X, RY, RW, H, {"r": 30, "bg": {"lin": 180, "stops": [["#F6E7C8", 0.0], ["#EAD3A4", 1.0]]},
		"shadows": [[0, 0, 0, 5, "#5A3A22"], [0, 0, 0, 9, "#E8A92E"], [0, 22, 44, 0, "rgba(0,0,0,.55)"]]}, a)
	# h2 + the blue tag (the .gpanel title, smaller)
	var cy := RY + 22.0 + lh / 2.0
	var title := "Tonight's Cast"
	m._txt(ci, "logo", 40, X + 26.0, cy, title, "#B5472A", 0.0, [[0.0, 3.0, 0.0, "rgba(90,40,20,.25)"]], a)
	var tag := "%d/%d" % [ps.size(), mx]
	var tls := 16.0 * 0.12
	var tw: float = m._tw("sign", 16, tag, tls) + 20.0
	var th: float = m._lh(m._fonts.sign, 16) + 10.0
	var tx: float = X + 26.0 + m._tw("logo", 40, title) + 14.0
	ci.draw_set_transform(Vector2(tx + tw / 2.0, cy), deg_to_rad(-3.0), Vector2.ONE)
	m._paintBox(ci, "ltag%d" % int(tw), -tw / 2.0, -th / 2.0, tw, th, {"r": 8, "bg": "#2F5BD3"}, a)
	m._txt(ci, "sign", 16, -tw / 2.0 + 10.0, 0.0, tag, "#F6E7C8", tls, [], a)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	var y := RY + 22.0 + lh + 12.0
	for i in mx:
		var r := Rect2(X + 18.0, y, RW - 36.0, ROW)
		if i < ps.size():
			_drawPeer(ci, r, ps[i], a)
		else:
			_drawOpen(ci, r, a)
		y += ROW + 8.0
	y += 4.0
	if isHost():
		_drawShare(ci, X, y, a)
	else:
		var hn := "?"
		for p in ps:
			if p.host:
				hn = str(p.name).to_upper()
		var s := "HOSTED BY %s" % hn
		m._txt(ci, "sign", 14, X + 26.0, y + 16.0, s, "#8A6428", 14.0 * 0.12, [], a)
	# toast (joins / leaves) under the card
	if toast.t < 3.0:
		var ta: float = a * m.clamp_(1.0 - (toast.t - 2.4) / 0.6, 0.0, 1.0)
		var s2: String = toast.text
		var w2: float = m._tw("sign", 16, s2, 16.0 * 0.1) + 32.0
		m._paintBox(ci, "ltoast%d" % int(w2), X + RW / 2.0 - w2 / 2.0, RY + H + 18.0, w2, 36.0, {"r": 18, "bg": "rgba(20,12,8,.78)", "shadows": [[0, 0, 0, 2, "#E8A92E"]]}, ta)
		m._txt(ci, "sign", 16, X + RW / 2.0 - w2 / 2.0 + 16.0, RY + H + 36.0, s2, "#FFE9B8", 16.0 * 0.1, [], ta)

func _drawPeer(ci: Control, r: Rect2, p: Dictionary, a: float) -> void:
	var rdy: bool = p.ready or (p.me and ready())
	var hero: String = p.hero
	if p.me:
		m._paintBox(ci, "lrowMe", r.position.x, r.position.y, r.size.x, r.size.y, {"r": 26, "bg": "rgba(232,169,46,.16)", "shadows": [[0, 0, 0, 2, "rgba(232,169,46,.7)"]]}, a)
	else:
		m._paintBox(ci, "lrow", r.position.x, r.position.y, r.size.x, r.size.y, {"r": 26, "bg": "rgba(90,58,34,.09)"}, a)
	var cy := r.get_center().y
	# channel badge (the pause pills' .chn): the claimed hero's channel, '?' while tuning
	var ci2: int = m._chanIndex(hero) if hero != "" else -1
	var chs := str(m.CHANNELS[ci2].ch) if ci2 >= 0 else "?"
	m._paintBox(ci, "lchn%s" % (ci2 >= 0), r.position.x + 10.0, cy - 26.0, 52.0, 52.0, {"r": 26, "bg": "#F4F1E8", "insets": [[0, 0, 0, 5, "#E23B3B" if ci2 >= 0 else "#B8A88A"]],
		"shadows": [[0, 2, 0, 0, "rgba(0,0,0,.3)"]]}, a)
	m._txt(ci, "hud", 28, r.position.x + 36.0 - m._tw("hud", 28, chs) / 2.0, cy, chs, "#2F5BD3" if ci2 >= 0 else "#8A90B0", 0.0, [], a)
	# name + the hero / state line
	var x := r.position.x + 74.0
	var nm := str(p.name).to_upper()
	var maxW := r.size.x - 74.0 - 112.0
	while nm.length() > 3 and m._tw("hud", 26, nm, 26.0 * 0.04) > maxW:
		nm = nm.substr(0, nm.length() - 1)
	m._txt(ci, "hud", 26, x, cy - 11.0, nm, "#3A2414", 26.0 * 0.04, [], a)
	var sub := "TUNING IN…"
	var subCol := "#8A6428"
	if hero != "" and ci2 >= 0:
		sub = _heroName(hero) if rdy else "%s?" % _heroName(hero)
		subCol = "#B5472A" if rdy else "#8A6428"
	var sx := x
	var sls := 12.0 * 0.1
	if p.host:
		sx += _chip(ci, sx, cy + 15.0, "HOST", "#2F5BD3", a) + 6.0
	if p.me:
		sx += _chip(ci, sx, cy + 15.0, "YOU", "#C8962A", a) + 6.0
	m._txt(ci, "sign", 12, sx, cy + 15.0, sub, subCol, sls, [], a)
	# ON AIR lamp (lit = ready) + ping
	var lw := 92.0
	var lx := r.end.x - lw - 12.0
	var ly := cy - 24.0
	if rdy:
		m._paintBox(ci, "lampOn", lx, ly, lw, 30.0, {"r": 8, "bg": {"lin": 180, "stops": [["#FF5A48", 0.0], ["#C8102A", 1.0]]},
			"shadows": [[0, 0, 14, 2, "rgba(255,60,40,.75)"]], "insets": [[0, 2, 0, 0, "rgba(255,220,200,.45)"]]}, a)
		m._txt(ci, "sign", 15, lx + (lw - m._tw("sign", 15, "ON AIR", 1.0)) / 2.0, ly + 15.0, "ON AIR", "#FFF4E8", 1.0, [[0.0, 0.0, 6.0, "rgba(255,230,200,.8)"]], a)
	else:
		m._paintBox(ci, "lampOff", lx, ly, lw, 30.0, {"r": 8, "bg": {"lin": 180, "stops": [["#5A3A2C", 0.0], ["#3E261C", 1.0]]},
			"insets": [[0, 2, 4, 0, "rgba(0,0,0,.45)"]]}, a)
		m._txt(ci, "sign", 15, lx + (lw - m._tw("sign", 15, "ON AIR", 1.0)) / 2.0, ly + 15.0, "ON AIR", "#7A5A48", 1.0, [], a)
	var ping = p.ping
	if p.host and not isHost():
		ping = _mine().get("ping", ping)   # (the host's own ping is 0: on a client its row shows our latency to it)
	var ps := "YOU" if p.me else ("— MS" if ping == null or float(ping) < 0.0 else "%d MS" % int(ping))
	if not p.me:
		var pc := "#3F8A3A" if ping != null and float(ping) >= 0.0 and float(ping) < 80.0 else ("#B07A1A" if ping != null and float(ping) >= 0.0 and float(ping) < 160.0 else "#B5472A")
		m._txt(ci, "tape", 24, lx + lw - m._tw("tape", 24, ps), cy + 18.0, ps, pc, 0.0, [], a)

func _chip(ci: Control, x: float, cy: float, s: String, bg: String, a: float) -> float:
	var w: float = m._tw("sign", 11, s, 1.0) + 12.0
	m._paintBox(ci, "lchip%s%d" % [bg, int(w)], x, cy - 9.0, w, 18.0, {"r": 5, "bg": bg}, a)
	m._txt(ci, "sign", 11, x + 6.0, cy, s, "#F6E7C8", 1.0, [], a)
	return w

func _drawOpen(ci: Control, r: Rect2, a: float) -> void:
	var dash: Texture2D = m._svgTex("lopen%d" % int(r.size.x), func():
		return HudScript.svgTexture(HudScript.svgDoc(0, 0, r.size.x, ROW, '<path d="%s" fill="none" stroke="#B8A88A" stroke-width="2.5" stroke-dasharray="10 8"/>' % HudScript.rrd(1.5, 1.5, r.size.x - 3.0, ROW - 3.0, 26))))
	if dash:
		ci.draw_texture_rect(dash, r, false, Color(1, 1, 1, a))
	var s := "OPEN CHANNEL"
	m._txt(ci, "sign", 14, r.get_center().x - m._tw("sign", 14, s, 14.0 * 0.14) / 2.0, r.get_center().y, s, "#B8A88A", 14.0 * 0.14, [], a)

# Host: the addresses to share. The UPnP external address on a Dymo tape when the router opened the port, the LAN
# address under it; while UPnP works / when it failed, a line says so (forward UDP <port> by hand).
func _drawShare(ci: Control, X: float, y: float, a: float) -> void:
	var cap := "SHARE YOUR ADDRESS"
	m._txt(ci, "sign", 14, X + 26.0, y + 12.0, cap, "#8A6428", 14.0 * 0.12, [], a)
	var port := _port()
	var main := ""
	var line2 := ""
	var line2col := "#5A3A22"
	if upnp.state == "ok" and upnp.ip != "":
		main = "%s:%d" % [upnp.ip, upnp.port if upnp.port > 0 else port]
		line2 = "LAN %s:%d" % [lanIp, port] if lanIp != "" else ""
	else:
		main = "%s:%d" % [lanIp if lanIp != "" else "127.0.0.1", port]
		if upnp.state == "pending":
			line2 = "UPNP · OPENING THE PORT" + ".".repeat(1 + int(t * 2.0) % 3)
		elif upnp.state == "off":
			line2 = "LAN ONLY · FORWARD UDP %d FOR ONLINE PLAY" % port
		else:
			line2 = "UPNP FAILED · FORWARD UDP %d FOR ONLINE PLAY" % port
			line2col = "#B5472A"
	# the Dymo tape (the dial's TUNE IN label maker)
	var dw: float = m._tw("hud", 28, main, 28.0 * 0.06) + 44.0
	dw = minf(dw, RW - 40.0)
	var tex: Texture2D = m._svgTex("ldymo%d" % int(dw), func(): return HudScript.svgTexture(m._dymoSvg(dw, 52.0)))
	var cx := X + 22.0 + dw / 2.0
	var cy := y + 56.0
	ci.draw_set_transform(Vector2(cx, cy), deg_to_rad(-1.5), Vector2.ONE)
	if tex:
		ci.draw_texture_rect(tex, Rect2(-dw / 2.0 - 14, -26 - 10, dw + 28, 52 + 30), false, Color(1, 1, 1, a))
	var emb := [[0.0, -1.0, 0.0, "rgba(0,0,0,.9)"], [0.0, 1.0, 0.0, "rgba(255,255,255,.35)"], [0.0, 2.0, 3.0, "rgba(0,0,0,.5)"]]
	m._txt(ci, "hud", 28, -dw / 2.0 + 22.0, 0.0, main, "#F2F0EA", 28.0 * 0.06, emb, a)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	if line2 != "":
		var fk := "tape" if line2.begins_with("LAN") else "sign"
		var sz := 26.0 if fk == "tape" else 12.0
		m._txt(ci, fk, sz, X + 26.0, y + 104.0, line2, line2col, 0.0 if fk == "tape" else 12.0 * 0.08, [], a)

func _heroName(id: String) -> String:
	var H = m._heroesLib()
	if H:
		for h in H.HEROES:
			if h.id == id:
				return str(h.name).to_upper()
	return id.to_upper()
