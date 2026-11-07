class_name CharacterBuilder
extends RefCounted
## Monta os personagens low poly cartoon (proporção "chibi": cabeça grande, corpo curto).
## A cor do time aparece nas peças de destaque (capa, tabardo, cachecol, cinto, penas).
## Referências por classe:
##   Tanque     cavaleiro pesado: elmo com viseira e penacho, ombreiras, escudo grande, maça
##   Assassino  capuz pontudo, rosto coberto, olhos brilhando, cachecol esvoaçante, duas adagas
##   Arqueiro   chapéu de caçador com pena, capa, aljava nas costas, arco longo
##   Druida     manto, barba, chifres e coroa de folhas, cajado com orbe verde
##   Engenheiro capacete com óculos de proteção, mochila com chaminé e engrenagem, chave inglesa
## Retorna o nó raiz "Model" com metadados: arm_w (braço da arma), arm_s (braço secundário).

const SKIN := [Color(0.96, 0.78, 0.62), Color(0.85, 0.66, 0.52), Color(0.72, 0.52, 0.38)]
const DARK := Color(0.1, 0.08, 0.12)
const STEEL := Color(0.66, 0.7, 0.76)
const WOOD := Color(0.5, 0.33, 0.2)
const LEATHER := Color(0.42, 0.28, 0.18)


