class_name CinematicDirector
extends Node3D
## Cinemática do golpe final.
## Recria o tabuleiro no estado inicial e encena TODO o registro da partida, do primeiro turno
## até o golpe final, sem pausas nem legendas entre turnos.
## Este nó é o montador: antes de começar, lê o registro inteiro, simula as posições e agrupa
## os turnos em PLANOS (cada plano segura alguns turnos que cabem no mesmo quadro). A
## CinematicCamera calcula o enquadramento de cada plano e faz os movimentos.
## Linguagem: plano geral de abertura -> planos de conjunto estáveis (push-in leve, cortes nas
## trocas de personagem) -> plano de preparação do golpe final -> plano baixo e dramático em
## câmera lenta, congelado no impacto -> plano aberto e estável revelando o vencedor.

signal finished

const SPEED := 1.8            # velocidade da encenação na cinemática
const MIN_HOLD := 1.5         # s: plano mais curto (salvo quando a ação não cabe no quadro)
const MAX_HOLD := 4.5         # s: plano mais longo antes de trocar o ângulo
const SOFT_SIZE := 14.0       # distância de enquadramento até onde vale juntar turnos num plano
const HARD_SIZE := 20.0       # acima disso corta mesmo que o plano esteja curto
const OPENING := 1.5          # s do plano geral de abertura
const SLOWMO := 0.3           # câmera lenta do golpe final
const FREEZE := 0.02          # "congelado" no impacto
const FREEZE_TIME := 1.6
const RESUME := 0.35          # retomada lenta (o alvo cai)
const RESUME_TIME := 1.3
const REVEAL_TIME := 2.6      # s do plano do vencedor antes da tela de vitória
const DEG := PI / 180.0

var main: Node                # main.gd: views, hud, player, arena
var camera: CinematicCamera
var running := false
var skipping := false
var time_mult := 1.0
var phase := ""               # abertura, montagem, final, congelado, retomada, revelacao (para testes)
var cuts := 0                 # cortes na última exibição (para testes)
var verbose := false          # imprime cada plano (teste da cinemática)
var preview_from := -1        # (testes) encena acelerado e sem planos até este evento

var _run := 0                 # identifica a exibição atual (corrotinas antigas se calam)
var _shots := {}              # índice do evento -> plano
var _final := {}              # dados do golpe final
var _opening: Array = []      # sujeitos do plano geral
var _winners: Array = []      # sujeitos da revelação
var _end_units: Array = []    # personagens vivos no fim (oclusão da revelação)
var _impact_seen := false
var _reaction_done := false
var _final_t0 := 0
var _finale_done := false
var _sizes := {}              # classe -> Vector2(raio, altura) medidos no modelo
var _poses := {}              # planos já calculados: índice do evento, "final_<tipo>", "revelacao"


func _ready() -> void:
	camera = CinematicCamera.new()
	add_child(camera)


func play(state: MatchState) -> void:
	if running:
		return
	_run += 1
	var run := _run
	running = true
	skipping = false
	cuts = 0
	phase = "abertura"
	_impact_seen = false
	_finale_done = false
	main.rebuild_views(state.initial_snapshot)
	main.rig.enabled = false
	main.hud.hide_caption()
	main.hud.set_cinematic(true)
	var player: EventPlayer = main.player
	player.speed = SPEED
	player.settle = 0.0
	if not player.impact.is_connected(_on_impact):
		player.impact.connect(_on_impact)

	camera.time_mult = time_mult
	camera.letterbox = GameHUD.LETTERBOX
	camera.set_obstacles(state.obstacles)
	var t0 := Time.get_ticks_usec()
	_plan(state)
	if verbose:
		print("  planejamento: %.1f ms, %d planos" % [(Time.get_ticks_usec() - t0) / 1000.0, _shots.size()])
	_poses = {}
	_prepare(run)
	camera.start()
	_set_scale(1.0)
	_cut(_opening_pose())
	await _hold(OPENING, run)

	phase = "montagem"
	for i in state.events.size():
		if skipping or run != _run:
			break
		var ev: Dictionary = state.events[i]
		if ev["t"] == "end":
			continue
		if ev.get("final", false):
			await _final_blow(ev, run)
			break
		if i < preview_from:
			player.speed = 40.0
		else:
			player.speed = SPEED
			if _shots.has(i):
				_start_shot(_shots[i])
			elif i == preview_from:
				_start_shot(_next_shot(i))
		await player.play(ev)

	if skipping:
		main.rebuild_views(state.snapshot())
		_cut(_reveal_pose(), _winners)
	if player.impact.is_connected(_on_impact):
		player.impact.disconnect(_on_impact)
	player.speed = 1.0
	player.settle = 0.25
	_set_scale(1.0)
	running = false
	skipping = false
	phase = ""
	main.hud.hide_caption()
	main.hud.set_cinematic(false)
	finished.emit()


