extends Node2D
## 关卡：检查点（x=600 / x=1600 Boss 门前）、金币、结算

const CHECKPOINTS := [600.0, 1600.0]

var respawn_point := Vector2(0, 0)
var gold := 0
var start_msec := 0

var _taken := 0
var _boss_seen := false
var _finished := false


func _ready() -> void:
	add_to_group("level")
	start_msec = Time.get_ticks_msec()
	Audio.start_music()


func _process(_delta: float) -> void:
	_track_checkpoints()
	_track_boss()


func _track_checkpoints() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return

	while _taken < CHECKPOINTS.size() and player.global_position.x >= CHECKPOINTS[_taken]:
		respawn_point = Vector2(CHECKPOINTS[_taken], 0.0)
		_taken += 1
		print("[检查点] 记录 x=%.0f" % respawn_point.x)
		if _taken >= CHECKPOINTS.size():
			player.hp = player.max_hp
			print("[神龛] 血已回满")


func _track_boss() -> void:
	var boss := get_tree().get_first_node_in_group("boss")
	if boss != null:
		_boss_seen = true
	elif _boss_seen and not _finished:
		_finished = true
		await get_tree().create_timer(1.0).timeout
		_show_results()


func add_gold(amount: int) -> void:
	gold += amount
	Audio.play_varied("gold", -10.0, 0.05)


func _show_results() -> void:
	var player := get_tree().get_first_node_in_group("player")
	var elapsed := (Time.get_ticks_msec() - start_msec) / 1000.0
	var stats := {
		"time": elapsed,
		"hits": player.hits_taken if player != null else 0,
		"max_combo": player.max_combo if player != null else 0,
		"gold": gold,
	}
	print("[结算] 用时 %.1fs  受伤 %d  最高连击 %d  金币 %d" % [
		elapsed, stats["hits"], stats["max_combo"], stats["gold"]])

	# 结算时隐藏战斗 HUD 和调试面板，避免透过结算页
	for node_name in ["HUD", "DebugPanel"]:
		var n := get_node_or_null(node_name)
		if n != null:
			n.visible = false

	var screen: Node = load("res://scenes/ui/results.gd").new()
	add_child(screen)
	screen.setup(stats)
	get_tree().paused = true
