@tool
class_name DMGraphColors extends RefCounted


## User-config key used to persist the chosen color for each node type.
const USER_CONFIG_KEY: String = "graph_node_colors"


static var _cached_colors: Dictionary = {}


static func get_kinds() -> Array[int]:
	return [
		DMGraphNode.Kind.CUE,
		DMGraphNode.Kind.DIALOGUE,
		DMGraphNode.Kind.CHOICES,
		DMGraphNode.Kind.RESPONSE,
		DMGraphNode.Kind.CONDITION,
		DMGraphNode.Kind.MATCH,
		DMGraphNode.Kind.WHILE,
		DMGraphNode.Kind.MUTATION,
		DMGraphNode.Kind.JUMP,
		DMGraphNode.Kind.RANDOM,
		DMGraphNode.Kind.CONCURRENT,
		DMGraphNode.Kind.COMMENT,
		DMGraphNode.Kind.IMPORT,
		DMGraphNode.Kind.USING,
		DMGraphNode.Kind.NOTE
	]


static func get_kind_name(kind: DMGraphNode.Kind) -> String:
	match kind:
		DMGraphNode.Kind.CUE:
			return "Cue"
		DMGraphNode.Kind.DIALOGUE:
			return "Dialogue"
		DMGraphNode.Kind.CHOICES:
			return "Choices"
		DMGraphNode.Kind.RESPONSE:
			return "Response"
		DMGraphNode.Kind.CONDITION:
			return "Condition"
		DMGraphNode.Kind.MATCH:
			return "Match"
		DMGraphNode.Kind.WHILE:
			return "While"
		DMGraphNode.Kind.MUTATION:
			return "Mutation"
		DMGraphNode.Kind.JUMP:
			return "Jump"
		DMGraphNode.Kind.RANDOM:
			return "Random"
		DMGraphNode.Kind.CONCURRENT:
			return "Concurrent"
		DMGraphNode.Kind.COMMENT:
			return "Comment"
		DMGraphNode.Kind.IMPORT:
			return "Import"
		DMGraphNode.Kind.USING:
			return "Using"
		DMGraphNode.Kind.NOTE:
			return "Note"
		_:
			return "Node"


static func get_default_color(kind: DMGraphNode.Kind) -> Color:
	match kind:
		DMGraphNode.Kind.CUE:
			return Color(0.35, 0.65, 1.0)
		DMGraphNode.Kind.DIALOGUE:
			return Color(0.35, 0.8, 0.45)
		DMGraphNode.Kind.CHOICES:
			return Color(0.9, 0.6, 0.2)
		DMGraphNode.Kind.RESPONSE:
			return Color(0.9, 0.75, 0.25)
		DMGraphNode.Kind.CONDITION, DMGraphNode.Kind.MATCH, DMGraphNode.Kind.WHILE:
			return Color(0.7, 0.45, 0.9)
		DMGraphNode.Kind.MUTATION:
			return Color(0.6, 0.6, 0.6)
		DMGraphNode.Kind.JUMP:
			return Color(0.9, 0.3, 0.3)
		DMGraphNode.Kind.RANDOM:
			return Color(0.2, 0.8, 0.8)
		DMGraphNode.Kind.CONCURRENT:
			return Color(0.35, 0.8, 0.45)
		DMGraphNode.Kind.IMPORT:
			return Color(0.35, 0.65, 1.0)
		DMGraphNode.Kind.NOTE:
			return Color(0.85, 0.75, 0.35)
		_:
			return Color(0.5, 0.5, 0.5)


static func get_color(kind: DMGraphNode.Kind) -> Color:
	var key: String = get_kind_name(kind)

	if not _cached_colors.has(key):
		var saved_colors: Dictionary = DMSettings.get_user_value(USER_CONFIG_KEY, {})
		var saved: Variant = saved_colors.get(key, null)
		if saved is String and Color.html_is_valid(saved):
			_cached_colors[key] = Color.html(saved)
		elif saved is Color:
			_cached_colors[key] = saved
		else:
			_cached_colors[key] = get_default_color(kind)

	return _cached_colors[key]


static func set_color(kind: DMGraphNode.Kind, color: Color) -> void:
	var key: String = get_kind_name(kind)
	var saved_colors: Dictionary = DMSettings.get_user_value(USER_CONFIG_KEY, {})
	saved_colors[key] = color.to_html(true)
	DMSettings.set_user_value(USER_CONFIG_KEY, saved_colors)
	_cached_colors[key] = color


static func reset_colors() -> void:
	DMSettings.set_user_value(USER_CONFIG_KEY, {})
	_cached_colors.clear()


static func get_text_color(background: Color) -> Color:
	return Color(0.08, 0.08, 0.08) if background.get_luminance() > 0.55 else Color.WHITE


## A stable, readable color for a character name. The same name always gets the
## same color, and different names are spread around the color wheel.
static func get_character_color(character: String) -> Color:
	if character.is_empty():
		return Color(0.7, 0.7, 0.7)

	var hash_value: int = abs(character.hash())
	var hue: float = float(hash_value % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.95)
