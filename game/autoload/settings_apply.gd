extends Node
## 把存档里的设置应用到运行时：音频总线音量、震屏强度、伤害数字开关
## 单独做成 autoload，因为「改设置」和「用设置」发生在不同场景

const BUS_BGM := "BGM"
const BUS_SFX := "SFX"


func _ready() -> void:
	ensure_buses()
	apply()


## 新建 BGM / SFX 两条总线（只建一次）。现在没有音频也先建好，
## 以后接音效时只要把 AudioStreamPlayer 的 bus 指向它们，音量滑条立刻生效。
func ensure_buses() -> void:
	for bus_name in [BUS_BGM, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


## 把当前设置全部重新应用一遍（改完设置调一次，启动时也调一次）
func apply() -> void:
	ensure_buses()
	_apply_bus(BUS_BGM, float(Save.get_setting("bgm", 1.0)))
	_apply_bus(BUS_SFX, float(Save.get_setting("sfx", 1.0)))

	Fx.shake_scale = float(Save.get_setting("shake", 1.0))
	Fx.numbers_enabled = bool(Save.get_setting("numbers", true))


func _apply_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


## 教学开关：教学层每帧问一次，关掉就整层不发提示
func tutorial_enabled() -> bool:
	return bool(Save.get_setting("tutorial", true))
