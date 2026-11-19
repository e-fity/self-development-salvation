extends Node
## 全局手感反馈：命中停顿 / 震屏 / 伤害数字
## 数值来自 PRD 5.2：轻 40ms·2px / 中 55ms·4px / 重 80ms·6px

var hitstop_scale := 1.0
var shake_scale := 1.0     # 玩家设置（存档里的「震屏强度」）
var shake_tune := 1.0      # 调试面板的临时倍率，不改存档
var numbers_enabled := true

var _stop_token := 0


## 打中目标时调用一次：命中停顿 + 震屏（多目标时传最大的那段伤害）
## stop_override > 0 时用它代替按伤害分档的停顿（技能可以配置轻/重）
func impact(dmg: float, with_sound := true, stop_override := -1.0) -> void:
	var tier := _tier(dmg)
	if with_sound:
		Audio.play_hit(dmg)
	var stop_ms: float = [40.0, 55.0, 80.0][tier] * hitstop_scale
	if stop_override > 0.0:
		stop_ms = stop_override * 1000.0 * hitstop_scale
	var amp: float = [2.0, 4.0, 6.0][tier] * shake_scale * shake_tune

	_hit_stop(stop_ms / 1000.0)

	var cam := get_viewport().get_camera_2d()
	if cam != null and cam.has_method("shake"):
		cam.shake(amp, 0.15)


## 单个目标头顶飘一个数字
func damage_number(world_pos: Vector2, dmg: float, color := Color(1, 1, 1)) -> void:
	if not numbers_enabled:
		return
	_spawn_number(world_pos, dmg, _tier(dmg) == 2, color)


func _tier(dmg: float) -> int:
	if dmg < 10.0:
		return 0
	if dmg <= 20.0:
		return 1
	return 2


## 用真实时间计时，避免 time_scale = 0 时定时器自己被冻住
func _hit_stop(seconds: float) -> void:
	_stop_token += 1
	var token := _stop_token
	Engine.time_scale = 0.0
	await get_tree().create_timer(seconds, true, false, true).timeout
	if token == _stop_token:
		Engine.time_scale = 1.0


func _spawn_number(world_pos: Vector2, dmg: float, heavy: bool, color := Color(1, 1, 1)) -> void:
	var host := get_tree().current_scene
	if host == null:
		return

	var label := Label.new()
	label.text = str(int(round(dmg)))
	label.add_theme_font_size_override("font_size", 34 if heavy else 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.2) if heavy else color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.z_index = 100
	host.add_child(label)
	label.position = world_pos

	var tw := label.create_tween()
	tw.set_ignore_time_scale(true)
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", world_pos.y - 46.0, 0.45)
	tw.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.15)
	tw.set_parallel(false)
	tw.tween_callback(label.queue_free)
