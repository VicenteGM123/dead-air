extends RefCounted
class_name Story
## Las historias del pueblo: lo que dice un cliente al recibir una poción (todavía no la ha usado: solo puede verla,
## olerla y leer la etiqueta), cuándo y cómo llegan las noticias (una carta a la mañana siguiente o una visita días
## después) y los textos de esas noticias. El estado (noticias pendientes, quién está ofendido...) vive en game.gd
## (bloque STORY); los textos, en data.gd (REACTIONS, LETTERS, RETURN_VISITS, WRONG_EFFECTS, INTUITION...).

## Un texto al azar de una lista (o el texto tal cual).
static func pick(v) -> String:
	if v is Array:
		return "" if v.is_empty() else String(v.pick_random())
	return "" if v == null else String(v)

static func char_name(who: String) -> String:
	return String(Data.CHARACTERS.get(who, {}).get("name", who.capitalize()))

static func char_title(who: String) -> String:
	return String(Data.CHARACTERS.get(who, {}).get("title", ""))

## Sprite de un personaje: el suyo (assets/chars/<id>_idle.png) o, mientras no exista, su "fallback" de CHARACTERS.
static func sprite_id(who: String) -> String:
	if ResourceLoader.exists("res://assets/chars/%s_idle.png" % who):
		return who
	var fb := String(Data.CHARACTERS.get(who, {}).get("fallback", ""))
	if fb != "" and ResourceLoader.exists("res://assets/chars/%s_idle.png" % fb):
		return fb
	return "anciano"

# ------------------------------------------------------------------ qué pide y qué recibe

## Lo que pide un cliente: el id de una poción. Las runas que quiere en la etiqueta van aparte (Game.order_runes).
## --- R3 MAGIC3: ya no hay pergaminos
static func wanted(req: Dictionary) -> String:
	return String(req.get("potion", ""))

## Siempre "potion" (antes también "scroll"; se deja por compatibilidad).   # --- R3 MAGIC3
static func wanted_kind(_req: Dictionary) -> String:
	return "potion"

static func item_name(_kind: String, id: String) -> String:
	if Data.POTIONS.has(id):
		return String(Data.POTIONS[id]["name"])
	return id.replace("_", " ").capitalize()   # (noticias viejas de pergaminos)   # --- R3 MAGIC3

## --- R3 MAGIC3: nombre de una runa ("Prisa").
static func rune_name(id: String) -> String:
	return String(Data.RUNES[id]["name"]) if Data.RUNES.has(id) else id.capitalize()

## Nombre de un ingrediente u objeto (regalos).
static func thing_name(id: String) -> String:
	if Data.INGREDIENTS.has(id):
		return String(Data.INGREDIENTS[id]["name"])
	var mi = Data.get("MAGIC_ITEMS")
	if mi is Dictionary and mi.has(id) and mi[id] is Dictionary:
		return String(mi[id].get("name", id))
	return id.replace("_", " ").capitalize()

## Lo que paga el cliente al recibirlo: el precio de la poción y, por cada runa que pidió y va en la etiqueta, un extra
## según sus estrellas (Game.rune_bonus). La propina llega después, con las noticias.   # --- R3 MAGIC3
static func price_of(item: Dictionary, req := {}) -> int:
	var potency := int(item.get("potency", 5))
	return int(Game.price_for(String(item["id"]), potency, 0)["price"]) + Game.rune_bonus(item, req)

## La propina (llega con las noticias). misses: intentos fallidos antes (bajan la propina).
static func tip_of(item: Dictionary, misses := 0) -> int:
	return int(Game.price_for(String(item["id"]), int(item.get("potency", 5)), misses)["tip"])   # --- R3 MAGIC3

# ------------------------------------------------------------------ al entregar

