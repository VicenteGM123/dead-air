# DEAD AIR — the living room's front menus (MP_SPEC §0, §3.5; added for online co-op). A helper of menu.gd (game.menu):
# it owns no Nodes; menu.gd routes its mode 'main' here (keys, pad, update) and paints it on the panel pn.front.
#   MAIN (title -> any key): the camera glides to the 'main' pose (Telly's console TV on the left, still showing the
#     DEAD AIR logo) and five walnut channel pills (the pause card's pills) slide in on the right under "What's on
#     tonight?": 2 SINGLE PLAYER, 3 MULTIPLAYER, 4 OPTIONS, 5 CONTROLS, 7 QUIT. Moving the highlight turns the TV's VHF
#     dial to that channel (a soft clack, the green OSD number on the picture). SINGLE PLAYER -> menu.showSelect() (the
#     dial, exactly as before); OPTIONS / CONTROLS -> the pause menu's own cards (menu._pause.sub: same rows, same
#     persistence; the camera eases a little left to make room); QUIT asks once ("QUIT? SURE"), then the set powers off
#     (crt_power_off, CRT collapse) and the app quits. Esc / B -> the title.
#   MULTIPLAYER (TV GUIDE cards: the Options card's .gpanel): HOST GAME / JOIN GAME / CONNECTION (desktop only: ONLINE ·
#     CODE = WebRTC with a room code, or DIRECT IP · LAN = ENet; persisted as deadair.mpmode; the browser build is
#     always ONLINE · CODE) / NAME (a Dymo tape; default = the OS user name, persisted as deadair.mpname) / BACK.
#     ONLINE · CODE: HOST -> net.host({name, transport: 'rtc'}) -> menu.showLobby() (the lobby shows the room code to
#     share); JOIN -> ENTER CODE (a phosphor readout + a letter keypad of the code alphabet, Ctrl+V pastes) -> net.join(
#     code, 0, {transport: 'rtc'}); the MULTIPLAYER card shows TUNING IN TO ROOM ... then the lobby or a red line (no such
#     room / signal server unreachable / connection failed / version...).
#     DIRECT IP · LAN: HOST -> net.host({name}) -> menu.showLobby(). JOIN -> the LAN
#     listings (net.discover(true); net.lan rows: host name, players n/max, FULL / OLD VERSION / ON AIR tags) + ENTER
#     ADDRESS (IP or IP:port; persisted as deadair.mpaddr) + BACK. Tuning in: net.join(ip, port, {name}); the TV goes to
#     snow and the card shows TUNING IN…; 'net:status' events: connected -> the lobby, rejected (version / full /
#     started) / failed / timeout -> a red line on the card (a 15 s local timeout backs mp-core's own).
#   The address and name cards take the keyboard (type, Backspace, Enter = OK, Esc = back) and draw an on-screen
#   keypad for the pad and the mouse: Touch-Tone digits . : DEL TUNE IN, or a letter board A-Z 0-9 . - _ ' SPACE DEL OK.
#   Pad: D-pad / stick move, A press, B back, X delete, Y space, Start OK (menu.padButton -> pad()).
# API (menu.gd): enter(screen, fromMode), key(e) (e = menu._onKey's dict + 'char'), pad(btn) -> bool, update(dt),
#   draw(ci), backFromCard() (menu._pauseSub('main') while in mode 'main'), onNet(event, payload), leaveScreen().
extends RefCounted

const HudScript = preload("res://scripts/ui/hud.gd")

const PX := 1160.0                 # main pills: resting left edge (stage px), width / height / pitch as the pause card
const PW := 640.0
const PH := 104.0
const PSTEP := 126.0
const PY := 250.0
const CX0 := 1034.0                # .gpanel content box (left 1000 + padding 34, width 752)
const CW := 752.0
const ROW_H := 62.0
const NAME_MAX := 14
const ADDR_MAX := 21
const NAME_KEY := "deadair.mpname"
const ADDR_KEY := "deadair.mpaddr"
const MODE_KEY := "deadair.mpmode"
const CONNECT_TIMEOUT := 15.0
const CONNECT_TIMEOUT_RTC := 45.0      # room lookup + WebRTC setup (net_rtc reports its own failures well before)
const RtcScript = preload("res://scripts/net/net_rtc.gd")
const KP_CODE := [
	[["A"], ["B"], ["C"], ["D"], ["E"], ["F"], ["G"], ["H"]],
	[["J"], ["K"], ["M"], ["N"], ["P"], ["Q"], ["R"], ["S"]],
	[["T"], ["U"], ["V"], ["W"], ["X"], ["Y"], ["Z"], ["2"]],
	[["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"], ["DEL", "del"]],
	[["TUNE IN", "ok", 8]],
]
const KP_ADDR := [
	[["1"], ["2"], ["3"], ["DEL", "del"]],
	[["4"], ["5"], ["6"], [":"]],
	[["7"], ["8"], ["9"], ["."]],
	[["0", "", 2], ["TUNE IN", "ok", 2]],
]
const KP_NAME := [
	[["A"], ["B"], ["C"], ["D"], ["E"], ["F"], ["G"], ["H"], ["I"], ["J"]],
	[["K"], ["L"], ["M"], ["N"], ["O"], ["P"], ["Q"], ["R"], ["S"], ["T"]],
	[["U"], ["V"], ["W"], ["X"], ["Y"], ["Z"], ["."], ["-"], ["_"], ["'"]],
	[["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"], ["0"]],
	[["SPACE", "space", 4], ["DEL", "del", 3], ["OK", "ok", 3]],
]
const REJECT := {"version": "WRONG VERSION · UPDATE THE GAME", "full": "LOBBY FULL · 4 VIEWERS MAX", "started": "SHOW ALREADY ON AIR",
	"kicked": "THE HOST TOOK YOU OFF THE AIR", "timeout": "NO SIGNAL · TIMED OUT", "connect": "NO SIGNAL · COULDN'T CONNECT",
	"failed": "NO SIGNAL · COULDN'T CONNECT", "lost": "THE SIGNAL DROPPED", "disconnected": "THE SIGNAL DROPPED",
	"notfound": "NO SUCH ROOM · CHECK THE CODE", "signal": "CAN'T REACH THE SIGNAL SERVER · CHECK YOUR INTERNET",
	"ice": "COULDN'T LINK UP · A FIREWALL OR STRICT NAT?", "nortc": "ONLINE PLAY ISN'T AVAILABLE IN THIS BUILD"}

var m                              # menu.gd
var game
var screen := "main"               # main | options | controls | mp | join | addr | name | code
var sel := 0                       # main pill
var rsel := {"mp": 0, "join": 0}   # card rows
var quitArm := -1.0
var off := -1.0                    # power-off timer (QUIT)
var inT := 99.0                    # since the pills (re)entered: slide-in
var tvT := 99.0                    # TV picture: snow burst after a channel change (coming back from the dial)
var osd := {"ch": "", "t": 99.0}
var entry := {"kind": "", "text": "", "orig": "", "err": 0.0}
var kp := {"r": 0, "i": 0, "press": -1, "pt": 0.0}
var conn := {"state": "", "text": "", "t": 0.0, "err": ""}
var status := {"text": "", "err": false, "t": 0.0}   # mp card line (host failure, net missing)
var name := ""
var addr := ""
var netMode := "code"              # 'code' (WebRTC room codes) | 'ip' (ENet: direct IP / LAN; desktop only)
var _lanSeen := 0
const WEB_NOTE := "DESKTOP ONLY"
var WEB: bool = OS.has_feature("web")   # browser build: online play with room codes only (no ENet/UDP in browsers)

