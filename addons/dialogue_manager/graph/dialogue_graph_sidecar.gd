@tool
class_name DMGraphSidecar extends RefCounted


const VERSION: int = 1


static func get_path(dialogue_path: String) -> String:
	return "%s.graph.json" % [dialogue_path]


static func load_for(dialogue_path: String) -> Dictionary:
	var sidecar_path: String = get_path(dialogue_path)
	if not FileAccess.file_exists(sidecar_path):
		return {}

	var file: FileAccess = FileAccess.open(sidecar_path, FileAccess.READ)
	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if parsed is Dictionary:
		return parsed
	return {}


static func save_for(dialogue_path: String, document: DMGraphDocument) -> void:
	if dialogue_path.is_empty():
		return

	var data: Dictionary = collect_from_document(document)
	var file: FileAccess = FileAccess.open(get_path(dialogue_path), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


static func move(old_path: String, new_path: String) -> void:
	if old_path.is_empty():
		return

	var old_sidecar: String = get_path(old_path)
	if not FileAccess.file_exists(old_sidecar):
		return

	if new_path.is_empty():
		remove(old_path)
		return

	var new_sidecar: String = get_path(new_path)
	var old_absolute: String = ProjectSettings.globalize_path(old_sidecar)
	var new_absolute: String = ProjectSettings.globalize_path(new_sidecar)

	var error: Error = DirAccess.rename_absolute(old_absolute, new_absolute)
	if error != OK:
		# Fall back to copy + remove for filesystems that don't support rename.
		var contents: String = FileAccess.get_file_as_string(old_sidecar)
		var file: FileAccess = FileAccess.open(new_sidecar, FileAccess.WRITE)
		if file != null:
			file.store_string(contents)
			file.close()
			DirAccess.remove_absolute(old_absolute)


static func remove(path: String) -> void:
	if path.is_empty():
		return
	var sidecar_path: String = get_path(path)
	if FileAccess.file_exists(sidecar_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sidecar_path))


static func apply_to_document(document: DMGraphDocument, data: Dictionary) -> void:
	if data.is_empty():
		return

	var node_data: Dictionary = data.get("nodes", {})
	var used_keys: Dictionary = {}

	for node: DMGraphNode in document.nodes.values():
		var key: String = node.stable_key if not node.stable_key.is_empty() else node.id
		var matched_key: String = ""

		if node_data.has(key) and not used_keys.has(key):
			matched_key = key
		elif node.source_start >= 0:
			# Fall back to the source line when an edit changed the stable key.
			for saved_key: String in node_data:
				if used_keys.has(saved_key):
					continue
				var candidate: Dictionary = node_data[saved_key]
				if candidate.get("source_start", -1) == node.source_start:
					matched_key = saved_key
					break

		if matched_key.is_empty() and node.source_start >= 0:
			# Last resort: match the nearest saved node of the same kind.
			var best_distance: int = 999999
			for saved_key: String in node_data:
				if used_keys.has(saved_key):
					continue
				var candidate: Dictionary = node_data[saved_key]
				if candidate.get("kind", -1) != node.kind:
					continue
				var saved_source: int = candidate.get("source_start", -1)
				if saved_source < 0:
					continue
				var distance: int = abs(saved_source - node.source_start)
				if distance < best_distance:
					best_distance = distance
					matched_key = saved_key
			if best_distance > 8:
				matched_key = ""

		if matched_key.is_empty():
			continue

		used_keys[matched_key] = true
		var saved: Dictionary = node_data[matched_key]
		node.has_saved_position = true

		var position_data: Array = saved.get("position", [])
		if position_data.size() == 2:
			node.position = Vector2(position_data[0], position_data[1])
		var size_data: Array = saved.get("size", [])
		if size_data.size() == 2:
			node.size = Vector2(size_data[0], size_data[1])
		node.collapsed = saved.get("collapsed", false)


static func collect_from_document(document: DMGraphDocument) -> Dictionary:
	var node_data: Dictionary = {}
	for node: DMGraphNode in document.nodes.values():
		var key: String = node.stable_key if not node.stable_key.is_empty() else node.id
		node_data[key] = {
			position = [node.position.x, node.position.y],
			size = [node.size.x, node.size.y],
			collapsed = node.collapsed,
			source_start = node.source_start,
			kind = node.kind
		}

	return {
		version = VERSION,
		file = document.path,
		nodes = node_data,
		groups = [],
		settings = {}
	}
