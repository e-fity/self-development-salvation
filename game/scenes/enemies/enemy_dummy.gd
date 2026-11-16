extends CharacterBody2D
## 木桩敌人（灰盒）：40 HP，会前摇攻击；被打会闪白 + 击退，血量归零后淡出

# 数值来自 data/enemies.json 的 melee 段
var gravity := 1400.0
var juggle_gravity := 900.0
var launch_threshold := 120.0
var launch_velocity := -430.0
var attack_range := 150.0
var attack_height := 140.0
var sight_range := 420.0
var move_speed := 95.0
var windup_time := 0.45
var attack_cooldown := 1.6
var damage := 8.0
var gold_reward := 8

@export var max_hp := 40.0
@export var defense := 3.0
@export var flash_time := 0.08

var hp := 0.0

var _knockback := 0.0
var _flash := 0.0
var _dead := false
var _launched := false
var _atk_cd := 0.0
var _winding := false
var _windup := 0.0
var _facing := 1
var _lean := 0.0
var _walk_vx := 0.0
var _slash: Line2D
## 判定用的形状与查询对象只建一次；attack_range/height 变了才改 size
var _hit_shape: RectangleShape2D
var _hit_query: PhysicsShapeQueryParameters2D

@onready var visual: Node2D = $Visual
@onready var flash: Polygon2D = $Visual/Flash
@onready var collision: CollisionShape2D = $Collision


func _ready() -> void:
	_load_data()
	hp = max_hp
	flash.visible = false
	# 出手时甩出的一道弧线，让「小怪真的打了」看得见
	_slash = Line2D.new()
	var arc := PackedVector2Array()
	for i in 9:
		var a := deg_to_rad(lerpf(-52.0, 52.0, float(i) / 8.0))
		arc.append(Vector2(cos(a) * 78.0 + 18.0, sin(a) * 78.0 - 108.0))
	_slash.points = arc
	_slash.width = 9.0
	_slash.default_color = Color(1.0, 0.96, 0.92, 0.9)
	_slash.visible = false
	visual.add_child(_slash)

	_hit_shape = RectangleShape2D.new()
	_hit_shape.size = Vector2(attack_range, attack_height)
	_hit_query = PhysicsShapeQueryParameters2D.new()
	_hit_query.shape = _hit_shape
	_hit_query.collision_mask = 1          # 只查玩家层
	_hit_query.collide_with_areas = false


func _load_data() -> void:
	var d: Dictionary = Data.enemies.get("melee", {})
	max_hp = Data.num(d, "max_hp", max_hp)
	defense = Data.num(d, "defense", defense)
	damage = Data.num(d, "damage", damage)
	attack_range = Data.num(d, "attack_range", attack_range)
	attack_height = Data.num(d, "attack_height", attack_height)
	sight_range = Data.num(d, "sight", sight_range)
	move_speed = Data.num(d, "move_speed", move_speed)
	windup_time = Data.num(d, "windup", windup_time)
	attack_cooldown = Data.num(d, "cooldown", attack_cooldown)
	gravity = Data.num(d, "gravity", gravity)
	juggle_gravity = Data.num(d, "juggle_gravity", juggle_gravity)
	launch_threshold = Data.num(d, "launch_threshold", launch_threshold)
	launch_velocity = Data.num(d, "launch_velocity", launch_velocity)
	gold_reward = int(Data.num(d, "gold", float(gold_reward)))
	flash_time = Data.num(d, "flash_time", flash_time)


