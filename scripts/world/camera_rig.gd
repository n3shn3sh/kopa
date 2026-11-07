class_name CameraRig
extends Node3D
## Câmera de jogo estilo MOBA: perspectiva de cima em ângulo.
## WASD/setas movem, roda do mouse aproxima, Q/E giram, botão do meio arrasta.

var cam: Camera3D
var target := Vector3.ZERO
var cur := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(55.0)
var dist := 22.0
var cur_dist := 22.0
var enabled := true
var dragging := false


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)


func snap_to(p: Vector3) -> void:
	target = p
	cur = p
	cur_dist = dist
	_apply()


## Centraliza um pouco acima do meio da tela, para o painel de baixo não cobrir o personagem.
func focus(p: Vector3) -> void:
	target = p - _forward() * 2.5


func _unhandled_input(e: InputEvent) -> void:
	if not enabled:
		return
	var mb := e as InputEventMouseButton
	if mb:
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist - 2.0, 10.0, 40.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist + 2.0, 10.0, 40.0)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
	var mm := e as InputEventMouseMotion
	if mm and dragging:
		target -= (_right() * mm.relative.x - _forward() * mm.relative.y) * dist * 0.0025


func _right() -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _process(delta: float) -> void:
	if not enabled:
		return
	var real := delta / maxf(Engine.time_scale, 0.0001)
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		mv.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		mv.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		mv.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		mv.y -= 1.0
	if Input.is_key_pressed(KEY_Q):
		yaw -= real * 1.6
	if Input.is_key_pressed(KEY_E):
		yaw += real * 1.6
	target += (_right() * mv.x + _forward() * mv.y) * real * dist * 0.9
	target.x = clampf(target.x, -4.0, GameData.GRID_W * GameData.TILE + 2.0)
	target.z = clampf(target.z, -4.0, GameData.GRID_H * GameData.TILE + 2.0)
	var k := 1.0 - exp(-8.0 * real)
	cur = cur.lerp(target, k)
	cur_dist = lerpf(cur_dist, dist, k)
	_apply()


func _apply() -> void:
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * cur_dist
	cam.position = cur + off
	cam.look_at(cur)
