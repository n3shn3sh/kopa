class_name Scenery
extends Node3D
## Cenário ao redor do tabuleiro: platô gramado sobre um lago, ilhas com árvores,
## montanhas ao fundo, nuvens, estandartes dos times, braseiros e folhas caindo.

var lights: Array = []
var flags: Array = []
var clouds: Node3D
var _t := 0.0


func build(arena_min: Vector3, arena_max: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var c := (arena_min + arena_max) * 0.5
	var margin := 5.0
	var pmin := arena_min - Vector3(margin, 0, margin)
	var pmax := arena_max + Vector3(margin, 0, margin)
	var psize := pmax - pmin

	# platô: terra com gramado por cima
	LowPoly.part(self, LowPoly.prim("box", psize.x, 4.0, psize.z), Color(0.5, 0.36, 0.24), Vector3(c.x, -2.45, c.z),
		Vector3.ZERO, Vector3.ONE, false)
	LowPoly.part(self, LowPoly.prim("box", psize.x + 0.3, 0.3, psize.z + 0.3), Color(0.38, 0.6, 0.3), Vector3(c.x, -0.42, c.z),
		Vector3.ZERO, Vector3.ONE, false)
	LowPoly.part(self, LowPoly.prim("box", psize.x - 0.6, 0.6, psize.z - 0.6), Color(0.42, 0.3, 0.2), Vector3(c.x, -4.6, c.z),
		Vector3.ZERO, Vector3.ONE, false)
	# pedras na encosta
	for k in 40:
		var side := k % 4
		var t := rng.randf()
		var p := Vector3()
		match side:
			0:
				p = Vector3(lerpf(pmin.x, pmax.x, t), -1.5 - rng.randf() * 1.5, pmin.z)
			1:
				p = Vector3(lerpf(pmin.x, pmax.x, t), -1.5 - rng.randf() * 1.5, pmax.z)
			2:
				p = Vector3(pmin.x, -1.5 - rng.randf() * 1.5, lerpf(pmin.z, pmax.z, t))
			3:
				p = Vector3(pmax.x, -1.5 - rng.randf() * 1.5, lerpf(pmin.z, pmax.z, t))
		Props.rock(self, p, rng.randf_range(1.2, 2.4), rng, false, Color(0.55, 0.5, 0.48))

	# lago
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(420, 420)
	water.mesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.16, 0.44, 0.66)
	wmat.roughness = 0.15
	wmat.metallic = 0.25
	wmat.emission_enabled = true
	wmat.emission = Color(0.02, 0.06, 0.1)
	water.material_override = wmat
	water.position = Vector3(c.x, -2.7, c.z)
	add_child(water)

	# decoração da margem do platô (fora da área de jogo)
	for k in 220:
		var p := Vector3(rng.randf_range(pmin.x + 0.4, pmax.x - 0.4), -0.27, rng.randf_range(pmin.z + 0.4, pmax.z - 0.4))
		var inside := p.x > arena_min.x - 0.6 and p.x < arena_max.x + 0.6 and p.z > arena_min.z - 0.6 and p.z < arena_max.z + 0.6
		if inside:
			continue
		var near_camera := p.z > arena_max.z   # lado da câmera: só coisas baixas
		var roll := rng.randf()
		if roll < 0.08 and not near_camera:
			if rng.randf() < 0.5:
				Props.pine(self, p, rng.randf_range(0.9, 1.4), rng)
			else:
				Props.round_tree(self, p, rng.randf_range(0.9, 1.3), rng)
		elif roll < 0.16:
			Props.bush(self, p, rng.randf_range(0.8, 1.3), rng)
		elif roll < 0.22:
			Props.rock(self, p, rng.randf_range(0.4, 0.9), rng)
		elif roll < 0.5:
			Props.flower(self, p, rng)
		else:
			Props.tuft(self, p, rng)

	# estandartes e braseiros nas bases
	for player in 2:
		var x := arena_min.x - 2.6 if player == 0 else arena_max.x + 2.6
		var face := 1.0 if player == 0 else -1.0
		for z in [c.z - 5.0, c.z + 5.0]:
			var b := Props.banner(self, Vector3(x, -0.27, z), GameData.TEAM_COLORS[player], face)
			flags.append(b.get_node("Flag"))
	for corner in [Vector3(arena_min.x - 2.0, -0.27, arena_min.z - 2.0), Vector3(arena_max.x + 2.0, -0.27, arena_min.z - 2.0),
			Vector3(arena_min.x - 2.0, -0.27, arena_max.z + 2.0), Vector3(arena_max.x + 2.0, -0.27, arena_max.z + 2.0)]:
		lights.append(Props.brazier(self, corner))

	# ilhas ao redor
	for k in 13:
		var a := k * TAU / 13.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(36.0, 62.0)
		var p := c + Vector3(cos(a) * r * 1.2, -2.7, sin(a) * r)
		var sx := rng.randf_range(5.0, 9.0)
		var sz := rng.randf_range(5.0, 9.0)
		LowPoly.part(self, LowPoly.prim("sphere", 1.0, 0, 0, 8, 5), Color(0.4, 0.62, 0.32), p, Vector3(0, rng.randf() * TAU, 0),
			Vector3(sx, 2.4, sz), false, 0.0, 0.12, k)
		for t in rng.randi_range(2, 5):
			var tp := p + Vector3(rng.randf_range(-sx, sx) * 0.45, 2.1, rng.randf_range(-sz, sz) * 0.45)
			if rng.randf() < 0.6:
				Props.pine(self, tp, rng.randf_range(1.6, 2.6), rng, false)
			else:
				Props.round_tree(self, tp, rng.randf_range(1.5, 2.3), rng, false)
		if rng.randf() < 0.5:
			Props.rock(self, p + Vector3(sx * 0.5, 1.2, 0), rng.randf_range(1.5, 2.5), rng, false)

	# montanhas no horizonte
	for k in 11:
		var a := k * TAU / 11.0 + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(110.0, 150.0)
		var p := c + Vector3(cos(a) * r, -3.0, sin(a) * r)
		var rad := rng.randf_range(16.0, 26.0)
		var h := rng.randf_range(26.0, 42.0)
		var col := Color(0.47, 0.52, 0.64).lerp(Color(0.6, 0.62, 0.72), rng.randf())
		LowPoly.part(self, LowPoly.prim("cyl", 0.0, 1.0, 1.0, 7), col, p + Vector3(0, h * 0.5, 0), Vector3(0, rng.randf() * TAU, 0),
			Vector3(rad, h, rad), false, 0.0, 0.08, k)
		LowPoly.part(self, LowPoly.prim("cyl", 0.0, 1.0, 1.0, 7), Color(0.96, 0.97, 1.0), p + Vector3(0, h * 0.86, 0),
			Vector3(0, rng.randf() * TAU, 0), Vector3(rad * 0.3, h * 0.29, rad * 0.3), false, 0.0, 0.06, k + 20)

	# nuvens
	clouds = Node3D.new()
	clouds.position = c
	add_child(clouds)
	for k in 10:
		var a := rng.randf() * TAU
		var r := rng.randf_range(18.0, 75.0)
		var cp := Vector3(cos(a) * r, rng.randf_range(20.0, 30.0), sin(a) * r)
		var s := rng.randf_range(2.0, 3.6)
		for b in 3:
			LowPoly.part(clouds, LowPoly.prim("sphere", 1.0, 0, 0, 7, 4), Color(1, 1, 1), cp + Vector3((b - 1) * s * 1.1, (1 - absi(b - 1)) * s * 0.35, 0),
				Vector3.ZERO, Vector3(s * (1.2 - absi(b - 1) * 0.3), s * 0.7, s), false, 0.25, 0.1, k * 3 + b)

	# folhas caindo sobre a arena
	var leaves := CPUParticles3D.new()
	leaves.amount = 40
	leaves.lifetime = 9.0
	leaves.preprocess = 9.0
	leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	leaves.emission_box_extents = Vector3(psize.x * 0.5, 0.5, psize.z * 0.5)
	leaves.position = c + Vector3(0, 12, 0)
	leaves.direction = Vector3(1, -1, 0.3)
	leaves.spread = 25.0
	leaves.gravity = Vector3(0, -0.6, 0)
	leaves.initial_velocity_min = 0.6
	leaves.initial_velocity_max = 1.4
	leaves.angular_velocity_min = -120.0
	leaves.angular_velocity_max = 120.0
	leaves.mesh = LowPoly.facet(LowPoly.prim("box", 0.14, 0.02, 0.09))
	leaves.material_override = LowPoly.mat(Color(1.0, 0.72, 0.35))
	add_child(leaves)


func _process(delta: float) -> void:
	_t += delta
	for i in lights.size():
		lights[i].light_energy = 1.3 + sin(_t * 9.0 + i * 1.7) * 0.15 + sin(_t * 23.0 + i) * 0.1
	for i in flags.size():
		flags[i].rotation.y = sin(_t * 2.2 + i) * 0.18
	if clouds:
		clouds.rotation.y += delta * 0.01
