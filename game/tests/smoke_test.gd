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
##   Player   受伤、无敌帧、数值来源、输入缓冲窗口
##   Enemy    受击扣血、死亡标记
##   Level    战斗计时按 delta 累计、结算后停止
##   Boss     血量、阶段转换、转换期无敌与锁定出招、判定盒尺寸
##   Audio    BGM 走流内循环，不靠 finished 重播
##   Debug    无敌 / 冻结 AI / 控制台命令 / 秒杀

var _passed := 0
var _failed := 0


func _ready() -> void:
	await get_tree().process_frame

	print("========== 冒烟测试开始 ==========")

	_check_data()
	_check_save()
	_check_progress()
	_check_results()
	await _check_player()
	await _check_enemy()
	_check_level()
	await _check_level_resume()
	await _check_title_continue()
	await _check_boss()
	_check_audio()
	await _check_debug()

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
	_check_eq(Data.num(Data.player["energy"], "max", 0.0), 100.0, "能量上限取自 JSON")
	_check_eq(Data.num(Data.player["skill2"], "cooldown", 0.0), 10.0, "逆鳞冷却取自 JSON")
	_check_eq(Data.num(Data.player["ultimate"], "mult", 0.0), 4.0, "零点倍率取自 JSON")

	# 类型兜底：字符串不该被当成数字
	_check_eq(Data.num({"v": "坏值"}, "v", 5.0), 5.0, "num() 拒绝字符串")
	_check_eq(Data.num({"v": 7}, "v", 5.0), 7.0, "num() 接受整数")
	_check_eq(Data.flag({"b": false}, "b", true), false, "flag() 读取布尔")
	_check_eq(Data.flag({"b": "yes"}, "b", true), true, "flag() 拒绝非布尔")

	# 缺失键回落到内置默认值：删文件也不能崩
	var fallback: Dictionary = Data._load("res://data/__missing__.json", Data.DEFAULT_PLAYER)
	_check_eq(float(fallback.get("fps", 0.0)), 15.0, "缺文件回落到内置默认值")

	# 默认表与 JSON 重叠字段必须同值（规约 DATA-6），否则删掉 JSON 后手感会变
	_check(_same_value(Data.player, Data.DEFAULT_PLAYER), "player.json 与默认表同值")
	_check(_same_value(Data.enemies, Data.DEFAULT_ENEMIES), "enemies.json 与默认表同值")
	_check(_same_value(Data.boss, Data.DEFAULT_BOSS), "boss.json 与默认表同值")

	# _merge 类型校验：标量不能覆盖字典，否则 player.gd 的 Dictionary 取值会崩
	var scalar_over_dict: Dictionary = Data._merge(
			Data.DEFAULT_PLAYER.duplicate(true), {"move": 5, "stats": "坏"})
	_check_eq(typeof(scalar_over_dict.get("move")), TYPE_DICTIONARY, "标量不能覆盖 move 字典")
	_check_eq(float(scalar_over_dict["move"]["speed"]), 220.0, "被拒的标量不污染默认值")

	# 数组长度 / 元素结构不对时保留默认数组；合法元素则深合并
	var wrong_size: Dictionary = Data._merge(
			Data.DEFAULT_PLAYER.duplicate(true), {"attacks": [1, 2]})
	_check_eq(wrong_size["attacks"].size(), 3, "数组长度不符时保留默认数组")
	var partial: Dictionary = Data._merge(Data.DEFAULT_PLAYER.duplicate(true), {
		"attacks": [
			{"startup": 1},
			{},
			{"mult": 2.0, "active": 1, "recover": 3, "knockback": 60.0},
		],
	})
	_check_eq(int(partial["attacks"][0].get("startup", 0)), 1, "数组元素按字典深合并")
	_check_eq(int(partial["attacks"][0].get("active", 0)), 1, "数组元素缺键保留默认值")


