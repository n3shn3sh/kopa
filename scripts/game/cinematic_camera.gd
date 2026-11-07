class_name CinematicCamera
extends Node3D
## Câmera da cinemática, baseada em PLANOS (enquadramentos), não em perseguição.
## Um plano é uma pose: âncora, yaw, pitch, distância, posição da âncora na tela e FOV.
## A distância sai da matemática do FOV: é a menor que faz todos os sujeitos (caixas com a
## altura real dos personagens) caberem na área útil da tela (entre as faixas de cinema, com margem).
## Para cada plano são testados alguns ângulos e escolhido o melhor (sem obstáculo na frente,
## eixo dos 180° respeitado, tamanho dos personagens). A pose é suavizada com mola criticamente
## amortecida, em tempo real (não depende de Engine.time_scale). A orientação vem direto de
## yaw/pitch, sem look_at (nunca degenera).

const MIN_Y := 0.45                    # altura mínima da lente sobre o gramado
const SAFE_X := Vector2(-1.2, 27.2)    # fora dessa faixa há árvores e estandartes do cenário
const MAX_YAW := deg_to_rad(58.0)      # eixo dos 180°: a câmera fica do lado +Z (J1 à esquerda)
const NEAR := 0.8                      # nenhum ponto enquadrado a menos disto da lente
## Obstáculos do tabuleiro por tipo (Arena.obstacle_kind): cilindros (raio, altura) que os envolvem.
## O pinheiro é um cone: três cilindros cada vez mais finos.
const OBSTACLE_SHAPES := [
	[Vector2(1.2, 0.6), Vector2(0.8, 1.15)],                      # rochas: base larga e topo
	[Vector2(0.75, 0.5), Vector2(0.5, 3.0)],                      # ruína: base e coluna
	[Vector2(1.35, 1.9), Vector2(0.9, 2.9), Vector2(0.5, 3.9)],   # pinheiro
]
const KEYS := ["anchor", "yaw", "pitch", "dist", "sx", "sy", "fov"]   # componentes da pose suavizados

var cam: Camera3D
var time_mult := 1.0
var letterbox := 0.11                  # fração da altura coberta por cada faixa de cinema
var active := false
var obstacles: Array = []              # [{pos: Vector3, r, h}]

var _base := {}                        # plano atual (pose de referência)
var _cur := {}                         # pose suavizada
var _vel := {}                         # velocidades da mola
var _smooth := 0.35
var _t := 0.0                          # tempo dentro do plano (s de cinemática)
var _last_us := 0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.05
	cam.far = 600.0
	add_child(cam)
	_last_us = Time.get_ticks_usec()


## Lê os obstáculos da partida (grade do MatchState) como cilindros simples.
func set_obstacles(obs: Dictionary) -> void:
	obstacles.clear()
	for p in obs.keys():
		for s in OBSTACLE_SHAPES[Arena.obstacle_kind(p)]:
			obstacles.append({"pos": Arena.to_world(p), "r": s.x, "h": s.y})


func start() -> void:
	active = true
	_last_us = Time.get_ticks_usec()
	cam.current = true


func current_pose() -> Dictionary:
	return _cur.duplicate()


# ---------------------------------------------------------------- transições

## Corte seco: a pose nova vale já neste quadro.
func cut_to(pose: Dictionary) -> void:
	_base = pose.duplicate()
	_t = 0.0
	_smooth = pose.get("smooth", 0.35)
	_cur = _goal()
	_vel.clear()
	_apply()


## Movimento motivado até a pose nova (a mola leva a câmera, sem tranco).
func move_to(pose: Dictionary, smooth_time: float) -> void:
	if _cur.is_empty():
		cut_to(pose)
		return
	_base = pose.duplicate()
	_t = 0.0
	_smooth = maxf(0.05, smooth_time)


## Dá para chegar ao plano novo com um movimento curto (sem corte)?
func can_glide(pose: Dictionary, max_yaw_deg: float = 22.0, max_shift: float = 0.45) -> bool:
	if _cur.is_empty():
		return false
	var ratio: float = pose["dist"] / maxf(0.1, _cur["dist"])
	var shift: float = (pose["anchor"] as Vector3).distance_to(_cur["anchor"])
	return absf(_adiff(_cur["yaw"], pose["yaw"])) < deg_to_rad(max_yaw_deg) \
		and absf(_cur["pitch"] - pose["pitch"]) < deg_to_rad(12.0) \
		and ratio > 0.72 and ratio < 1.4 \
		and shift < max_shift * maxf(pose["dist"], _cur["dist"])


