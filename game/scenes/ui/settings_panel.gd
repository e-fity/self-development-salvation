extends CanvasLayer
## 设置面板：音乐/音效音量、震屏强度、伤害数字、教学提示
## 改一项立刻生效，关闭时统一写盘（拖动滑条时不写文件）

signal closed

const PANEL_W := 600.0

var _value_labels := {}
var _sliders := {}
var _checks := {}


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Audio.hook_buttons(self)


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.position = Vector2(-PANEL_W * 0.5, -300)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	margin.add_child(box)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_slider_row(box, "音乐音量", "bgm", 100.0, 0.01)
	_slider_row(box, "音效音量", "sfx", 100.0, 0.01)
	_slider_row(box, "震屏强度", "shake", 150.0, 0.01)
	_check_row(box, "显示伤害数字", "numbers")
	_check_row(box, "显示教学提示", "tutorial")

	var back := Button.new()
	back.text = "返回"
	back.custom_minimum_size = Vector2(0, 52)
	back.pressed.connect(_close)
	box.add_child(back)


## min/max 是滑条范围（0–100 之类），存盘值 = 滑条值 * scale
func _slider_row(
		parent: VBoxContainer,
		text: String,
		key: String,
		max_value: float,
		scale: float
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = text
	name_label.custom_minimum_size = Vector2(150, 0)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = max_value
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(260, 0)
	slider.value = float(Save.get_setting(key, 1.0)) / scale
	row.add_child(slider)
	_sliders[key] = slider

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	_value_labels[key] = value_label

	var refresh := func(v: float) -> void:
		var stored := v * scale
		Save.set_setting(key, stored)
		Settings.apply()
		_refresh_label(key, stored)
	slider.value_changed.connect(refresh)
	_refresh_label(key, slider.value * scale)


func _refresh_label(key: String, stored: float) -> void:
	var label: Label = _value_labels[key]
	if key == "shake":
		label.text = "%d%%" % int(round(stored * 100.0))
	else:
		label.text = "%d%%" % int(round(stored * 100.0))


func _check_row(parent: VBoxContainer, text: String, key: String) -> void:
	var check := CheckButton.new()
	check.text = text
	check.button_pressed = bool(Save.get_setting(key, true))
	check.toggled.connect(func(on: bool) -> void:
		Save.set_setting(key, on)
		Settings.apply())
	parent.add_child(check)
	_checks[key] = check


func _close() -> void:
	Save.save_data()
	Settings.apply()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_close()