func skip() -> void:
	if not running or skipping:
		return
	skipping = true
	main.player.speed = 8.0
	_set_scale(1.0)
	main.hud.hide_caption()


# ---------------------------------------------------------------- golpe final

func _final_blow(ev: Dictionary, run: int) -> void:
	var player: EventPlayer = main.player
	phase = "final"
	_final_t0 = Time.get_ticks_msec()
	_reaction_done = false
	_set_scale(SLOWMO)
	if _final["far"]:
		# alvo longe: plano do atirador e, com o projétil a caminho, contraplano do alvo
		_cut(_final_pose("atirador"), [_final["attacker"]])
		_reaction_cut(run)
	else:
		_cut(_final_pose("dois"), _final["subjects"])
	await player.play(ev)
	# o congelamento e a retomada correm em _on_impact; espera terminarem
	while _impact_seen and not _finale_done and not skipping and run == _run:
		await get_tree().process_frame
	if skipping or run != _run:
		return
	_set_scale(1.0)
	main.hud.hide_caption()
	phase = "revelacao"
	var pose := _reveal_pose()
	# afastar e subir até o vencedor (revelação); se for longe demais, corta
	if camera.can_glide(pose, 70.0, 1.6):
		camera.move_to(pose, 0.9)
	else:
		_cut(pose, _winners)
	await _hold(REVEAL_TIME, run)


## Contraplano do alvo pouco antes do impacto (o projétil entra pelo lado de onde veio).
func _reaction_cut(run: int) -> void:
	var lead: float = maxf(0.0, _final["impact"] - _final["flight"] * 0.45) / SLOWMO
	await _real_wait(lead)
	if run != _run or skipping or not running:
		return
	_cut_to_reaction()


func _cut_to_reaction() -> void:
	if _reaction_done:
		return
	_reaction_done = true
	if verbose:
		print("  contraplano em %.2f s" % [(Time.get_ticks_msec() - _final_t0) / 1000.0])
	_cut(_final_pose("alvo"), _final["victims"])


func _on_impact(ev: Dictionary) -> void:
	if not running or skipping or _impact_seen or not ev.get("final", false):
		return
	_impact_seen = true
	var run := _run
	if verbose:
		print("  impacto em %.2f s" % [(Time.get_ticks_msec() - _final_t0) / 1000.0])
	if _final["far"]:
		_cut_to_reaction()   # garante o alvo em quadro no congelamento
	phase = "congelado"
	_set_scale(FREEZE)
	var who: Dictionary = main.state.units.get(ev["unit"], {})
	var quem: String = main.state.display_name(who) if not who.is_empty() else ""
	if ev["t"] == "fog":
		main.hud.show_caption("GOLPE FINAL", "A névoa derruba %s" % quem if quem != "" else "Névoa")
	else:
		var nome: String = "Torreta" if ev["t"] == "turret" else GameData.ABILITIES[ev["ab"]]["nome"]
		main.hud.show_caption("GOLPE FINAL", "%s · %s" % [quem, nome] if quem != "" else nome)
	await _real_wait(FREEZE_TIME)
	if run != _run or skipping or not running:
		return
	phase = "retomada"
	_set_scale(RESUME)
	await _real_wait(RESUME_TIME)
	if run != _run or skipping or not running:
		return
	main.hud.hide_caption()
	_finale_done = true


