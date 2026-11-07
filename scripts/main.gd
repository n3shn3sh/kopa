extends Node3D
## Monta a cena e conduz a partida: entrada do jogador, comandos, encenação e golpe final.
## Rodar com `-- --autoplay` faz a IA jogar pelos dois lados (teste automático).
## `-- --cine-test[=<pasta>]` testa só a cinemática (ver README).

var state: MatchState
var arena: Arena
var rig: CameraRig
var hud: GameHUD
var player: EventPlayer
var cine: CinematicDirector
var units_root: Node3D
var fx_root: Node3D
var views: Dictionary = {}
var busy := false
var mode := "move"
var hover := Vector2i(-99, -99)
var autoplay := false
var time_mult := 1.0
var _showcase_dir := ""
var _cine_test := false
var _cine_dir := ""
var _cine_final := false
var _cine_video := false
var _seed := -1
var _capturing := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autoplay = "--autoplay" in args
	if autoplay:
		time_mult = 6.0
	for a in args:
		if a.begins_with("--showcase="):
			_showcase_dir = a.substr(11)
		if a.begins_with("--shots="):
			time_mult = 2.0
			_capture_loop(a.substr(8))
		if a == "--cine-video":
			_cine_test = true
			_cine_video = true
		if a == "--cine-test" or a.begins_with("--cine-test="):
			_cine_test = true
			_cine_dir = a.substr(12)
		if a == "--cine-final":
			_cine_final = true
		if a.begins_with("--seed="):
			_seed = a.substr(7).to_int()
	_build_environment()
	arena = Arena.new()
	add_child(arena)
	units_root = Node3D.new()
	add_child(units_root)
	fx_root = Node3D.new()
	add_child(fx_root)
	rig = CameraRig.new()
	add_child(rig)
	player = EventPlayer.new()
	player.views = views
	player.fx_root = fx_root
	player.spawn_view = spawn_view
	add_child(player)
	cine = CinematicDirector.new()
	cine.main = self
	cine.time_mult = time_mult
	add_child(cine)
	hud = GameHUD.new()
	add_child(hud)
	hud.move_pressed.connect(_select_move)
	hud.ability_pressed.connect(_select_ability)
	hud.end_pressed.connect(_end_turn)
	hud.replay_pressed.connect(_replay)
	hud.new_match_pressed.connect(new_match)
	hud.skip_pressed.connect(cine.skip)
	new_match()
	if _showcase_dir != "":
		_showcase()
	elif _cine_test:
		_run_cine_test()


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.55, 0.9)
	sky_mat.sky_horizon_color = Color(0.72, 0.82, 0.94)
	sky_mat.ground_horizon_color = Color(0.8, 0.86, 0.95)
	sky_mat.ground_bottom_color = Color(0.25, 0.4, 0.5)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.85, 0.95)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.3
	env.ssao_enabled = true
	env.ssao_intensity = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


# ---------------------------------------------------------------- partida

func new_match() -> void:
	hud.hide_end()
	busy = false
	Engine.time_scale = time_mult
	state = MatchState.new()
	state.setup(randi() if _seed < 0 else _seed)
	arena.build(state)
	rebuild_views(state.snapshot())
	rig.enabled = true
	rig.cam.current = true
	rig.snap_to(arena.center())
	hud.set_gameplay_visible(true)
	hud.add_log("Nova partida. Cada jogador ordena seus personagens por iniciativa e os jogadores se alternam.")
	_turn_started()


func rebuild_views(snap: Dictionary) -> void:
	for c in units_root.get_children():
		c.queue_free()
	for c in fx_root.get_children():
		c.queue_free()
	views.clear()
	for u in snap["units"].values():
		if u["alive"]:
			spawn_view(u)


func spawn_view(u: Dictionary) -> UnitView:
	var v := UnitView.new()
	units_root.add_child(v)
	v.setup(u)
	v.position = Arena.to_world(u["pos"])
	v.label.visible = not cine.running   # sem nomes flutuantes na cinemática
	views[u["id"]] = v
	return v


