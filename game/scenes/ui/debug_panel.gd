extends CanvasLayer
## 调试面板（灰盒期专用）：F1 显示 / 隐藏
## F2 无敌 · F3 秒杀最近敌人 · F4 传送到 Boss 前 · F5 冻结 AI · F6 碰撞形状
## `（反引号）打开控制台：god / freeze / kill / warp <x> / help
## 滑条改的是 Fx 里的倍率，改完立即生效，不用重启

var _panel: PanelContainer
var _stop_label: Label
var _shake_label: Label
var _numbers_box: CheckBox
var _status_label: Label
var _console: LineEdit
var _console_log: Label
var _console_open := false
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

	# 调试快捷键提示
	var hint := Label.new()
	hint.text = "F2 无敌 · F3 秒杀 · F4 到 Boss · F5 冻结 AI · F6 判定盒 · ` 控制台"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	box.add_child(hint)

	_console_log = Label.new()
	_console_log.add_theme_font_size_override("font_size", 12)
	_console_log.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	box.add_child(_console_log)

	_console = LineEdit.new()
	_console.visible = false
	_console.placeholder_text = "god / freeze / kill / warp <x> / help"
	_console.custom_minimum_size = Vector2(320, 26)
	_console.add_theme_font_size_override("font_size", 14)
	_console.text_submitted.connect(_on_command)
	box.add_child(_console)

	_player = get_tree().get_first_node_in_group("player")
	_update_labels()


func _process(_delta: float) -> void:
	if _status_label == null or not is_instance_valid(_player):
		return
	var state_name: String = _player.STATE_NAMES[_player.state]
	_status_label.text = "状态 %s   闪避 %.1fs   橙闪 %.1fs\n无敌 %s   冻结 %s   判定盒 %s" % [
		state_name, _player.dodge_cd, _player.dash_cd,
		_on_off(Debug.invincible), _on_off(Debug.freeze_ai), _on_off(Debug.hitboxes_visible)]


func _on_off(on: bool) -> String:
	return "开" if on else "关"


func _update_labels() -> void:
	_stop_label.text = "命中停顿  ×%.2f" % Fx.hitstop_scale
	_shake_label.text = "震屏      ×%.2f（设置 %.0f%%）" % [Fx.shake_tune, Fx.shake_scale * 100.0]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F1:
			visible = not visible
		KEY_F2:
			Debug.toggle_invincible()
		KEY_F3:
			_console_log.text = Debug.kill_nearest()
		KEY_F4:
			_console_log.text = Debug.warp_to_boss()
		KEY_F5:
			Debug.toggle_freeze_ai()
		KEY_F6:
			_console_log.text = Debug.toggle_hitboxes()
		_:
			return
	get_viewport().set_input_as_handled()


## 控制台：` 开合，Esc 关闭；输入在 LineEdit 里，不抢游戏内的单键操作
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_QUOTELEFT:
		_toggle_console()
		get_viewport().set_input_as_handled()
	elif _console_open and event.keycode == KEY_ESCAPE:
		_toggle_console()
		get_viewport().set_input_as_handled()


func _toggle_console() -> void:
	_console_open = not _console_open
	_console.visible = _console_open
	if _console_open:
		visible = true
		_console.clear()
		_console.grab_focus()
	else:
		_console.release_focus()
		get_viewport().gui_release_focus()


func _on_command(text: String) -> void:
	var msg := Debug.run_command(text)
	if not msg.is_empty():
		_console_log.text = msg
	_console.clear()
	_console.grab_focus()
