extends CharacterBody2D
## 「蓝橙」：移动 / 跳跃 / 三连击 / 闪避 / 橙闪 / 逆鳞 / 零点（灰盒）
## 参数：PRD 4.3（帧数据）· 4.5（能量/无敌/霸体）· 5.2（技能）

# ---------------- 数值（来自 data/player.json，Data 负责合并默认值） ----------------
var fps := 15.0

# 移动
var move_speed := 220.0
var jump_velocity := -520.0
var gravity := 1400.0
var max_jumps := 2
var second_jump_scale := 0.8

# 攻击
var combo_grace := 0.45
var attacks: Array = []
var air_attack: Dictionary = {}
var max_air_attacks := 2
var land_lock_time := 0.15

# 闪避
var dodge_frames := 5
var dodge_invuln_from := 1
var dodge_invuln_to := 3
var dodge_distance := 160.0
var dodge_cooldown := 1.2

# 橙闪
var dash_frames := 8
var dash_invuln_from := 3
var dash_invuln_to := 5
var dash_distance := 220.0
var dash_move_frames := 5
var dash_cooldown := 6.0
var dash_mult := 1.5
var dash_knockback := 120.0

# 受击/重生反馈（data/player.json 的 feedback 段）
var hurt_knockback := 240.0
var hurt_invuln_time := 0.5
var respawn_delay := 1.5
var combo_reset_time := 3.0

# 能量（PRD 4.5：命中 +6、击杀 +15、受击 −10，上限 100）
var max_energy := 100.0
var energy_on_hit := 6.0
var energy_on_kill := 15.0
var energy_on_damage := 10.0

# 逆鳞（L）：10 帧，1–3 起手 / 4 判定 / 5–10 收招，半径 120，10s 冷却，2s 霸体
var skill2_frames := 10
var skill2_startup := 3
var skill2_active := 1
var skill2_recover := 6
var skill2_radius := 120.0
var skill2_mult := 1.2
var skill2_knockback := 120.0
var skill2_cooldown := 10.0
var skill2_armor := 2.0

# 零点（I）：24 帧，1–6 起手 / 7–12 判定+无敌 / 13–24 收招，倍率 4.0 + 连击加成
var ult_frames := 24
var ult_startup := 6
var ult_active := 6
var ult_recover := 12
var ult_mult := 4.0
var ult_combo_bonus := 0.005
var ult_combo_cap := 1.0
var ult_knockback := 160.0
var ult_width := 4800.0
var ult_height := 2400.0

@export var attack_power := 12.0        # PRD：ATK 初始 12
@export var hitbox_size := Vector2(100, 130)
@export var hitbox_offset := Vector2(55, -90)

enum State { IDLE, ATTACK, DODGE, DASH, SKILL2, ULTIMATE, DEAD }
const STATE_NAMES := ["待机", "攻击", "闪避", "橙闪", "逆鳞", "零点", "死亡"]

# 调试面板读这几个
var dodge_cd := 0.0
var dash_cd := 0.0
var skill2_cd := 0.0

var state: State = State.IDLE
var invulnerable := false

# 能量（0–max_energy）；零点在判定帧一次性清空
var energy := 0.0

# 生命
var max_hp := 100.0
var hp := 100.0
var _hurt_invuln := 0.0
var _dead := false

# 结算统计
var combo := 0
var max_combo := 0
var hits_taken := 0
var _combo_timer := 0.0

var _state_time := 0.0
var _action_dir := 1
var _move_remaining := 0.0

# 攻击运行时
var _atk_index := 0
var _atk_total := 0.0
var _active_from := 0.0
var _active_to := 0.0
var _hit_done := false
var _buffered := false
var _combo_next := 0
var _grace := 0.0
var _hit_ids: Array[int] = []
var _current_def: Dictionary = {}
var _air_mode := false
var _air_attacks := 0
var _land_lock := 0.0

var _jumps_left := max_jumps
var _facing := 1
var _knock := 0.0
var _was_on_floor := true        # 受击击退的横向速度，逐帧衰减

