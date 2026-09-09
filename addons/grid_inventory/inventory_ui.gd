@tool
extends Control
class_name InventoryUI
## Drop this node into your UI, assign an Inventory, and it renders a clickable,
## drag-and-drop grid that stays in sync via the inventory's signal.
const SLOT_SCENE := preload("res://addons/grid_inventory/inventory_slot.tscn")
@export var columns: int = 5:
	set(value):
		columns = max(1, value)
		if _grid != null:
			_grid.columns = columns
## Assign an Inventory resource here (or via set_inventory at runtime).
@export var inventory: Inventory:
	get:
		return _inventory
	set(value):
		set_inventory(value)
var _inventory: Inventory
var _grid: GridContainer
var _slots: Array[InventorySlot] = []
func _ready() -> void:
	if _grid == null:
		_grid = GridContainer.new()
		_grid.columns = columns
		_grid.set_anchors_preset(Control.PRESET_TOP_LEFT)
		add_child(_grid)
	if _inventory != null:
		_rebuild()
func set_inventory(inv: Inventory) -> void:
	if _inventory == inv:
		return
	if _inventory != null and _inventory.inventory_changed.is_connected(_on_changed):
		_inventory.inventory_changed.disconnect(_on_changed)
	_inventory = inv
	if _inventory != null:
		_inventory.inventory_changed.connect(_on_changed)
	if is_inside_tree():
		_rebuild()
func _rebuild() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()
	_slots.clear()
	if _inventory == null:
		return
	for i in _inventory.size:
		var slot: InventorySlot = SLOT_SCENE.instantiate()
		_grid.add_child(slot)
		slot.setup(_inventory, i)
		_slots.append(slot)
func _on_changed() -> void:
	if _slots.size() != _inventory.size:
		_rebuild()
		return
	for slot in _slots:
		slot.refresh()
