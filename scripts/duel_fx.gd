extends Node2D

# All authored coordinates use the same 960 x 540 world as the combat actors.
const Fighter = preload("res://scripts/fighter.gd")
var fighters: Array = []
var impacts: Array[Dictionary] = []
var _serial := 0
const TEAL := Color("#47e1b8")
const ICE := Color("#b2fff0")
const GOLD := Color("#ffe082")
const DARK := Color("#273842")
const COLORS := {"mirinda":Color("#ff9950"), "doctor":TEAL, "orange":Color("#bca3ff"), "taffy":Color("#e2a957"), "pudding":Color("#8bd3e8")}

# Height of the extended paw on each normal's contact frame, measured from the floor.
const PAW_HEIGHT := {"mirinda":[115.0,127.0], "doctor":[93.0,113.0], "orange":[122.0,101.0],"taffy":[102.0,105.0],"pudding":[95.0,115.0]}
const PLASMA_AZURE := Color("#42adff")
const GRIP_HEIGHT := {"mirinda":110.0, "doctor":87.0, "orange":111.0,"taffy":105.0,"pudding":99.0}
const THROW_INK := Color("#38274b")
const THROW_VIOLET := Color("#c77aff")
const THROW_PEAK := Color("#fff0ff")
const KICK_TEXTURE := preload("res://art/mirinda/super_2.png")
# Outline of the extended striped hind leg on the transparent super frame.
const KICK_LIMB := [Vector2(103,157), Vector2(132,138), Vector2(167,126), Vector2(191,115),
	Vector2(214,99), Vector2(229,93), Vector2(246,94), Vector2(249,108), Vector2(246,120),
	Vector2(230,130), Vector2(205,136), Vector2(171,157), Vector2(139,177), Vector2(113,183)]
const KICK_PIVOT := Vector2(107,167)
const KICK_ANGLES := [-0.46, 0.18, -0.18, -0.68]

func _ready() -> void:
	z_index = 10

func clear_fx() -> void:
	impacts.clear()
	queue_redraw()

func on_throw_tech(point: Vector2) -> void:
	# Both fighters share this single contact. Its broken ring separates in both directions.
	impacts.append({"throw_event":"tech", "p":point, "age":0.0, "life":0.31, "side":-1, "block":false})
	queue_redraw()

func _throw_released(point: Vector2, attacker) -> void:
	var direction: int = attacker.last_projectile_direction
	var victim = fighters[1-attacker.side_index] if fighters.size()==2 else null
	var trail := PackedVector2Array()
	if is_instance_valid(victim):
		trail.append(victim.position + Vector2(-direction*24,-32))
	impacts.append({"throw_event":"release", "p":point, "age":0.0, "life":0.40, "side":attacker.side_index,
		"block":false, "facing":direction, "victim":victim, "trail":trail})
	queue_redraw()

func _trace_throw(event: Dictionary) -> void:
	var victim = event.victim
	if not is_instance_valid(victim): return
	var sample: Vector2 = victim.position + Vector2(-int(event.facing)*24,-32)
	var trail: PackedVector2Array = event.trail
	if trail.is_empty() or trail[-1].distance_squared_to(sample) > 8.0:
		trail.append(sample)
		if trail.size()>15: trail.remove_at(0)
		event.trail=trail


func on_impact(point: Vector2, kind: String, blocked: bool, attacker) -> void:
	if not is_instance_valid(attacker): return
	if kind=="throw":
		_throw_released(point,attacker)
		return
	_serial += 1
	var rail_hit: int = attacker.last_projectile_hit if attacker.fighter_id == "doctor" else 0
	var direction: int = attacker.last_projectile_direction if rail_hit > 0 else attacker.facing
	var launch: bool = attacker.last_launch and not blocked
	var volley: bool = kind == "super" and attacker.fighter_id in ["mirinda","doctor","pudding"] and not launch
	var weight := 1.0 if kind == "light" else 1.38
	if volley: weight = 0.90
	if launch: weight = 1.66
	var guard_center := point
	if fighters.size() == 2:
		var defender = fighters[1-attacker.side_index]
		if is_instance_valid(defender):
			if kind in ["light","heavy"]:
				var height: float=PAW_HEIGHT[attacker.fighter_id][int(kind=="heavy")]
				point.y=clampf(attacker.position.y-height,defender.position.y-defender._body_height()-9,defender.position.y-18)
			guard_center.x = defender.position.x - direction * float(defender.config.width) * 0.68
			guard_center.y = clampf(point.y,defender.position.y-100.0,defender.position.y-72.0)
	# A newer contact from the same fighter replaces the bright core of a rapid series.
	# Earlier sparks disappear at a lower opacity instead of piling up over the fighters.
	for old in impacts:
		if old.side == attacker.side_index and not old.block:
			old.age = maxf(old.age, old.life * 0.76)
	var duration := 0.33 if blocked else (0.42 if launch else (0.22 if volley else 0.29))
	impacts.append({"p":point, "guard_center":guard_center, "age":0.0, "life":duration, "block":blocked,
		"stone":kind=="super" and attacker.fighter_id=="taffy","stone_origin":attacker.position,
		"rail_hit":rail_hit, "rail_super":kind=="super", "weight":weight, "normal":kind in ["light","heavy"], "launch":launch,
		"lift":launch or attacker.last_impact_route == "JJJK", "side":attacker.side_index, "facing":direction, "seed":_serial})
	if impacts.size()>24: impacts.pop_front()
	queue_redraw()

