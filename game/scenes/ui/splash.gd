extends Control
## 启动页：程序化雨幕 + 标题 + 「按任意键进入」。
## 任意键 / 鼠标点击 / 手柄键进入标题菜单；6 秒无操作自动进入。

const TITLE_SCENE := "res://scenes/ui/title.tscn"
const FALLBACK_VERSION := "0.2.0"
const AUTO_ADVANCE := 6.0
const RAIN_COUNT := 110
const DESIGN_SIZE := Vector2(1920.0, 1080.0)

var _elapsed := 0.0
var _leaving := false
var _hint: Label
var _rain_x := PackedFloat32Array()
var _rain_y := PackedFloat32Array()
var _rain_len := PackedFloat32Array()
var _rain_speed := PackedFloat32Array()
var _rain_alpha := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.seed = 20261120
	_build()
	_spawn_rain()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.45)


func _build() -> void:
	var top := Label.new()
	top.name = "TitleTop"
	_place(top, Rect2(0, 296, DESIGN_SIZE.x, 92), 58, Color(0.86, 0.90, 0.96))
	top.text = "自我开发"
	add_child(top)

	var main := Label.new()
	main.name = "TitleMain"
	_place(main, Rect2(0, 378, DESIGN_SIZE.x, 156), 108, Color(0.941, 0.541, 0.141))
	main.text = "拯救"
	add_child(main)

	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.position = Vector2(860, 552)
	rule.size = Vector2(200, 2)
	rule.color = Color(0.26, 0.52, 0.92, 0.5)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	var sub := Label.new()
	sub.name = "Subtitle"
	_place(sub, Rect2(0, 570, DESIGN_SIZE.x, 34), 20, Color(0.55, 0.62, 0.72))
	sub.text = "S A L V A T I O N · 灰盒 M1"
	add_child(sub)

	_hint = Label.new()
	_hint.name = "Hint"
	_place(_hint, Rect2(0, 900, DESIGN_SIZE.x, 40), 24, Color(0.88, 0.92, 0.98))
	_hint.text = "按任意键进入"
	add_child(_hint)

	var ver := Label.new()
	ver.name = "Version"
	_place(ver, Rect2(44, 1026, 720, 24), 15, Color(0.40, 0.46, 0.55))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ver.text = "v%s · Godot 4.7" % str(
			ProjectSettings.get_setting("application/config/version", FALLBACK_VERSION))
	add_child(ver)

	var foot := Label.new()
	foot.name = "Footer"
	_place(foot, Rect2(1160, 1026, 716, 24), 15, Color(0.40, 0.46, 0.55))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.text = "A/D 移动 · Shift 闪避 · K/L/I 技能"
	add_child(foot)


func _place(label: Label, rect: Rect2, font_size: int, color: Color) -> void:
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _spawn_rain() -> void:
	for _i in RAIN_COUNT:
		_rain_x.append(_rng.randf_range(0.0, DESIGN_SIZE.x))
		_rain_y.append(_rng.randf_range(-200.0, DESIGN_SIZE.y))
		_rain_len.append(_rng.randf_range(16.0, 74.0))
		_rain_speed.append(_rng.randf_range(260.0, 720.0))
		_rain_alpha.append(_rng.randf_range(0.06, 0.26))


func _process(delta: float) -> void:
	if _leaving:
		return
	_elapsed += delta
	for i in _rain_y.size():
		_rain_y[i] += _rain_speed[i] * delta
		_rain_x[i] -= 18.0 * delta
		if _rain_y[i] > DESIGN_SIZE.y + 60.0:
			_rain_y[i] = -_rain_len[i]
			_rain_x[i] = _rng.randf_range(0.0, DESIGN_SIZE.x + 60.0)
	if _hint != null:
		_hint.modulate.a = 0.78 + 0.22 * sin(_elapsed * 3.2)
	queue_redraw()
	if _elapsed >= AUTO_ADVANCE:
		_go_title()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), Color(0.024, 0.031, 0.047))
	# 中部冷色氛围：用细条叠出上下渐隐的软光，避免硬边色块
	for i in 28:
		var y := 120.0 + 30.0 * float(i)
		var t := ((y + 15.0) - 540.0) / 440.0
		var glow := maxf(0.0, 0.11 * (1.0 - t * t))
		draw_rect(Rect2(0, y, DESIGN_SIZE.x, 30.0), Color(0.10, 0.18, 0.30, glow))
	for i in _rain_y.size():
		var start := Vector2(_rain_x[i], _rain_y[i])
		var end := start + Vector2(-3.0, _rain_len[i])
		draw_line(start, end, Color(0.50, 0.68, 0.90, _rain_alpha[i]), 1.0)


func _input(event: InputEvent) -> void:
	if _leaving:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		pressed = event.pressed
	elif event is InputEventJoypadButton:
		pressed = event.pressed
	if pressed:
		get_viewport().set_input_as_handled()
		_go_title()


func _go_title() -> void:
	if _leaving:
		return
	_leaving = true
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.28)
	await tween.finished
	get_tree().change_scene_to_file(TITLE_SCENE)
