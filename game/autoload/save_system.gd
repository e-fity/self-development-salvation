extends Node
## 存档系统：默认 user://save.json
## 四条硬要求（PRD 8.4 / 14-9）：
##   1. 带 version 字段，预留迁移
##   2. 原子写入：先写 save.tmp，旧档降级为 save.bak，再把 tmp 改名成主档
##   3. 主档损坏 / 缺失时回落到 save.bak，再不行才回默认值，绝不崩
##   4. 字段类型异常（如 settings 被写成字符串）按类型校验丢弃，不崩
##
## 调试便利：设置环境变量 SALVATION_SAVE_DIR 可把存档改到指定目录
## （沙箱里 user:// 不可写时，用它把存档指到工程内）。

const VERSION := 2
const SAVE_NAME := "save.json"
const TMP_NAME := "save.tmp"
const BAK_NAME := "save.bak"

## 评价高低：S > A > B
const GRADE_RANK := {"": 0, "B": 1, "A": 2, "S": 3}

var data: Dictionary = {}

## 只存在内存里的跳转意图：标题页按「继续」时写入，关卡 _ready 读完清空
var pending_checkpoint := -1

var _dir := "user://"
var _save_path := "user://save.json"
var _tmp_path := "user://save.tmp"
var _bak_path := "user://save.bak"


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
	_bak_path = _dir + BAK_NAME


## 测试与调试用：把存档路径转成绝对路径；游戏逻辑只用 _save_path 等内部路径
func abs_save_path() -> String:
	return ProjectSettings.globalize_path(_save_path)


func abs_bak_path() -> String:
	return ProjectSettings.globalize_path(_bak_path)


## 进行中的关卡进度：已到达的检查点下标，-1 表示没有进度
func checkpoint() -> int:
	var p: Variant = data.get("progress", {})
	if typeof(p) != TYPE_DICTIONARY:
		return -1
	return maxi(int(p.get("checkpoint", -1)), -1)


## 神龛（最后一个检查点）是否已经领过回满
func shrine_taken() -> bool:
	var p: Variant = data.get("progress", {})
	if typeof(p) != TYPE_DICTIONARY:
		return false
	return bool(p.get("shrine_taken", false))


func has_progress() -> bool:
	return checkpoint() >= 0


## 到达检查点立刻落盘：下次「继续」能回到这里
func save_progress(index: int, shrine: bool) -> void:
	_write_progress(index, shrine)
	save_data()


## 新开一局或通关后清空进度；save_now=false 时由调用方统一写盘
func reset_progress(save_now := true) -> void:
	_write_progress(-1, false)
	if save_now:
		save_data()


func _write_progress(index: int, shrine: bool) -> void:
	data["progress"] = {
		"checkpoint": maxi(index, -1),
		"shrine_taken": shrine,
	}


func default_data() -> Dictionary:
	return {
		"version": VERSION,
		"gold": 0,
		"best_grade": "",
		"best_time": 0.0,
		"clears": 0,
		"settings": {"bgm": 1.0, "sfx": 1.0, "shake": 1.0, "numbers": true, "tutorial": true},
		# 进行中的关卡进度：checkpoint 是已到达的检查点下标（-1 = 没有进度）
		"progress": {"checkpoint": -1, "shrine_taken": false},
	}


func load_data() -> Dictionary:
	data = default_data()

	var loaded := _read_json_file(_save_path)
	if loaded.is_empty():
		var backup := _read_json_file(_bak_path)
		if not backup.is_empty():
			push_warning("[存档] 主档不可用，已从 %s 恢复" % BAK_NAME)
			loaded = backup

	if not loaded.is_empty():
		_apply_loaded(loaded)
	data = _migrate(data)
	return data


## 读一个 JSON 对象；文件缺失、为空或损坏都返回 {}，由调用方决定回落顺序
func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[存档] 打不开 %s" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	if text.strip_edges().is_empty():
		return {}

	# 用 JSON.new().parse() 而不是 parse_string()：后者会把「坏文件」当成引擎级错误刷屏，
	# 而坏档是可预期的情况，静默回落即可
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("[存档] %s 损坏（第 %d 行），尝试备份" % [path, json.get_error_line()])
		return {}
	return json.data


func _apply_loaded(loaded: Dictionary) -> void:
	# 只认已知字段；类型不对的字段丢弃并用默认值，避免把 "abc" 写进 gold 之类
	for key in data.keys():
		if key == "settings" or key == "progress" or not loaded.has(key):
			continue
		data[key] = _typed_value(loaded[key], data[key], "顶层字段 %s" % key)

	if loaded.has("settings"):
		_apply_settings(loaded["settings"])
	if loaded.has("progress"):
		_apply_progress(loaded["progress"])


