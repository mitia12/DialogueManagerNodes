@tool
class_name DMGraphView extends Control


signal text_changed(new_text: String, description: String)
signal test_requested(from_key: String)
signal error_selected(line_number: int)
signal node_selected(node: DMGraphNode)


var document: DMGraphDocument
var is_syncing: bool = false
var is_dirty: bool = false
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

	if is_instance_valid(graph_edit):
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
	graph_edit.snap_distance = 20
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

	for child: Node in graph_edit.get_children():
		graph_edit.remove_child(child)
		child.queue_free()
	node_views.clear()

	if document == null:
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

	var has_positions: bool = false
	for node: DMGraphNode in document.nodes.values():
		if node.position != Vector2.ZERO:
			has_positions = true
			break
	if not has_positions:
		graph_edit.arrange_nodes()

	_apply_errors()


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
			_add_apply_button()

		DMGraphNode.Kind.RESPONSE:
			_add_label("Prompt")
			_add_line_edit("text", selected_node.get_property("text", ""))
			_add_label("Condition")
			_add_line_edit("condition", selected_node.get_property("condition", ""))
			_add_label("Goto")
			_add_line_edit("goto", selected_node.get_property("goto", ""))
			_add_label("Static ID")
			_add_line_edit("static_id", selected_node.get_property("static_id", ""))
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
				static_id = inspector_fields["static_id"].text
			}
			new_text = DMGraphSerializer.set_dialogue_properties(new_text, selected_node, dialogue_properties)

		DMGraphNode.Kind.RESPONSE:
			var response_properties: Dictionary = {
				text = inspector_fields["text"].text,
				condition = inspector_fields["condition"].text,
				goto = inspector_fields["goto"].text,
				static_id = inspector_fields["static_id"].text
			}
			new_text = DMGraphSerializer.set_response_properties(new_text, selected_node, response_properties)

		DMGraphNode.Kind.CUE:
			new_text = DMGraphSerializer.set_cue_name(new_text, selected_node, inspector_fields["name"].text)

		DMGraphNode.Kind.JUMP:
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


func _on_connection_request(from_node: StringName, _from_port: int, to_node: StringName, _to_port: int) -> void:
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

	var target: String = ""
	if to_graph_node.kind == DMGraphNode.Kind.CUE:
		target = to_graph_node.get_property("cue", "")
	elif to_graph_node.kind == DMGraphNode.Kind.JUMP and to_graph_node.get_property("target", "") in ["END", "END!"]:
		target = to_graph_node.get_property("target", "")
	else:
		_set_status("Only connections to cue or END nodes are supported in this version.")
		return

	var new_text: String = document.text

	if from_graph_node.kind in [DMGraphNode.Kind.DIALOGUE, DMGraphNode.Kind.RESPONSE]:
		new_text = DMGraphSerializer.set_inline_goto(
			new_text,
			from_graph_node,
			target,
			from_graph_node.get_property("goto_is_snippet", false)
		)
	elif from_graph_node.kind == DMGraphNode.Kind.JUMP:
		new_text = DMGraphSerializer.set_jump_target(
			new_text,
			from_graph_node,
			target,
			from_graph_node.get_property("is_snippet", false)
		)
	else:
		_set_status("Connect from a dialogue, response, or jump node.")
		return

	_apply_text(new_text, "Connect to cue")


func _on_disconnection_request(_from_node: StringName, _from_port: int, _to_node: StringName, _to_port: int) -> void:
	_set_status("Disconnect is not supported yet. Edit the jump target in the inspector.")


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
	menu.position = Vector2i(get_screen_position() + at_position)
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

	graph_nodes.sort_custom(func(a: DMGraphNode, b: DMGraphNode) -> bool:
		return a.source_start > b.source_start
	)

	var new_text: String = document.text
	for graph_node: DMGraphNode in graph_nodes:
		new_text = DMGraphSerializer.delete_node(new_text, graph_node)
	_apply_text(new_text, "Delete nodes")


func _on_end_node_move() -> void:
	if document == null:
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
		graph_edit.arrange_nodes()
		_on_end_node_move()


func _on_test_pressed() -> void:
	if selected_node == null or selected_node.source_start < 0:
		return
	if selected_node.kind == DMGraphNode.Kind.CUE:
		test_requested.emit(selected_node.get_property("cue", ""))
	else:
		test_requested.emit(str(selected_node.source_start + 1))


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
