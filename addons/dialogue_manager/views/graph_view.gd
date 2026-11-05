@tool
class_name DMGraphView extends Control


signal text_changed(new_text: String, description: String)
signal test_requested(from_key: String)
signal error_selected(line_number: int)
signal node_selected(node: DMGraphNode)


const EXPORT_TO_CSV_DIALOG: PackedScene = preload("../components/export_to_csv_dialog.tscn")


var document: DMGraphDocument
var is_syncing: bool = false
var is_dirty: bool = false
var is_building: bool = false
var current_path: String = ""

var graph_edit: GraphEdit
var inspector: VBoxContainer
var status_label: Label
var node_views: Dictionary = {}
var selected_node: DMGraphNode
var inspector_fields: Dictionary = {}
var popup_position: Vector2 = Vector2.ZERO
var last_errors: Array[DMError] = []


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()


func load_document(path: String, text: String) -> void:
	current_path = path
	last_errors = []
	document = DMGraphBuilder.build(text, path)
	DMGraphSidecar.apply_to_document(document, DMGraphSidecar.load_for(path))
	selected_node = null
	_build_graph()
	_build_inspector()


func clear_document() -> void:
	current_path = ""
	document = null
	selected_node = null
	last_errors = []
	node_views.clear()
	if is_instance_valid(graph_edit):
		for child: Node in graph_edit.get_children():
			if child is GraphElement:
				graph_edit.remove_child(child)
				child.queue_free()
	_build_inspector()


func sync_from_text(text: String) -> void:
	if is_syncing or current_path.is_empty():
		return

	var selected_id: String = selected_node.id if selected_node != null else ""
	is_syncing = true
	last_errors = []
	document = DMGraphBuilder.build(text, current_path)
	DMGraphSidecar.apply_to_document(document, DMGraphSidecar.load_for(current_path))
	selected_node = null
	_build_graph()
	if not selected_id.is_empty() and document.nodes.has(selected_id):
		select_node(selected_id)
	else:
		_build_inspector()
	is_syncing = false


func rebuild() -> void:
	if document == null:
		return
	_build_graph()
	_build_inspector()


func set_errors(errors: Array[DMError]) -> void:
	last_errors = errors
	if document != null:
		document.errors = errors
	_apply_errors()


func _apply_errors() -> void:
	if document == null:
		return

	for node_id: String in node_views:
		var view: DMGraphNodeView = node_views[node_id]
		var graph_node: DMGraphNode = document.get_node(node_id)
		if graph_node == null:
			continue

		var has_error: bool = false
		for error: DMError in last_errors:
			var source_line: int = error.line_number - 1
			if graph_node.source_start <= source_line and source_line <= graph_node.source_end:
				has_error = true
				break
		view.set_error_state(has_error)


func select_node(node_id: String) -> void:
	if not node_views.has(node_id):
		return

	var view: DMGraphNodeView = node_views[node_id]
	view.selected = true
	selected_node = view.graph_node
	_build_inspector()

	if is_instance_valid(graph_edit) and graph_edit.is_visible_in_tree():
		graph_edit.scroll_offset = view.position_offset - graph_edit.size / 2


func select_cue(cue: String) -> void:
	if document == null:
		return
	var node: DMGraphNode = document.find_cue_node(cue)
	if node != null:
		select_node(node.id)


func select_line(line_number: int) -> void:
	if document == null:
		return
	var node: DMGraphNode = document.find_node_for_line(line_number)
	if node != null:
		select_node(node.id)


func move_sidecar(old_path: String, new_path: String) -> void:
	DMGraphSidecar.move(old_path, new_path)


func remove_sidecar(path: String) -> void:
	DMGraphSidecar.remove(path)


func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var toolbar: HBoxContainer = HBoxContainer.new()
	root.add_child(toolbar)

	var add_button: MenuButton = MenuButton.new()
	add_button.text = "Add"
	add_button.tooltip_text = "Add a node"
	var add_popup: PopupMenu = add_button.get_popup()
	add_popup.add_item("Dialogue", 0)
	add_popup.add_item("Response", 1)
	add_popup.add_item("Cue", 2)
	add_popup.add_item("Jump", 3)
	add_popup.add_item("Mutation", 4)
	add_popup.add_item("Comment", 5)
	add_popup.id_pressed.connect(_on_add_node_pressed)
	toolbar.add_child(add_button)

	var auto_button: Button = Button.new()
	auto_button.text = "Auto layout"
	auto_button.pressed.connect(_on_auto_layout_pressed)
	toolbar.add_child(auto_button)

	var test_button: Button = Button.new()
	test_button.text = "Test"
	test_button.pressed.connect(_on_test_pressed)
	toolbar.add_child(test_button)

	var localization_button: Button = Button.new()
	localization_button.text = "Localization"
	localization_button.pressed.connect(_open_localization_panel)
	toolbar.add_child(localization_button)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	status_label = Label.new()
	status_label.text = ""
	toolbar.add_child(status_label)

	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	graph_edit = GraphEdit.new()
	graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_edit.show_grid = true
	graph_edit.snapping_enabled = true
	graph_edit.snapping_distance = 20
	graph_edit.panning_scheme = GraphEdit.SCROLL_ZOOMS
	graph_edit.zoom_min = 0.25
	graph_edit.zoom_max = 2.0
	graph_edit.minimap_enabled = true
	graph_edit.right_disconnects = true
	graph_edit.connection_lines_curvature = 0.5
	graph_edit.connection_lines_thickness = 2.0
	graph_edit.connection_lines_antialiased = true
	graph_edit.connection_request.connect(_on_connection_request)
	graph_edit.disconnection_request.connect(_on_disconnection_request)
	graph_edit.node_selected.connect(_on_node_selected)
	graph_edit.node_deselected.connect(_on_node_deselected)
	graph_edit.popup_request.connect(_on_popup_request)
	graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	graph_edit.end_node_move.connect(_on_end_node_move)
	split.add_child(graph_edit)

	var inspector_scroll: ScrollContainer = ScrollContainer.new()
	inspector_scroll.custom_minimum_size = Vector2(280, 0)
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(inspector_scroll)

	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(inspector)

	_build_inspector()