# ---------------- Save ----------------
func _check_save() -> void:
	print("[Save] 存档")
	var backup: Dictionary = Save.data.duplicate(true)

	# 目录不存在时写档要自动建目录（P2-11）；只删测试目录，避免误删 user://
	var save_dir := Save.abs_save_path().get_base_dir()
	if not OS.get_environment("SALVATION_SAVE_DIR").is_empty():
		_remove_dir_recursive(save_dir)
	_check(Save.save_data(), "目录不存在时自动建目录并写档")
	_check(FileAccess.file_exists(Save.abs_save_path()), "主档已生成")

	Save.data["gold"] = 321
	Save.data["clears"] = 2
	_check(Save.save_data(), "写入存档")
	Save.load_data()
	_check_eq(int(Save.data.get("gold", 0)), 321, "金币读写往返")
	_check_eq(int(Save.data.get("clears", 0)), 2, "通关次数读写往返")

	# 第二次写档：旧主档应降级为 save.bak（此时 gold=321）
	Save.data["gold"] = 654
	_check(Save.save_data(), "第二次写入")
	_check(FileAccess.file_exists(Save.abs_bak_path()), "旧档降级为 save.bak")

	# 主档损坏 → 从 bak 恢复上一份
	_write_text(Save.abs_save_path(), "{ 这不是 JSON ")
	Save.load_data()
	_check_eq(int(Save.data.get("gold", 0)), 321, "主档损坏时从 save.bak 恢复")

	# settings 被写成字符串：不能崩，其余字段照读，settings 回落默认
	_write_json(Save.abs_save_path(), {"gold": 55, "settings": "坏"})
	Save.load_data()
	_check_eq(int(Save.data.get("gold", 0)), 55, "settings 损坏时其余字段仍可读")
	_check_eq(typeof(Save.data.get("settings")), TYPE_DICTIONARY, "settings 非字典时回落默认字典")
	_check_eq(float(Save.get_setting("bgm", -1.0)), 1.0, "settings 损坏时 get_setting 返回默认")

	# settings 内部值类型错误：逐键丢弃，合法键保留
	_write_json(Save.abs_save_path(), {"gold": 1, "settings": {
		"bgm": "大声", "numbers": "yes", "tutorial": false,
	}})
	Save.load_data()
	_check_eq(float(Save.get_setting("bgm", 0.0)), 1.0, "settings.bgm 类型错误回落默认")
	_check_eq(Save.get_setting("numbers", false), true, "settings.numbers 类型错误回落默认")
	_check_eq(Save.get_setting("tutorial", true), false, "settings 合法布尔保留")

	# 顶层字段类型错误也不能崩
	_write_json(Save.abs_save_path(), {"gold": "很多", "best_time": []})
	Save.load_data()
	_check_eq(int(Save.data.get("gold", 0)), 0, "gold 类型错误回落默认")
	_check_eq(float(Save.data.get("best_time", -1.0)), 0.0, "best_time 类型错误回落默认")

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

	Save.data = backup
	Save.save_data()