## 霸体剩余时间：逆鳞期间受击不打断、不被击退，伤害 ×0.8（PRD 4.5）
var _super_armor := 0.0
var _ult_mult := 0.0
var _rect := RectQuery.new()

const ART_IDLE := "res://art/player/idle.png"
const ART_HEIGHT := 180.0

@onready var visual: Node2D = $Visual
@onready var slash: Polygon2D = $Visual/Slash


func _ready() -> void:
	_load_data()
	slash.visible = false
	_apply_art()


## 有正式贴图就用贴图，没有就保留方块占位（美术可以随时换，不用改代码）
func _apply_art() -> void:
	if not ResourceLoader.exists(ART_IDLE):
		return
	var tex := load(ART_IDLE) as Texture2D
	if tex == null:
		return
	var sprite := Sprite2D.new()
	sprite.name = "Art"
	sprite.texture = tex
	sprite.centered = true
	var s := ART_HEIGHT / float(tex.get_height())
	sprite.scale = Vector2(s, s)
	sprite.position = Vector2(0.0, -ART_HEIGHT * 0.5)   # 脚底对齐 y=0
	visual.add_child(sprite)
	visual.move_child(sprite, 0)                        # 压在最底层，别盖住刀光

	# 脚下投影，让角色「站」在地上而不是飘着
	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		pts.append(Vector2(cos(a) * 46.0, sin(a) * 9.0 + -3.0))
	shadow.polygon = pts
	shadow.color = Color(0.0, 0.0, 0.0, 0.28)
	shadow.z_index = -2
	visual.add_child(shadow)
	visual.move_child(shadow, 0)

	for node_name in ["Body", "Eye"]:
		var placeholder := visual.get_node_or_null(node_name)
		if placeholder != null:
			placeholder.visible = false