## Lo que dice el cliente al recibir la poción o el pergamino: solo lo que puede notar ahora (color, olor, brillo,
## etiqueta) y lo que piensa hacer. Nadie dice que ya funcionó: no lo ha usado. Si no es lo que imaginaba, lo nota
## al leer la etiqueta (una pista suave, no una certeza), pero confía en la alquimista y se la lleva igual.
static func reaction(req: Dictionary, item: Dictionary, ok: bool) -> String:
	var kind := String(item.get("kind", "potion"))
	var id := String(item.get("id", ""))
	var stars := Game.stars_for(int(item.get("potency", 5)))
	var sense := pick(Data.REACTIONS.get(id, Data.REACTIONS["_potion"]))   # --- R3 MAGIC3
	var parts: Array = []
	if ok and String(req.get("kind", "")) == "hero" and req.has("react"):
		if stars == 3:
			parts.append(pick(Data.REACTION_QUALITY[3]))
		parts.append(String(req["react"]))
		return " ".join(parts)
	# --- R3 MERGE: dieta de texto: dos frases cortas. Lo que nota (la calidad si brilla o si salió floja; si no, el
	# olor o la etiqueta) y luego la runa de la etiqueta (MAGIC3) o lo que piensa hacer. Sin despedida: ya la dice el botón.
	if ok:
		if stars == 3 or stars == 1:
			parts.append(pick(Data.REACTION_QUALITY[stars]))
		elif randf() < 0.3:
			parts.append(pick(Data.REACTION_LABEL["right"]).replace("{p}", item_name(kind, id)))
		else:
			parts.append(sense)
		var rr := rune_react(req, item)   # --- R3 MAGIC3: lo que ve en la etiqueta (la runa que pidió, o que falta)
		parts.append(rr if rr != "" else plan_line(req))
	else:
		parts.append(pick(Data.REACTION_LABEL["wrong"]).replace("{p}", item_name(kind, id)))
		parts.append(plan_line(req))
	return " ".join(parts.filter(func(s): return s != ""))
	# --- end R3 MERGE

## --- R3 MAGIC3: lo que dice el cliente de las runas de la etiqueta al recibir la poción (la ve, todavía no la usó).
static func rune_react(req: Dictionary, item: Dictionary) -> String:
	var chk: Dictionary = Game.rune_check(item, req)
	# --- R3 MERGE: una sola frase: primero lo que falta (es lo que importa), si no la runa pedida, si no la de regalo
	if not chk["missing"].is_empty():
		var r := String(chk["missing"][0])
		if not chk["extra"].is_empty():
			return pick(Data.RUNE_TEXT["wrong_now"]).replace("{r}", rune_name(r)).replace("{g}", rune_name(chk["extra"][0]))
		return pick(Data.RUNE_TEXT["miss_now"]).replace("{r}", rune_name(r))
	if not chk["matched"].is_empty():
		return pick(Data.RUNES[chk["matched"][0][0]]["react"])
	if chk["want"].is_empty() and not chk["extra"].is_empty():
		return pick(Data.RUNE_TEXT["extra_now"]).replace("{g}", rune_name(chk["extra"][0]))
	return ""
	# --- end R3 MERGE

## --- R3 MAGIC3: lo que cuenta la carta (o la visita) de las runas: la que pidió y funcionó, la que faltó (y lo que
## hizo la que venía en su lugar). o: la noticia (make_outcome guarda "rune_want" y "rune_got").
static func rune_line(o: Dictionary) -> String:
	var want: Array = o.get("rune_want", [])
	var got := {}
	for g in o.get("rune_got", []):
		if g is Array and g.size() >= 2:
			got[String(g[0])] = int(g[1])
	var bits: Array = []
	if want.is_empty():
		if not got.is_empty() and randf() < 0.5:
			bits.append(pick(Data.RUNE_TEXT["extra_letter"]).replace("{g}", rune_name(String(got.keys()[0]))))
		return " ".join(bits)
	var wrong := ""
	for g in got:
		if not want.has(g):
			wrong = g
	for r in want:
		var id := String(r)
		if not Data.RUNES.has(id):
			continue
		var st := int(got.get(id, 0))
		if st > 0:
			bits.append(pick(Data.RUNES[id]["good"]))   # (las estrellas ya cuentan en el oro y el renombre)
		else:
			bits.append(pick(Data.RUNES[id]["miss"]))
			if wrong != "" and Data.RUNES.has(wrong):
				bits.append(pick(Data.RUNES[wrong]["fx"]))
				wrong = ""
	return " ".join(bits)

