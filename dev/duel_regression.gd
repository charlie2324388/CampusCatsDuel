extends SceneTree

const STEP := 1.0 / 60.0
const Controls = preload("res://scripts/duel_input.gd")
const F = preload("res://scripts/fighter.gd")
const IDS := ["mirinda", "doctor", "orange"]
var errors := 0
var assertions := 0
var arena: Node2D

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		errors += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	arena = Node2D.new()
	root.add_child(arena)
	await _keys()
	_guards()
	_meters()
	_simultaneous_and_dodge()
	_movement()
	_cpu()
	arena.free()
	if not OS.get_cmdline_user_args().has("--core-only"):
		await _match_flow()
	print("Duel regression: %d checks, %d failures" % [assertions, errors])
	quit(1 if errors else 0)

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await process_frame

func _keys() -> void:
	var pad = Controls.new()
	var mapping := [
		[0, KEY_A, "left"], [0, KEY_D, "right"], [0, KEY_W, "jump"], [0, KEY_S, "down"],
		[0, KEY_J, "light"], [0, KEY_K, "heavy"], [0, KEY_U, "special"], [0, KEY_I, "super"], [0, KEY_L, "throw"],
		[1, KEY_LEFT, "left"], [1, KEY_RIGHT, "right"], [1, KEY_UP, "jump"], [1, KEY_DOWN, "down"],
		[1, KEY_KP_1, "light"], [1, KEY_KP_2, "heavy"], [1, KEY_KP_4, "special"], [1, KEY_KP_5, "super"],
		[1, KEY_COMMA, "light"], [1, KEY_PERIOD, "heavy"], [1, KEY_BRACKETLEFT, "special"], [1, KEY_BRACKETRIGHT, "super"], [1, KEY_SLASH, "throw"], [1, KEY_KP_3, "throw"],
	]
	var keys_ok := true
	for pair in mapping:
		await _key(pair[1], true)
		var bound := bool(pad.read_player(pair[0])[pair[2]]) and not bool(pad.read_player(1 - pair[0])[pair[2]])
		if not bound: printerr("Unmatched pressed binding ",pair)
		keys_ok = keys_ok and bound
		await _key(pair[1], false)
		keys_ok = keys_ok and not bool(pad.read_player(pair[0])[pair[2]])
	check(keys_ok, "both physical keyboards, keypad and punctuation aliases")
	await _key(KEY_A, true)
	await _key(KEY_KP_2, true)
	check(pad.read_player(0).left and pad.read_player(1).heavy, "P1 and P2 can hold independent inputs on the same frame")
	await _key(KEY_A, false)
	await _key(KEY_KP_2, false)

func _pair(a_id: String = "mirinda", b_id: String = "doctor") -> Array:
	var a = F.new()
	var b = F.new()
	a.setup(a_id, 0)
	b.setup(b_id, 1)
	arena.add_child(a)
	arena.add_child(b)
	return [a, b]

func _dispose(pair: Array) -> void:
	for actor in pair:
		actor.free()

func _down(names: Array) -> Dictionary:
	var held := {}
	for key in Controls.MOVES:
		held[key] = key in names
	return held

func _tick(pair: Array, one: Array = [], two: Array = []) -> void:
	F.tick_pair(pair[0], pair[1], _down(one), _down(two), STEP)

func _hit_attempt(defense: Array, reversed_sides: bool = false, airborne: bool = false) -> Dictionary:
	var p := _pair()
	p[0].position = Vector2(570 if reversed_sides else 702, 442)
	p[1].position = Vector2(495 if reversed_sides else 777, 442)
	var received := []
	p[0].impact.connect(func(_point, _kind, guarded): received.append(guarded))
	if airborne:
		_tick(p, [], ["jump"])
	for i in range(27):
		_tick(p, ["light"] if i == 0 else [], defense)
	var answer := {"hp": int(p[1].hp), "max_hp":int(p[1].max_hp), "guarded": true in received, "energy": float(p[1].energy)}
	_dispose(p)
	return answer

