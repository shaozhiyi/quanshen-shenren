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
##
## ---- 可选字段（不写就用默认值，老 BOSS 完全不受影响）----
##   model        3D 模型路径（.glb/.gltf/.tscn）。有它就直接用模型，不再拼贴图盒；
##                模型出好后覆盖同名文件即可，代码不用动。
##   model_scale  模型缩放（默认 1.0）；model_y 上下偏移；model_rot_y 绕 Y 转的度数
##                —— 这三个专门用来把外部模型对齐到"原点落地、车头朝 +Z"
##   placeholder  模型文件缺失时的临时外观（"truck" = 程序化低模），联调用，随时可换
##   box          碰撞盒 [X宽, Y高, Z长]（米，与 Vector3 同序；车头朝 +Z 所以"长"在 Z）。
##                不写则沿用 0.09/0.25/0.06 × scale
##   hp_by_diff   三档血量 [普通, 困难, 噩梦]。写了就不再乘 DIFF_HP_MULT
##   arena        进战时切到哪套战斗空间："white" = 超平坦纯白（默认）
##                "highway" = 大运国道（两条无限延伸的国道，见 highway_arena.gd）
##   skills       false = 暂无技能（只驶近 + 贴身光环），默认 true
##   chase        无技能档的驶近速度（米/秒），默认 0 = 原地不动
##   bob_amp      待机浮动幅度；visual_y 外观离地高度

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
	# ---- 第二只：野生重卡（暂无技能，先把血量/模型管线跑通）----
	# 外观：把 Hyper3D 生成的车存成 res://assets/models/truck.glb 即自动生效；
	#       该文件不存在时先用 placeholder "truck" 的程序化低模顶上。
	"truck": {
		"name": "野生重卡",
		"model": "res://assets/models/truck.glb",
		"placeholder": "truck",
		"model_scale": 1.0,             # 真模型到位后再按实际尺寸调
		"model_y": 0.0,
		"model_rot_y": 0.0,             # 车头须朝 +Z（BOSS 用 +Z 对玩家）
		"face_dir": "res://assets/props/dogmilk/",
		"tint": Color(1, 1, 1),
		"scale": 1.0,
		"box": [3.0, 3.8, 10.6],        # 宽 3.0 · 高 3.8 · 长 10.6（米，车头朝 +Z）
		"hp_by_diff": [2000.0, 2500.0, 3000.0],   # 普通 / 困难 / 噩梦
		"aura": 0.3,                    # 贴身尾气：每 0.1 秒 0.3 血（困难 ×1.5、噩梦 ×2）
		"skills": false,                # 暂无技能：不飞天、不砸地、不射星点
		"chase": 3.6,                   # 缓慢驶近（玩家步行 5.0，跑得掉）
		"bob_amp": 0.02,                # 几乎贴地，只留一点悬挂起伏
		"visual_y": 0.0,
		"arena": "highway",             # 它的专属战场：两条无限延伸的国道
		"reward": "dogmilk",            # 拉的一车货
		"reward_counts": [2, 3, 4],
		"band": [60.0, 100.0],          # 车身 10 米多长，出生点离玩家更远些
		"song": "",
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