static func plan_line(req: Dictionary) -> String:
	if req.has("plan"):
		return String(req["plan"])
	return pick(Data.REACTION_PLANS.get(wanted(req), Data.REACTION_PLANS["_any"]))

## La noticia pendiente de una entrega: lo que traerá (propina, renombre... o una queja) y cuándo y cómo llega.
## Las quejas y el tutorial llegan por carta al día siguiente; los vecinos a veces vuelven en persona (1-3 días); los
## aventureros vuelven a contarlo (2-3 días) o escriben, según el capítulo ("via"). Se guarda con Game.schedule_outcome.
static func make_outcome(req: Dictionary, item: Dictionary, ok: bool, price: int, misses := 0) -> Dictionary:
	var who := String(req.get("who", ""))
	var hero := String(req.get("kind", "")) == "hero"
	var potency := int(item.get("potency", 5))
	var stars := Game.stars_for(potency)
	var o := {"who": who, "req_kind": "hero" if hero else "villager", "item_kind": String(item.get("kind", "potion")),
		"item": String(item.get("id", "")), "wanted": wanted(req), "potency": potency, "stars": stars, "ok": ok,
		"price": price, "day": Game.day, "tip": 0, "renombre": 0}
	# --- R3 MAGIC3: las runas que pidió y las que llevaba la etiqueta (la carta las cuenta)
	var chk: Dictionary = Game.rune_check(item, req)
	o["rune_want"] = chk["want"]
	o["rune_got"] = Game.potion_runes(item).map(func(r): return [r["id"], r["stars"]])
	# --- end R3 MAGIC3
	if ok:
		o["grade"] = ["ok", "ok", "good", "great"][stars]
		var tip := tip_of(item, misses)
		o["tip"] = tip + (int(round(tip * 0.5)) if stars == 3 else 0)
		o["renombre"] = stars + (2 if hero else 0)
		# --- R3 MAGIC3: cada runa que faltó: la mitad de propina y un punto menos de renombre; cada runa pedida de
		# 3 estrellas, un punto más
		for _r in chk["missing"]:
			o["tip"] = int(round(int(o["tip"]) * 0.5))
		var shine: int = chk["matched"].filter(func(m): return int(m[1]) >= 3).size()
		o["renombre"] = maxi(0, int(o["renombre"]) - chk["missing"].size() + shine)
		# --- end R3 MAGIC3
		o["good"] = String(req.get("good", req.get("thanks", req.get("outcome", ""))))
	else:
		o["grade"] = "bad"
		o["fail"] = String(req.get("fail", ""))
	if hero:
		o["chapter"] = int(req.get("chapter", 0))
	var via := "letter"
	var wait := 1
	if ok and not req.get("tutorial", false):
		if hero:
			via = String(req.get("via", "visit"))
			wait = randi_range(2, 3) if via == "visit" else randi_range(1, 2)
		elif bool(Data.CHARACTERS.get(who, {}).get("local", false)):
			if randf() < 0.45:
				via = "visit"
				wait = randi_range(1, 3)
		elif randf() < 0.35:
			wait = 2   # cartas que vienen de lejos
	o["via"] = via
	o["due"] = Game.day + wait
	return o

# ------------------------------------------------------------------ cuando llegan las noticias

