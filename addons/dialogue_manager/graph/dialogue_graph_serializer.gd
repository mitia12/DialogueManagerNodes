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


static func set_condition_cases(text: String, _node: DMGraphNode, cases: Array) -> String:
	var lines: Array = Array(text.split("\n"))
	for i: int in cases.size():
		var case: Dictionary = cases[i]
		var source_line: int = case.get("source_line", -1)
		if source_line < 0 or source_line >= lines.size():
			continue

		var indent: String = _line_indent(lines[source_line])
		var is_else: bool = case.get("is_else", false)
		var expression: String = _clean_expression(case.get("expression", ""))

		var header: String = ""
		if is_else:
			header = "else"
		elif i == 0:
			header = "if " + expression
		else:
			header = "elif " + expression
		lines[source_line] = indent + header

	return "\n".join(PackedStringArray(lines))


static func set_match_cases(text: String, _node: DMGraphNode, cases: Array) -> String:
	var lines: Array = Array(text.split("\n"))
	for case: Dictionary in cases:
		var source_line: int = case.get("source_line", -1)
		if source_line < 0 or source_line >= lines.size():
			continue

		var indent: String = _line_indent(lines[source_line])
		var is_else: bool = case.get("is_else", false)
		var expression: String = _clean_expression(case.get("expression", ""))
		lines[source_line] = indent + ("else" if is_else else "when " + expression)

	return "\n".join(PackedStringArray(lines))


static func set_while_expression(text: String, node: DMGraphNode, expression: String) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	if start < 0 or start >= lines.size():
		return text

	var indent: String = _line_indent(lines[start])
	lines[start] = indent + "while " + _clean_expression(expression)
	return "\n".join(PackedStringArray(lines))


static func set_random_branches(text: String, _node: DMGraphNode, branches: Array) -> String:
	var lines: Array = Array(text.split("\n"))
	for branch: Dictionary in branches:
		var source_line: int = branch.get("source_line", -1)
		if source_line < 0 or source_line >= lines.size():
			continue

		var indent: String = _line_indent(lines[source_line])
		var raw_text: String = branch.get("raw_text", "").strip_edges()
		var weight: float = branch.get("weight", 1.0)
		var condition: String = branch.get("condition_text", "").strip_edges()
		var content: String = _random_branch_content(raw_text)

		var prefix: String = "%"
		if weight != 1.0:
			prefix += _format_weight(weight)
		if not condition.is_empty():
			prefix += " [if %s /]" % [condition]
		if not content.is_empty():
			prefix += " " + content

		lines[source_line] = indent + prefix

	return "\n".join(PackedStringArray(lines))


static func _format_weight(weight: float) -> String:
	if is_equal_approx(weight, round(weight)):
		return str(int(round(weight)))
	return str(weight)


static func _clean_expression(expression: String) -> String:
	var cleaned: String = expression.strip_edges()
	if cleaned.ends_with(":"):
		cleaned = cleaned.substr(0, cleaned.length() - 1).strip_edges()
	return cleaned


static func _random_branch_content(raw_text: String) -> String:
	var regex: DMCompilerRegEx = DMCompilerRegEx.new()
	var found: RegExMatch = regex.WEIGHTED_RANDOM_SIBLINGS_REGEX.search(raw_text + " ")
	if found:
		return (raw_text + " ").substr(found.get_end()).strip_edges()
	return raw_text.substr(1).strip_edges() if raw_text.begins_with("%") else raw_text


static func add_condition_case(text: String, node: DMGraphNode, expression: String, is_else: bool) -> String:
	var cases: Array = Array(node.get_property("cases", []))
	if is_else:
		for case: Dictionary in cases:
			if case.get("is_else", false):
				return text

	var lines: Array = Array(text.split("\n"))
	var indent: String = ""
	if not cases.is_empty():
		var first_source: int = cases[0].get("source_line", node.source_start)
		if first_source >= 0 and first_source < lines.size():
			indent = _line_indent(lines[first_source])

	var insert_at: int = node.source_end + 1
	if not is_else:
		for case: Dictionary in cases:
			if case.get("is_else", false):
				var else_source: int = case.get("source_line", -1)
				if else_source >= 0:
					insert_at = else_source
				break

	var header: String = indent + ("else" if is_else else "elif " + _clean_expression(expression))
	var child: String = indent + "\tNathan: New branch"
	return insert_lines(text, insert_at, PackedStringArray([header, child]))


static func remove_condition_case(text: String, node: DMGraphNode, case_index: int) -> String:
	var cases: Array = Array(node.get_property("cases", []))
	if case_index <= 0 or case_index >= cases.size():
		return text

	var case: Dictionary = cases[case_index]
	var source_line: int = case.get("source_line", -1)
	var block_end: int = case.get("block_end", source_line)
	if source_line < 0:
		return text
	if block_end < source_line:
		block_end = source_line
	return delete_lines(text, source_line, block_end)


