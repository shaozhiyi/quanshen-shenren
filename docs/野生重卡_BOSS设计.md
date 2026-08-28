# 新 BOSS 设计 · 野生重卡

> 状态：**已进游戏可打**（暂无技能，先把血量与模型管线跑通）
> 名册 id：`truck` ｜ 定义位置：`scripts/boss_roster.gd` ｜ 实体逻辑：`scripts/boss.gd`
> 参考图：`assets/models/ref/truck_ref.png`（原图）· `truck_ref_clean.png`（已抠蓝底并放大到 900px，喂 Hyper3D 用）

---

## 一、这只 BOSS 的定位

一只红色三轴栏板重卡，停在草原上，车头永远对着你。它现在**没有任何技能**——不飞天、
不蓄力、不砸地、不射星点，只以 3.6 米/秒的速度缓慢朝你驶来（你步行 5 米/秒，走得掉），
贴到车身 6 米内才会被尾气蹭到血。所以它的实战角色是**厚血靶子**：给你一整段安心输出、
用来试武器强化等级和弓箭蓄力收益的沙包，同时把"外部 3D 模型 → BOSS"这条管线接通。

### 数值（三档，按 R 切档，赢过一次后解锁）

| 难度 | 血量 | 贴身光环（每 0.1 秒） | 掉落 |
|------|------|----------------------|------|
| 普通 | **2000** | 0.3（≈3 血/秒） | 野生狗奶 ×2 |
| 困难 | **2500** | 0.45（≈4.5 血/秒） | 野生狗奶 ×3 |
| 噩梦 | **3000** | 0.6（≈6 血/秒） | 野生狗奶 ×4 |

血量走名册的 `hp_by_diff` 定值，**不再**乘狗奶那套 1.0/1.6/2.4 倍率；光环伤害仍吃
`DIFF_AURA_MULT`。掉落照旧额外走一遍强化石概率（必掉 1 块 + 4%/3.95%… 递减追加）。

参考对照：剑一击 50（+10%/级），满蓄弓 70。普通档 2000 血 ≈ 40 剑 / 29 满蓄箭。

---

## 二、模型现在用的是什么

`assets/models/truck.glb` —— 一张真实建模的红色三轴栏板卡车（3752 三角形、10 个纯色
PBR 材质、无贴图依赖，Godot 直接导入）。

```
"Military Truck - 2D/3D Collab" by Alex Safayan（CC-BY 3.0，via Poly Pizza）
本仓库内改为红色（只动材质颜色，几何未改），署名详见 assets/models/CREDITS.txt
```

原始土黄色版本留在 `assets/models/truck_original_tan.glb`，想换口味把名册 `model` 指过去即可。

进场时按名册参数摆位：`model_scale = 1.4`（5.85 米 → 8.2 米长），`model_y = -0.02`（贴地），
`model_rot_y = 0`（车头已朝 +Z），碰撞盒 `box = [3.7, 3.85, 8.2]`（宽 × 高 × 长）。

**兜底**：如果 `truck.glb` 被删掉或导入失败，`boss.gd` 会自动改用 `scripts/boss_model.gd`
里那套程序化低模（同样是红车头 + 栏板货斗 + 三轴六轮，且轮子会跟着车身滚动），
所以任何时候这只 BOSS 都不会变成空气。

---

## 三、Hyper3D 出图后怎么换（三步）

1. 用参考图生成：上传 `assets/models/ref/truck_ref_clean.png`（已抠掉蓝底）。
   建议参数：输出 **GLB**，关闭/降低地面底座，尽量要"单个整体模型 + 一套贴图"。
2. 把生成的文件**覆盖**到 `E:\游戏大乱斗\assets\models\truck.glb`（同名即可，名册不用改）。
3. 双击 `启动游戏.exe`，Godot 会自动重新导入。若车陷进地里/浮空/朝向不对，只调名册里
   这三个数（不用碰代码）：

   | 名册字段 | 作用 | 现在的值 |
   |---|---|---|
   | `model_scale` | 整体缩放，让车身约 8~9 米长 | 1.4 |
   | `model_y` | 上下偏移，负值往下压贴地 | -0.02 |
   | `model_rot_y` | 绕 Y 转角度，让**车头朝 +Z**（BOSS 靠这个方向对玩家） | 0.0 |
   | `box` | 碰撞盒 `[宽, 高, 长]`，跟改完尺寸后一致 | [3.7, 3.85, 8.2] |

   注意：Hyper3D 常把模型中心放在几何中心（而非地面），所以一般要把 `model_y` 调成
   负的一半车高；如果它输出的是"车头朝 +X"，就把 `model_rot_y` 设 90 或 -90 试。