# ---------------------------------------------------------------- enquadramento

## Escolhe o melhor plano para os sujeitos. Sujeito: {pos (pés), r, h, id}.
## opts: candidates ([Vector3(yaw, pitch, bônus)]) ou yaws x pitches (rad), fov, box (Rect2 em NDC),
## center (Vector2), dmin, dmax, pref_yaw, yaw_weight, pref_pitch, prev (pose anterior),
## occluders ([sujeito]), unit_weight, occlusion_weight, wide_rays, mutual, clutter_weight; f0, f1, dur, arc, smooth vão para a pose (deriva do plano).
func frame(subjects: Array, opts: Dictionary) -> Dictionary:
	var job := _FrameJob.new(self, subjects, opts)
	while not job.step(1 << 30):
		pass
	return job.result


## Mesmo que frame(), mas dividido em fatias de até budget_usec por quadro (sem engasgos).
func frame_async(subjects: Array, opts: Dictionary, budget_usec: int = 3000) -> Dictionary:
	var job := _FrameJob.new(self, subjects, opts)
	while not job.step(budget_usec):
		await get_tree().process_frame
	return job.result


## Escolha de um plano em etapas: custo barato de todos os candidatos, depois a oclusão
## (cara) só para os que ainda podem vencer, do mais barato ao mais caro.
class _FrameJob:
	var cam_rig: CinematicCamera
	var subs: Array
	var opts: Dictionary
	var cands: Array = []
	var scored: Array = []
	var stage := 0
	var i := 0
	var best_score := INF
	var best := {}
	var result := {}

	func _init(rig: CinematicCamera, subjects: Array, o: Dictionary) -> void:
		cam_rig = rig
		opts = o
		subs = rig._unique(subjects)
		cands = o.get("candidates", [])
		if cands.is_empty():
			for y in o.get("yaws", [0.0]):
				for p in o.get("pitches", [deg_to_rad(32.0)]):
					cands.append(Vector3(y, p, 0.0))

	## Avança até gastar o orçamento; true quando terminou.
	func step(budget_usec: int) -> bool:
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < budget_usec:
			if stage == 0:
				if i < cands.size():
					var c: Vector3 = cands[i]
					var pose := cam_rig.compose(subs, c.x, c.y, opts)
					scored.append([cam_rig._score(pose, opts) + c.z, pose])
					i += 1
					continue
				scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
				stage = 1
				i = 0
			if i < scored.size() and scored[i][0] < best_score:
				var total: float = scored[i][0] + cam_rig._occlusion(scored[i][1], subs, opts)
				if total < best_score:
					best_score = total
					best = scored[i][1]
				i += 1
				continue
			_finish()
			return true
		return false

	func _finish() -> void:
		if best.is_empty():
			best = cam_rig.compose(subs, 0.0, deg_to_rad(34.0), opts)
		best["score"] = best_score
		for k in ["f0", "f1", "dur", "arc", "smooth"]:
			if opts.has(k):
				best[k] = opts[k]
		result = best


## Monta a pose que encaixa os sujeitos na caixa da tela para uma orientação dada.
func compose(subjects: Array, yaw: float, pitch: float, opts: Dictionary) -> Dictionary:
	var fov: float = opts.get("fov", 38.0)
	var box: Rect2 = opts.get("box", default_box())
	var center: Vector2 = opts.get("center", box.get_center())
	var dmin: float = opts.get("dmin", 6.0)
	var dmax: float = opts.get("dmax", 30.0)
	var pts := _corners(subjects)
	var pose := {"yaw": yaw, "pitch": pitch, "fov": fov, "sx": center.x, "sy": center.y, "anchor": Vector3.ZERO,
		"dist": dmin, "need": 0.0}
	if pts.is_empty():
		return pose
	var lo: Vector3 = pts[0]
	var hi: Vector3 = pts[0]
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	pose["anchor"] = (lo + hi) * 0.5
	var lens := _lens(pose)
	var th: float = lens["th"]
	var tv: float = lens["tv"]
	var abc := _camera_coords(pts, pose["anchor"], lens)
	var sx := center.x
	var sy := center.y
	var d := dmin
	var need := 0.0
	# encaixa e recentraliza: a composição pedida vale para o conjunto, não para a âncora
	for it in 3:
		need = _fit(abc, th, tv, sx, sy, box)
		d = clampf(need, dmin, dmax)
		var c := _ndc_bounds(abc, th, tv, sx, sy, d).get_center()
		sx = clampf(sx + (center.x - c.x), box.position.x + 0.04, box.end.x - 0.04)
		sy = clampf(sy + (center.y - c.y), box.position.y + 0.04, box.end.y - 0.04)
	need = _fit(abc, th, tv, sx, sy, box)
	pose["sx"] = sx
	pose["sy"] = sy
	pose["need"] = need
	pose["dist"] = clampf(need, dmin, dmax)
	return pose


