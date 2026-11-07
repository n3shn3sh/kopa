class_name MatchState
extends RefCounted
## Lógica pura da partida, sem nada visual.
## Cada comando valida, resolve na hora (sorteios incluídos) e grava eventos em `events`.
## Esse registro é a fonte de verdade: o jogo e a cinemática só encenam o que está nele.
## Para PvP online, basta sincronizar os comandos (ou os eventos) entre os jogadores.

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var W: int = GameData.GRID_W
var H: int = GameData.GRID_H
var units: Dictionary = {}        # id -> unidade (Dictionary)
var obstacles: Dictionary = {}    # Vector2i -> true
var turn_queue: Array = []        # ids que ainda vão agir nesta rodada
var active_id: int = -1
var round_no: int = 0
var turn_no: int = 0
var moved: bool = false
var acted: bool = false
var winner: int = -1
var events: Array = []
var initial_snapshot: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _next_id: int = 0
var _parents: Dictionary = {}


func setup(seed_value: int) -> void:
	rng.seed = seed_value
	var base := [Vector2i(4, 1), Vector2i(4, 2), Vector2i(6, 5), Vector2i(5, 7), Vector2i(3, 6)]
	for p in base:
		obstacles[p] = true
		obstacles[_mirror(p)] = true
	var formation := {
		"tanque": Vector2i(3, 4), "assassino": Vector2i(2, 6), "arqueiro": Vector2i(1, 3),
		"druida": Vector2i(1, 5), "engenheiro": Vector2i(2, 2),
	}
	for player in 2:
		for cls in GameData.ROSTER:
			var pos: Vector2i = formation[cls]
			if player == 1:
				pos = _mirror(pos)
			_add_unit(cls, player, pos)
	initial_snapshot = snapshot()
	_begin_next_turn()


func _mirror(p: Vector2i) -> Vector2i:
	return Vector2i(W - 1 - p.x, H - 1 - p.y)


func snapshot() -> Dictionary:
	return {"units": units.duplicate(true), "obstacles": obstacles.duplicate(), "fog": fog_active()}


## A névoa já desceu?
func fog_active() -> bool:
	return round_no >= GameData.FOG_START_ROUND


## Dano da névoa nesta rodada (cresce a cada rodada para garantir que a partida termine).
func fog_damage() -> int:
	if not fog_active():
		return 0
	return GameData.FOG_BASE_DAMAGE + (round_no - GameData.FOG_START_ROUND) * GameData.FOG_DAMAGE_STEP


func _add_unit(cls: String, player: int, pos: Vector2i, owner_id: int = -1) -> Dictionary:
	var d: Dictionary = GameData.CLASSES[cls]
	var u := {
		"id": _next_id, "cls": cls, "player": player, "pos": pos,
		"hp": d["hp"], "max_hp": d["hp"], "mov": d["mov"], "ini": d["ini"],
		"alive": true, "structure": d.get("estrutura", false), "owner": owner_id,
		"cooldowns": {}, "muralha": false, "enraizado": 0, "mov_turno": d["mov"],
	}
	units[_next_id] = u
	_next_id += 1
	return u


# ---------------------------------------------------------------- consultas

func active() -> Dictionary:
	return units.get(active_id, {})


func unit_at(p: Vector2i) -> Dictionary:
	for u in units.values():
		if u["alive"] and u["pos"] == p:
			return u
	return {}


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < W and p.y < H


func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func alive_characters(player: int) -> Array:
	var out := []
	for u in units.values():
		if u["alive"] and not u["structure"] and u["player"] == player:
			out.append(u)
	return out


func display_name(u: Dictionary) -> String:
	return "%s (J%d)" % [GameData.CLASSES[u["cls"]]["nome"], u["player"] + 1]


func cooldown(u: Dictionary, ab_id: String) -> int:
	return u["cooldowns"].get(ab_id, 0)


## Quadrados alcançáveis neste turno (pos -> distância). Passa por aliados, mas não para neles.
func reachable(u: Dictionary) -> Dictionary:
	var dist := {u["pos"]: 0}
	_parents = {u["pos"]: u["pos"]}
	var limit: int = 0 if moved else u["mov_turno"]
	var queue := [u["pos"]]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if dist[c] >= limit:
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if not in_bounds(n) or obstacles.has(n) or dist.has(n):
				continue
			var o := unit_at(n)
			if not o.is_empty() and (o["player"] != u["player"] or o["structure"]):
				continue
			dist[n] = dist[c] + 1
			_parents[n] = c
			queue.append(n)
	var res := {}
	for p in dist.keys():
		if p == u["pos"] or unit_at(p).is_empty():
			res[p] = dist[p]
	return res


func path_to(u: Dictionary, dest: Vector2i) -> Array:
	reachable(u)
	if not _parents.has(dest):
		return []
	var path := [dest]
	var c: Vector2i = dest
	while c != u["pos"]:
		c = _parents[c]
		path.push_front(c)
	return path