func _process(delta: float) -> void:
	for i in range(impacts.size()-1,-1,-1):
		if impacts[i].get("throw_event","")=="release": _trace_throw(impacts[i])
		impacts[i].age += delta
		if impacts[i].age >= impacts[i].life: impacts.remove_at(i)
	queue_redraw()

func _draw() -> void:
	for f in fighters:
		if not is_instance_valid(f) or not f.is_inside_tree(): continue
		for shot in f.projectiles: _plasma_round(shot)
		if f.hp <= 0: continue
		if f.state in ["throw","throw_hold"]:
			_throw_gesture(f)
			continue
		if f.state in ["grabbed","throw_recover"]: continue
		var kind: String = f.attack_kind
		if kind.is_empty(): continue
		if f.fighter_id == "doctor" and kind in ["special","super"]:
			_gauntlet(f)
		elif f.fighter_id == "mirinda" and kind == "super":
			_shadow_kicks(f)
		elif f.fighter_id=="taffy" and kind in ["special","super"]:
			_taffy_skill(f)
		elif f.fighter_id=="pudding" and kind in ["special","super"]:
			_pudding_skill(f)
		elif kind=="special" or kind=="super":
			_rush(f)
		else:
			_swipe(f)
	for burst in impacts:
		_impact(burst)

func _tint(c: Color, alpha: float) -> Color:
	return Color(c.r,c.g,c.b,clampf(alpha,0.0,1.0))

# A rotated oval is drawn in world space so its stroke width remains legible.
func _oval(center: Vector2, radii: Vector2, color: Color, width: float, start: float=0.0, end: float=TAU) -> void:
	var outline := PackedVector2Array()
	for i in range(25):
		var angle := lerpf(start,end,float(i)/24.0)
		outline.append(center + Vector2(cos(angle)*radii.x,sin(angle)*radii.y))
	draw_polyline(outline,color,width,true)

func _swipe(f) -> void:
	var progress := (float(f.move_time)-float(f.startup)+0.025)/(float(f.active_time)+0.09)
	if progress<0.0 or progress>=1.0: return
	var heavy: bool = f.attack_kind=="heavy"
	var c: Color = COLORS[f.fighter_id]
	var center: Vector2 = f.position+Vector2(f.facing*15.0,-67.0)
	var reach := 94.0 if heavy else 73.0
	var depth := 48.0 if heavy else 34.0
	var arc_start := lerpf(-1.10,0.41,progress)
	var arc_end := lerpf(-0.25,1.10,progress)
	var tip := center
	for i in range(10):
		var t := float(i)/9.0
		var a := lerpf(arc_start,arc_end,t)
		var next := center+Vector2(f.facing*cos(a)*reach,sin(a)*depth)
		if i>0:
			var weight := (2.5 if heavy else 1.4) + sin(t*PI)*(3.8 if heavy else 1.9)
			draw_line(tip,next,_tint(c,(1.0-progress)*0.85),weight,true)
		tip=next
	if heavy:
		_oval(center+Vector2(0,4), Vector2(reach-8,depth-5), _tint(GOLD,(1.0-progress)*0.57), 1.4,
			arc_start if f.facing>0 else PI-arc_end, arc_end if f.facing>0 else PI-arc_start)

func _rush(f) -> void:
	var t: float = f.move_time-f.startup
	if t<0 or t>f.active_time+0.11: return
	var alpha := clampf(1.0-maxf(0.0,t-f.active_time)/0.11,0.0,1.0)
	var power: bool = f.attack_kind=="super"
	var orange: bool = f.fighter_id=="orange"
	var c: Color = COLORS[f.fighter_id]
	var trail: Vector2=f.position+Vector2(-f.facing*35,-45 if orange else -62)
	var count := 6 if power else 4
	for i in count:
		var phase := fmod(t*(3.8 if orange else 5.5)+float(i)*0.257,1.0)
		var end := trail+Vector2(-f.facing*(18.0+phase*43.0),(i-2.5)*(6 if power else 5))
		var length := (93.0 if power else 61.0)*(1.0-phase*0.71)
		var root := end-Vector2(f.facing*length,0)
		var line_ink := GOLD if i==1 else c
		draw_line(root,end,_tint(line_ink,alpha*(0.28+sin(PI*phase)*0.52)),3 if i%3==0 else 1.6,true)
	if orange and f.grounded:
		for j in 4:
			var k := fmod(t*4.0+j*0.25,1.0)
			var p: Vector2=f.position+Vector2(-f.facing*(34+92*k),-4-20*sin(PI*k))
			var size := 1.5+2.2*(1.0-k)
			_chip(p,size,k*3.0+float(j),_tint(GOLD,alpha*(1.0-k)))

# The near paving line lifts from the planted paws outward in three beats.
# Brick tones echo the garden paving so the thrust appears to move the floor.
func _heave_pavers(origin:Vector2, direction:int, seconds:float) -> void:
	for index in 3:
		var t:=clampf((seconds-0.054*index)/0.27,0.0,1.0)
		if t<=0.0 or t>=1.0: continue
		var arc:=sin(t*PI)
		var center:=Vector2(origin.x+direction*(44+index*39),Fighter.FLOOR_Y-1.0-index*0.8)
		var tilt:=arc*float(14+index*3)
		var root:=center+Vector2(direction*(-17),0)
		var lip:=center+Vector2(direction*17,-tilt)
		var rear:=Vector2(direction*8,-5)
		var top:=PackedVector2Array([root,lip,lip+rear,root+rear])
		draw_colored_polygon(PackedVector2Array([root,lip,lip+Vector2(0,5.0*arc),root+Vector2(0,2.0)]),_tint(Color("#654b46"),arc))
		draw_colored_polygon(top,_tint(Color("#d5b898"),minf(1.0,arc*2.7)))
		draw_polyline(PackedVector2Array([top[0],top[1],top[2],top[3],top[0]]),_tint(Color("#5d4f49"),arc),1.6,true)
		draw_line(root,lip,_tint(Color("#ffe8ae"),arc),2.8,true)
		for j in 3:
			var bit:=lip+Vector2(direction*((j+1)*4.0+8*t),-arc*(4+j*4))
			draw_line(bit,bit+Vector2(direction*3,1),_tint(Color("#f3d399"),arc),1.8,true)

