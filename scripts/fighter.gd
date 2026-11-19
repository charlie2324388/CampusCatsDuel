extends Node2D

signal move_started(kind: String)
signal impact(point: Vector2, kind: String, blocked: bool)
signal knocked_out()
signal wave_launched(kind: String)
signal throw_teched(point: Vector2)

const FLOOR_Y := 442.0
const LEFT_EDGE := 85.0
const RIGHT_EDGE := 875.0
const GRAVITY := 1480.0
const JUMP := 681.0
const MAX_ENERGY := 200.0
const BASE_HEALTH := 170
const COMBO_DAMAGE := [1.0, 1.0, 0.8, 0.6]
const ATTACKS := ["light", "heavy", "special", "super"]
const BUTTON_LETTER := {"light":"J", "heavy":"K", "special":"U", "super":"I"}
# Each entry is a real follow-up with its own startup, damage, reach and knockback.
const FOLLOW_UPS := {
	"JJ":   {"startup":0.052,"damage":5,"reach":108.0,"push":65.0,"stun":0.19},
	"JJJ":  {"startup":0.063,"damage":5,"reach":113.0,"push":68.0,"stun":0.20},
	"JJJJ": {"startup":0.048,"damage":9,"reach":118.0,"push":155.0,"stun":0.23},
	"JJJK": {"startup":0.090,"damage":13,"reach":128.0,"push":95.0,"stun":0.31,"lift":248.0},
	"KK":   {"startup":0.118,"damage":10,"reach":136.0,"push":110.0,"stun":0.28},
	"KKK":  {"startup":0.142,"damage":17,"reach":146.0,"push":345.0,"stun":0.34}
}
const ANIM := ["idle", "walk", "attack", "jump", "hurt", "special", "super", "guard", "heavy"]
const STATS := {
	"mirinda": {"speed":292.0, "width":57.0, "anchor":30.0, "height":100.0, "tint":Color("#ffab52")},
	"doctor": {"speed":259.0, "width":55.0, "anchor":27.0, "height":104.0, "tint":Color("#68e4d1")},
	"taffy": {"speed":197.0,"width":66.0,"anchor":24.0,"height":114.0,"tint":Color("#efbd79")},
	"pudding": {"speed":335.0,"width":51.0,"anchor":24.0,"height":103.0,"tint":Color("#8ee2ee")},
	"orange": {"speed":222.0, "width":60.0, "anchor":30.0, "height":93.0, "tint":Color("#bcabff")}
}
# Seconds and pixels. Normal moves share controls and frame rules.
const THROW_DAMAGE := 12
const GRIP_TIME := 0.22
const THROW_MARGIN := 18.0
const THROW_TECH_WINDOW := 0.05
const NORMALS := {
	"throw": {"startup":0.11,"active":0.05,"recovery":0.36,"damage":THROW_DAMAGE},
	"light": {"startup":0.065, "active":0.085, "recovery":0.14, "damage":6, "reach":96.0, "push":96.0, "stun":0.14},
	"heavy": {"startup":0.15, "active":0.105, "recovery":0.235, "damage":12, "reach":120.0, "push":210.0, "stun":0.235}
}
# Recovery after a block starts immediately and leaves time for a close-range heavy punish.
# Horizontal speed and upward impulse in arena pixels per second.
const SUPER_LAUNCH := {"orange":Vector2(525,580),"mirinda":Vector2(255,640),"doctor":Vector2(545,490),"taffy":Vector2(460,600),"pudding":Vector2(315,590)}
const BLOCK_RECOVERY := {"mirinda":[0.54,0.73],"doctor":[0.61,0.79],"orange":[0.62,0.84],"taffy":[0.64,0.80],"pudding":[0.53,0.70]}
const SKILLS := {
	"taffy":{
		"special":{"startup":0.15,"active":0.145,"recovery":0.25,"damage":19,"reach":111.0,"push":260.0,"stun":0.25,"dash":345.0},
		"super":{"startup":0.235,"active":0.20,"recovery":0.50,"damage":35,"reach":145.0,"push":295.0,"stun":0.36,"dash":135.0}
	},
	"pudding":{
		"special":{"startup":0.092,"active":0.16,"recovery":0.20,"damage":13,"reach":97.0,"push":150.0,"stun":0.18,"dash":525.0},
		"super":{"startup":0.138,"active":0.45,"recovery":0.32,"damage":8,"reach":112.0,"push":60.0,"stun":0.24}
	},
	"mirinda": {
		"special":{"startup":0.11,"active":0.24,"recovery":0.19,"damage":16,"reach":94.0,"push":220.0,"stun":0.25,"dash":485.0},
		"super":{"startup":0.16,"active":0.43,"recovery":0.27,"damage":5,"reach":100.0,"push":62.0,"stun":0.17,"dash":355.0}
	},
	"doctor": {
		"special":{"startup":0.19,"active":0.105,"recovery":0.28,"damage":14,"reach":526.0,"push":140.0,"stun":0.19},
		"super":{"startup":0.30,"active":0.145,"recovery":0.32,"damage":30,"reach":74.0,"push":265.0,"stun":0.32}
	},
	"orange": {
		"special":{"startup":0.13,"active":0.37,"recovery":0.23,"damage":17,"reach":91.0,"push":245.0,"stun":0.24,"dash":515.0},
		"super":{"startup":0.19,"active":0.63,"recovery":0.30,"damage":32,"reach":110.0,"push":398.0,"stun":0.39,"dash":665.0}
	}
}

