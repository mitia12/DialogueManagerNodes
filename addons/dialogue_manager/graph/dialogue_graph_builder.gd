@tool
class_name DMGraphBuilder extends RefCounted


static func build(text: String, path: String) -> DMGraphDocument:
	var doc: DMGraphDocument = DMGraphDocument.new()
	doc.path = path
	doc.text = text
	doc.source_lines = text.split("\n")

	var result: DMCompilerResult = DMCompiler.compile_string(text, path)
	doc.errors = result.errors
	doc.using_states = result.using_states
	doc.characters = result.character_names.duplicate()
	doc.imports = _extract_imports(doc.source_lines)

	_build_file_nodes(doc, result)
	_build_cue_nodes(doc, result)
	_build_line_nodes(doc, result)
	_build_edges(doc, result)

	return doc


static func _extract_imports(lines: PackedStringArray) -> Array[Dictionary]:
	var imports: Array[Dictionary] = []
	var regex: DMCompilerRegEx = DMCompilerRegEx.new()
	for i: int in lines.size():
		var line: String = lines[i].strip_edges()
		if not line.begins_with("import "):
			continue
		var found: RegExMatch = regex.IMPORT_REGEX.search(line)
		if found:
			imports.append({
				path = found.strings[found.names.path],
				alias = found.strings[found.names.prefix],
				line = i
			})
	return imports


static func _build_file_nodes(doc: DMGraphDocument, _result: DMCompilerResult) -> void:
	var regex: DMCompilerRegEx = DMCompilerRegEx.new()

	for i: int in doc.source_lines.size():
		var raw_line: String = doc.source_lines[i]
		var line: String = raw_line.strip_edges()

		if line.begins_with("import "):
			var found: RegExMatch = regex.IMPORT_REGEX.search(line)
			if found:
				var import_path: String = found.strings[found.names.path]
				var alias: String = found.strings[found.names.prefix]
				var import_node: DMGraphNode = DMGraphNode.new("import:%d" % [i], DMGraphNode.Kind.IMPORT)
				import_node.stable_key = "import:%s" % [import_path]
				import_node.source_start = i
				import_node.source_end = i
				import_node.properties = {
					path = import_path,
					alias = alias,
					line = i
				}
				doc.add_node(import_node)

		elif line.begins_with("using "):
			var state: String = line.substr(6).strip_edges()
			var using_node: DMGraphNode = DMGraphNode.new("using:%d" % [i], DMGraphNode.Kind.USING)
			using_node.stable_key = "using:%s" % [state]
			using_node.source_start = i
			using_node.source_end = i
			using_node.properties = {
				state = state,
				line = i
			}
			doc.add_node(using_node)


static func _build_cue_nodes(doc: DMGraphDocument, result: DMCompilerResult) -> void:
	var first_cue_name: String = ""

	for cue: String in result.cues:
		# Imported cues are "alias/cue" and point at another file.
		if "/" in cue:
			continue

		var next_id: String = result.cues[cue]
		if first_cue_name.is_empty() and next_id == result.first_cue:
			first_cue_name = cue

		var source_line: int = _find_cue_line(doc.source_lines, cue)
		var cue_node: DMGraphNode = DMGraphNode.new("cue:%s" % [cue], DMGraphNode.Kind.CUE)
		cue_node.stable_key = "cue:%s" % [cue]
		cue_node.source_start = source_line
		cue_node.source_end = source_line
		cue_node.indent = 0
		cue_node.properties = {
			cue = cue,
			next_id = next_id,
			is_first = false
		}
		cue_node.add_port("out", "flow", Color(0.35, 0.65, 1.0))
		doc.add_node(cue_node)
		doc.cues[cue] = cue_node.id

	if first_cue_name.is_empty() and not result.cues.is_empty():
		for cue: String in result.cues:
			if not "/" in cue:
				first_cue_name = cue
				break

	doc.first_cue = first_cue_name
	if not first_cue_name.is_empty() and doc.cues.has(first_cue_name):
		var first_node: DMGraphNode = doc.get_node(doc.cues[first_cue_name])
		if first_node != null:
			first_node.set_property("is_first", true)


static func _find_cue_line(lines: PackedStringArray, cue: String) -> int:
	for i: int in lines.size():
		var line: String = lines[i].strip_edges()
		if line.begins_with("~ "):
			if line.substr(2).strip_edges() == cue:
				return i
	return -1


