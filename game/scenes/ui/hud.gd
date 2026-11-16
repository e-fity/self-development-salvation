extends CanvasLayer
## 灰盒 HUD：左上血条 + Boss 血条 + 胜利提示

const BAR_W := 314.0
const BOSS_BAR_W := 640.0

var _player: Node
var _fill: ColorRect
var _label: Label

var _boss_bar: ColorRect
var _boss_bg: ColorRect
var _boss_label: Label
var _victory: Label
var _combo_label: Label
var _boss_seen := false
var _victory_time := 0.0


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	layer = 10

	var bg := ColorRect.new()
	bg.position = Vector2(24, 64)
	bg.size = Vector2(BAR_W + 6, 24)
	bg.color = Color(0.04, 0.05, 0.07, 0.85)
	add_child(bg)

	_fill = ColorRect.new()
	_fill.position = Vector2(27, 67)
	_fill.size = Vector2(BAR_W, 18)
	_fill.color = Color(0.85, 0.22, 0.26)
	add_child(_fill)

	_label = Label.new()
	_label.position = Vector2(24, 28)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.9, 0.93, 1.0))
	add_child(_label)

	# Boss 血条（屏幕上方居中）
	_boss_bg = ColorRect.new()
	_boss_bg.position = Vector2(640, 40)
	_boss_bg.size = Vector2(BOSS_BAR_W + 6, 22)
	_boss_bg.color = Color(0.04, 0.05, 0.07, 0.85)
	_boss_bg.visible = false
	add_child(_boss_bg)

	_boss_bar = ColorRect.new()
	_boss_bar.position = Vector2(643, 43)
	_boss_bar.size = Vector2(BOSS_BAR_W, 16)
	_boss_bar.color = Color(0.72, 0.18, 0.24)
	_boss_bar.visible = false
	add_child(_boss_bar)

	_boss_label = Label.new()
	_boss_label.position = Vector2(640, 12)
	_boss_label.add_theme_font_size_override("font_size", 18)
	_boss_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2))
	_boss_label.visible = false
	add_child(_boss_label)

	_victory = Label.new()
	_victory.position = Vector2(700, 470)
	_victory.add_theme_font_size_override("font_size", 84)
	_victory.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_victory.text = "VICTORY"
	_victory.visible = false
	add_child(_victory)

	# 连击数（右上）
	_combo_label = Label.new()
	_combo_label.position = Vector2(1600, 64)
	_combo_label.size = Vector2(280, 60)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label.add_theme_font_size_override("font_size", 40)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	_combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_combo_label.add_theme_constant_override("outline_size", 8)
	_combo_label.visible = false
	add_child(_combo_label)


func _process(delta: float) -> void:
	if is_instance_valid(_player):
		var ratio: float = clampf(_player.hp / _player.max_hp, 0.0, 1.0)
		_fill.size.x = BAR_W * ratio
		_label.text = "HP  %d / %d" % [int(ceil(_player.hp)), int(_player.max_hp)]

		if _player.combo >= 2:
			_combo_label.visible = true
			_combo_label.text = "%d 连击" % _player.combo
		else:
			_combo_label.visible = false

	_update_boss()

	if _victory_time > 0.0:
		_victory_time -= delta
		_victory.visible = true
		if _victory_time <= 0.0:
			_victory.visible = false


func _update_boss() -> void:
	var boss := get_tree().get_first_node_in_group("boss")

	# Boss 从关卡一开始就在场，但血条要等它「醒来」才出现，否则开局就剧透
	var engaged: bool = boss != null and is_instance_valid(boss) and bool(boss.active)

	if engaged:
		_boss_seen = true
		_boss_bg.visible = true
		_boss_bar.visible = true
		_boss_label.visible = true
		var ratio: float = clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		_boss_bar.size.x = BOSS_BAR_W * ratio
		_boss_label.text = "夜巡    阶段 %d / 3" % boss.phase
	elif _boss_seen:
		# Boss 被移除 = 打死了
		_boss_seen = false
		_boss_bg.visible = false
		_boss_bar.visible = false
		_boss_label.visible = false
		_victory_time = 3.0
