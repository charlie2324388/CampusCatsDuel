extends RefCounted

const MOVES := ["left", "right", "down", "jump", "light", "heavy", "special", "super", "throw"]
const KEYSETS := [
	[[KEY_A], [KEY_D], [KEY_S], [KEY_W], [KEY_J], [KEY_K], [KEY_U], [KEY_I], [KEY_L]],
	[[KEY_LEFT], [KEY_RIGHT], [KEY_DOWN], [KEY_UP], [KEY_KP_1, KEY_COMMA], [KEY_KP_2, KEY_PERIOD], [KEY_KP_4, KEY_BRACKETLEFT], [KEY_KP_5, KEY_BRACKETRIGHT], [KEY_KP_3, KEY_SLASH]],
]
const ATTACKS := ["light", "heavy", "special", "super"]

var rng := RandomNumberGenerator.new()
var _clock := 0.0
var _reaction := 0.18
var _think_in := 0.0
var _sample_in := 0.0
var _jump_ready := 0.0
var _throw_ready := 0.0
var _guard_seen_since := -1.0
var _trail: Array[Dictionary] = []
var _seen: Dictionary = {}
var _walk := 0
var _guard_down := false
var _planned_route := ""
var _last_follow_route := ""

func _init() -> void:
	rng.randomize()
	for seat in range(2):
		for index in range(MOVES.size()):
			var action := _action_name(seat, MOVES[index])
			if InputMap.has_action(action):
				continue
			InputMap.add_action(action)
			for key in KEYSETS[seat][index]:
				var binding := InputEventKey.new()
				binding.physical_keycode = key
				InputMap.action_add_event(action, binding)
	reset_round()

func _action_name(seat: int, move: String) -> StringName:
	return StringName("duel_p%d_%s" % [seat + 1, move])

func reset_round() -> void:
	_clock = 0.0
	_reaction = rng.randf_range(0.16, 0.21)
	_think_in = 0.0
	_sample_in = 0.0
	_jump_ready = 0.0
	_throw_ready = 0.0
	_guard_seen_since = -1.0
	_planned_route = ""
	_last_follow_route = ""
	_trail.clear()
	_seen.clear()
	_walk = 0
	_guard_down = false

func read_player(seat: int) -> Dictionary:
	var result := {}
	for move in MOVES:
		result[move] = Input.is_action_pressed(_action_name(seat, move))
	return result

func _blank() -> Dictionary:
	return {"left": false, "right": false, "down": false, "jump": false,
		"light": false, "heavy": false, "special": false, "super": false, "throw": false}

func read_cpu(actor, opponent, delta: float) -> Dictionary:
	var action := _blank()
	_clock += delta
	_sample_in -= delta
	_think_in -= delta
	if _sample_in <= 0.0:
		_sample_in = 0.05
		_trail.append({"time": _clock, "position": opponent.position, "state": opponent.state, "body_width": opponent.config.width,
			"waves": opponent.projectiles.duplicate(true),
			"guarding": opponent.state=="guard",
			"air": not opponent.grounded, "recovering": not opponent.attack_kind.is_empty() and opponent.move_time>opponent.startup+opponent.active_time,
			"recovery_left": maxf(0.0,opponent.move_duration-opponent.move_time)})
	while not _trail.is_empty() and float(_trail[0].time) <= _clock - _reaction:
		_seen = _trail.pop_front()
		if not _seen.guarding:
			_guard_seen_since=-1.0
		elif _guard_seen_since<0.0:
			_guard_seen_since=_seen.time
	if _seen.is_empty() or actor.hp <= 0:
		return action
	if _think_in <= 0.0:
		_think_in = rng.randf_range(0.13, 0.23)
		_decide(actor, action)
	action.left = _walk < 0
	action.right = _walk > 0
	action.down = _guard_down and actor.grounded
	return action

func _jump(action: Dictionary) -> void:
	action.jump = true
	_jump_ready = _clock + rng.randf_range(1.05, 2.1)