## Distância necessária para enquadrar os sujeitos num ângulo padrão (mede o "tamanho" do
## plano no planejamento; versão rápida, com uma recentralização só).
func size_of(subjects: Array) -> float:
	var pts := _corners(subjects)
	if pts.is_empty():
		return 0.0
	var lo: Vector3 = pts[0]
	var hi: Vector3 = pts[0]
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	var pose := {"yaw": 0.0, "pitch": deg_to_rad(34.0), "fov": 38.0}
	var lens := _lens(pose)
	var box := default_box()
	var th: float = lens["th"]
	var tv: float = lens["tv"]
	var abc := _camera_coords(pts, (lo + hi) * 0.5, lens)
	var c := box.get_center()
	var d := _fit(abc, th, tv, c.x, c.y, box)
	var nb := _ndc_bounds(abc, th, tv, c.x, c.y, d).get_center()
	var sx := clampf(c.x * 2.0 - nb.x, box.position.x + 0.04, box.end.x - 0.04)
	var sy := clampf(c.y * 2.0 - nb.y, box.position.y + 0.04, box.end.y - 0.04)
	return _fit(abc, th, tv, sx, sy, box)


## Área útil da tela em NDC (y para cima), já descontando as faixas de cinema.
func default_box(mx: float = 0.8, top: float = 0.86, bottom: float = 0.88) -> Rect2:
	var v := 1.0 - 2.0 * letterbox
	return Rect2(-mx, -v * bottom, mx * 2.0, v * (bottom + top))


func position_of(pose: Dictionary) -> Vector3:
	var lens := _lens(pose)
	var d: float = pose["dist"]
	return (pose["anchor"] as Vector3) - lens["f"] * d - lens["r"] * (pose["sx"] * lens["th"] * d) \
		- lens["u"] * (pose["sy"] * lens["tv"] * d)


## Limites na tela (NDC) dos sujeitos vistos pela câmera real, para conferência nos testes.
func screen_bounds(subjects: Array) -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in _corners(subjects):
		if cam.is_position_behind(q):
			return Rect2(-9, -9, 18, 18)
		var px := cam.unproject_position(q)
		var n := Vector2(px.x / vs.x * 2.0 - 1.0, 1.0 - px.y / vs.y * 2.0)
		lo = lo.min(n)
		hi = hi.max(n)
	return Rect2(lo, hi - lo)


# ---------------------------------------------------------------- avaliação

## Sujeitos repetidos (caminhos passam pelos mesmos quadrados) contam uma vez só.
func _unique(subjects: Array) -> Array:
	var seen := {}
	var out := []
	for sj in subjects:
		var p: Vector3 = sj["pos"]
		var key := "%d|%d|%d|%d" % [sj.get("id", -1), roundi(p.x * 2.0), roundi(p.z * 2.0), 1 if sj.get("tile", false) else 0]
		if not seen.has(key):
			seen[key] = true
			out.append(sj)
	return out