static var frame_cache := {}
var fighter_id := "mirinda"
var side_index := 0
var max_hp := BASE_HEALTH
var hp := BASE_HEALTH
var energy := 0.0
var facing := 1
var state := "idle"
var grounded := true
var velocity := Vector2.ZERO
var stun_left := 0.0
var hitstop_left := 0.0
var move_time := 0.0
var projectiles: Array[Dictionary] = []
var last_block_recovery := false
var last_pudding_hit := 0
var pudding_braked := false
var last_launch := false
var launched := false
var _launch_direction := 1
var last_projectile_hit := 0
var last_projectile_direction := 1
var last_impact_route := ""
var _grip_gap := 0.0
var _grip_pull := 0.0
var _cast_id := 0
var _wave_launched := false
var move_duration := 0.0
var startup := 0.0
var active_time := 0.0
var attack_kind := ""
var wins := 0

var config: Dictionary = STATS["mirinda"]
var move_data := {}
var _buttons := {}
var _previous := {}
# Public readouts used by the HUD and CPU. The hit count excludes guarded blows.
var combo_route := ""
var normal_confirmed := false
var combo_hits := 0
var _received_hits := 0
# Remember each attack in the current uninterrupted string. A later pulse of an
# already counted projectile keeps that move's original multiplier.
var _combo_damage_steps := {}
var _input_buffer: Array[Dictionary] = []
var _last_hit_pulse := -1
var _anim_age := 0.0
var _glow := 0.0
var _ready_for_round := false

func setup(id: String, index: int) -> void:
	fighter_id = id if STATS.has(id) else "mirinda"
	side_index = clampi(index, 0, 1)
	config = STATS[fighter_id]
	_load_clips()
	reset_round()

func reset_round() -> void:
	hp = max_hp
	energy = 0.0
	facing = 1 if side_index == 0 else -1
	position = Vector2(255.0 if side_index == 0 else 705.0, FLOOR_Y)
	grounded = true
	velocity = Vector2.ZERO
	stun_left = 0.0
	hitstop_left = 0.0
	_received_hits = 0
	_combo_damage_steps.clear()
	projectiles.clear()
	last_block_recovery = false
	last_pudding_hit=0
	pudding_braked=false
	last_launch = false
	launched = false
	last_projectile_hit = 0
	last_impact_route = ""
	_wave_launched = false
	attack_kind = ""
	move_data = {}
	move_time = 0.0
	move_duration = 0.0
	startup = 0.0
	active_time = 0.0
	_last_hit_pulse = -1
	_buttons.clear()
	_previous.clear()
	_input_buffer.clear()
	_clear_combo()
	_glow = 0.0
	_anim_age = 0.0
	state = "idle"
	_ready_for_round = true
	queue_redraw()

# Advance both players from one authoritative physics clock. Both collision
# packets are captured before damage interrupts either attack.
static func tick_pair(a, b, a_buttons: Dictionary, b_buttons: Dictionary, delta: float) -> void:
	if delta <= 0.0 or a == null or b == null: return
	a._capture(a_buttons)
	b._capture(b_buttons)
	var freeze: float = maxf(a.hitstop_left, b.hitstop_left)
	if freeze > 0.0:
		var used := minf(delta, freeze)
		a.hitstop_left = freeze - used
		b.hitstop_left = freeze - used
		delta -= used
		if delta < 0.00001: return
	if a.state=="throw_hold" and b.state=="grabbed":
		a._carry_throw(b,delta)
		return
	if b.state=="throw_hold" and a.state=="grabbed":
		b._carry_throw(a,delta)
		return
	# A reset or round interruption may have released only one participant.
	a.release_grip()
	b.release_grip()
	var old_gap: float = b.position.x - a.position.x
	var ax: float = a.position.x
	var bx: float = b.position.x
	a._advance(bx, delta)
	b._advance(ax, delta)
	_resolve_push(a,b,old_gap)
	# Read both attacks after advancing both players and use the same snapshot
	# for priority. Neither side gets to interrupt the other's startup first.
	a._advance_wave(delta)
	b._advance_wave(delta)
	_resolve_waves(a,b)
	var one: Dictionary = a._first_contact(b)
	var two: Dictionary = b._first_contact(a)
	if not one.is_empty() or not two.is_empty():
		# Commit HP, gauge and hit reaction on both sides before callbacks.
		if not one.is_empty(): b._receive(one)
		if not two.is_empty(): a._receive(two)
		if not one.is_empty(): a._confirm(one)
		if not two.is_empty(): b._confirm(two)
		if a.hp==0 or b.hp==0:
			a.projectiles.clear()
			b.projectiles.clear()
		if a.hp == 0 and not two.is_empty(): a.knocked_out.emit()
		if b.hp == 0 and not one.is_empty(): b.knocked_out.emit()
	else:
		_try_throws(a,b)
	a.queue_redraw()
	b.queue_redraw()

func _can_grab(other) -> bool:
	if state!="throw" or move_time<startup or move_time>startup+active_time: return false
	if not grounded or hp<=0 or other.hp<=0 or not other.grounded or other.launched: return false
	if other.stun_left>0.0 or other.invulnerability_tier()>0: return false
	var forward: float=(other.position.x-position.x)*facing
	return forward>=0.0 and forward<=float(config.width)+float(other.config.width)+THROW_MARGIN