# ---------------------------------------------------------------- planos

func _cut(pose: Dictionary, subjects: Array = []) -> void:
	cuts += 1
	camera.cut_to(pose)
	if verbose and phase != "montagem":
		_log_shot("corte", pose, subjects)


func _start_shot(shot: Dictionary) -> void:
	var pose := _pose_for(shot.get("start", -1), shot)
	# ação perto da anterior: a câmera acompanha com um movimento curto; senão, corte
	var glide := camera.can_glide(pose)
	if glide:
		camera.move_to(pose, 0.6)
	else:
		_cut(pose)
	if verbose:
		_log_shot("glide" if glide else "corte", pose, shot["subjects"])


func _log_shot(kind: String, pose: Dictionary, subjects: Array) -> void:
	var ids := {}
	for s in subjects:
		ids[s["id"]] = true
	var sb := camera.screen_bounds(subjects) if not subjects.is_empty() else Rect2()
	print("PLANO %s %s yaw=%.0f pitch=%.0f d=%.1f need=%.1f s=(%.2f,%.2f) score=%.1f ids=%s tela=[%.2f..%.2f, %.2f..%.2f]" % [
		phase, kind, rad_to_deg(pose["yaw"]), rad_to_deg(pose["pitch"]), pose["dist"], pose["need"], pose["sx"], pose["sy"],
		pose.get("score", 0.0), ids.keys(), sb.position.x, sb.end.x, sb.position.y, sb.end.y])


## Plano de conjunto da montagem: lateral ao eixo da ação, do lado do público (+Z).
func _montage_opts(shot: Dictionary, prev: Dictionary) -> Dictionary:
	var pref := _axis_yaw(shot["subjects"])
	var yaws := []
	for d in [0.0, -16.0, 16.0, -32.0, 32.0, -48.0, 48.0]:
		yaws.append(clampf(pref + d * DEG, -CinematicCamera.MAX_YAW, CinematicCamera.MAX_YAW))
	return {
		"yaws": yaws, "pitches": [28.0 * DEG, 36.0 * DEG, 46.0 * DEG, 56.0 * DEG],
		"pref_yaw": pref, "pref_pitch": 34.0 * DEG, "fov": 38.0, "box": camera.default_box(),
		"dmin": 8.5, "dmax": 24.0, "prev": prev,
		"occluders": shot["units"], "unit_weight": 0.5, "clutter_weight": 4.0,
		"f0": 1.06, "f1": 1.0, "dur": maxf(1.2, shot["dur"]), "smooth": 0.35,
	}


## Plano geral: o tabuleiro com os dois times, de frente, com push-in lento.
func _opening_pose() -> Dictionary:
	return camera.frame(_opening, {
		"yaws": [0.0], "pitches": [40.0 * DEG, 48.0 * DEG], "pref_pitch": 42.0 * DEG,
		"fov": 38.0, "box": camera.default_box(0.86, 0.8, 0.86), "dmin": 14.0, "dmax": 44.0,
		"occluders": [], "unit_weight": 0.0, "f0": 1.12, "f1": 1.0, "dur": OPENING + 0.4, "smooth": 0.35,
	})


## Golpe final: planos baixos (contra-plongée leve) com lente mais longa, do lado do público
## e perpendiculares ao golpe, para a direção na tela ficar clara (atacante de um lado, alvo
## do outro). kind: "dois" (atacante e alvo perto: plano de dois, cada um num terço),
## "atirador" (alvo longe: o atacante num terço, com espaço para onde mira) ou "alvo"
## (contraplano: o alvo no outro terço, recebendo o golpe). Push-in lento durante a câmera
## lenta e o congelamento; o terço de baixo fica livre para a legenda.
func _final_pose(kind: String) -> Dictionary:
	return _pose_for("final_" + kind)


