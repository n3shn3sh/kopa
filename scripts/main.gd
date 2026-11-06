extends Node3D
## Monta a cena e conduz a partida: entrada do jogador, comandos, encenação e golpe final.
## Rodar com `-- --autoplay` faz a IA jogar pelos dois lados (teste automático).

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


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	autoplay = "--autoplay" in args
	if autoplay:
		time_mult = 6.0
	for a in args:
		if a.begins_with("--shots="):
			time_mult = 2.0
			_capture_loop(a.substr(8))
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


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.shadow_enabled = true
	add_child(sun)


# ---------------------------------------------------------------- partida

func new_match() -> void:
	hud.hide_end()
	busy = false
	Engine.time_scale = time_mult
	state = MatchState.new()
	state.setup(randi())
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

## Salva capturas de tela periódicas (para revisão visual em testes automáticos).
func _capture_loop(dir: String) -> void:
	var i := 0
	while true:
		await get_tree().create_timer(1.2, true, false, true).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%03d.png" % [dir, i])
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
