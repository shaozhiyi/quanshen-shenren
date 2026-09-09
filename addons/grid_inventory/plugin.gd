@tool
extends EditorPlugin
## Grid Inventory ships its functionality through class_name scripts
## (InvItem, Inventory, InventoryUI, InventorySlot), so enabling the plugin
## just makes sure they are registered. No autoload required.
func _enter_tree() -> void:
	pass
func _exit_tree() -> void:
	pass