static func add_match_case(text: String, node: DMGraphNode, expression: String, is_else: bool) -> String:
	var cases: Array = Array(node.get_property("cases", []))
	if is_else:
		for case: Dictionary in cases:
			if case.get("is_else", false):
				return text

	var lines: Array = Array(text.split("\n"))
	var indent: String = ""
	if not cases.is_empty():
		var first_source: int = cases[0].get("source_line", node.source_start)
		if first_source >= 0 and first_source < lines.size():
			indent = _line_indent(lines[first_source])

	var insert_at: int = node.source_end + 1
	if not is_else:
		for case: Dictionary in cases:
			if case.get("is_else", false):
				var else_source: int = case.get("source_line", -1)
				if else_source >= 0:
					insert_at = else_source
				break

	var header: String = indent + ("else" if is_else else "when " + _clean_expression(expression))
	var child: String = indent + "\tNathan: New branch"
	return insert_lines(text, insert_at, PackedStringArray([header, child]))


static func remove_match_case(text: String, node: DMGraphNode, case_index: int) -> String:
	var cases: Array = Array(node.get_property("cases", []))
	if case_index < 0 or case_index >= cases.size() or cases.size() <= 1:
		return text

	var case: Dictionary = cases[case_index]
	var source_line: int = case.get("source_line", -1)
	var block_end: int = case.get("block_end", source_line)
	if source_line < 0:
		return text
	if block_end < source_line:
		block_end = source_line
	return delete_lines(text, source_line, block_end)


static func add_random_branch(text: String, node: DMGraphNode, weight: float, condition: String) -> String:
	var branches: Array = Array(node.get_property("branches", []))
	var lines: Array = Array(text.split("\n"))
	var indent: String = ""
	if not branches.is_empty():
		var first_source: int = branches[0].get("source_line", node.source_start)
		if first_source >= 0 and first_source < lines.size():
			indent = _line_indent(lines[first_source])

	var insert_at: int = node.source_end + 1
	var prefix: String = "%"
	if weight != 1.0:
		prefix += _format_weight(weight)
	if not condition.is_empty():
		prefix += " [if %s /]" % [condition]

	var header: String = indent + prefix
	var child: String = indent + "\tNathan: New branch"
	return insert_lines(text, insert_at, PackedStringArray([header, child]))


static func remove_random_branch(text: String, node: DMGraphNode, branch_index: int) -> String:
	var branches: Array = Array(node.get_property("branches", []))
	if branch_index < 0 or branch_index >= branches.size() or branches.size() <= 1:
		return text

	var branch: Dictionary = branches[branch_index]
	var source_line: int = branch.get("source_line", -1)
	var block_end: int = branch.get("block_end", source_line)
	if source_line < 0:
		return text
	if block_end < source_line:
		block_end = source_line
	return delete_lines(text, source_line, block_end)


static func insert_lines(text: String, at: int, new_lines: PackedStringArray) -> String:
	var lines: Array = Array(text.split("\n"))
	if at < 0:
		at = 0
	if at > lines.size():
		at = lines.size()

	var result: Array = []
	result.append_array(lines.slice(0, at))
	result.append_array(Array(new_lines))
	result.append_array(lines.slice(at))
	return "\n".join(PackedStringArray(result))


static func delete_lines(text: String, start_line: int, end_line: int) -> String:
	var lines: Array = Array(text.split("\n"))
	if start_line < 0 or start_line >= lines.size():
		return text
	if end_line < start_line:
		end_line = start_line
	if end_line >= lines.size():
		end_line = lines.size() - 1

	var result: Array = []
	result.append_array(lines.slice(0, start_line))
	result.append_array(lines.slice(end_line + 1))
	return "\n".join(PackedStringArray(result))


static func set_comment_text(text: String, node: DMGraphNode, comment: String) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	if start < 0 or start >= lines.size():
		return text

	var indent: String = _line_indent(lines[start])
	lines[start] = indent + comment
	return "\n".join(PackedStringArray(lines))


static func clear_inline_goto(text: String, node: DMGraphNode) -> String:
	var lines: Array = Array(text.split("\n"))
	var start: int = node.source_start
	if start < 0 or start >= lines.size():
		return text

	var line: String = lines[start]
	var regex: DMCompilerRegEx = DMCompilerRegEx.new()
	var found: RegExMatch = regex.GOTO_REGEX.search(line)
	if found == null:
		return text

	var static_id: String = DMCompiler.get_static_line_id(line)
	if not static_id.is_empty():
		line = line.replace("[ID:%s]" % [static_id], "").strip_edges()

	line = line.substr(0, found.get_start()).strip_edges()
	if not static_id.is_empty():
		line += " [ID:%s]" % [static_id]

	lines[start] = line
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


static func add_cue_before(text: String, node: DMGraphNode, cue: String) -> String:
	var lines: Array = Array(text.split("\n"))
	var insert_at: int = node.source_start
	if insert_at < 0:
		return text
	if insert_at > lines.size():
		insert_at = lines.size()
	lines.insert(insert_at, "~ " + cue)
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