func _init(menu) -> void:
	m = menu
	game = menu.game
	var saved = m.storeGet(NAME_KEY)
	name = _clean(str(saved), NAME_MAX) if saved != null else ""
	if name == "":
		name = defaultName()
	var a = m.storeGet(ADDR_KEY)
	addr = _cleanAddr(str(a)) if a != null else ""
	var md = m.storeGet(MODE_KEY)
	netMode = "ip" if (md != null and str(md) == "ip" and not WEB) else "code"

static func defaultName() -> String:
	var s := OS.get_environment("USERNAME")
	if s == "":
		s = OS.get_environment("USER")
	s = _clean(s.to_upper(), NAME_MAX)
	return s if s != "" else "VIEWER"

static func _clean(s: String, mx: int) -> String:
	var out := ""
	for ch in s.to_upper():
		if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in [" ", ".", "-", "_", "'"]:
			out += ch
	return out.strip_edges().substr(0, mx)

static func _cleanAddr(s: String) -> String:
	var out := ""
	for ch in s.strip_edges():
		if (ch >= "0" and ch <= "9") or (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch in [".", ":", "-"]:
			out += ch
	return out.substr(0, ADDR_MAX)

func _net():
	return game.get("net")

# -------------------------------------------------------------------------------------------- screens
# Called by menu.showMain() after hideAll() (mode = 'main', pn.front visible). fromMode: the mode before.
func enter(scr: String, fromMode) -> void:
	quitArm = -1.0
	off = -1.0
	conn.state = ""
	if fromMode == "title" or fromMode == "select" or fromMode == "tunein" or fromMode == null:
		inT = 0.0
	if fromMode == "select" or fromMode == "tunein":
		tvT = 0.0          # the picture comes back from the hero's channel: snow burst, then the logo
	var items := mainItems()
	sel = clampi(sel, 0, items.size() - 1)
	_dial(items[sel].ch, false)
	_go(scr, true)

func mainItems() -> Array:
	var items := [
		{"ch": "2", "label": "SINGLE PLAYER", "act": func(): _single()},
		{"ch": "3", "label": "MULTIPLAYER", "act": func(): _go("mp")},
		{"ch": "4", "label": "OPTIONS", "act": func(): _go("options")},
		{"ch": "5", "label": "CONTROLS", "act": func(): _go("controls")},
		{"ch": "7", "label": "QUIT", "act": func(): _quit()},
	]
	if WEB:
		items.pop_back()   # a browser tab can't be quit (it would only stop the engine on a black canvas)
	return items

# Switches the front screen (sounds + camera + hit regions). silent: no clack (entering the menu).
func _go(scr: String, silent: bool = false) -> void:
	var was := screen
	if was == "join" and scr != "join" and scr != "addr":
		_discover(false)
	screen = scr
	if not silent:
		m._play("ui_menu_clack", {"vol": 0.7})
	var pose := "main" if scr == "main" else "card"
	if m._camTo != pose:
		m._camGo(pose, 0.7)
	if scr == "options" or scr == "controls":
		m._pause.sub = scr
		m._pause.osel = 0
		m._renderPause()         # the card's own hit regions (rows, segments, sliders, back)
		return
	if scr == "join":
		_lanSeen = 0
		_discover(true)
		var rows := _rows()
		rsel.join = clampi(rsel.join, 0, rows.size() - 1)
		rsel.join = _skip(rows, rsel.join, 1)
	if scr == "addr" or scr == "name" or scr == "code":
		kp.r = 0
		kp.i = 0
		kp.press = -1
	if scr == "main":
		quitArm = -1.0
	_hitsFor()

# menu._pauseSub('main') from an Options / Controls card while the main menu shows.
func backFromCard() -> void:
	_go("main")

func leaveScreen() -> void:
	if screen == "join" or screen == "addr":
		_discover(false)

func _codeMode() -> bool:
	return WEB or netMode == "code"

func _toggleMode() -> void:
	if WEB:
		return
	netMode = "ip" if netMode == "code" else "code"
	m.storeSet(MODE_KEY, netMode)
	m._play("ui_menu_clack", {"vol": 0.6})
	conn.state = ""
	_hitsFor()

func _joinPressed() -> void:
	if _codeMode():
		if not _rtcOk():
			return
		_edit("code")
	else:
		_go("join")

# WebRTC present (browser: always; desktop: the webrtc-native extension). Else a red line on the card.
func _rtcOk() -> bool:
	var n = _net()
	if n != null and n.has_method("rtcAvailable") and n.rtcAvailable():
		return true
	_status(REJECT.nortc + (" · USE DIRECT IP" if not WEB else ""), true)
	return false

func _rowIndex(id: String) -> int:
	var rows := _rows()
	for i in rows.size():
		if rows[i].id == id:
			return i
	return 0

func _single() -> void:
	m._play("ui_menu_clack")
	m.showSelect()

func _quit() -> void:
	if quitArm < 0.0:
		quitArm = 2.5
		m._play("ui_denied", {"vol": 0.5})
		_hitsFor()
		return
	# power the set off: the CRT collapses to a dot, then the app quits
	quitArm = -1.0
	off = 0.0
	m._hits.clear()
	m._play("crt_power_off")

func _discover(on: bool) -> void:
	var n = _net()
	if n != null and n.has_method("discover"):
		n.discover(on)

# -------------------------------------------------------------------------------------------- rows (mp / join)
func _rows() -> Array:
	if screen == "mp":
		var cm := _codeMode()
		var out: Array = [
			{"id": "host", "label": "HOST GAME", "hint": "GET A ROOM CODE" if cm else "OPEN YOUR STATION", "act": func(): _host()},
			{"id": "join", "label": "JOIN GAME", "hint": "ENTER A ROOM CODE" if cm else "TUNE IN TO A FRIEND", "act": func(): _joinPressed()},
		]
		if not WEB:
			out.append({"id": "mode", "label": "CONNECTION", "value": "ONLINE · CODE" if cm else "DIRECT IP · LAN", "act": func(): _toggleMode()})
		out.append({"id": "name", "label": "NAME", "value": name, "act": func(): _edit("name")})
		out.append({"id": "back", "label": "◀ BACK", "type": "back", "act": func(): _go("main")})
		return out
	if screen == "join":
		var out: Array = []
		var n = _net()
		var lan = n.get("lan") if n != null else null
		if lan is Array:
			var seen := {}
			for g in lan:
				if not (g is Dictionary):
					continue
				var gg: Dictionary = g
				# one host heard on two interfaces (or loopback + LAN) shows once
				var dk := "%s|%s|%s|%s" % [gg.get("name", ""), gg.get("port", ""), gg.get("version", ""), gg.get("players", "")]
				if seen.has(dk):
					continue
				seen[dk] = true
				var mx := int(gg.get("max", 4))
				var pl := int(gg.get("players", 0))
				var tag := ""
				var ok := true
				var ver = gg.get("version")
				var myv = n.get("version") if n != null else null
				if ver != null and myv != null and str(ver) != str(myv):
					tag = "OLD VERSION"
					ok = false
				elif gg.get("phase") != null and gg.get("phase") != "lobby":
					tag = "ON AIR"
					ok = false
				elif pl >= mx:
					tag = "FULL"
					ok = false
				out.append({"id": "lan:%s:%s" % [gg.get("ip", "?"), gg.get("port", "")], "type": "lan", "label": _clean(str(gg.get("name", "?")), NAME_MAX + 6),
					"ip": str(gg.get("ip", "")), "port": int(gg.get("port", _port())), "players": "%d/%d" % [pl, mx], "tag": tag, "ok": ok,
					"act": func(): _joinLan(gg)})
				if out.size() >= 5:
					break
		if out.is_empty():
			out.append({"id": "scan", "type": "info", "label": "SCANNING THE DIAL"})
		out.append({"id": "addr", "label": "ENTER ADDRESS", "hint": addr if addr != "" else "IP OR IP:PORT", "act": func(): _edit("addr")})
		out.append({"id": "back", "label": "◀ BACK", "type": "back", "act": func(): _go("mp")})
		return out
	return []

# Next selectable row from i in direction d (info rows are skipped).
func _skip(rows: Array, i: int, d: int) -> int:
	var n := rows.size()
	for k in n:
		var j := (i + d * k + n * 4) % n
		if rows[j].get("type") != "info":
			return j
	return 0

func _top() -> float:
	return 110.0 + 24.0 + m._lh(m._fonts.logo, 52) + 14.0

func _rowsLayout(rows: Array) -> Dictionary:
	var y := _top()
	var rects: Array = []
	for r in rows:
		if r.get("type") == "back":
			y += 10.0
		rects.append(Rect2(CX0, y, CW, ROW_H))
		y += ROW_H + 6.0
	return {"rects": rects, "bottom": y}

func _port() -> int:
	var n = _net()
	var p = n.get("port") if n != null else null
	return int(p) if p != null else 31313

# -------------------------------------------------------------------------------------------- hits (mouse)
func _hitsFor() -> void:
	m._hits.clear()
	if off >= 0.0:
		return
	if screen == "main":
		var items := mainItems()
		for i in items.size():
			var ii := i
			m._hits.append({"id": "mitem%d" % i, "rect": Rect2(PX + (26.0 if i == sel else 0.0), PY + i * PSTEP, PW, PH),
				"enter": func(): if ii != sel and off < 0.0:
					_select(ii),
				"click": func():
					if off >= 0.0:
						return
					_select(ii)
					mainItems()[ii].act.call()})
		return
	if screen == "mp" or screen == "join":
		var rows := _rows()
		var L := _rowsLayout(rows)
		for i in rows.size():
			if rows[i].get("type") == "info":
				continue
			var ii := i
			var k: String = screen
			m._hits.append({"id": "row%d" % i, "rect": L.rects[i],
				"enter": func(): if rsel[k] != ii:
					rsel[k] = ii
					m._tick(),
				"click": func():
					rsel[k] = ii
					_activateRow()})
		return
	if screen == "addr" or screen == "name" or screen == "code":
		var K := _kpLayout()
		for i in K.keys.size():
			var ii: int = i
			m._hits.append({"id": "key%d" % i, "rect": K.keys[i].rect,
				"enter": func(): if kp.i != ii:
					kp.i = ii
					kp.r = K.keys[ii].row,
				"click": func():
					kp.i = ii
					kp.r = K.keys[ii].row
					_pressKey(ii)})
		m._hits.append({"id": "kback", "rect": K.back, "click": func(): _entryBack()})

func _select(i: int) -> void:
	var items := mainItems()
	if i == sel:
		return
	sel = i
	if quitArm > 0.0 and items[i].label != "QUIT":
		quitArm = -1.0
	_dial(items[i].ch, true)
	_hitsFor()

# Turns Telly's VHF dial to a channel detent (the OSD number flashes on the picture).
func _dial(ch: String, sound: bool) -> void:
	var R = m._room
	if R == null:
		return
	var det = R.parts.get("dialDetents", {})
	if det is Dictionary:
		var v = det.get(ch, det.get(int(ch) if ch.is_valid_int() else ch))
		if v != null:
			R.dialTarget = float(v)
	osd.ch = ch
	osd.t = 0.0 if sound else 99.0
	if sound:
		m._play("ui_menu_clack", {"vol": 0.55, "rate": 0.95 + randf() * 0.1})

# -------------------------------------------------------------------------------------------- input
func key(e: Dictionary) -> void:
	if off >= 0.0:
		return
	var c: String = e.code
	var up := c == "KeyW" or c == "ArrowUp"
	var down := c == "KeyS" or c == "ArrowDown"
	var left := c == "KeyA" or c == "ArrowLeft"
	var right := c == "KeyD" or c == "ArrowRight"
	var ok := c == "Enter" or c == "KeyE" or c == "Space" or c == "NumpadEnter"
	if screen == "options" or screen == "controls":
		m._pauseKey(e)          # rows, sliders, segments; Esc / ◀ BACK -> menu._pauseSub('main') -> backFromCard()
		return
	if screen == "addr" or screen == "name" or screen == "code":
		_entryKey(e)
		return
	if c == "Escape":
		e.stop = true
		_back()
		return
	if screen == "main":
		var n := mainItems().size()
		if up or down:
			_select((sel + (-1 if up else 1) + n) % n)
		elif ok:
			mainItems()[sel].act.call()
		return
	# mp / join cards
	var rows := _rows()
	var k: String = screen
	if up or down:
		rsel[k] = _skip(rows, (rsel[k] + (-1 if up else 1) + rows.size()) % rows.size(), -1 if up else 1)
		m._tick()
	elif ok:
		_activateRow()
	elif (left or right) and conn.state != "connecting" and rows[clampi(rsel[k], 0, rows.size() - 1)].get("id") == "name":
		_edit("name")
	elif (left or right) and conn.state != "connecting" and rows[clampi(rsel[k], 0, rows.size() - 1)].get("id") == "mode":
		_toggleMode()

func _back() -> void:
	if screen == "main":
		m._play("ui_menu_clack", {"vol": 0.7})
		m.showTitle()
	elif screen == "mp":
		if conn.state == "connecting":
			_cancelConnect()
		else:
			_go("main")
	elif screen == "join":
		if conn.state == "connecting":
			_cancelConnect()
		else:
			_go("mp")

func _activateRow() -> void:
	var rows := _rows()
	var k: String = screen
	var i: int = clampi(rsel[k], 0, rows.size() - 1)
	var r: Dictionary = rows[i]
	if r.get("type") == "info":
		return
	if conn.state == "connecting" and r.id != "back":
		m._play("ui_denied", {"vol": 0.5})
		return
	if r.get("ok") == false:
		m._play("ui_denied", {"vol": 0.6})
		conn.err = "%s · %s" % [r.label, r.tag]
		conn.state = "error"
		conn.t = 0.0
		return
	(r.act as Callable).call()

# Xbox pad (menu.padButton while mode == 'main'). Returns true when used.
func pad(btn: String) -> bool:
	if off >= 0.0:
		return true
	var code = {"a": "Enter", "b": "Escape", "up": "ArrowUp", "down": "ArrowDown", "left": "ArrowLeft", "right": "ArrowRight", "start": "Enter"}.get(btn)
	if screen == "addr" or screen == "name" or screen == "code":
		if btn == "a":
			_pressKey(kp.i)
		elif btn == "x":
			_entryEdit("del")
		elif btn == "y" and screen == "name":
			_entryEdit("space")
		elif btn == "start":
			_entryOk()
		elif btn == "b":
			_entryBack()
		elif code:
			_kpMove(code)
		return true
	if code:
		m._onKey({"code": code, "repeat": false, "shiftKey": false, "stop": false, "char": ""})
	return true

# ---- address / name entry
func _edit(kind: String) -> void:
	entry.kind = kind
	entry.text = name if kind == "name" else ("" if kind == "code" else addr)
	entry.orig = entry.text
	entry.err = 0.0
	_go(kind)

func _entryKey(e: Dictionary) -> void:
	var c: String = e.code
	if c == "Escape":
		e.stop = true
		_entryBack()
		return
	if c == "Enter" or c == "NumpadEnter":
		_entryOk()
		return
	if c == "Backspace" or c == "Delete":
		_entryEdit("del")
		return
	if c.begins_with("Arrow"):
		_kpMove(c)
		return
	var ch: String = e.get("char", "")
	if c == "KeyV" and e.get("ctrlKey", false):
		_paste()
		return
	if ch == "" and c == "Space":
		ch = " "
	if ch != "":
		_entryEdit("chr", ch)

# Ctrl+V: the clipboard's text into the field (a room code keeps only its alphabet: "wztv-4k2p" -> WZTV4K2P).
func _paste() -> void:
	var t := DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) else ""
	var add := ""
	if entry.kind == "code":
		add = RtcScript.normalizeCode(t)
	elif entry.kind == "name":
		add = _clean(t, NAME_MAX)
	else:
		add = _cleanAddr(t)
	if add == "":
		m._play("ui_denied", {"vol": 0.35})
		return
	var mx := NAME_MAX if entry.kind == "name" else (RtcScript.CODE_LEN if entry.kind == "code" else ADDR_MAX)
	entry.text = (str(entry.text) + add).substr(0, mx) if entry.kind != "code" else add
	m._play("ui_prompt", {"vol": 0.5})