# ---------------- Save：检查点进度（R11） ----------------
func _check_progress() -> void:
	print("[Save] 检查点进度")
	var backup: Dictionary = Save.data.duplicate(true)

	Save.data = Save.default_data()
	Save.save_data()
	_check_eq(Save.checkpoint(), -1, "默认没有检查点进度")
	_check(not Save.has_progress(), "默认没有可继续的进度")

	Save.save_progress(0, false)
	_check_eq(Save.checkpoint(), 0, "记录第一个检查点")
	Save.load_data()
	_check_eq(Save.checkpoint(), 0, "检查点进度写入后能读回")
	_check(Save.has_progress(), "有进度时 has_progress 为真")

	Save.save_progress(0, true)
	Save.load_data()
	_check(Save.shrine_taken(), "神龛已领取标记能读回")

	# 旧版 v1 存档没有 progress 字段：迁移后补默认值，旧字段不能丢
	_write_json(Save.abs_save_path(), {"version": 1, "gold": 42})
	Save.load_data()
	_check_eq(int(Save.data.get("version", 0)), 2, "v1 存档迁移到 v2")
	_check_eq(int(Save.data.get("gold", 0)), 42, "迁移保留旧字段")
	_check_eq(Save.checkpoint(), -1, "迁移补出默认进度")

	# progress 被写坏时整段回落默认，不能崩
	_write_json(Save.abs_save_path(), {"version": 2, "progress": "坏"})
	Save.load_data()
	_check_eq(typeof(Save.data.get("progress")), TYPE_DICTIONARY, "progress 非字典回落默认")
	_check_eq(Save.checkpoint(), -1, "坏 progress 的检查点用默认值")

	# 通关记账要清空进行中的进度，避免下次「继续」回到已通关的关卡
	Save.save_progress(1, true)
	Save.record_run(100.0, "A", 0)
	_check(not Save.has_progress(), "通关后清空进行中进度")

	Save.save_progress(0, false)
	Save.reset_progress()
	_check(not Save.has_progress(), "reset_progress 清空进度")

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
	_check_eq(float(player.hurt_knockback), 240.0, "feedback 击退取自 player.json")
	_check_eq(float(player.combo_reset_time), 3.0, "feedback 连击窗口取自 player.json")
	_check_eq(float(player.skill2_cooldown), 10.0, "逆鳞冷却取自 player.json")
	_check_eq(float(player.ult_mult), 4.0, "零点倍率取自 player.json")
	_check_eq(float(player.skill2_hitstop), 0.04, "逆鳞顿帧取自 player.json")
	_check_eq(float(player.ult_hitstop), 0.08, "零点顿帧取自 player.json")

	# 收招阶段可直接移动（R15 手感：不用松手再按方向）
	_check_eq(float(player.attack_move_scale), 0.55, "收招移速比例取自 player.json")
	_check_eq(float(player._recover_vx(1.0)), 220.0 * 0.55, "收招右移速度 = 移速 × 比例")
	_check_eq(float(player._recover_vx(0.0)), 0.0, "不收招移动时不漂移")

	# 能量：初始 0、命中 +6、上限 100、受击 −10（PRD 4.5）
	_check_eq(float(player.energy), 0.0, "初始能量为 0")
	player.call("_gain_energy", 6.0)
	_check_eq(float(player.energy), 6.0, "命中一次 +6 能量")
	player.call("_gain_energy", 1000.0)
	_check_eq(float(player.energy), float(player.max_energy), "能量封顶 100")

	player.take_damage(10.0, 1)
	_check_eq(float(player.hp), float(player.max_hp) - 10.0, "受伤扣血")
	_check_eq(int(player.hits_taken), 1, "受伤计数")
	_check_eq(float(player.energy), 90.0, "受击 −10 能量")
	player.take_damage(10.0, 1)
	_check_eq(float(player.hp), float(player.max_hp) - 10.0, "无敌帧内二次受伤被忽略")

	# 等受击无敌结束（真实时间，轮询而不是固定等 0.6s，避开命中停顿造成的抖动）
	var waited := 0.0
	while float(player.get("_hurt_invuln")) > 0.0 and waited < 2.0:
		await get_tree().create_timer(0.05, true, false, true).timeout
		waited += 0.05
	player.take_damage(10.0, 1)
	_check_eq(float(player.hp), float(player.max_hp) - 20.0, "无敌结束后可再次受伤")

	# P2-2：伤害公式只认目标自己的 defense，缺省按 0，不能藏硬编码的 3
	var plain := Node2D.new()
	_check_eq(player.call("_damage_against", 1.0, plain), 12.0, "目标无 defense 时按 0 计算")
	plain.free()
	var armed := ArmedTarget.new()
	_check_eq(player.call("_damage_against", 1.0, armed), 7.0, "目标 defense 参与减伤")
	_check(is_equal_approx(player.call("_damage_against", 1.2, armed), 9.4), "逆鳞倍率参与伤害")
	armed.free()

	# 逆鳞：判定帧才消耗冷却，起手期 2s 霸体
	player.call("_start_skill2")
	_check_eq(int(player.state), int(player.State.SKILL2), "逆鳞进入起手状态")
	_check(player.get("_super_armor") > 1.5, "逆鳞起手即有 2s 霸体")
	player.set("_state_time", float(player.skill2_startup) / float(player.fps))
	player.call("_process_skill2", 0.0)
	_check_eq(float(player.skill2_cd), 10.0, "逆鳞判定帧消耗 10s 冷却")

	# 零点：判定帧清空能量，20 连击时 4.0 × 1.1 = 4.4 倍
	player.set("state", player.State.IDLE)
	player.set("energy", player.max_energy)
	player.set("combo", 20)
	player.call("_start_ultimate")
	player.set("_state_time", float(player.ult_startup) / float(player.fps))
	player.call("_process_ultimate", 0.0)
	_check_eq(float(player.energy), 0.0, "零点判定帧清空能量")
	_check(is_equal_approx(float(player.get("_ult_mult")), 4.4), "零点吃 20 连击加成到 4.4 倍")

	# 收尾：回到待机，避免影响后面的闪避/红闪断言
	player.set("state", player.State.IDLE)
	player.invulnerable = false
	player.set("energy", 0.0)
	player.set("combo", 0)
	player.call("_apply_visual_alpha")

	# P2-5：红闪在闪避/橙闪期间到期时，不能把红色残留到动作结束
	player.set("_hurt_invuln", 0.05)
	player.call("_start_dodge", 1)
	await get_tree().create_timer(0.2, true, false, true).timeout
	_check(is_equal_approx(player.visual.modulate.r, 1.0), "闪避中红闪到期后不再泛红")
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check(is_equal_approx(player.visual.modulate.a, 1.0), "闪避结束后恢复不透明")

	# R12：特效节点预建、播放可见、播完隐藏；残影池固定 3 个
	_check(player.get("_ring") != null and player.get("_ult_bar") != null, "逆鳞环与零点横斩已预建")
	_check_eq(player.get("_ghosts").size(), 3, "残影池固定 3 个")
	player.call("_play_ring")
	player.call("_play_ult_bar")
	_check(player.get("_ring").visible and player.get("_ult_bar").visible, "技能特效播放时可见")
	await get_tree().create_timer(0.45, true, false, true).timeout
	_check(
			not player.get("_ring").visible and not player.get("_ult_bar").visible,
			"技能特效播完自动隐藏"
	)
	player.call("_start_dodge", 1)
	await get_tree().physics_frame
	var ghost_visible := 0
	for ghost in player.get("_ghosts"):
		if ghost.visible:
			ghost_visible += 1
	_check_eq(ghost_visible, 3, "闪避时 3 个残影可见")

	# 输入缓冲：只在硬直结束前 0.15s 内接受（PRD 5.3）
	player.set("_air_mode", false)
	player.set("_atk_total", 0.4)
	player.set("_state_time", 0.1)
	_check(not player.call("_accepts_buffer", true), "硬直早期按攻击不进缓冲")
	player.set("_state_time", 0.3)
	_check(bool(player.call("_accepts_buffer", true)), "结束前 0.15s 内按攻击进缓冲")
	_check(not player.call("_accepts_buffer", false), "没有按键时不进缓冲")
	player.set("_air_mode", true)
	_check(not player.call("_accepts_buffer", true), "空中攻击不吃缓冲")
	player.set("_air_mode", false)

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
	var rect_before = enemy.get("_rect")
	enemy.call("_hits_player")
	enemy.call("_hits_player")
	_check(
			enemy.get("_rect") == rect_before,
			"判定查询对象复用，不逐帧重建"
	)
	_check_eq(rect_before.shape.size, Vector2(70.0, 200.0), "判定盒尺寸取 enemies.json")
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
	_check_eq(boss._combo_size(), Vector2(120.0, 160.0), "三连斩判定用 combo_height")
	_check_eq(boss._jump_size(), Vector2(280.0, 180.0), "跳劈判定用 jump_height")

	# 600 → 350 = 58.3%，越过 66% 阈值 → 进二阶段并无敌
	boss.take_hit(250.0, 1, 0.0)
	_check_eq(float(boss.hp), 350.0, "Boss 受伤扣血")
	_check_eq(int(boss.phase), 2, "血量过阈值进二阶段")
	_check(boss._busy, "阶段转换期间锁住出招")
	boss.take_hit(50.0, 1, 0.0)
	_check_eq(float(boss.hp), 350.0, "阶段转换无敌期不吃伤害")

	await get_tree().create_timer(1.1, true, false, true).timeout
	_check(not boss._invuln, "转换结束后解除无敌")
	_check(not boss._busy, "转换结束后解除出招锁")

	boss.queue_free()
	await get_tree().process_frame


