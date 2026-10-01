class_name GameData
extends RefCounted
## Loads the spike's JSON data tables. Shared by server and client.

static var rules: Dictionary = {}
static var towers: Dictionary = {}
static var enemies: Dictionary = {}
static var rounds: Array = []
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	rules = _read("res://data/rules.json")
	towers = _read("res://data/towers.json")
	enemies = _read("res://data/enemies.json")
	rounds = _read("res://data/rounds.json").get("rounds", [])
	_loaded = true


static func _read(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("GameData: cannot read %s" % path)
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: bad JSON in %s" % path)
		return {}
	return parsed


static func slot_count() -> int:
	return int(rules.slot_cols) * int(rules.slot_rows)


static func validate_deck(deck: Array) -> bool:
	if deck.size() != int(rules.deck_size):
		return false
	var seen := {}
	for t in deck:
		if typeof(t) != TYPE_STRING or not towers.has(t) or seen.has(t):
			return false
		seen[t] = true
	return true