static func _try_throws(a,b) -> void:
	var a_ready:bool=a._can_grab(b)
	var b_ready:bool=b._can_grab(a)
	if not a_ready and not b_ready: return
	# Only simultaneous or near-simultaneous throws tech. A late throw during an
	# established grab cannot escape the paired animation.
	if a.state=="throw" and b.state=="throw" and absf(a.move_time-b.move_time)<=THROW_TECH_WINDOW+0.00001:
		var point: Vector2=(a.position+b.position)*0.5+Vector2(0,-65)
		for actor in [a,b]:
			actor.position.x=clampf(actor.position.x-actor.facing*10.0,LEFT_EDGE,RIGHT_EDGE)
			actor._throw_recovery(0.20)
			actor.hitstop_left=0.055
		var emitter=a if a.side_index<b.side_index else b
		emitter.throw_teched.emit(point)
		return
	var owner=a if a_ready else b
	var captive=b if a_ready else a
	owner._grip_gap=absf(captive.position.x-owner.position.x)
	owner.move_time=0.0
	owner._set_state("throw_hold")
	captive.attack_kind=""
	captive._set_state("grabbed")
	captive.facing=-owner.facing
	captive._grip_pull=14.0 if owner.fighter_id=="mirinda" else 4.0
	for participant in [owner,captive]:
		participant.velocity=Vector2.ZERO
		participant._input_buffer.clear()
		participant._clear_combo()

func _throw_recovery(duration: float) -> void:
	move_time=startup+active_time+0.001
	move_duration=move_time+duration
	velocity=Vector2.ZERO
	_input_buffer.clear()
	_set_state("throw_recover")

func release_grip() -> void:
	if state=="throw_hold":
		_throw_recovery(0.19)
	elif state=="grabbed":
		grounded=true
		position.y=FLOOR_Y
		velocity=Vector2.ZERO
		_set_state("idle")
	else: return
	queue_redraw()

func _carry_throw(other,dt:float) -> void:
	# Once a throw is secured, play the short lift as a paired move. Existing
	# projectiles keep traveling during these protected animation frames.
	_advance_wave(dt)
	other._advance_wave(dt)
	_resolve_waves(self,other)
	move_time+=dt
	var progress:=clampf(move_time/GRIP_TIME,0.0,1.0)
	other.position=Vector2(clampf(position.x+facing*(_grip_gap-18.0*sin(PI*progress)),LEFT_EDGE,RIGHT_EDGE),
		FLOOR_Y-24.0*sin(0.5*PI*progress))
	other.grounded=false
	if progress>=1.0:
		var point:Vector2=other.position+Vector2(-facing*12.0,-58.0)
		var packet:=_packet(other,"throw",facing,THROW_DAMAGE,0.22,point,245.0,338.0,false)
		packet.launch=true
		other._receive(packet)
		_throw_recovery(0.22)
		_confirm(packet)
		if other.hp<=0:
			projectiles.clear()
			other.projectiles.clear()
			other.knocked_out.emit()
	queue_redraw()
	other.queue_redraw()

func _capture(buttons: Dictionary) -> void:
	_buttons = buttons.duplicate()
	if launched or hp<=0 or state in ["grabbed","throw_hold","throw_recover"]:
		_previous = _buttons.duplicate()
		return
	for action in ["super","special","throw","heavy","light","jump"]:
		if bool(_buttons.get(action,false)) and not bool(_previous.get(action,false)):
			if action=="throw" and (not grounded or stun_left>0 or not attack_kind.is_empty()):
				continue
			if _input_buffer.size() < 4:
				# Allow rapid taps to survive hitstop and the windup of preceding taps.
				var lifetime := 0.25 + 0.14 * _input_buffer.size()
				var paid_cancel: bool = action in ["special","super"] and attack_kind in ["light","heavy"]
				_input_buffer.append({"command":action,"left":lifetime,"cancel_only":paid_cancel})
			break
	_previous = _buttons.duplicate()

func _clear_combo() -> void:
	combo_route = ""
	combo_hits = 0
	normal_confirmed = false

func _cancel_allowed(next: String) -> bool:
	if not grounded or not normal_confirmed or not attack_kind in ["light","heavy"]: return false
	if next in ["special","super"]:
		return energy >= (200.0 if next=="super" else 100.0) and (fighter_id!="doctor" or projectiles.is_empty())
	if not next in ["light","heavy"]: return false
	var delay := 0.035 if attack_kind=="light" else 0.070
	return move_time >= startup + delay and FOLLOW_UPS.has(combo_route + str(BUTTON_LETTER[next]))

func _axis() -> int:
	return int(bool(_buttons.get("right",false))) - int(bool(_buttons.get("left",false)))