static func _build_line_nodes(doc: DMGraphDocument, result: DMCompilerResult) -> void:
	var line_ids: Array = result.lines.keys()
	line_ids.sort_custom(func(a: String, b: String) -> bool:
		return _source_line_for_id(a) < _source_line_for_id(b)
	)

	var response_group_first: Dictionary = {}
	var concurrent_ids: Dictionary = {}

	for line_id: String in line_ids:
		var line: Dictionary = result.lines[line_id]
		var line_type: String = line.get("type", "")

		if line_type == DMConstants.TYPE_RESPONSE:
			var responses: Array = Array(line.get("responses", []))
			if responses.size() > 0:
				response_group_first[responses[0]] = line_id

		for concurrent_id: String in Array(line.get("concurrent_lines", [])):
			concurrent_ids[concurrent_id] = true

	for line_id: String in line_ids:
		var line: Dictionary = result.lines[line_id]
		var line_type: String = line.get("type", "")
		var source_start: int = _source_line_for_id(line_id)
		if source_start < 0 or source_start >= doc.source_lines.size():
			continue

		var raw_line: String = doc.source_lines[source_start]
		var indent: int = _indent_count(raw_line)
		var source_end: int = _find_block_end(doc.source_lines, source_start, indent)
		var node_id: String = "line:%s" % [line_id]
		var stable_key: String = _stable_key(line, source_start)

		match line_type:
			DMConstants.TYPE_CUE:
				continue

			DMConstants.TYPE_COMMENT:
				var comment_node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.COMMENT)
				comment_node.stable_key = "comment:%s" % [raw_line.sha1_text()]
				comment_node.source_start = source_start
				comment_node.source_end = source_start
				comment_node.indent = indent
				comment_node.properties = {
					text = raw_line.strip_edges().trim_prefix("#").trim_prefix("#").strip_edges(),
					raw_text = raw_line,
					next_id = line.get("next_id", "")
				}
				comment_node.add_port("out", "flow", Color(0.5, 0.5, 0.5))
				doc.add_node(comment_node)
				doc.line_nodes[line_id] = comment_node.id

			DMConstants.TYPE_RESPONSE:
				var response_node: DMGraphNode = _make_response_node(
					node_id,
					stable_key,
					line,
					raw_line,
					source_start,
					source_end,
					indent,
					result
				)
				doc.add_node(response_node)
				doc.line_nodes[line_id] = response_node.id

				if response_group_first.has(line_id):
					var response_ids: Array = Array(line.get("responses", []))
					var choices_node: DMGraphNode = _make_choices_node(
						"choices:%s" % [line_id],
						"choices:%s" % [stable_key],
						line,
						response_ids,
						result,
						doc,
						source_start,
						indent
					)
					doc.add_node(choices_node)
					doc.response_groups[line_id] = choices_node.id

			DMConstants.TYPE_CONDITION:
				if raw_line.strip_edges().begins_with("if "):
					var condition_node: DMGraphNode = _make_condition_node(
						"condition:%s" % [line_id],
						"condition:%s" % [stable_key],
						line,
						result,
						doc,
						source_start,
						indent
					)
					doc.add_node(condition_node)
					doc.line_nodes[line_id] = condition_node.id

			DMConstants.TYPE_MATCH:
				var match_node: DMGraphNode = _make_match_node(
					"match:%s" % [line_id],
					"match:%s" % [stable_key],
					line,
					raw_line,
					doc,
					source_start,
					source_end,
					indent
				)
				doc.add_node(match_node)
				doc.line_nodes[line_id] = match_node.id

			DMConstants.TYPE_WHILE:
				var while_node: DMGraphNode = _make_while_node(
					"while:%s" % [line_id],
					"while:%s" % [stable_key],
					line,
					raw_line,
					source_start,
					source_end,
					indent
				)
				doc.add_node(while_node)
				doc.line_nodes[line_id] = while_node.id

			DMConstants.TYPE_MUTATION:
				var mutation_node: DMGraphNode = _make_mutation_node(node_id, stable_key, line, raw_line, source_start, source_end, indent)
				doc.add_node(mutation_node)
				doc.line_nodes[line_id] = mutation_node.id

			DMConstants.TYPE_GOTO:
				if "." in line_id:
					continue
				var goto_siblings: Array = Array(line.get("siblings", []))
				if goto_siblings.size() > 0 and goto_siblings[0].get("id", "") == line_id:
					var goto_random_node: DMGraphNode = _make_random_node(
						"random:%s" % [line_id],
						"random:%s" % [stable_key],
						line,
						goto_siblings,
						result,
						doc,
						source_start,
						indent
					)
					doc.add_node(goto_random_node)
					doc.line_nodes[line_id] = goto_random_node.id
				var jump_node: DMGraphNode = _make_jump_node(node_id, stable_key, line, raw_line, source_start, source_end, indent)
				doc.add_node(jump_node)
				if not doc.line_nodes.has(line_id):
					doc.line_nodes[line_id] = jump_node.id

			DMConstants.TYPE_RANDOM:
				var block_random_node: DMGraphNode = _make_random_node(
					"random:%s" % [line_id],
					"random:%s" % [stable_key],
					line,
					Array(line.get("siblings", [])),
					result,
					doc,
					source_start,
					indent
				)
				doc.add_node(block_random_node)
				doc.line_nodes[line_id] = block_random_node.id

			DMConstants.TYPE_DIALOGUE:
				if concurrent_ids.has(line_id):
					var concurrent_node: DMGraphNode = _make_concurrent_node(node_id, stable_key, line, raw_line, source_start, source_end, indent)
					doc.add_node(concurrent_node)
					doc.line_nodes[line_id] = concurrent_node.id
				else:
					var dialogue_siblings: Array = Array(line.get("siblings", []))
					if dialogue_siblings.size() > 0 and dialogue_siblings[0].get("id", "") == line_id:
						var dialogue_random_node: DMGraphNode = _make_random_node(
							"random:%s" % [line_id],
							"random:%s" % [stable_key],
							line,
							dialogue_siblings,
							result,
							doc,
							source_start,
							indent
						)
						doc.add_node(dialogue_random_node)
						doc.line_nodes[line_id] = dialogue_random_node.id
					var dialogue_node: DMGraphNode = _make_dialogue_node(node_id, stable_key, line, raw_line, source_start, source_end, indent, result)
					doc.add_node(dialogue_node)
					if not doc.line_nodes.has(line_id):
						doc.line_nodes[line_id] = dialogue_node.id

			_:
				continue


