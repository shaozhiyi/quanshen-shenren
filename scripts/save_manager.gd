extends RefCounted
class_name SaveManager
## 存档管理：把游戏状态写成 JSON 放进工程根目录的 save/ 文件夹，读档时还原。
## 导出成 exe 后 save/ 会自动创建在 exe 同级目录（res:// 在导出包里是只读的）。
##
## 存档数据结构（version=1）：
##   seed/amp/freq  地形：同种子 = 同一片世界
##   player         血量、位置、朝向、当前武器
##   equipment/bag  装备栏与背包内容（物品 id 数组）
##   bosses         每只 BOSS 的难度与击败次数
##   kills          累计击杀数

const VERSION := 1
const BAG_SIZE := 27

static var current_slot := ""      # 本次游戏写入的存档路径（新游戏/读档时确定）
static var pending_seed := -1      # 菜单传给下一局的强制种子（-1 = 让地形自己随机）
static var pending_load := {}      # 菜单传给下一局的存档内容（空 = 不套用）


## 存档目录：编辑器里是 <工程>/save，导出后是 <exe 所在目录>/save
static func save_dir() -> String:
	var dir := ""
	if OS.has_feature("editor"):
		dir = ProjectSettings.globalize_path("res://save")
	else:
		dir = OS.get_executable_path().get_base_dir().path_join("save")
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func slot_path(label: String) -> String:
	var safe := label.replace(" ", "_")
	return save_dir().path_join("野生狗奶_%s.json" % safe)


static func new_slot() -> String:
	var t := Time.get_datetime_dict_from_system()
	return slot_path("%04d%02d%02d_%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second])


## 列出全部存档（按修改时间倒序）：[{path, time_text, seed, hp, kills, name}]
static func list_saves() -> Array:
	var out: Array = []
	var dir := DirAccess.open(save_dir())
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".json"):
			var full := save_dir().path_join(f)
			var data := read_from(full)
			if not data.is_empty():
				var st := FileAccess.get_modified_time(full)
				var t := Time.get_datetime_dict_from_unix_time(int(st))
				out.append({
					"path": full,
					"file": f,
					"time_text": "%04d-%02d-%02d %02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute],
					"seed": int(data.get("seed", 0)),
					"hp": float(data.get("player", {}).get("hp", 0.0)),
					"kills": int(data.get("kills", 0)),
					"mtime": float(st),
				})
		f = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return float(a.mtime) > float(b.mtime))
	return out


static func write_to(path: String, data: Dictionary) -> bool:
	data["version"] = VERSION
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("存档写入失败：%s" % path)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true


static func read_from(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var txt := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("存档格式不是 JSON 对象：%s" % path)
		return {}
	return parsed


## 供 UI 显示的存档摘要
static func describe(entry: Dictionary) -> String:
	return "%s ｜ 种子 %d ｜ 血量 %d ｜ 击杀 %d" % [
		String(entry.get("time_text", "?")), int(entry.get("seed", 0)),
		int(roundf(float(entry.get("hp", 0.0)))), int(entry.get("kills", 0))]


## 把存档里的地形参数交给下一局（terrain.gd 会读 pending_seed）
static func stage_new_game(seed_value: int) -> void:
	pending_load = {}
	pending_seed = seed_value
	current_slot = new_slot()


static func stage_load(path: String) -> void:
	var data := read_from(path)
	if data.is_empty():
		return
	pending_load = data
	pending_seed = int(data.get("seed", -1))
	current_slot = path


## 从活体节点收集状态（由 player.gd 调用，避免这里到处找节点）
static func build_data(seed: int, amp: float, freq: float, player: Dictionary,
		inventory: Dictionary, bosses: Dictionary, kills: int) -> Dictionary:
	return {
		"seed": seed, "amp": amp, "freq": freq,
		"player": player,
		"equipment": inventory.get("equipment", {}),
		"bag": inventory.get("bag", []),
		"bosses": bosses, "kills": kills,
		"saved_at": Time.get_datetime_string_from_system(false, true),
	}
