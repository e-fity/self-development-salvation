extends CharacterBody2D
## Boss「夜巡」：600 HP，三阶段（PRD 8.3）
## P1 三连斩/跳劈 → P2 加召唤 → P3 狂暴（攻速 ×1.3）

# 数值来自 data/boss.json（Data 负责合并默认值）
var gravity := 1400.0
var gold_reward := 50
var engage_range := 520.0
var phase_thresholds: Array = [0.66, 0.33]
var phase_interval: Array = [2.0, 1.6, 1.1]
var windup_scale: Array = [1.0, 1.0, 0.8]
var transition_seconds := 1.0
var flash_time := 0.08

var combo_telegraph := 0.6
var combo_hits := 3
var combo_damage := 10.0
var combo_range := 120.0
var combo_height := 160.0
var combo_gap := 0.28
var combo_tail := 0.2

var jump_telegraph := 0.5
var jump_air_time := 0.45
var jump_velocity_y := -700.0
var jump_speed_x := 620.0
var jump_damage := 14.0
var jump_range := 140.0
var jump_height := 180.0
var jump_tail := 0.3

var summon_telegraph := 1.0
var summon_offsets: Array = [-280.0, 280.0]
var summon_tail := 0.4
var summon_phase := 2
var summon_chance := 0.45

@export var max_hp := 600.0
@export var defense := 3.0

var hp := 0.0
var phase := 1
var active := false

var _dead := false
var _busy := false
var _invuln := false
var _atk_timer := 1.2
var _facing := -1
var _jumping := false
var _flash := 0.0
var _summons: Array[Node] = []
var _slash: Polygon2D
var _blade: Polygon2D
var _aim: Polygon2D
var _aim_line: Line2D

@onready var visual: Node2D = $Visual
@onready var flash_poly: Polygon2D = $Visual/Flash
@onready var collision: CollisionShape2D = $Collision


func _ready() -> void:
	_load_data()
	_slash = Polygon2D.new()
	_slash.polygon = PackedVector2Array([
		Vector2(30, -210), Vector2(120, -170), Vector2(150, -90),
		Vector2(120, -20), Vector2(40, -10), Vector2(70, -100),
	])
	_slash.color = Color(0.75, 0.88, 1.0, 0.55)
	_slash.visible = false
	visual.add_child(_slash)

	# 朝向标记：一侧的巨刃，随 Visual 一起翻转，玩家一眼能看出他要往哪边砍
	_blade = Polygon2D.new()
	_blade.polygon = PackedVector2Array([
		Vector2(48, -200), Vector2(140, -158), Vector2(150, -60), Vector2(52, -30),
	])
	_blade.color = Color(0.70, 0.74, 0.82, 1.0)
	visual.add_child(_blade)

	# 预警框：直接画出这一刀会打在哪儿（不随 Visual 翻转，按世界位置摆）
	_aim = Polygon2D.new()
	_aim.color = Color(1.0, 0.80, 0.30, 0.22)
	_aim.z_index = -1           # 画在 Boss 身后，不挡住本体
	_aim.visible = false
	add_child(_aim)

	_aim_line = Line2D.new()
	_aim_line.width = 4.0
	_aim_line.default_color = Color(1.0, 0.86, 0.40, 0.95)
	_aim_line.closed = true
	_aim_line.z_index = -1
	_aim_line.visible = false
	add_child(_aim_line)

	hp = max_hp
	add_to_group("boss")
	flash_poly.visible = false


func is_dead() -> bool:
	return _dead


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	if not _jumping:
		velocity.x = 0.0
	move_and_slide()

	if _flash > 0.0:
		_flash -= delta
		flash_poly.visible = true
	else:
		flash_poly.visible = false

	if _dead or _busy:
		return

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return

	# 玩家靠近才开打
	if not active:
		if absf(player.global_position.x - global_position.x) < engage_range:
			active = true
			Audio.play("boss_roar", -2.0)
			print("[Boss] 夜巡 醒来了")
		return

	# 出招期间锁朝向：转身要付代价，打完才能重新面向玩家
	if not _busy:
		_face(player)
	_atk_timer -= delta
	if _atk_timer <= 0.0:
		_busy = true
		_choose_attack(player)


func _face(player: Node) -> void:
	var dx: float = player.global_position.x - global_position.x
	if absf(dx) > 8.0:
		_facing = signi(int(dx))
		visual.scale.x = _facing