static func _make_dialogue_node(
	node_id: String,
	stable_key: String,
	line: Dictionary,
	raw_line: String,
	source_start: int,
	source_end: int,
	indent: int,
	result: DMCompilerResult
) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.DIALOGUE)
	node.stable_key = stable_key
	node.source_start = source_start
	node.source_end = source_end
	node.indent = indent
	var goto: String = _extract_goto(raw_line)
	node.properties = {
		character = line.get("character", ""),
		text = line.get("text", ""),
		tags = Array(line.get("tags", [])),
		static_id = line.get("static_id", ""),
		notes = line.get("notes", ""),
		concurrent_lines = Array(line.get("concurrent_lines", [])),
		next_id = line.get("next_id", ""),
		goto = goto,
		goto_is_snippet = not goto.is_empty() and "=><" in raw_line,
		raw_text = raw_line
	}

	var inline_goto_id: String = "%s.1" % [line.get("id", "")]
	if result.lines.has(inline_goto_id):
		var inline_goto: Dictionary = result.lines[inline_goto_id]
		node.set_property("next_id_after", inline_goto.get("next_id_after", ""))

	node.add_port("out", "flow", Color(0.35, 0.8, 0.45))
	if node.get_property("goto_is_snippet", false):
		node.add_port("return", "return", Color(0.8, 0.6, 0.2))
	return node


static func _make_response_node(
	node_id: String,
	stable_key: String,
	line: Dictionary,
	raw_line: String,
	source_start: int,
	source_end: int,
	indent: int,
	result: DMCompilerResult
) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.RESPONSE)
	node.stable_key = stable_key
	node.source_start = source_start
	node.source_end = source_end
	node.indent = indent
	var goto: String = _extract_goto(raw_line)
	node.properties = {
		character = line.get("character", ""),
		text = line.get("text", ""),
		tags = Array(line.get("tags", [])),
		static_id = line.get("static_id", ""),
		notes = line.get("notes", ""),
		condition = line.get("condition_as_text", ""),
		next_id = line.get("next_id", ""),
		goto = goto,
		goto_is_snippet = not goto.is_empty() and "=><" in raw_line,
		raw_text = raw_line
	}

	var inline_goto_id: String = "%s.1" % [line.get("id", "")]
	if result.lines.has(inline_goto_id):
		var inline_goto: Dictionary = result.lines[inline_goto_id]
		node.set_property("next_id_after", inline_goto.get("next_id_after", ""))

	node.add_port("out", "flow", Color(0.9, 0.75, 0.25))
	if node.get_property("goto_is_snippet", false):
		node.add_port("return", "return", Color(0.8, 0.6, 0.2))
	return node


static func _make_choices_node(
	node_id: String,
	stable_key: String,
	line: Dictionary,
	responses: Array,
	result: DMCompilerResult,
	doc: DMGraphDocument,
	source_start: int,
	indent: int
) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.CHOICES)
	node.stable_key = stable_key
	node.source_start = source_start
	node.indent = indent
	node.properties = {
		responses = responses,
		next_id_after = line.get("next_id_after", "")
	}

	var last_source: int = source_start
	for response_id: String in responses:
		var response_line: Dictionary = result.lines.get(response_id, {})
		var response_source: int = _source_line_for_id(response_id)
		if response_source >= 0:
			last_source = _find_block_end(doc.source_lines, response_source, _indent_count(doc.source_lines[response_source]))
		var response_text: String = response_line.get("text", "")
		node.add_port(response_text, "response", Color(0.9, 0.6, 0.2))

	node.source_end = last_source
	node.add_port("Continue", "continue", Color(0.5, 0.5, 0.5))
	return node


