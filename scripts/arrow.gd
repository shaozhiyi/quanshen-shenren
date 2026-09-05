extends RigidBody3D
## 箭弹体：物理引擎负责重力抛物线——射程/落点完全由初速（蓄力程度）与出手角度决定。
## 命中 BOSS 按蓄力伤害扣血（满蓄 50），钉住 4 秒后消失；同屏最多 15 支，超出回收最旧的。

const ARROW_MODEL := preload("res://assets/weapons/arrow.glb")
const MAX_ALIVE := 15

static var _active: Array = []

var dmg := 50
var _hit := false
var _life := 0.0


static func spawn(parent: Node, cam_basis: Basis, origin: Vector3, speed: float, damage: int) -> void:
	## 从相机处生成一支箭：沿视线方向（-Z）给出初速
	_prune()
	while _active.size() >= MAX_ALIVE:
		var old = _active.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var ar: RigidBody3D = load("res://scripts/arrow.gd").new()
	ar.dmg = damage
	ar._configure()
	parent.add_child(ar)
	ar.global_transform = Transform3D(cam_basis.orthonormalized(), origin)
	ar.linear_velocity = -cam_basis.z * speed
	_active.append(ar)


static func _prune() -> void:
	var live: Array = []
	for a in _active:
		if is_instance_valid(a):
			live.append(a)
	_active = live


func _configure() -> void:
	mass = 0.06
	continuous_cd = true          # 高速箭防穿透
	contact_monitor = true
	max_contacts_reported = 2
	angular_damp = 2.0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	# 箭在层2：玩家/剑射线（层1查询）不受散落箭枝干扰
	collision_layer = 2
	collision_mask = 1
	# 视觉：arrow.glb 杆身沿 X 轴，旋转使 +X 朝前方 -Z
	var holder := Node3D.new()
	holder.rotation_degrees = Vector3(0, 90, 0)
	holder.scale = Vector3.ONE * 0.34
	holder.add_child(ARROW_MODEL.instantiate())
	add_child(holder)
	var csc := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.03
	cyl.height = 0.75
	csc.shape = cyl
	csc.rotation_degrees = Vector3(90, 0, 0)
	add_child(csc)
	body_entered.connect(_on_body_entered)


func _on_body_entered(other: Node) -> void:
	if _hit:
		return
	_hit = true
	if other != null and other.is_in_group("boss"):
		var n: Node = other
		while n != null and not n.has_method("take_damage"):
			n = n.get_parent()
		if n != null:
			n.take_damage(dmg, "弓")
	freeze = true
	set_contact_monitor.call_deferred(false)
	get_tree().create_timer(4.0).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	if _hit:
		return
	_life += delta
	if global_position.y < -30.0:
		queue_free()
		return
	if _life > 8.0:
		# 长时间未命中（落在远处/卡住）：钉住后延时回收
		_hit = true
		freeze = true
		set_contact_monitor.call_deferred(false)
		get_tree().create_timer(3.0).timeout.connect(queue_free)


func _exit_tree() -> void:
	_active.erase(self)