func _build_graph() -> void:
	if not is_instance_valid(graph_edit):
		return

	is_building = true
	for child: Node in graph_edit.get_children():
		if child is GraphElement:
			graph_edit.remove_child(child)
			child.queue_free()
	node_views.clear()

	if document == null:
		is_building = false
		return

	for node: DMGraphNode in document.nodes.values():
		var view: DMGraphNodeView = DMGraphNodeView.new()
		view.setup(node, document)
		graph_edit.add_child(view)
		node_views[node.id] = view

	for edge: DMGraphEdge in document.edges:
		if not node_views.has(edge.from_node) or not node_views.has(edge.to_node):
			continue

		var from_view: DMGraphNodeView = node_views[edge.from_node]
		var to_view: DMGraphNodeView = node_views[edge.to_node]
		var from_slot: int = edge.from_port + from_view.get_port_slot_offset()
		if from_slot >= from_view.get_output_port_count():
			continue
		if edge.to_port >= to_view.get_input_port_count():
			continue

		var from_name: StringName = StringName(DMGraphNodeView.safe_name(edge.from_node))
		var to_name: StringName = StringName(DMGraphNodeView.safe_name(edge.to_node))
		graph_edit.connect_node(from_name, from_slot, to_name, edge.to_port)

	var has_saved_positions: bool = false
	for node: DMGraphNode in document.nodes.values():
		if node.has_saved_position:
			has_saved_positions = true
			break

	if has_saved_positions:
		for node: DMGraphNode in document.nodes.values():
			if node.has_saved_position:
				continue
			var default_position: Vector2 = Vector2(400, 0) if node.source_start < 0 else Vector2(0, (node.source_start + 1) * 140)
			node.position = default_position
			if node_views.has(node.id):
				node_views[node.id].position_offset = default_position
	else:
		_arrange_graph()

	_apply_errors()
	is_building = false


func _arrange_graph() -> void:
	if document == null:
		return

	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	for node: DMGraphNode in document.nodes.values():
		incoming[node.id] = 0
		outgoing[node.id] = []

	for edge: DMGraphEdge in document.edges:
		if edge.kind not in [DMGraphEdge.Kind.FLOW, DMGraphEdge.Kind.BRANCH]:
			continue
		if not incoming.has(edge.to_node) or not outgoing.has(edge.from_node):
			continue
		incoming[edge.to_node] += 1
		outgoing[edge.from_node].append(edge)

	var layers: Dictionary = {}
	var queue: Array[String] = []

	for node: DMGraphNode in document.nodes.values():
		if incoming.get(node.id, 0) == 0:
			layers[node.id] = 0
			queue.append(node.id)

	if queue.is_empty():
		for node: DMGraphNode in document.nodes.values():
			layers[node.id] = 0
			queue.append(node.id)

	var index: int = 0
	while index < queue.size():
		var node_id: String = queue[index]
		index += 1
		var layer: int = layers[node_id]
		for edge: DMGraphEdge in outgoing.get(node_id, []):
			if layers.has(edge.to_node):
				continue
			layers[edge.to_node] = layer + 1
			queue.append(edge.to_node)

	for node: DMGraphNode in document.nodes.values():
		if not layers.has(node.id):
			layers[node.id] = 0

	# Simultaneous lines stay on the same layer as their origin.
	for edge: DMGraphEdge in document.edges:
		if edge.kind == DMGraphEdge.Kind.CONCURRENT:
			layers[edge.to_node] = layers.get(edge.from_node, 0)

	var max_layer: int = 0
	for layer_value: int in layers.values():
		max_layer = max(max_layer, layer_value)

	# End nodes go to the final column.
	for node: DMGraphNode in document.nodes.values():
		if node.id in ["__end__", "__end_conversation__"]:
			layers[node.id] = max_layer + 1

	var by_layer: Dictionary = {}
	for node: DMGraphNode in document.nodes.values():
		var layer_value: int = layers.get(node.id, 0)
		if not by_layer.has(layer_value):
			by_layer[layer_value] = []
		by_layer[layer_value].append(node)

	var x_spacing: int = 340
	var y_spacing: int = 160
	for layer_value: int in by_layer:
		var nodes: Array = by_layer[layer_value]
		nodes.sort_custom(func(a: DMGraphNode, b: DMGraphNode) -> bool:
			return a.source_start < b.source_start
		)
		for i: int in nodes.size():
			var node: DMGraphNode = nodes[i]
			var position: Vector2 = Vector2(layer_value * x_spacing, i * y_spacing)
			node.position = position
			if node_views.has(node.id):
				node_views[node.id].position_offset = position


