@tool
extends Resource
class_name Inventory
## A fixed-size, slot-based inventory. UI-agnostic — pair it with InventoryUI or
## drive your own interface from the `inventory_changed` signal.
##
## ─────────────────────────────────────────────────────────────────────────
## Grid Inventory LITE: one item per slot, move & swap via drag and drop.
## Grid Inventory PRO adds: stacking & auto-merge with per-item max_stack,
## quantity counters, item tooltips, count_of()/has_item() query helpers, and
## one-call save/load. Same classes, drop-in upgrade:
##   https://godot-forge.itch.io/grid-inventory-godot
## ─────────────────────────────────────────────────────────────────────────
signal inventory_changed
signal item_added(item: InvItem)
signal full(item: InvItem)
@export var size: int = 20:
	set(value):
		size = max(1, value)
		_resize_slots()
## Each slot is either null or {"item": InvItem}.
var slots: Array = []
func _init(slot_count: int = 20) -> void:
	size = slot_count
func _resize_slots() -> void:
	slots.resize(size)
## Places `item` in the first empty slot. Returns true if it fit.
func add_item(item: InvItem) -> bool:
	if item == null:
		return false
	var idx := _first_empty()
	if idx == -1:
		full.emit(item)
		return false
	slots[idx] = {"item": item}
	item_added.emit(item)
	inventory_changed.emit()
	return true
## Removes whatever is in `index`.
func remove_at(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	if slots[index] != null:
		slots[index] = null
		inventory_changed.emit()
## Swaps the contents of two slots (used by drag and drop).
func move_slot(from_index: int, to_index: int) -> void:
	if from_index == to_index:
		return
	if from_index < 0 or to_index < 0 or from_index >= slots.size() or to_index >= slots.size():
		return
	if slots[from_index] == null:
		return
	var tmp = slots[to_index]
	slots[to_index] = slots[from_index]
	slots[from_index] = tmp
	inventory_changed.emit()
func clear() -> void:
	for i in slots.size():
		slots[i] = null
	inventory_changed.emit()
func _first_empty() -> int:
	for i in slots.size():
		if slots[i] == null:
			return i
	return -1
