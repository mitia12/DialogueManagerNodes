@tool
class_name DMGraphSerializer extends RefCounted


static func set_dialogue_properties(text: String, node: DMGraphNode, properties: Dictionary) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	var end: int = node.source_end
	if start < 0 or start >= lines.size():
		return text
	if end < start:
		end = start

	var indent: String = _line_indent(lines[start])
	var character: String = properties.get("character", node.get_property("character", ""))
	var dialogue: String = properties.get("text", node.get_property("text", ""))
	var tags: PackedStringArray = PackedStringArray(properties.get("tags", node.get_property("tags", [])))
	var static_id: String = properties.get("static_id", node.get_property("static_id", ""))
	var goto: String = properties.get("goto", node.get_property("goto", ""))
	var goto_is_snippet: bool = properties.get("goto_is_snippet", node.get_property("goto_is_snippet", false))
	var old_text: String = node.get_property("text", "")

	if end > start and dialogue == old_text:
		lines[start] = indent + _format_dialogue_line(character, dialogue, tags, static_id, goto, goto_is_snippet)
		return "\n".join(PackedStringArray(lines))

	var replacement: PackedStringArray = []
	var dialogue_lines: PackedStringArray = dialogue.split("\n")
	for i: int in dialogue_lines.size():
		if i == 0:
			replacement.append(indent + _format_dialogue_line(character, dialogue_lines[i], tags, static_id, goto, goto_is_snippet))
		else:
			replacement.append(indent + "\t" + dialogue_lines[i])
	return replace_lines(text, start, end, replacement)


static func set_response_properties(text: String, node: DMGraphNode, properties: Dictionary) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	var end: int = node.source_end
	if start < 0 or start >= lines.size():
		return text
	if end < start:
		end = start

	var indent: String = _line_indent(lines[start])
	var character: String = properties.get("character", node.get_property("character", ""))
	var prompt: String = properties.get("text", node.get_property("text", ""))
	var tags: PackedStringArray = PackedStringArray(properties.get("tags", node.get_property("tags", [])))
	var condition: String = properties.get("condition", node.get_property("condition", ""))
	var goto: String = properties.get("goto", node.get_property("goto", ""))
	var goto_is_snippet: bool = properties.get("goto_is_snippet", node.get_property("goto_is_snippet", false))
	var static_id: String = properties.get("static_id", node.get_property("static_id", ""))
	var old_text: String = node.get_property("text", "")

	if end > start and prompt == old_text:
		lines[start] = indent + _format_response_line(prompt, condition, goto, static_id, goto_is_snippet, character, tags)
		return "\n".join(PackedStringArray(lines))

	var replacement: PackedStringArray = []
	var prompt_lines: PackedStringArray = prompt.split("\n")
	for i: int in prompt_lines.size():
		if i == 0:
			replacement.append(indent + _format_response_line(prompt_lines[i], condition, goto, static_id, goto_is_snippet, character, tags))
		else:
			replacement.append(indent + "\t" + prompt_lines[i])
	return replace_lines(text, start, end, replacement)


static func set_cue_name(text: String, node: DMGraphNode, new_name: String) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	if start < 0 or start >= lines.size():
		return text

	var old_name: String = node.get_property("cue", "")
	var indent: String = _line_indent(lines[start])
	lines[start] = indent + "~ " + new_name

	if not old_name.is_empty() and old_name != new_name:
		for i: int in lines.size():
			var line: String = lines[i]
			line = line.replace("=> " + old_name, "=> " + new_name)
			line = line.replace("=>< " + old_name, "=>< " + new_name)
			lines[i] = line

	return "\n".join(PackedStringArray(lines))


static func set_jump_target(text: String, node: DMGraphNode, target: String, is_snippet: bool) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	if start < 0 or start >= lines.size():
		return text

	var indent: String = _line_indent(lines[start])
	lines[start] = indent + ("=>< " if is_snippet else "=> ") + target
	return "\n".join(PackedStringArray(lines))


static func set_inline_goto(text: String, node: DMGraphNode, target: String, is_snippet: bool) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	if start < 0 or start >= lines.size():
		return text

	var line: String = lines[start]
	var static_id: String = DMCompiler.get_static_line_id(line)
	if not static_id.is_empty():
		line = line.replace("[ID:%s]" % [static_id], "").strip_edges()

	var regex: DMCompilerRegEx = DMCompilerRegEx.new()
	var found: RegExMatch = regex.GOTO_REGEX.search(line)
	var goto_text: String = ("=>< " if is_snippet else "=> ") + target

	if found:
		line = line.substr(0, found.get_start()) + goto_text
	else:
		line = line + " " + goto_text

	if not static_id.is_empty():
		line += " [ID:%s]" % [static_id]

	lines[start] = line
	return "\n".join(PackedStringArray(lines))


static func set_comment_text(text: String, node: DMGraphNode, comment: String) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	if start < 0 or start >= lines.size():
		return text

	var indent: String = _line_indent(lines[start])
	lines[start] = indent + comment
	return "\n".join(PackedStringArray(lines))


static func set_mutation_expression(text: String, node: DMGraphNode, expression: String, is_blocking: bool) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	if start < 0 or start >= lines.size():
		return text

	var indent: String = _line_indent(lines[start])
	lines[start] = indent + ("$> " if is_blocking else "$>> ") + expression
	return "\n".join(PackedStringArray(lines))


