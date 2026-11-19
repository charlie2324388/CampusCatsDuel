extends SceneTree

const F = preload("res://scripts/fighter.gd")
const DT := 1.0/60.0
const CATS := ["mirinda","doctor","orange"]
const BUTTON := {"J":"light","K":"heavy","U":"special","I":"super"}
var assertions := 0
var errors := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		errors += 1
		printerr("FAIL ",message)

func _route(cat: String, route: String, reverse: bool=false, corner: bool=false) -> Dictionary:
	var a=F.new()
	var b=F.new()
	a.setup(cat,1 if reverse else 0)
	b.setup("orange",0 if reverse else 1)
	var origin:=235.0 if corner and reverse else (760.0 if corner else 450.0)
	a.position.x=origin
	b.position.x=origin+(-119.0 if reverse else 119.0)
	a.energy=200
	var starts: Array[String]=[]
	var hits: Array[int]=[]
	var lifted: Array[bool]=[]
	var kinds: Array[String]=[]
	a.move_started.connect(func(kind): starts.append(a.combo_route); kinds.append(kind))
	a.impact.connect(func(_p,_k,block): 
		hits.append(-1 if block else a.combo_hits)
		lifted.append(not b.grounded))
	var index:=0
	var last_tap:=-5
	for frame in range(240):
		var keys:={}
		# First hit is neutral. Every subsequent button is manually tapped as soon
		# as its predecessor connects; after hit one the opponent holds defense.
		if index<route.length() and frame-last_tap>=2 and (index==0 or hits.size()>=index):
			keys[BUTTON[route[index]]]=true
			index+=1
			last_tap=frame
		F.tick_pair(a,b,keys,{"down":not hits.is_empty()},DT)
	var result:={"starts":starts,"hits":hits,"lifted":lifted,"energy":a.energy,"hp":b.hp,"gap":absf(a.position.x-b.position.x)}
	a.free()
	b.free()
	return result

func _run() -> void:
	for cat in CATS:
		for route in ["JJJJ","JJJK","KKK","JJU","JJI","KKI","JJJJI","JJJKI","KKKI"]:
			for variant in [0,1]:
				var result:=_route(cat,route,variant==1,variant==1)
				var needed: int =route.length() + ((3 if cat=="mirinda" else (4 if cat=="doctor" else 0)) if route.ends_with("I") else 0)
				var expected:Array[int]=[]
				for n in range(1,needed+1): expected.append(n)
				_check(result.starts.size()==route.length() and result.starts.back()==route,
					"%s starts %s (variant %d): %s"%[cat,route,variant,result])
				_check(result.hits==expected,"%s true combo %s (variant %d): %s"%[cat,route,variant,result])
				if route=="JJJK": _check(true in result.lifted,"JJJK pops defender off the floor")
				if route.ends_with("I"): _check(is_zero_approx(result.energy),"two full stocks consumed")
				if route.ends_with("U"): _check(is_equal_approx(result.energy,100.0),"one stock consumed")
	for condition in ["guard","miss","hold","rapid","reset","no_meter","air","interrupted"]:
		var a=F.new()
		var b=F.new()
		a.setup("doctor",0)
		b.setup("mirinda",1)
		a.position.x=390
		b.position.x=840 if condition=="miss" else 504
		a.energy=0 if condition=="no_meter" else 200
		var moves:Array[String]=[]
		a.move_started.connect(func(_kind): moves.append(a.combo_route))
		for frame in range(150):
			var keys:={}
			var other:={}
			if frame==0 and condition=="air":
				keys.jump=true
			if frame==(1 if condition=="air" else 0) or (condition=="hold" and frame<100):
				keys.light=true
			if frame==(2 if condition=="interrupted" else 8) and condition in ["miss","guard","no_meter","air","interrupted"]:
				keys.super=true
			if frame in [2,4,6] and condition=="rapid": keys.light=true
			if condition=="guard": other.down=true
			if condition=="interrupted" and frame==0: other.light=true
			if condition=="reset" and frame==52: keys.light=true
			F.tick_pair(a,b,keys,other,DT)
		match condition:
			"miss","guard","air","interrupted":
				_check(not "JI" in moves and not "I" in moves and is_equal_approx(a.energy,200),"no spending on "+condition+str(moves))
			"no_meter": _check(moves==["J"] and a.energy<100.0,"insufficient stock rejects cancel")
			"hold": _check(moves==["J"],"a held button generates a single jab")
			"rapid": _check(moves==["J","JJ","JJJ","JJJJ"],"rapid individual taps buffered in order: "+str(moves))
			"reset": _check(moves==["J","J"],"expired chain starts over")
		a.free()
		b.free()
	_duel_priority()
	_phase_bonuses()
	_late_active_link()
	_wave_tests()
	_launch_checks()
	_damage_scaling()
	print("Combo regression: %d checks, %d failures"%[assertions,errors])
	quit(1 if errors else 0)

