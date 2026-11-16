"""一次性 codemod：把 Audio.play(...) 批量插进各脚本（2026-11 已完成）。

仅作历史留档，不再运行；里面的路径是当时的绝对路径，已随目录调整失效。
"""
import io

BASE = r'D:\Self-Development Salvation\game'


def patch(rel, pairs, must=True):
    path = BASE + '\\' + rel
    s = io.open(path, encoding='utf-8').read()
    missing = []
    for a, b in pairs:
        if a not in s:
            missing.append(a.splitlines()[0][:60])
            continue
        s = s.replace(a, b, 1)
    io.open(path, 'w', encoding='utf-8').write(s)
    print(rel, 'missing=' + repr(missing))


# ---------- Fx：命中音挂在 impact 上 ----------
patch(r'autoload\fx.gd', [
    ('func impact(dmg: float) -> void:\n\tvar tier := _tier(dmg)',
     'func impact(dmg: float, with_sound := true) -> void:\n\tvar tier := _tier(dmg)\n\tif with_sound:\n\t\tAudio.play_hit(dmg)'),
])

# ---------- 玩家 ----------
patch(r'scenes\player\player.gd', [
    ('\tFx.impact(amount)          # 挨打也要有停顿和震屏',
     '\tFx.impact(amount, false)   # 挨打也要有停顿和震屏，音效下面单独播\n\tAudio.play_varied("hurt", -2.0)'),
    ('func _die() -> void:\n\t_dead = true',
     'func _die() -> void:\n\t_dead = true\n\tAudio.play("die", -3.0)'),
    ('\tstate = State.ATTACK\n\tif not _air_mode:\n\t\tvelocity.x = 0.0\n\tslash.visible = false',
     '\tstate = State.ATTACK\n\tif not _air_mode:\n\t\tvelocity.x = 0.0\n\tslash.visible = false\n'
     '\tvar heavy: bool = float(a.get("mult", 1.0)) >= 1.2\n'
     '\tAudio.play_varied("swing_heavy" if heavy else "swing_light", -7.0)'),
    ('\t_move_remaining = dodge_distance', '\t_move_remaining = dodge_distance\n\tAudio.play_varied("dodge", -7.0)'),
    ('\t_move_remaining = dash_distance', '\t_move_remaining = dash_distance\n\tAudio.play("dash", -3.0)'),
    ('\t\tif is_on_floor():\n\t\t\tvelocity.y = jump_velocity\n\t\t\t_jumps_left = max_jumps - 1\n\t\telif _jumps_left > 0:\n\t\t\tvelocity.y = jump_velocity * second_jump_scale\n\t\t\t_jumps_left -= 1',
     '\t\tif is_on_floor():\n\t\t\tvelocity.y = jump_velocity\n\t\t\t_jumps_left = max_jumps - 1\n\t\t\tAudio.play_varied("jump", -9.0, 0.04)\n\t\telif _jumps_left > 0:\n\t\t\tvelocity.y = jump_velocity * second_jump_scale\n\t\t\t_jumps_left -= 1\n\t\t\tAudio.play("jump", -7.0, 1.15)'),
    ('\t\t_:\n\t\t\t_process_move(delta)',
     '\t\t_:\n\t\t\t_process_move(delta)\n\n\t# 落地音（用上一帧的地面状态判断，避免站在地上时反复触发）\n\tif is_on_floor() and not _was_on_floor:\n\t\tAudio.play_varied("land", -10.0, 0.05)\n\t_was_on_floor = is_on_floor()'),
    ('var _knock := 0.0', 'var _knock := 0.0\nvar _was_on_floor := true'),
])

# ---------- 木桩 ----------
patch(r'scenes\enemies\enemy_dummy.gd', [
    ('func _die() -> void:\n\t_dead = true', 'func _die() -> void:\n\t_dead = true\n\tAudio.play_varied("enemy_die", -5.0)'),
    ('\t\t_winding = true\n\t\t_windup = windup_time',
     '\t\t_winding = true\n\t\t_windup = windup_time\n\t\tAudio.play_varied("swing_light", -14.0)'),
])

# ---------- Boss ----------
patch(r'scenes\enemies\boss.gd', [
    ('\t\t\tactive = true', '\t\t\tactive = true\n\t\t\tAudio.play("boss_roar", -2.0)'),
    ('func _transition(new_phase: int) -> void:\n\tphase = new_phase',
     'func _transition(new_phase: int) -> void:\n\tphase = new_phase\n\tAudio.play("boss_phase", -2.0)'),
    ('func _die() -> void:\n\t_dead = true', 'func _die() -> void:\n\t_dead = true\n\tAudio.play("enemy_die", -2.0, 0.7)'),
    ('func _telegraph(seconds: float) -> void:\n', 'func _telegraph(seconds: float) -> void:\n\tAudio.play("boss_swing", -8.0)\n'),
    ('\tprint("[Boss] 召唤了 2 只小怪")', '\tAudio.play("summon", -3.0)\n\tprint("[Boss] 召唤了 2 只小怪")'),
])

# ---------- 结算 / 界面 ----------
patch(r'scenes\ui\results.gd', [
    ('\tSave.record_run(float(_stats.get("time", 0.0)), _grade(), int(_stats.get("gold", 0)))\n\t_build()',
     '\tSave.record_run(float(_stats.get("time", 0.0)), _grade(), int(_stats.get("gold", 0)))\n\t_build()\n\tAudio.play("victory", -4.0)\n\tAudio.hook_buttons(self)'),
])
patch(r'scenes\ui\title.gd', [('\t_build()\n\t_report_state()', '\t_build()\n\t_report_state()\n\tAudio.hook_buttons(self)')])
patch(r'scenes\ui\pause_menu.gd', [('\t_build()', '\t_build()\n\tAudio.hook_buttons(self)')])
patch(r'scenes\ui\settings_panel.gd', [('\t_build()', '\t_build()\n\tAudio.hook_buttons(self)')])
print('done')