func _advance(opponent_x: float, delta: float) -> void:
	_anim_age += delta
	_glow = maxf(0.0, _glow - delta)
	if launched:
		_advance_launch(delta)
		return
	if hp <= 0:
		velocity.x = move_toward(velocity.x,0.0,900.0*delta)
		_integrate(delta)
		return
	for index in range(_input_buffer.size()-1,-1,-1):
		_input_buffer[index].left -= delta
		if _input_buffer[index].left <= 0.0:
			_input_buffer.remove_at(index)
	if stun_left > 0:
		stun_left = maxf(0.0,stun_left - delta)
		velocity.x = move_toward(velocity.x,0.0,(870.0 if grounded else 320.0)*delta)
		_integrate(delta)
		if stun_left <= 0:
			_received_hits = 0
			_set_state(("guard" if bool(_buttons.get("down",false)) else "idle") if grounded else "jump")
		return
	if attack_kind.is_empty():
		if absf(opponent_x-position.x) > 0.1: facing = 1 if opponent_x>position.x else -1
		if not _input_buffer.is_empty():
			var entry: Dictionary = _input_buffer.pop_front()
			var command: String = entry.command
			if command == "jump" and grounded:
				velocity.y = -JUMP
				grounded = false
			elif command=="throw" and grounded:
				_begin_move("throw",opponent_x)
			elif command in ATTACKS and not entry.cancel_only:
				_begin_move(command,opponent_x)
	elif not _input_buffer.is_empty():
		var command: String = _input_buffer.front().command
		if _cancel_allowed(command):
			_input_buffer.pop_front()
			_begin_move(command,opponent_x,true)
		elif command in ["special","super"] and normal_confirmed and energy < (200.0 if command=="super" else 100.0):
			_input_buffer.pop_front()
	if not attack_kind.is_empty():
		move_time += delta
		if move_time >= move_duration:
			attack_kind = ""
			_clear_combo()
			_set_state("idle" if grounded else "jump")
		else:
			var push_speed := float(move_data.get("dash",0.0))
			if fighter_id=="pudding" and attack_kind=="super" and move_time>=startup and move_time<=startup+active_time:
				var t:=move_time-startup
				if t>0.085 and _last_hit_pulse<0:
					# No opening tag: stop at the current position and spend the whiff recovery.
					pudding_braked=true
					_end_paid_active(0.35)
					velocity.x=facing*100.0
				elif t<=0.085: velocity.x=facing*395.0
				elif t<0.165: velocity.x=-facing*165.0
				elif t<0.24: velocity.x=facing*295.0
				elif t<0.325: velocity.x=0.0
				else: velocity.x=facing*365.0
			elif combo_route.length()>1 and move_time<startup and grounded:
				# Step into the next hit to follow natural hit recoil, at either screen edge.
				velocity.x = facing * (220.0 if attack_kind=="heavy" else 155.0)
			elif push_speed > 0 and move_time >= startup and move_time <= startup+active_time:
				velocity.x = facing * push_speed
			elif grounded:
				velocity.x = move_toward(velocity.x,0.0,2050.0*delta)
			_integrate(delta)
			return
	var axis := _axis()
	var defend := bool(_buttons.get("down",false)) and grounded
	var target_speed: float = axis * float(config.speed) * (0.82 if axis*facing < 0 else 1.0)
	if defend:
		velocity.x = 0.0
	else:
		velocity.x = move_toward(velocity.x,target_speed,(2600 if grounded else 920)*delta)
	_integrate(delta)
	if not grounded: _set_state("jump")
	elif defend: _set_state("guard")
	elif absf(velocity.x)>10: _set_state("walk")
	else: _set_state("idle")

func _integrate(delta: float) -> void:
	if not grounded: velocity.y += GRAVITY*delta
	position += velocity*delta
	position.x = clampf(position.x,LEFT_EDGE,RIGHT_EDGE)
	if position.y >= FLOOR_Y:
		position.y = FLOOR_Y
		velocity.y = 0.0
		grounded = true

func _advance_launch(delta: float) -> void:
	stun_left=maxf(0.0,stun_left-delta)
	velocity.x=move_toward(velocity.x,0.0,190.0*delta)
	_integrate(delta)
	if (position.x<=LEFT_EDGE and velocity.x<0.0) or (position.x>=RIGHT_EDGE and velocity.x>0.0):
		velocity.x=0.0
	if grounded:
		launched=false
		velocity=Vector2.ZERO
		stun_left=0.0
		_received_hits=0
		_set_state("ko" if hp<=0 else ("guard" if _buttons.get("down",false) else "idle"))

# Round-end presentation advances only existing motion, never controls or attacks.
func advance_ko_fall(delta: float) -> void:
	if delta<=0 or (not launched and (hp>0 or grounded)): return
	var used:=minf(hitstop_left,delta)
	hitstop_left-=used
	delta-=used
	if delta<=0: return
	_glow=maxf(0.0,_glow-delta)
	_anim_age+=delta
	if launched: _advance_launch(delta)
	else: _integrate(delta)
	queue_redraw()