func _turn_started() -> void:
	var u := state.active()
	mode = "" if state.moved else "move"
	hud.add_log("Vez de %s." % state.display_name(u))
	rig.focus(Arena.to_world(u["pos"]))
	_refresh()
	if autoplay:
		_ai_turn()


func _refresh() -> void:
	hud.update(state, mode)
	_update_marks()


func _command(evs: Array) -> void:
	if evs.is_empty():
		return
	busy = true
	arena.clear_marks()
	for ev in evs:
		if ev.get("final", false):
			await _final_blow()
			return
	var new_turn := false
	for ev in evs:
		if ev["t"] == "turn":
			new_turn = true
		await player.play(ev)
		var line := describe(ev)
		if line != "":
			hud.add_log(line)
	busy = false
	if new_turn:
		_turn_started()
	else:
		if mode.begins_with("ab:") and state.acted:
			mode = "" if state.moved else "move"
		elif mode == "move" and state.moved:
			mode = ""
		_refresh()


## O golpe que encerra a partida não é encenado aqui: vira a cinemática da partida inteira.
func _final_blow() -> void:
	hud.set_gameplay_visible(false)
	hud.final_flash(true)
	await get_tree().create_timer(1.4 / time_mult, true, false, true).timeout
	hud.final_flash(false)
	await cine.play(state)
	_show_end()


func _replay() -> void:
	if cine.running:
		return
	hud.hide_end()
	await cine.play(state)
	_show_end()


func _show_end() -> void:
	busy = true
	var w := state.winner
	var dmg := [0, 0]
	var heal := [0, 0]
	var kills := [0, 0]
	for ev in state.events:
		if ev["t"] == "ability" or ev["t"] == "turret":
			var p: int = state.units[ev["unit"]]["player"]
			for h in ev["hits"]:
				dmg[p] += h["dmg"]
				heal[p] += h["heal"]
				if h["killed"]:
					kills[p] += 1
	var sub := "%d turnos em %d rodadas\nDano causado: J1 %d · J2 %d\nCura: J1 %d · J2 %d\nAbates: J1 %d · J2 %d" % [
		state.turn_no, state.round_no, dmg[0], dmg[1], heal[0], heal[1], kills[0], kills[1]]
	hud.show_end("%s vence" % GameData.TEAM_NAMES[w], sub, GameData.TEAM_COLORS[w])
	if autoplay:
		print("AUTOPLAY_OK vencedor=J%d turnos=%d eventos=%d" % [w + 1, state.turn_no, state.events.size()])
		print(sub)
		get_tree().quit()


func describe(ev: Dictionary) -> String:
	match ev["t"]:
		"move":
			return "%s se move." % state.display_name(state.units[ev["unit"]])
		"ability", "turret":
			var who := state.display_name(state.units[ev["unit"]])
			var nm: String = "dispara" if ev["t"] == "turret" else "usa " + GameData.ABILITIES[ev["ab"]]["nome"]
			var parts := []
			for h in ev["hits"]:
				var tn := state.display_name(state.units[h["unit"]])
				if h["dmg"] > 0:
					parts.append("%s -%d%s%s" % [tn, h["dmg"], " (crítico)" if h["crit"] else "", " (abatido)" if h["killed"] else ""])
				if h["heal"] > 0:
					parts.append("%s +%d" % [tn, h["heal"]])
			if parts.is_empty():
				return "%s %s." % [who, nm]
			return "%s %s: %s." % [who, nm, ", ".join(PackedStringArray(parts))]
	return ""


# ---------------------------------------------------------------- entrada

func _unhandled_input(e: InputEvent) -> void:
	if busy or autoplay or state == null or state.winner >= 0:
		return
	var mm := e as InputEventMouseMotion
	if mm:
		var t := _pick(mm.position)
		if t != hover:
			hover = t
			_update_marks()
		return
	var mb := e as InputEventMouseButton
	if mb and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_click(_pick(mb.position))
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
		return
	var k := e as InputEventKey
	if k and k.pressed and not k.echo:
		match k.keycode:
			KEY_1:
				_select_ability(0)
			KEY_2:
				_select_ability(1)
			KEY_M:
				_select_move()
			KEY_SPACE, KEY_ENTER:
				_end_turn()
			KEY_ESCAPE:
				_cancel()
			KEY_F:
				rig.focus(Arena.to_world(state.active()["pos"]))