func _choose_attack(player: Node) -> void:
	if _dead:
		return
	var dx: float = player.global_position.x - global_position.x

	if phase >= summon_phase and _alive_summons() == 0 and randf() < summon_chance:
		await _move_summon()
	elif absf(dx) > 260.0:
		await _move_jump(player)
	else:
		await _move_combo(player)

	if _dead:
		return
	_busy = false
	_atk_timer = float(phase_interval[phase - 1])


# ---------------- 招式 ----------------
func _move_combo(player: Node) -> void:
	await _telegraph(
		combo_telegraph * float(windup_scale[phase - 1]),
		_combo_center(),
		_combo_size()
	)
	for i in combo_hits:
		if _dead:
			return
		# 判定盒在身前（跟着朝向走），比「按距离」更像真的在砍
		_flash_slash()
		if _hits_player(global_position + _combo_center(), _combo_size()):
			var dir := signi(int(player.global_position.x - global_position.x))
			player.take_damage(combo_damage, dir)
			Audio.play("boss_swing", -6.0)
		await _wait(combo_gap)
	await _wait(combo_tail)


## 三连斩判定盒：宽 combo_range、高 combo_height（JSON 可调，不再写死 220）
func _combo_size() -> Vector2:
	return Vector2(combo_range, combo_height)


func _combo_center() -> Vector2:
	return Vector2(_facing * combo_range * 0.5, -combo_height * 0.5)


func _move_jump(player: Node) -> void:
	var lead_x: float = player.global_position.x
	await _telegraph(
		jump_telegraph * float(windup_scale[phase - 1]),
		Vector2(lead_x - global_position.x, -jump_height * 0.5),
		_jump_size()
	)
	if _dead:
		return
	var target_x: float = player.global_position.x
	var dir := signf(target_x - global_position.x)
	_jumping = true
	velocity.y = jump_velocity_y
	velocity.x = dir * jump_speed_x
	await _wait(jump_air_time)
	_jumping = false
	velocity.x = 0.0

	# 落点范围伤害：以落点为中心的一块矩形，高度同样走跳劈配置
	if _hits_player(global_position + _jump_center(), _jump_size()):
		player.take_damage(jump_damage, signi(int(player.global_position.x - global_position.x)))
		Audio.play("hit_heavy", -4.0)
	await _wait(jump_tail)


## 跳劈落点判定：宽 jump_range*2、高 jump_height
func _jump_size() -> Vector2:
	return Vector2(jump_range * 2.0, jump_height)


func _jump_center() -> Vector2:
	return Vector2(0.0, -jump_height * 0.5)


## 挥砍的一道白光，让判定「看得见」
func _flash_slash() -> void:
	_slash.visible = true
	await _wait(0.09)
	_slash.visible = false


## 矩形判定盒里有没有玩家（用物理查询，和玩家的判定方式一致）
func _hits_player(center: Vector2, size: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = size
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	query.collision_mask = 1          # 只查玩家层
	query.collide_with_areas = false
	for hit in space.intersect_shape(query, 4):
		var body = hit.get("collider")
		if body != null and body.has_method("take_damage"):
			return true
	return false


func _move_summon() -> void:
	await _telegraph(summon_telegraph * float(windup_scale[phase - 1]))
	if _dead:
		return
	var scene: PackedScene = load("res://scenes/enemies/enemy_dummy.tscn")
	for offset in summon_offsets:
		var d: Node = scene.instantiate()
		d.position = Vector2(global_position.x + offset, 0)
		get_parent().add_child(d)
		_summons.append(d)
	Audio.play("summon", -3.0)
	print("[Boss] 召唤了 2 只小怪")
	await _wait(summon_tail)


func _telegraph(seconds: float, aim_center := Vector2.ZERO, aim_size := Vector2.ZERO) -> void:
	Audio.play("boss_swing", -8.0)
	modulate = Color(1.0, 0.42, 0.42)
	_show_aim(aim_center, aim_size)
	await _wait(seconds)
	_aim.visible = false
	_aim_line.visible = false
	if not _dead and not _invuln:   # 转换期的红色由 _transition 收尾，别被预警提前擦掉
		modulate = Color.WHITE


## 把「这一刀打在哪儿」画出来，让预警是空间信息而不只是颜色
func _show_aim(center: Vector2, size: Vector2) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		_aim.visible = false
		return
	var half := size * 0.5
	_aim.position = Vector2.ZERO
	_aim.polygon = PackedVector2Array([
		center + Vector2(-half.x, -half.y),
		center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y),
		center + Vector2(-half.x, half.y),
	])
	_aim_line.points = _aim.polygon
	_aim.visible = true
	_aim_line.visible = true


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ---------------- 受伤与阶段 ----------------
func take_hit(dmg: float, _dir: int, _force: float) -> void:
	if _dead or _invuln:
		return
	hp = maxf(0.0, hp - dmg)
	_flash = flash_time

	if hp <= 0.0:
		_die()
		return

	var ratio := hp / max_hp
	if phase == 1 and ratio <= float(phase_thresholds[0]):
		_transition(2)
	elif phase == 2 and ratio <= float(phase_thresholds[1]):
		_transition(3)