func _begin_move(kind: String, _opponent_x: float, chained: bool = false) -> void:
	var cost := 200.0 if kind=="super" else (100.0 if kind=="special" else 0.0)
	if energy < cost: return
	if fighter_id=="doctor" and cost>0 and not projectiles.is_empty(): return
	energy -= cost
	_cast_id += 1
	_wave_launched = false
	pudding_braked = false
	attack_kind = kind
	if not chained: _clear_combo()
	if kind!="throw": combo_route += str(BUTTON_LETTER[kind])
	normal_confirmed = false
	move_data = (NORMALS[kind] if NORMALS.has(kind) else SKILLS[fighter_id][kind]).duplicate()
	if FOLLOW_UPS.has(combo_route):
		move_data.merge(FOLLOW_UPS[combo_route],true)
	startup = float(move_data.startup)
	if kind in ["light","heavy"]:
		if fighter_id=="taffy":
			move_data.damage+=1 if kind=="light" else 3
			move_data.reach+=6.0
		elif fighter_id=="pudding" and kind=="light":
			move_data.damage=maxi(1,int(move_data.damage)-1)
	if not chained:
		if fighter_id=="taffy" and kind in ["light","heavy"]: startup+=0.018
		if fighter_id=="pudding" and kind in ["light","heavy"]: startup-=0.012
		if fighter_id=="mirinda" and kind=="light": startup -= 0.015
		if fighter_id=="orange" and kind=="heavy": startup += 0.018
	elif kind in ["special","super"]:
		# A confirmed ground strike pays full gauge but bypasses the neutral cast windup.
		startup = minf(startup,0.082)
	active_time = float(move_data.active)
	move_duration = startup + active_time + float(move_data.recovery)
	move_time = 0.0
	_last_hit_pulse = -1
	_set_state(kind)
	move_started.emit(kind)

func _set_state(next: String) -> void:
	if state != next:
		state = next
		_anim_age = 0.0

func _body_height() -> float:
	if fighter_id=="orange" and attack_kind=="special": return 57.0
	return float(config.height)

static func _resolve_push(a,b,old_gap: float) -> void:
	if a.hp<=0 or b.hp<=0: return
	var overlap_y: float = minf(a.position.y,b.position.y) - maxf(a.position.y-a._body_height(),b.position.y-b._body_height())
	if overlap_y <= 4.0: return
	var need: float = float(a.config.width)+float(b.config.width)
	var dx: float = b.position.x - a.position.x
	# A full jump may switch sides. With overlapping torsos high-speed travel
	# cannot invert their order even when a dash advances across the midpoint.
	var side := signf(old_gap) if absf(old_gap)>0.005 else signf(dx)
	if side == 0: side = 1.0 if a.side_index==0 else -1.0
	var missing := need - dx*side
	if missing <= 0: return
	var room_a: float = (a.position.x-LEFT_EDGE) if side>0 else (RIGHT_EDGE-a.position.x)
	var room_b: float = (RIGHT_EDGE-b.position.x) if side>0 else (b.position.x-LEFT_EDGE)
	var shift_a := minf(room_a,missing*0.5)
	var shift_b := minf(room_b,missing-shift_a)
	shift_a = minf(room_a,missing-shift_b)
	a.position.x -= side*shift_a
	b.position.x += side*shift_b

func _guarding() -> bool:
	return grounded and attack_kind.is_empty() and state=="guard" and bool(_buttons.get("down",false))

func invulnerability_tier() -> int:
	if hp<=0 or move_time>startup+active_time: return 0
	if attack_kind=="super": return 2
	if attack_kind=="special": return 1
	return 0

func _end_paid_active(recovery: float) -> void:
	move_time = startup+active_time+0.001
	move_duration = move_time+recovery
	velocity.x = 0.0
	_input_buffer.clear()

# Three discrete contact windows. Both the collider and the draw code use these
# windows so a pause or direction reversal cannot add an extra attack.
func pudding_strike() -> int:
	if fighter_id!="pudding" or attack_kind!="super" or pudding_braked: return 0
	var t:=move_time-startup
	if t>=0.0 and t<=0.085: return 1
	if t>=0.165 and t<=0.24: return 2
	if t>=0.325 and t<=active_time: return 3
	return 0

func _active_strike() -> Rect2:
	if hp<=0 or attack_kind.is_empty() or move_time<startup or move_time>startup+active_time:
		return Rect2()
	if attack_kind=="throw": return Rect2()
	var reach: float = move_data.reach
	if fighter_id=="doctor" and attack_kind in ["special","super"]:
		return Rect2()
	var low := fighter_id=="orange" and attack_kind=="special"
	var top := 78.0 if low else (141.0 if attack_kind in ["heavy","super"] else 113.0)
	if fighter_id=="pudding" and attack_kind=="super":
		match pudding_strike():
			0: return Rect2()
			1: top=66.0
			2: top=104.0
			3: top=151.0
	var bottom := 3.0 if low else 15.0
	return Rect2(position.x-5 if facing>0 else position.x-reach,position.y-top,reach+5,top-bottom)

func _hurtbox() -> Rect2:
	var width: float = config.width * 0.82
	return Rect2(position.x-width,position.y-_body_height()-13,width*2,_body_height()+9)

func _advance_wave(dt: float) -> void:
	if fighter_id!="doctor": return
	if not _wave_launched and attack_kind in ["special","super"] and move_time>=startup and hp>0:
		_wave_launched=true
		var power := attack_kind=="super"
		var muzzle := position+Vector2(facing*53.0,-71.0)
		projectiles.append({"kind":attack_kind,"tier":2 if power else 1,"point":muzzle,
			"previous":muzzle,"radius":Vector2(43,32) if power else Vector2(22,18),
			"speed":520.0 if power else 610.0,"direction":facing,"age":0.0,"hits":0,
			"next_hit":0.0,"cast":_cast_id,"route":combo_route})
		wave_launched.emit(attack_kind)
	if projectiles.is_empty(): return
	var wave: Dictionary = projectiles[0]
	wave.previous=wave.point
	wave.age+=dt
	wave.next_hit=maxf(0.0,float(wave.next_hit)-dt)
	wave.point.x+=float(wave.direction)*float(wave.speed)*dt
	if wave.point.x < -wave.radius.x or wave.point.x>960.0+wave.radius.x:
		projectiles.clear()

