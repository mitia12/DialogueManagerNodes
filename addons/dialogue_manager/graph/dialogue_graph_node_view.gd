@tool
class_name DMGraphNodeView extends GraphNode


var graph_node: DMGraphNode
var document: DMGraphDocument


func setup(node: DMGraphNode, doc: DMGraphDocument) -> void:
	graph_node = node
	document = doc

	name = safe_name(node.id)
	title = "End" if node.source_start < 0 else _get_kind_title(node.kind)
	position_offset = node.position
	custom_minimum_size = Vector2(240, 0)
	size = node.size if node.size != Vector2.ZERO else Vector2(240, 0)
	resizable = true
	draggable = true
	selectable = true

	var color: Color = _get_kind_color(node.kind)

	match node.kind:
		DMGraphNode.Kind.CUE:
			var cue_label: String = "~ " + str(node.get_property("cue", ""))
			if node.get_property("is_first", false):
				cue_label = "★ " + cue_label
			_add_port_row(cue_label, true, true, color)

		DMGraphNode.Kind.DIALOGUE:
			var character: String = node.get_property("character", "")
			var text: String = node.get_property("text", "")
			var label: String = text if character.is_empty() else "%s: %s" % [character, text]
			_add_port_row(_short(label), true, true, color)
			if node.get_property("goto_is_snippet", false):
				_add_port_row("Return", false, true, Color(0.8, 0.6, 0.2))
			_add_goto_label(node)

		DMGraphNode.Kind.RESPONSE:
			var response_character: String = node.get_property("character", "")
			var response_text: String = node.get_property("text", "")
			var response_label: String = response_text if response_character.is_empty() else "%s: %s" % [response_character, response_text]
			_add_port_row("- " + _short(response_label), true, true, color)
			if node.get_property("goto_is_snippet", false):
				_add_port_row("Return", false, true, Color(0.8, 0.6, 0.2))
			_add_goto_label(node)

		DMGraphNode.Kind.CHOICES:
			_add_port_row("Choices", true, false, color)
			for port: Dictionary in node.ports:
				_add_port_row(_short(port.get("name", "")), false, true, color)

		DMGraphNode.Kind.CONDITION:
			var cases: Array = Array(node.get_property("cases", []))
			var first_expression: String = ""
			if not cases.is_empty():
				first_expression = cases.front().get("expression", "")
			_add_port_row("if " + _short(first_expression), true, false, color)
			for port: Dictionary in node.ports:
				_add_port_row(_short(port.get("name", "")), false, true, color)

		DMGraphNode.Kind.MATCH:
			_add_port_row("match " + _short(node.get_property("expression", "")), true, false, color)
			for port: Dictionary in node.ports:
				_add_port_row(_short(port.get("name", "")), false, true, color)

		DMGraphNode.Kind.WHILE:
			_add_port_row("while " + _short(node.get_property("expression", "")), true, false, color)
			for port: Dictionary in node.ports:
				_add_port_row(_short(port.get("name", "")), false, true, color)

		DMGraphNode.Kind.MUTATION:
			_add_port_row("$> " + _short(node.get_property("expression", "")), true, true, color)

		DMGraphNode.Kind.JUMP:
			_add_port_row("=> " + _short(node.get_property("target", "")), true, true, color)
			if node.get_property("is_snippet", false):
				_add_port_row("Return", false, true, Color(0.8, 0.6, 0.2))

		DMGraphNode.Kind.RANDOM:
			_add_port_row("Random", true, false, color)
			for port: Dictionary in node.ports:
				_add_port_row(_short(port.get("name", "")), false, true, color)

		DMGraphNode.Kind.CONCURRENT:
			var concurrent_character: String = node.get_property("character", "")
			var concurrent_text: String = node.get_property("text", "")
			var concurrent_label: String = concurrent_text if concurrent_character.is_empty() else "%s: %s" % [concurrent_character, concurrent_text]
			_add_port_row("| " + _short(concurrent_label), true, false, color)

		DMGraphNode.Kind.IMPORT:
			_add_port_row("import " + _short(node.get_property("path", "")), false, false, color)

		DMGraphNode.Kind.USING:
			_add_port_row("using " + _short(node.get_property("state", "")), false, false, color)

		DMGraphNode.Kind.COMMENT:
			_add_port_row(_short(node.get_property("text", "")), true, true, color)

		DMGraphNode.Kind.NOTE:
			_add_port_row(_short(node.get_property("text", "")), false, false, color)

	set_error_state(false)