func _entryEdit(act: String, ch: String = "") -> void:
	var name_: bool = entry.kind == "name"
	var code_: bool = entry.kind == "code"
	var t: String = entry.text
	var mx := NAME_MAX if name_ else (RtcScript.CODE_LEN if code_ else ADDR_MAX)
	if act == "del":
		if t.length() > 0:
			entry.text = t.substr(0, t.length() - 1)
			m._play("ui_prompt", {"vol": 0.45, "rate": 0.85})
		return
	if act == "space":
		ch = " "
	var c2 := _clean(ch, 1) if name_ else (RtcScript.normalizeCode(ch) if code_ else _cleanAddr(ch))
	if ch == " " and name_ and t.length() > 0 and not t.ends_with(" "):
		c2 = " "
	if c2 == "" or t.length() >= mx:
		m._play("ui_denied", {"vol": 0.35})
		return
	entry.text = t + c2
	m._play("ui_prompt", {"vol": 0.5, "rate": 0.95 + randf() * 0.1})

func _entryOk() -> void:
	if entry.kind == "name":
		var nm := _clean(entry.text, NAME_MAX)
		if nm == "":
			_entryErr()
			return
		name = nm
		m.storeSet(NAME_KEY, name)
		_go("mp")
		rsel.mp = _rowIndex("name")
		_hitsFor()
		return
	if entry.kind == "code":
		var cd := RtcScript.normalizeCode(entry.text)
		if cd.length() != RtcScript.CODE_LEN:
			_entryErr()
			return
		_go("mp", true)
		rsel.mp = _rowIndex("join")
		m._play("ui_tune_in", {"vol": 0.6})
		_connectCode(cd)
		return
	var pa := _parseAddr(entry.text)
	if pa.is_empty():
		_entryErr()
		return
	addr = _cleanAddr(entry.text)
	m.storeSet(ADDR_KEY, addr)
	_go("join", true)
	m._play("ui_tune_in", {"vol": 0.6})
	_connect(pa.host, pa.port)