func _final_args(kind: String) -> Array:
	var base: float = _final["side"]
	var cands := []
	# sem passar de 90° do eixo: a direção do golpe na tela não se inverte entre os planos
	# e nunca além de MAX_YAW: a câmera continua do lado do público (regra dos 180°)
	var seen := {}
	for dy in [0.0, -18.0, 18.0, -36.0, 36.0, -54.0, 54.0, -70.0, 70.0]:
		var yaw := clampf(base + dy * DEG, -CinematicCamera.MAX_YAW, CinematicCamera.MAX_YAW)
		var yk := roundi(yaw / DEG)
		if seen.has(yk):
			continue
		seen[yk] = true
		for p in [[-4.0, 0.0], [5.0, 0.6], [14.0, 2.0], [24.0, 5.0], [34.0, 9.0], [46.0, 14.0]]:
			cands.append(Vector3(yaw, p[0] * DEG, absf(yaw - base) / DEG * 0.06 + p[1]))
	var v_lb := 1.0 - 2.0 * GameHUD.LETTERBOX
	var caption_box := Rect2(-0.62, -0.36, 1.24, 0.36 + v_lb * 0.78)
	var to_right: float = 1.0 if _final["target_right"] else -1.0
	var impact: float = _final["impact"] / SLOWMO
	var lead: float = maxf(0.0, _final["impact"] - _final["flight"] * 0.45) / SLOWMO
	var opts := {
		"candidates": cands, "fov": 32.0, "dmin": 4.5, "dmax": 22.0,
		"pref_yaw": 0.0, "yaw_weight": 1.5, "occluders": _final["occluders"], "unit_weight": 1.0,
		"occlusion_weight": 250.0, "wide_rays": true, "mutual": true, "clutter_weight": 35.0, "smooth": 0.3,
		"arc": (-1.0 if base > 0.0 else 1.0) * 6.0 * DEG,
	}
	var subjects: Array = _final["subjects"]
	match kind:
		"atirador":
			subjects = [_final["attacker"]]
			opts.merge({"box": camera.default_box(0.78, 0.8, 0.86), "center": Vector2(-0.34 * to_right, 0.0),
				"dmin": 4.2, "f0": 1.14, "f1": 1.0, "dur": lead + 0.3, "arc": 0.0}, true)
		"alvo":
			subjects = _final["victims"]
			opts.merge({"box": caption_box, "center": Vector2(0.3 * to_right, 0.14),
				"dmin": 4.2, "f0": 1.1, "f1": 0.94, "dur": maxf(0.3, impact - lead) + FREEZE_TIME}, true)
		_:
			opts.merge({"box": caption_box, "f0": 1.22, "f1": 0.95, "dur": impact + FREEZE_TIME}, true)
	return [subjects, opts]


## Revelação: o time vencedor num plano aberto e estável, com push-in quase imperceptível.
func _reveal_pose() -> Dictionary:
	return _pose_for("revelacao")


func _reveal_args() -> Array:
	var subs := _winners if not _winners.is_empty() else _opening
	var pref := _axis_yaw(subs) * 0.6
	var yaws := []
	for d in [0.0, -15.0, 15.0, -30.0, 30.0]:
		yaws.append(clampf(pref + d * DEG, -CinematicCamera.MAX_YAW, CinematicCamera.MAX_YAW))
	return [subs, {
		"yaws": yaws, "pitches": [14.0 * DEG, 20.0 * DEG, 28.0 * DEG, 38.0 * DEG], "pref_yaw": pref,
		"pref_pitch": 18.0 * DEG, "fov": 36.0, "box": camera.default_box(0.7, 0.78, 0.8), "dmin": 7.5, "dmax": 30.0,
		"occlusion_weight": 120.0, "clutter_weight": 8.0,
		"occluders": _end_units, "unit_weight": 0.8,
		"f0": 1.0, "f1": 0.94, "dur": REVEAL_TIME * 2.0, "smooth": 0.9,
	}]


