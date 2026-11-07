class_name EventPlayer
extends Node
## Encena eventos do registro da partida. Usado tanto no jogo normal quanto na cinemática:
## a cinemática só muda a velocidade, tira as pausas e usa outra câmera.

signal focus(points: Array)
signal event_started(ev: Dictionary)
signal impact(ev: Dictionary)

var views: Dictionary = {}
var fx_root: Node3D
var spawn_view: Callable
var speed := 1.0
var settle := 0.25


func play(ev: Dictionary) -> void:
	event_started.emit(ev)
	match ev["t"]:
		"turn":
			var v: UnitView = views.get(ev["unit"])
			if v:
				v.set_shield(false)
		"move":
			await _move(ev)
		"ability":
			await _ability(ev)
		"turret":
			await _turret(ev)


## Duração estimada de um evento na velocidade atual, em segundos de jogo (usada pela
## cinemática para planejar os planos). impact: quando o golpe acerta; total: fim do evento;
## flight: tempo de voo do projétil (0 se não houver).
func estimate(ev: Dictionary, cls: String = "") -> Dictionary:
	var cast_t := (0.30 if cls == "arqueiro" else 0.34) / speed
	var rest := settle / speed
	match ev["t"]:
		"move":
			var t := maxf(0.0, ev["path"].size() - 1) * 0.17 / speed
			return {"impact": t, "total": t, "flight": 0.0}
		"ability":
			var ab: Dictionary = GameData.ABILITIES[ev["ab"]]
			match ab["anim"]:
				"melee":
					return {"impact": 0.28 / speed, "total": 0.5 / speed + rest, "flight": 0.0}
				"si", "invocar":
					return {"impact": cast_t, "total": cast_t + rest, "flight": 0.0}
				"projetil", "arco":
					var fly := _flight_time(Arena.to_world(ev["from"]), Arena.to_world(ev["target"]), ab["anim"] == "arco")
					return {"impact": cast_t + fly, "total": cast_t + fly + rest, "flight": fly}
		"turret":
			var fly := _flight_time(Arena.to_world(ev["from"]), Arena.to_world(ev["target"]), false)
			return {"impact": fly, "total": fly + rest, "flight": fly}
	return {"impact": 0.0, "total": 0.0, "flight": 0.0}


func _flight_time(a: Vector3, b: Vector3, arc: bool) -> float:
	var length := (a + Vector3(0, 1.1, 0)).distance_to(b + Vector3(0, 0.9, 0))
	return clampf(length / 22.0, 0.18, 0.6) * (1.6 if arc else 1.0) / speed


func _move(ev: Dictionary) -> void:
	var v: UnitView = views.get(ev["unit"])
	var path: Array = ev["path"]
	if v == null or path.size() < 2:
		return
	var pts := []
	for p in path.slice(1):
		pts.append(Arena.to_world(p))
	focus.emit([v.position, pts[-1]])
	await v.move_path(pts, 0.17 / speed)


func _ability(ev: Dictionary) -> void:
	var v: UnitView = views.get(ev["unit"])
	if v == null:
		return
	var ab: Dictionary = GameData.ABILITIES[ev["ab"]]
	var tw := Arena.to_world(ev["target"])
	var home := v.position
	focus.emit([home, tw])
	match ab["anim"]:
		"melee":
			await v.lunge_in(tw, speed)
			impact.emit(ev)
			_apply_hits(ev)
			await v.return_to(home, speed)
		"si":
			await v.cast(speed)
			impact.emit(ev)
			_apply_hits(ev)
		"invocar":
			v.face(tw)
			await v.cast(speed)
			if ev.has("removed"):
				var old: UnitView = views.get(ev["removed"])
				if old:
					old.die(speed)
			var nv: UnitView = spawn_view.call(ev["spawn"])
			nv.pop_in(speed)
			impact.emit(ev)
			_burst(tw + Vector3(0, 0.5, 0), GameData.TEAM_COLORS[v.player], 18)
		"projetil", "arco":
			v.face(tw)
			await v.cast(speed)
			var arc: bool = ab["anim"] == "arco"
			await _projectile(home + Vector3(0, 1.1, 0), tw + Vector3(0, 0.9, 0), ab.get("cor", Color.WHITE), arc)
			impact.emit(ev)
			if arc:
				_explosion(tw, ab.get("cor", Color.WHITE))
			_apply_hits(ev)
	if settle > 0.0:
		await _wait(settle / speed)