static func _make_condition_node(
	node_id: String,
	stable_key: String,
	line: Dictionary,
	result: DMCompilerResult,
	doc: DMGraphDocument,
	source_start: int,
	indent: int
) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.CONDITION)
	node.stable_key = stable_key
	node.source_start = source_start
	node.indent = indent

	var cases: Array = []
	var current_id: String = line.get("id", "")
	var last_source: int = source_start

	while not current_id.is_empty():
		var current: Dictionary = result.lines.get(current_id, {})
		if current.is_empty():
			break

		var current_source: int = _source_line_for_id(current_id)
		if current_source < 0 or current_source >= doc.source_lines.size():
			break

		var current_raw: String = doc.source_lines[current_source]
		var current_indent: int = _indent_count(current_raw)
		last_source = _find_block_end(doc.source_lines, current_source, current_indent)

		cases.append({
			expression = _extract_condition(current_raw),
			is_else = current_raw.strip_edges() == "else",
			next_id = current.get("next_id", ""),
			source_line = current_source,
			block_end = last_source
		})

		current_id = current.get("next_sibling_id", "")

	node.source_end = last_source
	node.properties = {
		cases = cases,
		next_id_after = line.get("next_id_after", "")
	}

	for case: Dictionary in cases:
		var label: String = "else" if case.get("is_else", false) else "if %s" % [case.get("expression", "")]
		node.add_port(label, "condition", Color(0.7, 0.45, 0.9))
	node.add_port("After", "after", Color(0.5, 0.5, 0.5))
	return node


static func _make_match_node(
	node_id: String,
	stable_key: String,
	line: Dictionary,
	raw_line: String,
	doc: DMGraphDocument,
	source_start: int,
	source_end: int,
	indent: int
) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.MATCH)
	node.stable_key = stable_key
	node.source_start = source_start
	node.source_end = source_end
	node.indent = indent
	var source_cases: Array = []
	for case: Dictionary in Array(line.get("cases", [])):
		var case_source: int = _find_match_case_line(doc, case, source_start, source_end)
		var case_raw: String = doc.source_lines[case_source].strip_edges() if case_source >= 0 else ""
		var case_block_end: int = -1
		if case_source >= 0:
			case_block_end = _find_block_end(
				doc.source_lines,
				case_source,
				_indent_count(doc.source_lines[case_source])
			)
		source_cases.append({
			expression = _extract_when_expression(case_raw),
			is_else = case_raw == "else",
			next_id = case.get("next_id", ""),
			source_line = case_source,
			block_end = case_block_end,
			raw_text = case_raw,
			condition = case.get("condition", {})
		})

	node.properties = {
		expression = _extract_condition(raw_line),
		cases = source_cases,
		next_id_after = line.get("next_id_after", "")
	}

	for case: Dictionary in source_cases:
		var label: String = case.get("raw_text", "")
		if label.is_empty():
			label = "else" if case.get("is_else", false) else "when"
		node.add_port(label, "case", Color(0.7, 0.45, 0.9))
	node.add_port("After", "after", Color(0.5, 0.5, 0.5))
	return node


static func _find_match_case_line(
	doc: DMGraphDocument,
	case: Dictionary,
	source_start: int,
	_source_end: int
) -> int:
	var next_id: String = case.get("next_id", "")
	var child_source: int = _source_line_for_id(next_id)
	if child_source < 0 or child_source >= doc.source_lines.size():
		return -1

	var child_indent: int = _indent_count(doc.source_lines[child_source])
	for i: int in range(child_source - 1, source_start - 1, -1):
		if i < 0 or i >= doc.source_lines.size():
			continue
		var raw_line: String = doc.source_lines[i]
		if raw_line.strip_edges().is_empty():
			continue
		if _indent_count(raw_line) >= child_indent:
			continue
		var text: String = raw_line.strip_edges()
		if text.begins_with("when ") or text == "else":
			return i

	return -1


static func _extract_when_expression(raw_line: String) -> String:
	var regex: DMCompilerRegEx = DMCompilerRegEx.new()
	var found: RegExMatch = regex.CONDITION_REGEX.search(raw_line)
	if found:
		return found.strings[found.names.expression].strip_edges()
	return ""


