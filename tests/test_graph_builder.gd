extends AbstractTest


func test_builds_basic_dialogue() -> void:
	var text: String = "~ start\nNathan: Hello.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")

	assert(doc.cues.has("start"), "Should have a start cue.")
	assert(doc.find_cue_node("start") != null, "Should have a cue node.")

	var dialogue: DMGraphNode = doc.get_node("line:1")
	assert(dialogue != null, "Should have a dialogue node.")
	assert(dialogue.kind == DMGraphNode.Kind.DIALOGUE, "Should be a dialogue node.")
	assert(dialogue.get_property("character") == "Nathan", "Should have a character.")
	assert(dialogue.get_property("text") == "Hello.", "Should have text.")

	var jump: DMGraphNode = doc.get_node("line:2")
	assert(jump != null, "Should have a jump node.")
	assert(jump.kind == DMGraphNode.Kind.JUMP, "Should be a jump node.")
	assert(jump.get_property("target") == "END", "Should jump to END.")


func test_builds_responses() -> void:
	var text: String = "~ start\nNathan: Choose.\n- First\n\tNathan: One.\n- Second\n\tNathan: Two.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")

	assert(doc.response_groups.has("2"), "Should have a response group.")
	var choices: DMGraphNode = doc.get_node("choices:2")
	assert(choices != null, "Should have a choices node.")
	assert(choices.kind == DMGraphNode.Kind.CHOICES, "Should be a choices node.")
	assert(Array(choices.get_property("responses")).size() == 2, "Should have two responses.")
	assert(choices.get_property("next_id_after") == "6", "Should continue after the responses.")

	var first_response: DMGraphNode = doc.get_node("line:2")
	assert(first_response != null, "Should have the first response node.")
	assert(first_response.kind == DMGraphNode.Kind.RESPONSE, "Should be a response node.")

	var second_response: DMGraphNode = doc.get_node("line:4")
	assert(second_response != null, "Should have the second response node.")
	assert(second_response.kind == DMGraphNode.Kind.RESPONSE, "Should be a response node.")


func test_builds_conditions() -> void:
	var text: String = "~ start\nif score > 10\n\tNathan: High.\nelse\n\tNathan: Low.\nNathan: After.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")

	var condition: DMGraphNode = doc.get_node("condition:1")
	assert(condition != null, "Should have a condition node.")
	assert(condition.kind == DMGraphNode.Kind.CONDITION, "Should be a condition node.")
	assert(Array(condition.get_property("cases")).size() == 2, "Should have two cases.")
	assert(condition.get_property("next_id_after") == "5", "Should continue after the condition.")
	assert(condition.ports.size() == 3, "Should have two case ports and an after port.")


func test_builds_match() -> void:
	var text: String = "~ start\nmatch SomeGlobal.mode\n\twhen 1\n\t\tNathan: One.\n\telse\n\t\tNathan: Other.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")

	var match_node: DMGraphNode = doc.get_node("match:1")
	assert(match_node != null, "Should have a match node.")
	assert(match_node.kind == DMGraphNode.Kind.MATCH, "Should be a match node.")
	assert(Array(match_node.get_property("cases")).size() == 2, "Should have two cases.")
	assert(match_node.get_property("next_id_after") == "6", "Should continue after the match.")
	assert(match_node.ports.size() == 3, "Should have two case ports and an after port.")


func test_builds_while() -> void:
	var text: String = "~ start\nwhile count < 10\n\tNathan: Loop.\n\t$> count += 1\nNathan: Done.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")

	var while_node: DMGraphNode = doc.get_node("while:1")
	assert(while_node != null, "Should have a while node.")
	assert(while_node.kind == DMGraphNode.Kind.WHILE, "Should be a while node.")
	assert(while_node.get_property("next_id") == "2", "Should have a body.")
	assert(while_node.get_property("next_id_after") == "4", "Should continue after the loop.")
	assert(while_node.ports.size() == 2, "Should have body and after ports.")

	var mutation: DMGraphNode = doc.get_node("line:3")
	assert(mutation != null, "Should have a mutation node.")
	assert(mutation.get_property("next_id") == "1", "Should loop back to the while line.")


func test_builds_random() -> void:
	var text: String = "~ start\n% Nathan: One.\n%2 Nathan: Two.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")

	var random_node: DMGraphNode = doc.get_node("random:1")
	assert(random_node != null, "Should have a random node.")
	assert(random_node.kind == DMGraphNode.Kind.RANDOM, "Should be a random node.")
	assert(Array(random_node.get_property("branches")).size() == 2, "Should have two branches.")
	assert(random_node.get_property("next_id_after") == "3", "Should continue after the random group.")
	assert(random_node.ports.size() == 3, "Should have two branch ports and an after port.")

	assert(doc.get_node("line:1") != null, "Should have the first branch node.")
	assert(doc.get_node("line:2") != null, "Should have the second branch node.")


func test_builds_concurrent_lines() -> void:
	var text: String = "~ start\nNathan: Main.\n| Coco: Same time.\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")

	var main: DMGraphNode = doc.get_node("line:1")
	assert(main != null, "Should have the main dialogue node.")
	assert(Array(main.get_property("concurrent_lines")).size() == 1, "Should have one concurrent line.")

	var concurrent: DMGraphNode = doc.get_node("line:2")
	assert(concurrent != null, "Should have a concurrent node.")
	assert(concurrent.kind == DMGraphNode.Kind.CONCURRENT, "Should be a concurrent node.")


func test_builds_imports() -> void:
	DMCache.add_file("res://tests/snippets.dialogue")

	var text: String = "import \"res://tests/snippets.dialogue\" as snippets\n~ start\n=>< snippets/snippet\n=> END"
	var doc: DMGraphDocument = DMGraphBuilder.build(text, "")

	assert(doc.imports.size() == 1, "Should have one import.")
	assert(doc.get_node("import:0") != null, "Should have an import node.")

	var jump: DMGraphNode = doc.get_node("line:2")
	assert(jump != null, "Should have a jump node.")
	assert(jump.get_property("target") == "snippets/snippet", "Should jump to the imported cue.")
	assert(jump.get_property("is_snippet") == true, "Should be a jump and return.")
