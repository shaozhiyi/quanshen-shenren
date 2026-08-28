extends Area3D
## 掉落箱：玩家丢弃装备后在地上生成的可拾取物。
## 用 game-icons.net 的 open-chest（CC-BY, skoll）作为广告牌图标，走近按 E 回收。

var item_id := ""
var item_count := 1
var _visual: Sprite3D


func setup(id: String, count: int = 1) -> void:
	item_id = id
	item_count = count
	add_to_group("drop_box")

	_visual = Sprite3D.new()
	_visual.texture = load("res://assets/items/chest.svg")
	_visual.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_visual.shaded = false
	_visual.pixel_size = 0.0045          # 512px → 约 2.3m
	_visual.modulate = Color(0.95, 0.72, 0.35)   # 木箱金棕色
	_visual.position = Vector3(0, 0.6, 0)
	add_child(_visual)

	var lbl := Label3D.new()
	lbl.text = "掉落箱 · 按 E 回收" if count <= 1 else "掉落箱 ×%d · 按 E 回收" % count
	lbl.position = Vector3(0, 1.6, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 48
	lbl.outline_size = 14
	lbl.pixel_size = 0.0035
	lbl.modulate = Color(1, 0.9, 0.55)
	add_child(lbl)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 1.2, 1.2)
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	add_child(col)


func _process(_delta: float) -> void:
	if _visual != null:
		_visual.position.y = 0.6 + 0.06 * sin(Time.get_ticks_msec() / 1000.0 * 2.2)