func _guards() -> void:
	var bare := _hit_attempt([])
	var back := _hit_attempt(["right"])
	var down := _hit_attempt(["down"])
	check(bare.hp < bare.max_hp, "a grounded jab lands on the opponent")
	check(not back.guarded and back.hp == bare.hp, "walking backward in range takes the same damage as standing")
	check(down.guarded and down.hp == down.max_hp and down.energy > 0.0, "holding down guards jab damage and earns meter")
	check(_hit_attempt(["down"], true).guarded, "holding down still guards after swapping sides")
	var air := _hit_attempt(["down"], false, true)
	check(not air.guarded and air.hp < air.max_hp, "holding down in the air cannot guard an incoming jab")
	var counter := _hit_attempt(["down", "heavy"])
	check(not counter.guarded and counter.hp < counter.max_hp, "attacking while holding down opens a punishable startup")

	var p := _pair("doctor", "doctor")
	var original_x: float = p[1].position.x
	var standing_height: float = p[1]._body_height()
	for i in range(15):
		_tick(p, [], ["down", "left"])
	check(p[1].state == "guard" and p[1].grounded and is_equal_approx(original_x, p[1].position.x), "down enters the grounded standing guard pose and holds position")
	check(is_equal_approx(p[1]._body_height(), standing_height), "standing guard keeps the full idle hurtbox height")
	for i in range(12):
		_tick(p, [], ["left"])
	check(p[1].state == "walk" and p[1].position.x < original_x - 10, "release down and walk immediately")
	p[0].reset_round()
	p[1].reset_round()
	p[0].position = Vector2(300, 394)
	p[0].velocity.y = -150
	p[0].grounded = false
	p[0].energy = 100
	p[1].position.x = 570
	var high_beam := []
	p[0].impact.connect(func(_point, _kind, guarded): high_beam.append(guarded))
	for i in range(45):
		_tick(p, ["special"] if i == 0 else [], ["down"])
	check(true in high_beam and p[1].hp < p[1].max_hp, "standing guard intercepts a head-height laser and receives chip")
	_dispose(p)

func _meters() -> void:
	for id in IDS:
		for move in ["special", "super"]:
			var cost := 100 if move == "special" else 200
			for enough in [false, true]:
				var p := _pair(id, "doctor")
				p[0].energy = cost if enough else cost - 1
				var performed := []
				p[0].move_started.connect(func(kind): performed.append(kind))
				_tick(p, [move])
				_tick(p)
				check((move in performed) == enough and int(p[0].energy) == (0 if enough else cost - 1), "%s %s %s" % [id, move, "spends exact meter" if enough else "refuses insufficient meter"])
				_dispose(p)
	# Normal contact provides a route to the next bar.
	var p := _pair()
	p[0].position = Vector2(450,442)
	p[1].position = Vector2(520,442)
	for i in range(30):
		_tick(p, ["heavy"] if i == 1 else [])
	check(p[1].hp < p[1].max_hp and p[0].energy > 0, "heavy hits deal damage and gain meter")
	_dispose(p)

func _simultaneous_and_dodge() -> void:
	var p := _pair("doctor", "doctor")
	p[0].position = Vector2(430,442)
	p[1].position = Vector2(520,442)
	p[0].hp = 6
	p[1].hp = 6
	for i in range(20):
		_tick(p, ["light"] if i == 1 else [], ["light"] if i == 1 else [])
	check(p[0].hp == 0 and p[1].hp == 0, "simultaneous jabs resolve a real double KO")
	_dispose(p)
	for id in IDS:
		p = _pair("doctor",id)
		p[0].energy = 200
		p[0].position.x = 220
		p[1].position.x = 710
		var leapt := false
		for i in range(170):
			var jump_now := false
			if not leapt and not p[0].projectiles.is_empty():
				var gap: float=p[1].position.x-p[0].projectiles[0].point.x
				if gap <= 215.0:
					leapt = true
					jump_now = true
			_tick(p,["super"] if i==1 else [],["jump"] if jump_now else [])
		check(leapt and p[1].hp==p[1].max_hp and p[0].energy==0 and p[0].projectiles.is_empty(),"%s jumps over the traveling magnetic wave" % id)
		_dispose(p)

func _movement() -> void:
	var p := _pair()
	var clear := true
	for i in range(260):
		_tick(p, ["right"], ["left"])
		clear = clear and p[0].position.x + 20 <= p[1].position.x
	check(clear, "grounded fighters cannot walk through each other")
	for i in range(260):
		_tick(p, ["left"], ["right"])
	check(p[0].position.x >= 83.0 and p[1].position.x <= 877.0 and p[0].position.x < 130.0 and p[1].position.x > 830.0, "both arena edges hold fighters on screen")
	p[0].reset_round()
	p[1].reset_round()
	p[0].position = Vector2(390,442)
	p[1].position = Vector2(465,442)
	for i in range(64):
		_tick(p, ["right","jump"] if i == 0 else ["right"])
	check(p[0].position.x > p[1].position.x and p[0].facing == -1 and p[1].facing == 1, "jump-over changes both facing directions")
	check(p[0].grounded and absf(p[0].position.y - 442.0) < 1.0, "jumper returns to the arena floor")
	_dispose(p)