static func _wave_shape(wave: Dictionary) -> Rect2:
	var point: Vector2=wave.point
	var previous: Vector2=wave.previous
	var radius: Vector2=wave.radius
	return Rect2(Vector2(minf(point.x,previous.x),point.y)-radius,2.0*radius+Vector2(absf(point.x-previous.x),0))

static func _resolve_waves(a,b) -> void:
	if a.projectiles.is_empty() or b.projectiles.is_empty(): return
	var first: Dictionary=a.projectiles[0]
	var second: Dictionary=b.projectiles[0]
	if first.tier!=second.tier and _wave_shape(first).intersects(_wave_shape(second)):
		if first.tier>second.tier: b.projectiles.clear()
		else: a.projectiles.clear()

func _first_contact(other) -> Dictionary:
	var defense: int = other.invulnerability_tier()
	if not projectiles.is_empty():
		var wave: Dictionary=projectiles[0]
		if int(wave.tier)>=defense and float(wave.next_hit)<=0.0:
			var contact := _wave_shape(wave).intersection(other._hurtbox())
			if contact.has_area() and other.hp>0:
				var power: bool = wave.tier==2
				var n: int = int(wave.hits)+1
				var ending := not power or n==5
				var damage := (10 if ending else 5) if power else 14
				var push := (295.0 if ending else 43.0) if power else 140.0
				var packet := _packet(other,wave.kind,wave.direction,damage,0.19 if not power else (0.31 if ending else 0.16),contact.get_center(),push,0.0,power and ending,wave.cast)
				packet.wave_hit=n
				packet.route=wave.route
				if packet.blocked or ending:
					projectiles.clear()
				else:
					wave.hits=n
					wave.next_hit=0.083
					# Impact slows the projectile itself; it never follows the opponent.
					wave.speed=65.0
				return packet
	if invulnerability_tier()>=defense:
		return _contact(other,_active_strike())
	return {}

func _contact(other, strike: Rect2) -> Dictionary:
	if other.hp<=0 or not strike.has_area(): return {}
	var volley := fighter_id=="mirinda" and attack_kind=="super"
	var pulse := mini(3,int((move_time-startup)/(active_time/4.0))) if volley else 0
	var triple:=fighter_id=="pudding" and attack_kind=="super"
	if triple: pulse=pudding_strike()-1
	if pulse==_last_hit_pulse: return {}
	var hurt: Rect2 = other._hurtbox()
	if not strike.intersects(hurt): return {}
	_last_hit_pulse = pulse
	var damage := int(move_data.damage)
	if attack_kind=="heavy" and fighter_id=="orange": damage+=2
	if volley and pulse==3: damage=12
	if triple: damage=[8,9,13][pulse]
	var push := float(move_data.push)*(3.0 if volley and pulse==3 else 1.0)
	var finisher:=attack_kind=="super" and (not volley or pulse==3) and (not triple or pulse==2)
	var packet:=_packet(other,attack_kind,facing,damage,float(move_data.stun),strike.intersection(hurt).get_center(),push,float(move_data.get("lift",0.0)),finisher)
	packet.pudding_hit=pulse+1 if triple else 0
	return packet

func _packet(other, kind: String, direction: int, damage: int, stun: float, point: Vector2, push: float, lift: float, finisher: bool, source_cast: int=-1) -> Dictionary:
	# Sample the defender before either hit resolves. Only a real, unguarded
	# interruption of startup or recovery earns a counter or punish bonus.
	var blocked: bool = other._guarding()
	var cast: int=_cast_id if source_cast<0 else source_cast
	var continued: bool=kind!="throw" and other.state=="hit" and (other.stun_left>0.0 or other.launched)
	var step:=1
	if continued:
		step=int(other._combo_damage_steps.get(cast,other._combo_damage_steps.size()+1))
	if not blocked and other.stun_left<=0.0 and not other.attack_kind.is_empty():
		var bonus_frames := 0
		if other.move_time<other.startup: bonus_frames=2
		elif other.move_time>other.startup+other.active_time: bonus_frames=4
		if bonus_frames>0:
			damage = roundi(damage*1.2)
			stun += float(bonus_frames)/60.0
	if not blocked:
		damage=maxi(1,roundi(damage*COMBO_DAMAGE[mini(step,COMBO_DAMAGE.size())-1]))
	# A lethal early pulse is the last actual hit, so it also supplies the finisher.
	var launch: bool = kind=="super" and not blocked and not other.launched and (finisher or damage>=other.hp)
	if launch:
		var impulse: Vector2=SUPER_LAUNCH[fighter_id]
		push=impulse.x
		lift=impulse.y
	return {"kind":kind,"blocked":blocked,"damage":damage,"point":point,"launch":launch,
		"direction":direction,"push":push,"stun":stun,"normal":kind in ["light","heavy"],
		"lift":lift,"wave_hit":0,"cast":cast,"route":combo_route,"damage_step":step,
		"hit_number":other._received_hits+1 if continued else 1}

