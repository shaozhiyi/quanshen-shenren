extends RefCounted
## 极轻量音效播放器：一次性 AudioStreamPlayer，播完自动释放，不占用场景结构。
## 素材放在 assets/audio/（jc-sounds「Fantasy SFX Pack Vol 1」，CC-BY 4.0，见 CREDITS.txt）。
## 一个"音效"由一到若干层组成；同一层可以配多个变体文件，每次随机挑一个（连挥不会机关枪感）。
## 任一文件缺失都不会报错，只是没声音 —— 代码可以先接，素材后补也不会黑屏。

const DIR := "res://assets/audio/"

# id -> {db: 整体音量, cut: 是否打断上一个同种音效, layers: [{files:[...], db, delay}]}
const SOUNDS := {
	"swing": {"db": -6.0, "cut": true, "layers": [
		{"files": ["sword_swing.wav", "sword_swing_2.wav"], "db": 0.0, "delay": 0.0},
	]},
	"draw":  {"db": -10.0, "cut": false, "layers": [
		{"files": ["bow_draw.wav"], "db": 0.0, "delay": 0.0},
	]},
	"shot":  {"db": -7.0, "cut": true, "layers": [
		{"files": ["bow_shot.wav"], "db": 0.0, "delay": 0.0},
	]},
}

static var _streams := {}        # path -> AudioStream（缺失记 false，避免反复探测）
static var _last := {}           # id -> 上次播放时刻(msec)，用于节流


static func play(id: String, vol_db := 0.0) -> void:
	## 播一次音效（所有层）。vol_db：本次额外音量；同种 60 毫秒内不重播
	var cfg: Dictionary = SOUNDS.get(id, {})
	if cfg.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, -999999)) < 60:
		return
	_last[id] = now
	var layers: Array = cfg.get("layers", [])
	for i in layers.size():
		var L: Dictionary = layers[i]
		var files: Array = L.get("files", [])
		if files.is_empty():
			continue
		# 同层多变体：随机起一个，全缺失则整层跳过
		var order: Array = files.duplicate()
		order.shuffle()
		var stream: AudioStream = null
		for f in order:
			stream = _stream_of(String(f))
			if stream != null:
				break
		if stream == null:
			continue
		_play_one(stream, float(cfg.get("db", 0.0)) + float(L.get("db", 0.0)) + vol_db,
			float(L.get("delay", 0.0)), id, bool(cfg.get("cut", false)))


static func _play_one(stream: AudioStream, db: float, delay: float, id: String, cut: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	if host == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = clampf(1.0 + randf_range(-0.04, 0.04), 0.8, 1.3)
	p.bus = "Master"
	p.set_meta("sfx", id)
	# 打断型：先掐掉上同一个还响着的（连挥两下不会糊成一片）
	if cut:
		for c in host.get_children():
			if c is AudioStreamPlayer and String((c as Node).get_meta("sfx", "")) == id:
				(c as AudioStreamPlayer).stop()
	host.add_child(p)
	p.finished.connect(p.queue_free)     # 播完即释放，不留垃圾节点
	if delay > 0.0:
		p.play(delay)                     # AudioStreamPlayer 自带延迟起播
	else:
		p.play()


static func _stream_of(file: String) -> AudioStream:
	## 首次使用时从磁盘加载并缓存；文件不存在则记 false，之后不再探测
	if file == "":
		return null
	var path := String(DIR) + file
	if _streams.has(path):
		var cached = _streams[path]
		return cached if cached is AudioStream else null
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	_streams[path] = s if s != null else false
	return s