func _taffy_skill(f) -> void:
	var t:float=f.move_time-f.startup
	var direction:int=f.facing
	var pos:Vector2=f.position
	var palm:Vector2=pos+Vector2(direction*42,-84)
	if f.attack_kind=="super":
		if t<0:
			var k:=clampf(f.move_time/f.startup,0,1)
			for j in 2:
				var foot:=pos+Vector2(direction*(6+j*20),-3.0)
				draw_line(foot-Vector2(direction*(9.0+k*6.0),0),foot,_tint(Color("#f6d194"),k*0.8),2.4,true)
			return
		if f._last_hit_pulse<0: _heave_pavers(pos,direction,t)
		if t>0.21: return
		var pressure:=sin(clampf(t/0.21,0,1)*PI)
		for j in 2:
			var c:=palm+Vector2(direction*(10+j*8+t*140),-6.0+j*12.0)
			var a:float=-0.80 if direction>0 else PI-0.80
			_oval(c,Vector2(18+j*7,21+j*5),_tint(Color("#ffe9bb"),pressure*(0.92-j*0.20)),3.6-j,a,a+1.6)
	elif t>=0.0 and t<0.22:
		var k:=sin(PI*clampf(t/0.22,0,1))
		for j in 3:
			var end:=pos+Vector2(direction*(5.0+j*4.0),-14.0-j*13)
			var root:=end-Vector2(direction*(15.0+k*(18+j*4)),3.0)
			draw_line(root,end,_tint(Color("#806350"),k*0.68),4.0,true)
			draw_line(root+Vector2(0,-1),end+Vector2(0,-1),_tint(Color("#ffdda3"),k),1.8,true)

func _pudding_skill(f) -> void:
	var t:float=f.move_time-f.startup
	if t<0 or f.pudding_braked or t>f.active_time: return
	var power:bool=f.attack_kind=="super"
	var stage:int=f.pudding_strike() if power else 1
	if stage==0: return
	var starts:=[0.0,0.165,0.325]
	var ends:=[0.085,0.24,0.45]
	var u:=clampf((t-float(starts[stage-1]))/(float(ends[stage-1])-float(starts[stage-1])) if power else t/0.16,0,1)
	var strength:=0.35+0.65*sin(u*PI)
	var d:int=f.facing
	var actor:Vector2=f.position
	var previous:=actor+Vector2(d*(-48.0 if stage!=2 else 12.0),0)
	var clips:Dictionary=Fighter.frame_cache.get("pudding",{})
	var frames:Array=clips.get(f.attack_kind,[])
	# Draw a low-opacity pose exactly where the angled trail begins.
	if not frames.is_empty():
		var tex:Texture2D=frames[mini(stage,frames.size()-1)]
		var sz:=tex.get_size()
		draw_set_transform(previous,0,Vector2(d,1))
		draw_texture_rect(tex,Rect2(Vector2(-sz.x*0.5-float(f.config.anchor),-sz.y+3),sz),false,Color(0.38,0.89,1.0,0.19*strength))
		draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
	var hand:Vector2=actor+Vector2(d*(65+u*23),[-35.0,-77.0,-125.0][stage-1])
	for j in 3:
		var tip:=hand+Vector2(d*j*2.5,float(j)*4.0)
		var bend:=actor+Vector2(d*(14.0 if stage!=2 else 54.0),[-41.0,-47.0,-45.0][stage-1]+j*3.0)
		var tail:=actor+Vector2(d*(-48.0 if stage!=2 else -16.0),[-21.0,-77.0,-20.0][stage-1]+j*6.0)
		var trace:=PackedVector2Array([tail,bend,tip])
		draw_polyline(trace,_tint(Color("#385876"),strength*0.62),4.8,true)
		draw_polyline(trace,_tint(Color("#83e9ec") if j!=1 else Color("#edf8e9"),strength),2.1,true)

