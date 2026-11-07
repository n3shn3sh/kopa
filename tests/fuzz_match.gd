extends SceneTree
## Teste de estresse da lógica da partida (MatchState), sem nada visual.
## Joga muitas partidas com comandos aleatórios (válidos e inválidos) e confere invariantes
## a cada comando. Também confere determinismo: os mesmos comandos com a mesma semente
## precisam gerar exatamente o mesmo registro (base para PvP online e para a cinemática).
##
## Uso: godot --headless --path . --script res://tests/fuzz_match.gd -- [partidas] [semente]

var failures := 0
var checks := 0
var _seen_events := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var matches := int(args[0]) if args.size() > 0 else 300
	var base_seed := int(args[1]) if args.size() > 1 else 1
	var stalemates := 0
	var total_cmds := 0
	var total_turns := 0
	for m in matches:
		var res := _play(base_seed + m)
		total_cmds += res["cmds"]
		total_turns += res["turns"]
		if not res["ended"]:
			stalemates += 1
		if (m + 1) % 10 == 0:
			print("  ... %d partidas" % (m + 1))
		if failures > 0:
			break
	print("FUZZ partidas=%d comandos=%d turnos=%d checagens=%d sem_fim=%d falhas=%d" % [
		matches, total_cmds, total_turns, checks, stalemates, failures])
	print("FUZZ_OK" if failures == 0 else "FUZZ_FALHA")
	quit(0 if failures == 0 else 1)


func _fail(msg: String, seed_value: int) -> void:
	failures += 1
	if failures <= 10:
		push_error("FUZZ semente %d: %s" % [seed_value, msg])
		print("FALHA semente %d: %s" % [seed_value, msg])


func _play(seed_value: int) -> Dictionary:
	var s := MatchState.new()
	s.setup(seed_value)
	_seen_events = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919
	var cmds := []
	_check(s, seed_value)
	var n := 0
	while s.winner < 0 and n < 4000:
		n += 1
		var cmd := _random_cmd(s, rng)
		var before := _fingerprint(s)
		var evs := _apply(s, cmd)
		cmds.append(cmd)
		if evs.is_empty() and _fingerprint(s) != before:
			_fail("comando recusado alterou o estado: %s" % str(cmd), seed_value)
		if not evs.is_empty() and cmd["valid"] == false and cmd["kind"] != "end":
			_fail("comando inválido foi aceito: %s" % str(cmd), seed_value)
		_check(s, seed_value)
		if failures > 0:
			break
	# determinismo: refaz os mesmos comandos numa partida nova
	if failures == 0:
		var r := MatchState.new()
		r.setup(seed_value)
		for c in cmds:
			_apply(r, c)
		checks += 1
		if var_to_str(r.events) != var_to_str(s.events):
			_fail("registro não determinístico", seed_value)
	return {"cmds": n, "turns": s.turn_no, "ended": s.winner >= 0}


func _apply(s: MatchState, c: Dictionary) -> Array:
	match c["kind"]:
		"move":
			return s.move_to(c["pos"])
		"ability":
			return s.use_ability(c["ab"], c["pos"])
		"end":
			return s.end_turn()
	return []


## Comando aleatório: na maioria válido, às vezes inválido de propósito.
func _random_cmd(s: MatchState, rng: RandomNumberGenerator) -> Dictionary:
	var u := s.active()
	var roll := rng.randf()
	var any_tile := Vector2i(rng.randi_range(-2, s.W + 1), rng.randi_range(-2, s.H + 1))
	if roll < 0.35:
		var r := s.reachable(u).keys()
		r.erase(u["pos"])
		if not r.is_empty() and not s.moved:
			return {"kind": "move", "pos": r[rng.randi() % r.size()], "valid": true}
	elif roll < 0.72:
		var abs: Array = GameData.CLASSES[u["cls"]]["habilidades"]
		var ab: String = abs[rng.randi() % abs.size()]
		var tg := s.ability_targets(u, ab)
		if s.can_use(u, ab):
			return {"kind": "ability", "ab": ab, "pos": tg[rng.randi() % tg.size()], "valid": true}
	elif roll < 0.85:
		return {"kind": "end", "valid": true}
	# inválidos: quadrado qualquer (fora do tabuleiro, obstáculo, ocupado), habilidade de
	# outra classe, alvo fora do alcance, repetir movimento/ação
	var bad := rng.randi() % 3
	if bad == 0:
		var ok: bool = s.reachable(u).has(any_tile) and any_tile != u["pos"] and not s.moved
		return {"kind": "move", "pos": any_tile, "valid": ok}
	var all_abs := GameData.ABILITIES.keys()
	var ab2: String = all_abs[rng.randi() % all_abs.size()]
	var ok2: bool = ab2 in GameData.CLASSES[u["cls"]]["habilidades"] and s.can_use(u, ab2) \
		and any_tile in s.ability_targets(u, ab2)
	return {"kind": "ability", "ab": ab2, "pos": any_tile, "valid": ok2}


func _fingerprint(s: MatchState) -> String:
	return var_to_str([s.units, s.turn_queue, s.active_id, s.moved, s.acted, s.winner, s.events.size(), s.turn_no])


func _check(s: MatchState, sd: int) -> void:
	checks += 1
	var occupied := {}
	var alive_chars := [0, 0]
	for u in s.units.values():
		if u["hp"] < 0 or u["hp"] > u["max_hp"]:
			_fail("vida fora do limite: %s" % str(u), sd)
		if u["alive"] and u["hp"] <= 0:
			_fail("vivo com vida 0: %s" % str(u), sd)
		if not u["structure"] and not u["alive"] and u["hp"] > 0:
			_fail("personagem morto com vida: %s" % str(u), sd)
		for k in u["cooldowns"]:
			if u["cooldowns"][k] < 0:
				_fail("recarga negativa: %s" % str(u), sd)
		if not u["alive"]:
			continue
		var p: Vector2i = u["pos"]
		if not s.in_bounds(p) or s.obstacles.has(p):
			_fail("unidade em posição inválida: %s" % str(u), sd)
		if occupied.has(p):
			_fail("duas unidades no mesmo quadrado %s" % str(p), sd)
		occupied[p] = true
		if not u["structure"]:
			alive_chars[u["player"]] += 1
	var someone_out: bool = alive_chars[0] == 0 or alive_chars[1] == 0
	if someone_out != (s.winner >= 0):
		_fail("vencedor inconsistente: vivos=%s winner=%d" % [str(alive_chars), s.winner], sd)
	if s.winner >= 0:
		if alive_chars[s.winner] == 0:
			_fail("vencedor sem personagens vivos", sd)
		var finals := 0
		for ev in s.events:
			if ev.get("final", false):
				finals += 1
		if finals != 1:
			_fail("esperado 1 evento final, veio %d" % finals, sd)
		if s.events[-1]["t"] != "end":
			_fail("último evento não é 'end'", sd)
		return
	var a := s.active()
	if a.is_empty() or not a["alive"] or a["structure"]:
		_fail("personagem ativo inválido: %s" % str(a), sd)
	for id in s.turn_queue:
		if s.units[id]["structure"]:
			_fail("estrutura na fila de turnos", sd)
	# só os eventos novos desde a última checagem (evita custo quadrático)
	for i in range(_seen_events, s.events.size()):
		var ev: Dictionary = s.events[i]
		if ev["t"] == "ability" or ev["t"] == "turret":
			for h in ev["hits"]:
				if h["dmg"] < 0 or h["heal"] < 0:
					_fail("dano/cura negativo no registro", sd)
	_seen_events = s.events.size()
