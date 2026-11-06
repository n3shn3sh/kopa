class_name UnitView
extends Node3D
## Visual provisório de um personagem (formas simples por classe) e suas animações.
## Trocar por modelos e AnimationPlayer depois: a interface (move_path, lunge_in, cast, die...) continua a mesma.

var unit_id := -1
var cls := ""
var player := 0
var dead := false
var body_mat: StandardMaterial3D
var label: Label3D
var shield_fx: MeshInstance3D


func setup(u: Dictionary) -> void:
	unit_id = u["id"]
	cls = u["cls"]
	player = u["player"]
	name = "Unidade_%d" % unit_id
	var team: Color = GameData.TEAM_COLORS[player]
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = team.darkened(0.45)
	body_mat.roughness = 0.6
	var accent := StandardMaterial3D.new()
	accent.albedo_color = team
	accent.emission_enabled = true
	accent.emission = team
	accent.emission_energy_multiplier = 1.4

	if u["structure"]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.45
		cyl.bottom_radius = 0.6
		cyl.height = 0.9
		_mesh(cyl, body_mat, Vector3(0, 0.45, 0))
		var gun := BoxMesh.new()
		gun.size = Vector3(0.25, 0.25, 0.9)
		_mesh(gun, accent, Vector3(0, 1.0, 0.3))
	else:
		var r := 0.55 if cls == "tanque" else 0.4
		var h := 1.7 if cls == "tanque" else 1.5
		var cap := CapsuleMesh.new()
		cap.radius = r
		cap.height = h
		_mesh(cap, body_mat, Vector3(0, h * 0.5, 0))
		_mesh(_sphere(0.12), accent, Vector3(0, h * 0.8, r * 0.9))
		match cls:
			"tanque":
				var shield := BoxMesh.new()
				shield.size = Vector3(1.0, 1.1, 0.15)
				_mesh(shield, accent, Vector3(0, 0.9, r + 0.15))
			"assassino":
				var blade := PrismMesh.new()
				blade.size = Vector3(0.25, 0.8, 0.08)
				var b := _mesh(blade, accent, Vector3(0.45, 0.85, 0.35))
				b.rotation.x = deg_to_rad(80)
			"arqueiro":
				var bow := TorusMesh.new()
				bow.inner_radius = 0.45
				bow.outer_radius = 0.52
				var bw := _mesh(bow, accent, Vector3(0.45, 0.9, 0.15))
				bw.rotation.z = deg_to_rad(90)
			"druida":
				_mesh(_sphere(0.22), accent, Vector3(0.45, 1.55, 0.2))
			"engenheiro":
				var pack := BoxMesh.new()
				pack.size = Vector3(0.6, 0.6, 0.35)
				_mesh(pack, accent, Vector3(0, 1.0, -0.45))

	var ring := TorusMesh.new()
	ring.inner_radius = 0.62
	ring.outer_radius = 0.72
	var rg := _mesh(ring, accent, Vector3(0, 0.04, 0))
	rg.scale = Vector3(1, 0.2, 1)

	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.6, 0.85, 1.0, 0.18)
	shield_fx = _mesh(_sphere(1.0), sm, Vector3(0, 0.9, 0))
	shield_fx.visible = u["muralha"]

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.01
	label.modulate = team.lightened(0.35)
	label.position = Vector3(0, 2.5, 0)
	add_child(label)
	set_hp(u["hp"])
	rotation.y = atan2(1.0 if player == 0 else -1.0, 0.0)


func set_hp(hp: int) -> void:
	label.text = "%s\n%d" % [GameData.CLASSES[cls]["nome"], hp]


func set_shield(on: bool) -> void:
	shield_fx.visible = on


func face(p: Vector3) -> void:
	var d := p - position
	d.y = 0
	if d.length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func move_path(points: Array, step: float) -> void:
	for pt in points:
		face(pt)
		var tw := create_tween()
		tw.tween_property(self, "position", pt, step)
		await tw.finished


func lunge_in(target: Vector3, speed: float) -> void:
	face(target)
	var home := position
	var dir := target - home
	dir.y = 0
	dir = dir.normalized()
	var tw := create_tween()
	tw.tween_property(self, "position", home - dir * 0.35, 0.18 / speed).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "position", target - dir * 0.9, 0.1 / speed).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await tw.finished


func return_to(home: Vector3, speed: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "position", home, 0.22 / speed).set_trans(Tween.TRANS_SINE)
	await tw.finished


func cast(speed: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.1, 0.85, 1.1), 0.12 / speed)
	tw.tween_property(self, "scale", Vector3(0.92, 1.15, 0.92), 0.1 / speed)
	tw.tween_property(self, "scale", Vector3.ONE, 0.12 / speed)
	await tw.finished


func pop_in(speed: float) -> void:
	scale = Vector3.ONE * 0.05
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.35 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hit_flash() -> void:
	body_mat.emission_enabled = true
	body_mat.emission = Color(1, 1, 1)
	body_mat.emission_energy_multiplier = 2.5
	var tw := create_tween()
	tw.tween_property(body_mat, "emission_energy_multiplier", 0.0, 0.35)
	var tw2 := create_tween()
	tw2.tween_property(self, "scale", Vector3(1.15, 0.85, 1.15), 0.06)
	tw2.tween_property(self, "scale", Vector3.ONE, 0.18)


func die(speed: float) -> void:
	dead = true
	label.visible = false
	shield_fx.visible = false
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", deg_to_rad(-80), 0.45 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "position:y", -0.2, 0.45 / speed)
	tw.tween_interval(0.6 / speed)
	tw.tween_property(self, "scale", Vector3(1, 0.02, 1), 0.4 / speed)
	tw.tween_callback(hide)


func _mesh(m: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s
