extends AbstractTest


func test_sets_dialogue_properties() -> void:
	var text: String = "~ start\nNathan: Hello.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:1")

	var new_text: String = DMGraphSerializer.set_dialogue_properties(text, node, {
		character = "Coco",
		text = "Meow.",
		tags = PackedStringArray(["happy"]),
		static_id = "MEOW"
	})

	assert(new_text.contains("Coco: [#happy] Meow. [ID:MEOW]"), "Should write the dialogue line.")


func test_sets_response_properties() -> void:
	var text: String = "~ start\nNathan: Choose.\n- First\n\tNathan: One.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:2")

	var new_text: String = DMGraphSerializer.set_response_properties(text, node, {
		text = "Second",
		condition = "score > 1",
		goto = "start",
		static_id = "SECOND"
	})

	assert(new_text.contains("- Second [if score > 1 /] => start [ID:SECOND]"), "Should write the response line.")


func test_renames_cue_and_updates_jumps() -> void:
	var text: String = "~ start\nNathan: Hello.\n=> start"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.find_cue_node("start")

	var new_text: String = DMGraphSerializer.set_cue_name(text, node, "begin")

	assert(new_text.contains("~ begin"), "Should rename the cue.")
	assert(new_text.contains("=> begin"), "Should update jumps to the cue.")


func test_sets_jump_target() -> void:
	var text: String = "~ start\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:1")

	var new_text: String = DMGraphSerializer.set_jump_target(text, node, "start", false)

	assert(new_text.contains("=> start"), "Should set the jump target.")


func test_adds_dialogue_after() -> void:
	var text: String = "~ start\nNathan: Hello.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:1")

	var new_text: String = DMGraphSerializer.add_dialogue_after(text, node, "Coco", "Meow.")

	assert(new_text.contains("Coco: Meow."), "Should add a dialogue line.")


func test_adds_response_after() -> void:
	var text: String = "~ start\nNathan: Choose.\n- First\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:1")

	var new_text: String = DMGraphSerializer.add_response_after(text, node, "Second")

	assert(new_text.contains("- Second"), "Should add a response line.")


func test_adds_response_to_choices_group() -> void:
	var text: String = "~ start\nNathan: Choose.\n- First\n\tNathan: One.\n- Second\n\tNathan: Two.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var choices: DMGraphNode = doc.get_node("choices:2")

	var new_text: String = DMGraphSerializer.add_response_after(text, choices, "Third")
	var new_doc: DMGraphDocument = DMGraphBuilder.build(new_text, "")
	var new_choices: DMGraphNode = new_doc.get_node("choices:2")

	assert(new_choices != null, "Should keep the choices node.")
	assert(Array(new_choices.get_property("responses", [])).size() == 3, "Should add the response to the same group.")


func test_removes_response_from_choices_group() -> void:
	var text: String = "~ start\nNathan: Choose.\n- First\n\tNathan: One.\n- Second\n\tNathan: Two.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var choices: DMGraphNode = doc.get_node("choices:2")
	var response_ids: Array = Array(choices.get_property("responses", []))
	var second_response: DMGraphNode = doc.get_node("line:%s" % [response_ids[1]])

	var new_text: String = DMGraphSerializer.delete_node(text, second_response)
	var new_doc: DMGraphDocument = DMGraphBuilder.build(new_text, "")
	var new_choices: DMGraphNode = new_doc.get_node("choices:2")

	assert(not new_text.contains("- Second"), "Should remove the response line.")
	assert(Array(new_choices.get_property("responses", [])).size() == 1, "Should keep the remaining response.")


func test_moves_response_blocks() -> void:
	var text: String = "~ start\nNathan: Choose.\n- First\n\tNathan: One.\n- Second\n\tNathan: Two.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var choices: DMGraphNode = doc.get_node("choices:2")
	var response_ids: Array = Array(choices.get_property("responses", []))
	var first_response: DMGraphNode = doc.get_node("line:%s" % [response_ids[0]])
	var second_response: DMGraphNode = doc.get_node("line:%s" % [response_ids[1]])

	var moved_down: String = DMGraphSerializer.move_node_block(
		text,
		first_response,
		second_response.source_end + 1
	)
	assert(moved_down.find("- Second") < moved_down.find("- First"), "Should move the first response down.")

	var moved_up: String = DMGraphSerializer.move_node_block(
		text,
		second_response,
		first_response.source_start
	)
	assert(moved_up.find("- Second") < moved_up.find("- First"), "Should move the second response up.")

	var moved_doc: DMGraphDocument = DMGraphBuilder.build(moved_up, "")
	var moved_choices: DMGraphNode = moved_doc.get_node("choices:2")
	var moved_ids: Array = Array(moved_choices.get_property("responses", []))
	var moved_first: DMGraphNode = moved_doc.get_node("line:%s" % [moved_ids[0]])
	assert(moved_first.get_property("text") == "Second", "Should update the response order in the graph.")


func test_deletes_node() -> void:
	var text: String = "~ start\nNathan: Hello.\nCoco: Meow.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:1")

	var new_text: String = DMGraphSerializer.delete_node(text, node)

	assert(not new_text.contains("Nathan: Hello."), "Should remove the dialogue line.")
	assert(new_text.contains("Coco: Meow."), "Should keep the other dialogue line.")


func test_sets_condition_cases() -> void:
	var text: String = "~ start\nif score > 10\n\tNathan: High.\nelse\n\tNathan: Low.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("condition:1")
	var cases: Array = Array(node.get_property("cases", []))
	cases[0].expression = "score >= 20"

	var new_text: String = DMGraphSerializer.set_condition_cases(text, node, cases)

	assert(new_text.contains("if score >= 20"), "Should update the if expression.")
	assert(new_text.contains("else"), "Should keep the else case.")


func test_sets_match_cases() -> void:
	var text: String = "~ start\nmatch mode\n\twhen 1\n\t\tNathan: One.\n\telse\n\t\tNathan: Other.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("match:1")
	var cases: Array = Array(node.get_property("cases", []))
	cases[0].expression = "2"

	var new_text: String = DMGraphSerializer.set_match_cases(text, node, cases)

	assert(new_text.contains("when 2"), "Should update the when expression.")


func test_sets_while_expression() -> void:
	var text: String = "~ start\nwhile count < 10\n\tNathan: Loop.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("while:1")

	var new_text: String = DMGraphSerializer.set_while_expression(text, node, "count < 5")

	assert(new_text.contains("while count < 5"), "Should update the while expression.")


func test_sets_random_branches() -> void:
	var text: String = "~ start\n% Nathan: One.\n%2 Nathan: Two.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("random:1")
	var branches: Array = Array(node.get_property("branches", []))
	branches[0].weight = 3.0
	branches[1].condition_text = "score > 1"

	var new_text: String = DMGraphSerializer.set_random_branches(text, node, branches)

	assert(new_text.contains("%3 Nathan: One."), "Should update the branch weight.")
	assert(new_text.contains("%2 [if score > 1 /] Nathan: Two."), "Should update the branch condition.")


func test_clears_inline_goto() -> void:
	var text: String = "~ start\nNathan: Hello. => start\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:1")

	var new_text: String = DMGraphSerializer.clear_inline_goto(text, node)

	assert(not new_text.contains("=> start"), "Should remove the inline goto.")
	assert(new_text.contains("Nathan: Hello."), "Should keep the dialogue text.")


func test_adds_cue_before() -> void:
	var text: String = "~ start\nNathan: Hello.\nCoco: Meow.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:2")

	var new_text: String = DMGraphSerializer.add_cue_before(text, node, "goto_line_2")
	var lines: PackedStringArray = new_text.split("\n")

	assert(lines[2] == "~ goto_line_2", "Should insert the cue before the target line.")