static func _make_while_node(
	node_id: String,
	stable_key: String,
	line: Dictionary,
	raw_line: String,
	source_start: int,
	source_end: int,
	indent: int
) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.WHILE)
	node.stable_key = stable_key
	node.source_start = source_start
	node.source_end = source_end
	node.indent = indent
	node.properties = {
		expression = _extract_condition(raw_line),
		next_id = line.get("next_id", ""),
		next_id_after = line.get("next_id_after", ""),
		line_id = line.get("id", "")
	}
	node.add_port("Body", "body", Color(0.7, 0.45, 0.9))
	node.add_port("After", "after", Color(0.5, 0.5, 0.5))
	return node


static func _make_mutation_node(
	node_id: String,
	stable_key: String,
	line: Dictionary,
	raw_line: String,
	source_start: int,
	source_end: int,
	indent: int
) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.MUTATION)
	node.stable_key = stable_key
	node.source_start = source_start
	node.source_end = source_end
	node.indent = indent
	var mutation: Dictionary = line.get("mutation", {})
	node.properties = {
		expression = _extract_mutation(raw_line),
		is_blocking = mutation.get("is_blocking", true),
		next_id = line.get("next_id", ""),
		raw_text = raw_line
	}
	node.add_port("out", "flow", Color(0.6, 0.6, 0.6))
	return node


static func _make_jump_node(
	node_id: String,
	stable_key: String,
	line: Dictionary,
	raw_line: String,
	source_start: int,
	source_end: int,
	indent: int
) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.JUMP)
	node.stable_key = stable_key
	node.source_start = source_start
	node.source_end = source_end
	node.indent = indent
	node.properties = {
		target = _extract_goto(raw_line),
		is_snippet = line.get("is_snippet", false),
		next_id = line.get("next_id", ""),
		next_id_after = line.get("next_id_after", ""),
		raw_text = raw_line
	}
	node.add_port("Jump", "jump", Color(0.9, 0.3, 0.3))
	if node.get_property("is_snippet", false):
		node.add_port("Return", "return", Color(0.8, 0.6, 0.2))
	return node


static func _make_random_node(
	node_id: String,
	stable_key: String,
	line: Dictionary,
	branches: Array,
	_result: DMCompilerResult,
	doc: DMGraphDocument,
	source_start: int,
	indent: int
) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.RANDOM)
	node.stable_key = stable_key
	node.source_start = source_start
	node.indent = indent

	var branch_lines: Array[int] = _find_random_branch_lines(doc, source_start, indent)
	var source_branches: Array = []
	var last_source: int = source_start

	for i: int in branches.size():
		var branch: Dictionary = branches[i]
		var branch_id: String = branch.get("id", "")
		var branch_source: int = _source_line_for_id(branch_id)
		if branch_source >= 0 and branch_source < doc.source_lines.size():
			last_source = _find_block_end(doc.source_lines, branch_source, _indent_count(doc.source_lines[branch_source]))

		var raw_line: String = ""
		var branch_line: int = branch_lines[i] if i < branch_lines.size() else -1
		if branch_line >= 0:
			raw_line = doc.source_lines[branch_line].strip_edges()

		var branch_block_end: int = -1
		if branch_line >= 0:
			branch_block_end = _find_block_end(doc.source_lines, branch_line, indent)

		source_branches.append({
			id = branch_id,
			weight = branch.get("weight", 1.0),
			condition = branch.get("condition", {}),
			condition_text = _extract_random_condition(raw_line),
			source_line = branch_line,
			block_end = branch_block_end,
			raw_text = raw_line
		})

	node.source_end = last_source
	node.properties = {
		branches = source_branches,
		next_id_after = line.get("next_id_after", "")
	}

	for branch: Dictionary in source_branches:
		var weight: float = branch.get("weight", 1.0)
		var condition_text: String = branch.get("condition_text", "")
		var label: String = "%sx" % [weight]
		if not condition_text.is_empty():
			label += " [if %s]" % [condition_text]
		node.add_port(label, "random", Color(0.2, 0.8, 0.8))

	node.add_port("After", "after", Color(0.5, 0.5, 0.5))
	return node


static func _find_random_branch_lines(doc: DMGraphDocument, source_start: int, indent: int) -> Array[int]:
	var result: Array[int] = []
	var i: int = source_start
	while i < doc.source_lines.size():
		var raw_line: String = doc.source_lines[i]
		if raw_line.strip_edges().is_empty():
			i += 1
			continue

		var line_indent: int = _indent_count(raw_line)
		if line_indent > indent:
			i += 1
			continue
		if line_indent < indent:
			break
		if not raw_line.strip_edges().begins_with("%"):
			break

		result.append(i)
		i += 1

	return result


