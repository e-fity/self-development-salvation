extends Node2D
## 冒烟测试：不依赖画面，验证核心系统的关键不变量
##
## 运行：
##   godot --headless --path game res://tests/smoke_test.tscn
## 退出码：0 = 全部通过，1 = 有失败项
##
## 覆盖范围：
##   Data     数值表加载 / 缺省兜底 / 类型兜底
##   Save     读写往返 / 坏档回落 / 战绩累积规则
##   Results  评价档位（S ≥ 90、A ≥ 70、否则 B）
##   Player   受伤、无敌帧、数值来源
##   Enemy    受击扣血、死亡标记
##   Boss     血量、阶段转换、转换期无敌

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame

	# 自定义存档目录必须存在，否则写档失败（save_system 不建目录，见审查报告 P2-11）
	var save_dir := Save.abs_save_path().get_base_dir()
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)

	print("========== 冒烟测试开始 ==========")

	_check_data()
	_check_save()
	_check_results()
	await _check_player()
	await _check_enemy()
	await _check_boss()

	# 留一帧给延迟 free / tween / 计时器收尾，避免退出时报对象泄漏
	await get_tree().create_timer(1.1, true, false, true).timeout
	await get_tree().process_frame

	print("========== 结果：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


# ---------------- 断言 ----------------
func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  [PASS] %s" % what)
	else:
		_failed += 1
		print("  [FAIL] %s" % what)


func _check_eq(actual: Variant, expected: Variant, what: String) -> void:
	_check(actual == expected, "%s（实际 %s，期望 %s）" % [what, var_to_str(actual), var_to_str(expected)])


# ---------------- Data ----------------
func _check_data() -> void:
	print("[Data] 数值表")
	_check(not Data.player.is_empty(), "player.json 已加载")
	_check(Data.enemies.has("melee"), "enemies.json 含 melee")
	_check(Data.boss.has("combo"), "boss.json 含 combo")
	_check_eq(Data.player["attacks"].size(), 3, "玩家三段普攻")
	_check_eq(Data.num(Data.enemies["melee"], "attack_range", 0.0), 70.0, "木桩攻击距离取自 JSON")

	# 类型兜底：字符串不该被当成数字
	_check_eq(Data.num({"v": "坏值"}, "v", 5.0), 5.0, "num() 拒绝字符串")
	_check_eq(Data.num({"v": 7}, "v", 5.0), 7.0, "num() 接受整数")
	_check_eq(Data.flag({"b": false}, "b", true), false, "flag() 读取布尔")
	_check_eq(Data.flag({"b": "yes"}, "b", true), true, "flag() 拒绝非布尔")

	# 缺失键回落到内置默认值：删文件也不能崩
	var fallback: Dictionary = Data._load("res://data/__missing__.json", Data.DEFAULT_PLAYER)
	_check_eq(float(fallback.get("fps", 0.0)), 15.0, "缺文件回落到内置默认值")


# ---------------- Save ----------------
func _check_save() -> void:
	print("[Save] 存档")
	var backup: Dictionary = Save.data.duplicate(true)

	Save.data["gold"] = 321
	Save.data["clears"] = 2
	_check(Save.save_data(), "写入存档")
	Save.load_data()
	_check_eq(int(Save.data.get("gold", 0)), 321, "金币读写往返")
	_check_eq(int(Save.data.get("clears", 0)), 2, "通关次数读写往返")

	# 战绩累积规则：金币累加、评价取高、最快用时取小
	Save.data["gold"] = 0
	Save.data["clears"] = 0
	Save.data["best_grade"] = ""
	Save.data["best_time"] = 0.0
	Save.record_run(120.0, "A", 10)
	Save.record_run(200.0, "B", 5)
	_check_eq(int(Save.data.get("gold", 0)), 15, "金币累加")
	_check_eq(int(Save.data.get("clears", 0)), 2, "通关次数累加")
	_check_eq(String(Save.data.get("best_grade", "")), "A", "评价只升不降")
	_check_eq(float(Save.data.get("best_time", 0.0)), 120.0, "最快用时取最小")

	# 坏档回落：写一段非法 JSON，load_data() 必须给默认值而不是崩
	var f := FileAccess.open(Save.abs_save_path(), FileAccess.WRITE)
	if f != null:
		f.store_string("{ 这不是 JSON ")
		f.close()
	Save.load_data()
	_check_eq(int(Save.data.get("gold", 0)), 0, "坏档回落默认值")

	Save.data = backup
	Save.save_data()


# ---------------- Results ----------------
func _check_results() -> void:
	print("[Results] 评价档位")
	var screen: Node = load("res://scenes/ui/results.gd").new()
	screen.set("_stats", {"time": 100.0, "hits": 0, "max_combo": 40})
	_check_eq(screen.call("_grade"), "S", "完美局评 S")
	screen.set("_stats", {"time": 200.0, "hits": 0, "max_combo": 15})
	_check_eq(screen.call("_grade"), "A", "中局评 A")
	screen.set("_stats", {"time": 400.0, "hits": 9, "max_combo": 0})
	_check_eq(screen.call("_grade"), "B", "差局评 B")
	screen.free()


# ---------------- Player ----------------
func _check_player() -> void:
	print("[Player] 受伤与无敌帧")
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector2(0, -200)
	add_child(player)
	await get_tree().physics_frame

	_check_eq(
			float(player.max_hp),
			float(Data.num(Data.player["stats"], "max_hp", 0.0)),
			"max_hp 取自数值表"
	)
	_check_eq(float(player.hp), float(player.max_hp), "初始满血")

	player.take_damage(10.0, 1)
	_check_eq(float(player.hp), float(player.max_hp) - 10.0, "受伤扣血")
	_check_eq(int(player.hits_taken), 1, "受伤计数")
	player.take_damage(10.0, 1)
	_check_eq(float(player.hp), float(player.max_hp) - 10.0, "无敌帧内二次受伤被忽略")

	# 等受击无敌结束（真实时间，避开命中停顿的 time_scale=0）
	await get_tree().create_timer(0.6, true, false, true).timeout
	player.take_damage(10.0, 1)
	_check_eq(float(player.hp), float(player.max_hp) - 20.0, "无敌结束后可再次受伤")

	player.queue_free()
	await get_tree().process_frame


# ---------------- Enemy ----------------
func _check_enemy() -> void:
	print("[Enemy] 受击与死亡")
	var enemy = load("res://scenes/enemies/enemy_dummy.tscn").instantiate()
	enemy.position = Vector2(2000, 0)
	add_child(enemy)
	await get_tree().physics_frame

	var full: float = enemy.max_hp
	enemy.take_hit(10.0, 1, 0.0)
	_check_eq(float(enemy.hp), full - 10.0, "木桩受击扣血")
	enemy.take_hit(9999.0, 1, 9999.0)
	_check(bool(enemy.get("_dead")), "木桩血量归零后死亡")

	enemy.queue_free()
	await get_tree().process_frame


# ---------------- Boss ----------------
func _check_boss() -> void:
	print("[Boss] 阶段转换")
	var boss = load("res://scenes/enemies/boss.tscn").instantiate()
	boss.position = Vector2(3000, 0)
	add_child(boss)
	await get_tree().physics_frame

	_check_eq(float(boss.max_hp), 600.0, "Boss 血量取自数值表")
	_check_eq(int(boss.phase), 1, "初始为第一阶段")

	# 600 → 350 = 58.3%，越过 66% 阈值 → 进二阶段并无敌
	boss.take_hit(250.0, 1, 0.0)
	_check_eq(float(boss.hp), 350.0, "Boss 受伤扣血")
	_check_eq(int(boss.phase), 2, "血量过阈值进二阶段")
	boss.take_hit(50.0, 1, 0.0)
	_check_eq(float(boss.hp), 350.0, "阶段转换无敌期不吃伤害")

	boss.queue_free()
	await get_tree().process_frame