func _entryErr() -> void:
	entry.err = 0.6
	m._play("ui_denied", {"vol": 0.6})

func _entryBack() -> void:
	_go("join" if entry.kind == "addr" else "mp")
	if entry.kind != "addr":
		rsel.mp = _rowIndex(entry.kind if entry.kind == "name" else "join")
		_hitsFor()

# "host", "host:port" (IPv4 or a host name). {} when invalid.
func _parseAddr(s: String) -> Dictionary:
	s = s.strip_edges()
	if s == "":
		return {}
	var host := s
	var port := _port()
	var i := s.rfind(":")
	if i >= 0:
		host = s.substr(0, i)
		var ps := s.substr(i + 1)
		if not ps.is_valid_int() or int(ps) < 1 or int(ps) > 65535:
			return {}
		port = int(ps)
	if host == "" or host.contains(":"):
		return {}
	var digits := true
	for ch in host:
		if not ((ch >= "0" and ch <= "9") or ch == "."):
			digits = false
	if digits:
		var parts := host.split(".")
		if parts.size() != 4:
			return {}
		for p in parts:
			if not p.is_valid_int() or int(p) > 255 or p.length() > 3:
				return {}
	return {"host": host, "port": port}

# ---- keypad
func _kpRows() -> Array:
	return KP_NAME if screen == "name" else (KP_CODE if screen == "code" else KP_ADDR)

# Key rects (stage px): the address pad is a centred 4-column Touch-Tone block, the name board spans the card.
func _kpLayout() -> Dictionary:
	var rows := _kpRows()
	var cols := 10 if screen == "name" else (8 if screen == "code" else 4)
	var kw := 68.0 if screen == "name" else (84.0 if screen == "code" else 120.0)
	var kh := 54.0 if screen == "name" or screen == "code" else 60.0
	var gap := 8.0 if screen == "name" or screen == "code" else 14.0
	var totalW := cols * kw + (cols - 1) * gap
	var x0 := CX0 + (CW - totalW) / 2.0
	var y := _top() + 78.0 + 40.0
	var keys: Array = []
	for r in rows.size():
		var c := 0
		for k in rows[r]:
			var span: int = k[2] if k.size() > 2 else 1
			var w := span * kw + (span - 1) * gap
			keys.append({"rect": Rect2(x0 + c * (kw + gap), y, w, kh), "label": k[0], "act": (k[1] if k.size() > 1 and k[1] != "" else "chr"),
				"ch": k[0], "row": r, "c0": c, "span": span})
			c += span
		y += kh + gap
	y += 10.0
	var back := Rect2(CX0, y, CW, 50.0)
	return {"keys": keys, "back": back, "bottom": back.end.y + 52.0, "field": Rect2(CX0, _top(), CW, 78.0)}

func _kpMove(code: String) -> void:
	var K := _kpLayout()
	var keys: Array = K.keys
	if keys.is_empty():
		return
	var cur: Dictionary = keys[clampi(kp.i, 0, keys.size() - 1)]
	var nrows := _kpRows().size()
	if code == "ArrowLeft" or code == "ArrowRight":
		var d := -1 if code == "ArrowLeft" else 1
		var rowKeys: Array = []
		for i in keys.size():
			if keys[i].row == cur.row:
				rowKeys.append(i)
		var at := rowKeys.find(kp.i)
		kp.i = rowKeys[(at + d + rowKeys.size()) % rowKeys.size()]
	elif code == "ArrowUp" or code == "ArrowDown":
		var d2 := -1 if code == "ArrowUp" else 1
		var r: int = (int(cur.row) + d2 + nrows) % nrows
		var cx: float = cur.rect.get_center().x
		var best := -1
		var bd := INF
		for i in keys.size():
			if keys[i].row != r:
				continue
			var dd: float = absf(keys[i].rect.get_center().x - cx)
			if dd < bd:
				bd = dd
				best = i
		if best >= 0:
			kp.i = best
	else:
		return
	kp.r = keys[kp.i].row
	m._tick()

