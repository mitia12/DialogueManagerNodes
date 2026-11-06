@tool
class_name DMGraphNodeView extends GraphNode


signal property_changed(node: DMGraphNode, key: String, value: Variant)


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
	_apply_kind_color()

	match node.kind:
		DMGraphNode.Kind.CUE:
			var cue_content: HBoxContainer = HBoxContainer.new()
			cue_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if node.get_property("is_first", false):
				var first_label: Label = Label.new()
				first_label.text = "★"
				first_label.tooltip_text = "First cue"
				cue_content.add_child(first_label)
			var cue_edit: LineEdit = _create_property_line_edit("cue", str(node.get_property("cue", "")))
			cue_content.add_child(cue_edit)
			_add_control_row(cue_content, true, true, color)

		DMGraphNode.Kind.DIALOGUE:
			var character: String = node.get_property("character", "")
			var text: String = node.get_property("text", "")
			var dialogue_content: VBoxContainer = VBoxContainer.new()
			dialogue_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			dialogue_content.add_child(_create_character_picker(character))
			dialogue_content.add_child(_create_dialogue_text_edit(text, character))
			_add_control_row(dialogue_content, true, true, color)
			if node.get_property("goto_is_snippet", false):
				_add_port_row("Return", false, true, Color(0.8, 0.6, 0.2))
			_add_goto_label(node)

		DMGraphNode.Kind.RESPONSE:
			var response_character: String = node.get_property("character", "")
			var response_text: String = node.get_property("text", "")
			var response_content: VBoxContainer = VBoxContainer.new()
			response_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			response_content.add_child(_create_character_picker(response_character))
			response_content.add_child(_create_property_line_edit("text", response_text, response_character))
			_add_control_row(response_content, true, true, color)
			if node.get_property("goto_is_snippet", false):
				_add_port_row("Return", false, true, Color(0.8, 0.6, 0.2))
			_add_goto_label(node)

		DMGraphNode.Kind.CHOICES:
			_add_port_row("Choices", true, false, color)
			for port: Dictionary in node.ports:
				_add_port_row(_short(port.get("name", "")), false, true, color)

		DMGraphNode.Kind.CONDITION:
			var cases: Array = Array(node.get_property("cases", []))
			_add_port_row("Condition", true, false, color)
			for i: int in cases.size():
				var condition_case: Dictionary = cases[i]
				if condition_case.get("is_else", false):
					_add_port_row("else", false, true, color)
				else:
					_add_control_row(
						_create_keyword_editor(
							"if" if i == 0 else "elif",
							"condition_case:%d" % [i],
							str(condition_case.get("expression", ""))
						),
						false,
						true,
						color
					)
			_add_port_row("After", false, true, color)

		DMGraphNode.Kind.MATCH:
			var match_cases: Array = Array(node.get_property("cases", []))
			_add_port_row("Match", true, false, color)
			for i: int in match_cases.size():
				var match_case: Dictionary = match_cases[i]
				if match_case.get("is_else", false):
					_add_port_row("else", false, true, color)
				else:
					_add_control_row(
						_create_keyword_editor(
							"when",
							"match_case:%d" % [i],
							str(match_case.get("expression", ""))
						),
						false,
						true,
						color
					)
			_add_port_row("After", false, true, color)

		DMGraphNode.Kind.WHILE:
			_add_control_row(
				_create_property_line_edit("expression", str(node.get_property("expression", ""))),
				true,
				false,
				color
			)
			for port: Dictionary in node.ports:
				_add_port_row(_short(port.get("name", "")), false, true, color)

		DMGraphNode.Kind.MUTATION:
			_add_control_row(
				_create_property_line_edit("expression", str(node.get_property("expression", ""))),
				true,
				true,
				color
			)

		DMGraphNode.Kind.JUMP:
			_add_control_row(
				_create_property_line_edit("target", str(node.get_property("target", ""))),
				true,
				node.source_start >= 0,
				color
			)
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
			_add_control_row(
				_create_property_line_edit("text", str(node.get_property("text", ""))),
				true,
				true,
				color
			)

		DMGraphNode.Kind.NOTE:
			_add_port_row(_short(node.get_property("text", "")), false, false, color)

	set_error_state(false)
	queue_redraw()


func refresh_appearance() -> void:
	_apply_kind_color()


func _apply_kind_color() -> void:
	if graph_node == null:
		return

	var color: Color = _get_kind_color(graph_node.kind)
	var text_color: Color = DMGraphColors.get_text_color(color)
	var selected_color: Color = color.lightened(0.18)

	add_theme_stylebox_override("titlebar", _make_title_style(color))
	add_theme_stylebox_override("titlebar_selected", _make_title_style(selected_color))

	var titlebar: HBoxContainer = get_titlebar_hbox()
	if titlebar != null:
		for child: Node in titlebar.get_children():
			if child is Label:
				(child as Label).add_theme_color_override("font_color", text_color)
	queue_redraw()


