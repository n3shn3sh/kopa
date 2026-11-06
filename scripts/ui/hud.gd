class_name GameHUD
extends CanvasLayer
## Interface provisória, montada em código: ordem de iniciativa, personagem da vez,
## ações, registro de eventos, faixas de cinema, legenda e tela de fim.

signal move_pressed
signal ability_pressed(index: int)
signal end_pressed
signal replay_pressed
signal new_match_pressed
signal skip_pressed

const BG := Color(0.05, 0.06, 0.09, 0.88)
const FG := Color(0.92, 0.94, 0.97)
const MUTE := Color(0.62, 0.66, 0.74)

var root: Control
var top: PanelContainer
var bottom: PanelContainer
var log_panel: PanelContainer
var top_label: Label
var queue_box: HBoxContainer
var unit_name: Label
var unit_info: Label
var hp_bar: ProgressBar
var hp_fill: StyleBoxFlat
var btn_move: Button
var btn_abs: Array = []
var btn_end: Button
var desc_label: Label
var hint_label: Label
var log_label: Label
var log_lines: Array = []
var bar_top: ColorRect
var bar_bot: ColorRect
var caption_box: VBoxContainer
var caption_big: Label
var caption_small: Label
var flash_label: Label
var end_panel: PanelContainer
var end_title: Label
var end_sub: Label
var skip_btn: Button
var _ab_ids: Array = []


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top()
	_build_bottom()
	_build_log()
	_build_cinematic()
	_build_end()


# ---------------------------------------------------------------- construção

func _panel(bg: Color = BG, margin: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String = "", size: int = 16, color: Color = FG) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, w: float = 150.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, 44)
	b.add_theme_font_size_override("font_size", 15)
	return b


func _outline(l: Label, size: int) -> void:
	l.add_theme_constant_override("outline_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))


func _build_top() -> void:
	top = _panel()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 10
	root.add_child(top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	top.add_child(hb)
	top_label = _label("", 18)
	hb.add_child(top_label)
	hb.add_child(_label("Ordem de iniciativa:", 13, MUTE))
	queue_box = HBoxContainer.new()
	queue_box.add_theme_constant_override("separation", 6)
	hb.add_child(queue_box)


func _build_bottom() -> void:
	bottom = _panel()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 12
	bottom.offset_right = -12
	bottom.offset_bottom = -10
	bottom.offset_top = -150
	root.add_child(bottom)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	bottom.add_child(hb)

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(300, 0)
	hb.add_child(info)
	unit_name = _label("", 22)
	info.add_child(unit_name)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(280, 16)
	hp_bar.show_percentage = false
	hp_fill = StyleBoxFlat.new()
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	info.add_child(hp_bar)
	unit_info = _label("", 13, MUTE)
	unit_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(unit_info)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(mid)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	mid.add_child(btns)
	btn_move = _button("Mover [M]")
	btn_move.toggle_mode = true
	btn_move.pressed.connect(func() -> void: move_pressed.emit())
	btns.add_child(btn_move)
	for i in 2:
		var b := _button("", 230.0)
		b.toggle_mode = true
		var idx := i
		b.pressed.connect(func() -> void: ability_pressed.emit(idx))
		b.mouse_entered.connect(func() -> void: _show_desc(idx))
		btns.add_child(b)
		btn_abs.append(b)
	btn_end = _button("Encerrar turno [Espaço]", 210.0)
	btn_end.pressed.connect(func() -> void: end_pressed.emit())
	btns.add_child(btn_end)
	desc_label = _label("", 14, MUTE)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(desc_label)

	hint_label = _label("", 15, Color(1.0, 0.88, 0.6))
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.offset_top = -190
	hint_label.offset_bottom = -162
	hint_label.offset_left = -420
	hint_label.offset_right = 420
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(hint_label, 6)
	root.add_child(hint_label)


func _build_log() -> void:
	log_panel = _panel(Color(0.05, 0.06, 0.09, 0.7))
	log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	log_panel.offset_left = -390
	log_panel.offset_right = -12
	log_panel.offset_top = 78
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_panel)
	log_label = _label("", 13)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.custom_minimum_size = Vector2(355, 0)
	log_panel.add_child(log_label)


func _build_cinematic() -> void:
	bar_top = ColorRect.new()
	bar_top.color = Color.BLACK
	bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar_top.offset_bottom = 0
	bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_top)
	bar_bot = ColorRect.new()
	bar_bot.color = Color.BLACK
	bar_bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar_bot.offset_top = 0
	bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_bot)

	caption_box = VBoxContainer.new()
	caption_box.anchor_left = 0.0
	caption_box.anchor_right = 1.0
	caption_box.anchor_top = 1.0
	caption_box.anchor_bottom = 1.0
	caption_box.offset_top = -260
	caption_box.offset_bottom = -120
	caption_box.alignment = BoxContainer.ALIGNMENT_CENTER
	caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_box.visible = false
	root.add_child(caption_box)
	caption_big = _label("", 84, Color(1.0, 0.9, 0.75))
	caption_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(caption_big, 18)
	caption_box.add_child(caption_big)
	caption_small = _label("", 22)
	caption_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_outline(caption_small, 8)
	caption_box.add_child(caption_small)

	flash_label = _label("GOLPE FINAL", 128, Color(1.0, 0.85, 0.6))
	flash_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_outline(flash_label, 24)
	flash_label.visible = false
	root.add_child(flash_label)

	skip_btn = _button("Pular cinemática", 190.0)
	skip_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip_btn.offset_left = -206
	skip_btn.offset_right = -16
	skip_btn.offset_top = 16
	skip_btn.offset_bottom = 60
	skip_btn.visible = false
	skip_btn.pressed.connect(func() -> void: skip_pressed.emit())
	root.add_child(skip_btn)


