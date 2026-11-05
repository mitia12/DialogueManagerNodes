@tool
class_name DMGraphEdge extends RefCounted


enum Kind {
	FLOW,
	BRANCH,
	JUMP,
	RETURN,
	IMPORT,
	CONCURRENT
}


var from_node: String = ""
var from_port: int = 0
var to_node: String = ""
var to_port: int = 0
var kind: Kind = Kind.FLOW
var label: String = ""


func _init(
	initial_from_node: String = "",
	initial_from_port: int = 0,
	initial_to_node: String = "",
	initial_to_port: int = 0,
	initial_kind: Kind = Kind.FLOW,
	initial_label: String = ""
) -> void:
	from_node = initial_from_node
	from_port = initial_from_port
	to_node = initial_to_node
	to_port = initial_to_port
	kind = initial_kind
	label = initial_label


func to_dict() -> Dictionary:
	return {
		from_node = from_node,
		from_port = from_port,
		to_node = to_node,
		to_port = to_port,
		kind = kind,
		label = label
	}


static func from_dict(data: Dictionary) -> DMGraphEdge:
	return DMGraphEdge.new(
		data.get("from_node", ""),
		data.get("from_port", 0),
		data.get("to_node", ""),
		data.get("to_port", 0),
		data.get("kind", Kind.FLOW),
		data.get("label", "")
	)