static func _extract_random_condition(raw_line: String) -> String:
	var regex: DMCompilerRegEx = DMCompilerRegEx.new()
	var found: RegExMatch = regex.WEIGHTED_RANDOM_SIBLINGS_REGEX.search(raw_line + " ")
	if found and found.names.has("condition"):
		return found.strings[found.names.condition].strip_edges()
	return ""


static func _make_concurrent_node(
	node_id: String,
	stable_key: String,
	line: Dictionary,
	raw_line: String,
	source_start: int,
	source_end: int,
	indent: int
) -> DMGraphNode:
	var node: DMGraphNode = DMGraphNode.new(node_id, DMGraphNode.Kind.CONCURRENT)
	node.stable_key = stable_key
	node.source_start = source_start
	node.source_end = source_end
	node.indent = indent
	node.properties = {
		character = line.get("character", ""),
		text = line.get("text", ""),
		tags = Array(line.get("tags", [])),
		static_id = line.get("static_id", ""),
		notes = line.get("notes", ""),
		raw_text = raw_line
	}
	return node


static func _build_edges(doc: DMGraphDocument, _result: DMCompilerResult) -> void:
	_add_end_nodes(doc)

	for node: DMGraphNode in doc.nodes.values():
		if node.id in ["__end__", "__end_conversation__"]:
			continue

		match node.kind:
			DMGraphNode.Kind.CUE:
				_add_flow(doc, node, node.get_property("next_id", ""))

			DMGraphNode.Kind.DIALOGUE, DMGraphNode.Kind.RESPONSE:
				var goto: String = node.get_property("goto", "")
				if not goto.is_empty():
					_add_jump(doc, node, goto)
					if node.get_property("goto_is_snippet", false):
						_add_return(doc, node, node.get_property("next_id_after", ""))
				else:
					var next_id: String = node.get_property("next_id", "")
					if node.kind == DMGraphNode.Kind.RESPONSE and _target_node_id(doc, next_id).is_empty():
						next_id = node.get_property("next_id_after", "")
					_add_flow(doc, node, next_id)

			DMGraphNode.Kind.CHOICES:
				var choice_responses: Array = Array(node.get_property("responses", []))
				for i: int in choice_responses.size():
					_add_branch_to_node(doc, node, i, "line:%s" % [choice_responses[i]])
				_add_flow(doc, node, node.get_property("next_id_after", ""), node.ports.size() - 1)

			DMGraphNode.Kind.CONDITION:
				var condition_cases: Array = Array(node.get_property("cases", []))
				for i: int in condition_cases.size():
					_add_branch(doc, node, i, condition_cases[i].get("next_id", ""))
				_add_flow(doc, node, node.get_property("next_id_after", ""), node.ports.size() - 1)

			DMGraphNode.Kind.MATCH:
				var match_cases: Array = Array(node.get_property("cases", []))
				for i: int in match_cases.size():
					_add_branch(doc, node, i, match_cases[i].get("next_id", ""))
				_add_flow(doc, node, node.get_property("next_id_after", ""), node.ports.size() - 1)

			DMGraphNode.Kind.WHILE:
				_add_flow(doc, node, node.get_property("next_id", ""), 0)
				_add_flow(doc, node, node.get_property("next_id_after", ""), 1)

			DMGraphNode.Kind.MUTATION:
				_add_flow(doc, node, node.get_property("next_id", ""))

			DMGraphNode.Kind.JUMP:
				_add_jump(doc, node, node.get_property("target", ""))
				if node.get_property("is_snippet", false):
					_add_return(doc, node, node.get_property("next_id_after", ""))

			DMGraphNode.Kind.RANDOM:
				var random_branches: Array = Array(node.get_property("branches", []))
				for i: int in random_branches.size():
					_add_branch_to_node(doc, node, i, "line:%s" % [random_branches[i].get("id", "")])
				_add_flow(doc, node, node.get_property("next_id_after", ""), node.ports.size() - 1)

			DMGraphNode.Kind.COMMENT:
				_add_flow(doc, node, node.get_property("next_id", ""))

			DMGraphNode.Kind.CONCURRENT:
				pass

			_:
				pass

	# While loops: the last line of the body points back to the while line.
	for node: DMGraphNode in doc.nodes.values():
		if node.kind != DMGraphNode.Kind.WHILE:
			continue
		var while_line_id: String = node.get_property("line_id", "")
		if while_line_id.is_empty():
			continue
		for other: DMGraphNode in doc.nodes.values():
			if other.id == node.id:
				continue
			var next_id: String = other.get_property("next_id", "")
			var next_id_after: String = other.get_property("next_id_after", "")
			if next_id == while_line_id:
				_add_edge_if_missing(doc, DMGraphEdge.new(other.id, _get_flow_port(other), node.id, 0, DMGraphEdge.Kind.RETURN, "loop"))
			elif next_id_after == while_line_id:
				_add_edge_if_missing(doc, DMGraphEdge.new(other.id, _get_return_port(other), node.id, 0, DMGraphEdge.Kind.RETURN, "loop"))

	# Concurrent lines are attached to their origin dialogue line.
	for node: DMGraphNode in doc.nodes.values():
		if node.kind != DMGraphNode.Kind.DIALOGUE:
			continue
		for concurrent_id: String in Array(node.get_property("concurrent_lines", [])):
			var target_id: String = _target_node_id(doc, concurrent_id)
			if not target_id.is_empty():
				_add_edge_if_missing(doc, DMGraphEdge.new(node.id, 0, target_id, 0, DMGraphEdge.Kind.CONCURRENT, "concurrent"))


