class_name UnitView
extends Node3D
## Visual de um personagem (modelo low poly montado pelo CharacterBuilder) e suas animações.
## Para trocar por modelos feitos em Blender depois, só esta classe muda:
## a interface (move_path, lunge_in, cast, die...) continua a mesma.

var unit_id := -1
var cls := ""
var player := 0
var dead := false
var model: Node3D
var arm_w: Node3D
var arm_s: Node3D
var label: Label3D
var shield_fx: MeshInstance3D
var _parts: Array = []
var _flash_mat: StandardMaterial3D
var _phase := 0.0
var _t := 0.0


func setup(u: Dictionary) -> void:
	unit_id = u["id"]
	cls = u["cls"]
	player = u["player"]
	name = "Unidade_%d" % unit_id
	_phase = randf() * TAU
	var team: Color = GameData.TEAM_COLORS[player]

	model = CharacterBuilder.build(cls, team)
	add_child(model)
	if model.has_meta("arm_w"):
		arm_w = model.get_meta("arm_w")
		arm_s = model.get_meta("arm_s")
	_collect_parts(model)

	# anel do time no chão
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.6
	tm.outer_radius = 0.7
	ring.mesh = tm
	ring.material_override = LowPoly.mat(team, 1.2)
	ring.scale = Vector3(1, 0.15, 1)
	ring.position.y = 0.03
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	var sm := StandardMaterial3D.new()
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.6, 0.85, 1.0, 0.2)
	shield_fx = MeshInstance3D.new()
	shield_fx.mesh = LowPoly.facet(LowPoly.prim("sphere", 1.0, 0, 0, 10, 6))
	shield_fx.material_override = sm
	shield_fx.position.y = 0.9
	shield_fx.visible = u["muralha"]
	add_child(shield_fx)

	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1, 1, 1, 0)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 40
	label.outline_size = 10
	label.pixel_size = 0.01
	label.modulate = team.lightened(0.35)
	label.position = Vector3(0, 2.35, 0)
	add_child(label)
	set_hp(u["hp"])
	rotation.y = atan2(1.0 if player == 0 else -1.0, 0.0)


func _collect_parts(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and not c.has_meta("outline"):
			_parts.append(c)
		_collect_parts(c)


func _process(delta: float) -> void:
	if dead or model == null:
		return
	_t += delta
	model.position.y = absf(sin(_t * 2.0 + _phase)) * 0.025
	model.rotation.z = sin(_t * 1.3 + _phase) * 0.02


func set_hp(hp: int) -> void:
	label.text = "%s\n%d" % [GameData.CLASSES[cls]["nome"], hp]


func set_shield(on: bool) -> void:
	shield_fx.visible = on


func face(p: Vector3) -> void:
	var d := p - position
	d.y = 0
	if d.length() > 0.01:
		rotation.y = atan2(d.x, d.z)


func _arm(arm: Node3D, angle: float, dur: float, tw: Tween = null) -> Tween:
	if arm == null:
		return tw
	if tw == null:
		tw = create_tween()
	tw.tween_property(arm, "rotation:x", angle, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw


func move_path(points: Array, step: float) -> void:
	for pt in points:
		face(pt)
		var tw := create_tween()
		tw.tween_property(self, "position", pt, step)
		tw.parallel().tween_property(model, "rotation:x", 0.12, step * 0.5)
		await tw.finished
	var settle := create_tween()
	settle.tween_property(model, "rotation:x", 0.0, 0.12)


func lunge_in(target: Vector3, speed: float) -> void:
	face(target)
	var home := position
	var dir := target - home
	dir.y = 0
	dir = dir.normalized()
	var tw := create_tween()
	tw.tween_property(self, "position", home - dir * 0.35, 0.18 / speed).set_trans(Tween.TRANS_SINE)
	if arm_w:
		tw.parallel().tween_property(arm_w, "rotation:x", -2.7, 0.18 / speed)
	if cls == "assassino" and arm_s:
		tw.parallel().tween_property(arm_s, "rotation:x", -2.4, 0.18 / speed)
	tw.tween_property(self, "position", target - dir * 0.9, 0.1 / speed).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	if arm_w:
		tw.parallel().tween_property(arm_w, "rotation:x", -0.5, 0.1 / speed)
	if cls == "assassino" and arm_s:
		tw.parallel().tween_property(arm_s, "rotation:x", -0.7, 0.12 / speed)
	await tw.finished


func return_to(home: Vector3, speed: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "position", home, 0.22 / speed).set_trans(Tween.TRANS_SINE)
	if arm_w:
		tw.parallel().tween_property(arm_w, "rotation:x", -0.25, 0.22 / speed)
	if arm_s:
		tw.parallel().tween_property(arm_s, "rotation:x", -0.25, 0.22 / speed)
	await tw.finished


func cast(speed: float) -> void:
	var tw := create_tween()
	if cls == "arqueiro" and arm_s and arm_w:
		# puxa a corda: arco à frente, mão da flecha para trás
		tw.tween_property(arm_s, "rotation:x", -1.5, 0.16 / speed)
		tw.parallel().tween_property(arm_w, "rotation:x", -1.2, 0.16 / speed)
		tw.tween_interval(0.08 / speed)
		tw.tween_property(arm_w, "rotation:x", -0.6, 0.06 / speed)
		await tw.finished
		var back := create_tween()
		back.tween_property(arm_s, "rotation:x", -0.25, 0.25 / speed)
		back.parallel().tween_property(arm_w, "rotation:x", -0.25, 0.25 / speed)
		return
	tw.tween_property(model, "scale", Vector3(1.08, 0.88, 1.08), 0.12 / speed)
	if arm_w:
		tw.parallel().tween_property(arm_w, "rotation:x", -2.6, 0.14 / speed)
	tw.tween_property(model, "scale", Vector3(0.95, 1.1, 0.95), 0.1 / speed)
	if arm_w:
		tw.parallel().tween_property(arm_w, "rotation:x", -1.2, 0.1 / speed)
	tw.tween_property(model, "scale", Vector3.ONE, 0.12 / speed)
	await tw.finished
	if arm_w:
		var back := create_tween()
		back.tween_property(arm_w, "rotation:x", -0.25, 0.25 / speed)


func pop_in(speed: float) -> void:
	scale = Vector3.ONE * 0.05
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.35 / speed).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hit_flash() -> void:
	for p in _parts:
		p.material_overlay = _flash_mat
	_flash_mat.albedo_color.a = 0.85
	var tw := create_tween()
	tw.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(_clear_flash)
	var tw2 := create_tween()
	tw2.tween_property(model, "scale", Vector3(1.15, 0.85, 1.15), 0.06)
	tw2.tween_property(model, "scale", Vector3.ONE, 0.18)


func _clear_flash() -> void:
	for p in _parts:
		p.material_overlay = null


func die(speed: float) -> void:
	dead = true
	label.visible = false
	shield_fx.visible = false
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", deg_to_rad(-85), 0.45 / speed).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(model, "position:y", 0.1, 0.45 / speed)
	tw.tween_interval(0.7 / speed)
	tw.tween_property(self, "scale", Vector3(1, 0.02, 1), 0.4 / speed)
	tw.tween_callback(hide)
