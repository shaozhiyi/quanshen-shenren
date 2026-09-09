extends Node3D
## 多 BOSS 生成器：把 scripts/boss_roster.gd 名册里的每一只 BOSS 实例化到主场景，
## 并按本局地形各挑一处互不重叠的落点。加新 BOSS 只需改名册，不需要动这里。
## 由 player.gd 在选定出生点后调用 spawn_all()（那时地形高度场已就绪）。
const BOSS_SCRIPT := preload("res://scripts/boss.gd")
const ROSTER := preload("res://scripts/boss_roster.gd")
var _spawned := false
func spawn_all(spawn_point: Vector3) -> int:
	## 依序放置名册里的所有 BOSS，返回成功放置的数量；重复调用只生效一次
	if _spawned:
		return 0
	_spawned = true
	var ground := get_node_or_null("../Ground")
	var placed: Array = []
	var count := 0
	for id in ROSTER.ids():
		var b := BOSS_SCRIPT.new()
		b.name = "Boss_%s" % String(id)
		b.set("def_id", String(id))
		add_child(b)
		if bool(b.get("random_spawn")) and b.call("place_near", spawn_point, ground, placed):
			count += 1
		placed.append(b.get("position"))
	print("[boss_field] 名册 %d 只，成功随机落点 %d 只" % [ROSTER.ids().size(), count])
	return count