func _cpu() -> void:
	var p := _pair()
	var bot = Controls.new()
	bot.rng.seed = 12937
	bot.reset_round()
	var reacted_early := false
	for i in range(8):
		var ai: Dictionary = bot.read_cpu(p[1], p[0], STEP)
		reacted_early = reacted_early or true in ai.values()
	check(not reacted_early, "CPU waits for a past observation before acting")
	var twin = Controls.new()
	bot.rng.seed = 334
	twin.rng.seed = 334
	bot.reset_round()
	twin.reset_round()
	for i in range(22):
		bot.read_cpu(p[1], p[0], STEP)
		twin.read_cpu(p[1], p[0], STEP)
	# Give only one CPU a teleporting opponent who is suddenly doing a super.
	# Before human reaction time elapses both pilots must act identically.
	var normal_x: float = p[0].position.x
	var fair := true
	for i in range(8):
		p[0].position.x = normal_x
		p[0].state = "idle"
		var original: Dictionary = bot.read_cpu(p[1], p[0], STEP)
		p[0].position.x = p[1].position.x + 20.0
		p[0].state = "super"
		var changed: Dictionary = twin.read_cpu(p[1], p[0], STEP)
		fair = fair and original == changed
	check(fair, "same-frame position and super changes cannot alter CPU input early")
	_dispose(p)
	p=_pair("mirinda","orange")
	p[0].position.x=390
	p[1].position.x=509
	var guard_pilot=Controls.new()
	guard_pilot.rng.seed=806
	guard_pilot.reset_round()
	var throws: Array=[]
	p[1].impact.connect(func(_point,kind,blocked):
		if not blocked: throws.append(kind))
	for frame in range(600):
		var bot_input: Dictionary=guard_pilot.read_cpu(p[1],p[0],STEP)
		F.tick_pair(p[0],p[1],_down(["down"]),bot_input,STEP)
		if "throw" in throws: break
	check("throw" in throws, "CPU breaks a sustained standing guard with a close throw")
	_dispose(p)
	# A close target gives the easy CPU repeated opportunities to act.
	p = _pair("mirinda", "doctor")
	p[0].position.x = 475
	p[1].position.x = 565
	var easy = Controls.new()
	easy.easy_cpu = true
	easy.rng.seed = 7261
	easy.reset_round()
	var swings := 0
	var last_swing := -1000
	var has_openings := true
	var uses_advanced := false
	for frame in range(1800):
		p[1].energy = 200
		var input: Dictionary = easy.read_cpu(p[1], p[0], STEP)
		if input.light or input.heavy or input.special:
			has_openings = has_openings and frame >= 22 and frame - last_swing >= 52
			swings += 1
			last_swing = frame
		uses_advanced = uses_advanced or input.throw or input.super
	check(swings >= 5 and has_openings and not uses_advanced, "easy CPU fights with spaced single strikes and leaves counterattack windows")
	_dispose(p)
	var attacks := {}
	var guarded_without_stepping := false
	var retreated_without_guarding := false
	for index in range(IDS.size()):
		p = _pair(IDS[index], IDS[(index+1)%IDS.size()])
		var pilot_a = Controls.new()
		var pilot_b = Controls.new()
		pilot_a.rng.seed = 110 + index
		pilot_b.rng.seed = 420 + index
		pilot_a.reset_round()
		pilot_b.reset_round()
		p[0].energy = 200
		p[1].energy = 120
		for i in range(3600):
			var a: Dictionary = pilot_a.read_cpu(p[0],p[1],STEP)
			var b: Dictionary = pilot_b.read_cpu(p[1],p[0],STEP)
			for input in [a,b]:
				for key in ["jump","light","heavy","special","super"]:
					if input[key]: attacks[key] = true
			F.tick_pair(p[0],p[1],a,b,STEP)
			guarded_without_stepping = guarded_without_stepping or (a.down and not a.left and not a.right)
			var toward: int = p[0].facing
			var step_axis := int(a.right) - int(a.left)
			retreated_without_guarding = retreated_without_guarding or (step_axis * toward < 0 and not a.down and p[0].grounded)
			if p[0].hp <= 0 or p[1].hp <= 0: break
		check(p[0].hp < p[0].max_hp and p[1].hp < p[1].max_hp, "%s CPU duel produces reciprocal hits" % IDS[index])
		_dispose(p)
	check(attacks.size() == 5, "seeded CPU rounds exercise jump, basics and both meter costs")
	check(guarded_without_stepping and retreated_without_guarding, "CPU guards by pressing down and takes independent backward steps")

