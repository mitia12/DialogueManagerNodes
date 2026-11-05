@tool
class_name DMGraphNode extends RefCounted


enum Kind {
	CUE,
	DIALOGUE,
	CHOICES,
	RESPONSE,
	CONDITION,
	MATCH,
	WHILE,
	MUTATION,
	JUMP,
	RANDOM,
	CONCURRENT,
	COMMENT,
	IMPORT,
	USING,
	NOTE
}


var id: String = ""
var kind: Kind = Kind.DIALOGUE
var stable_key: String = ""
## 0-based source line range, inclusive.
var source_start: int = -1
var source_end: int = -1
var indent: int = 0
var parent_id: String = ""
var children: PackedStringArray = []
## Each port is { name: String, kind: String, color: Color }.
var ports: Array[Dictionary] = []
var properties: Dictionary = {}
var position: Vector2 = Vector2.ZERO
var size: Vector2 = Vector2.ZERO
var collapsed: bool = false


func _init(initial_id: String = "", initial_kind: Kind = Kind.DIALOGUE) -> void:
	id = initial_id
	kind = initial_kind


func get_property(key: String, default: Variant = null) -> Variant:
	return properties.get(key, default)


func set_property(key: String, value: Variant) -> void:
	properties[key] = value


func add_port(port_name: String, port_kind: String, color: Color = Color.WHITE) -> int:
	ports.append({
		name = port_name,
		kind = port_kind,
		color = color
	})
	return ports.size() - 1


func to_dict() -> Dictionary:
	return {
		id = id,
		kind = kind,
		stable_key = stable_key,
		source_start = source_start,
		source_end = source_end,
		indent = indent,
		parent_id = parent_id,
		children = Array(children),
		ports = ports.duplicate(true),
		properties = properties.duplicate(true),
		position = [position.x, position.y],
		size = [size.x, size.y],
		collapsed = collapsed
	}


static func from_dict(data: Dictionary) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(
		data.get("id", ""),
		data.get("kind", Kind.DIALOGUE)
	)
	node.stable_key = data.get("stable_key", "")
	node.source_start = data.get("source_start", -1)
	node.source_end = data.get("source_end", -1)
	node.indent = data.get("indent", 0)
	node.parent_id = data.get("parent_id", "")
	node.children = PackedStringArray(data.get("children", []))
	node.ports.clear()
	for port: Dictionary in Array(data.get("ports", [])):
		node.ports.append(port)
	node.properties = data.get("properties", {})
	var position_data: Array = data.get("position", [0, 0])
	node.position = Vector2(position_data[0], position_data[1])
	var size_data: Array = data.get("size", [0, 0])
	node.size = Vector2(size_data[0], size_data[1])
	node.collapsed = data.get("collapsed", false)
	return node