func _shadow_kicks(f) -> void:
	var beat: float = f.active_time / 4.0
	var elapsed: float = f.move_time - f.startup
	if elapsed < 0.0 or elapsed > f.active_time + 0.13: return
	var beat_index := mini(3, int(elapsed / beat))
	# Fan the actual striped kicking leg across three heights. Each echo lasts into the next beat.
	for i in range(maxi(0, beat_index - 2), beat_index + 1):
		var age := (elapsed - float(i) * beat) / beat
		if age < 0.0 or age >= 2.1: continue
		var strength := sqrt(clampf(1.0 - age / 2.1, 0.0, 1.0))
		var launch := clampf(age / 0.36, 0.0, 1.0)
		var extent := 0.83 + 0.22 * sin(launch * PI / 2.0)
		var angle := float(KICK_ANGLES[i]) + 0.10 * (1.0 - launch)
		var hip: Vector2 = f.position + Vector2(f.facing * (-21.0 + 5.0 * i), -82.0)
		var tint := Color("#ffaf50") if i % 2 == 0 else Color("#ff7848")
		var axis := Vector2(cos(angle) * f.facing, sin(angle))
		var lateral := Vector2(-sin(angle) * f.facing, cos(angle))
		var vertices := PackedVector2Array()
		var uvs := PackedVector2Array()
		var legacy_tilt := -0.414
		for source: Vector2 in KICK_LIMB:
			var v := (source - KICK_PIVOT).rotated(-legacy_tilt)
			vertices.append(hip + axis * v.x * extent + lateral * v.y)
			uvs.append(source / KICK_TEXTURE.get_size())
		var paw := hip + axis * (137.0 * extent)
		# Tapered gold pressure ribbons hug the two edges of the paw.
		for sign_y: float in [-1.0, 1.0]:
			var edge := lateral * sign_y
			var ribbon := PackedVector2Array([hip + axis * 10.0 + edge * 13.0,
				hip + axis * 65.0 + edge * 22.0, paw + edge * 14.0 + axis * 9.0,
				hip + axis * 83.0 + edge * 15.0])
			draw_colored_polygon(ribbon, _tint(tint, strength * 0.96))
			draw_polyline(PackedVector2Array([ribbon[0], ribbon[1], ribbon[2]]), _tint(Color("#953d1b"), strength * 0.8), 2.8, true)
			draw_polyline(PackedVector2Array([ribbon[1], ribbon[2]]), _tint(Color("#fff7ae"), strength * 0.97), 1.8, true)
			draw_line(hip + axis * 71.0 + edge * 21.0, paw + edge * 13.0 + axis * 6.0, _tint(GOLD, strength), 1.7, true)
		draw_polygon(vertices, PackedColorArray([_tint(tint.lightened(0.22), strength * 0.84)]), uvs, KICK_TEXTURE)
		# Curved heel trails extend the stripe silhouette, even against the tan laboratory walls.
		var sweep := PackedVector2Array()
		for step in 12:
			var u := float(step) / 11.0
			sweep.append(hip + axis * (36.0 + 100.0 * u) + lateral * (48.0 * (1.0 - u) * (1.0 - u) + 13.0))
		draw_polyline(sweep, _tint(Color("#a8431b"), strength * 0.90), 6.0, true)
		draw_polyline(sweep, _tint(Color("#ffbb3e"), strength * 0.98), 4.0, true)
		draw_polyline(sweep.slice(4), _tint(Color("#fff8b9"), strength), 1.8, true)
		var tip := paw + axis * 5.0
		for j in 3:
			var offset := lateral * (float(j - 1) * 6.0)
			draw_line(tip + offset, tip + offset + axis * (11.0 + 5.0 * strength), _tint(GOLD, strength * 0.84), 1.7, true)

func _gauntlet(f) -> void:
	var full: bool = f.attack_kind == "super"
	var after: float = f.move_time - f.startup
	var charge := clampf(f.move_time / maxf(0.01, f.startup), 0.0, 1.0)
	# These anchors are the wrist centres on the three special frames, in actor space.
	# Match the fighter's pose switches exactly so the cuff never travels through empty space.
	var extended: bool = charge >= 0.5 and after <= f.active_time + 0.09
	var rest: bool = charge < 0.2 or f.move_time >= f.move_duration - 0.07
	var wrist := Vector2(26,-91) if extended else (Vector2(-36,-71) if rest else Vector2(-39,-80))
	var angle := -0.12 if extended else (1.73 if rest else 0.13)
	var actor_transform := Transform2D(0.0, Vector2(f.facing,1), 0.0, f.position)
	draw_set_transform_matrix(actor_transform * Transform2D(angle,wrist))
	var alloy := Color("#849ba7")
	var casing := Color("#293346")
	var light := PLASMA_AZURE if full else TEAL
	var size := 1.0 if extended else 0.68
	var shell := PackedVector2Array([Vector2(-19,-8),Vector2(-13,-13),Vector2(6,-13),Vector2(16,-7),
		Vector2(21,-6),Vector2(20,6),Vector2(8,10),Vector2(-16,9),Vector2(-21,4)])
	for i in shell.size(): shell[i] *= size
	draw_colored_polygon(shell,casing)
	var plate := PackedVector2Array([shell[0],shell[1],shell[2],shell[3],Vector2(6,-4)*size,Vector2(-17,1)*size])
	draw_colored_polygon(plate,alloy)
	draw_polyline(PackedVector2Array([shell[0],shell[1],shell[2],shell[3]]),ICE,1.5,true)
	for i in 3:
		var x := -12.0 + 6.0 * i
		draw_line(Vector2(x,0)*size,Vector2(x+3,6)*size,_tint(light,0.67+0.33*charge),2.4,true)
	var nose := Vector2(21,0)*size
	if extended:
		# Encircle the existing triangular crystal with a mount. It is the sight above the barrel.
		var stock := PackedVector2Array([Vector2(6,-11),Vector2(13,-16),Vector2(30,-13),
			Vector2(34,-11),Vector2(29,-6),Vector2(18,-4),Vector2(14,-8)])
		draw_colored_polygon(stock,casing)
		draw_polyline(PackedVector2Array([stock[1],stock[2],stock[3]]),light,2.2,true)
		draw_line(Vector2(12,-11),Vector2(23,-11),ICE,1.6,true)
	_oval(nose,Vector2(4.1,7.2)*size,casing,3.7)
	_oval(nose,Vector2(4.1,7.2)*size,light,2.1)
	if extended and after < 0.0:
		var r := 2.1 + charge*(5.5 if full else 3.0)
		draw_circle(nose,r*1.55,_tint(light,0.26),true,-1.0,true)
		draw_circle(nose,r,_tint(light,0.95),true,-1.0,true)
		draw_circle(nose,r*0.45,Color.WHITE,true,-1.0,true)
		for i in (3 if full else 2):
			var a := i * TAU / (3.0 if full else 2.0) + charge*TAU
			draw_arc(nose,r+4.0+2.0*i,a,a+1.13,10,_tint(light,0.78*charge),1.6,true)
	if extended and after >= 0.0 and after < 0.13:
		# Bend the short muzzle flare into the level projectile path below the aiming crystal.
		draw_set_transform_matrix(actor_transform)
		var strength := 1.0-after/0.13
		var guide := PackedVector2Array([Vector2(46,-94),Vector2(51,-92),Vector2(56,-86),
			Vector2(59,-79),Vector2(64,-74),Vector2(73,-71),Vector2(82,-71)])
		draw_polyline(guide,_tint(light,strength*0.90),5.5,true)
		draw_polyline(guide,_tint(ICE,strength),2.1,true)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _plasma_round(shot: Dictionary) -> void:
	var center: Vector2 = shot.point
	var radius: Vector2 = shot.radius
	var age: float = shot.age
	var full: bool = shot.kind == "super"
	draw_set_transform(center, 0.0, Vector2(float(shot.direction),1.0))
	var pulse := 0.5 + 0.5 * sin(age * (25.0 if full else 37.0))
	var wake := clampf(age * 13.0, 0.2, 1.0)
	if full:
		_magnetic_wave(radius, age, pulse, wake, int(shot.hits))
	else:
		_pulse_probe(radius, age, pulse, wake)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _wake_ribbon(from: Vector2, to: Vector2, bend: float, thick: float, ink: Color) -> void:
	# Moving ribbons taper at both tips and stay cropped to the rear of the projectile.
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in 13:
		var u := float(i) / 12.0
		var arch := sin(u * PI)
		var mid := from.lerp(to,u) + Vector2(0,bend*arch)
		top.append(mid - Vector2(0,thick*arch))
		if i > 0 and i < 12: bottom.append(mid + Vector2(0,thick*arch))
	bottom.reverse()
	top.append_array(bottom)
	draw_colored_polygon(top,ink)