## 从 data/player.json 读数值；缺字段 / 文件丢失时由 Data 回落默认值
func _load_data() -> void:
	var d: Dictionary = Data.player
	var mv: Dictionary = d.get("move", {})
	move_speed = Data.num(mv, "speed", move_speed)
	jump_velocity = Data.num(mv, "jump_velocity", jump_velocity)
	gravity = Data.num(mv, "gravity", gravity)
	max_jumps = int(Data.num(mv, "max_jumps", float(max_jumps)))
	second_jump_scale = Data.num(mv, "second_jump_scale", second_jump_scale)

	var st: Dictionary = d.get("stats", {})
	max_hp = Data.num(st, "max_hp", max_hp)
	hp = max_hp
	attack_power = Data.num(st, "attack_power", attack_power)

	fps = Data.num(d, "fps", fps)
	combo_grace = Data.num(d, "combo_grace", combo_grace)
	var fb: Dictionary = d.get("feedback", {})
	hurt_knockback = Data.num(fb, "hurt_knockback", hurt_knockback)
	hurt_invuln_time = Data.num(fb, "hurt_invuln", hurt_invuln_time)
	respawn_delay = Data.num(fb, "respawn_delay", respawn_delay)
	combo_reset_time = Data.num(fb, "combo_reset", combo_reset_time)
	attacks = d.get("attacks", attacks)
	air_attack = d.get("air_attack", air_attack)
	max_air_attacks = int(Data.num(air_attack, "max_uses", float(max_air_attacks)))
	land_lock_time = Data.num(air_attack, "land_lock", land_lock_time)

	var dg: Dictionary = d.get("dodge", {})
	dodge_frames = int(Data.num(dg, "frames", float(dodge_frames)))
	dodge_invuln_from = int(Data.num(dg, "invuln_from", float(dodge_invuln_from)))
	dodge_invuln_to = int(Data.num(dg, "invuln_to", float(dodge_invuln_to)))
	dodge_distance = Data.num(dg, "distance", dodge_distance)
	dodge_cooldown = Data.num(dg, "cooldown", dodge_cooldown)

	var ds: Dictionary = d.get("dash", {})
	dash_frames = int(Data.num(ds, "frames", float(dash_frames)))
	dash_invuln_from = int(Data.num(ds, "invuln_from", float(dash_invuln_from)))
	dash_invuln_to = int(Data.num(ds, "invuln_to", float(dash_invuln_to)))
	dash_distance = Data.num(ds, "distance", dash_distance)
	dash_move_frames = int(Data.num(ds, "move_frames", float(dash_move_frames)))
	dash_cooldown = Data.num(ds, "cooldown", dash_cooldown)
	dash_mult = Data.num(ds, "mult", dash_mult)
	dash_knockback = Data.num(ds, "knockback", dash_knockback)

	var en: Dictionary = d.get("energy", {})
	max_energy = Data.num(en, "max", max_energy)
	energy_on_hit = Data.num(en, "on_hit", energy_on_hit)
	energy_on_kill = Data.num(en, "on_kill", energy_on_kill)
	energy_on_damage = Data.num(en, "on_damage", energy_on_damage)
	energy = 0.0

	var s2: Dictionary = d.get("skill2", {})
	skill2_frames = int(Data.num(s2, "frames", float(skill2_frames)))
	skill2_startup = int(Data.num(s2, "startup", float(skill2_startup)))
	skill2_active = int(Data.num(s2, "active", float(skill2_active)))
	skill2_recover = int(Data.num(s2, "recover", float(skill2_recover)))
	skill2_radius = Data.num(s2, "radius", skill2_radius)
	skill2_mult = Data.num(s2, "mult", skill2_mult)
	skill2_knockback = Data.num(s2, "knockback", skill2_knockback)
	skill2_cooldown = Data.num(s2, "cooldown", skill2_cooldown)
	skill2_armor = Data.num(s2, "armor_time", skill2_armor)

	var ul: Dictionary = d.get("ultimate", {})
	ult_frames = int(Data.num(ul, "frames", float(ult_frames)))
	ult_startup = int(Data.num(ul, "startup", float(ult_startup)))
	ult_active = int(Data.num(ul, "active", float(ult_active)))
	ult_recover = int(Data.num(ul, "recover", float(ult_recover)))
	ult_mult = Data.num(ul, "mult", ult_mult)
	ult_combo_bonus = Data.num(ul, "combo_bonus", ult_combo_bonus)
	ult_combo_cap = Data.num(ul, "combo_bonus_cap", ult_combo_cap)
	ult_knockback = Data.num(ul, "knockback", ult_knockback)
	ult_width = Data.num(ul, "width", ult_width)
	ult_height = Data.num(ul, "height", ult_height)

	_jumps_left = max_jumps


