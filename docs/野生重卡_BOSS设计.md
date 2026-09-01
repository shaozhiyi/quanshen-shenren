# 新 BOSS 设计 · 野生重卡

> 状态：**已进游戏可打**（暂无技能，先把血量与模型管线跑通）
> 名册 id：`truck` ｜ 定义位置：`scripts/boss_roster.gd` ｜ 实体逻辑：`scripts/boss.gd`
> 造型对标：橙色 **8×4 自卸重卡**（大运重卡那一类）——高顶驾驶室 + 黑色中网 + 带竖向加强筋的
> 自卸斗 + 侧面竖排白字「大运重卡」+ 前双转向桥、后双驱动桥共四轴八轮。
> 参考图：`assets/models/ref/truck_ref_dump.png`（原图 434×241）·
> `truck_ref_dump_big.png`（3× 放大到 1302×723，喂 Hyper3D 用）·
> 另留一张早期的红色栏板货车参考 `truck_ref.png` / `truck_ref_clean.png`（已抠蓝底）

---

## 一、这只 BOSS 的定位

一辆橙色自卸重卡停在草原上，车头永远对着你。它现在**没有任何技能**——不飞天、不蓄力、
不砸地、不射星点，只做两件事：以 3.6 米/秒缓慢朝你驶来（你步行 5 米/秒，走得掉；它会在
离你约 6.3 米处停下，不会把车头插进你身体），以及在你贴到车身 7.3 米内时持续蹭你"尾气"。
所以它的实战角色是**厚血靶子**：给你一整段安心输出、用来试武器强化等级和弓箭蓄力收益的沙包，
同时把"外部 3D 模型 → BOSS"这条管线接通。

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

## 二、外观现在长什么样

**当前生效的是程序化低模**：`scripts/boss_model.gd` 里的 `build_truck()`，约 90 个
BoxMesh/CylinderMesh 图元拼出整车——高顶驾驶室（前挡玻璃、遮阳板、门窗、三角窗、后视镜、
登车踏步）、黑色中网 + 三条镀铬横杠 + 圆车标 + 双联大灯 + 保险杠、底盘纵梁与横梁、
侧面油箱与储气筒、排气竖管、带 9 根竖向加强筋的自卸斗（前挡板加高、尾板铰链、上下横梁）、
后桥挡泥板与侧面防护栏，以及**四轴八轮**（轮子挂在名为 `Wheels` 的节点下，车身一动就滚）。
货箱两侧的竖排「大运重卡」白字是一张运行时生成的贴图：`assets/models/truck_lettering.png`
（384×1024，黑体白字带深色描边，贴在 0.55×1.46 米的面片上，居中在侧壁高度）。

主色取自参考图的橙红：`Color(0.760, 0.085, 0.020)`（线性空间，约等于 sRGB #E8491E），
竖筋和暗面用更深的 `Color(0.560, 0.055, 0.015)`。

名册里的碰撞盒按实车给：`box = [3.0, 3.8, 10.6]`（宽 × 高 × 长，米），出生距离带
60~100 米（车太长，别贴着脸刷出来）。

### 模型槽位是空的，等你把真模型放进来

`assets/models/truck.glb` 目前**不存在**——这是故意的：槽位空着时 `boss.gd` 自动用上面那套
程序化低模；一旦你把 Hyper3D（或任何来源）的自卸车 GLB 存成这个文件名，它立刻接管，代码不用动。

上一版试过的 CC-BY 军用卡车（`"Military Truck - 2D/3D Collab"` by Alex Safayan，CC-BY 3.0，
via Poly Pizza，改红）已经**移出工程**，暂存在我的工作目录 `truck_dl/held_out/military_truck_red.glb`。
它只有两轴、造型偏军用，和你给的参考不是一类车，所以不再作为默认外观；真要启用，把文件放回
`assets/models/` 并让名册 `model` 指过去即可（届时需要恢复它的 CC-BY 署名）。

---

## 三、Hyper3D 出图后怎么换（三步）

1. 上传 `assets/models/ref/truck_ref_dump_big.png`（就是这张橙色 8×4 自卸车）。
   建议：输出 **GLB**、关掉地面底座、尽量"单个整体模型 + 一套贴图"。
2. 把生成的文件**覆盖**到 `E:\游戏大乱斗\assets\models\truck.glb`（同名即可，名册不用改）。
3. 双击 `启动游戏.exe`，Godot 自动重新导入。若车陷地/浮空/朝向不对，只调名册里这四个数：

   | 名册字段 | 作用 | 现在的值 |
   |---|---|---|
   | `model_scale` | 整体缩放，让车身约 10~11 米长 | 1.0 |
   | `model_y` | 上下偏移，负值往下压贴地 | 0.0 |
   | `model_rot_y` | 绕 Y 转角度，让**车头朝 +Z**（BOSS 靠这个方向对玩家） | 0.0 |
   | `box` | 碰撞盒 `[宽, 高, 长]`，与放大后的车身一致 | [3.0, 3.8, 10.6] |

   注意：Hyper3D 常把模型中心放在包围盒中心（而非地面），所以一般要把 `model_y` 调成
   负的一半车高；若它输出"车头朝 +X"，把 `model_rot_y` 设 90 或 -90 试。
   真模型到位后，程序化低模与白字贴图会自动不再使用（想保留白字，把它当纹理贴进自己的模型即可）。

