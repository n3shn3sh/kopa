class_name TacticalAI
extends RefCounted
## IA simples: usada no modo de teste automático e como base para um modo contra a máquina.
## Testa cada quadrado alcançável x cada habilidade x cada alvo e escolhe o melhor valor.


static func decide(s: MatchState) -> Dictionary:
	var u := s.active()
	var origin: Vector2i = u["pos"]
	var tiles: Array = s.reachable(u).keys()
	var best := {"score": 0.0, "move": origin, "ab": "", "target": Vector2i.ZERO}
	for tile in tiles:
		u["pos"] = tile
		for ab_id in GameData.CLASSES[u["cls"]]["habilidades"]:
			if s.acted or s.cooldown(u, ab_id) > 0:
				continue
			for tg in s.ability_targets(u, ab_id):
				var sc := _score(s, u, ab_id, tg)
				if sc <= 0.0:
					continue
				sc -= 0.01 * s.manhattan(origin, tile)
				if sc > best["score"]:
					best = {"score": sc, "move": tile, "ab": ab_id, "target": tg}
	u["pos"] = origin
	if best["ab"] == "":
		var goal := _nearest_enemy(s, u)
		var bd := 9999
		for tile in tiles:
			var d := s.manhattan(tile, goal)
			if d < bd:
				bd = d
				best["move"] = tile
	return best


static func _nearest_enemy(s: MatchState, u: Dictionary) -> Vector2i:
	var best: Vector2i = u["pos"]
	var bd := 9999
	for o in s.alive_characters(1 - u["player"]):
		var d := s.manhattan(u["pos"], o["pos"])
		if d < bd:
			bd = d
			best = o["pos"]
	return best


static func _score(s: MatchState, u: Dictionary, ab_id: String, tg: Vector2i) -> float:
	var ab: Dictionary = GameData.ABILITIES[ab_id]
	match ab["alvo"]:
		"inimigo":
			return _damage_value(ab, s.unit_at(tg))
		"area":
			var total := 0.0
			for p in s.area_tiles(tg, ab["raio"]):
				var o := s.unit_at(p)
				if not o.is_empty() and o["player"] != u["player"]:
					total += _damage_value(ab, o)
			return total
		"aliado":
			var v := s.unit_at(tg)
			if float(v["hp"]) / v["max_hp"] > 0.7:
				return 0.0
			return minf(ab["cura"], v["max_hp"] - v["hp"]) * 1.1
		"si":
			var near := 0
			for o in s.alive_characters(1 - u["player"]):
				if s.manhattan(o["pos"], u["pos"]) <= 3:
					near += 1
			return 8.0 * near if u["hp"] < u["max_hp"] * 0.8 else 0.0
		"vazio":
			for t in s.units.values():
				if t["alive"] and t["structure"] and t["owner"] == u["id"]:
					return 0.0
			return 14.0
	return 0.0


static func _damage_value(ab: Dictionary, v: Dictionary) -> float:
	var d := float(ab["dano"])
	if ab.has("execucao") and float(v["hp"]) / v["max_hp"] < ab["execucao"]:
		d *= 2.0
	var val := minf(d, v["hp"])
	if d >= v["hp"]:
		val += 30.0
	if v["structure"]:
		val *= 0.5
	return val
