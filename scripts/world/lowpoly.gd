class_name LowPoly
extends RefCounted
## Utilitários do estilo visual: malhas facetadas (low poly), material cartoon e contorno.
## Malhas e materiais ficam em cache para serem reaproveitados.

static var _prims := {}
static var _faceted := {}
static var _mats := {}
static var _outline: StandardMaterial3D


## Primitiva com poucos segmentos. kind: sphere | cyl | box | capsule | prism | torus
static func prim(kind: String, a: float, b: float = 0.0, c: float = 0.0, seg: int = 8, rings: int = 4) -> PrimitiveMesh:
	var key := "%s_%.3f_%.3f_%.3f_%d_%d" % [kind, a, b, c, seg, rings]
	if _prims.has(key):
		return _prims[key]
	var m: PrimitiveMesh
	match kind:
		"sphere":
			var s := SphereMesh.new()
			s.radius = a
			s.height = a * 2.0
			s.radial_segments = seg
			s.rings = rings
			m = s
		"cyl":
			var cy := CylinderMesh.new()
			cy.top_radius = a
			cy.bottom_radius = b
			cy.height = c
			cy.radial_segments = seg
			cy.rings = 0
			m = cy
		"box":
			var bx := BoxMesh.new()
			bx.size = Vector3(a, b, c)
			m = bx
		"capsule":
			var cp := CapsuleMesh.new()
			cp.radius = a
			cp.height = maxf(b, a * 2.0)
			cp.radial_segments = seg
			cp.rings = rings
			m = cp
		"prism":
			var pr := PrismMesh.new()
			pr.size = Vector3(a, b, c)
			m = pr
		"torus":
			var t := TorusMesh.new()
			t.inner_radius = a
			t.outer_radius = b
			t.rings = seg
			t.ring_segments = rings
			m = t
	m.set_meta("key", key)
	_prims[key] = m
	return m


## Converte a primitiva em malha com normais por face (visual facetado).
## jitter desloca os vértices de forma determinística (pedras, folhagem).
static func facet(m: PrimitiveMesh, jitter: float = 0.0, seed_value: int = 0) -> ArrayMesh:
	var key := "%s|%.3f|%d" % [m.get_meta("key", str(m.get_instance_id())), jitter, seed_value]
	if _faceted.has(key):
		return _faceted[key]
	var arr := m.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	if jitter > 0.0:
		var rng := RandomNumberGenerator.new()
		for i in v.size():
			var p := v[i]
			rng.seed = hash(Vector3i(roundi(p.x * 997.0), roundi(p.y * 997.0), roundi(p.z * 997.0))) + seed_value
			v[i] = p + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * jitter
	var out := PackedVector3Array()
	var on := PackedVector3Array()
	var count := idx.size() if idx.size() > 0 else v.size()
	for i in range(0, count - 2, 3):
		var i0 := idx[i] if idx.size() > 0 else i
		var i1 := idx[i + 1] if idx.size() > 0 else i + 1
		var i2 := idx[i + 2] if idx.size() > 0 else i + 2
		var a := v[i0]
		var b := v[i1]
		var c := v[i2]
		var fn := (b - a).cross(c - a)
		if fn.length_squared() < 1e-12:
			continue
		fn = fn.normalized()
		if fn.dot(n[i0] + n[i1] + n[i2]) < 0.0:
			fn = -fn
		out.append(a)
		out.append(b)
		out.append(c)
		on.append(fn)
		on.append(fn)
		on.append(fn)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out
	arrays[Mesh.ARRAY_NORMAL] = on
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_faceted[key] = am
	return am


## Material com sombreado em faixas (cartoon).
static func mat(c: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f" % [c.to_html(), emissive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	_mats[key] = m
	return m


## Contorno escuro (casco invertido), típico de estilo cartoon.
static func outline_mat() -> StandardMaterial3D:
	if _outline == null:
		_outline = StandardMaterial3D.new()
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline.grow = true
		_outline.grow_amount = 0.022
		_outline.albedo_color = Color(0.07, 0.06, 0.09)
	return _outline


## Cria uma peça facetada (com contorno opcional) e a pendura em `parent`.
static func part(parent: Node3D, m: PrimitiveMesh, color: Color, pos: Vector3,
		rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, outline: bool = true,
		emissive: float = 0.0, jitter: float = 0.0, seed_value: int = 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = facet(m, jitter, seed_value)
	mi.material_override = mat(color, emissive)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	if outline:
		var o := MeshInstance3D.new()
		o.mesh = facet(m, jitter, seed_value) if jitter > 0.0 else m
		o.material_override = outline_mat()
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		o.set_meta("outline", true)
		mi.add_child(o)
	return mi