# ---------------- Level ----------------
func _check_level() -> void:
	print("[Level] 战斗计时")
	var level = load("res://scenes/levels/level.gd").new()
	level.tick(0.25)
	level.tick(0.25)
	_check(is_equal_approx(level.elapsed, 0.5), "计时按帧 delta 累计（不受暂停墙钟影响）")
	level.set("_finished", true)
	level.tick(10.0)
	_check(is_equal_approx(level.elapsed, 0.5), "结算后停止累计")

	# P2-10：检查点坐标从场景里的 Checkpoint* 节点读取，而不是脚本里另抄一份
	var probe = load("res://scenes/levels/level.gd").new()
	var cp1 := Node2D.new()
	cp1.name = "Checkpoint1"
	cp1.position = Vector2(600, 0)
	probe.add_child(cp1)
	var cp2 := Node2D.new()
	cp2.name = "Checkpoint2"
	cp2.position = Vector2(1600, 0)
	probe.add_child(cp2)
	probe.call("_collect_checkpoints")
	_check_eq(probe.checkpoints.size(), 2, "检查点数量取自场景节点")
	_check_eq(probe.checkpoints[0], 600.0, "检查点按 x 排序")
	_check_eq(probe.checkpoints[1], 1600.0, "第二个检查点位置取自场景")
	probe.free()

	# R11：过检查点写档、神龛只记一次、恢复位置可校验
	Save.data = Save.default_data()
	Save.save_data()
	var runner = load("res://scenes/levels/level.gd").new()
	runner.checkpoints.assign([600.0, 1600.0])
	runner.call("_record_checkpoint", 0)
	_check_eq(Save.checkpoint(), 0, "过检查点写入存档")
	_check_eq(runner.respawn_point, Vector2(600, 0), "重生点取检查点位置")
	_check_eq(int(runner.get("_taken")), 1, "检查点计数前移")
	runner.call("_record_checkpoint", 1)
	_check(Save.shrine_taken(), "神龛领取标记落盘")

	# R13：Boss 战阵亡回到神龛并回满；非 Boss 战不额外回能量
	var fake := FakePlayer.new()
	runner.add_child(fake)
	runner.set("_boss_seen", true)
	var stub_boss := DeadBoss.new()
	runner.add_child(stub_boss)
	runner.set("_boss", stub_boss)
	runner.call("on_player_respawn", fake)
	_check_eq(fake.hp, 100.0, "Boss 战复活回满血")
	_check_eq(fake.energy, 100.0, "Boss 战复活回满能量")
	runner.set("_boss_seen", false)
	fake.hp = 10.0
	fake.energy = 10.0
	runner.call("on_player_respawn", fake)
	_check_eq(fake.energy, 10.0, "非 Boss 战复活不额外回能量")
	stub_boss.free()
	fake.free()

	var resumed = load("res://scenes/levels/level.gd").new()
	resumed.checkpoints.assign([600.0, 1600.0])
	_check(resumed.call("_apply_resume", 1), "恢复索引合法")
	_check_eq(resumed.respawn_point, Vector2(1600, 0), "恢复后重生点正确")
	_check_eq(int(resumed.get("_taken")), 2, "恢复后检查点计数正确")
	_check(not resumed.call("_apply_resume", 9), "越界索引被拒绝")
	resumed.free()
	runner.free()
	Save.reset_progress()

	level.free()