## Argumentos (sujeitos, opções) do plano de uma chave.
func _args_for(key, shot: Dictionary = {}) -> Array:
	if key is String:
		if key == "revelacao":
			return _reveal_args()
		return _final_args((key as String).substr(6))
	var prev: Dictionary = {}
	var keys := _shots.keys()
	keys.sort()
	var idx := keys.find(key)
	if idx > 0 and _poses.has(keys[idx - 1]):
		prev = _poses[keys[idx - 1]]
	if shot.is_empty():
		shot = _shots.get(key, {})
	return [shot.get("subjects", []), _montage_opts(shot, prev)]


## Plano pronto (calculado antes, em segundo plano) ou calculado agora, se ainda não deu tempo.
func _pose_for(key, shot: Dictionary = {}) -> Dictionary:
	if _poses.has(key):
		return _poses[key]
	var args := _args_for(key, shot)
	var t0 := Time.get_ticks_usec()
	var pose := camera.frame(args[0], args[1])
	if verbose:
		print("  plano %s calculado na hora: %.1f ms" % [str(key), (Time.get_ticks_usec() - t0) / 1000.0])
	if key is String or _shots.has(key):
		_poses[key] = pose
	return pose


## Calcula todos os planos com antecedência, em fatias pequenas por quadro (sem engasgos):
## primeiro os da montagem, na ordem, depois os do golpe final e a revelação.
func _prepare(run: int) -> void:
	var keys: Array = _shots.keys()
	keys.sort()
	var finals := ["final_atirador", "final_alvo"] if _final.get("far", false) else ["final_dois"]
	keys.append_array(finals + ["revelacao"])
	var frame_t0 := Time.get_ticks_usec()
	for k in keys:
		if run != _run or not running:
			return
		if _poses.has(k):
			continue
		var args := _args_for(k)
		var pose: Dictionary = await camera.frame_async(args[0], args[1], 2500)
		if run != _run or not running:
			return
		if not _poses.has(k):
			_poses[k] = pose
		# orçamento por quadro (não por plano): cede o quadro quando passar de 2,5 ms
		if Time.get_ticks_usec() - frame_t0 > 2500:
			await get_tree().process_frame
			frame_t0 = Time.get_ticks_usec()
			if run != _run or not running:
				return


## Yaw que olha de lado para o eixo principal dos sujeitos (sem cruzar para o lado -Z).
func _axis_yaw(subjects: Array) -> float:
	if subjects.size() < 2:
		return 0.0
	var m := Vector2.ZERO
	for s in subjects:
		m += Vector2(s["pos"].x, s["pos"].z)
	m /= subjects.size()
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	for s in subjects:
		var d := Vector2(s["pos"].x, s["pos"].z) - m
		sxx += d.x * d.x
		szz += d.y * d.y
		sxz += d.x * d.y
	var total := sxx + szz
	if total < 1.0:
		return 0.0
	var aniso := sqrt((sxx - szz) * (sxx - szz) + 4.0 * sxz * sxz) / total
	var a := 0.5 * atan2(2.0 * sxz, sxx - szz)
	# perto de ±90° (eixo ao longo de Z) o sinal de `a` vira ruído: o peso cos(a) leva a 0
	# (vista de frente) de forma contínua, sem saltos de 80° entre planos parecidos
	return clampf(-a * clampf(aniso * 1.4, 0.0, 1.0) * cos(a), -40.0 * DEG, 40.0 * DEG)


# ---------------------------------------------------------------- planejamento