func _pick(screen: Vector2) -> Vector2i:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2i(-99, -99)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen), cam.project_ray_normal(screen))
	if hit == null:
		return Vector2i(-99, -99)
	return arena.to_tile(hit)


func _click(p: Vector2i) -> void:
	if not state.in_bounds(p):
		return
	var u := state.active()
	if mode == "move":
		if p != u["pos"] and state.reachable(u).has(p):
			await _command(state.move_to(p))
	elif mode.begins_with("ab:"):
		var ab_id := mode.substr(3)
		if p in state.ability_targets(u, ab_id):
			await _command(state.use_ability(ab_id, p))


func _select_move() -> void:
	if busy or state.moved:
		return
	mode = "move"
	_refresh()


func _select_ability(i: int) -> void:
	if busy:
		return
	var u := state.active()
	var ab_id: String = GameData.CLASSES[u["cls"]]["habilidades"][i]
	if state.can_use(u, ab_id):
		mode = "ab:" + ab_id
		_refresh()


func _cancel() -> void:
	mode = "" if state.moved else "move"
	_refresh()


func _end_turn() -> void:
	if busy or state.winner >= 0:
		return
	await _command(state.end_turn())


func _update_marks() -> void:
	var m := {}
	if state.winner < 0 and not busy:
		var u := state.active()
		if mode == "move":
			var r := state.reachable(u)
			for p in r:
				m[p] = "move"
			if r.has(hover) and hover != u["pos"]:
				for p in state.path_to(u, hover):
					m[p] = "path"
		elif mode.begins_with("ab:"):
			var ab_id := mode.substr(3)
			var ab: Dictionary = GameData.ABILITIES[ab_id]
			var tg := state.ability_targets(u, ab_id)
			for p in tg:
				m[p] = "target"
			if hover in tg:
				if ab["alvo"] == "area":
					for p in state.area_tiles(hover, ab["raio"]):
						m[p] = "area"
				else:
					m[hover] = "area"
		m[u["pos"]] = "active"
	arena.show_marks(m)


# ---------------------------------------------------------------- teste automático

## Gera imagens de vitrine (personagens e cenário) e fecha. Uso: -- --showcase=<pasta>
func _showcase() -> void:
	busy = true
	hud.set_gameplay_visible(false)
	await get_tree().create_timer(0.5).timeout
	rig.enabled = false
	var cam := rig.cam
	# 1) fileira de personagens, de perto
	rebuild_views({"units": {}})
	var c := arena.center() + Vector3(0, -0.27, 13.0)
	var i := 0
	for player in 2:
		for cls in GameData.ROSTER + ["torreta"]:
			var u := {"id": 1000 + i, "cls": cls, "player": player, "pos": Vector2i.ZERO, "hp": 100, "max_hp": 100,
				"structure": cls == "torreta", "muralha": false}
			var v := spawn_view(u)
			v.label.visible = false
			v.position = c + Vector3((i % 6 - 2.5) * 1.6, 0, (player - 0.5) * 3.0)
			v.rotation.y = 0.0
			i += 1
	cam.position = c + Vector3(0, 2.6, 9.5)
	cam.look_at(c + Vector3(0, 0.8, 0))
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(_showcase_dir + "/vitrine_personagens.png")
	cam.position = c + Vector3(-2.2, 1.6, 4.4)
	cam.look_at(c + Vector3(-2.2, 0.9, 1.5))
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(_showcase_dir + "/vitrine_close.png")
	# 2) visão de jogo
	rebuild_views(state.snapshot())
	rig.enabled = true
	rig.snap_to(arena.center())
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(_showcase_dir + "/vitrine_jogo.png")
	# 3) panorâmica do cenário
	rig.enabled = false
	cam.position = arena.center() + Vector3(-30, 16, 34)
	cam.look_at(arena.center() + Vector3(0, -2, 0))
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(_showcase_dir + "/vitrine_cenario.png")
	get_tree().quit()


