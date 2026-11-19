extends SceneTree

const F=preload("res://scripts/fighter.gd")
const Pad=preload("res://scripts/duel_input.gd")
const DT:=1.0/60.0
const CATS:=["mirinda","doctor","orange"]
var count:=0
var failures:=0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok:bool, label:String)->void:
	count+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)

func _pair(id:String,swap:bool=false)->Array:
	var a=F.new()
	var b=F.new()
	a.setup(id,1 if swap else 0)
	b.setup("mirinda",0 if swap else 1)
	a.position.x=520 if swap else 380
	b.position.x=a.position.x+(-1 if swap else 1)*(a.config.width+b.config.width+3.0)
	return [a,b]

func _step(p:Array,a_keys:Dictionary,b_keys:Dictionary,swap:bool=false)->void:
	if swap: F.tick_pair(p[1],p[0],b_keys,a_keys,DT)
	else: F.tick_pair(p[0],p[1],a_keys,b_keys,DT)

func _close(p:Array)->void:
	for actor in p:actor.free()

func _pressed(code:Key,yes:bool)->void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=yes
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame

func _physical_keys()->void:
	var pads=Pad.new()
	var p:=_pair("doctor")
	var techs:=[]
	p[0].throw_teched.connect(func(_point):techs.append(0))
	p[1].throw_teched.connect(func(_point):techs.append(1))
	await _pressed(KEY_L,true)
	await _pressed(KEY_SLASH,true)
	_check(pads.read_player(0).get("throw",false) and pads.read_player(1).get("throw",false),"physical L and slash bind both throws")
	for frame in 12:F.tick_pair(p[0],p[1],pads.read_player(0),pads.read_player(1),DT)
	_check(techs==[0] and p[0].hp==p[0].max_hp and p[1].hp==p[1].max_hp,"both physical keyboards produce a single tech")
	await _pressed(KEY_L,false)
	await _pressed(KEY_SLASH,false)
	_close(p)

func _basic(id:String,swap:bool,scenario:String)->void:
	var p:=_pair(id,swap)
	var a=p[0]
	var b=p[1]
	var direction:float=-1.0 if swap else 1.0
	if scenario=="corner":
		b.position.x=F.LEFT_EDGE if swap else F.RIGHT_EDGE
		a.position.x=b.position.x-direction*(a.config.width+b.config.width+3.0)
	if scenario=="ko":b.hp=1
	var damage0:int=b.hp
	var hits:=[]
	var attempts:=[]
	var enemy_attacks:=[]
	var held:=false
	var height:=0.0
	var reset:=false
	var released:=false
	var release_x:=[0.0]
	var damage_before_release:=true
	var stable:=true
	a.move_started.connect(func(k):attempts.append(k))
	a.impact.connect(func(_point,kind,blocked):hits.append([kind,blocked,b.launched]); release_x[0]=b.position.x)
	b.move_started.connect(func(kind):enemy_attacks.append(kind))
	for frame in 145:
		var grabbed:bool=a.state=="throw_hold" and b.state=="grabbed"
		if grabbed:
			held=true
			height=maxf(height,F.FLOOR_Y-b.position.y)
			damage_before_release=damage_before_release and b.hp==damage0
			if scenario=="reset" and not reset:
				reset=true
				a.reset_round()
				b.reset_round()
			if scenario=="timeout" and not released:
				released=true
				a.release_grip()
				b.release_grip()
		var buttons:={"down":true}
		if grabbed and scenario!="timeout" and scenario!="reset":
			buttons={"heavy":frame%2==0,"jump":frame%2==0,"throw":frame%2==0,"right":true}
		if b.hp==0:
			b.advance_ko_fall(DT)
		else:
			_step(p,{"throw":frame==0 or (scenario=="hold_key" and frame<100)},buttons,swap)
		stable=stable and a.position.x>=F.LEFT_EDGE and a.position.x<=F.RIGHT_EDGE and b.position.x>=F.LEFT_EDGE and b.position.x<=F.RIGHT_EDGE
	var label:=id+"/"+scenario+(" left" if swap else " right")
	_check(held and damage_before_release,"real paired capture before damage "+label)
	if scenario in ["reset","timeout"]:
		_check(hits.is_empty() and a.state!="throw_hold" and b.state!="grabbed" and b.grounded,"reset/timeout safely tears down capture "+label)
	else:
		_check(attempts==["throw"] and hits==[["throw",false,true]],"one guard-breaking throw "+label+str([attempts,hits]))
		_check(b.hp==maxi(0,damage0-F.THROW_DAMAGE),"throw damage exact and unscaled "+label)
		_check(height>18.0 and enemy_attacks.is_empty() and stable and b.grounded and not b.launched,"lift, control lock, legal bounds and landing "+label)
		if scenario!="corner":_check((b.position.x-float(release_x[0]))*direction>66.0,"outward travel "+label)
		if scenario=="ko":_check(b.state=="ko","throw KO lands "+label)
	_close(p)

