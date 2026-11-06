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
var characters: PackedStringArray = []
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


## The entry point of the dialogue: the first cue declared in the file, or the
## first flow node when the file has no cues.
func get_start_node() -> DMGraphNode:
	var best_cue: DMGraphNode = null
	for cue_name: String in cues:
		var cue_node: DMGraphNode = get_node(cues[cue_name])
		if cue_node == null:
			continue
		if best_cue == null or _source_sort_key(cue_node) < _source_sort_key(best_cue):
			best_cue = cue_node
	if best_cue != null:
		return best_cue

	var best: DMGraphNode = null
	for node: DMGraphNode in nodes.values():
		if not _is_flow_node(node):
			continue
		if best == null or _source_sort_key(node) < _source_sort_key(best):
			best = node
	return best


## Returns human-readable problems used by the warning indicator. An empty array
## means the graph is fully connected and reaches an end from its start node.
func get_validation_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if nodes.is_empty():
		return warnings

	var start: DMGraphNode = get_start_node()
	if start == null:
		warnings.append("No start node")
		return warnings

	var reachable: Dictionary = _collect_reachable(start)

	var unconnected: PackedStringArray = []
	for node: DMGraphNode in nodes.values():
		if not _is_flow_node(node):
			continue
		if reachable.has(node.id):
			continue
		unconnected.append(_node_description(node))

	if not unconnected.is_empty():
		warnings.append("Unconnected nodes: %s" % [", ".join(unconnected)])

	var reaches_end: bool = false
	for node_id: String in reachable:
		var node: DMGraphNode = get_node(node_id)
		if node == null:
			continue
		if node.kind == DMGraphNode.Kind.JUMP and node.source_start < 0:
			reaches_end = true
			break
		if _is_flow_node(node) and not _has_flow_outgoing(node):
			reaches_end = true
			break

	if not reaches_end:
		warnings.append("Cannot reach the end from the start")

	return warnings


func _collect_reachable(start: DMGraphNode) -> Dictionary:
	var reachable: Dictionary = {}
	var queue: Array[String] = [start.id]
	reachable[start.id] = true

	var index: int = 0
	while index < queue.size():
		var current_id: String = queue[index]
		index += 1
		for edge: DMGraphEdge in edges:
			if edge.from_node != current_id:
				continue
			if reachable.has(edge.to_node):
				continue
			reachable[edge.to_node] = true
			queue.append(edge.to_node)

	return reachable


func _has_flow_outgoing(node: DMGraphNode) -> bool:
	for edge: DMGraphEdge in edges:
		if edge.from_node != node.id:
			continue
		if edge.kind == DMGraphEdge.Kind.CONCURRENT:
			continue
		return true
	return false


func _is_flow_node(node: DMGraphNode) -> bool:
	if node.source_start < 0:
		return false
	return node.kind not in [
		DMGraphNode.Kind.IMPORT,
		DMGraphNode.Kind.USING,
		DMGraphNode.Kind.NOTE,
		DMGraphNode.Kind.COMMENT
	]


func _source_sort_key(node: DMGraphNode) -> int:
	return node.source_start if node.source_start >= 0 else 999999


func _node_description(node: DMGraphNode) -> String:
	var label: String = DMGraphColors.get_kind_name(node.kind)
	if node.source_start < 0:
		return label

	var text: String = ""
	for key: String in ["cue", "text", "target", "expression"]:
		var value: Variant = node.get_property(key, "")
		if value is String and not value.is_empty():
			text = value.replace("\n", " ")
			break

	if text.is_empty():
		return "%s (line %d)" % [label, node.source_start + 1]
	return "%s \"%s\" (line %d)" % [label, text.substr(0, 40), node.source_start + 1]


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
		characters = Array(characters),
		source_lines = Array(source_lines)
	}