func _build_inspector() -> void:
	if not is_instance_valid(inspector):
		return

	for child: Node in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	inspector_fields.clear()

	if selected_node == null:
		var empty_label: Label = Label.new()
		empty_label.text = "Select a node"
		inspector.add_child(empty_label)
		return

	var title: Label = Label.new()
	title.text = "End" if selected_node.source_start < 0 else "Line %d" % [selected_node.source_start + 1]
	inspector.add_child(title)

	match selected_node.kind:
		DMGraphNode.Kind.DIALOGUE:
			_add_label("Character")
			_add_line_edit("character", selected_node.get_property("character", ""))
			_add_label("Text")
			_add_text_edit("text", selected_node.get_property("text", ""))
			_add_label("Tags")
			_add_line_edit("tags", ", ".join(PackedStringArray(selected_node.get_property("tags", []))))
			_add_label("Static ID")
			_add_line_edit("static_id", selected_node.get_property("static_id", ""))
			_add_label("Goto")
			_add_line_edit("goto", selected_node.get_property("goto", ""))
			_add_check_box("goto_is_snippet", selected_node.get_property("goto_is_snippet", false), "Jump and return")
			_add_label("Translator note")
			_add_read_only_text(selected_node.get_property("notes", ""))
			_add_apply_button()

		DMGraphNode.Kind.RESPONSE:
			_add_label("Character")
			_add_line_edit("character", selected_node.get_property("character", ""))
			_add_label("Prompt")
			_add_line_edit("text", selected_node.get_property("text", ""))
			_add_label("Tags")
			_add_line_edit("tags", ", ".join(PackedStringArray(selected_node.get_property("tags", []))))
			_add_label("Condition")
			_add_line_edit("condition", selected_node.get_property("condition", ""))
			_add_label("Goto")
			_add_line_edit("goto", selected_node.get_property("goto", ""))
			_add_check_box("goto_is_snippet", selected_node.get_property("goto_is_snippet", false), "Jump and return")
			_add_label("Static ID")
			_add_line_edit("static_id", selected_node.get_property("static_id", ""))
			_add_label("Translator note")
			_add_read_only_text(selected_node.get_property("notes", ""))
			_add_apply_button()

		DMGraphNode.Kind.CUE:
			_add_label("Cue name")
			_add_line_edit("name", selected_node.get_property("cue", ""))
			_add_apply_button()

		DMGraphNode.Kind.JUMP:
			if selected_node.source_start < 0:
				_add_label("Virtual end node")
				return
			_add_label("Target")
			_add_line_edit("target", selected_node.get_property("target", ""))
			_add_check_box("is_snippet", selected_node.get_property("is_snippet", false), "Jump and return")
			_add_apply_button()

		DMGraphNode.Kind.MUTATION:
			_add_label("Expression")
			_add_line_edit("expression", selected_node.get_property("expression", ""))
			_add_check_box("is_blocking", selected_node.get_property("is_blocking", true), "Blocking")
			_add_apply_button()

		DMGraphNode.Kind.COMMENT:
			_add_label("Comment")
			_add_line_edit("text", selected_node.get_property("text", ""))
			_add_apply_button()

		DMGraphNode.Kind.CONDITION:
			var condition_cases: Array = Array(selected_node.get_property("cases", []))
			var condition_edits: Array = []
			for i: int in condition_cases.size():
				var condition_case: Dictionary = condition_cases[i]
				_add_label("Case %d" % [i + 1])
				if condition_case.get("is_else", false):
					_add_label("else")
					condition_edits.append(null)
				else:
					condition_edits.append(_add_line_edit("condition_case_%d" % [i], condition_case.get("expression", "")))
			inspector_fields["condition_case_data"] = condition_cases
			inspector_fields["condition_case_edits"] = condition_edits
			_add_apply_button()

		DMGraphNode.Kind.MATCH:
			var match_cases: Array = Array(selected_node.get_property("cases", []))
			var match_edits: Array = []
			for i: int in match_cases.size():
				var match_case: Dictionary = match_cases[i]
				_add_label("Case %d" % [i + 1])
				if match_case.get("is_else", false):
					_add_label("else")
					match_edits.append(null)
				else:
					match_edits.append(_add_line_edit("match_case_%d" % [i], match_case.get("expression", "")))
			inspector_fields["match_case_data"] = match_cases
			inspector_fields["match_case_edits"] = match_edits
			_add_apply_button()

		DMGraphNode.Kind.WHILE:
			_add_label("Condition")
			_add_line_edit("while_expression", selected_node.get_property("expression", ""))
			_add_apply_button()

		DMGraphNode.Kind.RANDOM:
			var random_branches: Array = Array(selected_node.get_property("branches", []))
			var random_edits: Array = []
			for i: int in random_branches.size():
				var branch: Dictionary = random_branches[i]
				_add_label("Branch %d" % [i + 1])
				_add_label("Weight")
				var weight_edit: LineEdit = _add_line_edit("random_weight_%d" % [i], str(branch.get("weight", 1.0)))
				_add_label("Condition")
				var condition_edit: LineEdit = _add_line_edit("random_condition_%d" % [i], branch.get("condition_text", ""))
				random_edits.append({
					weight = weight_edit,
					condition = condition_edit
				})
			inspector_fields["random_branch_data"] = random_branches
			inspector_fields["random_branch_edits"] = random_edits
			_add_apply_button()

		_:
			var summary: Label = Label.new()
			summary.text = "This node is read-only in the current version."
			inspector.add_child(summary)
			var delete_button: Button = Button.new()
			delete_button.text = "Delete node"
			delete_button.pressed.connect(_on_delete_selected_pressed)
			inspector.add_child(delete_button)