## Sujeitos cobertos por obstáculos ou por outros personagens (raios da lente até o corpo).
func _occlusion(pose: Dictionary, subjects: Array, opts: Dictionary) -> float:
	var c := position_of(pose)
	var unit_w: float = opts.get("unit_weight", 0.5)
	var occ_w: float = opts.get("occlusion_weight", 60.0)
	var occ: Array = opts.get("occluders", [])
	var side: Vector3 = _lens(pose)["r"]
	var wide: bool = opts.get("wide_rays", false)
	var mutual: bool = opts.get("mutual", false)
	var laterals: Array = [0.0, -0.45, 0.45] if wide else [0.0]   # r tem folga para armas
	var heights: Array = [0.12, 0.38, 0.65, 0.92] if wide else [0.2, 0.55, 0.9]
	var ids := {}
	for sj in subjects:
		ids[sj.get("id", -1)] = true
	var rays := 0
	var blocked := 0.0
	for sj in subjects:
		if sj.get("tile", false):
			continue
		for lat in laterals:
			for k in heights:
				var q: Vector3 = sj["pos"] + Vector3(0, sj["h"] * k, 0) + side * (sj["r"] * lat)
				rays += 1
				var hit := 0.0
				for o in obstacles:
					if _blocks(c, q, o["pos"], o["r"], o["h"]):
						hit = 1.0
						break
				if hit == 0.0 and unit_w > 0.0:
					for o in occ:
						if ids.has(o.get("id", -2)):
							continue
						if _blocks(c, q, o["pos"], o["r"] * 0.8, o["h"] * 0.9):
							hit = unit_w
							break
				blocked += hit
	var pen := 0.0
	if rays > 0 and blocked > 0.0:
		# raios densos (golpe final): proporcional, uma ponta de braço não derruba o plano;
		# raios simples (montagem): qualquer bloqueio já pesa
		pen = occ_w * 2.5 * blocked / rays if wide else occ_w * blocked / rays + occ_w * 0.4
	if mutual:
		pen += _overlap_penalty(pose, c, subjects, occ_w)
	return pen


## Um sujeito na frente do outro (o atacante colado no alvo no impacto): mede na tela quanto
## da silhueta de quem está atrás fica coberta por quem está na frente.
func _overlap_penalty(pose: Dictionary, c: Vector3, subjects: Array, occ_w: float) -> float:
	var lens := _lens(pose)
	var rects := []
	for sj in subjects:
		if sj.get("tile", false):
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		# silhueta mais justa que a caixa de enquadramento (que tem folga para braços e armas)
		for q in _corners([{"pos": sj["pos"], "r": sj["r"] * 0.5, "h": sj["h"] * 0.9}]):
			var w: Vector3 = q - c
			var z := maxf(0.1, w.dot(lens["f"]))
			var n := Vector2(w.dot(lens["r"]) / z, w.dot(lens["u"]) / z)
			lo = lo.min(n)
			hi = hi.max(n)
		var depth: float = ((sj["pos"] as Vector3) - c).dot(lens["f"])
		rects.append([Rect2(lo, hi - lo), depth, sj.get("id", -1)])
	var pen := 0.0
	for a in rects:
		for b in rects:
			if a[2] == b[2] or a[1] > b[1] - 0.45:   # lado a lado não conta, só um à frente do outro
				continue
			var back: Rect2 = b[0]
			var cover := (a[0] as Rect2).intersection(back)
			var frac := cover.get_area() / maxf(0.0001, back.get_area())
			if frac > 0.3:
				pen += occ_w * (frac - 0.3)
	return pen