## settings 是嵌套字典：缺键补默认值，类型不对的键丢弃
func _apply_settings(incoming: Variant) -> void:
	if typeof(incoming) != TYPE_DICTIONARY:
		push_warning("[存档] settings 不是字典（%s），使用默认设置" % type_string(typeof(incoming)))
		return

	var merged: Dictionary = data["settings"].duplicate()
	for key in merged.keys():
		if not incoming.has(key):
			continue
		merged[key] = _typed_value(incoming[key], merged[key], "settings.%s" % key)
	data["settings"] = merged


## progress 是嵌套字典：缺键补默认值，类型不对的键丢弃
func _apply_progress(incoming: Variant) -> void:
	if typeof(incoming) != TYPE_DICTIONARY:
		push_warning("[存档] progress 不是字典（%s），使用默认进度" % type_string(typeof(incoming)))
		return
	if typeof(data.get("progress")) != TYPE_DICTIONARY:
		data["progress"] = default_data()["progress"]
	var merged: Dictionary = data["progress"]
	for key in merged.keys():
		if not incoming.has(key):
			continue
		merged[key] = _typed_value(incoming[key], merged[key], "progress.%s" % key)
	data["progress"] = merged


## 类型一致才接受；int/float 互认（JSON 数字都是 float）；其余保留默认值并告警
func _typed_value(value: Variant, base: Variant, label: String) -> Variant:
	if typeof(value) == typeof(base):
		return value
	if _is_number(value) and _is_number(base):
		if typeof(base) == TYPE_FLOAT:
			return float(value)
		if float(value) == floorf(float(value)):
			return int(value)
	push_warning("[存档] %s 类型错误（%s），使用默认值" % [label, type_string(typeof(value))])
	return base


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT


## 版本迁移入口：以后加字段时在这里补
func _migrate(d: Dictionary) -> Dictionary:
	var version := int(d.get("version", 0))
	if version < VERSION:
		d["version"] = VERSION
	if version > VERSION:
		push_warning("[存档] 存档版本比游戏新（%d），按当前版本读取" % version)
		d["version"] = VERSION

	# v1 → v2：旧档没有 progress 段，补默认值，不能因为缺键读成空进度
	var base: Dictionary = default_data()["progress"]
	var p: Variant = d.get("progress")
	if typeof(p) != TYPE_DICTIONARY:
		d["progress"] = base
	else:
		for key in base.keys():
			if not p.has(key):
				p[key] = base[key]
		d["progress"] = p
	return d


## 写入顺序：tmp → 旧档降级 bak → tmp 改名主档。任一步失败都保留可用的旧档。
func save_data() -> bool:
	data["version"] = VERSION

	if not _ensure_dir():
		return false

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

	# 旧主档先降级成备份：rename 只换名字不写内容，比「删旧档」安全
	if dir.file_exists(SAVE_NAME):
		if dir.file_exists(BAK_NAME) and dir.remove(BAK_NAME) != OK:
			push_error("[存档] 删不掉旧备份，放弃本次写入")
			dir.remove(TMP_NAME)
			return false
		if dir.rename(SAVE_NAME, BAK_NAME) != OK:
			push_error("[存档] 备份旧档失败，放弃本次写入")
			dir.remove(TMP_NAME)
			return false

	if dir.rename(TMP_NAME, SAVE_NAME) != OK:
		push_error("[存档] 替换存档失败，尝试回滚")
		dir.remove(TMP_NAME)
		if not dir.file_exists(SAVE_NAME) and dir.file_exists(BAK_NAME):
			dir.rename(BAK_NAME, SAVE_NAME)
		return false
	return true


## 首次写档时目录可能不存在（例如 SALVATION_SAVE_DIR 指到新目录）
func _ensure_dir() -> bool:
	var abs_dir := ProjectSettings.globalize_path(_dir).trim_suffix("/")
	if DirAccess.dir_exists_absolute(abs_dir):
		return true
	if DirAccess.make_dir_recursive_absolute(abs_dir) != OK:
		push_error("[存档] 建不了目录：%s" % abs_dir)
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

	# 通关即清空进行中进度，避免下次「继续」回到已经打完的关卡
	_write_progress(-1, false)
	save_data()


## 读一个设置项（存档里没有就用默认值；settings 被写坏也不会崩）
func get_setting(key: String, fallback: Variant = null) -> Variant:
	var s: Variant = data.get("settings", {})
	if typeof(s) != TYPE_DICTIONARY:
		return fallback
	return s.get(key, fallback)

## 只改内存，不写盘——滑条拖动时避免每帧写文件，关面板时统一 save_data()
func set_setting(key: String, value: Variant) -> void:
	if typeof(data.get("settings")) != TYPE_DICTIONARY:
		data["settings"] = default_data()["settings"]
	var s: Dictionary = data["settings"]
	s[key] = value