func _add_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	inspector.add_child(label)


func _add_line_edit(key: String, value: String) -> LineEdit:
	var edit: LineEdit = LineEdit.new()
	edit.text = value
	inspector.add_child(edit)
	inspector_fields[key] = edit
	return edit


func _add_text_edit(key: String, value: String) -> TextEdit:
	var edit: TextEdit = TextEdit.new()
	edit.text = value
	edit.custom_minimum_size = Vector2(0, 100)
	inspector.add_child(edit)
	inspector_fields[key] = edit
	return edit


func _add_read_only_text(value: String) -> void:
	var edit: TextEdit = TextEdit.new()
	edit.text = value
	edit.editable = false
	edit.custom_minimum_size = Vector2(0, 60)
	inspector.add_child(edit)


func _add_check_box(key: String, value: bool, text: String) -> CheckBox:
	var check: CheckBox = CheckBox.new()
	check.text = text
	check.button_pressed = value
	inspector.add_child(check)
	inspector_fields[key] = check
	return check


func _add_apply_button() -> void:
	var apply: Button = Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_on_apply_inspector_pressed)
	inspector.add_child(apply)


func _on_apply_inspector_pressed() -> void:
	if selected_node == null or document == null:
		return

	var new_text: String = document.text
	match selected_node.kind:
		DMGraphNode.Kind.DIALOGUE:
			var dialogue_properties: Dictionary = {
				character = inspector_fields["character"].text,
				text = inspector_fields["text"].text,
				tags = _parse_tags(inspector_fields["tags"].text),
				static_id = inspector_fields["static_id"].text,
				goto = inspector_fields["goto"].text,
				goto_is_snippet = inspector_fields["goto_is_snippet"].button_pressed
			}
			new_text = DMGraphSerializer.set_dialogue_properties(new_text, selected_node, dialogue_properties)

		DMGraphNode.Kind.RESPONSE:
			var response_properties: Dictionary = {
				character = inspector_fields["character"].text,
				text = inspector_fields["text"].text,
				tags = _parse_tags(inspector_fields["tags"].text),
				condition = inspector_fields["condition"].text,
				goto = inspector_fields["goto"].text,
				goto_is_snippet = inspector_fields["goto_is_snippet"].button_pressed,
				static_id = inspector_fields["static_id"].text
			}
			new_text = DMGraphSerializer.set_response_properties(new_text, selected_node, response_properties)

		DMGraphNode.Kind.CUE:
			new_text = DMGraphSerializer.set_cue_name(new_text, selected_node, inspector_fields["name"].text)

		DMGraphNode.Kind.JUMP:
			var jump_raw_text: String = selected_node.get_property("raw_text", "")
			if jump_raw_text.strip_edges().begins_with("%"):
				new_text = DMGraphSerializer.set_inline_goto(
					new_text,
					selected_node,
					inspector_fields["target"].text,
					inspector_fields["is_snippet"].button_pressed
				)
			else:
				new_text = DMGraphSerializer.set_jump_target(
					new_text,
					selected_node,
					inspector_fields["target"].text,
					inspector_fields["is_snippet"].button_pressed
				)

		DMGraphNode.Kind.MUTATION:
			new_text = DMGraphSerializer.set_mutation_expression(
				new_text,
				selected_node,
				inspector_fields["expression"].text,
				inspector_fields["is_blocking"].button_pressed
			)

		DMGraphNode.Kind.COMMENT:
			new_text = DMGraphSerializer.set_comment_text(new_text, selected_node, inspector_fields["text"].text)

		DMGraphNode.Kind.CONDITION:
			var condition_data: Array = inspector_fields["condition_case_data"]
			var condition_edits: Array = inspector_fields["condition_case_edits"]
			var new_condition_cases: Array = []
			for i: int in condition_data.size():
				var condition_case: Dictionary = condition_data[i].duplicate()
				if condition_edits[i] != null:
					condition_case.expression = condition_edits[i].text
				new_condition_cases.append(condition_case)
			new_text = DMGraphSerializer.set_condition_cases(new_text, selected_node, new_condition_cases)

		DMGraphNode.Kind.MATCH:
			var match_data: Array = inspector_fields["match_case_data"]
			var match_edits: Array = inspector_fields["match_case_edits"]
			var new_match_cases: Array = []
			for i: int in match_data.size():
				var match_case: Dictionary = match_data[i].duplicate()
				if match_edits[i] != null:
					match_case.expression = match_edits[i].text
				new_match_cases.append(match_case)
			new_text = DMGraphSerializer.set_match_cases(new_text, selected_node, new_match_cases)

		DMGraphNode.Kind.WHILE:
			new_text = DMGraphSerializer.set_while_expression(
				new_text,
				selected_node,
				inspector_fields["while_expression"].text
			)

		DMGraphNode.Kind.RANDOM:
			var random_data: Array = inspector_fields["random_branch_data"]
			var random_edits: Array = inspector_fields["random_branch_edits"]
			var new_random_branches: Array = []
			for i: int in random_data.size():
				var random_branch: Dictionary = random_data[i].duplicate()
				random_branch.weight = random_edits[i].weight.text.to_float()
				random_branch.condition_text = random_edits[i].condition.text
				new_random_branches.append(random_branch)
			new_text = DMGraphSerializer.set_random_branches(new_text, selected_node, new_random_branches)

		_:
			return

	_apply_text(new_text, "Edit node")


