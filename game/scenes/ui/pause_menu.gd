extends CanvasLayer
## 暂停菜单：Esc 呼出 / 再按关闭
## 结算页也是 paused=true，那种情况下本菜单不抢 Esc

const TITLE_SCENE := "res://scenes/ui/title.tscn"

var _open := false
var _settings_open := false
var _first_button: Button


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Audio.hook_buttons(self)
	visible = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.6)
	add_child(shade)

	var panel := PanelContainer.new()
	panel.position = Vector2(660, 290)
	panel.custom_minimum_size = Vector2(600, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.97)
	style.border_color = Color(0.184, 0.42, 0.847)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "暂停"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	box.add_child(gap)

	_first_button = _make_button("继续游戏", Color(0.184, 0.42, 0.847))
	_first_button.pressed.connect(_close)
	box.add_child(_first_button)

	var restart := _make_button("重新开始", Color(0.16, 0.18, 0.24))
	restart.pressed.connect(_on_restart)
	box.add_child(restart)

	var settings_btn := _make_button("设置", Color(0.16, 0.18, 0.24))
	settings_btn.pressed.connect(_on_settings)
	box.add_child(settings_btn)

	var to_title := _make_button("返回标题", Color(0.16, 0.18, 0.24))
	to_title.pressed.connect(_on_title)
	box.add_child(to_title)

	var quit := _make_button("退出游戏", Color(0.16, 0.18, 0.24))
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

	var hint := Label.new()
	hint.text = "Esc 关闭"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.45, 0.49, 0.58))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _make_button(text: String, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 56)
	b.add_theme_font_size_override("font_size", 21)

	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(9)

	var hover := StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.18)
	hover.set_corner_radius_all(9)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	# 设置面板开着时，Esc 归它管
	if _settings_open:
		return
	# 树已被别人暂停（结算页）时不要抢输入
	if get_tree().paused and not _open:
		return
	get_viewport().set_input_as_handled()
	_toggle()


func _toggle() -> void:
	_open = not _open
	visible = _open
	get_tree().paused = _open
	if _open:
		_first_button.grab_focus()


func _close() -> void:
	_open = false
	visible = false
	get_tree().paused = false


func _on_restart() -> void:
	_close()
	get_tree().reload_current_scene()


## 设置面板盖在暂停菜单上；关掉后回到暂停菜单（树仍保持暂停）
func _on_settings() -> void:
	_settings_open = true
	visible = false
	var panel := preload("res://scenes/ui/settings_panel.gd").new()
	add_child(panel)
	panel.closed.connect(func() -> void:
		_settings_open = false
		visible = _open
		_first_button.grab_focus())


func _on_title() -> void:
	_close()
	get_tree().change_scene_to_file(TITLE_SCENE)
