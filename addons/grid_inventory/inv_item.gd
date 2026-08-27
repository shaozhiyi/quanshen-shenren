@tool
extends Resource
class_name InvItem
## A single item definition. Create instances as .tres resources in the editor.
## (Lite edition — stacking fields live in the PRO version.)

@export var id: StringName = &""
@export var name: String = "Item"
@export_multiline var description: String = ""
@export var icon: Texture2D
## Optional tint used for placeholder icons when `icon` is null.
@export var color: Color = Color.WHITE