> **换完模型怎么生效**：双击 `启动游戏.exe`（跑源码）会提示重新导入，进游戏立刻是新车；
> 但 `build/游戏大乱斗.exe` 分享包已经把资源打进 exe 内部的 pck，换完模型需要重新导出一次
> （`Godot --headless --path . --export-release "Windows Desktop" build/out_game.exe`）才会带上。

### 喂给 Hyper3D 的提示词（可直接粘）

英文（Hyper3D Rodin 对英文响应更稳）：

```
Orange Chinese 8x4 heavy dump truck (tipper), high-roof cab-over cab with large dark
windshield, black front grille with chrome horizontal bars and round badge, sun visor
above the windshield, stacked headlights in the bumper, long mirrors on both doors,
tall dump body with vertical ribbed side panels and white vertical Chinese characters
on the front part of the side, four axles (two closely spaced steerable front axles plus
a rear tandem) with eight wheels, chrome fuel tank and air tanks on the chassis, black
frame rails, mud flaps, glossy orange-red paint, game-ready single object, centered on
origin, ground contact at bottom, Y-up, front facing +Z, real-world scale about 10.5
meters long, 3.0 meters wide, 3.8 meters tall, moderate polygon count, one texture set
```

中文：

```
橙色中国 8×4 自卸重卡（大运重卡风格），高顶平头驾驶室配大块深色前挡玻璃，黑色中网带镀铬
横条与圆形车标，挡风上方遮阳板，保险杠内叠式大灯，两侧长后视镜；高大的自卸货箱侧面带竖向
加强筋，前部有竖排白色汉字「大运重卡」；四轴八轮（前双转向桥 + 后双驱动桥），底盘侧面镀铬
油箱与储气筒，黑色车架，挡泥皮；橙红亮漆；单个整体模型、原点在车底中心、Y 轴向上、车头朝
+Z、真实尺度约长 10.5 米 / 宽 3.0 米 / 高 3.8 米、中等面数、一套贴图
```

### 交付给引擎的硬要求（Hyper3D 导出面板里能勾就勾）

- 格式 **GLB**（Godot 原生导入；FBX/OBJ 也能进但多一步）
- **Y-up**、单位米、原点在**车底中心**（不是包围盒中心）
- 车头朝 **+Z**（BOSS 用 +Z 对着玩家；朝错了用 `model_rot_y` 救）
- 面数 **≤ 6 万三角形**（这台机器是 MX250；程序化低模约几千面，很宽裕）
- 尽量**合并成 1~2 个网格 + 1 套 2K 贴图**；不要带地面底座/阴影板/多余空物体
- 不要骨骼和动画（车轮滚动是引擎按 `Wheels` 节点自己加的；外部模型想要滚轮，把轮子做成
  名为 `Wheels` 的父节点下的若干子节点即可，程序化低模就是这么接的）

### 已知坑（本机 Godot 4.7.2 实测）

- 有些站点导出的 GLB 把 BIN 块类型写成 `BIN `（末尾空格 0x204E4942），Godot 严格要求
  `BIN\0`（0x004E4942），否则报 `chunk_type != 0x004E4942` 导入失败。修法：把 BIN 块头部的
  4 字节类型改掉（偏移 = 20 + JSON 块长度 + 4）。
- 换过同名 glb 后如果引擎不肯重导，把 `assets/models/truck.glb.import` 与
  `.godot/imported/truck.glb-*.md5`（连同 `.scn`）移走再启动一次即可强制重导。
- 贴地面片（白字）必须 `cast_shadow = OFF`，否则会在白地上投出一块方影。

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
3. **卸货**：把斗里的货箱向后抛 3 只，落点提前显示红圈（复用 `_marker` 逻辑），落点内 -20
4. **顶斗扬尘**：货箱前顶抬起 1.5 秒，向后方扇形喷扬尘，减速玩家 40% 持续 2 秒
5. **鸣笛震慑**：半径 12 米内玩家移速 -40% 持续 2 秒（纯数值，不加任何屏幕提示）

以上都遵循同一条约定：**伤害一律走 `player.take_damage()`**，这样防具减伤、无敌免疫、
30% 复活这些规则自动生效；命中判定用"本帧起点→终点线段到玩家中心"的最近距离
（星点那套 `_seg_point_dist`），否则高速物体会在低帧率下穿人而过。
