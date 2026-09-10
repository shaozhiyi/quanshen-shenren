extends SceneTree
## 校验音效**素材文件本身**（绕开 Godot 导入）：
##   1) 四个 wav 的采样峰值统一在 -3 dBFS；
##   2) 按 sfx.gd 的 db + 调用方最大加成算下来，最响一次也不会顶到 0 dBFS（削顶）。
## 注：Godot 导入 wav 默认压成 IMA ADPCM（.sample 里 format=3），所以只能读源文件算峰值。
const DIR := "res://assets/audio/"
const FILES := ["sword_swing.wav", "sword_swing_2.wav", "bow_draw.wav", "bow_shot.wav"]
# id -> {base: sfx.gd 里的 db, extra: 调用方还能加多少 dB}
const MIX := {
	"swing": {"base": -6.0, "extra": 8.0},
	"draw": {"base": -14.0, "extra": 0.0},
	"shot": {"base": -4.0, "extra": 1.5},
}
const OWN := {
	"sword_swing.wav": "swing", "sword_swing_2.wav": "swing",
	"bow_draw.wav": "draw", "bow_shot.wav": "shot",
}
var _fails := 0

func _init() -> void:
	print("== 音效电平自检 ==")
	for f in FILES:
		var bytes := _read_all(DIR + f)
		if bytes.is_empty():
			print("  [失败] 读不到文件 " + f)
			_fails += 1
			continue
		var info := _pcm16_peak(bytes)
		var peak: int = info[0]
		var db: float = -999.0 if peak <= 0 else 20.0 * log(float(peak) / 32768.0) / log(10.0)
		var id := String(OWN[f])
		var mx: Dictionary = MIX[id]
		var loudest: float = db + float(mx.base) + float(mx.extra)
		var ok: bool = absf(db - (-3.0)) < 0.25 and loudest < -0.9
		if not ok:
			_fails += 1
		print("  %-20s 编码 %d 位深 %d 峰值 %6.2f dBFS   最响一次 %6.2f dBFS   %s" % [
			f, int(info[1]), int(info[2]), db, loudest, "OK" if ok else "<<< 不合格"])
	print("== 音效电平自检结果：%d 项失败 ==" % _fails)
	quit(1 if _fails > 0 else 0)

func _read_all(path: String) -> PackedByteArray:
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		return PackedByteArray()
	return fh.get_buffer(fh.get_length())

## 扫 RIFF 块找到 fmt 与 data，按 PCM16 取最大绝对值；返回 [峰值, 编码, 位深]
func _pcm16_peak(b: PackedByteArray) -> Array:
	var pos := 12
	var enc := 0
	var bits := 0
	var data_at := -1
	var data_len := 0
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var sz: int = b[pos + 4] | (b[pos + 5] << 8) | (b[pos + 6] << 16) | (b[pos + 7] << 24)
		if id == "fmt ":
			enc = b[pos + 8] | (b[pos + 9] << 8)          # 1 = PCM
			bits = b[pos + 22] | (b[pos + 23] << 8)       # 位深
		elif id == "data":
			data_at = pos + 8
			data_len = sz
		pos += 8 + sz + (sz & 1)
	if data_at < 0 or enc != 1 or bits != 16:
		return [0, enc, bits]
	var peak := 0
	var i := data_at
	var end: int = mini(data_at + data_len, b.size()) - 1
	while i < end:
		var v: int = b[i] | (b[i + 1] << 8)
		if v > 32767:
			v -= 65536
		peak = maxi(peak, absi(v))
		i += 2
	return [peak, enc, bits]
