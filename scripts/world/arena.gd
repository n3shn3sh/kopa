class_name Arena
extends Node3D
## Monta o tabuleiro 3D (quadrados de grama, obstáculos), o cenário em volta
## e as marcações de seleção.

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

	var scenery := Scenery.new()
	add_child(scenery)
	scenery.build(Vector3(-T * 0.5, 0, -T * 0.5), Vector3((GameData.GRID_W - 0.5) * T, 0, (GameData.GRID_H - 0.5) * T))

	# quadrados de grama com leve variação de tom; faixa central de terra batida
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var tile_mesh := LowPoly.facet(LowPoly.prim("box", T * 0.94, 0.3, T * 0.94))
	var grass := Color(0.45, 0.68, 0.33)
	var path := Color(0.78, 0.66, 0.45)
	var mark_mesh := PlaneMesh.new()
	mark_mesh.size = Vector2(T * 0.88, T * 0.88)
	for x in GameData.GRID_W:
		for y in GameData.GRID_H:
			var p := Vector2i(x, y)
			var mi := MeshInstance3D.new()
			mi.mesh = tile_mesh
			var on_path := absi(y * 2 - (GameData.GRID_H - 1)) <= 1 and x > 2 and x < GameData.GRID_W - 3
			var base := path if on_path else grass
			var col := base.lightened(rng.randf_range(0.0, 0.07)) if (x + y) % 2 == 0 else base.darkened(rng.randf_range(0.02, 0.08))
			mi.material_override = LowPoly.mat(col)
			mi.position = to_world(p) + Vector3(0, -0.16, 0)
			add_child(mi)
			var mk := MeshInstance3D.new()
			mk.mesh = mark_mesh
			mk.position = to_world(p) + Vector3(0, 0.02, 0)
			mk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mk.visible = false
			add_child(mk)
			marks[p] = mk
			if not on_path and not state.obstacles.has(p) and rng.randf() < 0.18:
				Props.tuft(self, to_world(p) + Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7)), rng)

	# obstáculos: rochas, ruínas e árvores (mesmo tipo nos dois lados, por simetria)
	for p in state.obstacles.keys():
		var q: Vector2i = p
		var canon := q if q.x * GameData.GRID_H + q.y < (GameData.GRID_W - 1 - q.x) * GameData.GRID_H + (GameData.GRID_H - 1 - q.y) \
			else Vector2i(GameData.GRID_W - 1 - q.x, GameData.GRID_H - 1 - q.y)
		var kind := (canon.x * 7 + canon.y * 13) % 3
		var orng := RandomNumberGenerator.new()
		orng.seed = canon.x * 31 + canon.y
		match kind:
			0:
				Props.rock_cluster(self, to_world(q), orng)
			1:
				Props.ruin_pillar(self, to_world(q), orng)
			2:
				Props.pine(self, to_world(q), 1.5, orng)


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
		"move": Color(0.3, 0.65, 1.0, 0.4), "path": Color(0.9, 0.97, 1.0, 0.7),
		"target": Color(1.0, 0.3, 0.3, 0.4), "area": Color(1.0, 0.6, 0.2, 0.7),
		"active": Color(1.0, 0.85, 0.3, 0.65),
	}
	for k in defs:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = defs[k]
		mark_mats[k] = m