func _parse_tags(text: String) -> PackedStringArray:
	var tags: PackedStringArray = []
	for part: String in text.split(","):
		var tag: String = part.strip_edges()
		if tag.begins_with("#"):
			tag = tag.substr(1)
		if not tag.is_empty():
			tags.append(tag)
	return tags


func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, _to_port: int) -> void:
	if document == null:
		return

	var from_id: String = _node_id_from_name(String(from_node))
	var to_id: String = _node_id_from_name(String(to_node))
	if from_id.is_empty() or to_id.is_empty():
		return

	var from_graph_node: DMGraphNode = document.get_node(from_id)
	var to_graph_node: DMGraphNode = document.get_node(to_id)
	if from_graph_node == null or to_graph_node == null:
		return

	var from_view: DMGraphNodeView = node_views.get(from_id, null)
	if from_view != null:
		var model_port: int = from_port - from_view.get_port_slot_offset()
		var has_return_port: bool = from_graph_node.get_property("goto_is_snippet", false) \
			or from_graph_node.get_property("is_snippet", false)
		if has_return_port and model_port == from_graph_node.ports.size() - 1:
			_set_status("Connect from the main output port, not the return port.")
			return

	var target: String = ""
	var cue_to_insert: String = ""
	var target_node: DMGraphNode = to_graph_node

	if to_graph_node.kind == DMGraphNode.Kind.CUE:
		target = to_graph_node.get_property("cue", "")
	elif to_graph_node.kind == DMGraphNode.Kind.JUMP and to_graph_node.get_property("target", "") in ["END", "END!"]:
		target = to_graph_node.get_property("target", "")
	else:
		var cue_info: Dictionary = _cue_for_node(to_graph_node)
		if cue_info.is_empty():
			_set_status("Connect to a top-level node, cue, or END node.")
			return
		target = cue_info.get("cue", "")
		cue_to_insert = cue_info.get("insert", "")

	if target.is_empty():
		return

	_apply_connection_to_target(from_graph_node, target, cue_to_insert, target_node)


func _apply_connection_to_target(
	from_graph_node: DMGraphNode,
	target: String,
	cue_to_insert: String,
	target_node: DMGraphNode
) -> void:
	var new_text: String = document.text

	if not cue_to_insert.is_empty():
		new_text = DMGraphSerializer.add_cue_before(new_text, target_node, cue_to_insert)
		var working_doc: DMGraphDocument = DMGraphBuilder.build(new_text, current_path)
		var working_source: DMGraphNode = _find_node_by_stable_key(
			working_doc,
			from_graph_node.stable_key,
			from_graph_node.source_start
		)
		if working_source == null:
			_set_status("Could not find the source node after adding a cue.")
			return
		from_graph_node = working_source

	if from_graph_node.kind in [DMGraphNode.Kind.DIALOGUE, DMGraphNode.Kind.RESPONSE]:
		new_text = DMGraphSerializer.set_inline_goto(
			new_text,
			from_graph_node,
			target,
			from_graph_node.get_property("goto_is_snippet", false)
		)
	elif from_graph_node.kind == DMGraphNode.Kind.JUMP:
		var raw_text: String = from_graph_node.get_property("raw_text", "")
		if raw_text.strip_edges().begins_with("%"):
			new_text = DMGraphSerializer.set_inline_goto(
				new_text,
				from_graph_node,
				target,
				from_graph_node.get_property("is_snippet", false)
			)
		else:
			new_text = DMGraphSerializer.set_jump_target(
				new_text,
				from_graph_node,
				target,
				from_graph_node.get_property("is_snippet", false)
			)
	elif from_graph_node.kind in [DMGraphNode.Kind.CUE, DMGraphNode.Kind.MUTATION, DMGraphNode.Kind.COMMENT]:
		new_text = DMGraphSerializer.add_jump_after(new_text, from_graph_node, target, false)
	else:
		_set_status("Connect from a dialogue, response, jump, cue, mutation, or comment node.")
		return

	_apply_text(new_text, "Connect to node")