func _actors(id_a:String,id_b:String,swap:bool=false) -> Array:
	var a=F.new()
	var b=F.new()
	a.setup(id_a,1 if swap else 0)
	b.setup(id_b,0 if swap else 1)
	a.position.x=480
	b.position.x=a.position.x+(-115 if swap else 115)
	return [a,b]

func _step(p:Array,one:Dictionary,two:Dictionary,swap:bool=false) -> void:
	if swap: F.tick_pair(p[1],p[0],two,one,DT)
	else: F.tick_pair(p[0],p[1],one,two,DT)

func _duel_priority() -> void:
	for swap in [false,true]:
		for specs in [
			["doctor","doctor","special","light",true],
			["doctor","doctor","super","special",true],
			["orange","doctor","super","special",true],
			["mirinda","doctor","special","special",true],
			["doctor","orange","super","super",false],
			["doctor","doctor","special","special",false],
			["doctor","doctor","super","super",false]
		]:
			var p:=_actors(specs[0],specs[1],swap)
			p[0].energy=200
			p[1].energy=200
			for frame in range(105):
				_step(p,{specs[2]:true} if frame==0 else {},{specs[3]:true} if frame==0 else {},swap)
			if specs[4]:
				_check(p[0].hp==p[0].max_hp and p[1].hp<p[1].max_hp,
					"first actor wins matchup %s / swap %s HP %s %s"%[specs,swap,p[0].hp,p[1].hp])
			elif specs[0]==specs[1]:
				var neutral_damage:int=F.SKILLS[specs[0]][specs[2]].damage
				_check(p[0].hp==p[0].max_hp-neutral_damage and p[0].hp==p[1].hp,
					"equal-timing skill trades exact regular damage %s"%specs[2])
			else:
				_check(p[1].hp==p[1].max_hp and p[0].hp==p[0].max_hp-roundi(1.2*F.SKILLS.orange.super.damage),
					"faster equal-tier super interrupts and counters slower startup")
			for fighter in p: fighter.free()
	for cat in CATS:
		for move in ["special","super"]:
			var p:=_actors(cat,"mirinda")
			p[0].energy=200
			p[1].position.x=815
			_step(p,{move:true},{})
			var visible_tier:int=2 if move=="super" else 1
			_check(p[0].invulnerability_tier()==visible_tier,"startup immunity "+cat+move)
			# Measure exactly at the final active instant and one ten-thousandth later.
			p[0].move_time=p[0].startup+p[0].active_time
			_check(p[0].invulnerability_tier()==visible_tier,"final active instant immune")
			p[0].move_time+=0.0001
			_check(p[0].invulnerability_tier()==0,"first recovery instant vulnerable")
			for fighter in p: fighter.free()
			for punish in ["light","heavy"]:
				_guard_punish(cat,move,punish)
	for swap in [false,true]:
		var p:=_actors("doctor","doctor",swap)
		p[0].energy=100
		p[1].energy=100
		p[0].hp=14
		p[1].hp=14
		for frame in 30: _step(p,{"special":true} if frame==0 else {},{"special":true} if frame==0 else {},swap)
		_check(p[0].hp==0 and p[1].hp==0,"same-tier simultaneous double KO")
		for fighter in p: fighter.free()
		var distant:=_actors("mirinda","mirinda",swap)
		distant[0].position.x=130
		distant[1].position.x=830
		for f in distant: f.energy=100
		for frame in 65: _step(distant,{"special":true} if frame==0 else {},{"special":true} if frame==0 else {},swap)
		_check(distant[0].hp==distant[0].max_hp and distant[1].hp==distant[1].max_hp,"out-of-range equal tier casts do not collide")
		for f in distant:f.free()