func _build_end() -> void:
	end_panel = _panel(Color(0.05, 0.06, 0.09, 0.94), 28)
	end_panel.set_anchors_preset(Control.PRESET_CENTER)
	end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	end_panel.visible = false
	root.add_child(end_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	end_panel.add_child(vb)
	end_title = _label("", 56)
	vb.add_child(end_title)
	end_sub = _label("", 16, MUTE)
	vb.add_child(end_sub)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	var b1 := _button("Rever cinemática", 190.0)
	b1.pressed.connect(func() -> void: replay_pressed.emit())
	hb.add_child(b1)
	var b2 := _button("Nova partida", 170.0)
	b2.pressed.connect(func() -> void: new_match_pressed.emit())
	hb.add_child(b2)


# ---------------------------------------------------------------- atualização

func update(state: MatchState, mode: String) -> void:
	var u := state.active()
	if u.is_empty():
		return
	var team: Color = GameData.TEAM_COLORS[u["player"]]
	top_label.text = "Rodada %d · Turno %d · Vez do %s" % [state.round_no, state.turn_no, GameData.TEAM_NAMES[u["player"]]]
	top_label.add_theme_color_override("font_color", team)

	for c in queue_box.get_children():
		queue_box.remove_child(c)
		c.queue_free()
	var first := true
	for id in state.upcoming(11):
		var o: Dictionary = state.units[id]
		var col: Color = GameData.TEAM_COLORS[o["player"]]
		var chip := _panel(col if first else col.darkened(0.6), 5)
		chip.add_child(_label(GameData.CLASSES[o["cls"]]["sigla"], 13, Color(0.04, 0.04, 0.07) if first else col.lightened(0.2)))
		queue_box.add_child(chip)
		first = false

	unit_name.text = state.display_name(u)
	unit_name.add_theme_color_override("font_color", team)
	hp_bar.max_value = u["max_hp"]
	hp_bar.value = u["hp"]
	hp_fill.bg_color = team
	var status := ""
	if u["muralha"]:
		status += " · Muralha"
	if u["mov_turno"] == 0:
		status += " · Enraizado"
	unit_info.text = "Vida %d/%d · Movimento %d · Iniciativa %d%s" % [u["hp"], u["max_hp"], u["mov_turno"], u["ini"], status]

	btn_move.disabled = state.moved
	btn_move.set_pressed_no_signal(mode == "move")
	_ab_ids = GameData.CLASSES[u["cls"]]["habilidades"]
	for i in 2:
		var ab_id: String = _ab_ids[i]
		var ab: Dictionary = GameData.ABILITIES[ab_id]
		var cd := state.cooldown(u, ab_id)
		var b: Button = btn_abs[i]
		b.text = "%d · %s%s" % [i + 1, ab["nome"], ("  (recarga %d)" % cd) if cd > 0 else ""]
		b.disabled = not state.can_use(u, ab_id)
		b.set_pressed_no_signal(mode == "ab:" + ab_id)
		b.tooltip_text = ab["desc"]

	if mode.begins_with("ab:"):
		var ab_sel: Dictionary = GameData.ABILITIES[mode.substr(3)]
		desc_label.text = "%s: %s" % [ab_sel["nome"], ab_sel["desc"]]
		hint_label.text = "Clique num quadrado vermelho para usar %s. Botão direito cancela." % ab_sel["nome"]
	elif mode == "move":
		desc_label.text = "Mova e use uma habilidade, em qualquer ordem. O turno acaba sozinho quando as duas coisas forem feitas."
		hint_label.text = "Clique num quadrado azul para mover. Teclas 1 e 2 escolhem habilidades."
	else:
		desc_label.text = "Escolha uma habilidade (1 ou 2) ou encerre o turno."
		hint_label.text = "Escolha uma habilidade ou encerre o turno."


func _show_desc(idx: int) -> void:
	if idx < _ab_ids.size():
		var ab: Dictionary = GameData.ABILITIES[_ab_ids[idx]]
		desc_label.text = "%s: %s" % [ab["nome"], ab["desc"]]


func add_log(line: String) -> void:
	log_lines.append(line)
	if log_lines.size() > 9:
		log_lines.pop_front()
	log_label.text = "\n".join(PackedStringArray(log_lines))


func set_gameplay_visible(on: bool) -> void:
	top.visible = on
	bottom.visible = on
	log_panel.visible = on
	hint_label.visible = on


func set_cinematic(on: bool) -> void:
	set_gameplay_visible(not on)
	skip_btn.visible = on
	var h := get_viewport().get_visible_rect().size.y * 0.11 if on else 0.0
	var tw := create_tween()
	tw.tween_property(bar_top, "offset_bottom", h, 0.6)
	tw.parallel().tween_property(bar_bot, "offset_top", -h, 0.6)


func show_caption(big: String, small: String) -> void:
	caption_big.text = big
	caption_small.text = small
	caption_box.visible = true


func hide_caption() -> void:
	caption_box.visible = false


func final_flash(on: bool) -> void:
	flash_label.visible = on


func show_end(title: String, sub: String, color: Color) -> void:
	set_gameplay_visible(false)
	end_title.text = title
	end_title.add_theme_color_override("font_color", color)
	end_sub.text = sub
	end_panel.visible = true


func hide_end() -> void:
	end_panel.visible = false