func refresh() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	setup(graph_node, document)


func set_error_state(has_error: bool) -> void:
	modulate = Color(1, 0.7, 0.7) if has_error else Color.WHITE
	tooltip_text = "Has errors" if has_error else ""


## The first row of some nodes is a header with only an input port. The model's
## output port indices start at 0, so the view needs to offset them by one.
func get_port_slot_offset() -> int:
	match graph_node.kind:
		DMGraphNode.Kind.CHOICES, DMGraphNode.Kind.CONDITION, DMGraphNode.Kind.MATCH, DMGraphNode.Kind.WHILE, DMGraphNode.Kind.RANDOM:
			return 1
		_:
			return 0


func _add_goto_label(node: DMGraphNode) -> void:
	var goto: String = node.get_property("goto", "")
	if goto.is_empty():
		return
	var prefix: String = "↩ " if node.get_property("goto_is_snippet", false) else "→ "
	_add_plain_label(prefix + goto)


func _add_plain_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(200, 0)
	add_child(label)


func _add_port_row(text: String, has_input: bool, has_output: bool, color: Color) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(220, 0)

	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(200, 0)
	row.add_child(label)

	add_child(row)
	var slot_index: int = get_child_count() - 1
	set_slot(slot_index, has_input, 0, color, has_output, 0, color)
	return row


func _get_kind_color(kind: DMGraphNode.Kind) -> Color:
	match kind:
		DMGraphNode.Kind.CUE:
			return Color(0.35, 0.65, 1.0)
		DMGraphNode.Kind.DIALOGUE:
			return Color(0.35, 0.8, 0.45)
		DMGraphNode.Kind.CHOICES:
			return Color(0.9, 0.6, 0.2)
		DMGraphNode.Kind.RESPONSE:
			return Color(0.9, 0.75, 0.25)
		DMGraphNode.Kind.CONDITION, DMGraphNode.Kind.MATCH, DMGraphNode.Kind.WHILE:
			return Color(0.7, 0.45, 0.9)
		DMGraphNode.Kind.MUTATION:
			return Color(0.6, 0.6, 0.6)
		DMGraphNode.Kind.JUMP:
			return Color(0.9, 0.3, 0.3)
		DMGraphNode.Kind.RANDOM:
			return Color(0.2, 0.8, 0.8)
		DMGraphNode.Kind.CONCURRENT:
			return Color(0.35, 0.8, 0.45)
		DMGraphNode.Kind.IMPORT:
			return Color(0.35, 0.65, 1.0)
		_:
			return Color(0.5, 0.5, 0.5)


func _get_kind_title(kind: DMGraphNode.Kind) -> String:
	match kind:
		DMGraphNode.Kind.CUE:
			return "Cue"
		DMGraphNode.Kind.DIALOGUE:
			return "Dialogue"
		DMGraphNode.Kind.CHOICES:
			return "Choices"
		DMGraphNode.Kind.RESPONSE:
			return "Response"
		DMGraphNode.Kind.CONDITION:
			return "Condition"
		DMGraphNode.Kind.MATCH:
			return "Match"
		DMGraphNode.Kind.WHILE:
			return "While"
		DMGraphNode.Kind.MUTATION:
			return "Mutation"
		DMGraphNode.Kind.JUMP:
			return "Jump"
		DMGraphNode.Kind.RANDOM:
			return "Random"
		DMGraphNode.Kind.CONCURRENT:
			return "Concurrent"
		DMGraphNode.Kind.COMMENT:
			return "Comment"
		DMGraphNode.Kind.IMPORT:
			return "Import"
		DMGraphNode.Kind.USING:
			return "Using"
		DMGraphNode.Kind.NOTE:
			return "Note"
		_:
			return "Node"


static func _short(text: String, max_length: int = 80) -> String:
	var single_line: String = text.replace("\n", " ")
	if single_line.length() > max_length:
		return single_line.substr(0, max_length - 3) + "..."
	return single_line


static func safe_name(id: String) -> String:
	var safe: String = id.replace(":", "_").replace("/", "_").replace(".", "_").replace(" ", "_")
	if safe.is_empty():
		return "node"
	return safe
