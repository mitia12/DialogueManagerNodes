@tool
class_name DMGraphDocument extends RefCounted


var path: String = ""
var text: String = ""
## String -> DMGraphNode
var nodes: Dictionary = {}
var edges: Array[DMGraphEdge] = []
## cue name -> node id
var cues: Dictionary = {}
## compiled line id -> graph node id
var line_nodes: Dictionary = {}
## first response line id -> choices node id
var response_groups: Dictionary = {}
var first_cue: String = ""
var imports: Array[Dictionary] = []
var using_states: PackedStringArray = []
var errors: Array[DMError] = []
var source_lines: PackedStringArray = []


func get_node(node_id: String) -> DMGraphNode:
	return nodes.get(node_id, null)


func add_node(node: DMGraphNode) -> void:
	nodes[node.id] = node


func remove_node(node_id: String) -> void:
	nodes.erase(node_id)
	for i: int in range(edges.size() - 1, -1, -1):
		var edge: DMGraphEdge = edges[i]
		if edge.from_node == node_id or edge.to_node == node_id:
			edges.remove_at(i)


func add_edge(edge: DMGraphEdge) -> void:
	edges.append(edge)


func get_edges_from(node_id: String) -> Array[DMGraphEdge]:
	var result: Array[DMGraphEdge] = []
	for edge: DMGraphEdge in edges:
		if edge.from_node == node_id:
			result.append(edge)
	return result


func get_edges_to(node_id: String) -> Array[DMGraphEdge]:
	var result: Array[DMGraphEdge] = []
	for edge: DMGraphEdge in edges:
		if edge.to_node == node_id:
			result.append(edge)
	return result


func find_node_for_line(line_number: int) -> DMGraphNode:
	# line_number is 1-based, source ranges are 0-based.
	var source_line: int = line_number - 1
	for node: DMGraphNode in nodes.values():
		if node.source_start <= source_line and source_line <= node.source_end:
			return node
	return null


func find_cue_node(cue: String) -> DMGraphNode:
	if cues.has(cue):
		return get_node(cues[cue])
	return null


func to_dict() -> Dictionary:
	var node_data: Dictionary = {}
	for node_id: String in nodes:
		node_data[node_id] = nodes[node_id].to_dict()

	var edge_data: Array = []
	for edge: DMGraphEdge in edges:
		edge_data.append(edge.to_dict())

	return {
		path = path,
		text = text,
		nodes = node_data,
		edges = edge_data,
		cues = cues.duplicate(true),
		first_cue = first_cue,
		imports = imports.duplicate(true),
		using_states = Array(using_states),
		source_lines = Array(source_lines)
	}