## Simula as posições ao longo do registro e monta os planos (grupos de turnos).
func _plan(state: MatchState) -> void:
	_shots.clear()
	_final = {}
	var player: EventPlayer = main.player
	var units := {}
	for u in state.initial_snapshot["units"].values():
		units[u["id"]] = {"id": u["id"], "cls": u["cls"], "player": u["player"], "alive": u["alive"],
			"pos": Arena.to_world(u["pos"])}
	_opening = _alive_subjects(units, -1)
	var beats := []
	var beat := {}
	for i in state.events.size():
		var ev: Dictionary = state.events[i]
		if ev["t"] == "end":
			continue
		if ev.get("final", false):
			_final = _final_data(ev, units, player)
			# o turno do golpe final ganha plano próprio (preparação: quem vai bater e o alvo)
			if not beat.is_empty():
				beat["subjects"].append(_final["victim"])
				if beat["dur"] >= 0.3:
					beat["force"] = true
				else:
					beat["join"] = true   # curto demais para plano próprio: entra no plano anterior
			_simulate(ev, units)
			break
		if ev["t"] == "turn" or beat.is_empty():
			beat = {"start": i, "subjects": [], "dur": 0.0, "units": _alive_subjects(units, -1)}
			beats.append(beat)
		var actor: Dictionary = units.get(ev.get("unit", -1), {})
		_collect(ev, units, beat["subjects"])
		beat["dur"] += player.estimate(ev, actor.get("cls", ""))["total"]
		_simulate(ev, units)
	_winners = _alive_subjects(units, state.winner)
	_end_units = _alive_subjects(units, -1)
	if _final.has("victims"):
		_end_units.append_array(_final["victims"])   # o alvo ainda está caindo na revelação
	if _final.is_empty():
		_final = _fallback_final(units, state.winner)

	# agrupa turnos: segura o plano enquanto a ação couber; corta na troca de personagem
	var shots := []
	var cur := {}
	for b in beats:
		if cur.is_empty():
			cur = _shot_from(b)
			continue
		var merge: bool = b.get("join", false)
		if not merge and not b.get("force", false):
			var size := camera.size_of(cur["subjects"] + b["subjects"])
			if cur["dur"] < MIN_HOLD:
				merge = size <= HARD_SIZE
			else:
				merge = size <= SOFT_SIZE and cur["dur"] + b["dur"] <= MAX_HOLD
		if merge:
			cur["subjects"].append_array(b["subjects"])
			cur["dur"] += b["dur"]
		else:
			shots.append(cur)
			cur = _shot_from(b)
	if not cur.is_empty():
		shots.append(cur)
	for s in shots:
		if not s["subjects"].is_empty():
			_add_neighbors(s)
			_shots[s["start"]] = s


## Plano que cobre o evento i (o último que começa antes dele).
func _next_shot(i: int) -> Dictionary:
	var best := -1
	for k in _shots.keys():
		if k <= i and k > best:
			best = k
	if best < 0:
		return {"subjects": _opening, "dur": 2.0, "units": []}
	return _shots[best]


## Quem está colado na ação entra no quadro inteiro (nada de meio personagem na borda).
func _add_neighbors(shot: Dictionary) -> void:
	var subs: Array = shot["subjects"]
	var core := subs.duplicate()
	var ids := {}
	for sj in subs:
		ids[sj["id"]] = true
	for u in shot["units"]:
		if ids.has(u["id"]):
			continue
		for sj in core:
			if not sj.get("tile", false) and (u["pos"] as Vector3).distance_to(sj["pos"]) < 2.6:
				subs.append(u)
				ids[u["id"]] = true
				break


func _shot_from(b: Dictionary) -> Dictionary:
	return {"start": b["start"], "subjects": b["subjects"].duplicate(), "dur": b["dur"], "units": b["units"]}