static func build(cls: String, team: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	match cls:
		"tanque":
			_tank(root, team)
		"assassino":
			_assassin(root, team)
		"arqueiro":
			_archer(root, team)
		"druida":
			_druid(root, team)
		"engenheiro":
			_engineer(root, team)
		"torreta":
			_turret(root, team)
	return root


static func P(kind: String, a: float, b: float = 0.0, c: float = 0.0, seg: int = 8, rings: int = 4) -> PrimitiveMesh:
	return LowPoly.prim(kind, a, b, c, seg, rings)


static func part(parent: Node3D, m: PrimitiveMesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO,
		scl: Vector3 = Vector3.ONE, outline: bool = true, emissive: float = 0.0) -> MeshInstance3D:
	return LowPoly.part(parent, m, color, pos, rot, scl, outline, emissive)


## Corpo base. Frente do personagem = +Z; a mão da arma fica em -X.
static func _humanoid(root: Node3D, skin: Color, cloth: Color, pants: Color, boots: Color,
		bulk: float = 1.0, eyes: Color = DARK, eye_glow: float = 0.0) -> Dictionary:
	for sx in [-1.0, 1.0]:
		part(root, P("cyl", 0.1 * bulk, 0.11 * bulk, 0.3, 6), pants, Vector3(0.13 * sx * bulk, 0.3, 0))
		part(root, P("box", 0.18 * bulk, 0.14, 0.27), boots, Vector3(0.13 * sx * bulk, 0.07, 0.04))
	var torso := part(root, P("cyl", 0.27 * bulk, 0.32 * bulk, 0.5, 8), cloth, Vector3(0, 0.68, 0))
	part(root, P("cyl", 0.33 * bulk, 0.33 * bulk, 0.08, 8), LEATHER, Vector3(0, 0.47, 0), Vector3.ZERO, Vector3.ONE, false)
	var head := Node3D.new()
	head.position = Vector3(0, 1.22, 0)
	root.add_child(head)
	part(head, P("sphere", 0.3, 0, 0, 8, 6), skin, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		part(head, P("box", 0.055, 0.09, 0.02), eyes, Vector3(0.1 * sx, 0.02, 0.29), Vector3.ZERO, Vector3.ONE, false, eye_glow)
	var d := {"head": head, "torso": torso}
	for side in ["w", "s"]:
		var sx := -1.0 if side == "w" else 1.0
		var piv := Node3D.new()
		piv.position = Vector3(0.37 * bulk * sx, 0.86, 0)
		piv.rotation.x = -0.25
		root.add_child(piv)
		part(piv, P("capsule", 0.085 * bulk, 0.42, 6, 2), cloth.darkened(0.12), Vector3(0, -0.17, 0))
		part(piv, P("sphere", 0.095 * bulk, 0, 0, 6, 4), skin, Vector3(0, -0.37, 0))
		var hand := Node3D.new()
		hand.position = Vector3(0, -0.38, 0.02)
		piv.add_child(hand)
		d["arm_" + side] = piv
		d["hand_" + side] = hand
	root.set_meta("arm_w", d["arm_w"])
	root.set_meta("arm_s", d["arm_s"])
	return d


## Nó que aponta para a frente a partir da mão (o eixo +Y do nó vira "para a frente").
static func _grip(hand: Node3D, forward: bool = true) -> Node3D:
	var g := Node3D.new()
	g.rotation.x = PI * 0.5 if forward else PI + 0.25
	hand.add_child(g)
	return g


# ---------------------------------------------------------------- classes

static func _tank(root: Node3D, team: Color) -> void:
	var d := _humanoid(root, SKIN[0], STEEL, Color(0.3, 0.3, 0.36), STEEL.darkened(0.35), 1.25)
	part(root, P("box", 0.42, 0.46, 0.05), team, Vector3(0, 0.62, 0.36))
	part(root, P("box", 0.12, 0.12, 0.06), Color(1, 0.86, 0.4), Vector3(0, 0.72, 0.4), Vector3(0, 0, PI * 0.25), Vector3.ONE, false, 0.3)
	for sx in [-1.0, 1.0]:
		part(root, P("sphere", 0.2, 0, 0, 6, 4), STEEL.darkened(0.15), Vector3(0.44 * sx, 0.95, 0), Vector3.ZERO, Vector3(1, 0.7, 1))
	var head: Node3D = d["head"]
	part(head, P("cyl", 0.34, 0.34, 0.42, 8), STEEL, Vector3(0, 0.02, 0))
	part(head, P("sphere", 0.34, 0, 0, 8, 4), STEEL, Vector3(0, 0.22, 0), Vector3.ZERO, Vector3(1, 0.55, 1))
	part(head, P("box", 0.4, 0.06, 0.04), DARK, Vector3(0, 0.04, 0.33), Vector3.ZERO, Vector3.ONE, false)
	part(head, P("box", 0.06, 0.28, 0.04), DARK, Vector3(0, -0.06, 0.335), Vector3.ZERO, Vector3.ONE, false)
	part(head, P("box", 0.08, 0.24, 0.42), team, Vector3(0, 0.46, -0.04), Vector3(-0.2, 0, 0))
	# escudo no braço secundário
	var arm_s: Node3D = d["arm_s"]
	var shield := Node3D.new()
	shield.position = Vector3(0.05, -0.24, 0.2)
	shield.rotation.x = PI * 0.5 + 0.25
	arm_s.add_child(shield)
	part(shield, P("cyl", 0.46, 0.46, 0.08, 8), team, Vector3.ZERO)
	part(shield, P("cyl", 0.5, 0.5, 0.05, 8), STEEL.darkened(0.2), Vector3(0, -0.03, 0), Vector3.ZERO, Vector3.ONE, false)
	part(shield, P("sphere", 0.12, 0, 0, 6, 4), STEEL, Vector3(0, 0.06, 0))
	# maça
	var g := _grip(d["hand_w"])
	part(g, P("cyl", 0.04, 0.04, 0.55, 6), WOOD, Vector3(0, 0.18, 0))
	part(g, P("sphere", 0.15, 0, 0, 6, 4), STEEL, Vector3(0, 0.5, 0))
	for k in 4:
		var a := k * PI * 0.5
		part(g, P("cyl", 0.0, 0.05, 0.14, 4), STEEL.darkened(0.2), Vector3(cos(a) * 0.16, 0.5, sin(a) * 0.16), Vector3(0, -a, PI * 0.5), Vector3.ONE, false)


static func _assassin(root: Node3D, team: Color) -> void:
	var cloth := Color(0.24, 0.21, 0.3)
	var d := _humanoid(root, SKIN[1], cloth, Color(0.16, 0.15, 0.2), Color(0.1, 0.1, 0.12), 0.92, team.lightened(0.3), 3.0)
	var head: Node3D = d["head"]
	part(head, P("sphere", 0.35, 0, 0, 8, 6), cloth.darkened(0.1), Vector3(0, 0.05, -0.08))
	part(head, P("cyl", 0.0, 0.17, 0.34, 6), cloth.darkened(0.1), Vector3(0, 0.26, -0.26), Vector3(-1.0, 0, 0))
	part(head, P("box", 0.46, 0.17, 0.08), team.darkened(0.35), Vector3(0, -0.12, 0.25))
	part(root, P("torus", 0.14, 0.26, 8, 4), team, Vector3(0, 1.0, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	part(root, P("box", 0.11, 0.42, 0.03), team, Vector3(0.1, 0.8, -0.3), Vector3(0.35, 0, 0.12))
	part(root, P("box", 0.09, 0.34, 0.03), team, Vector3(-0.04, 0.82, -0.3), Vector3(0.25, 0, -0.1))
	for side in ["w", "s"]:
		var g := _grip(d["hand_" + side])
		part(g, P("cyl", 0.035, 0.035, 0.14, 6), LEATHER, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3.ONE, false)
		part(g, P("box", 0.16, 0.03, 0.05), DARK, Vector3(0, 0.1, 0), Vector3.ZERO, Vector3.ONE, false)
		part(g, P("prism", 0.09, 0.38, 0.025), Color(0.85, 0.88, 0.95), Vector3(0, 0.3, 0))


static func _archer(root: Node3D, team: Color) -> void:
	var tunic := Color(0.32, 0.54, 0.3)
	var d := _humanoid(root, SKIN[0], tunic, Color(0.42, 0.3, 0.2), LEATHER, 1.0)
	var head: Node3D = d["head"]
	part(head, P("sphere", 0.31, 0, 0, 8, 6), Color(0.55, 0.32, 0.16), Vector3(0, 0.05, -0.06))
	part(head, P("cyl", 0.0, 0.36, 0.38, 6), tunic.darkened(0.25), Vector3(0, 0.33, -0.04), Vector3(-0.3, 0, 0))
	part(head, P("box", 0.04, 0.34, 0.09), team, Vector3(0.22, 0.44, -0.12), Vector3(0, 0, -0.55), Vector3.ONE, true, 0.4)
	part(root, P("box", 0.58, 0.66, 0.04), team.darkened(0.15), Vector3(0, 0.66, -0.34), Vector3(0.14, 0, 0))
	var quiver := Node3D.new()
	quiver.position = Vector3(-0.17, 0.86, -0.32)
	quiver.rotation.z = 0.4
	root.add_child(quiver)
	part(quiver, P("cyl", 0.11, 0.09, 0.52, 6), LEATHER, Vector3.ZERO)
	for k in 3:
		var x := (k - 1) * 0.05
		part(quiver, P("cyl", 0.012, 0.012, 0.24, 4), WOOD, Vector3(x, 0.36, 0), Vector3.ZERO, Vector3.ONE, false)
		part(quiver, P("box", 0.05, 0.1, 0.02), team, Vector3(x, 0.46, 0), Vector3.ZERO, Vector3.ONE, false)
	# arco: arco de segmentos + corda
	var bow := Node3D.new()
	bow.position = Vector3(0, 0, 0.06)
	bow.rotation.x = 0.25
	d["hand_s"].add_child(bow)
	var r := 0.55
	for k in 6:
		var a0 := deg_to_rad(-84.0 + k * 28.0)
		var a1 := a0 + deg_to_rad(28.0)
		var p0 := Vector3(0, sin(a0) * r, cos(a0) * r - r * 0.8)
		var p1 := Vector3(0, sin(a1) * r, cos(a1) * r - r * 0.8)
		var mid := (p0 + p1) * 0.5
		var seg := part(bow, P("cyl", 0.03, 0.03, p0.distance_to(p1) + 0.02, 5), WOOD, mid)
		seg.rotation.x = atan2(p1.z - p0.z, p1.y - p0.y)
	var top := Vector3(0, sin(deg_to_rad(84.0)) * r, cos(deg_to_rad(84.0)) * r - r * 0.8)
	part(bow, P("cyl", 0.006, 0.006, top.y * 2.0, 3), Color(0.95, 0.93, 0.85), Vector3(0, 0, top.z), Vector3.ZERO, Vector3.ONE, false)


static func _druid(root: Node3D, team: Color) -> void:
	var robe := Color(0.36, 0.46, 0.27)
	var d := _humanoid(root, SKIN[2], robe, robe.darkened(0.2), LEATHER, 1.05)
	part(root, P("cyl", 0.32, 0.46, 0.56, 8), robe.darkened(0.08), Vector3(0, 0.3, 0))
	part(root, P("box", 0.1, 0.72, 0.05), team, Vector3(0, 0.66, 0.31), Vector3(0, 0, 0.55))
	for sx in [-1.0, 1.0]:
		part(root, P("cyl", 0.0, 0.2, 0.12, 5), Color(0.4, 0.68, 0.3), Vector3(0.38 * sx, 0.97, 0), Vector3(0, 0, -0.35 * sx))
	var head: Node3D = d["head"]
	part(head, P("sphere", 0.21, 0, 0, 6, 4), Color(0.93, 0.92, 0.88), Vector3(0, -0.2, 0.2), Vector3.ZERO, Vector3(1, 1.25, 0.6))
	part(head, P("sphere", 0.3, 0, 0, 8, 4), Color(0.93, 0.92, 0.88), Vector3(0, 0.08, -0.06), Vector3.ZERO, Vector3(1.02, 0.85, 1.0))
	var bone := Color(0.86, 0.78, 0.6)
	for sx in [-1.0, 1.0]:
		var ant := Node3D.new()
		ant.position = Vector3(0.18 * sx, 0.24, -0.02)
		ant.rotation.z = -0.55 * sx
		head.add_child(ant)
		part(ant, P("cyl", 0.022, 0.032, 0.36, 5), bone, Vector3(0, 0.18, 0))
		part(ant, P("cyl", 0.015, 0.022, 0.18, 4), bone, Vector3(0.07 * sx, 0.24, 0.02), Vector3(0, 0, -0.9 * sx))
		part(ant, P("cyl", 0.015, 0.022, 0.16, 4), bone, Vector3(-0.05 * sx, 0.34, 0), Vector3(0, 0, 0.7 * sx))
	for k in 6:
		var a := k * TAU / 6.0
		part(head, P("sphere", 0.065, 0, 0, 5, 3), Color(0.35, 0.72, 0.32), Vector3(cos(a) * 0.27, 0.18, sin(a) * 0.27), Vector3.ZERO, Vector3.ONE, false)
	var staff := Node3D.new()
	staff.position = Vector3(0, 0, 0.1)
	staff.rotation.x = PI + 0.25
	d["hand_w"].add_child(staff)
	part(staff, P("cyl", 0.04, 0.05, 1.5, 6), WOOD, Vector3(0, 0.45, 0))
	part(staff, P("torus", 0.08, 0.14, 6, 4), WOOD.darkened(0.2), Vector3(0, 1.2, 0), Vector3(PI * 0.5, 0, 0))
	part(staff, P("sphere", 0.1, 0, 0, 6, 4), Color(0.45, 1.0, 0.5), Vector3(0, 1.22, 0), Vector3.ZERO, Vector3.ONE, false, 2.5)
	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 1.0, 0.55)
	light.light_energy = 0.8
	light.omni_range = 2.5
	light.position = Vector3(0, 1.22, 0)
	staff.add_child(light)


static func _engineer(root: Node3D, team: Color) -> void:
	var suit := Color(0.95, 0.55, 0.18)
	var d := _humanoid(root, SKIN[1], suit, suit.darkened(0.2), Color(0.3, 0.22, 0.16), 1.05)
	part(root, P("cyl", 0.36, 0.36, 0.1, 8), team, Vector3(0, 0.47, 0))
	for sx in [-1.0, 1.0]:
		part(root, P("box", 0.1, 0.12, 0.08), LEATHER, Vector3(0.24 * sx, 0.44, 0.27))
	var head: Node3D = d["head"]
	var hat := Color(0.98, 0.82, 0.22)
	part(head, P("sphere", 0.33, 0, 0, 8, 4), hat, Vector3(0, 0.13, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	part(head, P("cyl", 0.38, 0.38, 0.04, 8), hat.darkened(0.1), Vector3(0, 0.1, 0.05))
	for sx in [-1.0, 1.0]:
		part(head, P("cyl", 0.085, 0.085, 0.07, 6), DARK, Vector3(0.11 * sx, 0.2, 0.27), Vector3(PI * 0.5 - 0.4, 0, 0))
		part(head, P("cyl", 0.06, 0.06, 0.02, 6), Color(0.4, 0.95, 1.0), Vector3(0.11 * sx, 0.215, 0.305), Vector3(PI * 0.5 - 0.4, 0, 0), Vector3.ONE, false, 1.8)
	var metal := Color(0.5, 0.52, 0.58)
	part(root, P("box", 0.52, 0.52, 0.3), metal, Vector3(0, 0.8, -0.36))
	part(root, P("cyl", 0.06, 0.07, 0.34, 6), DARK.lightened(0.15), Vector3(0.15, 1.18, -0.4))
	part(root, P("torus", 0.08, 0.17, 8, 4), team, Vector3(-0.27, 0.82, -0.36), Vector3(0, 0, PI * 0.5))
	var g := _grip(d["hand_w"])
	part(g, P("box", 0.06, 0.48, 0.04), STEEL, Vector3(0, 0.2, 0))
	part(g, P("torus", 0.06, 0.12, 6, 4), STEEL, Vector3(0, 0.48, 0), Vector3(PI * 0.5, 0, 0))


static func _turret(root: Node3D, team: Color) -> void:
	var metal := Color(0.5, 0.52, 0.58)
	for k in 3:
		var a := k * TAU / 3.0
		part(root, P("cyl", 0.04, 0.05, 0.7, 5), metal.darkened(0.2), Vector3(cos(a) * 0.25, 0.3, sin(a) * 0.25), Vector3(sin(a) * 0.5, 0, -cos(a) * 0.5))
	part(root, P("cyl", 0.22, 0.28, 0.2, 8), metal, Vector3(0, 0.62, 0))
	part(root, P("box", 0.5, 0.36, 0.5), Color(0.95, 0.55, 0.18), Vector3(0, 0.88, 0))
	part(root, P("box", 0.52, 0.08, 0.52), team, Vector3(0, 0.98, 0))
	var barrel := part(root, P("cyl", 0.07, 0.07, 0.6, 6), metal.darkened(0.3), Vector3(0, 0.88, 0.45))
	barrel.rotation.x = PI * 0.5
	part(root, P("sphere", 0.06, 0, 0, 5, 3), Color(1.0, 0.3, 0.2), Vector3(0.15, 1.1, 0.1), Vector3.ZERO, Vector3.ONE, false, 2.0)
