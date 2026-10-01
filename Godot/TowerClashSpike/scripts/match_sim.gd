class_name MatchSim
extends RefCounted
## Authoritative, pure-data TowerClash match. Runs only on the server.
## No nodes, no world positions: players, slot indices, path distances.

enum Phase { WAITING, WAVE, INTERMISSION, ENDED }

const TARGETING := ["FurthestAlongPath", "ClosestDistance", "LowestHealth", "HighestHealth", "MostRecent"]
const FINAL_ROUND_CAP_S := 120.0

var rng := RandomNumberGenerator.new()
var time := 0.0
var phase: int = Phase.WAITING
var round_index := -1
var phase_time_left := 0.0
var players: Array = []
var enemies: Array = []
var next_enemy_id := 1
var result: Dictionary = {}

# Cosmetic records gathered since the last snapshot (sent unreliably, safe to lose).
var _shots: Array = []
var _kills: Array = []
var _hits: Array = []

var tower_types: Array = []
var enemy_types: Array = []
var stats := {"shots": 0, "kills": 0, "recycled_spawns": 0, "base_hits": 0, "placements": 0, "merges": 0}


func setup(decks: Array, seed_value: int) -> void:
	GameData.ensure_loaded()
	rng.seed = seed_value
	tower_types = GameData.towers.keys()
	tower_types.sort()
	enemy_types = GameData.enemies.keys()
	enemy_types.sort()
	players.clear()
	for i in 2:
		players.append({
			"deck": decks[i],
			"gold": int(GameData.rules.start_gold),
			"base_hp": int(GameData.rules.base_hp),
			"placed": 0,
			"towers": {},
			"schedule": [],
			"recycle_queue": [],
			"recycle_cd": 0.0,
			"damaged_this_wave": false,
			"kills": 0,
		})


func start() -> void:
	_begin_wave(0)


func next_tower_cost(p: int) -> int:
	return int(GameData.rules.tower_cost_base) + int(GameData.rules.tower_cost_step) * int(players[p].placed)


func request_place(p: int) -> Dictionary:
	if phase == Phase.ENDED or phase == Phase.WAITING:
		return {"ok": false, "reason": "not_running"}
	var pl: Dictionary = players[p]
	var cost := next_tower_cost(p)
	if pl.gold < cost:
		return {"ok": false, "reason": "gold"}
	var empty: Array = []
	for s in GameData.slot_count():
		if not pl.towers.has(s):
			empty.append(s)
	if empty.is_empty():
		return {"ok": false, "reason": "full"}
	var slot: int = empty[rng.randi_range(0, empty.size() - 1)]
	var type: String = pl.deck[rng.randi_range(0, pl.deck.size() - 1)]
	pl.gold -= cost
	pl.placed += 1
	pl.towers[slot] = {"type": type, "level": 1, "cd": 0.5, "aim": Vector2.ZERO}
	stats.placements += 1
	return {"ok": true, "slot": slot, "type": type}


func request_merge(p: int, src: int, dst: int) -> Dictionary:
	if phase == Phase.ENDED or phase == Phase.WAITING:
		return {"ok": false, "reason": "not_running"}
	var t: Dictionary = players[p].towers
	if src == dst or not t.has(src) or not t.has(dst):
		return {"ok": false, "reason": "slots"}
	var a: Dictionary = t[src]
	var b: Dictionary = t[dst]
	if a.type != b.type or a.level != b.level or int(b.level) >= int(GameData.rules.max_tower_level):
		return {"ok": false, "reason": "mismatch"}
	var deck: Array = players[p].deck
	b.level = int(b.level) + 1
	b.type = deck[rng.randi_range(0, deck.size() - 1)]
	b.cd = 0.5
	t.erase(src)
	stats.merges += 1
	return {"ok": true, "slot": dst, "type": b.type, "level": b.level}


func step(dt: float) -> void:
	if phase == Phase.WAITING or phase == Phase.ENDED:
		return
	time += dt
	phase_time_left -= dt
	if phase == Phase.WAVE:
		for p in 2:
			_spawn_tick(p, dt)
	_enemies_tick(dt)
	if phase == Phase.ENDED:
		return
	for p in 2:
		_towers_tick(p, dt)
	_check_phase()


# ---------------------------------------------------------------- waves

func _begin_wave(idx: int) -> void:
	round_index = idx
	phase = Phase.WAVE
	var rd: Dictionary = GameData.rounds[idx]
	phase_time_left = float(rd.duration_s)
	var list: Array = []
	for entry in rd.spawns:
		var type: String = entry[0]
		var n := int(entry[1]) * int(GameData.enemies[type].get("group", 1))
		for i in n:
			list.append(type)
	var window := float(rd.spawn_window_s)
	for p in 2:
		var sched: Array = []
		for i in list.size():
			sched.append({"type": list[i], "at": time + window * float(i) / max(1, list.size())})
		players[p].schedule = sched
		players[p].damaged_this_wave = false