func _pulse_probe(r: Vector2, age: float, pulse: float, wake: float) -> void:
	var shell := Color("#235d81")
	var aqua := Color("#26f4df")
	for i in 3:
		var off := float(i - 1)
		_wake_ribbon(Vector2(-r.x-38.0*wake+absf(off)*14,off*3.0),Vector2(r.x*0.5,off*r.y*0.50),
			off*(4.0+2.0*pulse),3.1-absf(off),_tint(aqua,0.83))
	var s := r.y*(0.88+0.06*pulse)
	draw_circle(Vector2.ZERO,s*1.30,_tint(aqua,0.24),true,-1.0,true)
	draw_circle(Vector2.ZERO,s,shell,true,-1.0,true)
	draw_circle(Vector2(1,0),s*0.84,aqua,true,-1.0,true)
	draw_circle(Vector2(2,-1),s*0.49,Color("#eefff4"),true,-1.0,true)
	for i in 2:
		var phase := age*6.8 + i*PI
		_oval(Vector2(-1,0),Vector2(r.x*0.94,r.y*0.95),_tint(ICE,0.92),1.9,phase,phase+2.03)
	# Forward nose and two titanium fins give the pulse a visible direction.
	draw_colored_polygon(PackedVector2Array([Vector2(r.x*0.48,-3),Vector2(r.x+3,0),Vector2(r.x*0.48,3)]),Color.WHITE)
	for side: float in [-1,1]:
		draw_colored_polygon(PackedVector2Array([Vector2(-r.x*0.65,side*r.y*0.42),Vector2(-r.x*1.1,side*r.y*0.91),Vector2(-r.x*0.12,side*r.y*0.66)]),shell)
		draw_line(Vector2(-r.x*1.1,side*r.y*0.91),Vector2(-r.x*0.12,side*r.y*0.66),ICE,1.3,true)

