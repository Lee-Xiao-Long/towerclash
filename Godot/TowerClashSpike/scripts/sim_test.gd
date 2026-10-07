class_name SimTest
extends Node
## Offline MatchSim runner (no network): --simtest [--matches=N] [--seed=S]
## Both sides play the bot policy (place when affordable, merge when nearly full).

func _ready() -> void:
	GameData.ensure_loaded()
	var n := int(Net.args.get("matches", "10"))
	var seed0 := int(Net.args.get("seed", "1"))
	var t0 := Time.get_ticks_msec()
	var wins := [0, 0, 0]
	var rounds_total := 0
	var reasons := {}
	var end_rounds := {}
	for m in n:
		var res := run_one(seed0 + m)
		wins[int(res.winner) + 1] += 1
		rounds_total += int(res.round)
		reasons[res.reason] = reasons.get(res.reason, 0) + 1
		end_rounds[str(res.round)] = end_rounds.get(str(res.round), 0) + 1
		if Net.args.has("verbose"):
			print("SIMTEST_MATCH " + JSON.stringify(res))
	var out := {
		"matches": n, "draws": wins[0], "p0_wins": wins[1], "p1_wins": wins[2],
		"avg_rounds": float(rounds_total) / n, "reasons": reasons, "end_rounds": end_rounds,
		"ms_per_match": float(Time.get_ticks_msec() - t0) / n,
	}
	print("SIMTEST " + JSON.stringify(out))
	get_tree().quit(0)


static func run_one(seed_value: int) -> Dictionary:
	var sim := MatchSim.new()
	var deck: Array = GameData.rules.default_deck
	sim.setup([deck, deck], seed_value)
	sim.start()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919
	var dt := 1.0 / 30.0
	var think := [0.0, 0.0]
	var guard := 0
	while sim.phase != MatchSim.Phase.ENDED and guard < 30 * 60 * 20:
		guard += 1
		sim.step(dt)
		for p in 2:
			think[p] -= dt
			if think[p] > 0.0:
				continue
			think[p] = rng.randf_range(0.3, 1.2)
			bot_decide(sim, p, rng)
	return sim.result


static func bot_decide(sim: MatchSim, p: int, rng: RandomNumberGenerator) -> void:
	var towers: Dictionary = sim.players[p].towers
	if towers.size() >= 12 or rng.randf() < 0.15:
		var by_key := {}
		for slot in towers:
			var t: Dictionary = towers[slot]
			if int(t.level) >= int(GameData.rules.max_tower_level):
				continue
			var k := "%s:%d" % [t.type, t.level]
			if by_key.has(k):
				sim.request_merge(p, by_key[k], slot)
				return
			by_key[k] = slot
	if sim.players[p].gold >= sim.next_tower_cost(p):
		sim.request_place(p)
	elif towers.size() >= 8 and rng.randf() < 0.1:
		var i := rng.randi_range(0, sim.players[p].deck.size() - 1)
		var cost := sim.next_upgrade_cost(p, i)
		if cost > 0 and sim.players[p].gold >= cost:
			sim.request_upgrade(p, i)