## Salva capturas de tela periódicas (para revisão visual em testes automáticos).
func _capture_loop(dir: String) -> void:
	var i := 0
	while true:
		await get_tree().create_timer(1.2, true, false, true).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%03d.png" % [dir, i])
		i += 1


## Teste da cinemática: simula a partida inteira só na lógica (MatchState + TacticalAI, sem
## animação), toca a cinemática em velocidade normal (com capturas densas se houver pasta) e
## depois testa "Rever" com "Pular" no meio, na câmera lenta, no congelamento e logo no início.
## Uso: -- --cine-test[=<pasta>] [--seed=N] [--cine-final (acelera tudo menos o trecho final)]
func _run_cine_test() -> void:
	busy = true
	hud.set_gameplay_visible(false)
	var guard := 0
	while state.winner < 0 and guard < 2000:
		guard += 1
		var turn := state.turn_no
		var plan := TacticalAI.decide(state)
		if plan["move"] != state.active()["pos"]:
			state.move_to(plan["move"])
		if state.winner < 0 and state.turn_no == turn and plan["ab"] != "":
			state.use_ability(plan["ab"], plan["target"])
		if state.winner < 0 and state.turn_no == turn:
			state.end_turn()
	if state.winner < 0:
		print("CINE_TEST_FALHA partida não terminou")
		get_tree().quit(1)
		return
	print("CINE_TEST partida: turnos=%d eventos=%d" % [state.turn_no, state.events.size()])
	cine.verbose = true
	if _cine_final:
		cine.preview_from = maxi(0, state.events.size() - 14)   # só o trecho final em velocidade normal
	var t0 := Time.get_ticks_msec()
	if _cine_dir != "":
		_capturing = true
		_dense_capture(_cine_dir, 0.4)
	await _final_blow()
	_capturing = false
	print("CINE_TEST exibição completa: %.1f s, %d cortes" % [(Time.get_ticks_msec() - t0) / 1000.0, cine.cuts])
	if _cine_video:
		# gravação de vídeo (Movie Maker): mostra a tela de vitória um instante e fecha
		await get_tree().create_timer(2.5, true, false, true).timeout
		get_tree().quit()
		return
	cine.verbose = false
	# rever e pular no meio da montagem
	_replay()
	await get_tree().create_timer(3.0, true, false, true).timeout
	cine.skip()
	while cine.running:
		await get_tree().process_frame
	# rever e pular no começo da câmera lenta do golpe final
	_replay()
	while cine.running and cine.phase != "final":
		await get_tree().process_frame
	cine.skip()
	while cine.running:
		await get_tree().process_frame
	# rever e pular durante o congelamento do golpe final
	_replay()
	while cine.running and cine.phase != "congelado":
		await get_tree().process_frame
	cine.skip()
	while cine.running:
		await get_tree().process_frame
	# rever e pular logo de cara
	_replay()
	cine.skip()
	while cine.running:
		await get_tree().process_frame
	# rever inteira de novo, acelerada, até o fim
	cine.time_mult = 4.0
	_replay()
	while cine.running:
		await get_tree().process_frame
	cine.time_mult = time_mult
	print("CINE_TEST_OK vencedor=J%d" % [state.winner + 1])
	get_tree().quit()


func _dense_capture(dir: String, every: float) -> void:
	var i := 0
	while _capturing:
		await get_tree().create_timer(every, true, false, true).timeout
		if not _capturing:
			break
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png("%s/c%04d_%s.png" % [dir, i, cine.phase if cine.phase != "" else "fim"])
		i += 1


func _ai_turn() -> void:
	var my_turn := state.turn_no
	if my_turn > 600:
		print("AUTOPLAY_FALHA partida longa demais")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.3).timeout
	if state.winner >= 0 or state.turn_no != my_turn:
		return
	var plan := TacticalAI.decide(state)
	if plan["move"] != state.active()["pos"]:
		await _command(state.move_to(plan["move"]))
		if state.winner >= 0 or state.turn_no != my_turn:
			return
	if plan["ab"] != "":
		await _command(state.use_ability(plan["ab"], plan["target"]))
		if state.winner >= 0 or state.turn_no != my_turn:
			return
	await _command(state.end_turn())
