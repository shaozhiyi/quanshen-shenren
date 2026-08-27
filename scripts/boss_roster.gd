extends RefCounted
## BOSS 名册：所有 BOSS 都在这里定义，加一只只需在 DEFS 里多写一条 + 准备贴图目录。
## boss.gd 按 def_id 取这里的配置来生成外观、数值、掉落与出生距离带；
## boss_field.gd 负责把名册里的每一只都放到大地图上。
##
## 字段说明：
##   name        显示名（头顶标签 + HUD 提示）
##   face_dir    六面贴图目录（front/back/side/top/bottom.png）
##   tint        贴图着色（同一套贴图换色即可做出不同 BOSS，不需要新素材）
##   scale       盒体放大倍数（0.25m 基准）
##   base_hp     普通档血量；困难/噩梦按 boss.gd 的 DIFF_HP_MULT 倍率放大
##   aura        普通档光环每 0.1 秒伤害；同样受 DIFF_AURA_MULT 缩放
##   reward      掉落物品 id；reward_counts 是三档各自的掉落数量
##   band        出生点距玩家的水平距离带 [最小, 最大]（米）
##   song        战斗配乐（空字符串 = 无声，走同一时间轴）

const DEFS := {
	"dogmilk": {
		"name": "野生狗奶",
		"face_dir": "res://assets/props/dogmilk/",
		"tint": Color(1, 1, 1),
		"scale": 24.0,
		"base_hp": 1000.0,
		"aura": 0.3,
		"reward": "dogmilk",
		"reward_counts": [2, 3, 4],
		"band": [35.0, 65.0],
		"song": "res://assets/audio/song.mp3",
	},
	# 下一只 BOSS 照抄一条写在这里即可（换 face_dir 用新贴图，
	# 或先用 tint 着色区分），boss.gd / 玩家 / HUD 都不用改。
}


static func ids() -> Array:
	return DEFS.keys()


static func def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func display_name(id: String) -> String:
	var d := def(id)
	return String(d.get("name", id))