## Pontos de interesse de um evento: quem age, por onde passa, o alvo, quem é atingido.
func _collect(ev: Dictionary, units: Dictionary, out: Array) -> void:
	var actor: Dictionary = units.get(ev.get("unit", -1), {})
	match ev["t"]:
		"turn":
			if not actor.is_empty() and actor["alive"]:
				out.append(_subject(actor))
		"move":
			if actor.is_empty():
				return
			for p in ev["path"]:
				out.append(_subject(actor, Arena.to_world(p)))
		"ability", "turret", "fog":
			if not actor.is_empty():
				out.append(_subject(actor, Arena.to_world(ev.get("from", Vector2i.ZERO))))
			var area: bool = ev["t"] == "ability" and GameData.ABILITIES[ev["ab"]]["anim"] == "arco"
			out.append(_tile_subject(Arena.to_world(ev["target"]), 1.6 if area else 0.6))
			for h in ev.get("hits", []):
				var hu: Dictionary = units.get(h["unit"], {})
				if hu.is_empty():
					continue
				out.append(_subject(hu))
				if h.has("push"):
					out.append(_subject(hu, Arena.to_world(h["push"])))
			if ev.has("spawn"):
				var sp: Dictionary = ev["spawn"]
				out.append(_subject({"id": sp["id"], "cls": sp["cls"]}, Arena.to_world(sp["pos"])))


## Aplica o evento ao estado simulado (posições, mortes, torretas).
func _simulate(ev: Dictionary, units: Dictionary) -> void:
	var id: int = ev.get("unit", -1)
	match ev["t"]:
		"move":
			if units.has(id) and not ev["path"].is_empty():
				units[id]["pos"] = Arena.to_world(ev["path"][-1])
		"ability", "turret", "fog":
			for h in ev.get("hits", []):
				if not units.has(h["unit"]):
					continue
				if h.has("push"):
					units[h["unit"]]["pos"] = Arena.to_world(h["push"])
				if h["killed"]:
					units[h["unit"]]["alive"] = false
			if ev.has("removed") and units.has(ev["removed"]):
				units[ev["removed"]]["alive"] = false
			if ev.has("spawn"):
				var sp: Dictionary = ev["spawn"]
				units[sp["id"]] = {"id": sp["id"], "cls": sp["cls"], "player": sp["player"], "alive": true,
					"pos": Arena.to_world(sp["pos"])}


func _final_data(ev: Dictionary, units: Dictionary, player: EventPlayer) -> Dictionary:
	var actor: Dictionary = units.get(ev.get("unit", -1), {})
	var from := Arena.to_world(ev.get("from", Vector2i.ZERO))
	if actor.is_empty():
		actor = {"id": -1, "cls": "torreta", "player": 0}
	var att := _subject(actor, from)
	var target := Arena.to_world(ev["target"])
	var subjects := [att]
	var victim := {}
	var best := INF
	for h in ev.get("hits", []):
		var hu: Dictionary = units.get(h["unit"], {})
		if hu.is_empty() or not (h["killed"] or ev["hits"].size() == 1):
			continue
		var s := _subject(hu)
		subjects.append(s)
		var d: float = (s["pos"] as Vector3).distance_to(target)
		if d < best:
			best = d
			victim = s
	if victim.is_empty():
		victim = _tile_subject(target, 0.6)
		subjects.append(victim)
	var occ := []
	for u in units.values():
		if u["alive"]:
			occ.append(_subject(u))
	var victims := subjects.slice(1)
	# corpo a corpo: no impacto o atacante avança até colado no alvo (UnitView.lunge_in);
	# essa posição também entra no quadro e conta como possível cobertura do alvo
	if ev["t"] == "ability" and GameData.ABILITIES[ev["ab"]]["anim"] == "melee":
		var dir := target - from
		dir.y = 0.0
		if dir.length() > 0.01:
			subjects.append(_subject(actor, target - dir.normalized() * 0.9))
	var est := player.estimate(ev, actor.get("cls", ""))
	var data := {"attacker": att, "victim": victim, "victims": victims, "subjects": subjects,
		"player": actor.get("player", 0), "occluders": occ, "impact": est["impact"], "flight": est["flight"]}
	_final_axis(data)
	return data