func _cue_for_node(target_node: DMGraphNode) -> Dictionary:
	if target_node == null or target_node.source_start < 0:
		return {}
	if target_node.indent > 0:
		return {}
	if target_node.kind in [
		DMGraphNode.Kind.RESPONSE,
		DMGraphNode.Kind.CHOICES,
		DMGraphNode.Kind.IMPORT,
		DMGraphNode.Kind.USING,
		DMGraphNode.Kind.NOTE,
		DMGraphNode.Kind.CONCURRENT
	]:
		return {}

	for cue_name: String in document.cues:
		var cue_node: DMGraphNode = document.get_node(document.cues[cue_name])
		if cue_node == null:
			continue
		var next_id: String = cue_node.get_property("next_id", "")
		var next_node_id: String = ""
		if document.response_groups.has(next_id):
			next_node_id = document.response_groups[next_id]
		else:
			next_node_id = document.line_nodes.get(next_id, "")
		if next_node_id == target_node.id:
			return { cue = cue_name, insert = "" }

	var base: String = "goto_" + _sanitize_cue_name(target_node.id)
	var cue_name: String = base
	var counter: int = 1
	while document.cues.has(cue_name):
		cue_name = "%s_%d" % [base, counter]
		counter += 1

	return { cue = cue_name, insert = cue_name }


func _sanitize_cue_name(value: String) -> String:
	var regex: RegEx = RegEx.create_from_string("[^a-zA-Z0-9_]")
	var result: String = regex.sub(value, "_", true)
	if result.is_empty():
		result = "node"
	if result[0].is_valid_int():
		result = "n_" + result
	return result


func _find_node_by_stable_key(
	doc: DMGraphDocument,
	stable_key: String,
	source_start_hint: int = -1
) -> DMGraphNode:
	var best: DMGraphNode = null
	var best_distance: int = 999999

	for node: DMGraphNode in doc.nodes.values():
		if node.stable_key != stable_key:
			continue
		if source_start_hint < 0:
			return node
		var distance: int = abs(node.source_start - source_start_hint)
		if distance < best_distance:
			best_distance = distance
			best = node

	return best


func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if document == null:
		return

	var from_id: String = _node_id_from_name(String(from_node))
	var to_id: String = _node_id_from_name(String(to_node))
	if from_id.is_empty() or to_id.is_empty():
		return

	var from_view: DMGraphNodeView = node_views.get(from_id, null)
	if from_view == null:
		return

	var model_port: int = from_port - from_view.get_port_slot_offset()
	var matching_edge: DMGraphEdge = null
	for edge: DMGraphEdge in document.edges:
		if edge.from_node == from_id \
			and edge.from_port == model_port \
			and edge.to_node == to_id \
			and edge.to_port == to_port:
			matching_edge = edge
			break

	if matching_edge == null:
		return

	var from_graph_node: DMGraphNode = document.get_node(from_id)
	var to_graph_node: DMGraphNode = document.get_node(to_id)
	if from_graph_node == null or to_graph_node == null:
		return

	var new_text: String = document.text

	match matching_edge.kind:
		DMGraphEdge.Kind.JUMP:
			if from_graph_node.kind in [DMGraphNode.Kind.DIALOGUE, DMGraphNode.Kind.RESPONSE]:
				new_text = DMGraphSerializer.clear_inline_goto(new_text, from_graph_node)
			elif from_graph_node.kind == DMGraphNode.Kind.JUMP:
				var jump_raw: String = from_graph_node.get_property("raw_text", "")
				if jump_raw.strip_edges().begins_with("%"):
					new_text = DMGraphSerializer.set_inline_goto(new_text, from_graph_node, "END", false)
				else:
					new_text = DMGraphSerializer.set_jump_target(new_text, from_graph_node, "END", false)
			else:
				_set_status("This connection cannot be disconnected here.")
				return

		DMGraphEdge.Kind.RETURN:
			var while_line_id: String = ""
			if to_graph_node.kind == DMGraphNode.Kind.WHILE:
				while_line_id = to_graph_node.get_property("line_id", "")

			if not while_line_id.is_empty() and from_graph_node.get_property("next_id", "") == while_line_id:
				new_text = DMGraphSerializer.add_jump_after(new_text, from_graph_node, "END", false)
			elif from_graph_node.kind in [DMGraphNode.Kind.DIALOGUE, DMGraphNode.Kind.RESPONSE]:
				new_text = DMGraphSerializer.clear_inline_goto(new_text, from_graph_node)
			elif from_graph_node.kind == DMGraphNode.Kind.JUMP:
				var return_raw: String = from_graph_node.get_property("raw_text", "")
				if return_raw.strip_edges().begins_with("%"):
					new_text = DMGraphSerializer.set_inline_goto(new_text, from_graph_node, "END", false)
				else:
					new_text = DMGraphSerializer.set_jump_target(new_text, from_graph_node, "END", false)
			else:
				_set_status("This return connection cannot be disconnected here.")
				return

		DMGraphEdge.Kind.FLOW:
			var main_port: int = 0
			if from_graph_node.kind in [
				DMGraphNode.Kind.CHOICES,
				DMGraphNode.Kind.CONDITION,
				DMGraphNode.Kind.MATCH,
				DMGraphNode.Kind.RANDOM
			]:
				main_port = from_graph_node.ports.size() - 1
			elif from_graph_node.kind == DMGraphNode.Kind.WHILE:
				main_port = 1

			if matching_edge.from_port != main_port:
				_set_status("Only the main continuation can be disconnected.")
				return

			new_text = DMGraphSerializer.add_jump_after(new_text, from_graph_node, "END", false)

		_:
			_set_status("This connection cannot be disconnected here.")
			return

	_apply_text(new_text, "Disconnect")


