extends Node
## 存档系统：默认 user://save.json
## 三条硬要求（PRD 8.4 / 14-9）：
##   1. 带 version 字段，预留迁移
##   2. 原子写入：先写 save.tmp，再替换 save.json，避免写一半损坏
##   3. 文件损坏 / 缺失时回落到默认值，绝不崩
##
## 调试便利：设置环境变量 SALVATION_SAVE_DIR 可把存档改到指定目录
## （沙箱里 user:// 不可写时，用它把存档指到工程内）。

const VERSION := 1
const SAVE_NAME := "save.json"
const TMP_NAME := "save.tmp"

## 评价高低：S > A > B
const GRADE_RANK := {"": 0, "B": 1, "A": 2, "S": 3}

var data: Dictionary = {}

var _dir := "user://"
var _save_path := "user://save.json"
var _tmp_path := "user://save.tmp"


func _ready() -> void:
	_resolve_paths()
	load_data()


func _resolve_paths() -> void:
	var override := OS.get_environment("SALVATION_SAVE_DIR").strip_edges()
	if override.is_empty():
		return
	_dir = override.replace("\\", "/").trim_suffix("/") + "/"
	_save_path = _dir + SAVE_NAME
	_tmp_path = _dir + TMP_NAME


func abs_save_path() -> String:
	return ProjectSettings.globalize_path(_save_path)


func abs_tmp_path() -> String:
	return ProjectSettings.globalize_path(_tmp_path)


func default_data() -> Dictionary:
	return {
		"version": VERSION,
		"gold": 0,
		"best_grade": "",
		"best_time": 0.0,
		"clears": 0,
		"settings": {"bgm": 1.0, "sfx": 1.0, "shake": 1.0, "numbers": true, "tutorial": true},
	}


func load_data() -> Dictionary:
	data = default_data()

	if not FileAccess.file_exists(_save_path):
		return data

	var f := FileAccess.open(_save_path, FileAccess.READ)
	if f == null:
		push_warning("[存档] 打不开存档，使用默认值")
		return data
	var text := f.get_as_text()
	f.close()

	# 用 JSON.new().parse() 而不是 parse_string()：后者会把「坏文件」当成引擎级错误刷屏，
	# 而坏档是可预期的情况，静默回落即可
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("[存档] 文件损坏（第 %d 行），使用默认值" % json.get_error_line())
		return data

	# 只认已知字段，旧档里多出来的键不会污染内存
	var loaded: Dictionary = json.data
	for key in data.keys():
		if loaded.has(key):
			data[key] = loaded[key]

	# settings 是嵌套字典：老档里可能缺键，缺的用默认值补齐，
	# 否则滑条会读到 null 把自己初始化成 0
	var loaded_settings: Dictionary = loaded.get("settings", {})
	var merged: Dictionary = data["settings"].duplicate()
	for key in loaded_settings.keys():
		if merged.has(key):
			merged[key] = loaded_settings[key]
	data["settings"] = merged

	data = _migrate(data)
	return data


## 版本迁移入口：以后加字段时在这里补
func _migrate(d: Dictionary) -> Dictionary:
	var version := int(d.get("version", 0))
	if version < 1:
		d["version"] = VERSION
	if version > VERSION:
		push_warning("[存档] 存档版本比游戏新（%d），按当前版本读取" % version)
		d["version"] = VERSION
	return d


func save_data() -> bool:
	data["version"] = VERSION

	var f := FileAccess.open(_tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[存档] 写不了临时文件：%s" % _tmp_path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	f.close()

	var dir := DirAccess.open(_dir)
	if dir == null:
		push_error("[存档] 打不开目录：%s" % _dir)
		return false

	# Windows 上不能覆盖已存在的文件，先删再改名；中间崩溃只会丢这一份新档，
	# 不会出现「写了一半的 save.json」
	if dir.file_exists(SAVE_NAME):
		dir.remove(SAVE_NAME)
	if dir.rename(TMP_NAME, SAVE_NAME) != OK:
		push_error("[存档] 替换存档失败")
		return false
	return true


## 一次通关后记账：金币累加、评价取最好、最快用时取最小
func record_run(time_s: float, grade: String, gold_earned: int) -> void:
	data["gold"] = int(data.get("gold", 0)) + gold_earned
	data["clears"] = int(data.get("clears", 0)) + 1

	var best_grade := String(data.get("best_grade", ""))
	if int(GRADE_RANK.get(grade, 0)) > int(GRADE_RANK.get(best_grade, 0)):
		data["best_grade"] = grade

	var best_time := float(data.get("best_time", 0.0))
	if best_time <= 0.0 or time_s < best_time:
		data["best_time"] = time_s

	save_data()


## 读一个设置项（存档里没有就用默认值）
func get_setting(key: String, fallback: Variant = null) -> Variant:
	var s: Dictionary = data.get("settings", {})
	return s.get(key, fallback)

## 只改内存，不写盘——滑条拖动时避免每帧写文件，关面板时统一 save_data()
func set_setting(key: String, value: Variant) -> void:
	var s: Dictionary = data.get("settings", {})
	s[key] = value
	data["settings"] = s
