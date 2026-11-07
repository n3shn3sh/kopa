class_name Props
extends RefCounted
## Peças de cenário low poly: árvores, pedras, ruínas, arbustos, flores, estandartes e braseiros.

const GREENS := [Color(0.3, 0.6, 0.3), Color(0.36, 0.66, 0.32), Color(0.26, 0.52, 0.3), Color(0.45, 0.7, 0.3)]
const STONE := Color(0.52, 0.5, 0.56)
const TRUNK := Color(0.45, 0.3, 0.2)


static func _node(parent: Node3D, pos: Vector3, yaw: float = 0.0, s: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	parent.add_child(n)
	return n


static func pine(parent: Node3D, pos: Vector3, s: float, rng: RandomNumberGenerator, outline: bool = true) -> Node3D:
	var n := _node(parent, pos, rng.randf() * TAU, s)
	LowPoly.part(n, LowPoly.prim("cyl", 0.12, 0.17, 0.7, 6), TRUNK, Vector3(0, 0.35, 0), Vector3.ZERO, Vector3.ONE, outline)
	var g: Color = GREENS[rng.randi() % GREENS.size()]
	for k in 3:
		var r := 0.95 - k * 0.24
		LowPoly.part(n, LowPoly.prim("cyl", 0.0, r, 0.95, 7), g.lightened(k * 0.06), Vector3(0, 0.95 + k * 0.55, 0),
			Vector3(0, k * 0.4, 0), Vector3.ONE, outline)
	return n


static func round_tree(parent: Node3D, pos: Vector3, s: float, rng: RandomNumberGenerator, outline: bool = true) -> Node3D:
	var n := _node(parent, pos, rng.randf() * TAU, s)
	LowPoly.part(n, LowPoly.prim("cyl", 0.12, 0.18, 1.0, 6), TRUNK, Vector3(0, 0.5, 0), Vector3.ZERO, Vector3.ONE, outline)
	var g: Color = GREENS[rng.randi() % GREENS.size()]
	var seed_value := rng.randi() % 50
	LowPoly.part(n, LowPoly.prim("sphere", 0.85, 0, 0, 7, 5), g, Vector3(0, 1.55, 0), Vector3.ZERO, Vector3(1, 0.9, 1),
		outline, 0.0, 0.12, seed_value)
	LowPoly.part(n, LowPoly.prim("sphere", 0.5, 0, 0, 6, 4), g.lightened(0.08), Vector3(0.45, 1.9, 0.2), Vector3.ZERO,
		Vector3.ONE, outline, 0.0, 0.08, seed_value + 1)
	return n


static func bush(parent: Node3D, pos: Vector3, s: float, rng: RandomNumberGenerator) -> Node3D:
	var n := _node(parent, pos, rng.randf() * TAU, s)
	var g: Color = GREENS[rng.randi() % GREENS.size()]
	LowPoly.part(n, LowPoly.prim("sphere", 0.4, 0, 0, 6, 4), g, Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1, 0.75, 1),
		true, 0.0, 0.07, rng.randi() % 50)
	if rng.randf() < 0.5:
		var c: Color = [Color(1, 0.45, 0.5), Color(1, 0.9, 0.4), Color(0.95, 0.95, 1)][rng.randi() % 3]
		for k in 3:
			LowPoly.part(n, LowPoly.prim("sphere", 0.06, 0, 0, 5, 3), c, Vector3(rng.randf_range(-0.25, 0.25), 0.45, rng.randf_range(-0.25, 0.25)),
				Vector3.ZERO, Vector3.ONE, false)
	return n


static func rock(parent: Node3D, pos: Vector3, s: float, rng: RandomNumberGenerator, outline: bool = true, color: Color = STONE) -> Node3D:
	var n := _node(parent, pos, rng.randf() * TAU, s)
	LowPoly.part(n, LowPoly.prim("sphere", 0.5, 0, 0, 6, 4), color.darkened(rng.randf() * 0.12), Vector3(0, 0.22, 0),
		Vector3.ZERO, Vector3(1.2, 0.8, 1.0), outline, 0.0, 0.14, rng.randi() % 60)
	return n