func _is_final_round() -> bool:
	return round_index >= GameData.rounds.size() - 1


func _board_clear() -> bool:
	if not enemies.is_empty():
		return false
	for p in 2:
		if not players[p].schedule.is_empty() or not players[p].recycle_queue.is_empty():
			return false
	return true


func _check_phase() -> void:
	if phase == Phase.WAVE:
		var clear := _board_clear()
		var timed_out := phase_time_left <= 0.0
		if _is_final_round():
			# Final round resolves every enemy (with a safety cap) before scoring.
			if clear or phase_time_left <= -FINAL_ROUND_CAP_S:
				_end_wave()
				_finish_by_score("final_round")
		elif clear or timed_out:
			_end_wave()
			phase = Phase.INTERMISSION
			phase_time_left = float(GameData.rounds[round_index].intermission_s)
	elif phase == Phase.INTERMISSION and phase_time_left <= 0.0:
		_begin_wave(round_index + 1)


func _end_wave() -> void:
	for p in 2:
		var pl: Dictionary = players[p]
		pl.gold += int(GameData.rules.wave_bonus)
		if not pl.damaged_this_wave:
			pl.gold += int(GameData.rules.perfect_wave_bonus)


func _spawn_tick(p: int, dt: float) -> void:
	var pl: Dictionary = players[p]
	while not pl.schedule.is_empty() and float(pl.schedule[0].at) <= time:
		_spawn_enemy(p, pl.schedule.pop_front().type, false, 0.0)
	pl.recycle_cd -= dt
	if pl.recycle_cd <= 0.0 and not pl.recycle_queue.is_empty():
		_spawn_enemy(p, pl.recycle_queue.pop_front(), true, 0.0)
		stats.recycled_spawns += 1
		pl.recycle_cd = float(GameData.rules.recycle_spawn_interval_s)


func _spawn_enemy(board: int, type: String, recycled: bool, dist: float) -> void:
	var def: Dictionary = GameData.enemies[type]
	enemies.append({
		"id": next_enemy_id, "board": board, "type": type,
		"hp": float(def.hp), "max_hp": float(def.hp), "dist": dist,
		"recycled": recycled, "slow_t": 0.0, "slow_f": 1.0,
		"minion_cd": float(def.get("minion_interval_s", 0.0)),
	})
	next_enemy_id += 1


# ---------------------------------------------------------------- enemies

func _enemies_tick(dt: float) -> void:
	var length := BoardLayout.path_length()
	var spawned: Array = []
	var arrived: Array = []
	for e in enemies:
		var def: Dictionary = GameData.enemies[e.type]
		var f: float = e.slow_f if e.slow_t > 0.0 else 1.0
		e.slow_t = max(0.0, e.slow_t - dt)
		e.dist += float(def.speed) * f * dt
		if def.has("heal_per_s"):
			var here := BoardLayout.path_point(e.dist)
			for o in enemies:
				if o.id != e.id and o.board == e.board and o.hp < o.max_hp \
						and BoardLayout.path_point(o.dist).distance_to(here) <= float(def.heal_radius):
					o.hp = min(o.max_hp, o.hp + float(def.heal_per_s) * dt)
		if def.has("minion"):
			e.minion_cd -= dt
			if e.minion_cd <= 0.0:
				e.minion_cd = float(def.minion_interval_s)
				spawned.append([e.board, def.minion, e.dist])
		if e.dist >= length:
			arrived.append(e)
	for s in spawned:
		_spawn_enemy(s[0], s[1], false, s[2])
	for e in arrived:
		_remove_enemy(e)
		var pl: Dictionary = players[e.board]
		pl.base_hp -= int(GameData.enemies[e.type].damage)
		pl.damaged_this_wave = true
		stats.base_hits += 1
		_hits.append([e.board, e.id])
	var dead: Array = []
	for p in 2:
		if players[p].base_hp <= 0:
			dead.append(p)
	if dead.size() == 2:
		_finish_by_score("both_bases_destroyed")
	elif dead.size() == 1:
		_finish(1 - int(dead[0]), "base_destroyed")


## Enemies are Dictionaries; Array.erase/has compare them by value, so remove by id.
func _remove_enemy(e: Dictionary) -> void:
	for i in enemies.size():
		if enemies[i].id == e.id:
			enemies.remove_at(i)
			return


# ---------------------------------------------------------------- towers

func tower_damage(t: Dictionary) -> float:
	var def: Dictionary = GameData.towers[t.type]
	return float(def.damage) * pow(float(GameData.rules.merge_power_multiplier), int(t.level) - 1)