static func _add_end_nodes(doc: DMGraphDocument) -> void:
	var end_node: DMGraphNode = DMGraphNode.new("__end__", DMGraphNode.Kind.JUMP)
	end_node.stable_key = "end"
	end_node.properties = {
		target = "END",
		is_snippet = false,
		next_id = "",
		next_id_after = ""
	}
	end_node.add_port("Jump", "jump", Color(0.9, 0.3, 0.3))
	doc.add_node(end_node)

	var end_conversation_node: DMGraphNode = DMGraphNode.new("__end_conversation__", DMGraphNode.Kind.JUMP)
	end_conversation_node.stable_key = "end!"
	end_conversation_node.properties = {
		target = "END!",
		is_snippet = false,
		next_id = "",
		next_id_after = ""
	}
	end_conversation_node.add_port("Jump", "jump", Color(0.9, 0.3, 0.3))
	doc.add_node(end_conversation_node)


static func _get_flow_port(node: DMGraphNode) -> int:
	match node.kind:
		DMGraphNode.Kind.CHOICES, DMGraphNode.Kind.CONDITION, DMGraphNode.Kind.MATCH, DMGraphNode.Kind.RANDOM:
			return node.ports.size() - 1
		_:
			return 0


static func _get_return_port(node: DMGraphNode) -> int:
	match node.kind:
		DMGraphNode.Kind.CHOICES, DMGraphNode.Kind.CONDITION, DMGraphNode.Kind.MATCH, DMGraphNode.Kind.RANDOM:
			return node.ports.size() - 1
		DMGraphNode.Kind.DIALOGUE, DMGraphNode.Kind.RESPONSE, DMGraphNode.Kind.JUMP:
			return 1 if node.ports.size() > 1 else 0
		_:
			return 0


static func _add_flow(doc: DMGraphDocument, node: DMGraphNode, line_id: String, port: int = 0) -> void:
	var target_id: String = _target_node_id(doc, line_id)
	if target_id.is_empty():
		return

	# A while loop's last body line points back to the while line. The dedicated
	# while-loop pass adds that as a RETURN edge, so don't duplicate it here.
	var target_node: DMGraphNode = doc.get_node(target_id)
	if target_node != null \
		and target_node.kind == DMGraphNode.Kind.WHILE \
		and target_node.get_property("line_id", "") == line_id:
		return

	_add_edge_if_missing(doc, DMGraphEdge.new(node.id, port, target_id, 0, DMGraphEdge.Kind.FLOW, ""))


static func _add_branch(doc: DMGraphDocument, node: DMGraphNode, port: int, line_id: String) -> void:
	var target_id: String = _target_node_id(doc, line_id)
	if target_id.is_empty():
		return
	_add_edge_if_missing(doc, DMGraphEdge.new(node.id, port, target_id, 0, DMGraphEdge.Kind.BRANCH, ""))


static func _add_branch_to_node(doc: DMGraphDocument, node: DMGraphNode, port: int, target_node_id: String) -> void:
	if not doc.nodes.has(target_node_id):
		return
	_add_edge_if_missing(doc, DMGraphEdge.new(node.id, port, target_node_id, 0, DMGraphEdge.Kind.BRANCH, ""))


static func _add_jump(doc: DMGraphDocument, node: DMGraphNode, target: String) -> void:
	var target_id: String = _cue_target_node_id(doc, target)
	if target_id.is_empty():
		return
	_add_edge_if_missing(doc, DMGraphEdge.new(node.id, 0, target_id, 0, DMGraphEdge.Kind.JUMP, target))


static func _add_return(doc: DMGraphDocument, node: DMGraphNode, line_id: String) -> void:
	var target_id: String = _target_node_id(doc, line_id)
	if target_id.is_empty():
		return
	var port: int = 1 if node.ports.size() > 1 else 0
	_add_edge_if_missing(doc, DMGraphEdge.new(node.id, port, target_id, 0, DMGraphEdge.Kind.RETURN, "return"))


