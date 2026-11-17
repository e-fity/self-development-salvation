extends CanvasLayer
## 教学浮层：按推进位置依次给一句提示，每条只出现一次
## 不用弹窗、不打断操作——底部一条半透明提示带，3 秒后自己淡出

const HOLD := 3.0

## 提示触发位置：跟关卡布局绑定，挪关卡时改这里（Boss 提示改用 boss.json 的 engage_range）
const HINT_MOVE_X := 120.0
const HINT_ATTACK_X := 300.0
const HINT_DODGE_X := 520.0
const HINT_SKILL_X := 1350.0

var _panel: PanelContainer
var _label: Label
var _queue: Array[Dictionary] = []
var _busy := false
var _shown: Dictionary = {}
var _player: Node
var _boss: Node


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
	if x > HINT_MOVE_X:
		_hint("move", "A / D 移动 · 空格 跳跃（可二段跳）")
	if x > HINT_ATTACK_X:
		_hint("attack", "鼠标左键 连击 · 空中还能再打两下")
	if x > HINT_DODGE_X:
		_hint("dodge", "Shift 闪避 · 前 3 帧无敌")
	if x > HINT_SKILL_X:
		_hint("skills", "K 橙闪突进 · L 逆鳞范围击退 · I 能量满时放零点")
	if int(_player.get("hits_taken")) > 0:
		_hint("hurt", "被击中后有一小段无敌时间——先拉开，再反击")
	# Boss 提示按距离触发，不能按「场景里有没有 Boss」——Boss 一开局就在场景里
	if _boss == null:
		_boss = get_tree().get_first_node_in_group("boss")
	var engage := float(Data.num(Data.boss, "engage_range", 520.0))
	if _boss != null and absf(_boss.global_position.x - x) < engage:
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