func _on_node_selected(node: Node) -> void:
	if node is DMGraphNodeView:
		selected_node = node.graph_node
		_build_inspector()
		node_selected.emit(selected_node)


func _on_node_deselected(_node: Node) -> void:
	pass


func _on_popup_request(at_position: Vector2) -> void:
	popup_position = at_position
	var menu: PopupMenu = PopupMenu.new()
	menu.add_item("Add dialogue", 0)
	menu.add_item("Add response", 1)
	menu.add_item("Add cue", 2)
	menu.add_item("Add jump", 3)
	menu.add_item("Add mutation", 4)
	menu.add_item("Add comment", 5)
	menu.add_separator()
	menu.add_item("Delete selected", 100)
	menu.id_pressed.connect(_on_popup_menu_id_pressed)
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.position = Vector2i(graph_edit.get_screen_position() + at_position)
	menu.popup()


func _on_popup_menu_id_pressed(id: int) -> void:
	if id == 100:
		_on_delete_selected_pressed()
	else:
		_on_add_node_pressed(id)


func _on_delete_selected_pressed() -> void:
	if selected_node == null or document == null:
		return
	var new_text: String = DMGraphSerializer.delete_node(document.text, selected_node)
	_apply_text(new_text, "Delete node")


func _on_delete_nodes_request(nodes: Array) -> void:
	if document == null:
		return

	var graph_nodes: Array[DMGraphNode] = []
	for node_name: Variant in nodes:
		var node_id: String = _node_id_from_name(String(node_name))
		if node_id.is_empty():
			continue
		var graph_node: DMGraphNode = document.get_node(node_id)
		if graph_node != null:
			graph_nodes.append(graph_node)

	var filtered: Array[DMGraphNode] = []
	for graph_node: DMGraphNode in graph_nodes:
		var is_contained: bool = false
		for other: DMGraphNode in graph_nodes:
			if other == graph_node:
				continue
			if other.source_start <= graph_node.source_start and graph_node.source_end <= other.source_end:
				is_contained = true
				break
		if not is_contained:
			filtered.append(graph_node)
	graph_nodes = filtered

	graph_nodes.sort_custom(func(a: DMGraphNode, b: DMGraphNode) -> bool:
		return a.source_start > b.source_start
	)

	var new_text: String = document.text
	for graph_node: DMGraphNode in graph_nodes:
		new_text = DMGraphSerializer.delete_node(new_text, graph_node)
	_apply_text(new_text, "Delete nodes")


func _on_end_node_move() -> void:
	if is_building or document == null:
		return

	for node_id: String in node_views:
		var view: DMGraphNodeView = node_views[node_id]
		var graph_node: DMGraphNode = document.get_node(node_id)
		if graph_node != null:
			graph_node.position = view.position_offset
			graph_node.size = view.size

	_save_layout()


func _on_add_node_pressed(kind: int) -> void:
	if document == null:
		return
	if kind != 2 and (selected_node == null or selected_node.source_start < 0):
		_set_status("Select a node with a source line first.")
		return

	if kind == 1 and selected_node.kind not in [DMGraphNode.Kind.DIALOGUE, DMGraphNode.Kind.CHOICES, DMGraphNode.Kind.RESPONSE]:
		_set_status("Select a dialogue, choices, or response node to add a response.")
		return

	var new_text: String = document.text
	match kind:
		0:
			new_text = DMGraphSerializer.add_dialogue_after(new_text, selected_node, "Nathan", "New dialogue")
		1:
			new_text = DMGraphSerializer.add_response_after(new_text, selected_node, "New response")
		2:
			new_text = DMGraphSerializer.add_cue(new_text, "new_cue")
		3:
			new_text = DMGraphSerializer.add_jump_after(new_text, selected_node, "END", false)
		4:
			new_text = DMGraphSerializer.add_mutation_after(new_text, selected_node, "debug(\"mutation\")", true)
		5:
			new_text = DMGraphSerializer.add_comment_after(new_text, selected_node, "Comment")
		_:
			return

	_apply_text(new_text, "Add node")