func _match_flow() -> void:
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	var instance = load(scene_path).instantiate()
	root.add_child(instance)
	await process_frame
	check(instance.state == "select", "new session enters character select")
	instance.set_slot(0)
	instance.choose(1)
	instance.set_slot(1)
	instance.choose(2)
	var cpu_before: bool = instance.vs_cpu
	instance.toggle_mode()
	check(instance.vs_cpu != cpu_before, "mode selector changes CPU / local opponent")
	if not instance.vs_cpu: instance.toggle_mode()
	instance.start_match()
	check(instance.fighters.size() == 2 and instance.fighters[0].fighter_id == "doctor" and instance.fighters[1].fighter_id == "orange", "selected cats appear together in the arena")
	# The match controller advances these checks through its normal physics loop.
	await _until(instance, "fight")
	check(instance.state == "fight" and instance.round_no == 1, "countdown enters a live round")
	await _key(KEY_P, true)
	await _key(KEY_P, false)
	var clock_at_pause: float = instance.seconds_left
	for i in range(15): await physics_frame
	check(instance.state == "pause" and is_equal_approx(instance.seconds_left, clock_at_pause), "physical P pauses the clock and movement")
	await _key(KEY_P, true)
	await _key(KEY_P, false)
	check(instance.state == "fight", "physical P resumes the same round")
	var initial_x: float = instance.fighters[1].position.x
	for i in range(90): await physics_frame
	check(absf(initial_x - instance.fighters[1].position.x) > 12.0, "single-player match drives the actual CPU fighter")

	# Expired timer at equal health does not consume a best-of-three win.
	instance.fighters[0].reset_round()
	instance.fighters[1].reset_round()
	instance.seconds_left = 0.0
	await _until(instance, "round_end")
	check(instance.state == "round_end" and int(instance.wins[0]) == 0 and int(instance.wins[1]) == 0, "equal HP timeout awards neither player")
	await _until(instance, "fight")
	check(instance.state == "fight" and instance.round_no == 1, "draw repeats the same round")
	
	# Test the controller's response to a double KO produced by live fighter logic.
	var a = instance.fighters[0]
	var b = instance.fighters[1]
	a.reset_round()
	b.reset_round()
	a.position.x = 430.0
	b.position.x = 520.0
	a.hp = 6
	b.hp = 6
	for i in range(12):
		F.tick_pair(a, b, _down(["light"]) if i == 1 else _down([]), _down(["light"]) if i == 1 else _down([]), STEP)
	await _until(instance, "round_end")
	check(a.hp == 0 and b.hp == 0 and int(instance.wins[0]) == 0 and int(instance.wins[1]) == 0, "double KO carries no win into the replay")
	await _until(instance, "fight")
	
	# The first timeout goes to P1, the next to P2, the decider to P1.
	for idx in range(3):
		var winner := 1 if idx == 1 else 0
		instance.fighters[0].hp = 85 if winner == 0 else 30
		instance.fighters[1].hp = 85 if winner == 1 else 30
		instance.seconds_left = 0.0
		await _until(instance, "match_end" if idx == 2 else "round_end")
		if idx < 2:
			check(instance.round_winner == winner, "unequal timeout awards round %d to the higher HP" % (idx + 1))
			await _until(instance, "fight")
			check(instance.round_no == idx + 2 and instance.fighters[0].hp == instance.fighters[0].max_hp and instance.fighters[1].hp == instance.fighters[1].max_hp, "next round restores health and advances numbering")
	check(instance.state == "match_end" and instance.match_winner == 0 and int(instance.wins[0]) == 2 and int(instance.wins[1]) == 1, "first to two wins settles a 2-1 match")
	instance.rematch()
	await _until(instance, "fight")
	check(instance.state == "fight" and instance.round_no == 1 and int(instance.wins[0]) == 0 and int(instance.wins[1]) == 0 and instance.fighters[0].hp == instance.fighters[0].max_hp and instance.fighters[1].energy == 0.0, "rematch resets wins, round, HP, and meter")
	check(instance.fighters[0].fighter_id == "doctor" and instance.fighters[1].fighter_id == "orange", "rematch keeps the selected lineup")
	instance.to_select()
	check(instance.state == "select", "return to character select")
	instance.toggle_mode()
	check(not instance.vs_cpu, "menu can start a two-human match")
	instance.start_match()
	await _until(instance, "fight")
	var old_a: float = instance.fighters[0].position.x
	var old_b: float = instance.fighters[1].position.x
	await _key(KEY_D, true)
	await _key(KEY_LEFT, true)
	for i in range(24): await physics_frame
	await _key(KEY_D, false)
	await _key(KEY_LEFT, false)
	check(instance.fighters[0].position.x > old_a + 25 and instance.fighters[1].position.x < old_b - 25, "actual PvP scene moves both cats from one keyboard")
	await _key(KEY_S, true)
	await _key(KEY_DOWN, true)
	for i in range(6): await physics_frame
	check(instance.fighters[0].state == "guard" and instance.fighters[1].state == "guard", "physical S and Down put both local players into standing guard")
	await _key(KEY_S, false)
	await _key(KEY_DOWN, false)

	instance.to_select()
	instance.free()

func _until(game, desired: String) -> void:
	for i in range(540):
		if game.state == desired:
			return
		await physics_frame
	printerr("Timed out waiting for ", desired, "; game is ", game.state)
