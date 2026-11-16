extends Node
## 音效播放（autoload `Audio`）
## 池化 12 个 AudioStreamPlayer，全部走 SFX 总线 —— 音量由设置面板控制（Settings.apply）。
## 占位音由 tools/make_sfx.py 程序化生成，换正式素材只要保持同名覆盖 wav 即可。

const SFX_DIR := "res://audio/sfx/"
const BGM_DIR := "res://audio/bgm/"
const POOL_SIZE := 12

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _cache: Dictionary = {}
var _warned: Dictionary = {}
var _music: AudioStreamPlayer
var _music_name := ""


func _ready() -> void:
	var bus := "SFX"
	if AudioServer.get_bus_index(bus) == -1:
		bus = "Master"
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		add_child(p)
		_pool.append(p)


## 播放一个音效；pitch 是音高倍率（1.0 = 原速）
func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream: AudioStream = _stream(sound)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## 带轻微随机音高，连击时不会听起来像机关枪
func play_varied(sound: String, volume_db := 0.0, jitter := 0.06) -> void:
	play(sound, volume_db, 1.0 + randf_range(-jitter, jitter))


## 命中音按伤害分档，和命中停顿/震屏同一套分档
func play_hit(dmg: float) -> void:
	if dmg < 10.0:
		play_varied("hit_light", -3.0)
	elif dmg <= 20.0:
		play_varied("hit_mid", -2.0)
	else:
		play_varied("hit_heavy", 0.0)


## 给场景里所有按钮挂上点击音（重复调用不会重复连接）
func hook_buttons(root: Node) -> void:
	if root == null:
		return
	if root is BaseButton:
		var b := root as BaseButton
		if not b.pressed.is_connected(_on_button_pressed):
			b.pressed.connect(_on_button_pressed)
	for child in root.get_children():
		hook_buttons(child)


func _on_button_pressed() -> void:
	play("ui_click", -6.0)


# ---------------- 环境音 / BGM ----------------
## 循环播放一首背景音；已经在放同一首时不会重复开始（场景切换也不会断）
func start_music(sound := "rain_loop", volume_db := -16.0) -> void:
	if _music != null and _music_name == sound and _music.playing:
		return
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.bus = "BGM" if AudioServer.get_bus_index("BGM") != -1 else "Master"
		_music.finished.connect(_on_music_finished)
		add_child(_music)
	var stream: AudioStream = _stream(sound, BGM_DIR)
	if stream == null:
		return
	_music.stream = stream
	_music.volume_db = volume_db
	_music_name = sound
	_music.play()


func stop_music() -> void:
	if _music != null:
		_music.stop()


func _on_music_finished() -> void:
	# wav 没开循环，用「播完再放」来循环，循环点已经做了交叉淡化
	if _music != null and _music.stream != null:
		_music.play()


func _stream(sound: String, dir := SFX_DIR) -> AudioStream:
	var key := dir + sound
	if _cache.has(key):
		return _cache[key]
	var path := dir + sound + ".wav"
	if not ResourceLoader.exists(path):
		if not _warned.has(key):
			_warned[key] = true
			push_warning("[音效] 缺少 %s" % path)
		_cache[key] = null
		return null
	var stream: AudioStream = load(path)
	_cache[key] = stream
	return stream