func _pressKey(i: int) -> void:
	var K := _kpLayout()
	if i < 0 or i >= K.keys.size():
		return
	var k: Dictionary = K.keys[i]
	kp.press = i
	kp.pt = 0.12
	match k.act:
		"del":
			_entryEdit("del")
		"space":
			_entryEdit("space")
		"ok":
			_entryOk()
		_:
			_entryEdit("chr", k.ch)

# -------------------------------------------------------------------------------------------- multiplayer
func _host() -> void:
	var n = _net()
	if n == null or not n.has_method("host"):
		_status("MULTIPLAYER ISN'T AVAILABLE IN THIS BUILD", true)
		return
	if _codeMode():
		if not _rtcOk():
			return
		var rr = n.host({"name": name, "hero": m.selected, "transport": "rtc"})
		if (rr is bool and rr == false) or (rr is int and rr != OK):
			_status(REJECT.nortc, true)
			return
		m._play("ui_tune_in", {"vol": 0.7})
		m.showLobby()
		return
	var r = n.host({"name": name, "hero": m.selected})
	if (r is bool and r == false) or (r is int and r != OK):
		_status("COULDN'T OPEN THE STATION · PORT %d BUSY?" % _port(), true)
		return
	m._play("ui_tune_in", {"vol": 0.7})
	m.showLobby()

func _joinLan(g: Dictionary) -> void:
	m._play("ui_tune_in", {"vol": 0.6})
	_connect(str(g.get("ip", "")), int(g.get("port", _port())))

func _connect(host: String, port: int) -> void:
	var n = _net()
	if n == null or not n.has_method("join"):
		conn = {"state": "error", "text": "", "t": 0.0, "err": "MULTIPLAYER ISN'T AVAILABLE IN THIS BUILD"}
		return
	conn = {"state": "connecting", "text": "%s:%d" % [host, port], "t": 0.0, "err": ""}
	tvT = 99.0
	var r = n.join(host, port, {"name": name, "hero": m.selected})
	if ((r is bool and r == false) or (r is int and r != OK)) and conn.state == "connecting":
		_fail("connect")   # (a synchronous net:status 'failed' may already have reported it)

# ONLINE · CODE: find the room, link up (WebRTC), then the same handshake; the MULTIPLAYER card shows the progress.
func _connectCode(cd: String) -> void:
	var n = _net()
	if n == null or not n.has_method("join"):
		conn = {"state": "error", "text": "", "t": 0.0, "err": "MULTIPLAYER ISN'T AVAILABLE IN THIS BUILD", "rtc": true}
		return
	conn = {"state": "connecting", "text": "ROOM " + RtcScript.formatCode(cd), "t": 0.0, "err": "", "rtc": true}
	tvT = 99.0
	_hitsFor()
	var r = n.join(cd, 0, {"name": name, "hero": m.selected, "transport": "rtc"})
	if ((r is bool and r == false) or (r is int and r != OK)) and conn.state == "connecting":
		_fail("nortc" if not _rtcOkSilent() else "signal")

func _rtcOkSilent() -> bool:
	var n = _net()
	return n != null and n.has_method("rtcAvailable") and n.rtcAvailable()

func _cancelConnect() -> void:
	var n = _net()
	conn.state = ""
	if n != null and n.has_method("leave"):
		n.leave()
	m._play("ui_menu_clack", {"vol": 0.7})
	tvT = 0.0

func _fail(reason: String) -> void:
	var n = _net()
	var was: String = conn.state
	conn.state = "error"
	if was == "connecting" and n != null and n.get("active") == true and n.has_method("leave"):
		n.leave()
	conn.err = REJECT.get(reason, "NO SIGNAL · %s" % reason.to_upper())
	conn.t = 0.0
	tvT = 0.0
	m._play("ui_denied", {"vol": 0.7})

func _status(t: String, err: bool) -> void:
	status = {"text": t, "err": err, "t": 0.0}
	if err:
		m._play("ui_denied", {"vol": 0.6})

# game.events net:* while mode == 'main' (menu.gd forwards them).
func onNet(ev: String, p) -> void:
	var d: Dictionary = p if p is Dictionary else {}
	if ev == "net:lan":
		if screen == "join":
			var rows := _rows()
			var lanN := 0
			for r in rows:
				if r.get("type") == "lan":
					lanN += 1
			if _lanSeen == 0 and lanN > 0 and rows[clampi(rsel.join, 0, rows.size() - 1)].id == "addr" and conn.state != "connecting":
				rsel.join = 0   # the first station heard: highlight it (the viewer had not moved yet)
			_lanSeen = lanN
			rsel.join = _skip(rows, clampi(rsel.join, 0, rows.size() - 1), 1)
			_hitsFor()
		return
	if ev != "net:status" or conn.state != "connecting":
		return
	var st := str(d.get("status", ""))
	var why := str(d.get("reason", ""))
	if st == "connected":
		conn.state = ""
		m.showLobby()
	elif st == "rejected":
		_fail(why if why != "" else "failed")
	elif st in ["failed", "lost"]:
		_fail(why if REJECT.has(why) else st)

# -------------------------------------------------------------------------------------------- per frame
func update(dt: float) -> void:
	inT += dt
	tvT += dt
	osd.t += dt
	status.t += dt
	if quitArm > 0.0:
		quitArm -= dt
		if quitArm <= 0.0:
			quitArm = -1.0
			_hitsFor()
	if kp.pt > 0.0:
		kp.pt -= dt
		if kp.pt <= 0.0:
			kp.press = -1
	if entry.err > 0.0:
		entry.err -= dt
	if conn.state != "":
		conn.t += dt
		if conn.state == "connecting":
			var n = _net()
			if n != null and n.get("active") == true and n.get("status") == "connected":
				conn.state = ""   # (a missed net:status 'connected')
				m.showLobby()
				return
			if conn.t > (CONNECT_TIMEOUT_RTC if conn.get("rtc", false) else CONNECT_TIMEOUT):
				_fail("timeout")
	if m._camBlend < 1.0:
		m._camBlend = minf(1.0, m._camBlend + dt / m._camDur)
	_tv(dt)
	if off >= 0.0:
		_powerOff(dt)

func _tv(dt: float) -> void:
	var R = m._room
	if R == null:
		return
	var TV: Dictionary = R.tv
	var u: Dictionary = TV.u
	var t := tvT
	var rt: float = game.time.realNow
	TV.pic = TV.titleTex
	u.uPic = 1.0
	u.uUI = 1.0
	if conn.state == "connecting":
		# tuning: snow with a rolling hold, the logo ghosting through now and then
		u.uSnow = 0.82 + 0.12 * sin(rt * 7.0)
		u.uRoll = fmod(rt * 0.6, 1.0)
		u.uSeam = 0.9
		u.uJitter = 0.7
		m._tvGlow("#C8D8FF", 1.4 + randf() * 0.6)
	else:
		var settle: float = m.clamp_((t - 0.16) / 0.45, 0.0, 1.0)
		var hic := maxf(0.0, sin(rt * 0.9) - 0.985) * 60.0
		u.uSnow = 1.0 if t < 0.16 else m.lerp_(0.85, 0.035, m.easeOut(settle))
		u.uRoll = 0.0 if t < 0.16 else (1.0 - m.easeOut(settle)) * 0.6
		u.uSeam = 0.9 if settle < 1.0 else 0.0
		u.uJitter = m.lerp_(0.8, 0.02, m.easeOut(settle)) + hic * 0.4
		m._tvGlow("#C8D8FF" if t < 0.16 else "#FFB070", 1.4 + randf() * 0.6 if t < 0.16 else 1.7 + hic)
	u.uBright = 1.0 if off < 0.0 else maxf(0.0, 1.0 - off / 0.35)
	_drawOsd()