func _duel(swap:bool,delay:int)->void:
	var p:=_pair("orange",swap)
	var techs:=[]
	var hits:=[]
	p[0].throw_teched.connect(func(_p):techs.append(p[0].side_index))
	p[1].throw_teched.connect(func(_p):techs.append(p[1].side_index))
	p[0].impact.connect(func(_p,k,_blocked):hits.append(k))
	for f in 85:_step(p,{"throw":f==0},{"throw":f==delay},swap)
	var expect_tech:=delay<=3
	_check(techs==([0] if expect_tech else []),"single symmetric tech at delay "+str([delay,swap,techs]))
	_check(hits==([] if expect_tech else ["throw"]) and p[0].hp==p[0].max_hp,"late tech loses to first grab "+str([delay,swap,hits]))
	if expect_tech:_check(p[1].hp==p[1].max_hp,"tech causes zero damage")
	_close(p)

func _denied(id:String,condition:String)->void:
	var p:=_pair(id)
	var a=p[0]
	var b=p[1]
	var hits:=[]
	var attempts:=[]
	var foe_hits:=[]
	a.impact.connect(func(_p,k,_blocked):hits.append(k))
	a.move_started.connect(func(k):attempts.append(k))
	b.impact.connect(func(_p,k,_blocked):foe_hits.append(k))
	if condition in ["far","punish"]:
		b.position.x=a.position.x+a.config.width+b.config.width+23.0
	if condition in ["hitstun","blockstun"]:
		b.stun_left=0.32
		b.state="hit" if condition=="hitstun" else "guard"
	if condition in ["one","two"]:b.energy=200
	for frame in 110:
		var ak:={}
		var bk:={}
		match condition:
			"far","hitstun","blockstun": ak={"throw":frame==0}
			"punish":
				ak={"throw":frame==0,"down":true}
				bk={"heavy":frame==12}
			"jump":
				ak={"throw":frame==0}
				bk={"jump":frame==3}
			"air_throw":ak={"jump":frame==0,"throw":frame==3}
			"one","two":
				ak={"throw":frame==0}
				bk={"special" if condition=="one" else "super":frame==3}
			"cannot_cancel":
				ak={"light":frame==0,"throw":frame==7}
			"incoming_strike":
				ak={"throw":frame==0}
				bk={"light":frame==2}
		_step(p,ak,bk)
	_check(not "throw" in hits,"disallowed catches: "+id+" / "+condition+str(hits))
	if condition in ["cannot_cancel","air_throw"]:_check(not "throw" in attempts,"no unauthorised throw startup "+condition)
	if condition=="punish":_check("heavy" in foe_hits and a.hp<a.max_hp-F.NORMALS.heavy.damage,"whiff is punishable by a real heavy PC")
	_close(p)

func _run()->void:
	for id in CATS:
		for swap in [false,true]:
			for scenario in ["block","corner","hold_key","reset","timeout","ko"]:_basic(id,swap,scenario)
		for condition in ["far","hitstun","blockstun","punish","jump","air_throw","one","two","cannot_cancel","incoming_strike"]:_denied(id,condition)
	for mirrored in [false,true]:
		for delay in [0,2,3,4,8]:_duel(mirrored,delay)
	if not OS.get_cmdline_user_args().has("--core-only"):await _physical_keys()
	print("Throw regression: %d checks, %d failures"%[count,failures])
	quit(1 if failures else 0)