func _receive(packet: Dictionary) -> void:
	var block := bool(packet.blocked)
	var amount := int(packet.damage)
	_received_hits = 0 if block else int(packet.hit_number)
	if _received_hits<=1:
		_combo_damage_steps.clear()
	if not block:
		_combo_damage_steps[packet.cast]=packet.damage_step
	if block:
		if not bool(packet.normal): hp=maxi(1,hp-(2 if packet.kind=="super" else 1))
	else:
		hp = maxi(0,hp-amount)
	energy = minf(MAX_ENERGY,energy + (7.0 if block else float(amount)*1.65))
	hitstop_left = maxf(hitstop_left,0.052 if packet.kind=="light" or block else 0.085)
	stun_left = float(packet.stun)*(0.70 if block else 1.0)
	if not launched:
		velocity.x = float(packet.direction)*float(packet.push)*(0.48 if block else 1.0)
		if not block and float(packet.lift)>0.0 and (hp>0 or packet.launch):
			velocity.y = -float(packet.lift)
			grounded = false
			launched = bool(packet.launch)
			_launch_direction = int(packet.direction)
	attack_kind = ""
	_input_buffer.clear()
	_clear_combo()
	_glow = hitstop_left+0.08
	_set_state("ko" if hp==0 else ("guard" if block else "hit"))

func _confirm(packet: Dictionary) -> void:
	hitstop_left = maxf(hitstop_left,0.052 if packet.kind=="light" or packet.blocked else 0.085)
	last_launch=bool(packet.launch)
	last_pudding_hit=int(packet.get("pudding_hit",0))
	if last_launch and fighter_id=="orange" and attack_kind=="super":
		# The scooter brakes on impact while its rider throws the target forward.
		# It must not drive underneath the target and push it backward on descent.
		move_data.dash=0.0
	last_projectile_hit=packet.wave_hit
	last_projectile_direction=packet.direction
	last_impact_route=packet.route
	var close_block: bool = packet.wave_hit==0 or absf(float(packet.point.x)-position.x)<180.0
	last_block_recovery=bool(packet.blocked) and packet.cast==_cast_id and close_block and attack_kind in ["special","super"]
	if last_block_recovery:
		_end_paid_active(float(BLOCK_RECOVERY[fighter_id][1 if attack_kind=="super" else 0]))
	if not bool(packet.blocked):
		combo_hits = int(packet.hit_number)
		if packet.wave_hit==0:
			normal_confirmed = bool(packet.normal) and attack_kind==packet.kind and hp>0
	if bool(packet.normal):
		energy=minf(MAX_ENERGY,energy+((15.0 if packet.kind=="light" else 18.0) if packet.blocked else (25.0 if packet.kind=="light" else 34.0)))
	impact.emit(packet.point,packet.kind,packet.blocked)

func _load_clips() -> void:
	if frame_cache.has(fighter_id): return
	var clips := {}
	for kind in ANIM:
		var frames: Array[Texture2D] = []
		for idx in 16:
			var path := "res://art/%s/%s_%d.png" % [fighter_id,kind,idx]
			if not ResourceLoader.exists(path): break
			var item := load(path) as Texture2D
			if item: frames.append(item)
		clips[kind]=frames
	frame_cache[fighter_id]=clips

