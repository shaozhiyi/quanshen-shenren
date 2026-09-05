class_name LoadingUI
extends RefCounted
## 全屏加载覆盖层（纯代码绘制，不用任何素材）：主菜单点"新游戏/读取存档/输入种子"之后
## 立刻盖住画面，把"读场景素材 → 生成地形起伏 → 铺碰撞面"这几段耗时念成进度。
##
## 为什么要它：世界是在主线程上一口口建出来的（实测场景素材 ~1.4 秒、地表材质 ~0.9 秒、
## 地形碰撞 ~1.7 秒），主线程一忙画面就冻住。光有个静止的"加载中"等于没有，所以配套改了两处：
##   1) menu.gd 用 ResourceLoader.load_threaded_request 在后台线程读场景与 2K 贴图；
##   2) terrain.gd 把高度场采样按行切片，每片 await 一帧（LoadingUI.active() 为真时才分片，
##      直接进场景或无头自检仍走一口建完的老路，不改变测试的时序约定）。
## 每一次让帧都会回到 Card._process 重画，星轮与进度条才真的在动。
##
## 挂在 root Window 下（不是 current_scene 的孩子），所以换场景时它不会被顺手释放。
## 没显示过时调 stage()/finish() 都是空操作；拿不到场景树（无头自检）时同样静默跳过。

const BG := Color(0.043, 0.047, 0.067, 1.0)
const GOLD := Color(1.0, 0.88, 0.42)
const DIM := Color(1, 1, 1, 0.62)
const BAR_W := 380.0
const RING_Y := 344.0               # 星轮中心（屏幕 720 高里的固定坐标）
const BAR_Y := 422.0                # 进度条顶边
const FADE_IN := 0.18
const FADE_OUT := 0.32

static var _layer: CanvasLayer
static var _dim: Control            # 一个 Control 兜住全部子节点，淡入淡出只动它的 modulate
static var _card: Card
static var _stage: Label
static var _pct: Label
static var _target := 0.0
static var _fade_in := 0.0
static var _fade_out := -1.0


static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## 有没有加载界面正盖着（地形据此决定要不要分片建碰撞）
static func active() -> bool:
	return _layer != null and is_instance_valid(_layer)


## 盖上加载层（重复调用只更新文字，不会盖第二层）
static func show(msg := "正在进入世界…") -> void:
	var tr := _tree()
	if tr == null or tr.root == null:
		return
	if active():
		# 已经盖着：重新归零再走一遍（stage() 有"只许前进"的闸，这里必须直接重置）
		_target = 0.0
		if _card != null and is_instance_valid(_card):
			_card.target = 0.0
		if _stage != null and is_instance_valid(_stage):
			_stage.text = msg
		return
	_target = 0.0
	_fade_in = FADE_IN
	_fade_out = -1.0
	_layer = CanvasLayer.new()
	_layer.layer = 200                              # 盖住 HUD(10) 与背包
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS   # 暂停/背包也不该挡住加载动画
	tr.root.add_child(_layer)

	_dim = Control.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.modulate = Color(1, 1, 1, 0.0)
	_layer.add_child(_dim)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.add_child(bg)

	_card = Card.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.add_child(_card)

	_dim.add_child(_caption("全是神人", 236, 44, Color(1, 0.95, 0.72)))
	_pct = _caption("0%", 440, 18, GOLD)
	_dim.add_child(_pct)
	_stage = _caption(msg, 472, 16, DIM)
	_dim.add_child(_stage)


static func _caption(text: String, y: float, size_pt: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = Vector2(0, y)
	l.size = Vector2(1280, size_pt + 12)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_pt)
	l.add_theme_color_override("font_color", col)
	if size_pt >= 40:
		l.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.02, 0.9))
		l.add_theme_constant_override("outline_size", 8)
	return l


## 报进度：frac 取 0..1（同一个值反复给也没关系），msg 非空则换一行说明
## 进度只许前进：各阶段是按物理帧/后台线程推进的，彼此会交错
## （例如地形已经跑到 100%，分帧进场景那边才补上最后一个节点的 42%），
## 不挡住回退就会出现"进度条从满格倒拽回去"。要重置请走 show()。
static func stage(frac: float, msg := "") -> void:
	if not active():
		return
	var v := clampf(frac, 0.0, 1.0)
	if v < _target:
		return
	_target = v
	if _card != null and is_instance_valid(_card):
		_card.target = _target
	if msg != "" and _stage != null and is_instance_valid(_stage):
		_stage.text = msg


## 收摊：淡出后自毁。没盖着时调用是空操作（幂等）。
static func finish() -> void:
	if not active() or _fade_out >= 0.0:
		return
	stage(1.0, "世界就绪")
	_fade_out = FADE_OUT