func _magnetic_wave(r: Vector2, age: float, pulse: float, wake: float, hits: int) -> void:
	var blue := PLASMA_AZURE
	var blue_dark := Color("#29397b")
	var violet := Color("#bb91ff")
	var mint := Color("#96fff6")
	var wake_len := (66.0+8.0*pulse)*wake
	for i in 5:
		var lane := float(i-2)*0.5
		var begin := Vector2(-r.x - wake_len*(1.0-absf(lane)*0.38),lane*r.y*0.60)
		var end := Vector2(r.x*0.7,lane*r.y*0.64)
		_wake_ribbon(begin,end,lane*(6.0+6.0*sin(age*15+i)),5.6-2.8*absf(lane),_tint(violet if i%2==0 else blue,0.85))
	# The solid curved leading crest describes the actual attack volume. Open foil rings trail it.
	var skin := PackedVector2Array()
	for j in 25:
		var a := -PI*0.65 + PI*1.30*j/24.0
		skin.append(Vector2(cos(a)*r.x,sin(a)*r.y))
	for j in range(23,0,-1):
		var a := -PI*0.65 + PI*1.30*j/24.0
		skin.append(Vector2(cos(a)*r.x*0.71-2.0,sin(a)*r.y*0.89))
	draw_colored_polygon(skin, _tint(blue,0.93))
	_oval(Vector2.ZERO,r,blue_dark,4.4,-1.68,1.68)
	_oval(Vector2.ZERO,r,mint,2.4,-1.64,1.64)
	var core := Vector2(-1.0,0)
	draw_circle(core,r.y*0.91,_tint(blue,0.37),true,-1.0,true)
	# Three luminous plasma arms wind inward to the core under the mechanical rings.
	for arm in 3:
		var coil := PackedVector2Array()
		for j in 21:
			var u := float(j)/20.0
			var a := float(arm)*TAU/3.0 + age*9.0 + u*3.8
			var radius := pow(1.0-u,0.78)
			coil.append(core + Vector2(cos(a)*r.x*0.81,sin(a)*r.y*0.87)*radius)
		draw_polyline(coil,_tint(blue_dark,0.90),5.5,true)
		draw_polyline(coil,_tint(mint,0.97),3.6,true)
		draw_polyline(coil.slice(4,17),Color.WHITE,1.9,true)
	draw_circle(core,r.y*0.24,mint,true,-1.0,true)
	draw_circle(core,r.y*0.145,Color.WHITE,true,-1.0,true)
	draw_line(Vector2(-r.x*0.42,0),Vector2(r.x*0.71,0),_tint(ICE,0.74),1.4,true)
	for i in 3:
		var travel := fposmod(age * 3.0 + float(i)/3.0,1.0)
		var hub := Vector2(lerpf(r.x*0.44,-r.x*1.04,travel),0)
		var ring_radii := Vector2(7.5+3.5*travel,r.y*(0.77+0.23*sin(travel*PI)))
		var strength := 0.9-0.28*travel
		_oval(hub,ring_radii,_tint(blue_dark,strength),4.2)
		_oval(hub,ring_radii,_tint(violet if i%2==0 else mint,strength),2.0)
		var angle := age*12.0+float(i)*2.2
		var bead := hub+Vector2(cos(angle)*ring_radii.x,sin(angle)*ring_radii.y)
		draw_circle(bead,2.5,Color.WHITE,true,-1.0,true)
	if hits > 0:
		for i in mini(hits,4):
			var a := age*7.0+i*TAU/4.0
			_chip(Vector2(cos(a)*r.x*0.72,sin(a)*r.y*0.88),2.8,a,Color.WHITE)

func _rail_impact(e: Dictionary, t: float) -> void:
	var p: Vector2 = e.p
	var full: bool = e.rail_super
	var finish: bool = full and int(e.rail_hit) >= 5
	var direction: int = e.facing
	var alpha := (1.0-t)*(1.0-t)
	var progress := sqrt(t)
	var reach := (65.0 if finish else (30.0 if full else 22.0))
	if finish:
		_oval(p,Vector2(17+52*progress,11+34*progress),_tint(PLASMA_AZURE,alpha),4.6)
		_oval(p,Vector2(22+58*progress,15+38*progress),_tint(ICE,alpha),2.4)
	# Split the final discharge into a wider fan pointing along the incoming shot.
	for i in (9 if finish else 4):
		var spread := (float(i)/float(8 if finish else 3)-0.5)*2.0
		var a := spread*1.44 + (0.80 if not finish and int(e.rail_hit)%2==0 else 0.0)
		var axis := Vector2(direction*cos(a),sin(a))
		var edge := axis.orthogonal()
		var origin := p+axis*progress*13.0
		var end := p+axis*reach*(0.60+0.40*progress)
		var arc := PackedVector2Array([origin,origin.lerp(end,0.35)+edge*5.5,origin.lerp(end,0.59)-edge*2.8,end])
		draw_polyline(arc,_tint(PLASMA_AZURE,alpha),3.4,true)
		draw_polyline(arc,_tint(ICE,alpha),1.35,true)

func _chip(p: Vector2, size: float, angle: float, color: Color) -> void:
	var nose:=Vector2.from_angle(angle)*size*1.65
	var edge:=nose.orthogonal()*0.51
	draw_colored_polygon(PackedVector2Array([p+nose,p+edge,p-nose*0.65,p-edge]),color)

func _claw_curve(p: Vector2, control: Vector2, tip: Vector2) -> PackedVector2Array:
	var path := PackedVector2Array()
	for k in 10:
		var u := float(k)/9.0
		path.append(p.lerp(control,u).lerp(control.lerp(tip,u),u))
	return path