static func _target_node_id(doc: DMGraphDocument, line_id: String) -> String:
	if line_id.is_empty():
		return ""
	if line_id == "end":
		return "__end__"
	if line_id == "end!":
		return "__end_conversation__"
	if doc.response_groups.has(line_id):
		return doc.response_groups[line_id]
	if doc.line_nodes.has(line_id):
		return doc.line_nodes[line_id]
	if doc.cues.has(line_id):
		return doc.cues[line_id]
	return ""


static func _cue_target_node_id(doc: DMGraphDocument, target: String) -> String:
	if target.is_empty():
		return ""
	if target == "END":
		return "__end__"
	if target == "END!":
		return "__end_conversation__"
	if target.begins_with("{{"):
		return ""
	if doc.cues.has(target):
		return doc.cues[target]
	return ""


static func _add_edge_if_missing(doc: DMGraphDocument, edge: DMGraphEdge) -> void:
	for existing: DMGraphEdge in doc.edges:
		if existing.from_node == edge.from_node \
			and existing.from_port == edge.from_port \
			and existing.to_node == edge.to_node \
			and existing.to_port == edge.to_port \
			and existing.kind == edge.kind:
			return
	doc.add_edge(edge)


static func _source_line_for_id(line_id: String) -> int:
	if line_id.is_empty():
		return -1
	var base: String = line_id.split(".")[0]
	if not base.is_valid_int():
		return -1
	return base.to_int()


static func _find_block_end(lines: PackedStringArray, start_line: int, indent: int) -> int:
	if start_line < 0 or start_line >= lines.size():
		return start_line

	var end: int = start_line
	var i: int = start_line + 1
	while i < lines.size():
		var raw_line: String = lines[i]
		if raw_line.strip_edges().is_empty():
			i += 1
			continue
		if _indent_count(raw_line) <= indent:
			break
		end = i
		i += 1
	return end


static func _indent_count(line: String) -> int:
	var count: int = 0
	for i: int in line.length():
		if line[i] == "\t":
			count += 4
		elif line[i] == " ":
			count += 1
		else:
			break
	return count


static func _stable_key(line: Dictionary, _index: int) -> String:
	var line_type: String = line.get("type", "")
	var static_id: String = line.get("static_id", "")
	var text: String = line.get("text", "")
	var character: String = line.get("character", "")

	match line_type:
		DMConstants.TYPE_DIALOGUE:
			if not static_id.is_empty():
				return "dialogue:%s" % [static_id]
			return "dialogue:%s" % [("%s:%s" % [character, text]).sha1_text()]
		DMConstants.TYPE_RESPONSE:
			if not static_id.is_empty():
				return "response:%s" % [static_id]
			return "response:%s" % [text.sha1_text()]
		DMConstants.TYPE_CONDITION:
			return "condition:%s" % [str(line.get("condition", {})).sha1_text()]
		DMConstants.TYPE_MATCH:
			return "match:%s" % [str(line.get("condition", {})).sha1_text()]
		DMConstants.TYPE_WHILE:
			return "while:%s" % [str(line.get("condition", {})).sha1_text()]
		DMConstants.TYPE_MUTATION:
			return "mutation:%s" % [str(line.get("mutation", {})).sha1_text()]
		DMConstants.TYPE_GOTO:
			return "jump:%s:%s" % [
				str(line.get("next_id", "")).sha1_text(),
				str(line.get("is_snippet", false))
			]
		DMConstants.TYPE_RANDOM:
			return "random:%s" % [str(line.get("siblings", [])).sha1_text()]
		_:
			return "%s:%d" % [line_type, _index]


static func _extract_goto(raw_line: String) -> String:
	var line: String = raw_line
	var static_id: String = DMCompiler.get_static_line_id(line)
	if not static_id.is_empty():
		line = line.replace("[ID:%s]" % [static_id], "").strip_edges()

	var regex: DMCompilerRegEx = DMCompilerRegEx.new()
	var found: RegExMatch = regex.GOTO_REGEX.search(line)
	if found:
		return found.strings[found.names.goto].strip_edges()
	return ""


static func _extract_condition(raw_line: String) -> String:
	var regex: DMCompilerRegEx = DMCompilerRegEx.new()
	var found: RegExMatch = regex.CONDITION_REGEX.search(raw_line.strip_edges())
	if found:
		return found.strings[found.names.expression].strip_edges()
	return ""


static func _extract_mutation(raw_line: String) -> String:
	var regex: DMCompilerRegEx = DMCompilerRegEx.new()
	var found: RegExMatch = regex.MUTATION_REGEX.search(raw_line.strip_edges())
	if found:
		return found.strings[found.names.expression].strip_edges()
	return ""