func line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var steps: int = maxi(absi(b.x - a.x), absi(b.y - a.y)) * 3
	for i in range(1, steps):
		var t := float(i) / steps
		var p := Vector2i(roundi(lerpf(a.x, b.x, t)), roundi(lerpf(a.y, b.y, t)))
		if p != a and p != b and obstacles.has(p):
			return false
	return true


func area_tiles(center: Vector2i, radius: int) -> Array:
	var out := []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var p := center + Vector2i(dx, dy)
			if in_bounds(p) and not obstacles.has(p):
				out.append(p)
	return out


func ability_targets(u: Dictionary, ab_id: String) -> Array:
	var ab: Dictionary = GameData.ABILITIES[ab_id]
	var origin: Vector2i = u["pos"]
	if ab["alvo"] == "si":
		return [origin]
	var out := []
	for x in W:
		for y in H:
			var p := Vector2i(x, y)
			var d := manhattan(origin, p)
			if d > ab["alcance"] or obstacles.has(p):
				continue
			if d == 0 and ab["alvo"] != "aliado":
				continue
			if ab.get("visao", false) and not line_of_sight(origin, p):
				continue
			var o := unit_at(p)
			var ok := false
			match ab["alvo"]:
				"inimigo":
					ok = not o.is_empty() and o["player"] != u["player"]
				"aliado":
					ok = not o.is_empty() and o["player"] == u["player"] and not o["structure"]
				"area":
					ok = true
				"vazio":
					ok = o.is_empty()
			if ok:
				out.append(p)
	return out


func can_use(u: Dictionary, ab_id: String) -> bool:
	return winner < 0 and not acted and cooldown(u, ab_id) == 0 and not ability_targets(u, ab_id).is_empty()


func upcoming(n: int) -> Array:
	var out := [active_id]
	for id in turn_queue:
		var c: Dictionary = units.get(id, {})
		if not c.is_empty() and c["alive"]:
			out.append(id)
	return out.slice(0, n)


# ---------------------------------------------------------------- comandos

func move_to(dest: Vector2i) -> Array:
	var start := events.size()
	var u := active()
	if winner >= 0 or moved or u.is_empty():
		return []
	var r := reachable(u)
	if dest == u["pos"] or not r.has(dest):
		return []
	var path := path_to(u, dest)
	u["pos"] = dest
	moved = true
	_log({"t": "move", "unit": u["id"], "path": path})
	_auto_end()
	return events.slice(start)


func use_ability(ab_id: String, target: Vector2i) -> Array:
	var start := events.size()
	var u := active()
	if winner >= 0 or acted or u.is_empty():
		return []
	if not ab_id in GameData.CLASSES[u["cls"]]["habilidades"]:
		return []
	if cooldown(u, ab_id) > 0 or not target in ability_targets(u, ab_id):
		return []
	var ab: Dictionary = GameData.ABILITIES[ab_id]
	var ev := {"t": "ability", "unit": u["id"], "ab": ab_id, "from": u["pos"], "target": target, "hits": []}
	var victims := []
	match ab["alvo"]:
		"inimigo", "aliado":
			victims.append(unit_at(target))
		"si":
			victims.append(u)
		"area":
			for p in area_tiles(target, ab["raio"]):
				var o := unit_at(p)
				if not o.is_empty() and o["player"] != u["player"]:
					victims.append(o)
		"vazio":
			for t in units.values():
				if t["alive"] and t["structure"] and t["owner"] == u["id"]:
					t["alive"] = false
					ev["removed"] = t["id"]
			var tur := _add_unit(ab["invoca"], u["player"], target, u["id"])
			ev["spawn"] = tur.duplicate(true)
	for v in victims:
		ev["hits"].append(_resolve_hit(u, ab, v))
	u["cooldowns"][ab_id] = ab["recarga"]
	acted = true
	_log(ev)
	_check_victory(ev)
	_auto_end()
	return events.slice(start)


func end_turn() -> Array:
	var start := events.size()
	if winner >= 0 or active().is_empty():
		return []
	_finish_turn()
	return events.slice(start)


# ---------------------------------------------------------------- interno

func _resolve_hit(src: Dictionary, ab: Dictionary, v: Dictionary) -> Dictionary:
	var hit := {"unit": v["id"], "dmg": 0, "heal": 0, "crit": false, "killed": false}
	if ab.has("cura"):
		var h: int = mini(ab["cura"], v["max_hp"] - v["hp"])
		v["hp"] += h
		hit["heal"] = h
	if ab.has("dano"):
		var dmg := float(ab["dano"])
		if ab.has("execucao") and float(v["hp"]) / v["max_hp"] < ab["execucao"]:
			dmg *= 2.0
			hit["exec"] = true
		if not ab.get("sem_critico", false) and rng.randf() < GameData.CRIT_CHANCE:
			dmg *= GameData.CRIT_MULT
			hit["crit"] = true
		if v["muralha"]:
			dmg *= 0.5
			hit["blocked"] = true
		var d := int(round(dmg))
		v["hp"] = maxi(0, v["hp"] - d)
		hit["dmg"] = d
		if v["hp"] <= 0:
			v["alive"] = false
			hit["killed"] = true
		else:
			if ab.get("empurra", 0) > 0:
				var vp: Vector2i = v["pos"]
				var sp: Vector2i = src["pos"]
				var n := vp + Vector2i(signi(vp.x - sp.x), signi(vp.y - sp.y))
				if in_bounds(n) and not obstacles.has(n) and unit_at(n).is_empty():
					v["pos"] = n
					hit["push"] = n
			if ab.get("efeito", "") == "enraizar":
				v["enraizado"] = 1
				hit["rooted"] = true
	if ab.get("efeito", "") == "muralha":
		v["muralha"] = true
		hit["shield"] = true
	hit["hp"] = v["hp"]
	return hit


