extends CanvasLayer
## 手感调试面板（灰盒期专用）：F1 显示 / 隐藏
## 滑条改的是 Fx 里的倍率，改完立即生效，不用重启

var _panel: PanelContainer
var _stop_label: Label
var _shake_label: Label
var _numbers_box: CheckBox
var _status_label: Label
var _player: Node


func _ready() -> void:
	layer = 100
	_build()
	visible = true


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(1520, 20)
	_panel.custom_minimum_size = Vector2(360, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.85)
	style.border_color = Color(0.95, 0.72, 0.15, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "手感调试（F1 隐藏）"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.82, 0.2))
	box.add_child(title)

	# 命中停顿
	_stop_label = Label.new()
	_stop_label.add_theme_font_size_override("font_size", 15)
	box.add_child(_stop_label)
	var stop_slider := HSlider.new()
	stop_slider.min_value = 0.0
	stop_slider.max_value = 3.0
	stop_slider.step = 0.05
	stop_slider.value = Fx.hitstop_scale
	stop_slider.custom_minimum_size = Vector2(320, 20)
	stop_slider.value_changed.connect(func(v: float) -> void:
		Fx.hitstop_scale = v
		_update_labels())
	box.add_child(stop_slider)

	# 震屏
	_shake_label = Label.new()
	_shake_label.add_theme_font_size_override("font_size", 15)
	box.add_child(_shake_label)
	var shake_slider := HSlider.new()
	shake_slider.min_value = 0.0
	shake_slider.max_value = 3.0
	shake_slider.step = 0.05
	shake_slider.value = Fx.shake_tune
	shake_slider.custom_minimum_size = Vector2(320, 20)
	shake_slider.value_changed.connect(func(v: float) -> void:
		Fx.shake_tune = v
		_update_labels())
	box.add_child(shake_slider)

	# 伤害数字开关
	_numbers_box = CheckBox.new()
	_numbers_box.text = "显示伤害数字"
	_numbers_box.button_pressed = Fx.numbers_enabled
	_numbers_box.add_theme_font_size_override("font_size", 15)
	_numbers_box.toggled.connect(func(on: bool) -> void:
		Fx.numbers_enabled = on)
	box.add_child(_numbers_box)

	# 状态 / 冷却
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1))
	box.add_child(_status_label)

	_player = get_tree().get_first_node_in_group("player")
	_update_labels()


func _process(_delta: float) -> void:
	if _status_label == null or not is_instance_valid(_player):
		return
	var state_name: String = _player.STATE_NAMES[_player.state]
	_status_label.text = "状态 %s   闪避 %.1fs   橙闪 %.1fs" % [
		state_name, _player.dodge_cd, _player.dash_cd]


func _update_labels() -> void:
	_stop_label.text = "命中停顿  ×%.2f" % Fx.hitstop_scale
	_shake_label.text = "震屏      ×%.2f（设置 %.0f%%）" % [Fx.shake_tune, Fx.shake_scale * 100.0]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		visible = not visible
		get_viewport().set_input_as_handled()
