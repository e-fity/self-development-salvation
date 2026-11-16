extends Camera2D
## 震屏：按 PRD 5.2 的幅度随机抖动，随时间线性衰减
## 用 Time.get_ticks_msec() 计时，这样命中停顿（time_scale = 0）时也能震

var _amp := 0.0
var _until_ms := 0
var _dur_ms := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func shake(amount: float, seconds: float) -> void:
	_amp = maxf(_amp, amount)
	_dur_ms = maxi(int(seconds * 1000.0), 1)
	_until_ms = maxi(_until_ms, Time.get_ticks_msec() + _dur_ms)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now >= _until_ms:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	var frac := float(_until_ms - now) / float(_dur_ms)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _amp * frac