func _towers_tick(p: int, dt: float) -> void:
	var pl: Dictionary = players[p]
	for slot in pl.towers:
		var t: Dictionary = pl.towers[slot]
		t.cd -= dt
		if t.cd > 0.0:
			continue
		var def: Dictionary = GameData.towers[t.type]
		var pos := BoardLayout.slot_pos(slot)
		var target = _pick_target(p, pos, float(def.range), String(def.targeting))
		if target == null:
			t.cd = 0.0
			continue
		t.cd += 1.0 / float(def.rate)
		var tpos := BoardLayout.path_point(target.dist)
		t.aim = tpos - pos
		stats.shots += 1
		_shots.append([p, slot, target.id])
		var dmg := tower_damage(t)
		if def.has("splash_radius"):
			for e in enemies.duplicate():
				if e.board == p and BoardLayout.path_point(e.dist).distance_to(tpos) <= float(def.splash_radius):
					_damage(e, dmg, p)
		else:
			if def.has("slow_factor"):
				target.slow_f = float(def.slow_factor)
				target.slow_t = float(def.slow_time)
			_damage(target, dmg, p)


func _pick_target(p: int, pos: Vector2, rng_cm: float, mode: String):
	var best = null
	var best_score := -INF
	for e in enemies:
		if e.board != p:
			continue
		var d := BoardLayout.path_point(e.dist).distance_to(pos)
		if d > rng_cm:
			continue
		var score: float
		match mode:
			"ClosestDistance": score = -d
			"LowestHealth": score = -e.hp
			"HighestHealth": score = e.hp
			"MostRecent": score = e.id
			_: score = e.dist
		if score > best_score:
			best_score = score
			best = e
	return best


func _damage(e: Dictionary, dmg: float, killer: int) -> void:
	if e.hp <= 0.0:
		return
	var armor := float(GameData.enemies[e.type].get("armor", 0.0))
	e.hp -= dmg * (1.0 - armor)
	if e.hp > 0.0:
		return
	_remove_enemy(e)
	var def: Dictionary = GameData.enemies[e.type]
	var pl: Dictionary = players[killer]
	pl.gold += int(GameData.rules.recycled_kill_gold) if e.recycled else int(GameData.rules.kill_gold)
	pl.kills += 1
	stats.kills += 1
	var to_opponent: bool = not e.recycled and not def.get("boss", false)
	if to_opponent:
		players[1 - killer].recycle_queue.append(e.type)
	_kills.append([e.id, killer, to_opponent])


# ---------------------------------------------------------------- end

func _finish_by_score(reason: String) -> void:
	var a: Dictionary = players[0]
	var b: Dictionary = players[1]
	var winner := -1
	if a.base_hp != b.base_hp:
		winner = 0 if a.base_hp > b.base_hp else 1
	elif a.gold != b.gold:
		winner = 0 if a.gold > b.gold else 1
	_finish(winner, reason)


func _finish(winner: int, reason: String) -> void:
	phase = Phase.ENDED
	result = {
		"winner": winner, "reason": reason, "round": round_index + 1, "time": snappedf(time, 0.01),
		"base_hp": [players[0].base_hp, players[1].base_hp],
		"gold": [players[0].gold, players[1].gold],
		"towers": [players[0].towers.size(), players[1].towers.size()],
		"kills": [players[0].kills, players[1].kills],
		"stats": stats.duplicate(),
	}


# ---------------------------------------------------------------- replication

## Full-state snapshot in compact arrays. Type names are sent as indices into the sorted
## tower/enemy key lists, which both sides derive from the same data files.
func snapshot() -> Dictionary:
	var ps: Array = []
	var tws: Array = []
	for p in 2:
		var pl: Dictionary = players[p]
		ps.append([pl.gold, pl.base_hp, next_tower_cost(p), pl.recycle_queue.size(), pl.kills])
		var list: Array = []
		for slot in pl.towers:
			var t: Dictionary = pl.towers[slot]
			list.append([slot, tower_types.find(t.type), t.level, snappedf(t.aim.angle(), 0.01) if t.aim != Vector2.ZERO else 9.0])
		tws.append(list)
	var ens: Array = []
	for e in enemies:
		var flags := (1 if e.recycled else 0) | (2 if e.slow_t > 0.0 else 0)
		ens.append([e.id, e.board, enemy_types.find(e.type), snappedf(e.dist, 0.1), snappedf(e.hp / e.max_hp, 0.01), flags])
	var snap := {
		"t": snappedf(time, 0.001), "ph": phase, "r": round_index, "rn": GameData.rounds.size(),
		"tl": snappedf(max(phase_time_left, 0.0), 0.1), "p": ps, "tw": tws, "en": ens,
		"sh": _shots, "k": _kills, "h": _hits,
	}
	if not result.is_empty():
		snap["res"] = result
	_shots = []
	_kills = []
	_hits = []
	return snap