func _physics_process(delta: float) -> void:
	dodge_cd = maxf(0.0, dodge_cd - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	skill2_cd = maxf(0.0, skill2_cd - delta)
	_super_armor = maxf(0.0, _super_armor - delta)

	# 受击后的短暂无敌 + 闪烁（死亡动画期间不抢 visual.modulate）
	if _hurt_invuln > 0.0 and not _dead:
		_hurt_invuln -= delta
		var blink := int(_hurt_invuln * 20.0) % 2 == 0
		_apply_visual_alpha(0.45 if blink else 1.0)
		if _hurt_invuln <= 0.0:
			_apply_visual_alpha()      # 红闪结束：清掉红色，保留当前状态的透明度

	# 连击计时：3 秒内没有新命中就清零（PRD 4.2）
	if combo > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo = 0

	match state:
		State.ATTACK:
			_process_attack(delta)
		State.DODGE:
			_process_dodge(delta)
		State.DASH:
			_process_dash(delta)
		State.SKILL2:
			_process_skill2(delta)
		State.ULTIMATE:
			_process_ultimate(delta)
		State.DEAD:
			pass
		_:
			_process_move(delta)

	# 落地音（用上一帧的地面状态判断，避免站在地上时反复触发）
	if is_on_floor() and not _was_on_floor:
		Audio.play_varied("land", -10.0, 0.05)
	_was_on_floor = is_on_floor()


## 受击闪烁的底色：红闪期间保留红色，其余时候恢复白
func _flash_tint() -> Color:
	return Color(1.0, 0.6, 0.6) if _hurt_invuln > 0.0 else Color.WHITE


## 当前状态下应有的透明度（闪避/橙闪的无敌段半透明）
func _state_alpha() -> float:
	match state:
		State.DODGE:
			return 0.5 if invulnerable else 1.0
		State.DASH:
			return 0.6 if invulnerable else 1.0
	return 1.0


## 唯一改 visual.modulate 的入口：颜色跟红闪走、透明度跟状态走，
## 避免「红闪在闪避中到期」时只改 alpha、红色残留到动作结束
func _apply_visual_alpha(alpha := -1.0) -> void:
	var c := _flash_tint()
	c.a = _state_alpha() if alpha < 0.0 else alpha
	visual.modulate = c


# ---------------- 受伤 / 死亡 ----------------
func take_damage(amount: float, from_dir: int) -> void:
	if _dead or invulnerable or _hurt_invuln > 0.0:
		return
	var dmg := amount
	if _super_armor > 0.0:
		dmg *= 0.8                     # 霸体：照常受伤但 ×0.8（PRD 4.5）
	hp = maxf(0.0, hp - dmg)
	hits_taken += 1
	_hurt_invuln = hurt_invuln_time
	_gain_energy(-energy_on_damage)

	# 霸体期间不打断动作、不被击退，只掉血
	if _super_armor <= 0.0:
		# 击退不能直接写 velocity.x——_process_move 每帧都会覆盖它，会变成 0
		_knock = from_dir * hurt_knockback
		if state == State.ATTACK or state == State.SKILL2 or state == State.ULTIMATE:
			_end_action()

	Fx.impact(dmg, false)   # 挨打也要有停顿和震屏，音效下面单独播
	Audio.play_varied("hurt", -2.0)
	Fx.damage_number(global_position + Vector2(0, -230), dmg, Color(1.0, 0.42, 0.36))

	if hp <= 0.0:
		_die()


## 能量增减统一入口：命中/击杀加、受击减，永远夹在 0–max 之间
func _gain_energy(amount: float) -> void:
	energy = clampf(energy + amount, 0.0, max_energy)


func is_dead() -> bool:
	return _dead


func _die() -> void:
	_dead = true
	Audio.play("die", -3.0)
	state = State.DEAD
	velocity = Vector2.ZERO
	visual.modulate = Color(1, 1, 1, 0.25)
	print("[玩家] 倒下，%.1f 秒后从检查点重生" % respawn_delay)
	await get_tree().create_timer(respawn_delay).timeout
	_respawn()


func _respawn() -> void:
	if not _dead:
		return
	var level := get_tree().get_first_node_in_group("level")
	if level == null:
		level = get_tree().current_scene
	var pos := Vector2.ZERO
	if level != null and "respawn_point" in level:
		pos = level.respawn_point
	global_position = pos
	hp = max_hp
	energy = 0.0
	_dead = false
	state = State.IDLE
	velocity = Vector2.ZERO
	_super_armor = 0.0
	visual.modulate = Color.WHITE
	_hurt_invuln = 1.0
	print("[玩家] 已重生，HP %.0f" % hp)


# ---------------- 待机 / 移动 ----------------
func _process_move(delta: float) -> void:
	# 落地硬直：0.15 秒内不能行动（PRD 5.3）
	if _land_lock > 0.0:
		_land_lock -= delta
		velocity.x = 0.0
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		return

	if not is_on_floor():
		velocity.y += gravity * delta

	if is_on_floor():
		_jumps_left = max_jumps
		if _air_attacks > 0:
			_air_attacks = 0
			_land_lock = land_lock_time

	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = jump_velocity
			_jumps_left = max_jumps - 1
			Audio.play_varied("jump", -9.0, 0.04)
		elif _jumps_left > 0:
			velocity.y = jump_velocity * second_jump_scale
			_jumps_left -= 1
			Audio.play("jump", -7.0, 1.15)

	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * move_speed + _knock
	_knock = move_toward(_knock, 0.0, 900.0 * delta)
	if not is_zero_approx(dir):
		_facing = signi(int(dir))
		visual.scale.x = _facing

	if _grace > 0.0:
		_grace -= delta
		if _grace <= 0.0:
			_combo_next = 0

	# 优先级：闪避 > 橙闪 > 逆鳞 > 零点 > 普攻（地面三连，空中跳攻最多 2 段）
	if Input.is_action_just_pressed("dodge") and dodge_cd <= 0.0 and is_on_floor():
		_start_dodge(_input_dir())
	elif Input.is_action_just_pressed("skill1") and dash_cd <= 0.0:
		_start_dash()
	elif Input.is_action_just_pressed("skill2") and skill2_cd <= 0.0 and is_on_floor():
		_start_skill2()
	elif Input.is_action_just_pressed("ultimate") and energy >= max_energy and is_on_floor():
		_start_ultimate()
	elif _attack_pressed():
		if is_on_floor():
			_start_attack(_combo_next)
		elif _air_attacks < max_air_attacks:
			_start_air_attack()

	move_and_slide()


## 鼠标停在调试面板等 UI 上时，左键不应该触发攻击
func _attack_pressed() -> bool:
	if not Input.is_action_just_pressed("attack"):
		return false
	return get_viewport().gui_get_hovered_control() == null


func _input_dir() -> int:
	var dir := Input.get_axis("move_left", "move_right")
	if is_zero_approx(dir):
		return _facing
	return signi(int(dir))


# ---------------- 普攻三连 / 跳攻 ----------------
func _start_attack(idx: int) -> void:
	_atk_index = clampi(idx, 0, attacks.size() - 1)
	_air_mode = false
	_current_def = attacks[_atk_index]
	_begin_attack()


func _start_air_attack() -> void:
	_air_mode = true
	_air_attacks += 1
	_current_def = air_attack
	_begin_attack()


func _begin_attack() -> void:
	var a: Dictionary = _current_def
	var startup: float = float(a["startup"]) / fps
	var active: float = float(a["active"]) / fps
	var recover: float = float(a["recover"]) / fps

	_state_time = 0.0
	_atk_total = startup + active + recover
	_active_from = startup
	_active_to = startup + active
	_hit_done = false
	_buffered = false
	_hit_ids.clear()
	state = State.ATTACK
	if not _air_mode:
		velocity.x = 0.0
	slash.visible = false
	var heavy: bool = float(a.get("mult", 1.0)) >= 1.2
	Audio.play_varied("swing_heavy" if heavy else "swing_light", -7.0)


func _process_attack(delta: float) -> void:
	_state_time += delta

	if not is_on_floor():
		velocity.y += gravity * delta

	var in_active := _state_time >= _active_from and _state_time < _active_to
	if in_active and not _hit_done:
		_hit_done = true
		var a: Dictionary = _current_def
		_do_hit(float(a["mult"]), float(a["knockback"]), hitbox_offset)

	slash.visible = in_active

	# 收招阶段可以取消进闪避（PRD 5.3「第 6 帧起可接闪避」）
	if _state_time >= _active_to and Input.is_action_just_pressed("dodge") \
			and dodge_cd <= 0.0 and is_on_floor():
		_start_dodge(_input_dir())
		return

	# 只有地面三连才吃输入缓冲；空中要一按一段
	if not _air_mode and _attack_pressed():
		_buffered = true

	if _state_time >= _atk_total:
		slash.visible = false
		if not _air_mode and _buffered:
			_start_attack((_atk_index + 1) % attacks.size())
			return
		_end_action()
		if not _air_mode:
			_combo_next = (_atk_index + 1) % attacks.size()
			_grace = combo_grace

	move_and_slide()


# ---------------- 闪避 ----------------
func _start_dodge(direction: int) -> void:
	state = State.DODGE
	_state_time = 0.0
	_action_dir = direction
	_facing = direction
	visual.scale.x = _facing
	dodge_cd = dodge_cooldown
	velocity.x = 0.0
	slash.visible = false
	_move_remaining = dodge_distance
	Audio.play_varied("dodge", -7.0)


func _process_dodge(delta: float) -> void:
	_state_time += delta
	var frame := int(_state_time * fps)

	invulnerable = frame >= dodge_invuln_from - 1 and frame <= dodge_invuln_to - 1
	_apply_visual_alpha()

	# 按「剩余距离」推进，保证正好 160px（按时间结束会少算一帧）
	var speed := dodge_distance / (float(dodge_frames) / fps)
	var step := minf(speed * delta, _move_remaining)
	_move_remaining -= step
	velocity.x = _action_dir * (step / delta) if delta > 0.0 else 0.0

	# 先走完这一帧，再判断结束（否则最后一帧的速度会被 _end_action 清零）
	move_and_slide()

	if _move_remaining <= 0.01 or _state_time >= float(dodge_frames + 1) / fps:
		_end_action()


# ---------------- 橙闪 ----------------
func _start_dash() -> void:
	state = State.DASH
	_state_time = 0.0
	_action_dir = _facing
	dash_cd = dash_cooldown
	_hit_done = false
	_hit_ids.clear()
	velocity.x = 0.0
	slash.visible = true
	_move_remaining = dash_distance
	Audio.play("dash", -3.0)


func _process_dash(delta: float) -> void:
	_state_time += delta
	var frame := int(_state_time * fps)

	invulnerable = frame >= dash_invuln_from - 1 and frame <= dash_invuln_to - 1
	_apply_visual_alpha()

	# 正好推进 220px，推进完立刻停住
	if _move_remaining > 0.01 and _state_time < float(dash_move_frames + 1) / fps:
		var speed := dash_distance / (float(dash_move_frames) / fps)
		var step := minf(speed * delta, _move_remaining)
		_move_remaining -= step
		velocity.x = _action_dir * (step / delta) if delta > 0.0 else 0.0
	else:
		velocity.x = 0.0
		slash.visible = false

	if invulnerable and not _hit_done:
		_hit_done = true
		_do_hit(dash_mult, dash_knockback, hitbox_offset)

	if _state_time >= float(dash_frames) / fps:
		_end_action()

	move_and_slide()


# ---------------- 逆鳞（L） ----------------
func _start_skill2() -> void:
	state = State.SKILL2
	_state_time = 0.0
	_hit_done = false
	_hit_ids.clear()
	velocity.x = 0.0
	slash.visible = false
	_super_armor = skill2_armor      # 2 秒霸体：起手即生效
	Audio.play_varied("swing_heavy", -5.0, 0.9)


func _process_skill2(delta: float) -> void:
	_state_time += delta
	if not is_on_floor():
		velocity.y += gravity * delta

	var active_from := float(skill2_startup) / fps
	var active_to := float(skill2_startup + skill2_active) / fps
	var in_active := _state_time >= active_from and _state_time < active_to

	if in_active and not _hit_done:
		_hit_done = true
		# 判定帧才消耗冷却：起手被打断不产生伤害，也不该进 CD（PRD 4.3 硬规则 3）
		skill2_cd = skill2_cooldown
		_hit_circle(skill2_mult, skill2_knockback, global_position, skill2_radius)
		Audio.play("hit_heavy", -4.0, 0.9)
		Fx.impact(14.0)

	slash.visible = in_active

	# 第 8 帧起可接闪避（PRD 4.3）
	if _state_time >= float(8) / fps and Input.is_action_just_pressed("dodge") \
			and dodge_cd <= 0.0 and is_on_floor():
		_start_dodge(_input_dir())
		return

	if _state_time >= float(skill2_frames) / fps:
		_end_action()

	move_and_slide()


# ---------------- 零点（I） ----------------
func _start_ultimate() -> void:
	state = State.ULTIMATE
	_state_time = 0.0
	_hit_done = false
	_hit_ids.clear()
	_ult_mult = ult_mult
	velocity.x = 0.0
	slash.visible = false
	Audio.play_varied("swing_heavy", -2.0, 0.7)


func _process_ultimate(delta: float) -> void:
	_state_time += delta
	if not is_on_floor():
		velocity.y += gravity * delta

	var active_from := float(ult_startup) / fps
	var active_to := float(ult_startup + ult_active) / fps
	var in_active := _state_time >= active_from and _state_time < active_to
	invulnerable = in_active           # 7–12 帧无敌（PRD 4.3 / 4.5）
	_apply_visual_alpha()

	if in_active and not _hit_done:
		_hit_done = true
		var bonus := minf(float(combo) * ult_combo_bonus, ult_combo_cap)
		_ult_mult = ult_mult * (1.0 + bonus)
		_hit_rect(_ult_mult, ult_knockback, global_position, Vector2(ult_width, ult_height), 64)
		energy = 0.0                   # 判定帧清空能量；放在命中之后，避免把这一刀的 +6 又收回来
		Audio.play("hit_heavy", -2.0, 0.7)
		Fx.impact(40.0)

	slash.visible = in_active

	if _state_time >= float(ult_frames) / fps:
		_end_action()

	move_and_slide()


# ---------------- 公共 ----------------
func _end_action() -> void:
	state = State.IDLE
	invulnerable = false
	_state_time = 0.0
	velocity.x = 0.0
	slash.visible = false
	_apply_visual_alpha()


## 对单个目标的伤害：防御只取自目标自身，缺省按 0，公式里不再藏第二份默认值
func _damage_against(mult: float, target: Object) -> float:
	var defense := 0.0
	if "defense" in target:
		defense = float(target.defense)
	return maxf(1.0, attack_power * mult - defense)


func _do_hit(mult: float, knockback: float, offset: Vector2) -> void:
	var center := global_position + Vector2(offset.x * _facing, offset.y)
	_hit_rect(mult, knockback, center, hitbox_size)


## 矩形判定：普攻 / 跳攻 / 橙闪 / 零点
func _hit_rect(mult: float, knockback: float, center: Vector2, size: Vector2,
		max_targets := 8) -> void:
	var targets := _rect.bodies(get_world_2d().direct_space_state, center, size, 2, max_targets)
	_apply_hits(targets, mult, knockback)


## 圆形判定：逆鳞（半径 120）
func _hit_circle(mult: float, knockback: float, center: Vector2, radius: float) -> void:
	var targets := _rect.circle_bodies(get_world_2d().direct_space_state, center, radius, 2, 12)
	_apply_hits(targets, mult, knockback)


func _apply_hits(targets: Array[Node], mult: float, knockback: float) -> void:
	var hit_any := false
	var biggest := 0.0

	for body in targets:
		if not body.has_method("take_hit"):
			continue
		# 同一次动作对同一目标只结算一次
		if _hit_ids.has(body.get_instance_id()):
			continue
		_hit_ids.append(body.get_instance_id())

		# 防御只认目标自己的数值；没有该字段就按 0 算，不在公式里藏第二份默认值
		var dmg := _damage_against(mult, body)
		body.take_hit(dmg, _facing, knockback)
		Fx.damage_number(body.global_position + Vector2(0, -215), dmg)
		_gain_energy(energy_on_hit)
		if bool(body.get("_dead")):
			_gain_energy(energy_on_kill)
		hit_any = true
		biggest = maxf(biggest, dmg)

	if hit_any:
		# 连击计数：每命中一个目标 +1，3 秒内不断
		combo += 1
		max_combo = maxi(max_combo, combo)
		_combo_timer = combo_reset_time
		Fx.impact(biggest)
