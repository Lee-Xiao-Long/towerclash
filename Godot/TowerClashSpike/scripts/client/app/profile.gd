class_name Profile
extends RefCounted
## Local player profile in user://. --profile=<id> selects a separate file so several clients
## on one machine (launcher) keep their own names and stats.

const HISTORY_MAX := 10

var path := ""
var data := {}


static func open(id: String) -> Profile:
	var p := Profile.new()
	p.path = "user://profile%s.json" % ("" if id == "" else "_" + id.validate_filename())
	p._load()
	return p


func _defaults() -> Dictionary:
	GameData.ensure_loaded()
	return {
		"name": "Player%04d" % (randi() % 10000),
		"deck": GameData.rules.default_deck.duplicate(),
		"matches": 0, "wins": 0, "losses": 0, "draws": 0, "kills": 0, "best_round": 0,
		"history": [],
		"settings": {"connection": "online", "local_address": "127.0.0.1:%d" % Net.DEFAULT_PORT, "autoplay": false},
	}


func _load() -> void:
	data = _defaults()
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				data[k] = d[k]
			var s: Dictionary = _defaults().settings
			for k in data.settings:
				s[k] = data.settings[k]
			data.settings = s
	if not GameData.validate_deck(data.deck):
		data.deck = GameData.rules.default_deck.duplicate()
	save()


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Profile: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "  "))


func setting(key: String):
	return data.settings.get(key)


func set_setting(key: String, value) -> void:
	data.settings[key] = value
	save()


## Records a finished match from this player's point of view and returns the summary entry.
func record(res: Dictionary, me: int) -> Dictionary:
	var w := int(res.get("winner", -1))
	var o := 1 - me
	var names: Array = res.get("names", ["", ""])
	var kills: Array = res.get("kills", [0, 0])
	var hp: Array = res.get("base_hp", [0, 0])
	var entry := {
		"result": "draw" if w < 0 else ("win" if w == me else "loss"),
		"winner": w, "me": me, "reason": res.get("reason", ""),
		"opponent": names[o] if names.size() == 2 else "",
		"round": int(res.get("round", 0)), "time": float(res.get("time", 0.0)),
		"kills": [int(kills[me]), int(kills[o])], "base_hp": [int(hp[me]), int(hp[o])],
		"at": Time.get_datetime_string_from_system(false, true),
	}
	data.matches += 1
	match entry.result:
		"win": data.wins += 1
		"loss": data.losses += 1
		_: data.draws += 1
	data.kills += entry.kills[0]
	data.best_round = maxi(int(data.best_round), entry.round)
	data.history.push_front(entry)
	while data.history.size() > HISTORY_MAX:
		data.history.pop_back()
	save()
	return entry


func reset_stats() -> void:
	for k in ["matches", "wins", "losses", "draws", "kills", "best_round"]:
		data[k] = 0
	data.history = []
	save()
