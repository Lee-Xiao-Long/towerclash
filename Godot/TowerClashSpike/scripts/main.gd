extends Node
## Entry point. Role comes from user args after "--":
##   --server [--port=7777] [--seed=N] [--timescale=4] [--quit-on-end]
##   [--host=127.0.0.1] [--port=7777] [--name=X] [--bot] [--quit-on-end] [--shots=5,30 --shot-prefix=path]
##   --calib [--out=dir]


func _ready() -> void:
	var a: Dictionary = Net.args
	var port := int(a.get("port", str(Net.DEFAULT_PORT)))
	if a.has("calib"):
		add_child(CalibView.new())
	elif a.has("simtest"):
		add_child(SimTest.new())
	elif a.has("eostest"):
		add_child(load("res://scripts/eos_test.gd").new())
	elif a.has("server") or OS.has_feature("dedicated_server") or DisplayServer.get_name() == "headless" and not a.has("bot"):
		Net.start_server(port)
	else:
		add_child(ArenaView.new())
		GameData.ensure_loaded()
		var deck: Array = String(a.get("deck", ",".join(GameData.rules.default_deck))).split(",")
		Net.start_client(a.get("host", "127.0.0.1"), port, deck, a.get("name", "Player"))