## Custo da pose sem a oclusão: lente em lugar válido, quadro limpo, preferências, regra dos 30°.
func _score(pose: Dictionary, opts: Dictionary) -> float:
	var s := 0.0
	var c := position_of(pose)
	# lente dentro do chão ou de um obstáculo: descarta
	if c.y < MIN_Y:
		s += 400.0 + (MIN_Y - c.y) * 100.0
	for o in obstacles:
		var dx := Vector2(c.x - o["pos"].x, c.z - o["pos"].z).length()
		if dx < o["r"] + 0.4 and c.y < o["h"] + 0.4:
			s += 400.0
	# fora da faixa segura (árvores do cenário sem dados de colisão)
	if c.x < SAFE_X.x:
		s += (SAFE_X.x - c.x) * 12.0
	elif c.x > SAFE_X.y:
		s += (c.x - SAFE_X.y) * 12.0
	# obstáculo grande em primeiro plano tapando o quadro (mesmo sem cobrir os sujeitos)
	var clutter_w: float = opts.get("clutter_weight", 0.0)
	if clutter_w > 0.0:
		var lens := _lens(pose)
		var f: Vector3 = lens["f"]
		var th: float = lens["th"]
		var tv: float = lens["tv"]
		for o in obstacles:
			var w: Vector3 = o["pos"] + Vector3(0.0, o["h"] * 0.5, 0.0) - c
			var z := w.dot(f)
			if z < 0.3 or z > pose["dist"] - 1.5:
				continue
			var ex: float = o["r"] / (th * z)
			var ey: float = o["h"] * 0.5 / (tv * z)
			if absf(w.dot(lens["r"]) / (th * z)) - ex > 1.0 or absf(w.dot(lens["u"]) / (tv * z)) - ey > 1.0:
				continue
			s += clutter_w * minf(ex, 1.0)
	# plano não coube no limite de distância: algo seria cortado
	var dmax: float = opts.get("dmax", 30.0)
	if pose["need"] > dmax:
		s += 30.0 * (pose["need"] / dmax - 1.0) + 5.0
	# preferências: ângulo, altura, personagens grandes
	s += absf(_adiff(pose["yaw"], opts.get("pref_yaw", 0.0))) * opts.get("yaw_weight", 6.0)
	s += absf(pose["pitch"] - opts.get("pref_pitch", pose["pitch"])) * 14.0
	s += pose["dist"] / maxf(1.0, opts.get("dmin", 6.0)) * 1.5
	# regra dos 30°: corte para um plano quase igual vira "pulo" — melhor mudar ângulo ou tamanho
	var prev: Dictionary = opts.get("prev", {})
	if not prev.is_empty():
		var dy := absf(_adiff(pose["yaw"], prev["yaw"]))
		var ratio: float = pose["dist"] / maxf(0.1, prev["dist"])
		var shift: float = (pose["anchor"] as Vector3).distance_to(prev["anchor"])
		if dy < deg_to_rad(15.0) and ratio > 0.8 and ratio < 1.25 and shift < pose["dist"] * 0.9:
			s += 4.0
	return s


## O segmento lente -> ponto passa por dentro do cilindro (pos, r, h)?
func _blocks(c: Vector3, q: Vector3, o: Vector3, r: float, h: float) -> bool:
	var a := Vector2(c.x, c.z)
	var ab := Vector2(q.x, q.z) - a
	var p := Vector2(o.x, o.z) - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return false
	# trecho do segmento (em t) que fica dentro do círculo
	var tm := p.dot(ab) / l2
	var d2 := (p - ab * tm).length_squared()
	if d2 > r * r:
		return false
	var half := sqrt((r * r - d2) / l2)
	var t0 := maxf(0.0, tm - half)
	var t1 := minf(0.97, tm + half)
	if t0 >= t1:
		return false
	return minf(lerpf(c.y, q.y, t0), lerpf(c.y, q.y, t1)) < h


# ---------------------------------------------------------------- geometria

func _lens(pose: Dictionary) -> Dictionary:
	var b := Basis.from_euler(Vector3(-pose["pitch"], pose["yaw"], 0.0))
	var vs := Vector2(16.0, 9.0)
	if is_inside_tree():
		vs = get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(1.0, vs.y)
	var tv := tan(deg_to_rad(pose["fov"]) * 0.5)
	return {"b": b, "r": b.x, "u": b.y, "f": -b.z, "tv": tv, "th": tv * aspect}


## Caixas dos sujeitos (8 cantos cada), com a altura real.
func _corners(subjects: Array) -> Array:
	var out := []
	for sj in subjects:
		var p: Vector3 = sj["pos"]
		var r: float = sj.get("r", 0.5)
		var h: float = sj.get("h", 1.8)
		for y in [0.0, h]:
			for dx in [-r, r]:
				for dz in [-r, r]:
					out.append(p + Vector3(dx, y, dz))
	return out


## Coordenadas dos pontos na base da câmera, relativas à âncora: (direita, cima, frente).
func _camera_coords(pts: Array, anchor: Vector3, lens: Dictionary) -> PackedVector3Array:
	var r: Vector3 = lens["r"]
	var u: Vector3 = lens["u"]
	var f: Vector3 = lens["f"]
	var out := PackedVector3Array()
	out.resize(pts.size())
	for i in pts.size():
		var w: Vector3 = pts[i] - anchor
		out[i] = Vector3(w.dot(r), w.dot(u), w.dot(f))
	return out