## Una carta para el panel del correo (overlays.gd show_mail). res: lo que devolvió Game.resolve_outcome().
static func letter(o: Dictionary, res: Dictionary) -> Dictionary:
	var who := String(o.get("who", ""))
	var ch: Dictionary = Data.CHARACTERS.get(who, {})
	var body := ""
	if o.get("ok", false):
		body = String(o.get("good", ""))
		if body == "":
			body = pick(Data.LETTERS["good_default"])
		var rl := rune_line(o)   # --- R3 MAGIC3: la runa que pidió (o la que faltó)
		if rl != "":
			body += " " + rl
		var g := String(o.get("grade", "good"))
		if rl != "":
			pass   # --- R3 MERGE: dieta de texto: con la línea de la runa, sin la frase extra de la calidad
		elif g == "great" and String(o.get("req_kind", "")) != "hero":
			body += " " + pick(Data.LETTERS["great"])
		elif g == "ok":
			body += " " + pick(Data.LETTERS["ok"])
		if String(res.get("gift_text", "")) != "":
			body += "\n\nP.D.: " + String(res["gift_text"])
	else:
		var fail := String(o.get("fail", ""))
		if fail == "":
			fail = pick(Data.LETTERS["fail_default"])
		var fx_key := String(o.get("item", ""))
		if not Data.WRONG_EFFECTS.has(fx_key):
			fx_key = "_any"   # --- R3 MAGIC3 (también las noticias viejas de pergaminos)
		body = "%s %s\n\n%s" % [fail, pick(Data.WRONG_EFFECTS[fx_key]), pick(Data.LETTERS["complaint_close"])]
	var reward := reward_line(res, who)   # --- R4 RAVEN (antes iba directo en el diccionario)
	if bool(o.get("krapido", false)):   # --- R4 RAVEN: pedido a domicilio: la posdata del cuervo y la reseña en plumas
		if String(res.get("gift_text", "")) == "":
			body += "\n\n" + pick(Data.KRAPIDO_PD)
		reward = krapido_reward(res, reward)
	return {"who": who, "sprite": sprite_id(who), "name": char_name(who), "title": char_title(who),
		"hello": String(ch.get("hello", Data.LETTERS["hello_default"])), "body": body,
		"sign": String(ch.get("sign", char_name(who))), "reward": reward, "ok": bool(o.get("ok", false))}

## --- R4 RAVEN: la reseña en plumas (1 a 5) al final de lo que trae la carta de un pedido a domicilio.
static func krapido_reward(res: Dictionary, reward: String) -> String:
	var n := int(res.get("plumas", 0))
	if n <= 0:
		return reward
	var f := "[img=27]res://assets/ui/raven_head.png[/img] "
	for i in 5:
		f += "[img=27]res://assets/ui/pluma_%s.png[/img]" % ("full" if i < n else "empty")
	return (reward + "     " if reward != "" else "") + f

## Lo que cuenta quien vuelve a la tienda (main.gd _talk_return).
static func visit_text(o: Dictionary, res: Dictionary) -> String:
	var hero := String(o.get("req_kind", "")) == "hero"
	var t := pick(Data.RETURN_VISITS["open_hero" if hero else "open"]) + " " + String(o.get("good", ""))
	var rl := rune_line(o)   # --- R3 MAGIC3
	if rl != "":
		t += " " + rl
	var g := String(o.get("grade", "good"))
	if rl != "":
		pass   # --- R3 MERGE: dieta de texto (como en la carta)
	elif g == "great" and not hero:
		t += " " + pick(Data.RETURN_VISITS["great"])
	elif g == "ok":
		t += " " + pick(Data.RETURN_VISITS["ok"])
	if String(res.get("gift_text", "")) != "":
		t += " " + String(res["gift_text"])
	return t

## Lo que trajo una noticia, en una línea con colores (propina, renombre, regalos; o lo que costó una queja).
## --- R3 PAPER: iconos y números en vez de frases (el correo y las visitas lo muestran igual)
static func _ic(path: String, w := 32) -> String:
	return "[img=%d]%s[/img]" % [w, path]

