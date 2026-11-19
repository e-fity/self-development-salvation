extends Node2D
## 关卡：检查点（节点位置即逻辑位置）、金币、结算

const RESULTS_SCRIPT := preload("res://scenes/ui/results.gd")

## 检查点 x 坐标，_ready 时从场景里的 Checkpoint* 节点读取并排序
var checkpoints: Array[float] = []

var respawn_point := Vector2(0, 0)
var gold := 0
## 战斗用时：只累计帧 delta（暂停时 _process 不跑，暂停时间自然不算）
var elapsed := 0.0

var _taken := 0
var _boss_seen := false
var _finished := false
## 玩家/Boss 引用缓存：失效（重生、Boss 被清掉）才重新查组
var _player: Node2D
var _boss: Node2D


func _ready() -> void:
	add_to_group("level")
	_collect_checkpoints()
	_resume_if_needed()
	Audio.start_music()


## 视觉柱与判定点共用同一个节点位置，场景里挪柱子不必再改脚本
func _collect_checkpoints() -> void:
	checkpoints.clear()
	for child in get_children():
		if child is Node2D and String(child.name).begins_with("Checkpoint"):
			checkpoints.append((child as Node2D).position.x)
	checkpoints.sort()
	if checkpoints.is_empty():
		push_warning("[关卡] 没有 Checkpoint 节点，检查点系统停用")


func _process(delta: float) -> void:
	tick(delta)
	_track_checkpoints()
	_track_boss()


## 计时入口单独拆出来，便于测试；结算后停止累计
func tick(delta: float) -> void:
	if _finished:
		return
	elapsed += delta


func _find_player() -> Node2D:
	if not is_instance_valid(_player) and is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player


## 从存档恢复到某个检查点：先把玩家放到重生点，再继续跑关卡
func _resume_if_needed() -> void:
	var index := Save.pending_checkpoint
	Save.pending_checkpoint = -1
	if index < 0:
		return
	if not _apply_resume(index):
		push_warning("[关卡] 存档检查点 %d 超出场景范围，从头开始" % index)
		return
	var player := _find_player()
	if player != null:
		player.global_position = respawn_point
	print("[关卡] 从检查点 %d 继续（x=%.0f）" % [index, respawn_point.x])


## 把检查点下标应用成重生点；越界返回 false（场景改短后旧档不应崩）
func _apply_resume(index: int) -> bool:
	if index < 0 or index >= checkpoints.size():
		return false
	respawn_point = Vector2(checkpoints[index], 0.0)
	_taken = index + 1
	return true


## 记录一个检查点：更新重生点、写档；最后一个检查点是神龛（只回满一次）
func _record_checkpoint(index: int) -> void:
	if not _apply_resume(index):
		return
	print("[检查点] 记录 x=%.0f" % respawn_point.x)
	var shrine := index == checkpoints.size() - 1
	if shrine and not Save.shrine_taken():
		var player := _find_player()
		if player != null:
			player.hp = player.max_hp
			if "energy" in player:
				player.energy = player.max_energy
			print("[神龛] 血与能量已回满")
		Save.save_progress(index, true)
	else:
		Save.save_progress(index, Save.shrine_taken())


func _track_checkpoints() -> void:
	var player := _find_player()
	if player == null:
		return

	while _taken < checkpoints.size() and player.global_position.x >= checkpoints[_taken]:
		_record_checkpoint(_taken)


func _track_boss() -> void:
	if not is_instance_valid(_boss):
		_boss = get_tree().get_first_node_in_group("boss") as Node2D
	if _boss != null:
		_boss_seen = true
	elif _boss_seen and not _finished:
		_finished = true
		await get_tree().create_timer(1.0).timeout
		_show_results()


func add_gold(amount: int) -> void:
	gold += amount
	Audio.play_varied("gold", -10.0, 0.05)


## 玩家复活后的收尾：Boss 战阵亡回到门前神龛并回满（R13）
func on_player_respawn(player: Node) -> void:
	if not _boss_seen:
		return
	if not is_instance_valid(_boss) or bool(_boss.get("_dead")):
		return
	player.hp = player.max_hp
	if "energy" in player:
		player.energy = player.max_energy
	print("[神龛] Boss 战阵亡，回到门前神龛并回满")


func _show_results() -> void:
	# 场景已经切走就不要再建结算页（await 期间可能换场景）
	if not is_inside_tree():
		return
	var player := _find_player()
	var stats := {
		"time": elapsed,
		"hits": player.hits_taken if player != null else 0,
		"max_combo": player.max_combo if player != null else 0,
		"gold": gold,
	}
	print("[结算] 用时 %.1fs  受伤 %d  最高连击 %d  金币 %d" % [
		elapsed, stats["hits"], stats["max_combo"], stats["gold"]])

	# 结算时隐藏战斗 HUD、调试面板和教学提示，避免透过结算页
	for node_name in ["HUD", "DebugPanel", "Tutorial"]:
		var n := get_node_or_null(node_name)
		if n != null:
			n.visible = false

	var screen: Node = RESULTS_SCRIPT.new()
	add_child(screen)
	screen.setup(stats)
	get_tree().paused = true
