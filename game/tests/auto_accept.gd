extends Node2D
## 自动验收：在真窗口里跑一遍关键流程，抓截图与可量化指标。
##
## 用法（仓库根目录）：
##   $env:SALVATION_SHOT_DIR = "$PWD\_backup\shots"
##   $env:SALVATION_SAVE_DIR = "$PWD\_backup\test-save"
##   godot --path game res://tests/auto_accept.tscn --resolution 1280x720
##
## 退出码：0 = 所有自动断言通过；1 = 有失败项（明细见输出与 auto_accept.json）。
## 说明：这里验证的是「逻辑与渲染」，不是「手感」。音频、动画观感、真实输入延迟仍需人工。

const TITLE_SCENE := "res://scenes/ui/title.tscn"
const LEVEL_SCENE := "res://scenes/levels/level.tscn"
const SHOT_FALLBACK := "user://shots"

var shot_dir := ""
var fails := 0
var checks: Array[Dictionary] = []
var shots: Array[String] = []

var player: Node = null
var level: Node = null
var boss: Node = null
var latency_frames := -1
var combo_damage := -1.0
var dodge_dx := -1.0
var energy_after_ult := -1.0
var fps_avg := -1.0
var fps_min := -1.0
var retry_frames := -1
var ghost_pool := 0
var boss_engaged := false
var results_shown := false

func _ready() -> void:
	shot_dir = OS.get_environment("SALVATION_SHOT_DIR")
	if shot_dir.is_empty():
		shot_dir = SHOT_FALLBACK
	DirAccess.make_dir_recursive_absolute(shot_dir)
	Debug.invincible = true
	Debug.freeze_ai = false
	await _run()
	_report()
	get_tree().quit(0 if fails == 0 else 1)

func _run() -> void:
	await _stage_title()
	await _stage_level()
	await _stage_latency()
	await _stage_combo()
	await _stage_dodge()
	await _stage_skills()
	await _stage_retry()
	await _stage_boss()
	await _stage_results()

# ---------- 阶段 ----------

func _stage_title() -> void:
	var title: Node = load(TITLE_SCENE).instantiate()
	add_child(title)
	await _wait(0.9)
	await _shot("01_title.png")
	title.queue_free()
	await _wait(0.2)

func _stage_level() -> void:
	level = load(LEVEL_SCENE).instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await _wait(0.8)
	player = get_tree().get_first_node_in_group("player")
	_check(player != null, "关卡加载后有玩家")
	var panel: Node = level.get_node_or_null("DebugPanel")
	_check(panel != null and not panel.visible, "调试面板默认收起")
	await _shot("02_level.png")

func _stage_latency() -> void:
	if player == null:
		return
	Debug.freeze_ai = true
	player.global_position = Vector2(200.0, 0.0)
	player.set("_facing", 1)
	await _wait(0.2)
	var f0 := Engine.get_physics_frames()
	_tap("attack")
	for i in 6:
		await get_tree().physics_frame
		if player.state == player.State.ATTACK:
			latency_frames = Engine.get_physics_frames() - f0
			break
	_check(latency_frames >= 0 and latency_frames <= 2, "按键到起手 ≤2 物理帧（实测 %d）" % latency_frames)
	await _wait(0.5)

func _stage_combo() -> void:
	if player == null:
		return
	var dummy := _nearest_enemy(Vector2(420.0, 0.0))
	if dummy == null:
		_check(false, "找到可攻击的木桩")
		return
	player.global_position = Vector2(dummy.global_position.x - 70.0, 0.0)
	player.set("_facing", 1)
	await _wait(0.25)
	var hp0: float = dummy.get("hp")
	# 用「连点」模拟人类节奏：间隔 0.12s，落在每段收招前 0.15s 的缓冲窗口里。
	# 早期按下的会被丢弃（PRD 只缓冲收招前 0.15s），所以按密一点最稳。
	_tap("attack")
	await _wait(0.26)
	await _shot("03_hit.png")
	for i in 7:
		_tap("attack")
		await _wait(0.12)
	await _wait(1.0)
	combo_damage = hp0 - float(dummy.get("hp"))
	_check(combo_damage >= 30.0, "三连伤害 ≥30（实测 %.0f）" % combo_damage)
	_check(player.combo >= 3, "三连后连击数 ≥3（实测 %d）" % player.combo)

func _stage_dodge() -> void:
	if player == null:
		return
	await _wait(0.4)
	var x0: float = player.global_position.x
	_tap("dodge")
	var saw_invuln := false
	for i in 4:
		await get_tree().physics_frame
		if player.invulnerable:
			saw_invuln = true
	_check(saw_invuln, "闪避前 4 帧内出现无敌")
	ghost_pool = player.get("_ghosts").size()
	var ghost_visible := 0
	for ghost in player.get("_ghosts"):
		if ghost.visible:
			ghost_visible += 1
	_check(ghost_pool == 3 and ghost_visible == 3, "闪避残影：池 3 个且全部可见")
	await _shot("08_dodge_ghost.png")
	await _wait(0.5)
	dodge_dx = absf(player.global_position.x - x0)
	_check(dodge_dx >= 120.0, "闪避位移 ≥120px（实测 %.0f）" % dodge_dx)

