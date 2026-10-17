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

## Lo que pide un cliente: el id de una poción, o el de un hechizo si pide un pergamino ("scroll").
static func wanted(req: Dictionary) -> String:
	for k in ["scroll", "spell"]:
		if req.has(k):
			return String(req[k])
	return String(req.get("potion", ""))

## "potion" o "scroll".
static func wanted_kind(req: Dictionary) -> String:
	if req.has("scroll") or req.has("spell"):
		return "scroll"
	var p := String(req.get("potion", ""))
	return "potion" if p == "" or Data.POTIONS.has(p) else "scroll"

## Los hechizos de MAGIC (Data.SPELLS), si existen.
static func spells() -> Dictionary:
	var s = Data.get("SPELLS")
	return s if s is Dictionary else {}

static func item_name(kind: String, id: String) -> String:
	if kind == "potion" and Data.POTIONS.has(id):
		return String(Data.POTIONS[id]["name"])
	var sp := spells()
	if sp.has(id) and sp[id] is Dictionary:
		return String(sp[id].get("name", id))
	return id.replace("_", " ").capitalize()

## Nombre de un ingrediente u objeto (regalos).
static func thing_name(id: String) -> String:
	if Data.INGREDIENTS.has(id):
		return String(Data.INGREDIENTS[id]["name"])
	var mi = Data.get("MAGIC_ITEMS")
	if mi is Dictionary and mi.has(id) and mi[id] is Dictionary:
		return String(mi[id].get("name", id))
	return id.replace("_", " ").capitalize()

static func _scroll_base(id: String) -> int:
	var sp := spells()
	if sp.has(id) and sp[id] is Dictionary:
		for k in ["price", "base", "value"]:
			if sp[id].has(k):
				return int(sp[id][k])
	return 20

## Lo que paga el cliente al recibirlo: el precio. La propina llega después, con las noticias.
static func price_of(item: Dictionary) -> int:
	var potency := int(item.get("potency", 5))
	if String(item.get("kind", "potion")) == "potion":
		return int(Game.price_for(String(item["id"]), potency, 0)["price"])
	if Game.has_method("scroll_price"):
		return int(Game.call("scroll_price", String(item["id"]), potency))
	var mult: float = [1.0, 1.0, 1.35, 1.75][Game.stars_for(potency)]
	return int(round(_scroll_base(String(item["id"])) * mult))

## La propina (llega con las noticias). misses: pergaminos equivocados que el cliente devolvió antes (bajan la propina).
static func tip_of(item: Dictionary, misses := 0) -> int:
	var potency := int(item.get("potency", 5))
	if String(item.get("kind", "potion")) == "potion":
		return int(Game.price_for(String(item["id"]), potency, misses)["tip"])
	var base := _scroll_base(String(item["id"]))
	var tip_mult := 1.0 - 0.2 * mini(misses, 2)
	return maxi(0, int(round(base * 0.25 * tip_mult + base * Game.tip_bonus())))

# ------------------------------------------------------------------ al entregar

## Lo que dice el cliente al recibir la poción o el pergamino: solo lo que puede notar ahora (color, olor, brillo,
## etiqueta) y lo que piensa hacer. Nadie dice que ya funcionó: no lo ha usado. Si no es lo que imaginaba, lo nota
## al leer la etiqueta (una pista suave, no una certeza), pero confía en la alquimista y se la lleva igual.
static func reaction(req: Dictionary, item: Dictionary, ok: bool) -> String:
	var kind := String(item.get("kind", "potion"))
	var id := String(item.get("id", ""))
	if ok and kind == "scroll" and Game.has_method("scroll_react_line"):
		return String(Game.call("scroll_react_line", item))   # MAGIC: lee la etiqueta y nota la tinta (SPELLS[id].react)
	var stars := Game.stars_for(int(item.get("potency", 5)))
	var sense := pick(Data.REACTIONS.get(id, Data.REACTIONS["_scroll" if kind == "scroll" else "_potion"]))
	var parts: Array = []
	if ok and String(req.get("kind", "")) == "hero" and req.has("react"):
		if stars == 3:
			parts.append(pick(Data.REACTION_QUALITY[3]))
		parts.append(String(req["react"]))
		return " ".join(parts)
	if ok:
		if randf() < 0.3:
			parts.append(pick(Data.REACTION_LABEL["right"]).replace("{p}", item_name(kind, id)))
		else:
			parts.append(sense)
		parts.append(pick(Data.REACTION_QUALITY[stars]))
	else:
		parts.append(pick(Data.REACTION_LABEL["wrong"]).replace("{p}", item_name(kind, id)))
		parts.append(sense)
	parts.append(plan_line(req))
	var text := " ".join(parts.filter(func(s): return s != ""))
	if text.length() < 150:
		text += " " + pick(Data.REACTION_FAREWELL)
	return text

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
	if ok:
		o["grade"] = ["ok", "ok", "good", "great"][stars]
		var tip := tip_of(item, misses)
		o["tip"] = tip + (int(round(tip * 0.5)) if stars == 3 else 0)
		o["renombre"] = stars + (2 if hero else 0)
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
		var g := String(o.get("grade", "good"))
		if g == "great" and String(o.get("req_kind", "")) != "hero":
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
			fx_key = "_scroll" if String(o.get("item_kind", "")) == "scroll" else "_any"
		body = "%s %s\n\n%s" % [fail, pick(Data.WRONG_EFFECTS[fx_key]), pick(Data.LETTERS["complaint_close"])]
	return {"who": who, "sprite": sprite_id(who), "name": char_name(who), "title": char_title(who),
		"hello": String(ch.get("hello", Data.LETTERS["hello_default"])), "body": body,
		"sign": String(ch.get("sign", char_name(who))), "reward": reward_line(res, who), "ok": bool(o.get("ok", false))}

