extends Node
## 数值表加载器（autoload `Data`）
## 读 res://data/*.json；文件缺失、损坏、字段缺失都会静默回落到内置默认值，
## 所以删掉 data 目录游戏也能跑，只是调不了数值。

const PLAYER_PATH := "res://data/player.json"
const ENEMIES_PATH := "res://data/enemies.json"
const BOSS_PATH := "res://data/boss.json"

var player: Dictionary = {}
var enemies: Dictionary = {}
var boss: Dictionary = {}

## 内置默认值：与 data/*.json 初始内容一致，作为兜底
## 冒烟测试会断言两者的重叠字段同值（规约 DATA-6），改 JSON 时同步改这里
const DEFAULT_PLAYER := {
	"fps": 15.0,
	"stats": {"max_hp": 100.0, "attack_power": 12.0},
	"move": {"speed": 220.0, "jump_velocity": -520.0, "gravity": 1400.0,
		"max_jumps": 2, "second_jump_scale": 0.8},
	"combo_grace": 0.45,
	"feedback": {"hurt_knockback": 240.0, "hurt_invuln": 0.5,
		"respawn_delay": 1.5, "combo_reset": 3.0, "attack_move_scale": 0.55},
	"energy": {"max": 100.0, "on_hit": 6.0, "on_kill": 15.0, "on_damage": 10.0},
	"skill2": {"frames": 10, "startup": 3, "active": 1, "recover": 6,
		"radius": 120.0, "mult": 1.2, "knockback": 120.0,
		"cooldown": 10.0, "armor_time": 2.0, "hitstop": 0.04},
	"ultimate": {"frames": 24, "startup": 6, "active": 6, "recover": 12,
		"mult": 4.0, "combo_bonus": 0.005, "combo_bonus_cap": 1.0,
		"knockback": 160.0, "width": 4800.0, "height": 2400.0, "hitstop": 0.08},
	"attacks": [
		{"startup": 2, "active": 1, "recover": 3, "mult": 1.0, "knockback": 60.0},
		{"startup": 2, "active": 1, "recover": 3, "mult": 1.0, "knockback": 60.0},
		{"startup": 3, "active": 2, "recover": 3, "mult": 1.5, "knockback": 160.0},
	],
	"air_attack": {"startup": 2, "active": 2, "recover": 3, "mult": 1.0,
		"knockback": 40.0, "max_uses": 2, "land_lock": 0.15},
	"dodge": {"frames": 5, "invuln_from": 1, "invuln_to": 3, "distance": 160.0, "cooldown": 1.2},
	"dash": {"frames": 8, "invuln_from": 3, "invuln_to": 5, "distance": 220.0,
		"move_frames": 5, "cooldown": 6.0, "mult": 1.5, "knockback": 120.0},
}

const DEFAULT_ENEMIES := {
	"melee": {"name": "木桩", "max_hp": 40.0, "defense": 3.0, "damage": 8.0,
		"attack_range": 70.0, "attack_height": 200.0, "sight": 420.0, "move_speed": 95.0,
		"windup": 0.45, "cooldown": 1.6, "gravity": 1400.0, "juggle_gravity": 900.0,
		"launch_threshold": 120.0, "launch_velocity": -430.0, "gold": 8, "flash_time": 0.08},
}

const DEFAULT_BOSS := {
	"name": "夜巡", "max_hp": 600.0, "defense": 3.0, "gold": 50,
	"engage_range": 520.0, "phases": [0.66, 0.33],
	"phase_interval": [2.0, 1.6, 1.1], "windup_scale": [1.0, 1.0, 0.8],
	"transition_seconds": 1.0,
	"combo": {"telegraph": 0.6, "hits": 3, "damage": 10.0, "range": 120.0,
		"height": 160.0, "gap": 0.28, "tail": 0.2},
	"jump": {"telegraph": 0.5, "air_time": 0.45, "velocity_y": -700.0, "speed_x": 620.0,
		"damage": 14.0, "range": 140.0, "height": 180.0, "tail": 0.3},
	"summon": {"telegraph": 1.0, "offsets": [-280, 280], "tail": 0.4,
		"trigger_phase": 2, "chance": 0.45},
}


func _ready() -> void:
	reload()


## 改完 JSON 想热重载：控制台里 Data.reload() 即可（F5 重跑也会重新加载）
func reload() -> void:
	player = _load(PLAYER_PATH, DEFAULT_PLAYER)
	enemies = _load(ENEMIES_PATH, DEFAULT_ENEMIES)
	boss = _load(BOSS_PATH, DEFAULT_BOSS)


func _load(path: String, fallback: Dictionary) -> Dictionary:
	var base: Dictionary = fallback.duplicate(true)
	if not FileAccess.file_exists(path):
		push_warning("[数值] 找不到 %s，使用内置默认值" % path)
		return base

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[数值] 打不开 %s，使用内置默认值" % path)
		return base
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("[数值] %s 第 %d 行格式错误，使用内置默认值" % [path, json.get_error_line()])
		return base

	return _merge(base, json.data)


## 深合并：JSON 里缺的键保留默认值，多出来的键忽略。
## 类型不匹配时保留默认值并告警——若让标量覆盖字典，player.gd 里
## `var mv: Dictionary = ...` 会在运行时类型报错（审查报告 P1-3）。
func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	for key in over.keys():
		if not base.has(key):
			continue  # 只认已知字段（_comment 之类不会被读进来）
		base[key] = _merge_value(base[key], over[key], String(key))
	return base


func _merge_value(base: Variant, over: Variant, path: String) -> Variant:
	if typeof(base) == TYPE_DICTIONARY:
		if typeof(over) != TYPE_DICTIONARY:
			_warn_type_mismatch(path, base, over)
			return base
		return _merge(base, over)
	if typeof(base) == TYPE_ARRAY:
		if typeof(over) != TYPE_ARRAY:
			_warn_type_mismatch(path, base, over)
			return base
		return _merge_array(base, over, path)
	if typeof(base) == typeof(over):
		return over
	# JSON 的数字统一是 float，默认表里的整数键（max_jumps、gold…）允许整数化
	if _is_number(base) and _is_number(over):
		if typeof(base) == TYPE_FLOAT:
			return float(over)
		if float(over) == floorf(float(over)):
			return int(over)
	_warn_type_mismatch(path, base, over)
	return base


func _merge_array(base: Array, over: Array, path: String) -> Array:
	if base.size() != over.size():
		push_warning("[数值] %s 元素数 %d != %d，保留默认值" % [path, over.size(), base.size()])
		return base
	var result: Array = base.duplicate(true)
	for i in result.size():
		result[i] = _merge_value(result[i], over[i], "%s[%d]" % [path, i])
	return result


func _warn_type_mismatch(path: String, base: Variant, over: Variant) -> void:
	push_warning("[数值] %s 类型不匹配（期望 %s，实际 %s），保留默认值"
			% [path, type_string(typeof(base)), type_string(typeof(over))])


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


## 取一个数，类型不对就用兜底值（JSON 里手滑写成字符串时不至于崩）
func num(section: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = section.get(key, fallback)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	return fallback


func flag(section: Dictionary, key: String, fallback: bool) -> bool:
	var v: Variant = section.get(key, fallback)
	if typeof(v) == TYPE_BOOL:
		return v
	return fallback
