# -*- coding: utf-8 -*-
"""
手搓「大狗叫」梗图狗 —— 奶凶龇牙的奶油黄拉布拉多（低模卡通，武器用）。
无头运行：blender -b --factory-startup --python build_dog.py -- <out.glb> <preview_dir> [scale] [views]
产出：单个 GLB（一个网格、9 个材质槽）+ 多角度预览 PNG。
坐标系：狗朝 -Y（Blender 前视图正对镜头），+Z 上，地面 z=0；导出后 Godot 里 -Z 为前。
头部分三层坐标系：HEAD（整体抬头）→ UP（上颌）/ LOW（下颌，绕铰链张开）；
局部摆好后把矩阵烘焙进网格，最后 join 成一个对象。
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix

# --factory-startup 会带进默认启动场景的 Cube/Camera/Light，先清干净
# （否则那个 2m 默认立方体会被 join 进狗里，包围盒和预览相机全废）
for _ob in list(bpy.data.objects):
    bpy.data.objects.remove(_ob, do_unlink=True)
for _me in list(bpy.data.meshes):
    if _me.users == 0:
        bpy.data.meshes.remove(_me)

# ---------------------------------------------------------------- 参数区
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_GLB = args[0] if len(args) > 0 else "dog.glb"
OUT_DIR = args[1] if len(args) > 1 else "."
SCALE = float(args[2]) if len(args) > 2 else 1.0
VIEWS = args[3].split(",") if len(args) > 3 else ["face", "front", "left", "three"]

# ---------------------------------------------------------------- 材质
FUR = (0.580, 0.385, 0.155, 1.0)      # 奶油黄短毛（打光偏亮，压深两档才接近原图）
FUR_DK = (0.440, 0.270, 0.100, 1.0)   # 耳朵/眉骨/背线稍深
MUZZLE = (0.700, 0.530, 0.290, 1.0)   # 口鼻与下颌偏浅
NOSE = (0.045, 0.038, 0.036, 1.0)     # 黑鼻头
MOUTH = (0.170, 0.032, 0.044, 1.0)    # 口腔深红
GUM = (0.808, 0.325, 0.376, 1.0)      # 牙龈/舌头粉
TOOTH = (0.930, 0.918, 0.870, 1.0)    # 白牙
EYE = (0.055, 0.036, 0.026, 1.0)      # 深棕眼珠
WHITE = (0.920, 0.920, 0.920, 1.0)


def make_mat(name, rgba, rough=0.65, spec=0.3):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        bsdf.inputs["Roughness"].default_value = rough
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = spec
    return m


MATS = {
    "fur": make_mat("dog_fur", FUR),
    "fur_dk": make_mat("dog_fur_dark", FUR_DK),
    "muzzle": make_mat("dog_muzzle", MUZZLE),
    "nose": make_mat("dog_nose", NOSE, 0.32, 0.6),
    "nostril": make_mat("dog_nostril", (0.016, 0.013, 0.013, 1.0), 0.40, 0.4),
    "mouth": make_mat("dog_mouth", MOUTH, 0.60),
    "gum": make_mat("dog_gum", GUM, 0.45),
    "tooth": make_mat("dog_tooth", TOOTH, 0.28, 0.5),
    "eye": make_mat("dog_eye", EYE, 0.15, 0.7),
    "white": make_mat("dog_white", WHITE, 0.30, 0.5),
}

# ---------------------------------------------------------------- 几何小工具
_coll = bpy.context.collection
_parts = []


def _finish(bm, mat_key, smooth, name):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    _coll.objects.link(ob)
    ob.data.materials.append(MATS[mat_key])
    _parts.append(ob)
    return ob


def _xf(bm, loc, rot, radii):
    """缩放(半径) -> 欧拉 XYZ -> 平移，直接烘进 bmesh。rot 单位弧度。"""
    sx, sy, sz = radii
    M = (
        Matrix.Translation(Vector(loc))
        @ Matrix.Rotation(rot[2], 4, "Z")
        @ Matrix.Rotation(rot[1], 4, "Y")
        @ Matrix.Rotation(rot[0], 4, "X")
        @ Matrix.Diagonal((sx, sy, sz, 1.0))
    )
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts[:])
    return bm


def blob(loc, radii=(1, 1, 1), rot=(0, 0, 0), mat="fur", seg=14, ring=9, name="blob",
         frame=None, smooth=True):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=ring, radius=1.0)
    if frame is not None:
        bmesh.ops.transform(bm, matrix=frame, verts=bm.verts[:])
    return _finish(_xf(bm, loc, rot, radii), mat, smooth, name)


def cube(loc, size=(1, 1, 1), rot=(0, 0, 0), mat="fur", name="cube", smooth=False,
         bevel=0.0, frame=None):
    """圆角方块，卡通体积感的常驻件。size = 三轴全长。"""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts[:])
    if bevel > 0:
        bv = min(bevel, min(size) * 0.45)
        bmesh.ops.bevel(bm, geom=bm.verts[:] + bm.edges[:], offset=bv, segments=2,
                        affect="EDGES", clamp_overlap=True, material=0)
    if frame is not None:
        bmesh.ops.transform(bm, matrix=frame, verts=bm.verts[:])
    return _finish(_xf(bm, loc, rot, (1, 1, 1)), mat, smooth, name)


def spike(loc, r=0.02, depth=0.06, rot=(0, 0, 0), mat="tooth", seg=8, name="tooth",
          frame=None, smooth=True):
    """锥体（牙/爪），默认尖端朝 +Z。"""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=True, segments=seg,
                          radius1=r, radius2=0.0, depth=depth)
    if frame is not None:
        bmesh.ops.transform(bm, matrix=frame, verts=bm.verts[:])
    return _finish(_xf(bm, loc, rot, (1, 1, 1)), mat, smooth, name)


def rod(loc, r=0.04, depth=0.24, rot=(0, 0, 0), mat="fur", seg=12, name="rod",
        frame=None, smooth=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=r, radius2=r, depth=depth)
    if frame is not None:
        bmesh.ops.transform(bm, matrix=frame, verts=bm.verts[:])
    return _finish(_xf(bm, loc, rot, (1, 1, 1)), mat, smooth, name)


R = math.radians
PI = math.pi

# ================================================================ 身体
blob((0, 0.100, 0.300), (0.145, 0.225, 0.160), mat="fur", seg=20, ring=14, name="torso")
blob((0, -0.070, 0.290), (0.135, 0.115, 0.145), mat="fur", seg=16, ring=11, name="chest")
blob((0, 0.300, 0.300), (0.135, 0.115, 0.140), mat="fur", seg=16, ring=11, name="rump")
# 背线（深色一条，避免纯色大馒头）
blob((0, 0.120, 0.398), (0.075, 0.175, 0.052), mat="fur_dk", seg=14, ring=9, name="back_line")
# 脖子：往前上方顶住头
rod((0, -0.105, 0.395), r=0.078, depth=0.220, rot=(R(27), 0, 0), mat="fur", seg=14,
   name="neck")

# 前腿：外八撇开（原图两条前腿就是横着的）
for s in (-1, 1):
    t = "L" if s < 0 else "R"
    blob((s * 0.080, -0.070, 0.245), (0.062, 0.070, 0.075), mat="fur", name="shoulder_" + t)
    rod((s * 0.092, -0.078, 0.152), r=0.050, depth=0.235, rot=(R(6), R(-16 * s), 0),
        mat="fur", name="leg_f_" + t)
    blob((s * 0.135, -0.122, 0.036), (0.058, 0.086, 0.036), mat="fur", name="paw_f_" + t)
    for i in (-1, 0, 1):
        blob((s * 0.135 + i * 0.032, -0.186, 0.032), (0.015, 0.026, 0.026),
             mat="fur", seg=10, ring=7, name="toef%d_%s" % (i, t))
    for i in (-1, 1):
        spike((s * 0.135 + i * 0.034, -0.206, 0.026), r=0.009, depth=0.028,
              rot=(R(-105), 0, 0), mat="tooth", seg=6, name="claw%s_%d" % (t, i))

# 后腿：蹲坐感，大腿粗
for s in (-1, 1):
    t = "L" if s < 0 else "R"
    blob((s * 0.115, 0.300, 0.245), (0.075, 0.098, 0.112), rot=(0, R(8 * s), 0),
         mat="fur", name="thigh_" + t)
    rod((s * 0.126, 0.332, 0.142), r=0.048, depth=0.215, rot=(R(-4), R(-8 * s), 0),
        mat="fur", name="leg_b_" + t)
    blob((s * 0.132, 0.322, 0.036), (0.055, 0.088, 0.036), mat="fur", name="paw_b_" + t)

# 尾巴：紧张时往后上方翘
rod((0, 0.450, 0.352), r=0.042, depth=0.150, rot=(R(-58), 0, 0), mat="fur_dk", seg=12,
   name="tail_1")
rod((0, 0.522, 0.424), r=0.030, depth=0.120, rot=(R(-40), 0, 0), mat="fur_dk", seg=12,
   name="tail_2")
blob((0, 0.556, 0.478), (0.026, 0.040, 0.026), rot=(R(-40), 0, 0), mat="fur_dk",
     seg=12, ring=8, name="tail_tip")

# ================================================================ 头部
HEAD = Matrix.Translation(Vector((0, -0.150, 0.455))) @ Matrix.Rotation(R(-6), 4, "X")


def head(fn):
    """头局部坐标：把部件再套一次 HEAD 变换（抬头 6°）。"""
    before = len(_parts)
    fn()
    for ob in _parts[before:]:
        ob.data.transform(HEAD)


# 颅骨：宽而圆，两耳之间最宽
head(lambda: blob((0, 0.000, 0.020), (0.158, 0.146, 0.124), mat="fur", seg=20, ring=14,
                  name="skull"))
head(lambda: blob((0, -0.068, 0.048), (0.112, 0.088, 0.078), mat="fur", name="frontal"))
head(lambda: blob((0, 0.050, 0.056), (0.126, 0.090, 0.072), mat="fur_dk", name="crown"))
for s in (-1, 1):  # 腮垂：拉布拉多生气时脸上往后堆的肉（太靠前会把脸撑成仓鼠）
    head(lambda s=s: blob((s * 0.074, -0.042, -0.070), (0.036, 0.050, 0.044), mat="muzzle",
                          name="jowl%d" % s))

# ---- 上颌：短而宽的吻部，鼻头压在鼻尖（不能高过眼线）
UP = Matrix.Translation(Vector((0, -0.085, -0.020))) @ Matrix.Rotation(R(-3), 4, "X")


def up(fn):
    before = len(_parts)
    fn()
    for ob in _parts[before:]:
        ob.data.transform(HEAD @ UP)


up(lambda: blob((0, -0.070, 0.010), (0.080, 0.088, 0.052), mat="muzzle", seg=18, ring=12,
                name="snout_top"))
up(lambda: blob((0, -0.135, -0.014), (0.066, 0.052, 0.044), mat="muzzle", name="snout_front"))
up(lambda: blob((0, -0.158, 0.006), (0.040, 0.036, 0.032), rot=(R(-8), 0, 0),
                mat="nose", seg=16, ring=10, name="nose"))
up(lambda: cube((0, -0.178, 0.004), (0.052, 0.020, 0.040), rot=(R(-8), 0, 0),
                mat="nose", bevel=0.009, smooth=True, name="nose_face"))
for s in (-1, 1):  # 鼻孔：嵌在鼻头下方两侧的小黑缝（不能凸出鼻面）
    up(lambda s=s: blob((s * 0.016, -0.176, -0.012), (0.006, 0.010, 0.007),
                        rot=(0, R(20 * s), 0), mat="nostril", seg=10, ring=7,
                        name="nostril%d" % s))
# 鼻梁皱褶：两眼之间往下的两道横纹（龇牙时鼻子起皱）
for i in range(2):
    up(lambda i=i: cube((0, -0.100 - i * 0.026, 0.042 - i * 0.016),
                        (0.058 - i * 0.014, 0.016, 0.011), rot=(R(-28), 0, 0),
                        mat="fur_dk", bevel=0.004, smooth=True, name="wrinkle%d" % i))
# 上唇往上卷：翻到牙床上方，整排牙露出来
up(lambda: cube((0, -0.108, -0.046), (0.140, 0.040, 0.024), rot=(R(-20), 0, 0),
                mat="muzzle", bevel=0.009, smooth=True, name="lip_upper"))
for s in (-1, 1):
    up(lambda s=s: blob((s * 0.060, -0.098, -0.036), (0.024, 0.034, 0.022), rot=(R(-14), 0, 0),
                        mat="muzzle", seg=12, ring=8, name="lip_corner%d" % s))
# 上牙床 + 上排牙：短小的锯齿门牙 + 嘴角两颗犬齿（奶凶，不是吸血鬼）
up(lambda: cube((0, -0.114, -0.058), (0.116, 0.030, 0.016), rot=(R(-16), 0, 0),
                mat="gum", bevel=0.005, smooth=True, name="gum_upper"))
up(lambda: cube((0, -0.092, -0.062), (0.092, 0.056, 0.012), rot=(R(-8), 0, 0),
                mat="mouth", bevel=0.004, smooth=True, name="palate"))
for s in (-1, 1):
    up(lambda s=s: spike((s * 0.048, -0.120, -0.078), r=0.0115, depth=0.040,
                         rot=(R(176), R(4 * s), R(3 * s)), mat="tooth", seg=9,
                         name="fang_up%d" % s))
for i in range(6):
    x = -0.032 + i * 0.0128
    up(lambda x=x, i=i: spike((x, -0.128, -0.072), r=0.0085, depth=0.026 + (0.003 if i % 2 == 0 else 0.0),
                              rot=(R(180), 0, 0), mat="tooth", seg=7, name="cut_up%d" % i))

# ---- 口腔：扁椭球，整个缩在脸内，只从张嘴的缝里露出来
head(lambda: blob((0, -0.070, -0.104), (0.062, 0.052, 0.064), mat="mouth", seg=16, ring=11,
                  name="gape"))
head(lambda: blob((0, -0.010, -0.082), (0.050, 0.056, 0.046), mat="mouth", seg=12, ring=8,
                  name="throat"))

# ---- 下颌：绕头后下方的铰链往下打开 36°
LOW = Matrix.Translation(Vector((0, 0.010, -0.078))) @ Matrix.Rotation(R(36), 4, "X")


def low(fn):
    before = len(_parts)
    fn()
    for ob in _parts[before:]:
        ob.data.transform(HEAD @ LOW)


low(lambda: blob((0, -0.080, 0.000), (0.068, 0.095, 0.030), mat="muzzle", seg=16, ring=10,
                 name="jaw_bar"))
low(lambda: blob((0, -0.148, -0.010), (0.054, 0.060, 0.032), rot=(R(6), 0, 0),
                 mat="muzzle", seg=16, ring=10, name="chin"))
for s in (-1, 1):
    low(lambda s=s: blob((s * 0.036, -0.136, -0.022), (0.020, 0.030, 0.020), mat="muzzle",
                         seg=12, ring=8, name="lip_low%d" % s))
low(lambda: cube((0, -0.128, 0.022), (0.092, 0.038, 0.014), rot=(R(6), 0, 0),
                 mat="gum", bevel=0.004, smooth=True, name="gum_lower"))
for s in (-1, 1):
    low(lambda s=s: spike((s * 0.038, -0.128, 0.044), r=0.012, depth=0.042,
                          rot=(R(6), R(-4 * s), 0), mat="tooth", seg=9, name="fang_lo%d" % s))
for i in range(4):
    x = -0.019 + i * 0.0127
    low(lambda x=x: spike((x, -0.146, 0.034), r=0.0080, depth=0.024, rot=(R(4), 0, 0),
                          mat="tooth", seg=7, name="cut_lo%d" % i))
# 舌头：耷在下牙床上往前摊开，前端微微外翻（不能鼓成一颗球）
low(lambda: cube((0, -0.088, 0.020), (0.040, 0.110, 0.013), rot=(R(10), 0, 0),
                 mat="gum", bevel=0.006, smooth=True, name="tongue"))
low(lambda: blob((0, -0.142, 0.026), (0.021, 0.030, 0.010), rot=(R(26), 0, 0),
                 mat="gum", seg=12, ring=8, name="tongue_tip"))
low(lambda: cube((0, -0.084, 0.028), (0.004, 0.094, 0.005), rot=(R(10), 0, 0),
                 mat="mouth", bevel=0.002, smooth=True, name="tongue_groove"))

# ---- 眼睛：小而深棕，上睑压低成怒目（奶凶的关键是"凶得很勉强"）
for s in (-1, 1):
    t = "L" if s < 0 else "R"
    head(lambda s=s, t=t: blob((s * 0.068, -0.108, 0.026), (0.021, 0.018, 0.022),
                              mat="white", seg=14, ring=10, name="eye_w_" + t))
    head(lambda s=s, t=t: blob((s * 0.070, -0.122, 0.024), (0.015, 0.011, 0.017),
                              mat="eye", seg=14, ring=10, name="eye_p_" + t))
    head(lambda s=s, t=t: blob((s * 0.075, -0.131, 0.033), (0.004, 0.004, 0.005),
                              mat="white", seg=10, ring=7, name="eye_h_" + t))
    head(lambda s=s, t=t: blob((s * 0.068, -0.110, 0.042), (0.027, 0.026, 0.018),
                              rot=(R(-20), R(6 * s), 0), mat="fur", seg=12, ring=8,
                              name="lid_" + t))
    head(lambda s=s, t=t: cube((s * 0.070, -0.112, 0.058), (0.046, 0.024, 0.014),
                              rot=(R(-14), R(-26 * s), 0), mat="fur_dk", bevel=0.005,
                              smooth=True, name="brow_" + t))

# ---- 耳朵：贴着头往后翻，露一点粉色内耳
for s in (-1, 1):
    t = "L" if s < 0 else "R"
    head(lambda s=s, t=t: blob((s * 0.124, 0.030, 0.014), (0.028, 0.066, 0.018),
                              rot=(R(-34), R(8 * s), R(18 * s)), mat="fur_dk", seg=14,
                              ring=9, name="ear_" + t))
    head(lambda s=s, t=t: blob((s * 0.116, 0.026, 0.004), (0.018, 0.048, 0.010),
                              rot=(R(-34), R(8 * s), R(18 * s)), mat="gum", seg=12,
                              ring=8, name="ear_in_" + t))

# ---------------------------------------------------------------- 合并导出
for ob in _parts:
    ob.select_set(True)
bpy.context.view_layer.objects.active = _parts[0]
bpy.ops.object.join()
dog = bpy.context.active_object
dog.name = "BigDog"

# 朝向修正：Blender 里按 -Y 为前建模，但 glTF 的 Y-up 换算会把 -Y 翻成 glTF +Z，
# 进 Godot 就成了"屁股朝前"。这里整体绕 Z 转 180° 烘进网格，导出后狗头正好朝 Godot -Z。
dog.data.transform(Matrix.Rotation(PI, 4, "Z"))

if abs(SCALE - 1.0) > 1e-6:
    dog.scale = (SCALE, SCALE, SCALE)
    bpy.ops.object.transform_apply(scale=True)

me = dog.data
tris = sum(len(p.vertices) - 2 for p in me.polygons)
xs = [v.co for v in me.vertices]
mn = Vector((min(c.x for c in xs), min(c.y for c in xs), min(c.z for c in xs)))
mx = Vector((max(c.x for c in xs), max(c.y for c in xs), max(c.z for c in xs)))
print("DOG_BOUNDS_MIN %.4f %.4f %.4f" % tuple(mn))
print("DOG_BOUNDS_MAX %.4f %.4f %.4f" % tuple(mx))
print("DOG_SIZE %.4f %.4f %.4f" % tuple(mx - mn))
print("DOG_TRIANGLES", tris)
print("DOG_MATERIALS", [m.name for m in me.materials])

os.makedirs(os.path.dirname(os.path.abspath(OUT_GLB)) or ".", exist_ok=True)
bpy.ops.object.select_all(action="DESELECT")
dog.select_set(True)
bpy.context.view_layer.objects.active = dog
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True,
                          export_apply=True, export_yup=True)
print("WROTE", OUT_GLB, os.path.getsize(OUT_GLB), "bytes")

# ---------------------------------------------------------------- 预览渲染
center = (mn + mx) / 2.0
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 28
scene.cycles.use_denoising = True
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.image_settings.file_format = "PNG"
scene.world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
scene.world.use_nodes = True
bg = scene.world.node_tree.nodes.get("Background")
if bg:
    bg.inputs[0].default_value = (0.82, 0.84, 0.86, 1.0)
    bg.inputs[1].default_value = 0.45

bpy.ops.object.camera_add()
cam = bpy.context.object
cam.data.lens = 60
scene.camera = cam
bpy.ops.object.light_add(type="SUN")
sun = bpy.context.object
sun.data.energy = 2.0
sun.data.angle = R(8)
sun.rotation_euler = (R(48), R(12), R(28))
bpy.ops.object.light_add(type="SUN")
fill = bpy.context.object
fill.data.energy = 0.5
fill.rotation_euler = (R(60), R(-30), R(200))

VIEW_YAW = {"front": 0.0, "back": PI, "left": R(-90), "right": R(90),
            "three": R(-38), "top": 0.0, "face": R(-18)}
VIEW_PIT = {"front": 0.10, "back": 0.12, "left": 0.08, "right": 0.08,
            "three": 0.14, "top": 1.05, "face": 0.10}

os.makedirs(OUT_DIR, exist_ok=True)
dist = max(mx - mn) * 1.9
for v in VIEWS:
    yaw = VIEW_YAW.get(v, 0.0)
    pit = VIEW_PIT.get(v, 0.1)
    tgt, d = center, dist
    if v == "face":  # 怼脸看：梗图的灵魂全在龇牙的表情上
        tgt, d = Vector((0, 0.16, 0.40)), 0.90
    cam.location = (
        tgt.x + d * math.cos(pit) * math.sin(yaw),
        tgt.y + d * math.cos(pit) * math.cos(yaw),
        tgt.z + d * math.sin(pit),
    )
    look = Vector(tgt) - Vector(cam.location)
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    out = os.path.join(OUT_DIR, "dog_%s.png" % v)
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("RENDERED", out)
print("DONE")