func _make_title_style(color: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.border_width_bottom = 1
	style.border_color = color.darkened(0.3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


## Draw explicit connector circles for every port. Input ports are on the left
## side of the node and output ports are on the right side.
func _draw_port(_slot_index: int, position: Vector2i, _left: bool, color: Color) -> void:
	var center: Vector2 = Vector2(position)
	draw_circle(center, 6.0, color)
	draw_circle(center, 2.5, color.darkened(0.45))
	draw_arc(center, 6.0, 0, TAU, 24, Color(0, 0, 0, 0.65), 1.5, true)


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
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(200, 0)
	return _add_control_row(label, has_input, has_output, color)


func _add_control_row(content: Control, has_input: bool, has_output: bool, color: Color) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(220, 0)

	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(content)

	add_child(row)
	var slot_index: int = get_child_count() - 1
	set_slot(slot_index, has_input, 0, color, has_output, 0, color)
	return row


func _create_character_picker(character: String) -> OptionButton:
	var picker: OptionButton = OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size = Vector2(180, 0)

	picker.add_item("(Narration)")
	picker.set_item_metadata(0, "")

	var names: PackedStringArray = []
	if document != null:
		names = document.characters.duplicate()
	if not character.is_empty() and not names.has(character):
		names.append(character)

	var selected_index: int = 0
	for name: String in names:
		picker.add_item(name)
		var item_index: int = picker.item_count - 1
		picker.set_item_metadata(item_index, name)
		if name == character:
			selected_index = item_index

	picker.select(selected_index)
	_apply_character_color(picker, character)
	picker.item_selected.connect(_on_character_selected.bind(picker))
	return picker


func _on_character_selected(index: int, picker: OptionButton) -> void:
	var character: String = str(picker.get_item_metadata(index))
	_apply_character_color(picker, character)
	_commit_property("character", character)


func _apply_character_color(picker: OptionButton, character: String) -> void:
	var color: Color = DMGraphColors.get_character_color(character)
	picker.add_theme_color_override("font_color", color)
	picker.add_theme_color_override("font_hover_color", color.lightened(0.2))
	picker.add_theme_color_override("font_pressed_color", color.lightened(0.2))


func _create_property_line_edit(key: String, value: String, character: String = "") -> LineEdit:
	var edit: LineEdit = LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(180, 0)
	if not character.is_empty():
		edit.add_theme_color_override("font_color", DMGraphColors.get_character_color(character))
	edit.text_submitted.connect(_on_line_edit_submitted.bind(key, edit))
	edit.focus_exited.connect(_on_line_edit_focus_exited.bind(key, edit))
	return edit


func _create_keyword_editor(keyword: String, key: String, value: String) -> HBoxContainer:
	var content: HBoxContainer = HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var keyword_label: Label = Label.new()
	keyword_label.text = keyword
	keyword_label.custom_minimum_size = Vector2(42, 0)
	content.add_child(keyword_label)
	content.add_child(_create_property_line_edit(key, value))
	return content


func _on_line_edit_submitted(_text: String, key: String, edit: LineEdit) -> void:
	_commit_property(key, edit.text)


func _on_line_edit_focus_exited(key: String, edit: LineEdit) -> void:
	_commit_property(key, edit.text)


func _create_dialogue_text_edit(text: String, character: String) -> TextEdit:
	var edit: TextEdit = TextEdit.new()
	edit.text = text
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.scroll_fit_content_height = true
	edit.custom_minimum_size = Vector2(180, 40)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not character.is_empty():
		edit.add_theme_color_override("font_color", DMGraphColors.get_character_color(character))
	edit.focus_exited.connect(_on_text_edit_focus_exited.bind(edit))
	edit.gui_input.connect(_on_text_edit_gui_input.bind(edit))
	return edit


func _on_text_edit_focus_exited(edit: TextEdit) -> void:
	_commit_property("text", edit.text.strip_edges())


func _on_text_edit_gui_input(event: InputEvent, edit: TextEdit) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ENTER and key_event.keycode != KEY_KP_ENTER:
		return
	if not key_event.ctrl_pressed and not key_event.meta_pressed:
		return

	_commit_property("text", edit.text.strip_edges())
	edit.release_focus()
	edit.accept_event()


func _commit_property(key: String, value: Variant) -> void:
	if graph_node == null:
		return
	if graph_node.get_property(key, "") == value:
		return
	property_changed.emit(graph_node, key, value)


func _get_kind_color(kind: DMGraphNode.Kind) -> Color:
	return DMGraphColors.get_color(kind)


func _get_kind_title(kind: DMGraphNode.Kind) -> String:
	return DMGraphColors.get_kind_name(kind)


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