# ---------------- Level：从存档继续（R11） ----------------
func _check_level_resume() -> void:
	print("[Level] 从存档继续")
	Save.data = Save.default_data()
	Save.save_progress(1, false)
	Save.pending_checkpoint = 1

	var scene: Node = load("res://scenes/levels/level.tscn").instantiate()
	add_child(scene)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player := get_tree().get_first_node_in_group("player") as Node2D
	_check(player != null, "关卡里能找到玩家")
	if player != null:
		_check(
				absf(player.global_position.x - 1600.0) < 1.0,
				"继续时玩家落在第二个检查点（x 实际 %.0f）" % player.global_position.x)
	_check_eq(int(scene.get("_taken")), 2, "继续后检查点计数为 2")
	_check_eq(Save.pending_checkpoint, -1, "跳转意图用后清空")

	# HUD 左下角常驻操作提示：教学淡出后还能查键位（H 可隐藏）
	var hud := scene.get_node_or_null("HUD")
	_check(hud != null, "关卡里有 HUD")
	if hud != null:
		var controls: Label = hud.get("_controls")
		_check(controls != null and controls.text.contains("Shift 闪避"), "HUD 常驻提示含闪避键")
		_check(controls != null and controls.visible, "HUD 常驻提示默认可见")

	scene.queue_free()
	await get_tree().process_frame
	Save.reset_progress()


