extends Node
## 调试开关（灰盒期专用）：只影响可玩性与显示，不写存档、不进评分
## 快捷键 F2–F6 与控制台在 scenes/ui/debug_panel.gd 里绑定；命令解析也在这里，方便冒烟测试

var invincible := false       # F2：玩家不掉血（仍会播受击表现？不会，直接忽略）
var freeze_ai := false        # F5：木桩与 Boss 停止出招/移动
var hitboxes_visible := false # F6：显示引擎碰撞形状（SceneTree.debug_collisions_hint）


## 测试与重开时回到默认值
func reset() -> void:
	invincible = false
	freeze_ai = false
	set_hitboxes(false)


func toggle_invincible() -> String:
	invincible = not invincible
	return "无敌：%s" % ("开" if invincible else "关")


func toggle_freeze_ai() -> String:
	freeze_ai = not freeze_ai
	return "冻结 AI：%s" % ("开" if freeze_ai else "关")


func toggle_hitboxes() -> String:
	set_hitboxes(not hitboxes_visible)
	return "判定盒：%s" % ("开" if hitboxes_visible else "关")


func set_hitboxes(on: bool) -> void:
	hitboxes_visible = on
	var tree := get_tree()
	if tree != null:
		tree.debug_collisions_hint = on


## 控制台入口：执行一行命令并返回要显示的文字；空行返回空串
func run_command(line: String) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	match parts[0].to_lower():
		"god":
			return toggle_invincible()
		"freeze":
			return toggle_freeze_ai()
		"kill":
			return kill_nearest()
		"warp":
			return warp_to_x(parts[1] if parts.size() > 1 else "")
		"boss":
			return warp_to_boss()
		"help":
			return "命令：god / freeze / kill / warp <x> / boss / help"
		_:
			return "未知命令：%s（输入 help）" % parts[0]


## 把玩家传送到 x；非法数字返回提示
func warp_to_x(text: String) -> String:
	var player := get_player()
	if player == null:
		return "没有玩家"
	if not text.is_valid_float():
		return "用法：warp <x>，例如 warp 1600"
	player.global_position = Vector2(text.to_float(), player.global_position.y)
	player.velocity = Vector2.ZERO
	return "已传送到 x=%.0f" % player.global_position.x


## 秒杀离玩家最近的敌人/Boss；没有目标时给出提示
func kill_nearest() -> String:
	var target := nearest_enemy()
	if target == null:
		return "附近没有敌人"
	target.take_hit(99999.0, 1, 0.0)
	return "已秒杀 %s" % target.name


## 传送到 Boss 面前 420px，方便反复试三阶段
func warp_to_boss() -> String:
	var player := get_player()
	if player == null:
		return "没有玩家"
	var boss := get_tree().get_first_node_in_group("boss") as Node2D
	if boss == null:
		return "Boss 不在场"
	player.global_position = boss.global_position + Vector2(-420.0, -80.0)
	player.velocity = Vector2.ZERO
	return "已传送到 Boss 前"


func get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


## 就近取敌：木桩优先于 Boss（两者加起来的距离最小者）
func nearest_enemy() -> Node2D:
	var player := get_player()
	if player == null:
		return null
	var best: Node2D = null
	var best_dist := INF
	for group in ["enemy", "boss"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node2D and node.has_method("take_hit"):
				var dist: float = (node as Node2D).global_position.distance_to(player.global_position)
				if dist < best_dist:
					best_dist = dist
					best = node as Node2D
	return best