# The green OSD channel number in the TV picture's top-right corner (2.4 s, then it fades), like the dial's.
func _drawOsd() -> void:
	var TV: Dictionary = m._room.tv
	var x = TV.uiCtx
	if x == null:
		return
	var a: float = 1.0 if osd.t < 2.4 else m.clamp_(1.0 - (osd.t - 2.4) / 0.5, 0.0, 1.0)
	var key := "main|%s|%s" % [osd.ch, String.num(a, 2)]
	if key == TV.uiKey:
		return
	TV.uiKey = key
	var W: float = TV.ui.width
	var H: float = TV.ui.height
	x.clearRect(0, 0, W, H)
	if a > 0.0 and osd.ch != "":
		x.globalAlpha = a
		x.font = "92px " + DAFonts.FONTS.tape
		x.textAlign = "right"
		x.textBaseline = "top"
		x.fillStyle = "rgba(10,20,10,.75)"
		x.fillText(osd.ch, W - 34 + 4, 22 + 4)
		x.fillStyle = "#5CFF6E"
		x.fillText(osd.ch, W - 34, 22)
		x.globalAlpha = 1
	if TV.ui.has_method("redraw"):
		TV.ui.redraw()

func _powerOff(dt: float) -> void:
	off += dt
	var post = game.render.get("post") if game.render else null
	var k: float = m.clamp_(off / 0.55, 0.0, 1.0)
	if post is Dictionary:
		post.collapse = m.easeIn(k) * 0.55 + k * 0.45
	if off > 0.62 and not m._css.bg.black:
		m._css.bg.on = true
		m._css.bg.black = true
	if off > 0.95:
		off = -2.0
		var tree = game.get_tree() if game.is_inside_tree() else null
		if tree:
			tree.quit()

# -------------------------------------------------------------------------------------------- paint
func draw(ci: Control) -> void:
	if off >= 0.0 or off < -1.0:
		return
	if screen == "options":
		m._drawOptions(ci)
		return
	if screen == "controls":
		m._drawControls(ci)
		return
	if screen == "main":
		_drawMain(ci)
		return
	if screen == "mp" or screen == "join":
		_drawRowsCard(ci)
		return
	_drawEntry(ci)

func _drawMain(ci: Control) -> void:
	var items := mainItems()
	# header (the dial's "Who's on tonight?" sibling): Shrikhand 58, rotate(-2deg), centred over the pills
	var ha: float = m.easeOut(m.clamp_((inT - 0.2) / 0.5, 0.0, 1.0))
	if ha > 0.001:
		var s := "What's on tonight?"
		var lh: float = m._lh(m._fonts.logo, 58)
		var cx := PX + PW / 2.0 + 13.0
		var cy := PY - 30.0 - lh / 2.0
		var tw: float = m._tw("logo", 58, s)
		ci.draw_set_transform(Vector2(cx, cy), deg_to_rad(-2.0), Vector2.ONE)
		m._txt(ci, "logo", 58, -tw / 2.0, 0.0, s, "#FFE9B8", 0.0, [[0.0, 4.0, 0.0, "#8A2E14"], [0.0, 8.0, 16.0, "rgba(0,0,0,.5)"]], ha)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	for i in items.size():
		var p: float = m.clamp_((inT - (0.3 + 0.07 * i)) / 0.42, 0.0, 1.0)
		if p <= 0.0:
			continue
		var a: float = m.easeOut(p)
		var dx: float = (1.0 - m.easeOutBack(p, 1.4)) * 160.0
		var it: Dictionary = items[i]
		var warn: bool = it.label == "QUIT" and quitArm > 0.0
		var off_: bool = it.get("off", false)
		m._drawPill(ci, PX + dx, PY + i * PSTEP, it.ch, "QUIT? SURE" if warn else it.label, i == sel, warn, a * (0.5 if off_ else 1.0))
		if off_:
			# a blue sticker on the pill's right end (the .gpanel tag style)
			var tls := 18.0 * 0.12
			var tw: float = m._tw("sign", 18, WEB_NOTE, tls) + 24.0
			var th: float = m._lh(m._fonts.sign, 18) + 12.0
			ci.draw_set_transform(Vector2(PX + dx + 640.0 - tw / 2.0 - 10.0, PY + i * PSTEP + 14.0), deg_to_rad(-4.0), Vector2.ONE)
			m._paintBox(ci, "tag%d" % int(tw), -tw / 2.0, -th / 2.0, tw, th, {"r": 8, "bg": "#2F5BD3"}, a)
			m._txt(ci, "sign", 18, -tw / 2.0 + 12.0, 0.0, WEB_NOTE, "#F6E7C8", tls, [], a)
			ci.draw_set_transform_matrix(Transform2D.IDENTITY)

func _drawRowsCard(ci: Control) -> void:
	var rows := _rows()
	var L := _rowsLayout(rows)
	var extra := 0.0
	var line := _statusLine()
	if line.text != "":
		extra = 46.0
	m._gpanel(ci, L.bottom - 110.0 + extra + 84.0, "Multiplayer" if screen == "mp" else "Join", "CO-OP · 1-4 PLAYERS" if screen == "mp" else "LOCAL LISTINGS")
	var k: String = screen
	var s: int = rsel[k]
	for i in rows.size():
		_drawRow(ci, rows[i], L.rects[i], i == s and conn.state != "connecting", i)
	var y: float = L.bottom + 4.0
	if line.text != "":
		_drawStatus(ci, y, line)
		y += extra
	if conn.state == "connecting":
		_drawHints(ci, y + 14.0, [["b", "CANCEL"]] if _pad() else [["kc:ESC", "CANCEL"]])
	else:
		_drawHints(ci, y + 14.0, [["a", "SELECT"], ["b", "BACK"]] if _pad() else [["kc:ENTER", "SELECT"], ["kc:ESC", "BACK"]])

func _statusLine() -> Dictionary:
	var here: bool = screen == ("mp" if conn.get("rtc", false) else "join")
	if here and conn.state == "connecting":
		var dots := ".".repeat(1 + int(conn.t * 3.0) % 3)
		var what := "TUNING IN TO %s" % conn.text
		var n = _net()
		if conn.get("rtc", false) and n != null:
			var rs = (n.get("room") as Dictionary).get("state", "") if n.get("room") is Dictionary else ""
			what = ("LINKING UP WITH %s" if rs == "connecting" else "LOOKING FOR %s") % conn.text
		return {"text": what + dots, "err": false, "busy": true}
	if here and conn.state == "error" and conn.t < 12.0:
		return {"text": conn.err, "err": true, "busy": false}
	if screen == "mp" and status.text != "" and status.t < 6.0:
		return {"text": status.text, "err": status.err, "busy": false}
	return {"text": "", "err": false, "busy": false}