func _guard_punish(cat:String,move:String,punish:String) -> void:
	var p:=_actors(cat,"mirinda")
	# Place fighters at body-contact spacing, as after a blocked rush in the corner.
	p[1].position.x=F.RIGHT_EDGE
	p[0].position.x=p[1].position.x-p[0].config.width-p[1].config.width
	p[0].energy=200
	var blocked: Array[bool]=[]
	var hits: Array[int]=[]
	var stuns: Array[float]=[]
	p[0].impact.connect(func(_pt,_kind,guarded): blocked.append(guarded))
	p[1].impact.connect(func(_pt,_kind,guarded):
		hits.append(-1 if guarded else p[1].combo_hits)
		stuns.append(p[0].stun_left))
	var sent:=false
	var sent_follow:=false
	for frame in 180:
		var defend:={"down":true}
		if not blocked.is_empty() and not sent and p[1].stun_left<=0 and p[1].hitstop_left<=0:
			sent=true
			defend={punish:true}
		elif not hits.is_empty() and not sent_follow:
			defend={punish:true}
			sent_follow=true
		_step(p,{move:true} if frame==0 else {"down":true},defend)
	var first:int=roundi(1.2*int(F.NORMALS[punish].damage))
	var second:int=F.FOLLOW_UPS["JJ" if punish=="light" else "KK"].damage
	_check(blocked==[true],cat+move+" guard stops entire move")
	_check(hits==[1,2] and p[0].hp==p[0].max_hp-first-second,cat+move+" actual recovery punish "+punish+" into followup: "+str([hits,p[0].hp]))
	_check(stuns.size()==2 and is_equal_approx(stuns[0],float(F.NORMALS[punish].stun)+4.0/60.0),"PC adds 4 stagger frames on "+cat+move+punish)
	for f in p:f.free()

func _phase_bonuses() -> void:
	# Keep the attack shape fixed and probe the exact defender phase boundaries.
	for phase in ["idle","whiff_startup","active_start","active_end","whiff_recovery","hitstun","guard"]:
		var p:=_actors("mirinda","doctor")
		p[0]._begin_move("light",p[1].position.x)
		p[0].move_time=p[0].startup
		p[1].facing=-1
		if phase in ["whiff_startup","active_start","active_end","whiff_recovery"]:
			p[1]._begin_move("heavy",p[0].position.x)
			match phase:
				"whiff_startup": p[1].move_time=p[1].startup-0.0001
				"active_start": p[1].move_time=p[1].startup
				"active_end": p[1].move_time=p[1].startup+p[1].active_time
				"whiff_recovery": p[1].move_time=p[1].startup+p[1].active_time+0.0001
		elif phase=="hitstun":
			p[1].state="hit"
			p[1].stun_left=0.08
		elif phase=="guard":
			p[1].state="guard"
			p[1]._buttons={"down":true}
		var packet: Dictionary=p[0]._contact(p[1],p[0]._active_strike())
		var frames:int=2 if phase=="whiff_startup" else (4 if phase=="whiff_recovery" else 0)
		_check(not packet.is_empty() and packet.damage==(7 if frames>0 else 6) and
			is_equal_approx(packet.stun,0.14+frames/60.0),"correct counter/punish bonus at "+phase)
		for f in p:f.free()

func _late_active_link() -> void:
	# A deep heavy on the last active frame recovers soon enough to link to
	# an independent jab, but only with the extra recovery-punish hitstun.
	for punish in [false,true]:
		var p:=_actors("mirinda","doctor")
		var a=p[0]
		var b=p[1]
		b.position.x=F.RIGHT_EDGE
		a.position.x=b.position.x-b.config.width-a.config.width
		var starts: Array[String]=[]
		var hits: Array[int]=[]
		a.move_started.connect(func(_k): starts.append(a.combo_route))
		a.impact.connect(func(_p,_k,block): hits.append(-1 if block else a.combo_hits))
		a._begin_move("heavy",b.position.x)
		a.move_time=a.startup+a.active_time-DT*1.25
		if punish:
			b._begin_move("heavy",a.position.x)
			b.move_time=b.startup+b.active_time+0.01
		var sent:=false
		for frame in 85:
			var cmd:={}
			if not hits.is_empty() and a.attack_kind.is_empty() and not sent:
				sent=true
				cmd.light=true
			_step(p,cmd,{"down":frame>0})
		_check(starts==["K","J"],"independent moves do not invent a KJ recipe")
		_check(hits==([1,2] if punish else [1,-1]),"independent heavy -> jab counted only as a true punish link: "+str([punish,hits]))
		for f in p:f.free()