## Lo que cuenta quien vuelve a la tienda (main.gd _talk_return).
static func visit_text(o: Dictionary, res: Dictionary) -> String:
	var hero := String(o.get("req_kind", "")) == "hero"
	var t := pick(Data.RETURN_VISITS["open_hero" if hero else "open"]) + " " + String(o.get("good", ""))
	var g := String(o.get("grade", "good"))
	if g == "great" and not hero:
		t += " " + pick(Data.RETURN_VISITS["great"])
	elif g == "ok":
		t += " " + pick(Data.RETURN_VISITS["ok"])
	if String(res.get("gift_text", "")) != "":
		t += " " + String(res["gift_text"])
	return t

## Lo que trajo una noticia, en una línea con colores (propina, renombre, regalos; o lo que costó una queja).
static func reward_line(res: Dictionary, who := "") -> String:
	var bits: Array = []
	if int(res.get("tip", 0)) > 0:
		bits.append("[color=#ffd987]+%d oro de propina[/color]" % int(res["tip"]))
	if int(res.get("gift_gold", 0)) > 0:
		bits.append("[color=#ffd987]+%d oro de regalo[/color]" % int(res["gift_gold"]))
	if int(res.get("renombre", 0)) > 0:
		bits.append("[color=#d9c8ff]+%d renombre[/color]" % int(res["renombre"]))
	for it in res.get("items", []):
		bits.append("[color=#9eea9f]+%d %s[/color]" % [int(it["qty"]), thing_name(String(it["id"]))])
	if res.get("journal", false):
		bits.append("[color=#ffd987]Nueva página en el Diario de viajeros[/color]")
	if int(res.get("refund", 0)) > 0:
		bits.append("[color=#ff9b9b]Le devuelves %d oro[/color]" % int(res["refund"]))
	if int(res.get("renombre", 0)) < 0:
		bits.append("[color=#ff9b9b]-%d renombre[/color]" % -int(res["renombre"]))
	if int(res.get("away", 0)) > 0 and who != "":
		bits.append("[color=#b8aecb]%s no vendrá en unos días[/color]" % char_name(who))
	return "   ·   ".join(bits)

## Lo que se comenta en el pueblo el día que llega alguien nuevo ("rumor" en CHARACTERS).
static func rumors_today() -> Array:
	var out: Array = []
	for who in Data.CHARACTERS:
		var c: Dictionary = Data.CHARACTERS[who]
		if c.has("rumor") and int(c.get("arrives", 1)) == Game.day:
			out.append(String(c["rumor"]))
	return out

# ------------------------------------------------------------------ pedidos del día

## Todos los pedidos posibles de vecinos y viajeros: VILLAGER_REQUESTS y, si MAGIC lo define, SCROLL_REQUESTS.
static func request_pool() -> Array:
	return Data.VILLAGER_REQUESTS + scroll_requests()

## Pedidos de pergaminos (Data.SCROLL_REQUESTS de MAGIC, si existe). Mismo formato que VILLAGER_REQUESTS, con
## "scroll": <id del hechizo> (también se acepta "spell", o "potion" con el id de un hechizo).
static func scroll_requests() -> Array:
	var sr = Data.get("SCROLL_REQUESTS")
	var out: Array = []
	if sr is Array:
		for r in sr:
			if r is Dictionary and r.has("who") and r.has("text"):
				out.append(r)
	return out

static func request_key(r: Dictionary) -> String:
	return "%s:%s:%d" % [String(r.get("who", "")), wanted(r), String(r.get("text", "")).hash()]

## Si un pedido se puede cumplir hoy: la poción se puede preparar, o el hechizo ya está en el grimorio.
static func request_ok(r: Dictionary, brewable: Dictionary) -> bool:
	if wanted_kind(r) == "potion":
		return brewable.has(wanted(r))
	return scroll_ok(r)

## Si la alquimista ya puede escribir el pergamino que pide un cliente: abrió el grimorio (Game.magic_unlocked), el
## hechizo está en sus páginas (Game.spell_known) y, si el pedido trae "needs": {"hero", "chapter"}, ese capítulo ya
## pasó. Mismas reglas que Game.scroll_requests() de MAGIC.
static func scroll_ok(r: Dictionary) -> bool:
	var id := wanted(r)
	if id == "":
		return false
	var unlocked = Game.get("magic_unlocked")
	if unlocked == null or not bool(unlocked):
		return false
	var need = r.get("needs", {})
	if need is Dictionary and need.has("hero") and int(Game.hero_progress.get(String(need["hero"]), 0)) < int(need.get("chapter", 1)):
		return false
	if Game.has_method("scroll_request_ok"):
		return bool(Game.call("scroll_request_ok", r))
	for m in ["can_inscribe", "knows_spell", "has_spell", "spell_known", "is_spell_learned", "spell_learned"]:
		if Game.has_method(m):
			return bool(Game.call(m, id))
	for v in ["learned_spells", "known_spells", "spells_learned", "learned"]:
		var s = Game.get(v)
		if s is Dictionary:
			return s.has(id) and not (s[id] is bool and s[id] == false)
		if s is Array:
			return s.has(id)
	return false