func _drawStatus(ci: Control, y: float, line: Dictionary) -> void:
	var col := "#C8302A" if line.err else "#2F5BD3"
	var r := Rect2(CX0, y, CW, 38.0)
	m._paintBox(ci, "stLine%s" % line.err, r.position.x, r.position.y, r.size.x, r.size.y, {"r": 19, "bg": "rgba(200,48,42,.12)" if line.err else "rgba(47,91,211,.10)"})
	var x := r.position.x + 18.0
	if line.get("busy"):
		# a small VHF dial spinning while tuning
		var t: float = game.time.realNow
		var c := Vector2(x + 11.0, r.get_center().y)
		ci.draw_arc(c, 10.0, 0.0, TAU, 20, DAU.color("#2F5BD3"), 2.5, true)
		ci.draw_line(c, c + Vector2(cos(t * 5.0), sin(t * 5.0)) * 8.0, DAU.color("#2F5BD3"), 2.5, true)
		x += 32.0
	m._txt(ci, "sign", 16, x, r.get_center().y, line.text, col, 16.0 * 0.06)

func _drawRow(ci: Control, r: Dictionary, rect: Rect2, s: bool, i: int) -> void:
	var info: bool = r.get("type") == "info"
	var dim: bool = r.get("ok") == false
	if s:
		m._paintBox(ci, "frowSel", rect.position.x, rect.position.y, rect.size.x, rect.size.y, {"r": 31, "bg": "#2F5BD3", "shadows": [[0, 0, 0, 3, "#E8A92E"]]})
	elif not info:
		m._paintBox(ci, "frow", rect.position.x, rect.position.y, rect.size.x, rect.size.y, {"r": 31, "bg": "rgba(90,58,34,.10)"})
	var cy := rect.get_center().y
	var col := "#F6E7C8" if s else ("#9A8670" if dim else "#3A2414")
	var ls := 30.0 * 0.06
	if r.get("type") == "back":
		var bw: float = m._tw("hud", 28, r.label, 28.0 * 0.06)
		m._txt(ci, "hud", 28, rect.position.x + (rect.size.x - bw) / 2.0, cy, r.label, col, 28.0 * 0.06)
		return
	if info:
		var dots := " ·".repeat(1 + int(game.time.realNow * 2.5) % 3)
		var t2: String = r.label + dots
		m._txt(ci, "hud", 26, rect.position.x + 22.0, cy, t2, "#8A6428", 26.0 * 0.06, [], 0.55 + 0.45 * absf(sin(game.time.realNow * 2.0)))
		return
	var x := rect.position.x + 22.0
	m._txt(ci, "hud", 30, x, cy, r.label, col, ls)
	x += m._tw("hud", 30, r.label, ls) + 14.0
	var right := rect.end.x - 20.0
	if r.get("type") == "lan":
		# address (VT323), players n/max, and a red tag when it cannot be joined
		var pl: String = r.players
		var pw: float = m._tw("tape", 38, pl)
		m._txt(ci, "tape", 38, right - pw, cy, pl, "#F6E7C8" if s else "#5A3A22")
		right -= pw + 14.0
		if r.tag != "":
			var tw: float = m._tw("sign", 14, r.tag, 14.0 * 0.1) + 20.0
			m._paintBox(ci, "ftag%d" % int(tw), right - tw, cy - 14.0, tw, 28.0, {"r": 8, "bg": "#C8302A"})
			m._txt(ci, "sign", 14, right - tw + 10.0, cy, r.tag, "#F6E7C8", 14.0 * 0.1)
			right -= tw + 12.0
		m._txt(ci, "tape", 26, x, cy + 2.0, r.ip, "#C9D3F5" if s else "#8A6428")
		return
	if r.has("value"):
		# the name on a Dymo tape, right-aligned
		var v: String = r.value
		var vw: float = maxf(150.0, m._tw("hud", 26, v, 26.0 * 0.08) + 44.0)
		var tex: Texture2D = m._svgTex("fdymo%d" % int(vw), func(): return HudScript.svgTexture(m._dymoSvg(vw, 46.0)))
		var dx := right - vw
		ci.draw_set_transform(Vector2(dx + vw / 2.0, cy), deg_to_rad(-1.5), Vector2.ONE)
		if tex:
			ci.draw_texture_rect(tex, Rect2(-vw / 2.0 - 14, -23 - 10, vw + 28, 46 + 30), false)
		var emb := [[0.0, -1.0, 0.0, "rgba(0,0,0,.9)"], [0.0, 1.0, 0.0, "rgba(255,255,255,.35)"], [0.0, 2.0, 3.0, "rgba(0,0,0,.5)"]]
		m._txt(ci, "hud", 26, -vw / 2.0 + 22.0, 0.0, v, "#F2F0EA", 26.0 * 0.08, emb)
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	var hint = r.get("hint")
	if hint != null and str(hint) != "":
		var h: String = str(hint)
		var fk := "tape" if r.id == "addr" and addr != "" else "sign"
		var sz := 30.0 if fk == "tape" else 14.0
		var hw: float = m._tw(fk, sz, h, 0.0 if fk == "tape" else 14.0 * 0.1)
		m._txt(ci, fk, sz, right - hw, cy, h, "#C9D3F5" if s else "#B5472A", 0.0 if fk == "tape" else 14.0 * 0.1)

func _pad() -> bool:
	return m._padMode()

# Button hints along the card's bottom: [glyph, label] — glyph 'a'/'b'/'x'/'y'/'start' (Xbox) or 'kc:TEXT' (a key cap).
func _drawHints(ci: Control, y: float, hints: Array) -> void:
	var items: Array = []
	var total := 0.0
	for h in hints:
		var g: String = h[0]
		var gw := 40.0
		if g.begins_with("kc:"):
			gw = maxf(44.0, m._tw("hud", 18, g.substr(3), 18.0 * 0.06) + 20.0)
		var lw: float = m._tw("sign", 14, h[1], 14.0 * 0.12)
		items.append([g, h[1], gw, lw])
		total += gw + 8.0 + lw + 26.0
	total -= 26.0
	var x := CX0 + (CW - total) / 2.0
	var cy := y + 20.0
	for it in items:
		var g: String = it[0]
		if g.begins_with("kc:"):
			var t: String = g.substr(3)
			var kw: float = it[2]
			m._paintBox(ci, "hkc%d" % int(kw), x, cy - 18.0, kw, 36, {"r": 9, "bg": {"lin": 180, "stops": [["#4A3A30", 0.0], ["#2A1E18", 1.0]]},
				"shadows": [[0, 3, 0, 0, "#140C08"]], "insets": [[0, 1, 0, 0, "rgba(255,255,255,.2)"]]})
			m._txt(ci, "hud", 18, x + (kw - m._tw("hud", 18, t, 18.0 * 0.06)) / 2.0, cy, t, "#F6E7C8", 18.0 * 0.06)
		else:
			var gname := "MENU" if g == "start" else g.to_upper()
			m._drawPadGlyph(ci, gname, x, cy)
		x += float(it[2]) + 8.0
		m._txt(ci, "sign", 14, x, cy, it[1], "#5A3A22", 14.0 * 0.12)
		x += float(it[3]) + 26.0