func _stage_skills() -> void:
	if player == null:
		return
	player.energy = 0.0
	player.global_position = Vector2(340.0, 0.0)
	player.set("_facing", 1)
	await _wait(0.3)
	_tap("skill2")
	for i in 3:
		await get_tree().physics_frame
	_check(player.state == player.State.SKILL2, "L 逆鳞进入 SKILL2")
	await _wait(0.3)
	_check(player.get("_ring").visible, "逆鳞环在判定帧可见")
	var cd_after_skill2: float = player.skill2_cd
	await _shot("04_skill2.png")
	_check(cd_after_skill2 >= 9.8, "逆鳞判定后进入 10s CD（实测 %.2f）" % cd_after_skill2)
	await _wait(0.7)
	_check(not player.get("_ring").visible, "逆鳞环播完自动隐藏")

	player.energy = player.max_energy
	_tap("ultimate")
	var saw_invuln := false
	var saw_state := false
	for i in 60:
		await get_tree().physics_frame
		if player.state == player.State.ULTIMATE:
			saw_state = true
		if player.invulnerable:
			saw_invuln = true
			break
	_check(saw_state, "I 零点进入 ULTIMATE")
	_check(saw_invuln, "零点判定帧无敌")
	_check(player.get("_ult_bar").visible, "零点横斩在判定帧可见")
	await _shot("05_ultimate.png")
	await _shot("09_ult_slash.png")
	await _wait(1.4)
	_check(not player.get("_ult_bar").visible, "零点横斩播完自动隐藏")
	energy_after_ult = player.energy
	_check(energy_after_ult <= 6.0, "零点命中后能量清零（实测 %.0f）" % energy_after_ult)

## R13：死亡 → 按 R 立即重试，3 秒内可操作
func _stage_retry() -> void:
	if player == null:
		return
	player.global_position = Vector2(320.0, 0.0)
	await _wait(0.2)
	var full_hp: float = player.max_hp
	Debug.invincible = false
	player.set("_hurt_invuln", 0.0)
	player.set("hp", 5.0)
	player.take_damage(999.0, 1)
	_check(player.is_dead(), "血量归零进入 DEAD")
	var f0 := Engine.get_physics_frames()
	_tap("retry")
	var ready := false
	for i in 240:
		await get_tree().physics_frame
		if not player.is_dead():
			ready = true
			break
	retry_frames = Engine.get_physics_frames() - f0
	Debug.invincible = true
	_check(ready, "按 R 后立即复活")
	_check(retry_frames <= 180, "死亡→可操作 ≤3 秒（实测 %d 帧）" % retry_frames)
	_check(is_equal_approx(float(player.hp), full_hp), "重试后满血")
	await _wait(0.3)


func _stage_boss() -> void:
	Debug.freeze_ai = false
	boss = get_tree().get_first_node_in_group("boss")
	if boss == null:
		_check(false, "Boss 存在")
		return
	Debug.warp_to_boss()
	await _wait(1.2)
	_check(Save.checkpoint() >= 0, "经过检查点后写入存档（实测 %d）" % Save.checkpoint())
	boss_engaged = bool(boss.get("active"))
	_check(boss_engaged, "玩家靠近后 Boss 激活")
	await _shot("06_boss.png")

	# 采样 4 秒帧率（Boss 阶段 1 实战）
	var t0 := Time.get_ticks_msec()
	var samples: Array[float] = []
	while Time.get_ticks_msec() - t0 < 4000:
		samples.append(Engine.get_frames_per_second())
		await get_tree().process_frame
	if samples.is_empty():
		_check(false, "帧率采样非空")
		return
	samples.sort()
	fps_avg = _mean(samples)
	fps_min = samples[0]
	var p1: float = samples[maxi(0, int(samples.size() * 0.01) - 1)]
	_check(fps_avg >= 55.0, "Boss 战平均帧率 ≥55（实测 %.1f）" % fps_avg)
	_check(p1 >= 30.0, "1%% low ≥30（实测 %.1f）" % p1)

func _stage_results() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	boss.set("hp", 5.0)
	boss.take_hit(99999.0, 1, 0.0)
	await _wait(2.4)
	results_shown = bool(get_tree().paused)
	_check(results_shown, "Boss 死亡后进入结算（暂停）")
	var tut: Node = level.get_node_or_null("Tutorial")
	_check(tut == null or not tut.visible, "结算时隐藏教学提示")
	await _shot("07_results.png")

# ---------- 工具 ----------

func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := shot_dir.path_join(name)
	var err := img.save_png(path)
	if err == OK:
		shots.append(path)
	_check(err == OK, "截图 %s" % name)

func _nearest_enemy(around: Vector2) -> Node:
	var best: Node = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n):
			continue
		var d: float = absf((n as Node2D).global_position.x - around.x)
		if d < best_d:
			best_d = d
			best = n
	return best

func _mean(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / float(values.size())

func _check(ok: bool, name: String) -> void:
	if not ok:
		fails += 1
	checks.append({"ok": ok, "name": name})
	print("[%s] %s" % ["PASS" if ok else "FAIL", name])

func _report() -> void:
	var payload := {
		"fails": fails,
		"checks": checks,
		"latency_frames": latency_frames,
		"combo_damage": combo_damage,
		"dodge_dx": dodge_dx,
		"energy_after_ult": energy_after_ult,
		"retry_frames": retry_frames,
		"ghost_pool": ghost_pool,
		"fps_avg": fps_avg,
		"fps_min": fps_min,
		"boss_engaged": boss_engaged,
		"results_shown": results_shown,
		"shots": shots,
	}
	var file := FileAccess.open(shot_dir.path_join("auto_accept.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "  "))
		file.close()
	print("ACCEPT 通过 %d / 失败 %d，截图 %d 张，目录 %s" % [
		checks.size() - fails, fails, shots.size(), shot_dir])