func _decide(actor, action: Dictionary) -> void:
	_walk = 0
	_guard_down = false
	var seen_pos: Vector2 = _seen.position
	var dx := seen_pos.x - float(actor.position.x)
	var toward := 1 if dx > 0.0 else (-1 if dx < 0.0 else int(actor.facing))
	var gap := absf(dx)
	var can_jump: bool = actor.grounded and _clock >= _jump_ready
	var incoming := str(_seen.state)
	if actor.launched or actor.state in ["throw","throw_hold","throw_recover","grabbed"]:
		return
	if actor.stun_left > 0.0:
		if gap < 205.0:
			_guard_down = actor.grounded
		return
	if actor.state in ATTACKS:
		_think_in = 0.055
		var path: String = actor.combo_route
		if actor.normal_confirmed and path.length()>0 and path!=_last_follow_route and _planned_route.begins_with(path) and path.length()<_planned_route.length():
			var follow: String = _planned_route[path.length()]
			if follow in ["J","K"] or actor.energy>=(100.0 if follow=="U" else 200.0):
				action[{"J":"light","K":"heavy","U":"special","I":"super"}[follow]]=true
				_last_follow_route=path
		return
	_last_follow_route=""
	for wave in _seen.waves:
		var ahead: float=(actor.position.x-wave.point.x)*wave.direction
		var wave_height: float=absf((actor.position.y-62.0)-wave.point.y)
		if actor.grounded and ahead>15.0 and ahead<357.0 and wave_height<95.0:
			if can_jump and ahead>160.0 and rng.randf()<0.45:
				_jump(action)
			else:
				_guard_down=true
			return
	var throw_range: float=actor.config.width+_seen.body_width+15.0
	if actor.grounded and not _seen.air and _guard_seen_since>=0.0 and _seen.time-_guard_seen_since>=0.13 and _clock>=_throw_ready:
		if gap>throw_range and gap<215.0:
			_walk=toward
			_think_in=0.08
			return
		if gap<=throw_range and rng.randf()<0.7:
			action.throw=true
			_throw_ready=_clock+1.10
			return
	var recovery_seen: bool=_seen.recovering
	if recovery_seen and gap<143.0 and actor.grounded and absf(seen_pos.y-actor.position.y)<75.0:
		var opportunity: float=_seen.recovery_left-(_clock-float(_seen.time))
		if opportunity>0.11 and rng.randf()<0.73:
			if opportunity>0.20:
				action.heavy=true
				_planned_route="KKK"
			else:
				action.light=true
				_planned_route="JJU" if actor.energy>=75 else "JJJK"
			_think_in=0.08
			return
	var threatened := incoming in ATTACKS and not recovery_seen and (gap <= 168.0 or incoming in ["special", "super"])
	if threatened and rng.randf() < 0.64:
		if can_jump and gap > 125.0 and rng.randf() < 0.32:
			_walk = toward if gap > 260.0 else -toward
			_jump(action)
		else:
			_guard_down = actor.grounded
		return
	var is_doctor: bool = actor.fighter_id == "doctor"
	var super_reach: float={"doctor":590.0,"orange":300.0,"taffy":158.0,"pudding":218.0}.get(actor.fighter_id,198.0)
	if actor.grounded and actor.energy >= 200 and gap < super_reach and rng.randf() < 0.72:
		action.super = true
		return
	var tech_reach := 468.0 if is_doctor else 197.0
	var air_gap := absf(seen_pos.y - float(actor.position.y))
	if actor.grounded and actor.energy >= 100 and gap < tech_reach and air_gap < 82.0:
		var spend := 0.42 if actor.hp < actor.max_hp*0.45 or gap > 132.0 else 0.24
		if rng.randf() < spend:
			action.special = true
			return
	if gap > maxf(130.0,actor.config.width+_seen.body_width+8.0):
		_walk = toward
		if can_jump and gap < 350.0 and rng.randf() < 0.15:
			_jump(action)
		return
	if air_gap > 70.0 and _seen.air:
		if can_jump and rng.randf() < 0.45:
			_walk = toward
			_jump(action)
		else:
			_guard_down = actor.grounded
		return
	var choice := rng.randf()
	if choice < 0.08:
		_guard_down = actor.grounded
	elif choice < 0.15:
		_walk = -toward
	elif choice < 0.22 and can_jump:
		_walk = toward
		_jump(action)
	elif choice < 0.52:
		action.heavy = true
		_planned_route = "KKI" if actor.energy>=160 and rng.randf()<0.5 else "KKK"
		_think_in = 0.08
	else:
		action.light = true
		if actor.energy>=150 and rng.randf()<0.52: _planned_route="JJI"
		elif actor.energy>=60 and rng.randf()<0.4: _planned_route="JJU"
		else: _planned_route="JJJJ" if rng.randf()<0.6 else "JJJK"
		_think_in = 0.08