func _drawEntry(ci: Control) -> void:
	var K := _kpLayout()
	var isName := screen == "name"
	var isCode := screen == "code"
	m._gpanel(ci, K.bottom - 110.0 + 26.0, "Your Name" if isName else ("Room Code" if isCode else "Address"),
		"ON-SCREEN CREDIT" if isName else ("ENTER YOUR FRIEND'S CODE" if isCode else "DIAL A STATION"))
	var f: Rect2 = K.field
	var t: float = game.time.realNow
	var blink := fmod(t, 1.0) < 0.55
	var shake: float = sin(entry.err * 60.0) * 8.0 * (entry.err / 0.6) if entry.err > 0.0 else 0.0
	var txt: String = entry.text
	if isName:
		# a Dymo tape with the embossed name (the label maker of the dial's TUNE IN tape)
		var vw := CW - 120.0
		var tex: Texture2D = m._svgTex("fdymoN%d" % int(vw), func(): return HudScript.svgTexture(m._dymoSvg(vw, 70.0)))
		ci.draw_set_transform(Vector2(f.get_center().x + shake, f.get_center().y), deg_to_rad(-1.0), Vector2.ONE)
		if tex:
			ci.draw_texture_rect(tex, Rect2(-vw / 2.0 - 14, -35 - 10, vw + 28, 70 + 30), false)
		var emb := [[0.0, -1.0, 0.0, "rgba(0,0,0,.9)"], [0.0, 1.0, 0.0, "rgba(255,255,255,.35)"], [0.0, 2.0, 3.0, "rgba(0,0,0,.5)"]]
		var tw: float = m._tw("hud", 38, txt, 38.0 * 0.08)
		var x0 := -tw / 2.0
		m._txt(ci, "hud", 38, x0, 0.0, txt, "#F2F0EA", 38.0 * 0.08, emb)
		if blink:
			ci.draw_rect(Rect2(x0 + tw + 4.0, -20.0, 5.0, 40.0), DAU.color("#F2F0EA"))
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	else:
		# a green-phosphor readout (the OSD's VT323) in a dark bezel
		m._paintBox(ci, "faddr", f.position.x + shake, f.position.y, f.size.x, f.size.y, {"r": 18, "bg": {"lin": 180, "stops": [["#16121E", 0.0], ["#0C0A12", 1.0]]},
			"shadows": [[0, 0, 0, 4, "#5A3A22"]], "insets": [[0, 4, 14, 0, "rgba(0,0,0,.7)"]]})
		var shown := txt if txt != "" else ""
		var x1: float = f.position.x + 26.0 + shake
		var cy := f.get_center().y
		if isCode:
			# XXXX-XXXX: typed characters bright, the empty places as dim underscores, the cursor on the next place
			var cw: float = m._tw("tape", 56, "W")
			var x2: float = f.position.x + (f.size.x - cw * 9.0 - 12.0) / 2.0 + shake
			for i in RtcScript.CODE_LEN:
				var cx2: float = x2 + (i + (1 if i >= 4 else 0)) * (cw + 1.5)
				if i < txt.length():
					m._txt(ci, "tape", 56, cx2, cy, txt[i], "#5CFF6E", 0.0, [[0.0, 0.0, 10.0, "rgba(92,255,110,.45)"]])
				elif i == txt.length() and blink:
					ci.draw_rect(Rect2(cx2, cy - 22.0, cw, 44.0), DAU.color("#5CFF6E"))
				else:
					m._txt(ci, "tape", 56, cx2, cy, "_", "rgba(92,255,110,.3)")
			m._txt(ci, "tape", 56, x2 + 4.0 * (cw + 1.5), cy, "-", "rgba(92,255,110,.6)")
		elif shown == "":
			m._txt(ci, "tape", 48, x1, cy, "IP OR IP:PORT", "rgba(92,255,110,.25)")
		else:
			m._txt(ci, "tape", 48, x1, cy, shown, "#5CFF6E", 0.0, [[0.0, 0.0, 10.0, "rgba(92,255,110,.45)"]])
		if blink and not isCode:
			var cx: float = x1 + (m._tw("tape", 48, shown) if shown != "" else 0.0) + 3.0
			ci.draw_rect(Rect2(cx, cy - 20.0, 20.0, 40.0), DAU.color("#5CFF6E"))
	# caption
	var cap := "LETTERS · DIGITS · . - _ '  ·  %d MAX" % NAME_MAX if isName else "DEFAULT PORT %d" % _port()
	if isCode:
		cap = "8 CHARACTERS · NO I, L, O, 0 OR 1" + ("" if WEB else "  ·  CTRL+V PASTES")
	m._txt(ci, "sign", 14, f.position.x + 4.0, f.end.y + 22.0, cap, "#8A6428", 14.0 * 0.12)
	# keys
	for i in K.keys.size():
		_drawKey(ci, K.keys[i], i == kp.i, i == kp.press)
	var b: Rect2 = K.back
	m._paintBox(ci, "frowB", b.position.x, b.position.y, b.size.x, b.size.y, {"r": 25, "bg": "rgba(90,58,34,.10)"})
	var bt := "◀ BACK"
	m._txt(ci, "hud", 26, b.position.x + (b.size.x - m._tw("hud", 26, bt, 26.0 * 0.06)) / 2.0, b.get_center().y, bt, "#3A2414", 26.0 * 0.06)
	var hints: Array
	if _pad():
		hints = [["a", "PRESS"], ["x", "DELETE"]] + ([["y", "SPACE"]] if isName else []) + [["start", "OK" if isName else "TUNE IN"], ["b", "BACK"]]
	else:
		hints = [["kc:A-Z" if isName or isCode else "kc:0-9", "TYPE"], ["kc:ENTER", "OK" if isName else "TUNE IN"], ["kc:ESC", "BACK"]]
	_drawHints(ci, b.end.y + 4.0, hints)

# One push button of the keypad: cream Touch-Tone key (OK blue, DEL rust); the highlight is the pills' orange.
func _drawKey(ci: Control, k: Dictionary, s: bool, down: bool) -> void:
	var r: Rect2 = k.rect
	var off2 := 3.0 if down else 0.0
	var act: String = k.act
	var bg: Dictionary = {"lin": 180, "stops": [["#FBF6EA", 0.0], ["#E6DAC2", 1.0]]}
	var ink := "#3A2414"
	if act == "ok":
		bg = {"lin": 180, "stops": [["#4A72E0", 0.0], ["#2F5BD3", 1.0]]}
		ink = "#F6E7C8"
	elif act == "del":
		ink = "#B5472A"
	if s:
		bg = {"lin": 180, "stops": [["#F59A48", 0.0], ["#D9602B", 0.55], ["#A8401E", 1.0]]}
		ink = "#FFFBEA"
	var key := "fkey%d_%d_%s_%s_%s" % [int(r.size.x), int(r.size.y), act, s, down]
	m._paintBox(ci, key, r.position.x, r.position.y + off2, r.size.x, r.size.y, {"r": 12, "bg": bg,
		"shadows": [[0, 1 if down else 4, 0, 0, "#8A6A4A" if not s else "#6A2410"], [0, 6 if not down else 2, 10, 0, "rgba(0,0,0,.25)"]],
		"insets": [[0, 2, 0, 0, "rgba(255,255,255,.55)" if not s else "rgba(255,220,170,.35)"]]})
	var lab: String = k.label
	var sz := 30.0 if lab.length() <= 2 else 22.0
	var lw: float = m._tw("hud", sz, lab, sz * 0.06)
	m._txt(ci, "hud", sz, r.position.x + (r.size.x - lw) / 2.0, r.get_center().y + off2, lab, ink, sz * 0.06)