func _wave_tests() -> void:
	for move in ["special","super"]:
		for swap in [false,true]:
			var p:=_actors("doctor","mirinda",swap)
			var a=p[0]
			var b=p[1]
			a.position.x=840.0 if swap else 110.0
			b.position.x=110.0 if swap else 840.0
			a.energy=200
			var launches:Array[String]=[]
			var hits:Array[int]=[]
			var centers:Array[float]=[]
			var facing_on_hit:Array[int]=[]
			a.wave_launched.connect(func(k): launches.append(k))
			a.impact.connect(func(_where,_k,_block): hits.append(a.last_projectile_hit); facing_on_hit.append(a.last_projectile_direction))
			var travel_frames:=0
			var released_and_vulnerable:=false
			for frame in 240:
				_step(p,{move:true} if frame==0 else {},{},swap)
				if not a.projectiles.is_empty():
					var wave: Dictionary=a.projectiles[0]
					centers.append(wave.point.x)
					released_and_vulnerable=released_and_vulnerable or a.invulnerability_tier()==0
					if hits.is_empty(): travel_frames+=1
				if frame==40: _check(b.hp==b.max_hp,"no instant hit across campus: "+move)
			_check(launches==[move] and travel_frames>=45,"one real launch and visible flight "+move)
			_check(centers.front()>centers.back() if swap else centers.front()<centers.back(),"fixed horizontal travel in both directions")
			var expect:Array=[1] if move=="special" else [1,2,3,4,5]
			_check(hits==expect and facing_on_hit.back()==(-1 if swap else 1),"correct actual wave pulses and direction "+move)
			_check(released_and_vulnerable and a.projectiles.is_empty(),"flight independent of caster immunity and clears after last hit")
			for f in p:f.free()
		for scenario in ["jump","interrupted_after","interrupted_before","new_round","ko","cap"]:
			var p:=_actors("doctor","mirinda")
			var a=p[0]
			var b=p[1]
			a.position.x=130
			b.position.x=765
			a.energy=200
			var marks:Array[int]=[]
			var launches:Array[String]=[]
			a.impact.connect(func(_where,_k,_block): marks.append(a.last_projectile_hit))
			a.wave_launched.connect(func(k): launches.append(k))
			var jumped:=false
			var acted:=false
			var cap_protected:=false
			for frame in 230:
				var ka:={move:true} if frame==0 else {}
				var kb:={}
				if scenario=="interrupted_before" and frame==2:
					# Another two-stock technique lands before the hand opens.
					b.position.x=a.position.x+119
					b.energy=200
					b._begin_move("super",a.position.x)
					b.facing=-1
					b.move_time=b.startup-DT*0.5
				if not a.projectiles.is_empty():
					var wave: Dictionary=a.projectiles[0]
					if scenario=="jump" and not jumped and absf(wave.point.x-b.position.x)<215.0:
						kb.jump=true
						jumped=true
					if scenario=="new_round" and not acted:
						acted=true
						a.reset_round()
						b.reset_round()
					if scenario=="interrupted_after" and not acted and a.invulnerability_tier()==0 and absf(wave.point.x-a.position.x)>245:
						acted=true
						# A real jab catches the caster's recovery after the projectile has passed this point.
						var original:Vector2=b.position
						b.position.x=a.position.x+115
						b._begin_move("light",a.position.x)
						b.facing=-1
						b.move_time=b.startup-DT*0.5
						_step(p,{}, {})
						b.position=original
					if scenario=="ko" and not acted and a.invulnerability_tier()==0 and absf(wave.point.x-a.position.x)>245:
						acted=true
						a.hp=1
						b.position.x=a.position.x+115
						b._begin_move("light",a.position.x)
						b.facing=-1
						b.move_time=b.startup-DT*0.5
					if scenario=="cap" and not acted and a.attack_kind.is_empty():
						acted=true
						a.energy=200
						ka={move:true}
				_step(p,ka,kb)
				if scenario=="cap" and acted and launches.size()==1 and a.energy==200:
					cap_protected=true
			match scenario:
				"jump":_check(jumped and marks.is_empty() and a.projectiles.is_empty(),"jump clears traveling wave and it exits arena "+move)
				"interrupted_before":_check(launches.is_empty() and a.hp<a.max_hp,"pre-release interruption prevents projectile creation "+move)
				"interrupted_after":_check(acted and a.hp<a.max_hp and not marks.is_empty(),"released shot survives a genuine recovery punish "+move)
				"new_round":_check(acted and a.projectiles.is_empty() and marks.is_empty() and launches.size()==1,"round reset clears wave")
				"ko":_check(acted and a.hp==0 and a.projectiles.is_empty() and marks.is_empty(),"KO clears both players' waves")
				"cap":_check(cap_protected and launches.size()==1,"one-wave limit never spends a second gauge "+move)
			for f in p:f.free()
	for swap in [false,true]:
		var p:=_actors("doctor","doctor",swap)
		p[0].position.x=836 if swap else 124
		p[1].position.x=124 if swap else 836
		for f in p:f.energy=200
		var shots_alive_together:=false
		var intercepted:=false
		for frame in 220:
			_step(p,{"super":true} if frame==0 else {},{"special":true} if frame==0 else {},swap)
			if not p[0].projectiles.is_empty() and not p[1].projectiles.is_empty(): shots_alive_together=true
			if shots_alive_together and p[1].projectiles.is_empty() and p[1].hp==p[1].max_hp and not p[0].projectiles.is_empty():
				intercepted=true
		_check(intercepted and p[0].hp==p[0].max_hp and p[1].hp<p[1].max_hp,"two-stock projectile overtakes smaller wave at contact")
		for f in p:f.free()

