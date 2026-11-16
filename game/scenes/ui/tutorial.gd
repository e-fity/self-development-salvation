extends CanvasLayer
## 教学浮层：按推进位置依次给一句提示，每条只出现一次
## 不用弹窗、不打断操作——底部一条半透明提示带，3 秒后自己淡出

const HOLD := 3.0

var _panel: PanelContainer
var _label: Label
var _queue: Array[Dictionary] = []
var _busy := false
var _shown: Dictionary = {}
var _player: Node


func _ready() -> void:
	layer = 40
	_build()
	visible = false


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(560, 890)
	_panel.custom_minimum_size = Vector2(800, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.86)
	style.border_color = Color(0.184, 0.42, 0.847, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.98))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_label)


func _process(_delta: float) -> void:
	# 设置里关掉教学就整层不工作
	if not Settings.tutorial_enabled():
		visible = false
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return

	var x: float = _player.global_position.x
	if x > 120.0:
		_hint("move", "A / D 移动 · 空格 跳跃（可二段跳）")
	if x > 300.0:
		_hint("attack", "鼠标左键 连击 · 空中还能再打两下")
	if x > 520.0:
		_hint("dodge", "Shift 闪避 · 前 3 帧无敌")
	if x > 1350.0:
		_hint("skills", "K 橙闪突进 · L 逆鳞范围 · I 能量满时放零点")
	if int(_player.get("hits_taken")) > 0:
		_hint("hurt", "被击中后有一小段无敌时间——先拉开，再反击")
	# Boss 提示按距离触发，不能按「场景里有没有 Boss」——Boss 一开局就在场景里
	var boss := get_tree().get_first_node_in_group("boss")
	if boss != null and absf(boss.global_position.x - x) < 520.0:
		_hint("boss", "夜巡出招前会亮红光，那就是可以闪的时机")


func _hint(id: String, text: String) -> void:
	if _shown.has(id):
		return
	_shown[id] = true
	_queue.append({"text": text})
	_pump()


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var item: Dictionary = _queue.pop_front()
	_label.text = String(item["text"])
	visible = true
	_panel.modulate.a = 0.0

	var fade_in := create_tween()
	fade_in.tween_property(_panel, "modulate:a", 1.0, 0.2)
	await fade_in.finished
	await get_tree().create_timer(HOLD, true, false, true).timeout

	var fade_out := create_tween()
	fade_out.tween_property(_panel, "modulate:a", 0.0, 0.25)
	await fade_out.finished

	visible = false
	_busy = false
	_pump()
