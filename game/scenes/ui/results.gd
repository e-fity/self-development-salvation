extends CanvasLayer
## 结算页：评价 S/A/B、用时、受伤、最高连击、金币
## 评价规则（PRD 1.5 的三维度加权，阈值按当前灰盒关卡调整）

var _stats := {}


func setup(stats: Dictionary) -> void:
	_stats = stats
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50
	# 记账：金币累加、评价取最好、最快用时取最小（内部原子写盘）
	Save.record_run(float(_stats.get("time", 0.0)), _grade(), int(_stats.get("gold", 0)))
	_build()
	Audio.play("victory", -4.0)
	Audio.hook_buttons(self)


func _build() -> void:
	var grade := _grade()
	var palette := {
		"S": Color(1.0, 0.82, 0.2),
		"A": Color(0.55, 0.85, 1.0),
		"B": Color(0.7, 0.72, 0.78),
	}
	var grade_color: Color = palette.get(grade, Color.WHITE)

	# 半透明黑底
	var shade := ColorRect.new()
	shade.size = Vector2(1920, 1080)
	shade.color = Color(0, 0, 0, 0.55)
	add_child(shade)

	var panel := PanelContainer.new()
	panel.position = Vector2(560, 250)
	panel.custom_minimum_size = Vector2(800, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.96)
	style.border_color = grade_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "关卡完成"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var grade_label := Label.new()
	grade_label.text = grade
	grade_label.add_theme_font_size_override("font_size", 110)
	grade_label.add_theme_color_override("font_color", grade_color)
	grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(grade_label)

	var time_s: float = _stats.get("time", 0.0)
	var time_text := (
		"%.1f 秒" % time_s
		if time_s < 60.0
		else "%d 分 %02d 秒" % [int(time_s) / 60, int(time_s) % 60]
	)
	var rows := [
		["用时", time_text],
		["受伤", "%d 次" % int(_stats.get("hits", 0))],
		["最高连击", "%d" % int(_stats.get("max_combo", 0))],
		["本局金币", "%d" % int(_stats.get("gold", 0))],
		["累计金币", "%d" % int(Save.data.get("gold", 0))],
		["最好评价", String(Save.data.get("best_grade", "—"))],
	]
	for row in rows:
		var line := Label.new()
		line.text = "%-8s %s" % [row[0], row[1]]
		line.add_theme_font_size_override("font_size", 22)
		line.add_theme_color_override("font_color", Color(0.82, 0.86, 0.95))
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)

	# 分项分展示出来，方便知道评级差在哪（也顺手用上 _score 的三个分项）
	var score := _score()
	var breakdown := Label.new()
	breakdown.text = "评分 %d · 时间 %d / 受伤 %d / 连击 %d" % [
		int(score["total"]), int(score["time"]), int(score["hits"]), int(score["combo"])]
	breakdown.add_theme_font_size_override("font_size", 18)
	breakdown.add_theme_color_override("font_color", Color(0.6, 0.66, 0.78))
	breakdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(breakdown)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	box.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	box.add_child(buttons)

	var again := Button.new()
	again.text = "再来一次"
	again.custom_minimum_size = Vector2(220, 56)
	again.add_theme_font_size_override("font_size", 22)
	again.process_mode = Node.PROCESS_MODE_ALWAYS
	again.pressed.connect(_on_again)
	buttons.add_child(again)

	var quit := Button.new()
	quit.text = "返回标题"
	quit.custom_minimum_size = Vector2(160, 56)
	quit.add_theme_font_size_override("font_size", 22)
	quit.process_mode = Node.PROCESS_MODE_ALWAYS
	quit.pressed.connect(_on_title)
	buttons.add_child(quit)


## 三维度加权：时间 40 + 受伤 35 + 连击 25
func _score() -> Dictionary:
	var time_s: float = _stats.get("time", 999.0)
	var hits: int = int(_stats.get("hits", 99))
	var combo: int = int(_stats.get("max_combo", 0))

	var time_score := 40.0 if time_s <= 150.0 else (24.0 if time_s <= 240.0 else 10.0)
	var hit_score := 35.0 if hits == 0 else (24.0 if hits <= 3 else 10.0)
	var combo_score := 25.0 if combo >= 30 else (17.0 if combo >= 15 else 8.0)

	return {
		"total": time_score + hit_score + combo_score,
		"time": time_score,
		"hits": hit_score,
		"combo": combo_score,
	}


func _grade() -> String:
	var total: float = _score()["total"]
	if total >= 90.0:
		return "S"
	if total >= 70.0:
		return "A"
	return "B"


func _on_again() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/title.tscn")
