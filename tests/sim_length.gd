extends SceneTree
## Mede a duração das partidas com a IA jogando pelos dois lados (só lógica, sem visual).
## Imprime média, mediana e percentis de rodadas e turnos, e a rodada em que a névoa desceu.
##
## Uso: godot --headless --path . --script res://tests/sim_length.gd -- [partidas] [semente]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 200
	var base := int(args[1]) if args.size() > 1 else 1
	var rounds := []
	var turns := []
	var unfinished := 0
	var by_fog := 0
	var fog_kills := 0
	var fog_final_seeds := []
	var orphan_seeds := []
	for i in n:
		var s := MatchState.new()
		s.setup(base + i)
		var guard := 0
		while s.winner < 0 and guard < 3000:
			guard += 1
			var t := s.turn_no
			var plan := TacticalAI.decide(s)
			if plan["move"] != s.active()["pos"]:
				s.move_to(plan["move"])
			if s.winner < 0 and s.turn_no == t and plan["ab"] != "":
				s.use_ability(plan["ab"], plan["target"])
			if s.winner < 0 and s.turn_no == t:
				s.end_turn()
		if s.winner < 0:
			unfinished += 1
			continue
		rounds.append(s.round_no)
		for ev in s.events:
			if ev["t"] == "turret" and not s.units[s.units[ev["unit"]]["owner"]]["alive"] and ev.get("final", false):
				orphan_seeds.append(base + i)
		turns.append(s.turn_no)
		for ev in s.events:
			if ev["t"] == "fog":
				for h in ev["hits"]:
					if h["killed"]:
						fog_kills += 1
						if ev.get("final", false):
							by_fog += 1
							fog_final_seeds.append(base + i)
	rounds.sort()
	turns.sort()
	print("SIM partidas=%d terminadas=%d sem_fim=%d" % [n, rounds.size(), unfinished])
	if not rounds.is_empty():
		print("SIM rodadas: média %.1f · mediana %d · p25 %d · p75 %d · p90 %d · máx %d" % [
			_mean(rounds), rounds[rounds.size() / 2], rounds[rounds.size() / 4], rounds[rounds.size() * 3 / 4],
			rounds[rounds.size() * 9 / 10], rounds[-1]])
		print("SIM turnos:  média %.1f · mediana %d · p90 %d · máx %d" % [
			_mean(turns), turns[turns.size() / 2], turns[turns.size() * 9 / 10], turns[-1]])
	print("SIM névoa: começa na rodada %d · abates pela névoa %d · partidas decididas pela névoa %d" % [
		GameData.FOG_START_ROUND, fog_kills, by_fog])
	print("SIM sementes com golpe final da névoa: %s" % str(fog_final_seeds.slice(0, 5)))
	print("SIM sementes com golpe final de torreta sem engenheiro: %s" % str(orphan_seeds.slice(0, 5)))
	quit()


func _mean(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()