## Menor distância que põe todos os pontos dentro da caixa (cada lado é uma inequação linear).
func _fit(abc: PackedVector3Array, th: float, tv: float, sx: float, sy: float, box: Rect2) -> float:
	var x0 := box.position.x
	var x1 := box.end.x
	var y0 := box.position.y
	var y1 := box.end.y
	var kx1 := 1.0 / ((x1 - sx) * th)
	var kx0 := 1.0 / ((sx - x0) * th)
	var ky1 := 1.0 / ((y1 - sy) * tv)
	var ky0 := 1.0 / ((sy - y0) * tv)
	var need := 0.0
	for q in abc:
		need = maxf(need, NEAR - q.z)
		need = maxf(need, (q.x - x1 * th * q.z) * kx1)
		need = maxf(need, (x0 * th * q.z - q.x) * kx0)
		need = maxf(need, (q.y - y1 * tv * q.z) * ky1)
		need = maxf(need, (y0 * tv * q.z - q.y) * ky0)
	return need


func _ndc_bounds(abc: PackedVector3Array, th: float, tv: float, sx: float, sy: float, d: float) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in abc:
		var z := maxf(0.05, q.z + d)
		var n := Vector2((q.x + sx * th * d) / (th * z), (q.y + sy * tv * d) / (tv * z))
		lo = lo.min(n)
		hi = hi.max(n)
	return Rect2(lo, hi - lo)


# ---------------------------------------------------------------- movimento

## Pose alvo com a deriva do plano (push-in lento e arco curto, com suavização nas pontas).
func _goal() -> Dictionary:
	var g := _base.duplicate()
	var dur: float = _base.get("dur", 0.0)
	var k := 1.0
	if dur > 0.0:
		k = smoothstep(0.0, 1.0, clampf(_t / dur, 0.0, 1.0))
	g["dist"] = _base["dist"] * lerpf(_base.get("f0", 1.0), _base.get("f1", 1.0), k)
	g["yaw"] = _base["yaw"] + _base.get("arc", 0.0) * k
	return g


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1000000.0, 0.0, 0.25) * time_mult
	_last_us = now
	if not active or _base.is_empty() or not cam.current:
		return
	_t += dt
	var g := _goal()
	for k in KEYS:
		if k == "anchor":
			_cur[k] = _damp_v(_cur[k], g[k], k, dt)
		elif k == "yaw":
			# caminho mais curto no ângulo
			var target: float = _cur[k] + _adiff(_cur[k], g[k])
			_cur[k] = _damp_f(_cur[k], target, k, dt)
		else:
			_cur[k] = _damp_f(_cur[k], g[k], k, dt)
	_apply()


## Diferença angular mais curta de a para b (rad).
static func _adiff(a: float, b: float) -> float:
	return wrapf(b - a, -PI, PI)


## Mola criticamente amortecida (SmoothDamp), estável para qualquer dt.
func _damp_f(c: float, t: float, key: String, dt: float) -> float:
	var vel: float = _vel.get(key, 0.0)
	var omega := 2.0 / _smooth
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := c - t
	var temp := (vel + omega * change) * dt
	_vel[key] = (vel - omega * temp) * e
	return t + (change + temp) * e


func _damp_v(c: Vector3, t: Vector3, key: String, dt: float) -> Vector3:
	var vel: Vector3 = _vel.get(key, Vector3.ZERO)
	var omega := 2.0 / _smooth
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := c - t
	var temp := (vel + omega * change) * dt
	_vel[key] = (vel - omega * temp) * e
	return t + (change + temp) * e


func _apply() -> void:
	if _cur.is_empty():
		return
	var lens := _lens(_cur)
	var p := position_of(_cur)
	# segurança: nunca abaixo do gramado nem dentro de um obstáculo
	p.y = maxf(p.y, MIN_Y)
	for o in obstacles:
		var d := Vector2(p.x - o["pos"].x, p.z - o["pos"].z)
		var rr: float = o["r"] + 0.3
		if p.y < o["h"] + 0.3 and d.length() < rr:
			var dir := d.normalized() if d.length() > 0.001 else Vector2(0.0, 1.0)
			p.x = o["pos"].x + dir.x * rr
			p.z = o["pos"].z + dir.y * rr
	cam.fov = _cur["fov"]
	cam.global_transform = Transform3D(lens["b"], p)