func _throw_gesture(f) -> void:
	var grabbing: bool = f.state=="throw_hold"
	var palm: Vector2
	var openness := 1.0
	var opacity := 1.0
	if grabbing and fighters.size()==2:
		var caught = fighters[1-f.side_index]
		if not is_instance_valid(caught): return
		palm = f.position.lerp(caught.position,0.62)-Vector2(0,GRIP_HEIGHT[f.fighter_id])
		openness = 0.27
	else:
		var phase: float = f.move_time/maxf(f.startup,0.01)
		if phase<0.38: return
		var recovery: float = maxf(0.0,f.move_time-f.startup-f.active_time)
		var retract := smoothstep(0.01,0.20,recovery)
		opacity = (1.0-retract) * smoothstep(0.37,0.67,phase)
		if opacity<0.01: return
		var reach := 39.0 + 34.0 * smoothstep(0.38,1.05,phase)
		openness = lerpf(1.0,0.44,clampf(phase-0.6,0,1)) + retract*0.5
		palm = f.position + Vector2(f.facing*(reach - 24.0*retract),-float(GRIP_HEIGHT[f.fighter_id])-6.0)
	draw_set_transform(palm,0.0,Vector2(f.facing,1))
	# Two pairs of hooked claw marks close around the opposing lapel. An empty reach fades open.
	for half: float in [-1.0,1.0]:
		var gap := 8.5 + 10.5*openness
		for i in 2:
			var offset := float(i)*5.0
			var start := Vector2(-18.0-offset,half*(gap+offset-3.0))
			var bow := Vector2(2.0-offset,half*(gap+offset+8.0))
			var tip := Vector2(11.0-offset,half*(gap-5.5+offset*0.6))
			var claw := _claw_curve(start,bow,tip)
			draw_polyline(claw,_tint(THROW_INK,opacity*0.97),4.5,true)
			draw_polyline(claw,_tint(THROW_VIOLET,opacity),2.9,true)
			draw_polyline(claw.slice(5),_tint(THROW_PEAK,opacity),1.5,true)
	if grabbing:
		for half: float in [-1.0,1.0]:
			_chip(Vector2(13,half*8),2.8,half*0.6,_tint(THROW_PEAK,0.95))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _throw_break(p: Vector2, t: float) -> void:
	var spread := sqrt(t)
	var alpha := 1.0-smoothstep(0.30,1.0,t)
	for dir: float in [-1.0,1.0]:
		var local := p+Vector2(dir*(3.0+29.0*spread),0)
		draw_set_transform(local,0,Vector2(dir,1))
		# A split semicircle moves with each fighter; the cap accents point outward.
		var radii := Vector2(9.0+4.0*spread,20.0+8.0*spread)
		_oval(Vector2.ZERO,radii,_tint(THROW_INK,alpha),5.3,-1.40,1.40)
		_oval(Vector2.ZERO,radii,_tint(THROW_VIOLET,alpha),3.3,-1.40,1.40)
		_oval(Vector2.ZERO,radii,_tint(THROW_PEAK,alpha),1.6,-1.30,-0.15)
		var tip := PackedVector2Array([Vector2(16,-4),Vector2(22,0),Vector2(16,4)])
		draw_polyline(tip,_tint(THROW_INK,alpha),3.8,true)
		draw_polyline(tip,_tint(THROW_PEAK,alpha),1.8,true)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
	var split := PackedVector2Array([p+Vector2(4,-15),p+Vector2(-3,-1),p+Vector2(2,-3),p+Vector2(-4,14)])
	draw_polyline(split,_tint(THROW_INK,alpha),4.8,true)
	draw_polyline(split,_tint(THROW_PEAK,alpha),2.4,true)

func _throw_arc(event: Dictionary, t: float) -> void:
	var trail: PackedVector2Array=event.trail
	var dir: int=event.facing
	var fade := 1.0 - smoothstep(0.56,1.0,t)
	if trail.size()>=2:
		# Follow the victim's actual flight, including throws against the edge of the stage.
		draw_polyline(trail,_tint(THROW_INK,fade*0.86),6.1,true)
		draw_polyline(trail,_tint(THROW_VIOLET,fade),3.8,true)
		draw_polyline(trail.slice(floori(trail.size()*0.40)),_tint(THROW_PEAK,fade),1.8,true)
		if trail.size()>5:
			var echo := PackedVector2Array()
			for i in range(1,trail.size()-2):
				echo.append(trail[i]+Vector2(-dir*4,5.0+4.0*i/trail.size()))
			draw_polyline(echo,_tint(THROW_VIOLET,fade*0.72),1.6,true)
	var flash := 1.0-smoothstep(0.16,0.62,t)
	if flash>0.01:
		# A short release flourish bridges the impact stop before the moving trail can form.
		var mark: Vector2 = event.p
		for i in 2:
			var start := mark+Vector2((-25-i*5)*dir,12+i*6)
			var elbow := mark+Vector2(4*dir,20+i*5)
			var tip := mark+Vector2((18+9.0*sqrt(t)+i*2)*dir,-8-i*5)
			var stroke := _claw_curve(start,elbow,tip)
			draw_polyline(stroke,_tint(THROW_INK,flash),4.3-i,true)
			draw_polyline(stroke,_tint(THROW_VIOLET,flash),2.6-i*0.5,true)
			draw_polyline(stroke.slice(5),_tint(THROW_PEAK,flash),1.4,true)
	var snapped := 1.0-smoothstep(0.08,0.65,t)
	draw_set_transform(event.p,0.0,Vector2(dir,1))
	for half: float in [-1.0,1.0]:
		var spread := 5.0*sqrt(t)
		var arc := _claw_curve(Vector2(-15,half*(14+spread)),Vector2(3,half*(22+spread)),Vector2(12,half*(7+spread)))
		draw_polyline(arc,_tint(THROW_INK,snapped),4.5,true)
		draw_polyline(arc,_tint(THROW_PEAK,snapped),2.3,true)
		_chip(Vector2(15+10*sqrt(t),half*(8+14*sqrt(t))),2.6,half*0.55,_tint(THROW_VIOLET,snapped))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)