func _on_auto_layout_pressed() -> void:
	if is_instance_valid(graph_edit):
		_arrange_graph()
		_on_end_node_move()


func _on_test_pressed() -> void:
	if selected_node == null or selected_node.source_start < 0:
		return
	if selected_node.kind == DMGraphNode.Kind.CUE:
		test_requested.emit(selected_node.get_property("cue", ""))
	else:
		test_requested.emit(str(selected_node.source_start + 1))


func _open_localization_panel() -> void:
	if document == null:
		return

	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "Localization"
	dialog.min_size = Vector2i(800, 500)
	dialog.ok_button_text = "Close"
	dialog.confirmed.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 8
	vbox.offset_top = 8
	vbox.offset_right = -8
	vbox.offset_bottom = -52
	dialog.add_child(vbox)

	var tree: Tree = Tree.new()
	tree.columns = 5
	tree.column_titles_visible = true
	tree.set_column_title(0, "Static ID")
	tree.set_column_title(1, "Text")
	tree.set_column_title(2, "Character")
	tree.set_column_title(3, "Notes")
	tree.set_column_title(4, "Status")
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.custom_minimum_size = Vector2(700, 400)
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_selected.connect(func() -> void: _on_localization_item_selected(tree))
	vbox.add_child(tree)

	var buttons: HBoxContainer = HBoxContainer.new()
	vbox.add_child(buttons)

	var generate_button: Button = Button.new()
	generate_button.text = "Generate IDs"
	generate_button.pressed.connect(func() -> void:
		var new_text: String = DMTranslationUtilities.generate_static_line_ids_for_text(document.text, current_path)
		_apply_text(new_text, "Generate static IDs")
		_build_localization_rows(tree)
	)
	buttons.add_child(generate_button)

	var export_button: Button = Button.new()
	export_button.text = "Export CSV"
	export_button.pressed.connect(func() -> void:
		var csv_dialog: ConfirmationDialog = EXPORT_TO_CSV_DIALOG.instantiate() as ConfirmationDialog
		add_child(csv_dialog)
		csv_dialog.popup_centered()
	)
	buttons.add_child(export_button)

	var refresh_button: Button = Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(func() -> void: _build_localization_rows(tree))
	buttons.add_child(refresh_button)

	add_child(dialog)
	_build_localization_rows(tree)
	dialog.popup_centered()


func _build_localization_rows(tree: Tree) -> void:
	if not is_instance_valid(tree) or document == null:
		return

	tree.clear()
	var root: TreeItem = tree.create_item()
	var id_counts: Dictionary = {}

	for node: DMGraphNode in document.nodes.values():
		if node.kind not in [DMGraphNode.Kind.DIALOGUE, DMGraphNode.Kind.RESPONSE]:
			continue
		var static_id: String = node.get_property("static_id", "")
		if not static_id.is_empty():
			id_counts[static_id] = id_counts.get(static_id, 0) + 1

	for node: DMGraphNode in document.nodes.values():
		if node.kind not in [DMGraphNode.Kind.DIALOGUE, DMGraphNode.Kind.RESPONSE]:
			continue

		var item: TreeItem = tree.create_item(root)
		var static_id: String = node.get_property("static_id", "")
		var text: String = node.get_property("text", "").replace("\n", " ")
		var character: String = node.get_property("character", "")
		var notes: String = node.get_property("notes", "").replace("\n", " ")

		var status: String = "OK"
		var color: Color = Color(0.6, 0.8, 0.6)
		if static_id.is_empty():
			status = "Missing ID"
			color = Color(1.0, 0.8, 0.4)
		elif id_counts.get(static_id, 0) > 1:
			status = "Duplicate ID"
			color = Color(1.0, 0.5, 0.5)

		item.set_text(0, static_id)
		item.set_text(1, text)
		item.set_text(2, character)
		item.set_text(3, notes)
		item.set_text(4, status)
		item.set_custom_color(4, color)
		item.set_metadata(0, node.id)


func _on_localization_item_selected(tree: Tree) -> void:
	if not is_instance_valid(tree):
		return

	var selected: TreeItem = tree.get_selected()
	if selected == null:
		return

	var node_id: Variant = selected.get_metadata(0)
	if node_id is String and not node_id.is_empty():
		select_node(node_id)


func _apply_text(new_text: String, description: String) -> void:
	if document == null or new_text == document.text:
		return

	is_dirty = true
	is_syncing = true
	text_changed.emit(new_text, description)
	is_syncing = false
	is_dirty = false
	sync_from_text(new_text)


func _save_layout() -> void:
	if current_path.is_empty() or document == null:
		return
	DMGraphSidecar.save_for(current_path, document)


func _node_id_from_name(node_name: String) -> String:
	for node_id: String in node_views:
		if DMGraphNodeView.safe_name(node_id) == node_name:
			return node_id
	return ""


func _set_status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message