# ---------------- Title：继续按钮（R11） ----------------
func _check_title_continue() -> void:
	print("[Title] 继续按钮状态")
	Save.data = Save.default_data()
	var title: Node = load("res://scenes/ui/title.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame

	var btn: Button = title.get("_continue_btn")
	title.call("_report_state")
	_check(btn.disabled, "没有进度时「继续」禁用")

	Save.save_progress(0, false)
	title.call("_report_state")
	_check(not btn.disabled, "有进度时「继续」可用")
	_check(String(btn.text).contains("第 1 检查点"), "继续按钮显示检查点序号")

	title.queue_free()
	await get_tree().process_frame
	Save.reset_progress()


# ---------------- Audio ----------------
func _check_audio() -> void:
	print("[Audio] BGM 循环")
	Audio.start_music()
	var stream: AudioStream = null
	if Audio._music != null:
		stream = Audio._music.stream
	_check(stream is AudioStreamWAV, "BGM 素材已加载")
	if stream is AudioStreamWAV:
		_check_eq(
				(stream as AudioStreamWAV).loop_mode,
				AudioStreamWAV.LOOP_FORWARD,
				"BGM 使用流内前向循环"
		)
	Audio.stop_music()


# ---------------- Debug ----------------
func _check_debug() -> void:
	print("[Debug] 调试开关与控制台")
	Debug.reset()
	_check(
			not Debug.invincible and not Debug.freeze_ai and not Debug.hitboxes_visible,
			"调试开关默认全关"
	)
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector2(0, -200)
	add_child(player)
	await get_tree().physics_frame
	_check(player != null, "测试场景里有玩家")

	# F2 无敌：开启后 take_damage 直接返回
	if player != null:
		var hp_before := float(player.hp)
		Debug.invincible = true
		player.take_damage(99.0, 1)
		_check_eq(float(player.hp), hp_before, "无敌开启后不掉血")
		Debug.invincible = false

	# F5 冻结 AI：木桩不推进冷却、不走动
	var dummy = load("res://scenes/enemies/enemy_dummy.tscn").instantiate()
	dummy.position = Vector2(600, -100)
	add_child(dummy)
	await get_tree().physics_frame
	dummy.set("_atk_cd", 5.0)
	Debug.freeze_ai = true
	dummy.call("_physics_process", 0.1)
	_check_eq(float(dummy.get("_atk_cd")), 5.0, "冻结 AI 时不推进攻击冷却")
	_check(is_zero_approx(float(dummy.velocity.x)), "冻结 AI 时不走动")
	Debug.freeze_ai = false

	# 控制台：warp 改坐标、非法参数与未知命令有提示
	_check_eq(Debug.warp_to_x("1234"), "已传送到 x=1234", "warp 命令移动玩家")
	if player != null:
		_check(is_equal_approx(player.global_position.x, 1234.0), "玩家 x 变为 1234")
	_check(Debug.warp_to_x("abc").begins_with("用法："), "warp 非法参数被拒绝")
	_check(Debug.run_command("help").begins_with("命令："), "help 列出命令")
	_check(Debug.run_command("nope").begins_with("未知命令"), "未知命令给出提示")
	_check(Debug.warp_to_boss() == "Boss 不在场", "场景无 Boss 时传送有提示")

	# F3 秒杀：木桩在附近时 kill 生效
	_check(Debug.run_command("kill").begins_with("已秒杀"), "kill 命中最近敌人")
	_check(bool(dummy.get("_dead")), "被秒杀的木桩进入死亡")

	Debug.reset()
	dummy.queue_free()
	player.queue_free()
	await get_tree().process_frame


# ---------------- 测试辅助 ----------------
## 默认表里的每个键，实际数据（JSON 合并结果）都必须同类型同值
func _same_value(actual: Variant, defaults: Variant) -> bool:
	if typeof(defaults) == TYPE_DICTIONARY:
		if typeof(actual) != TYPE_DICTIONARY:
			return false
		for key in defaults.keys():
			if not actual.has(key) or not _same_value(actual[key], defaults[key]):
				return false
		return true
	if typeof(defaults) == TYPE_ARRAY:
		if typeof(actual) != TYPE_ARRAY or actual.size() != defaults.size():
			return false
		for i in actual.size():
			if not _same_value(actual[i], defaults[i]):
				return false
		return true
	if typeof(defaults) == TYPE_FLOAT or typeof(defaults) == TYPE_INT:
		if typeof(actual) != TYPE_FLOAT and typeof(actual) != TYPE_INT:
			return false
		return is_equal_approx(float(actual), float(defaults))
	return actual == defaults


func _remove_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()

	for name in names:
		var full := path.path_join(name)
		if DirAccess.dir_exists_absolute(full):
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
	DirAccess.remove_absolute(path)


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_check(false, "写测试文件 %s" % path)
		return
	f.store_string(text)
	f.close()


func _write_json(path: String, d: Dictionary) -> void:
	_write_text(path, JSON.stringify(d, "\t"))


## 带防御值的假目标，用来验证伤害公式不会自带默认防御
class ArmedTarget:
	extends Node2D

	var defense := 5.0


## 关卡回满逻辑用的假玩家：只需要 hp / energy 两组字段
class FakePlayer:
	extends Node2D

	var hp := 10.0
	var max_hp := 100.0
	var energy := 0.0
	var max_energy := 100.0


## 关卡判断「Boss 还活着」用的假 Boss
class DeadBoss:
	extends Node2D

	var _dead := false