func _transition(new_phase: int) -> void:
	# 转换期锁定：不然会出现「一边无敌一边起手」，玩家看到的预警和伤害对不上
	var was_busy := _busy
	_busy = true
	phase = new_phase
	Audio.play("boss_phase", -2.0)
	_invuln = true
	modulate = Color(1.0, 0.35, 0.35)
	print("[Boss] 进入第 %d 阶段（短暂无敌）" % phase)
	await _wait(transition_seconds)
	if _dead:
		return
	modulate = Color.WHITE
	_invuln = false
	_busy = was_busy
	_atk_timer = minf(_atk_timer, 0.8)


func _die() -> void:
	_dead = true
	Audio.play("enemy_die", -2.0, 0.7)
	collision.set_deferred("disabled", true)
	remove_from_group("boss")
	var parent := get_parent()
	if parent != null and parent.has_method("add_gold"):
		parent.add_gold(gold_reward)
	print("[Boss] 夜巡 倒下了")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)


func _alive_summons() -> int:
	_summons = _summons.filter(func(n): return is_instance_valid(n))
	return _summons.size()


## 从 data/boss.json 读数值；缺字段时由 Data 回落默认值
func _load_data() -> void:
	var d: Dictionary = Data.boss
	max_hp = Data.num(d, "max_hp", max_hp)
	defense = Data.num(d, "defense", defense)
	gold_reward = int(Data.num(d, "gold", float(gold_reward)))
	engage_range = Data.num(d, "engage_range", engage_range)
	if d.get("phases") is Array and d["phases"].size() >= 2:
		phase_thresholds = d["phases"]
	if d.get("phase_interval") is Array and d["phase_interval"].size() >= 3:
		phase_interval = d["phase_interval"]
	if d.get("windup_scale") is Array and d["windup_scale"].size() >= 3:
		windup_scale = d["windup_scale"]
	transition_seconds = Data.num(d, "transition_seconds", transition_seconds)

	var c: Dictionary = d.get("combo", {})
	combo_telegraph = Data.num(c, "telegraph", combo_telegraph)
	combo_hits = int(Data.num(c, "hits", float(combo_hits)))
	combo_damage = Data.num(c, "damage", combo_damage)
	combo_range = Data.num(c, "range", combo_range)
	combo_height = Data.num(c, "height", combo_height)
	combo_gap = Data.num(c, "gap", combo_gap)
	combo_tail = Data.num(c, "tail", combo_tail)

	var j: Dictionary = d.get("jump", {})
	jump_telegraph = Data.num(j, "telegraph", jump_telegraph)
	jump_air_time = Data.num(j, "air_time", jump_air_time)
	jump_velocity_y = Data.num(j, "velocity_y", jump_velocity_y)
	jump_speed_x = Data.num(j, "speed_x", jump_speed_x)
	jump_damage = Data.num(j, "damage", jump_damage)
	jump_range = Data.num(j, "range", jump_range)
	jump_height = Data.num(j, "height", jump_height)
	jump_tail = Data.num(j, "tail", jump_tail)

	var sm: Dictionary = d.get("summon", {})
	summon_telegraph = Data.num(sm, "telegraph", summon_telegraph)
	if sm.get("offsets") is Array:
		summon_offsets = sm["offsets"]
	summon_tail = Data.num(sm, "tail", summon_tail)
	summon_phase = int(Data.num(sm, "trigger_phase", float(summon_phase)))
	summon_chance = Data.num(sm, "chance", summon_chance)