func _launch_checks() -> void:
	for cat in CATS:
		for swap in [false,true]:
			for scenario in ["ground","corner","airborne","block","special","ko","early_ko","timeout"]:
				var p:=_actors(cat,"doctor",swap)
				var a=p[0]
				var b=p[1]
				var direction: int=-1 if swap else 1
				var target_x: float=F.LEFT_EDGE if swap else F.RIGHT_EDGE
				if scenario!="corner": target_x=590.0 if swap else 370.0
				b.position.x=target_x
				a.position.x=b.position.x-115.0*direction
				a.energy=200
				var stages: int=4 if cat=="mirinda" else (5 if cat=="doctor" else 1)
				if scenario=="ko": b.hp=27 if cat=="mirinda" else (30 if cat=="doctor" else 32)
				if scenario=="early_ko": b.hp=3
				var flags:Array[bool]=[]
				var states:Array[String]=[]
				var origin:Array[Vector2]=[]
				a.impact.connect(func(_pos,_kind,_block):
					flags.append(a.last_launch)
					states.append(b.state)
					if a.last_launch: origin.append(b.position))
				var commands:Array[String]=[]
				b.move_started.connect(func(kind):commands.append(kind))
				var peak:float=F.FLOOR_Y
				var landing:=false
				var prepped_air:=false
				var coherent:=true
				var in_bounds:=true
				var min_dx:=0.0
				var last_x:float=b.position.x
				for frame in 270:
					if scenario=="airborne" and not prepped_air and flags.size()==stages-1:
						# Catch a low airborne target on the actual closing hit.
						b.grounded=false
						b.position.y-=37.0
						b.velocity.y=-160.0
						prepped_air=true
					var kb:={"down":true} if scenario=="block" else {}
					if b.launched:
						# No attack, guard or directional drift during forced flight.
						kb={"left":direction>0,"right":direction<0,"heavy":frame%2==0,"jump":frame%2==0,"down":true}
					var before:bool=b.launched
					if not flags.is_empty() and ((b.hp<=0) or (scenario=="timeout" and not origin.is_empty())):
						b.advance_ko_fall(DT)
					else:
						_step(p,{"special" if scenario=="special" else "super":true} if frame==0 else {},kb,swap)
					if b.launched:
						coherent=coherent and not b.grounded and b.state in ["hit","ko"] and b.attack_kind.is_empty()
						if before: min_dx=minf(min_dx,(b.position.x-last_x)*direction)
						if before: coherent=coherent and (b.position.x-last_x)*direction>=-0.001
						in_bounds=in_bounds and b.position.x>=F.LEFT_EDGE and b.position.x<=F.RIGHT_EDGE
						peak=minf(peak,b.position.y)
					if before and not b.launched: landing=true
					last_x=b.position.x
				var name:String=cat+" / "+scenario+(" left" if swap else " right")
				if scenario in ["block","special"]:
					_check(flags==[false] and b.grounded and is_equal_approx(b.position.y,F.FLOOR_Y),"no launch "+name)
					_free_fighters(p)
					continue
				var expected:Array[bool]=[]
				for n in (1 if scenario=="early_ko" else stages):
					expected.append(n==(0 if scenario=="early_ko" else stages-1))
				_check(flags==expected and origin.size()==1,"precise launch stage "+name+" "+str(flags))
				if origin.is_empty():
					_free_fighters(p)
					continue
				var height:float=origin[0].y-peak
				var distance:float=(b.position.x-origin[0].x)*direction
				var threshold:float=110.0 if cat=="mirinda" else (60.0 if cat=="doctor" else 95.0)
				_check(height>=threshold and height<165.0,"track visible physical launch height "+name+" "+str(height))
				_check(coherent and in_bounds and commands.is_empty(),"forced direction and no actions in flight "+name+" "+str([min_dx,commands,in_bounds,coherent]))
				_check(b.grounded and landing and not b.launched and b.velocity.is_zero_approx() and is_equal_approx(b.position.y,F.FLOOR_Y),"stable landing "+name)
				if scenario=="corner":_check(absf(distance)<2.0,"wall stops horizontal drift "+name)
				else:_check(distance>100.0,"real outward knockback "+name)
				if scenario=="airborne":_check(origin[0].y<F.FLOOR_Y-8.0,"airborne victim launched from actual altitude "+name)
				if scenario in ["ko","early_ko"]:_check(b.hp==0 and b.state=="ko","KO shown from actual fatal hit "+name)
				_free_fighters(p)
	# Both closing pulses can launch when HP is committed simultaneously.
	var pair:=_actors("doctor","doctor")
	for actor in pair:
		actor.hp=30
		actor.energy=200
	for frame in 110:
		_step(pair,{"super":true} if frame==0 else {},{"super":true} if frame==0 else {})
		if pair[0].hp<=0 or pair[1].hp<=0:break
	_check(pair[0].hp==0 and pair[1].hp==0 and pair[0].launched and pair[1].launched,"both final waves launch in double KO")
	for frame in 120:
		for actor in pair: actor.advance_ko_fall(DT)
	_check(pair[0].grounded and pair[1].grounded and pair[0].state=="ko" and pair[1].state=="ko","both double KO arcs land")
	_free_fighters(pair)

func _free_fighters(p:Array) -> void:
	for f in p:f.free()

# One projectile can still be hitting after its owner has begun another move.
# An already-counted cast must keep its damage step even when a later cast connects.
func _damage_scaling() -> void:
	var pair:=_actors("doctor","mirinda")
	var a=pair[0]
	var b=pair[1]
	var stamps:=[11,12,13,13,14,13]
	var expected:=[10,10,8,8,6,8]
	for i in stamps.size():
		var packet:Dictionary=a._packet(b,"light",1,10,0.2,b.position,0,0,false,stamps[i])
		_check(packet.damage==expected[i],"damage follows real move identity at contact "+str(i))
		b._receive(packet)
	b.stun_left=0.0
	b.state="idle"
	var fresh:Dictionary=a._packet(b,"light",1,10,0.2,b.position,0,0,false,15)
	_check(fresh.damage==10 and fresh.hit_number==1,"escaping a combo restores full damage")
	for f in pair: f.free()