func _guard_impact(e: Dictionary, t: float) -> void:
	var alpha := 1.0 - smoothstep(0.38,1.0,t)
	var spread := sqrt(t)
	var height := (43.0 + 6.0 * spread) * (1.03 if e.weight > 1.0 else 0.93)
	var center: Vector2 = e.guard_center
	draw_set_transform(center,0.0,Vector2(float(e.facing),1))
	# The raised central ridge faces the incoming hit. The translucent blue facets stay
	# between the cat's paws and the hit point, below eye level.
	var body := PackedVector2Array([Vector2(8,-height),Vector2(-6,-height*0.73),
		Vector2(-16,-height*0.32),Vector2(-18,height*0.10),Vector2(-12,height*0.56),
		Vector2(6,height),Vector2(18,height*0.64),Vector2(21,-height*0.35)])
	var edge := body.duplicate()
	edge.append(body[0])
	draw_colored_polygon(body,_tint(Color("#0b456e"),0.69*alpha))
	draw_colored_polygon(PackedVector2Array([body[0],body[1],body[2],body[3],body[4],body[5],Vector2(2,1)]),
		_tint(Color("#19bff2"),0.58*alpha))
	draw_polyline(edge,_tint(Color("#182b4a"),alpha),5.4,true)
	draw_polyline(edge,_tint(Color("#46dbff"),alpha),2.7,true)
	draw_polyline(PackedVector2Array([body[0],body[1],body[2],body[3],body[4]]),_tint(Color("#e3ffff"),alpha),2.2,true)
	var joint := Vector2(1,-1)
	for index in [0,3,5,7]:
		draw_line(joint,body[index],_tint(ICE,alpha*0.65),1.3,true)
	var flash := clampf(1.0-t*1.8,0.0,1.0)
	_chip(joint-Vector2(10,0),3.0+3.0*flash,0.0,_tint(Color.WHITE,flash))
	for i in 2:
		var wave_x := 18.0+spread*(13.0+i*9.0)+i*4.0
		var radii := Vector2(21.0+wave_x*0.52,height*(0.94+0.13*i))
		var origin := Vector2(-wave_x+radii.x-11.0,0)
		_oval(origin,radii,_tint(Color("#113358"),alpha*(0.95-0.30*i)),4.2-1.1*i,PI-1.03,PI+1.03)
		_oval(origin,radii,_tint(ICE if i==0 else PLASMA_AZURE,alpha*(0.94-0.25*i)),2.3-i*0.4,PI-1.03,PI+1.03)
	for i in 4:
		var a := -0.92+i*0.61
		var loc := Vector2(-cos(a)*(21+25*spread),sin(a)*(24+29*spread))
		_chip(loc,2.1*(1.0-0.5*t),PI-a,_tint(ICE,alpha))
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _launch_trails(e: Dictionary, t: float) -> void:
	var p: Vector2 = e.p
	var facing: int = e.facing
	var strength := 1.0-smoothstep(0.30,0.98,t)
	var rise := sqrt(t)
	for i in 2:
		# Follow-through curves rise from below the contact, in the direction of the knockback.
		var from := p+Vector2((-23.0-i*9.0)*facing,38.0+i*10.0)
		var control := p+Vector2((4.0+i*3.0)*facing,25.0-20.0*rise)
		var to := p+Vector2((13.0+30.0*rise+i*4.0)*facing,-15.0-32.0*rise)
		var curve := PackedVector2Array()
		for k in 12:
			var u := float(k)/11.0
			curve.append(from.lerp(control,u).lerp(control.lerp(to,u),u))
		draw_polyline(curve,_tint(Color("#692d29"),strength),5.7-1.3*i,true)
		draw_polyline(curve,_tint(Color("#ffba37"),strength),3.5-0.9*i,true)
		draw_polyline(curve.slice(6),_tint(Color("#fff4c6"),strength),1.6,true)

func _hit_stamp(e: Dictionary, t: float) -> void:
	var p: Vector2 = e.p
	var direction: int = e.facing
	var weight: float = e.weight
	var flash := 1.0-smoothstep(0.23,0.88,t)
	var radius := ((22.0 if e.normal else 17.0)+4.0*sin(clampf(t/0.4,0,1)*PI))*weight
	var tilt := float(int(e.seed)%4)*0.11
	# Slanted solid spikes give light hits a sharp pop and heavy hits a broader ink silhouette.
	var contour := PackedVector2Array()
	for i in 16:
		var a := float(i)*TAU/16.0 + tilt
		var scale_r := 0.49 if i%2==1 else (1.47 if i%4==0 else 0.90)
		var unit := Vector2(cos(a)*direction*1.07,sin(a)*0.88)
		contour.append(unit*radius*scale_r)
	var rim := PackedVector2Array()
	for v in contour: rim.append(p+v)
	rim.append(rim[0])
	draw_polyline(rim,_tint(Color("#342336"),flash),2.7,true)
	for layer in 4:
		var layer_scale: float = [1.0,0.88,0.65,0.34][layer]
		var layer_color: Color = [Color("#4b2837"),Color("#eb542c"),Color("#ffc541"),Color("#fff8d7")][layer]
		var star := PackedVector2Array()
		for v in contour: star.append(p+v*layer_scale)
		draw_colored_polygon(star,_tint(layer_color,flash))
	var spread := sqrt(t)
	for i in (8 if weight>1.2 else 5):
		var a := TAU * float(i) / (8.0 if weight>1.2 else 5.0) + tilt*1.8
		var axis := Vector2(cos(a)*direction,sin(a)*0.84)
		var side := axis.orthogonal()
		var begin := p + axis*(19.0+11.0*spread)*weight
		var end := p + axis*(28.0+21.0*spread+(i%2)*5.5)*weight
		var arrow := PackedVector2Array([begin-side*2.4, end, begin+side*2.4])
		draw_colored_polygon(arrow,_tint(Color("#4b2837"),1.0-t))
		draw_line(begin,end,_tint(GOLD,1.0-t),1.8,true)
	if e.launch:
		_oval(p,Vector2(18+43*spread,10+24*spread),_tint(Color("#fff2ad"),flash),2.6)
		_oval(p,Vector2(23+48*spread,13+28*spread),_tint(Color("#ec622d"),flash),1.7)

func _impact(e: Dictionary) -> void:
	var t := clampf(float(e.age)/float(e.life),0,1)
	match e.get("throw_event",""):
		"tech":
			_throw_break(e.p,t)
			return
		"release":
			_throw_arc(e,t)
			return
	if e.get("stone",false): _heave_pavers(e.stone_origin,e.facing,e.age)
	if e.block:
		_guard_impact(e,t)
		return
	if int(e.rail_hit)>0: _rail_impact(e,t)
	if e.lift: _launch_trails(e,t)
	_hit_stamp(e,t)