## 每个根节点在加载界面上的名字（只影响文案，不影响顺序）
const BOOT_LABEL := {
	"WorldEnvironment": "正在打亮天空",
	"Sun": "正在摆太阳",
	"SkyDome": "正在生成天空穹顶",
	"Ground": "正在生成地形",
	"GroundDetails": "正在撒石子",
	"BossField": "正在放置 BOSS",
	"Arena": "正在搭建纯白空间",
	"HighwayArena": "正在铺设国道",
	"Player": "正在放下你",
	"HUD": "正在装界面",
	"Inventory": "正在整理背包",
}


## 分帧进场景：instantiate 出来的根节点先单独进树，再把直接子节点一个一个挂回去。
## 每个节点的 _ready 只占一帧，中间这一帧回到这里 → 覆盖层能继续画，
## 于是"点开始后整幅画面僵死 4.5 秒"变成"一格一格推进的加载动画"。
## 顺序与场景文件里完全一致（先 Ground 再 BossField 再 Player…），依赖关系不变。
## 这里是静态协程：菜单自己可能中途被释放，静态函数的续体不挂在菜单实例上，安全。
static func enter_game(tr: SceneTree, ps: PackedScene) -> void:
	if tr == null or ps == null:
		return
	var old := tr.current_scene
	var w := ps.instantiate()
	var kids: Array[Node] = []
	for c in w.get_children():
		kids.append(c)
	for c in kids:
		w.remove_child(c)
	tr.root.add_child(w)
	tr.current_scene = w
	if old != null and is_instance_valid(old):
		old.queue_free()
	var total := kids.size()
	for i in total:
		var c: Node = kids[i]
		stage(0.34 + 0.08 * float(i + 1) / float(total), "%s %d/%d" % [
			String(BOOT_LABEL.get(String(c.name), "正在唤醒世界")), i + 1, total])
		w.add_child(c)
		await tr.process_frame


## 每帧由 Card._process 驱动：淡入淡出 + 收尾清理
static func _tick(delta: float) -> void:
	if _layer == null or not is_instance_valid(_layer):
		return
	if _fade_in > 0.0:
		_fade_in = maxf(_fade_in - delta, 0.0)
	if _fade_out >= 0.0:
		_fade_out = maxf(_fade_out - delta, 0.0)
	var a := 1.0
	if _fade_in > 0.0:
		a = 1.0 - _fade_in / FADE_IN
	if _fade_out >= 0.0:
		a = _fade_out / FADE_OUT
	if _dim != null and is_instance_valid(_dim):
		_dim.modulate = Color(1, 1, 1, clampf(a, 0.0, 1.0))
	if _fade_out >= 0.0 and _fade_out <= 0.0:
		_layer.queue_free()
		_layer = null
		_dim = null
		_card = null
		_stage = null
		_pct = null


# ---- 自绘卡片：12 枚星形指针转圈 + 进度条（进度由外部喂，这里负责让它动起来）----
class Card extends Control:
	var target := 0.0
	var _shown := 0.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		# 缓动追上目标：进度条滑得顺，也避免"卡在某一档"时看着像死机
		_shown = lerpf(_shown, target, minf(1.0, delta * 5.0))
		LoadingUI._tick(delta)
		var pct := LoadingUI._pct
		if pct != null and is_instance_valid(pct):
			pct.text = "%d%%" % int(roundf(_shown * 100.0))
		queue_redraw()

	func _draw() -> void:
		var cx := size.x * 0.5
		var cy := RING_Y
		# 星轮：12 枚菱形沿圆周排布，越靠近"指针头部"越亮，整体缓慢旋转
		var spin := _t * 1.9
		for i in 12:
			var a := spin + TAU * float(i) / 12.0
			var fade := clampf(1.0 - float(i) / 12.0, 0.10, 1.0)
			var r := 58.0
			var c := Vector2(cx + cos(a) * r, cy + sin(a) * r)
			var s := 5.0 + 3.4 * fade
			var pts := PackedVector2Array([
				c + Vector2(0, -s), c + Vector2(s * 0.62, 0),
				c + Vector2(0, s), c + Vector2(-s * 0.62, 0)])
			draw_colored_polygon(pts, Color(GOLD.r, GOLD.g, GOLD.b, 0.16 + 0.8 * fade))
		# 轨道 + 进度条 + 亮头
		var x0 := cx - BAR_W * 0.5
		var y0 := BAR_Y
		draw_rect(Rect2(x0, y0, BAR_W, 10.0), Color(1, 1, 1, 0.10))
		var w := BAR_W * clampf(_shown, 0.0, 1.0)
		if w > 1.0:
			draw_rect(Rect2(x0, y0, w, 10.0), Color(GOLD.r, GOLD.g, GOLD.b, 0.92))
			draw_rect(Rect2(x0 + w - 3.0, y0 - 3.0, 3.0, 16.0), Color(1, 1, 1, 0.95))
		draw_rect(Rect2(x0, y0, BAR_W, 10.0), Color(1, 1, 1, 0.16), false, 1.0)
