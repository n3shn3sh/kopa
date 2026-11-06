class_name CinematicDirector
extends Node3D
## Cinemática do golpe final.
## Recria o tabuleiro no estado inicial e encena TODO o registro da partida, do primeiro turno
## até o golpe final, sem pausas entre turnos. A câmera de cinema acompanha a ação sem cortes.
## Só o último golpe entra em câmera lenta, congela no impacto (com a câmera girando) e retoma.

signal finished

var main: Node          # main.gd: views, hud, player, arena
var cam: Camera3D
var points: Array = []
var look := Vector3.ZERO
var orbit := 0.0
var close := false
var running := false
var skipping := false
var time_mult := 1.0
var _bullet_time := false


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 42.0
	add_child(cam)


func play(state: MatchState) -> void:
	running = true
	skipping = false
	close = false
	_bullet_time = false
	main.rebuild_views(state.initial_snapshot)
	main.rig.enabled = false
	main.hud.set_cinematic(true)
	var player: EventPlayer = main.player
	player.speed = 1.8
	player.settle = 0.0
	player.focus.connect(_on_focus)
	player.impact.connect(_on_impact)
	player.event_started.connect(_on_started)

	var c: Vector3 = main.arena.center()
	points = [c]
	look = c
	orbit = -0.7
	cam.position = c + Vector3(-12.0, 10.0, 16.0)
	cam.look_at(c)
	cam.current = true
	_set_scale(1.0)
	await _real_wait(0.6)

	for ev in state.events:
		if skipping:
			break
		if ev["t"] == "end":
			continue
		await player.play(ev)

	if skipping:
		main.rebuild_views(state.snapshot())
	else:
		await _real_wait(1.8)

	player.focus.disconnect(_on_focus)
	player.impact.disconnect(_on_impact)
	player.event_started.disconnect(_on_started)
	player.speed = 1.0
	player.settle = 0.25
	_set_scale(1.0)
	running = false
	main.hud.hide_caption()
	main.hud.set_cinematic(false)
	finished.emit()


func skip() -> void:
	if not running:
		return
	skipping = true
	main.player.speed = 8.0
	_set_scale(1.0)


func _on_focus(pts: Array) -> void:
	points = pts


func _on_started(ev: Dictionary) -> void:
	if ev.get("final", false) and not skipping:
		close = true
		_set_scale(0.3)


func _on_impact(ev: Dictionary) -> void:
	if not ev.get("final", false) or skipping:
		return
	_set_scale(0.02)
	_bullet_time = true
	var who: Dictionary = {}
	for u in main.state.units.values():
		if u["id"] == ev["unit"]:
			who = u
	var nome: String = "Torreta" if ev["t"] == "turret" else GameData.ABILITIES[ev["ab"]]["nome"]
	main.hud.show_caption("GOLPE FINAL", "%s · %s" % [main.state.display_name(who), nome])
	await _real_wait(1.6)
	_bullet_time = false
	if skipping:
		return
	_set_scale(0.35)
	await _real_wait(1.4)
	main.hud.hide_caption()
	_set_scale(1.0)


func _process(delta: float) -> void:
	if not running:
		return
	var real := delta / maxf(Engine.time_scale, 0.0001)
	var target := Vector3.ZERO
	for p in points:
		target += p
	target /= maxf(1.0, points.size())
	var spread := 0.0
	for p in points:
		spread = maxf(spread, p.distance_to(target))
	orbit += real * (0.9 if _bullet_time else 0.12)
	var dist := clampf(7.0 + spread * 1.3, 7.0, 20.0)
	var pitch := deg_to_rad(30.0)
	if close:
		dist = clampf(5.0 + spread * 0.9, 5.0, 12.0)
		pitch = deg_to_rad(18.0)
	var desired := target + Vector3(sin(orbit) * cos(pitch), sin(pitch), cos(orbit) * cos(pitch)) * dist
	var k := 1.0 - exp(-2.5 * real)
	cam.position = cam.position.lerp(desired, k)
	look = look.lerp(target + Vector3(0, 0.9, 0), k)
	cam.look_at(look)


func _set_scale(x: float) -> void:
	Engine.time_scale = x * time_mult


func _real_wait(t: float) -> void:
	await get_tree().create_timer(t / time_mult, true, false, true).timeout