static func add_dialogue_after(text: String, node: DMGraphNode, character: String, dialogue: String) -> String:
	var lines: Array = Array(text.split("\n"))
	var insert_at: int = node.source_end + 1
	if insert_at < 0:
		insert_at = 0
	if insert_at > lines.size():
		insert_at = lines.size()

	var indent: String = ""
	if node.source_start >= 0 and node.source_start < lines.size():
		indent = _line_indent(lines[node.source_start])

	lines.insert(insert_at, indent + _format_dialogue_line(character, dialogue, PackedStringArray(), ""))
	return "\n".join(PackedStringArray(lines))


static func add_response_after(text: String, node: DMGraphNode, prompt: String) -> String:
	var lines: Array = Array(text.split("\n"))
	var insert_at: int = node.source_end + 1
	if insert_at < 0:
		insert_at = 0
	if insert_at > lines.size():
		insert_at = lines.size()

	var indent: String = ""
	if node.source_start >= 0 and node.source_start < lines.size():
		indent = _line_indent(lines[node.source_start])

	lines.insert(insert_at, indent + "- " + prompt)
	return "\n".join(PackedStringArray(lines))


static func add_cue(text: String, cue: String) -> String:
	var lines: Array = Array(text.split("\n"))
	lines.append("~ " + cue)
	return "\n".join(PackedStringArray(lines))


static func add_jump_after(text: String, node: DMGraphNode, target: String, is_snippet: bool) -> String:
	var lines: Array = Array(text.split("\n"))
	var insert_at: int = node.source_end + 1
	if insert_at < 0:
		insert_at = 0
	if insert_at > lines.size():
		insert_at = lines.size()

	var indent: String = ""
	if node.source_start >= 0 and node.source_start < lines.size():
		indent = _line_indent(lines[node.source_start])

	lines.insert(insert_at, indent + ("=>< " if is_snippet else "=> ") + target)
	return "\n".join(PackedStringArray(lines))


static func add_mutation_after(text: String, node: DMGraphNode, expression: String, is_blocking: bool) -> String:
	var lines: Array = Array(text.split("\n"))
	var insert_at: int = node.source_end + 1
	if insert_at < 0:
		insert_at = 0
	if insert_at > lines.size():
		insert_at = lines.size()

	var indent: String = ""
	if node.source_start >= 0 and node.source_start < lines.size():
		indent = _line_indent(lines[node.source_start])

	lines.insert(insert_at, indent + ("$> " if is_blocking else "$>> ") + expression)
	return "\n".join(PackedStringArray(lines))


static func add_comment_after(text: String, node: DMGraphNode, comment: String) -> String:
	var lines: Array = Array(text.split("\n"))
	var insert_at: int = node.source_end + 1
	if insert_at < 0:
		insert_at = 0
	if insert_at > lines.size():
		insert_at = lines.size()

	var indent: String = ""
	if node.source_start >= 0 and node.source_start < lines.size():
		indent = _line_indent(lines[node.source_start])

	lines.insert(insert_at, indent + "# " + comment)
	return "\n".join(PackedStringArray(lines))


static func delete_node(text: String, node: DMGraphNode) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	var end: int = node.source_end
	if start < 0 or start >= lines.size():
		return text
	if end < start:
		end = start
	if end >= lines.size():
		end = lines.size() - 1

	var result: Array = []
	result.append_array(lines.slice(0, start))
	result.append_array(lines.slice(end + 1))
	return "\n".join(PackedStringArray(result))


static func replace_lines(text: String, start_line: int, end_line: int, replacement: PackedStringArray) -> String:
	var lines: Array = Array(text.split("\n"))
	if start_line < 0:
		start_line = 0
	if start_line > lines.size():
		start_line = lines.size()
	if end_line < start_line - 1:
		end_line = start_line - 1
	if end_line >= lines.size():
		end_line = lines.size() - 1

	var result: Array = []
	result.append_array(lines.slice(0, start_line))
	result.append_array(Array(replacement))
	result.append_array(lines.slice(end_line + 1))
	return "\n".join(PackedStringArray(result))


static func _line_indent(line: String) -> String:
	var indent: String = ""
	for i: int in line.length():
		if line[i] == "\t" or line[i] == " ":
			indent += line[i]
		else:
			break
	return indent


static func _format_dialogue_line(
	character: String,
	dialogue: String,
	tags: PackedStringArray,
	static_id: String,
	goto: String = "",
	goto_is_snippet: bool = false
) -> String:
	var line: String = dialogue
	if tags.size() > 0:
		line = "[#%s] %s" % [", ".join(tags), line]
	if not character.is_empty():
		line = "%s: %s" % [character, line]
	if not goto.is_empty():
		line += (" =>< " if goto_is_snippet else " => ") + goto
	if not static_id.is_empty():
		line += " [ID:%s]" % [static_id]
	return line


static func _format_response_line(
	prompt: String,
	condition: String,
	goto: String,
	static_id: String,
	goto_is_snippet: bool = false,
	character: String = "",
	tags: PackedStringArray = []
) -> String:
	var line: String = prompt
	if tags.size() > 0:
		line = "[#%s] %s" % [", ".join(tags), line]
	if not character.is_empty():
		line = "%s: %s" % [character, line]
	line = "- " + line
	if not condition.is_empty():
		line += " [if %s /]" % [condition]
	if not goto.is_empty():
		line += (" =>< " if goto_is_snippet else " => ") + goto
	if not static_id.is_empty():
		line += " [ID:%s]" % [static_id]
	return line