static func reward_line(res: Dictionary, who := "") -> String:
	var bits: Array = []
	var coin := _ic("res://assets/icons/emote_coin.png")
	var gem := _ic("res://assets/icons/emote_gem.png")
	if int(res.get("tip", 0)) > 0:
		bits.append("%s [color=#ffd987]+%d[/color]" % [coin, int(res["tip"])])
	if int(res.get("gift_gold", 0)) > 0:
		bits.append("%s%s [color=#ffd987]+%d[/color]" % [_ic("res://assets/icons/emote_heart.png"), coin, int(res["gift_gold"])])
	if int(res.get("renombre", 0)) > 0:
		bits.append("%s [color=#d9c8ff]+%d[/color]" % [gem, int(res["renombre"])])
	for it in res.get("items", []):
		var id := String(it["id"])
		var icon := ""
		for path in ["res://assets/icons/ing_%s.png" % id, "res://assets/icons/%s.png" % id]:
			if icon == "" and ResourceLoader.exists(path):
				icon = path
		if icon != "":
			bits.append("%s [color=#9eea9f]+%d[/color]" % [_ic(icon), int(it["qty"])])
		else:
			bits.append("[color=#9eea9f]+%d %s[/color]" % [int(it["qty"]), thing_name(id)])
	if res.get("journal", false):
		bits.append("%s [color=#ffd987]Diario[/color]" % _ic("res://assets/ui/paper_i_page.png", 30))
	if int(res.get("refund", 0)) > 0:
		bits.append("%s [color=#ff9b9b]-%d[/color]" % [coin, int(res["refund"])])
	if int(res.get("renombre", 0)) < 0:
		bits.append("%s [color=#ff9b9b]%d[/color]" % [gem, int(res["renombre"])])
	if int(res.get("away", 0)) > 0 and who != "":
		bits.append("%s [color=#b8aecb]%d días[/color]" % [_ic("res://assets/ui/paper_i_door.png", 27), int(res["away"])])
	return "     ".join(bits)
# --- end R3 PAPER

## Lo que se comenta en el pueblo el día que llega alguien nuevo ("rumor" en CHARACTERS).
static func rumors_today() -> Array:
	var out: Array = []
	for who in Data.CHARACTERS:
		var c: Dictionary = Data.CHARACTERS[who]
		if c.has("rumor") and int(c.get("arrives", 1)) == Game.day:
			out.append(String(c["rumor"]))
	return out

# ------------------------------------------------------------------ pedidos del día

## Todos los pedidos posibles de vecinos y viajeros: VILLAGER_REQUESTS y los que traen runas (RUNE_REQUESTS).
static func request_pool() -> Array:
	return Data.VILLAGER_REQUESTS + Data.RUNE_REQUESTS   # --- R3 MAGIC3

static func request_key(r: Dictionary) -> String:
	return "%s:%s:%d" % [String(r.get("who", "")), wanted(r), String(r.get("text", "")).hash()]

## Si un pedido se puede cumplir hoy: la poción se puede preparar y, si pide runas, ya están en el grimorio.
static func request_ok(r: Dictionary, brewable: Dictionary) -> bool:
	return brewable.has(wanted(r)) and runes_ok(r)   # --- R3 MAGIC3

## --- R3 MAGIC3: si la alquimista ya puede inscribir las runas que pide (abrió el grimorio y las sabe; con "needs":
## {"hero", "chapter"}, después de ese capítulo; con "level", desde ese renombre).
static func runes_ok(r: Dictionary) -> bool:
	var rs = r.get("runes", [])
	if not (rs is Array) or rs.is_empty():
		return true
	for id in rs:
		if not Game.rune_known(String(id)):
			return false
	if rs.size() > Game.label_slots():
		return false
	var need = r.get("needs", {})
	if need is Dictionary and need.has("hero") and int(Game.hero_progress.get(String(need["hero"]), 0)) < int(need.get("chapter", 1)):
		return false
	return true
