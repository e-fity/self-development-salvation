extends Control
## 标题页：开始 / 继续 / 退出
## 继续按钮只在有通关记录时可用（读 Save.data）

const LEVEL_SCENE := "res://scenes/levels/level.tscn"

var _continue_btn: Button
var _start_btn: Button
var _settings_open := false


func _ready() -> void:
	_build()
	_report_state()
	Audio.hook_buttons(self)
	Audio.start_music()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 夜色底
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.043, 0.055, 0.086)
	add_child(bg)

	# 霓虹装饰：两条细竖线 + 一道地平线
	for x in [430.0, 1490.0]:
		var bar := ColorRect.new()
		bar.position = Vector2(x, 250)
		bar.size = Vector2(2, 520)
		bar.color = Color(0.184, 0.42, 0.847, 0.35)
		add_child(bar)

	var horizon := ColorRect.new()
	horizon.position = Vector2(430, 700)
	horizon.size = Vector2(1062, 2)
	horizon.color = Color(0.941, 0.541, 0.141, 0.35)
	add_child(horizon)

	var box := VBoxContainer.new()
	box.position = Vector2(620, 300)
	box.custom_minimum_size = Vector2(680, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	add_child(box)

	var title := Label.new()
	title.text = "自我开发——拯救"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.90, 0.93, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.text = "Self-Development: Salvation  ·  竖切片"
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.55, 0.60, 0.72))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	box.add_child(gap)

	_start_btn = _make_button("开始游戏", 26, Color(0.184, 0.42, 0.847))
	_start_btn.pressed.connect(_on_start)
	box.add_child(_start_btn)

	_continue_btn = _make_button("继续", 22, Color(0.16, 0.18, 0.24))
	_continue_btn.pressed.connect(_on_start)
	box.add_child(_continue_btn)

	var settings_btn := _make_button("设置", 22, Color(0.16, 0.18, 0.24))
	settings_btn.pressed.connect(_on_settings)
	box.add_child(settings_btn)

	var quit := _make_button("退出", 22, Color(0.16, 0.18, 0.24))
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)

	var foot := Label.new()
	foot.text = "v0.2 灰盒 M1"
	foot.add_theme_font_size_override("font_size", 16)
	foot.add_theme_color_override("font_color", Color(0.38, 0.42, 0.52))
	foot.position = Vector2(0, 1000)
	foot.size = Vector2(1920, 30)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(foot)

	_start_btn.grab_focus()


func _make_button(text: String, font_size: int, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 62)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", font_size)

	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(10)

	var hover := StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.18)
	hover.set_corner_radius_all(10)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b


## 有通关记录时，「继续」显示存档摘要
func _report_state() -> void:
	var clears := int(Save.data.get("clears", 0))
	if clears <= 0:
		_continue_btn.text = "继续（暂无记录）"
		_continue_btn.disabled = true
		return
	var grade := String(Save.data.get("best_grade", "—"))
	var gold := int(Save.data.get("gold", 0))
	_continue_btn.text = "继续  ·  最好 %s  ·  %d 金币  ·  第 %d 次" % [grade, gold, clears]


func _on_start() -> void:
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _on_settings() -> void:
	# 设置面板是模态的：期间禁用标题按钮，避免 Enter 触到仍有焦点的「开始」
	_settings_open = true
	_start_btn.disabled = true
	_continue_btn.disabled = true
	var panel := preload("res://scenes/ui/settings_panel.gd").new()
	panel.closed.connect(_on_settings_closed)
	add_child(panel)


func _on_settings_closed() -> void:
	_settings_open = false
	_start_btn.disabled = false
	_report_state()
	_start_btn.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _settings_open:
		return
	if event.is_action_pressed("ui_accept"):
		_on_start()