func _turret(ev: Dictionary) -> void:
	var v: UnitView = views.get(ev["unit"])
	if v == null:
		return
	var tw := Arena.to_world(ev["target"])
	focus.emit([v.position, tw])
	v.face(tw)
	await _projectile(v.position + Vector3(0, 1.0, 0), tw + Vector3(0, 0.9, 0), GameData.TEAM_COLORS[v.player], false)
	impact.emit(ev)
	_apply_hits(ev)
	if settle > 0.0:
		await _wait(settle / speed)


func _apply_hits(ev: Dictionary) -> void:
	for h in ev["hits"]:
		var hv: UnitView = views.get(h["unit"])
		if hv == null:
			continue
		var pos := hv.position
		if h["dmg"] > 0:
			hv.hit_flash()
			var crit: bool = h.get("crit", false)
			_float_text(pos, ("CRÍTICO -%d" if crit else "-%d") % h["dmg"], Color(1.0, 0.45, 0.4), crit)
			_burst(pos + Vector3(0, 1.0, 0), Color(1.0, 0.5, 0.4), 22 if crit else 12)
		if h["heal"] > 0:
			_float_text(pos, "+%d" % h["heal"], Color(0.5, 1.0, 0.55), false)
			_burst(pos + Vector3(0, 1.0, 0), Color(0.5, 1.0, 0.55), 12)
		if h.get("blocked", false):
			_float_text(pos + Vector3(0, 0.6, 0), "bloqueado", Color(0.6, 0.85, 1.0), false)
		if h.get("rooted", false):
			_float_text(pos + Vector3(0, 0.6, 0), "enraizado", Color(0.5, 0.9, 0.3), false)
		if h.get("shield", false):
			hv.set_shield(true)
		hv.set_hp(h["hp"])
		if h.has("push"):
			var t := hv.create_tween()   # preso ao personagem: morre junto se a cena for refeita
			t.tween_property(hv, "position", Arena.to_world(h["push"]), 0.2 / speed)
		if h["killed"]:
			hv.die(speed)


func _projectile(a: Vector3, b: Vector3, color: Color, arc: bool) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.15
	s.height = 0.3
	m.mesh = s
	m.material_override = _glow(color)
	fx_root.add_child(m)
	m.position = a
	var length := a.distance_to(b)
	var dur := clampf(length / 22.0, 0.18, 0.6) * (1.6 if arc else 1.0) / speed
	var lift := length * 0.35 if arc else 0.0
	var mover := func(k: float) -> void:
		m.position = a.lerp(b, k) + Vector3(0, sin(k * PI) * lift, 0)
	var tw := create_tween()
	tw.tween_method(mover, 0.0, 1.0, dur)
	await tw.finished
	m.queue_free()


func _explosion(p: Vector3, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.1
	ring.mesh = tm
	var mat := _glow(color)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	fx_root.add_child(ring)
	ring.position = p + Vector3(0, 0.1, 0)
	ring.scale = Vector3(0.2, 0.2, 0.2)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(3.0, 0.4, 3.0), 0.35 / speed)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.35 / speed)
	tw.tween_callback(ring.queue_free)
	_burst(p + Vector3(0, 0.4, 0), color, 30)


func _float_text(p: Vector3, text: String, color: Color, big: bool) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 80 if big else 56
	l.outline_size = 14
	l.pixel_size = 0.01
	l.modulate = color
	fx_root.add_child(l)
	l.position = p + Vector3(0, 2.9, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y + 1.3, 0.9 / speed)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9 / speed).set_delay(0.35 / speed)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.9 / speed).set_delay(0.35 / speed)
	tw.tween_callback(l.queue_free)


func _burst(p: Vector3, color: Color, n: int) -> void:
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.amount = n
	ps.lifetime = 0.6
	ps.explosiveness = 1.0
	ps.direction = Vector3.UP
	ps.spread = 180.0
	ps.initial_velocity_min = 2.5
	ps.initial_velocity_max = 6.0
	ps.gravity = Vector3(0, -9.0, 0)
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.12
	ps.mesh = s
	ps.material_override = _glow(color)
	fx_root.add_child(ps)
	ps.position = p
	ps.emitting = true
	var tw := ps.create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(ps.queue_free)


func _glow(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout
