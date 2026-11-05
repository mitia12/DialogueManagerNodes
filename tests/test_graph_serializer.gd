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


func test_deletes_node() -> void:
	var text: String = "~ start\nNathan: Hello.\nCoco: Meow.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:1")

	var new_text: String = DMGraphSerializer.delete_node(text, node)

	assert(not new_text.contains("Nathan: Hello."), "Should remove the dialogue line.")
	assert(new_text.contains("Coco: Meow."), "Should keep the other dialogue line.")


func test_round_trip_without_changes() -> void:
	var text: String = "~ start\nNathan: Hello.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")
	var node: DMGraphNode = doc.get_node("line:1")

	var new_text: String = DMGraphSerializer.set_dialogue_properties(text, node, {
		character = "Nathan",
		text = "Hello."
	})

	assert(new_text == text, "Should not change the text when nothing changed.")