## 被 player 的判定盒调用
func take_hit(dmg: float, dir: int, force: float) -> void:
	if _dead:
		return
	hp -= dmg
	_knockback = dir * force
	_flash = flash_time
	# 击退力够大 = 击飞（第三段普攻 160）
	if force >= launch_threshold and not _launched:
		_launched = true
		velocity.y = launch_velocity
		print("[木桩] 被击飞")
	print("[木桩] 本段打了 %.0f，剩余 %.0f / %.0f" % [dmg, maxf(hp, 0.0), max_hp])
	if hp <= 0.0:
		_die()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += (juggle_gravity if _launched else gravity) * delta
	elif _launched and velocity.y >= 0.0:
		# 刚被打飞的那一帧 is_on_floor() 还是上一帧的结果，不能立刻判定落地
		_launched = false
		print("[木桩] 落地")

	velocity.x = _knockback + _walk_vx
	_knockback = move_toward(_knockback, 0.0, 1800.0 * delta)
	move_and_slide()

	if _flash > 0.0:
		_flash -= delta
		flash.visible = true
	else:
		flash.visible = false

	if _dead:
		return

	# 被击飞期间不进攻（浮空状态没有出手权）
	if _launched:
		_winding = false
		_windup = 0.0
		return

	_atk_cd = maxf(0.0, _atk_cd - delta)
	_update_attack(delta)


## 前摇 0.45s（变红）→ 还在范围内就造成伤害
func _update_attack(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var dx: float = player.global_position.x - global_position.x
	var dy: float = player.global_position.y - global_position.y
	if absf(dx) > 4.0:
		_facing = signi(int(dx))
		visual.scale.x = _facing

	# 不量「中心到中心」，量「我这刀能不能碰到人」：身前一块矩形判定盒
	var in_range := _hits_player()

	# 打得着就停，打不着但看得见就走过去
	if _winding or _dead:
		_walk_vx = 0.0
	elif not in_range and absf(dx) < sight_range and absf(dy) < 160.0:
		_walk_vx = _facing * move_speed
	else:
		_walk_vx = 0.0

	if _winding:
		_windup -= delta
		# 起手：身体往玩家方向压过去 + 亮成暖色，比单纯变色更容易被看见
		_lean = lerpf(_lean, _facing * 7.0, 12.0 * delta)
		visual.position.x = _lean
		modulate = Color(1.7, 0.75, 0.65)
		if _windup <= 0.0:
			_winding = false
			modulate = Color.WHITE
			if in_range and player.has_method("take_damage"):
				_strike(player, dx)
			_atk_cd = attack_cooldown
	elif _atk_cd <= 0.0 and in_range:
		_winding = true
		_windup = windup_time
		Audio.play_varied("swing_light", -14.0)
	else:
		_lean = lerpf(_lean, 0.0, 10.0 * delta)
		visual.position.x = _lean


## 身前的矩形判定盒：从身体前缘（半宽 30）往外 attack_range，高 attack_height
## 用「盒子能不能盖住玩家」代替「中心距 < 半径」，两种体型之间的手感才一致
## 形状/查询对象在 _ready 预建并复用，不在每个物理帧 new
func _hits_player() -> bool:
	var size := Vector2(attack_range, attack_height)
	if _hit_shape.size != size:
		_hit_shape.size = size
	_hit_query.shape = _hit_shape

	var space := get_world_2d().direct_space_state
	_hit_query.transform = Transform2D(
		0.0,
		global_position + Vector2(_facing * (30.0 + attack_range * 0.5), -attack_height * 0.5)
	)
	for hit in space.intersect_shape(_hit_query, 4):
		var body = hit.get("collider")
		if body != null and body.has_method("take_damage"):
			return true
	return false


## 出手：前冲一小步 + 白弧 + 伤害数字，玩家才「感觉得到被打」
func _strike(player: Node, dx: float) -> void:
	_lean = _facing * 26.0
	visual.position.x = _lean
	_slash.visible = true
	_slash.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_slash, "modulate:a", 0.0, 0.12)
	tween.tween_callback(func() -> void: _slash.visible = false)
	Audio.play_varied("swing_heavy", -8.0)
	# 伤害数字统一由 player.take_damage 负责，这里不再重复飘一个
	player.take_damage(damage, signi(int(dx)))


func _die() -> void:
	_dead = true
	Audio.play_varied("enemy_die", -5.0)
	collision.set_deferred("disabled", true)
	var parent := get_parent()
	if parent != null and parent.has_method("add_gold"):
		parent.add_gold(gold_reward)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