## Eixo do golpe: yaw lateral (lado +Z), alvo longe ou perto, de que lado da tela o alvo fica.
func _final_axis(data: Dictionary) -> void:
	var a: Vector3 = data["attacker"]["pos"]
	var b: Vector3 = data["victim"]["pos"]
	var v := Vector2(b.x - a.x, b.z - a.z)
	if v.length() < 0.1:
		v = Vector2(1.0 if data["player"] == 0 else -1.0, 0.0)
	var side := wrapf(-atan2(v.y, v.x), -PI * 0.5, PI * 0.5)
	data["side"] = side
	data["far"] = v.length() > 5.0 and data["flight"] > 0.0
	# direita da câmera nesse yaw: (cos, -sin)
	data["target_right"] = v.dot(Vector2(cos(side), -sin(side))) >= 0.0


## Sem evento final no registro (não deveria acontecer): enquadra o vencedor.
func _fallback_final(units: Dictionary, winner: int) -> Dictionary:
	var subs := _alive_subjects(units, maxi(winner, 0))
	if subs.is_empty():
		subs = [_tile_subject(main.arena.center(), 1.0)]
	var data := {"attacker": subs[0], "victim": subs[-1], "victims": [subs[-1]], "subjects": subs,
		"player": maxi(winner, 0), "occluders": [], "impact": 0.3, "flight": 0.0}
	_final_axis(data)
	return data


func _alive_subjects(units: Dictionary, player: int) -> Array:
	var out := []
	for u in units.values():
		if not u["alive"] or (player >= 0 and (u["player"] != player or u["cls"] == "torreta")):
			continue
		out.append(_subject(u))
	return out


func _subject(u: Dictionary, pos = null) -> Dictionary:
	var size := _class_size(u.get("cls", ""))
	var p: Vector3 = u.get("pos", Vector3.ZERO) if pos == null else pos
	return {"pos": p, "r": size.x, "h": size.y, "id": u.get("id", -1)}


func _tile_subject(p: Vector3, r: float) -> Dictionary:
	return {"pos": p, "r": r, "h": 0.4, "id": -1, "tile": true}


## Raio e altura reais do modelo da classe (medidos uma vez na malha montada).
func _class_size(cls: String) -> Vector2:
	if _sizes.has(cls):
		return _sizes[cls]
	var size := Vector2(0.6, 1.9)
	if GameData.CLASSES.has(cls):
		var m := CharacterBuilder.build(cls, Color.WHITE)
		var box := _measure(m, Transform3D.IDENTITY)
		m.free()
		if box.size != Vector3.ZERO:
			var r := maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
			# margem para braços erguidos e para o anel do time no chão
			size = Vector2(clampf(r, 0.7, 1.2), clampf(box.end.y * 1.08, 0.9, 2.6))
	_sizes[cls] = size
	return size


func _measure(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var empty := true
	for c in n.get_children():
		var c3 := c as Node3D
		if c3 == null:
			continue
		var t := xf * c3.transform
		var mi := c3 as MeshInstance3D
		if mi and mi.mesh:
			var b := t * mi.mesh.get_aabb()
			out = b if empty else out.merge(b)
			empty = false
		var sub := _measure(c3, t)
		if sub.size != Vector3.ZERO:
			out = sub if empty else out.merge(sub)
			empty = false
	return out


# ---------------------------------------------------------------- tempo

func _set_scale(x: float) -> void:
	Engine.time_scale = x * time_mult


func _real_wait(t: float) -> void:
	await get_tree().create_timer(t / time_mult, true, false, true).timeout


## Espera em tempo real, mas sai na hora se a cinemática for pulada ou recomeçada.
func _hold(t: float, run: int) -> void:
	var end := Time.get_ticks_msec() + int(t / time_mult * 1000.0)
	while Time.get_ticks_msec() < end and not skipping and run == _run:
		await get_tree().process_frame