> **换完模型怎么生效**：双击 `启动游戏.exe`（跑源码）会提示重新导入，进游戏立刻是新车；
> 但 `build/游戏大乱斗.exe` 分享包已经把模型打进 exe 内部的 pck，换完模型需要重新导出一次
> （`Godot --headless --path . --export-release "Windows Desktop" build/out_game.exe`）才会带上。

### 喂给 Hyper3D 的提示词（可直接粘）

英文（Hyper3D Rodin 对英文响应更稳）：

```
Red Chinese heavy cargo truck, cab-over-engine design, long slatted stake-body cargo bed,
three axles with six visible wheels, boxy angular cab with large dark windshield,
chrome front grille and bumper, round headlights, side mirrors on both doors,
flat matte red paint with slight wear, game-ready single object, centered on origin,
ground contact at bottom, Y-up, front facing +Z, real-world scale about 9 meters long,
2.6 meters wide, 3.3 meters tall, moderate polygon count, one texture set
```

中文（若走中文界面）：

```
红色中国重卡，平头驾驶室，长栏板式货斗，三轴六轮，方正驾驶室配大块深色前挡玻璃，
镀铬中网与保险杠，两侧后视镜，哑光红漆略带磨损；单个整体模型、原点对齐车底中心、
Y 轴向上、车头朝 +Z、真实尺度约长 9 米 / 宽 2.6 米 / 高 3.3 米、中等面数、一套贴图
```

### 交付给引擎的硬要求（Hyper3D 导出面板里能勾就勾）

- 格式 **GLB**（Godot 原生导入；FBX/OBJ 也能进但要多一步）
- **Y-up**、单位米、原点在**车底中心**（不是包围盒中心）
- 车头朝 **+Z**（BOSS 用 +Z 对着玩家；朝错了用 `model_rot_y` 救）
- 面数 **≤ 5 万三角形**（这台机器是 MX250；现在这只 3752 面，很宽裕）
- 尽量**合并成 1~2 个网格 + 1 套 2K 贴图**；不要带地面底盘/阴影板/多余空物体
- 不要骨骼和动画（滚动动画是引擎按碰撞盒自己加的）

### 已知坑（本机 Godot 4.7.2 实测）

- 有些站点导出的 GLB 把 BIN 块类型写成 `BIN `（末尾空格），Godot 严格要求 `BIN\0`，
  会报 `chunk_type != 0x004E4942` 导入失败。修法：把 BIN 块头部的 4 字节类型改成
  `42 49 4E 00`（当前 `truck.glb` 就是这么修好的）。
- 换过同名 glb 后如果引擎不肯重导，把 `assets/models/truck.glb.import` 与
  `.godot/imported/truck.glb-*.md5` 移走再启动一次即可强制重导。

---

## 四、以后给它加技能（留好的接口）

`boss.gd` 的相位机是现成的：狗奶用 `_has_skills = true` 走
`0 待机 → 1 前摇 → 2 飞天攻击 → 4 空中追踪 → 5 红圈 → 6 砸落`。
重卡只要把名册 `"skills"` 改回 `true` 就会走同一套；想给它做**卡车专属**连招，
建议照 `_update_chase()` 的写法新增一个 `_update_charge()`，再在 `_process` 的
`if _has_skills:` 分支里按名册新字段（例如 `"skill_set": "truck"`）分流。候选技能：

1. **冲锋碾压**：锁定玩家 XZ → 车头转向 → 3 秒加速到 22 米/秒直线冲撞，撞上 -30 血 +
   击退；冲出场地边缘撞墙 → 扬尘 + 短暂硬直（现成的 `SLAM_FX.spawn_slam` 改 tint 就能当扬尘）
2. **甩尾横扫**：绕自身快速旋转 270°，扫过扇形区域，命中 -15
3. **卸货**：向天抛 3 只货箱，落点提前显示红圈（复用 `_marker` 逻辑），落点内 -20
4. **鸣笛震慑**：半径 12 米内玩家移速 -40% 持续 2 秒（纯数值，不加任何屏幕提示）

以上都遵循同一条约定：**伤害一律走 `player.take_damage()`**，这样防具减伤、无敌免疫、
30% 复活这些规则自动生效；命中判定用"本帧起点→终点线段到玩家中心"的最近距离
（星点那套 `_seg_point_dist`），否则高速物体会在低帧率下穿人而过。