func _draw() -> void:
	if not _ready_for_round: return
	var lift := FLOOR_Y-position.y
	draw_set_transform(Vector2(0,lift-1),0,Vector2(1,0.18))
	draw_circle(Vector2.ZERO,clampf(48.0-lift*0.15,22,48),Color(0.065,0.062,0.09,0.35))
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	var clip := "idle"
	match state:
		"walk","jump","special","super","heavy","guard": clip=state
		"light","throw","throw_hold","throw_recover": clip="attack"
		"hit","ko","grabbed": clip="hurt"
	var casting_wave := fighter_id=="doctor" and attack_kind in ["special","super"]
	if casting_wave: clip="special"
	# Mirinda's jab and heavy clips are kicks; use the planted two-paw brace for grabs.
	var brace_throw := fighter_id=="mirinda" and attack_kind=="throw"
	if brace_throw: clip="guard"
	var clips: Dictionary=frame_cache.get(fighter_id,{})
	var frames: Array=clips.get(clip,[])
	if frames.is_empty() and clip=="heavy":
		frames=clips.get("attack",[])
	elif frames.is_empty() and clip=="guard":
		frames=clips.get("idle",[])
	if frames.is_empty(): return
	var fps := 8.0 if clip=="walk" else (2.6 if clip=="guard" else 4.0)
	var idx := int(_anim_age*fps) % frames.size()
	if attack_kind=="throw":
		if brace_throw: idx=0 if move_time<startup*0.5 and state=="throw" else 1
		elif state=="throw_hold": idx=2
		elif state=="throw_recover" or move_time>startup+active_time: idx=3
		else: idx=0 if move_time<startup*0.42 else (1 if move_time<startup else 2)
		idx=mini(idx,frames.size()-1)
	elif state=="grabbed":
		idx=mini(1,frames.size()-1)
	elif fighter_id in ["taffy","pudding"] and attack_kind in ["special","super"]:
		var t:=move_time-startup
		if attack_kind=="special":
			if move_time<startup*0.45: idx=0
			elif t<0.0: idx=1
			elif t<=active_time: idx=2
			else: idx=3
		elif fighter_id=="taffy":
			if move_time<startup*0.38: idx=0
			elif move_time<startup*0.72: idx=1
			elif t<0.0: idx=2
			elif t<=active_time: idx=3
			else: idx=4
		elif pudding_braked or t>active_time: idx=4
		elif t<0: idx=0
		elif t<0.165: idx=1
		elif t<0.325: idx=2
		else: idx=3
		idx=mini(idx,frames.size()-1)
	elif casting_wave:
		if move_time<startup*0.5: idx=0 if move_time<startup*0.2 else 1
		elif move_time<=startup+active_time+0.09: idx=2
		else: idx=1 if move_time<move_duration-0.07 else 0
		idx=mini(idx,frames.size()-1)
	elif attack_kind in ["light","heavy"]:
		if move_time < startup:
			idx = 0 if move_time < startup*0.5 else 1
		elif move_time <= startup+active_time: idx = 2
		else: idx = 3
		idx=mini(idx,frames.size()-1)
	elif not attack_kind.is_empty():
		idx=mini(frames.size()-1,int(move_time/maxf(move_duration,0.01)*frames.size()))
	elif state=="ko": idx=frames.size()-1
	elif fighter_id in ["taffy","pudding"]:
		match state:
			"jump": idx=0 if velocity.y < -160 else (2 if velocity.y > 160 else 1)
			"hit": idx=2 if launched else (0 if _anim_age < 0.065 else 1)
			"guard": idx=1 if stun_left>0 else 0
		idx=mini(idx,frames.size()-1)
	var steady_idle := fighter_id=="mirinda" and state=="idle"
	var tex: Texture2D=frames[0] if steady_idle else frames[idx]
	var scale_y := 1.0
	var tilt := 0.0
	var pose_offset := Vector2.ZERO
	if state=="throw":
		var reach:=sin(PI*clampf(move_time/(startup+active_time+0.12),0.0,1.0))
		pose_offset=Vector2(facing*13.0,-4.0)*reach
		tilt=facing*0.14*reach
	elif state=="throw_hold":
		# Mirinda braces with short forearms; lean the shoulder into the grip.
		if fighter_id=="mirinda":
			pose_offset=Vector2(facing*35.0,-4.0)
			tilt=facing*0.115
		else:
			pose_offset=Vector2(facing*12.0,-4.0)
			tilt=-facing*0.12*clampf(move_time/GRIP_TIME,0.0,1.0)
	elif state=="grabbed":
		pose_offset.x=facing*_grip_pull
		tilt=-facing*0.09
	if FOLLOW_UPS.has(combo_route):
		var follow := sin(PI * clampf(move_time/move_duration,0.0,1.0))
		match combo_route:
			"JJ","KK":
				tilt = -0.08 * facing * follow
				pose_offset = Vector2(4*facing,-3) * follow
			"JJJ","JJJJ","KKK":
				tilt = 0.095 * facing * follow
				pose_offset = Vector2(9*facing,-2) * follow
			"JJJK":
				tilt = -0.14 * facing * follow
				pose_offset = Vector2(6*facing,-9) * follow
	if state=="guard" and stun_left>0: tilt=-facing*0.055
	if state=="hit": tilt=-facing*0.08
	if state=="ko" and grounded: scale_y=0.65
	if launched:
		tilt=_launch_direction*(0.31+0.15*clampf(velocity.y/640.0,-1.0,1.0))
	var tint := Color(0.88,0.94,1.0) if side_index==1 else Color.WHITE
	if _glow>0 and state in ["hit","guard"]: tint = Color(1.5,1.4,1.1)
	var pix_scale := 1.0
	var sz:=tex.get_size()*pix_scale
	draw_set_transform(pose_offset,tilt,Vector2(facing,scale_y))
	var bounds:=Rect2(Vector2(-sz.x*0.5-float(config.anchor),-sz.y+3.0),sz)
	if steady_idle:
		_draw_idle_breath(tex,bounds,tint)
	else:
		draw_texture_rect(tex,bounds,false,tint)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	if state=="guard":
		var arc_center:=Vector2(facing*24.0,-72.0)
		var axis:=0.0 if facing>0 else PI
		var strength:=0.48 if stun_left>0 else 0.28
		draw_arc(arc_center,28.0,axis-0.73,axis+0.73,16,Color(0.63,0.96,0.92,strength),2.4,true)


# The idle sheet contains both a low stance and an upright stance. Hold the
# low silhouette and breathe through the jacket, leaving face size and paws fixed.
func _draw_idle_breath(tex: Texture2D, bounds: Rect2, tint: Color) -> void:
	var rise:=0.9*(1.0-cos(TAU*_anim_age/1.9))
	var collar:=166.0
	var ankle:=225.0
	var w:=bounds.size.x
	var h:=bounds.size.y
	var head:=Rect2(0,0,w,collar)
	var chest:=Rect2(0,collar,w,ankle-collar)
	var legs:=Rect2(0,ankle,w,h-ankle)
	draw_texture_rect_region(tex,Rect2(bounds.position-Vector2(0,rise),head.size),head,tint)
	draw_texture_rect_region(tex,Rect2(bounds.position+Vector2(0,collar-rise),chest.size+Vector2(0,rise)),chest,tint)
	draw_texture_rect_region(tex,Rect2(bounds.position+legs.position,legs.size),legs,tint)