func test_adds_standalone_node() -> void:
	var text: String = "~ start\nNathan: Hello.\n=> END"
	var new_text: String = DMGraphSerializer.add_standalone_node(
		text,
		DMGraphNode.Kind.DIALOGUE,
		"draft"
	)
	var doc: DMGraphDocument = DMGraphBuilder.build(new_text, "")

	assert(doc.cues.has("draft"), "Should add a cue for the standalone block.")
	assert(new_text.contains("Nathan: New dialogue"), "Should add the new dialogue line.")
	assert(doc.get_validation_warnings().size() == 1, "The new block should be unconnected.")


func test_adds_unconnected_node() -> void:
	var text: String = "~ start\nNathan: Hello."
	var new_text: String = DMGraphSerializer.add_unconnected_node(text, DMGraphNode.Kind.DIALOGUE)
	var doc: DMGraphDocument = DMGraphBuilder.build(new_text, "")

	assert(new_text.contains("=> END"), "Should terminate the previous flow before the new node.")

	var new_node: DMGraphNode = null
	for node: DMGraphNode in doc.nodes.values():
		if node.kind == DMGraphNode.Kind.DIALOGUE and node.get_property("text") == "New dialogue":
			new_node = node
			break

	assert(new_node != null, "Should add the new dialogue node.")
	assert(doc.get_edges_to(new_node.id).is_empty(), "The new node should have no incoming connections.")
	assert(doc.get_edges_from(new_node.id).is_empty(), "The new node should have no outgoing connections.")


func test_adds_condition_case() -> void:
	var text: String = "~ start\nif score > 10\n\tNathan: High.\nelse\n\tNathan: Low.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("condition:1")

	var new_text: String = DMGraphSerializer.add_condition_case(text, node, "score > 0", false)

	assert(new_text.contains("elif score > 0"), "Should add an elif case.")
	assert(new_text.contains("Nathan: New branch"), "Should add a placeholder branch.")


func test_removes_condition_case() -> void:
	var text: String = "~ start\nif score > 10\n\tNathan: High.\nelse\n\tNathan: Low.\nNathan: After.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("condition:1")

	var new_text: String = DMGraphSerializer.remove_condition_case(text, node, 1)

	assert(not new_text.contains("else"), "Should remove the else case.")
	assert(new_text.contains("Nathan: After."), "Should keep the following line.")


func test_adds_match_case() -> void:
	var text: String = "~ start\nmatch mode\n\twhen 1\n\t\tNathan: One.\n\telse\n\t\tNathan: Other.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("match:1")

	var new_text: String = DMGraphSerializer.add_match_case(text, node, "2", false)

	assert(new_text.contains("when 2"), "Should add a when case.")
	assert(new_text.contains("Nathan: New branch"), "Should add a placeholder branch.")


func test_removes_match_case() -> void:
	var text: String = "~ start\nmatch mode\n\twhen 1\n\t\tNathan: One.\n\telse\n\t\tNathan: Other.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("match:1")

	var new_text: String = DMGraphSerializer.remove_match_case(text, node, 1)

	assert(not new_text.contains("else"), "Should remove the else case.")
	assert(new_text.contains("when 1"), "Should keep the when case.")


func test_adds_random_branch() -> void:
	var text: String = "~ start\n% Nathan: One.\n%2 Nathan: Two.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("random:1")

	var new_text: String = DMGraphSerializer.add_random_branch(text, node, 3.0, "score > 1")

	assert(new_text.contains("%3 [if score > 1 /]"), "Should add a weighted conditional branch.")
	assert(new_text.contains("Nathan: New branch"), "Should add a placeholder branch.")


func test_removes_random_branch() -> void:
	var text: String = "~ start\n% Nathan: One.\n%2 Nathan: Two.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("random:1")

	var new_text: String = DMGraphSerializer.remove_random_branch(text, node, 0)

	assert(not new_text.contains("% Nathan: One."), "Should remove the first branch.")
	assert(new_text.contains("%2 Nathan: Two."), "Should keep the second branch.")


func test_round_trip_without_changes() -> void:
	var text: String = "~ start\nNathan: Hello.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:1")

	var new_text: String = DMGraphSerializer.set_dialogue_properties(text, node, {
		character = "Nathan",
		text = "Hello."
	})

	assert(new_text == text, "Should not change the text when nothing changed.")
