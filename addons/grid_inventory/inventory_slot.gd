@tool
extends Panel
class_name InventorySlot
## One visual slot. Handles drag and drop; rendering is driven by refresh().
var inventory: Inventory
var index: int = 0
@onready var _icon: TextureRect = $Icon
@onready var _placeholder: ColorRect = $Placeholder
func setup(inv: Inventory, slot_index: int) -> void:
	inventory = inv
	index = slot_index
	refresh()
func refresh() -> void:
	var slot = inventory.slots[index] if inventory != null else null
	if slot == null:
		_icon.texture = null
		_icon.visible = false
		_placeholder.visible = false
		tooltip_text = ""
		return
	var item: InvItem = slot.item
	if item.icon != null:
		_icon.texture = item.icon
		_icon.visible = true
		_placeholder.visible = false
	else:
		_icon.visible = false
		_placeholder.color = item.color
		_placeholder.visible = true
	tooltip_text = item.name
func _get_drag_data(_pos: Vector2) -> Variant:
	if inventory == null or inventory.slots[index] == null:
		return null
	var src = inventory.slots[index]
	var cr := ColorRect.new()
	cr.color = src.item.color
	cr.custom_minimum_size = Vector2(48, 48)
	set_drag_preview(cr)
	return {"from_index": index}
func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("from_index")
func _drop_data(_pos: Vector2, data: Variant) -> void:
	inventory.move_slot(data["from_index"], index)
