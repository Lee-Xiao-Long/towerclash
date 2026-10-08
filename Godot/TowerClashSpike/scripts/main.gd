extends Node
## Entry point. Role comes from user args after "--":
##   --server [--port=7777] [--seed=N] [--timescale=4] [--quit-on-end] [--eos [--public-address=IP]] [--max-matches=N]
##   (no role args)  client app: splash -> home -> quick match -> arena -> home (see scripts/client/app/app.gd)
##   --host=127.0.0.1 [--port=7777] [--name=X] [--bot] [--quit-on-end] [--shots=5,30 --shot-prefix=path]
##                   direct test client: straight into the arena (tools/run_match.ps1)
##   --calib [--out=dir] | --simtest | --eostest=server|client


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
	elif a.has("host"):
		add_child(ArenaView.new())
		GameData.ensure_loaded()
		var deck: Array = String(a.get("deck", ",".join(GameData.rules.default_deck))).split(",")
		if not Net.start_client(a.host, port, deck, a.get("name", "Player")):
			get_tree().quit(2)
	else:
		add_child(App.new())
	_fit_hidpi_window()


## Desktop HiDPI (macOS Retina): the project window size is in physical pixels, so a 540x960
## window is half-size on a 2x screen. Scale size and position by the screen scale (capped to the
## usable screen height); canvas_items stretch then renders the UI at native resolution.
## Mobile is unaffected (the window is the full screen there).
func _fit_hidpi_window() -> void:
	if not OS.has_feature("pc") or DisplayServer.get_name() == "headless":
		return
	var screen := DisplayServer.window_get_current_screen()
	var size := DisplayServer.window_get_size()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var s := minf(DisplayServer.screen_get_scale(screen), usable.size.y * 0.95 / size.y)
	if s <= 1.0:
		return
	var pos := DisplayServer.window_get_position() - usable.position
	DisplayServer.window_set_size(Vector2i(Vector2(size) * s))
	DisplayServer.window_set_position(usable.position + Vector2i(Vector2(pos) * s))