func _turret_fire(t: Dictionary) -> void:
	var best := {}
	var best_d := 999
	for v in units.values():
		if not v["alive"] or v["player"] == t["player"]:
			continue
		var d := manhattan(t["pos"], v["pos"])
		if d <= GameData.TURRET_RANGE and d < best_d and line_of_sight(t["pos"], v["pos"]):
			best = v
			best_d = d
	if best.is_empty():
		return
	var ev := {"t": "turret", "unit": t["id"], "from": t["pos"], "target": best["pos"],
		"hits": [_resolve_hit(t, {"dano": GameData.TURRET_DAMAGE}, best)]}
	_log(ev)
	_check_victory(ev)


func _check_victory(ev: Dictionary) -> void:
	if winner >= 0:
		return
	for p in 2:
		if alive_characters(p).is_empty():
			winner = 1 - p
			ev["final"] = true   # este é o golpe final: o jogo não o encena, a cinemática sim
			_log({"t": "end", "winner": winner})
			return


func _finish_turn() -> void:
	var u := active()
	if u["cls"] == "engenheiro":
		for t in units.values():
			if t["alive"] and t["structure"] and t["owner"] == u["id"]:
				_turret_fire(t)
	if winner < 0:
		_begin_next_turn()


func _auto_end() -> void:
	if winner < 0 and moved and acted:
		_finish_turn()


## Ordem da rodada: cada jogador ordena seus personagens por iniciativa e os
## jogadores se alternam (J1, J2, J1, J2...). Começa quem tem a maior iniciativa;
## no empate, quem começa alterna a cada rodada.
func _start_round() -> void:
	# fim da rodada anterior: torretas cujo engenheiro morreu continuam atirando, uma vez por rodada
	if round_no > 0:
		for t in units.values():
			if t["alive"] and t["structure"] and not units.get(t["owner"], {}).get("alive", false):
				_turret_fire(t)
				if winner >= 0:
					return
	round_no += 1
	if round_no == GameData.FOG_START_ROUND:
		_log({"t": "fog_start", "round": round_no, "dmg": fog_damage()})
	var lists := [[], []]
	for u in units.values():
		if u["alive"] and not u["structure"]:
			lists[u["player"]].append(u)
	for l in lists:
		l.sort_custom(func(a, b): return a["ini"] > b["ini"] or (a["ini"] == b["ini"] and a["id"] < b["id"]))
	var first := 0
	if lists[0].is_empty():
		first = 1
	elif not lists[1].is_empty():
		if lists[1][0]["ini"] > lists[0][0]["ini"]:
			first = 1
		elif lists[1][0]["ini"] == lists[0][0]["ini"]:
			first = (round_no + 1) % 2
	turn_queue.clear()
	var i := 0
	while i < lists[0].size() or i < lists[1].size():
		for k in [first, 1 - first]:
			if i < lists[k].size():
				turn_queue.append(lists[k][i]["id"])
		i += 1


func _begin_next_turn() -> void:
	while winner < 0:
		var u := {}
		while u.is_empty():
			if turn_queue.is_empty():
				_start_round()
				if winner >= 0:
					return
			var id: int = turn_queue.pop_front()
			var c: Dictionary = units.get(id, {})
			if not c.is_empty() and c["alive"]:
				u = c
		_start_turn(u)
		# névoa: dano no início do turno; se o personagem cair, a vez passa para o próximo
		if fog_active():
			var ev := {"t": "fog", "unit": u["id"], "from": u["pos"], "target": u["pos"], "dmg": fog_damage(),
				"hits": [_resolve_hit(u, {"dano": fog_damage(), "sem_critico": true}, u)]}
			_log(ev)
			_check_victory(ev)
			if not u["alive"]:
				continue
		return


func _start_turn(u: Dictionary) -> void:
	active_id = u["id"]
	turn_no += 1
	acted = false
	u["muralha"] = false
	for k in u["cooldowns"].keys():
		u["cooldowns"][k] = maxi(0, u["cooldowns"][k] - 1)
	u["mov_turno"] = u["mov"]
	if u["enraizado"] > 0:
		u["mov_turno"] = 0
		u["enraizado"] -= 1
	moved = u["mov_turno"] == 0
	_log({"t": "turn", "unit": u["id"], "turn": turn_no, "round": round_no, "rooted": moved})


func _log(ev: Dictionary) -> void:
	events.append(ev)
