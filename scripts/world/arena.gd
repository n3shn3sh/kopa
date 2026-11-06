class_name Arena
extends Node3D
## Monta o tabuleiro 3D (quadrados, obstáculos) e as marcações de seleção.

const T := GameData.TILE

var marks: Dictionary = {}       # Vector2i -> MeshInstance3D
var mark_mats: Dictionary = {}


static func to_world(p: Vector2i) -> Vector3:
	return Vector3(p.x * T, 0.0, p.y * T)


func to_tile(w: Vector3) -> Vector2i:
	return Vector2i(roundi(w.x / T), roundi(w.z / T))


func center() -> Vector3:
	return Vector3((GameData.GRID_W - 1) * T * 0.5, 0.0, (GameData.GRID_H - 1) * T * 0.5)


func build(state: MatchState) -> void:
	for c in get_children():
		c.queue_free()
	marks.clear()
	_make_mark_mats()

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, 140)
	ground.mesh = pm
	ground.material_override = _mat(Color(0.06, 0.07, 0.09))
	ground.position = center() + Vector3(0, -0.3, 0)
	add_child(ground)

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(T * 0.96, 0.3, T * 0.96)
	var mat_a := _mat(Color(0.23, 0.26, 0.24))
	var mat_b := _mat(Color(0.19, 0.22, 0.2))
	var mark_mesh := PlaneMesh.new()
	mark_mesh.size = Vector2(T * 0.9, T * 0.9)
	for x in GameData.GRID_W:
		for y in GameData.GRID_H:
			var p := Vector2i(x, y)
			var mi := MeshInstance3D.new()
			mi.mesh = tile_mesh
			mi.material_override = mat_a if (x + y) % 2 == 0 else mat_b
			mi.position = to_world(p) + Vector3(0, -0.15, 0)
			add_child(mi)
			var mk := MeshInstance3D.new()
			mk.mesh = mark_mesh
			mk.position = to_world(p) + Vector3(0, 0.02, 0)
			mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mk.visible = false
			add_child(mk)
			marks[p] = mk

	var rock := _mat(Color(0.34, 0.32, 0.38))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for p in state.obstacles.keys():
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var h := rng.randf_range(1.2, 2.4)
		bm.size = Vector3(T * 0.86, h, T * 0.86)
		mi.mesh = bm
		mi.material_override = rock
		mi.position = to_world(p) + Vector3(0, h * 0.5, 0)
		mi.rotation.y = rng.randf_range(-0.15, 0.15)
		add_child(mi)

	# faixas de base de cada time
	for player in 2:
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.25, 0.1, GameData.GRID_H * T)
		strip.mesh = sm
		var m := _mat(GameData.TEAM_COLORS[player])
		m.emission_enabled = true
		m.emission = GameData.TEAM_COLORS[player]
		strip.material_override = m
		var x := -T * 0.6 if player == 0 else (GameData.GRID_W - 1) * T + T * 0.6
		strip.position = Vector3(x, 0.0, center().z)
		add_child(strip)


func show_marks(m: Dictionary) -> void:
	for p in marks:
		marks[p].visible = false
	for p in m:
		if marks.has(p):
			marks[p].visible = true
			marks[p].material_override = mark_mats[m[p]]


func clear_marks() -> void:
	show_marks({})


func _make_mark_mats() -> void:
	var defs := {
		"move": Color(0.3, 0.65, 1.0, 0.35), "path": Color(0.85, 0.95, 1.0, 0.65),
		"target": Color(1.0, 0.3, 0.3, 0.35), "area": Color(1.0, 0.6, 0.2, 0.65),
		"active": Color(1.0, 0.85, 0.3, 0.6),
	}
	for k in defs:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = defs[k]
		mark_mats[k] = m


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