static func rock_cluster(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var n := _node(parent, pos)
	rock(n, Vector3(0, 0, 0), 1.6, rng)
	rock(n, Vector3(0.55, 0, 0.4), 0.9, rng)
	rock(n, Vector3(-0.5, 0, -0.35), 0.8, rng)
	LowPoly.part(n, LowPoly.prim("sphere", 0.3, 0, 0, 6, 3), Color(0.4, 0.62, 0.3), Vector3(0.1, 0.62, 0.05),
		Vector3.ZERO, Vector3(1.6, 0.35, 1.3), false)
	return n


static func ruin_pillar(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var n := _node(parent, pos, rng.randf() * TAU)
	LowPoly.part(n, LowPoly.prim("box", 1.3, 0.25, 1.3), STONE.darkened(0.1), Vector3(0, 0.12, 0))
	var h := rng.randf_range(1.3, 2.3)
	LowPoly.part(n, LowPoly.prim("cyl", 0.38, 0.42, h, 8), STONE, Vector3(0, 0.25 + h * 0.5, 0))
	LowPoly.part(n, LowPoly.prim("cyl", 0.3, 0.42, 0.3, 8), STONE.lightened(0.05), Vector3(0.05, 0.25 + h + 0.1, 0), Vector3(0.2, 0, 0.15))
	LowPoly.part(n, LowPoly.prim("sphere", 0.35, 0, 0, 6, 3), Color(0.38, 0.6, 0.3), Vector3(0.05, 0.25 + h + 0.26, 0),
		Vector3.ZERO, Vector3(1.1, 0.35, 1.1), false)
	rock(n, Vector3(0.6, 0.05, 0.5), 0.45, rng)
	return n


static func flower(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var c: Color = [Color(1, 0.4, 0.45), Color(1, 0.85, 0.3), Color(0.95, 0.95, 1), Color(0.7, 0.5, 1)][rng.randi() % 4]
	var n := _node(parent, pos)
	LowPoly.part(n, LowPoly.prim("cyl", 0.012, 0.012, 0.22, 3), Color(0.3, 0.55, 0.25), Vector3(0, 0.11, 0), Vector3.ZERO, Vector3.ONE, false)
	LowPoly.part(n, LowPoly.prim("sphere", 0.06, 0, 0, 5, 3), c, Vector3(0, 0.24, 0), Vector3.ZERO, Vector3(1, 0.6, 1), false)


static func tuft(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var n := _node(parent, pos, rng.randf() * TAU)
	var g: Color = GREENS[rng.randi() % GREENS.size()].lightened(0.1)
	for k in 3:
		LowPoly.part(n, LowPoly.prim("cyl", 0.0, 0.05, 0.28, 3), g, Vector3((k - 1) * 0.07, 0.13, 0), Vector3(0, 0, (k - 1) * 0.3),
			Vector3.ONE, false)


static func banner(parent: Node3D, pos: Vector3, team: Color, face_x: float) -> Node3D:
	var n := _node(parent, pos)
	LowPoly.part(n, LowPoly.prim("cyl", 0.06, 0.07, 3.2, 6), TRUNK, Vector3(0, 1.6, 0))
	LowPoly.part(n, LowPoly.prim("sphere", 0.1, 0, 0, 5, 3), Color(1, 0.85, 0.4), Vector3(0, 3.25, 0), Vector3.ZERO, Vector3.ONE, true, 0.4)
	var flag := Node3D.new()
	flag.position = Vector3(0, 2.4, 0)
	flag.name = "Flag"
	n.add_child(flag)
	LowPoly.part(flag, LowPoly.prim("box", 0.9, 1.3, 0.05), team, Vector3(0.48 * face_x, 0, 0))
	LowPoly.part(flag, LowPoly.prim("prism", 0.9, 0.35, 0.05), team, Vector3(0.48 * face_x, -0.82, 0), Vector3(0, 0, PI))
	LowPoly.part(flag, LowPoly.prim("box", 0.25, 0.25, 0.07), Color(1, 0.9, 0.6), Vector3(0.48 * face_x, 0.1, 0.0),
		Vector3(0, 0, PI * 0.25), Vector3.ONE, false, 0.5)
	return n


static func brazier(parent: Node3D, pos: Vector3) -> OmniLight3D:
	var n := _node(parent, pos)
	LowPoly.part(n, LowPoly.prim("cyl", 0.12, 0.2, 0.9, 6), STONE.darkened(0.2), Vector3(0, 0.45, 0))
	LowPoly.part(n, LowPoly.prim("cyl", 0.36, 0.22, 0.25, 7), Color(0.35, 0.3, 0.32), Vector3(0, 1.0, 0))
	LowPoly.part(n, LowPoly.prim("cyl", 0.0, 0.26, 0.55, 6), Color(1.0, 0.55, 0.15), Vector3(0, 1.38, 0), Vector3.ZERO, Vector3.ONE, false, 2.5)
	LowPoly.part(n, LowPoly.prim("cyl", 0.0, 0.14, 0.35, 5), Color(1.0, 0.9, 0.4), Vector3(0, 1.32, 0), Vector3(0, 0.5, 0), Vector3.ONE, false, 3.0)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.light_energy = 1.4
	l.omni_range = 7.0
	l.position = Vector3(0, 1.6, 0)
	n.add_child(l)
	return l
