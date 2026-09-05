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
##   song        战斗配乐（空字符串 = 无声）。技能档按乐句时间轴放一遍副歌；
##               载具档（skills=false）是进战即从头循环播放的背景乐，撤退/击杀立刻停
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
##                "highway" = 国道（两条无限延伸的国道，见 highway_arena.gd）
##   skills       false = 不走"星点 + 升空 + 砸地"那套循环，改成载具档（驶近 + 尾气 + 锁定冲撞）
##   chase        载具档的驶近速度（米/秒），默认 0 = 原地不动
##   no_turn      true = 载具档：车头不再"永远正对玩家"，只对着行驶方向；锁定冲撞期间整个钉死
##   charge_lock  >0 才有的技能「锁定冲撞」：原地冻结这几秒（轮子停 + 地面铺红色撞击路径预警带），
##                到点沿锁死的方向直线猛冲，全程不转向。叠在 chase 之上，与 skills 字段互不影响
##   charge_units 撞击行程 = 玩家一次冲刺的位移 × 这个数（3.6 米 × 8 ≈ 28.8 米）
##   charge_speed_mult 冲撞速度 = 玩家奔跑速度（步行 ×2）× 这个数（10 × 3 = 30 米/秒）
##   charge_gap   一次冲完后的冷却秒数，防止它无限连撞
##   charge_damage 撞上的伤害（一次冲撞只结算一次，仍吃防具减伤/无敌免疫）
##   charge_knockback 撞上后把玩家沿撞击方向顶开几个"冲刺距离"（0 或缺省 = 不击退）
##   charge_slow_sec 撞上了给玩家几秒减速（玩家侧 SLOW_MULT 固定 ×0.5；0 = 不减速）。
##                击退与减速都**不当场生效**，而是等这一轮冲完、车停住那一刻一起结算
##   charge_ring_damage 冲完收尾那圈光波扫到人扣的伤害（0 或缺省 = 纯特效）。
##                它与撞击伤害各自结算一次：被顶飞后还在圈里，就会两回都挨上
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
	# ---- 第二只：大运（厚血载具，只会缓慢驶近 + 尾气 + 一招「锁定冲撞」直线撞过来）----
	# 外观：把 Hyper3D 生成的车存成 res://assets/models/truck.glb 即自动生效；
	#       该文件不存在时先用 placeholder "truck" 的程序化低模顶上。
	"truck": {
		"name": "大运",
		"model": "res://assets/models/truck.glb",
		"placeholder": "truck",
		"model_scale": 1.0,             # 真模型到位后再按实际尺寸调
		"model_y": 0.0,
		"model_rot_y": 0.0,             # 车头须朝 +Z（载具档用 +Z 当行驶方向）
		"face_dir": "res://assets/props/dogmilk/",
		"tint": Color(1, 1, 1),
		"scale": 1.0,
		"box": [3.0, 3.8, 10.6],        # 宽 3.0 · 高 3.8 · 长 10.6（米，车头朝 +Z）
		"hp_by_diff": [2000.0, 2500.0, 3000.0],   # 普通 / 困难 / 噩梦
		"aura": 0.3,                    # 贴身尾气：每 0.1 秒 0.3 血（困难 ×1.5、噩梦 ×2）
		"skills": false,                # 载具档：不走星点/升空/砸地那套循环
		"no_turn": true,                # 车头对着行驶方向，不再"永远梗脸对玩家"
		"chase": 3.6,                   # 缓慢驶近（玩家步行 5.0，跑得掉）
		# ---- 它的技能「锁定冲撞」：原地冻结 2 秒（地面铺红色撞击路径）→ 直线撞 8 个冲刺距离 ----
		"charge_lock": 2.0,
		"charge_units": 8.0,            # 3.6 米 × 8 ≈ 28.8 米
		"charge_speed_mult": 3.0,       # 玩家奔跑 10 米/秒 × 3 = 30 米/秒（整段仍约 0.96 秒）
		"charge_gap": 7.0,              # 撞完要等 7 秒才再出手
		"charge_damage": 20.0,          # 撞上一下的伤害（一次冲撞只结算一次）
		"charge_knockback": 2.0,        # 撞上就被顺着车行方向顶开 2 个冲刺距离 ≈ 7.2 米
		"charge_slow_sec": 3.0,         # 撞到了还减速 50% 持续 3 秒（击退与减速都等冲完才结算）
		"charge_ring_damage": 10.0,     # 冲完那圈橙色光波扫到人再扣 10
		"bob_amp": 0.02,                # 几乎贴地，只留一点悬挂起伏
		"visual_y": 0.0,
		"arena": "highway",             # 它的专属战场：两条无限延伸的国道
		"reward": "dogmilk",            # 拉的一车货
		"reward_counts": [2, 3, 4],
		"band": [60.0, 100.0],          # 车身 10 米多长，出生点离玩家更远些
		"song": "res://assets/audio/song_truck.mp3",   # 载具档专属战斗曲：进战整首循环，不按乐句打点
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
