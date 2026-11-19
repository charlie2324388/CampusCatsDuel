extends Node2D

const Fighter = preload("res://scripts/fighter.gd")
const Controls = preload("res://scripts/duel_input.gd")
const UI = preload("res://scripts/duel_ui.gd")
const Effects = preload("res://scripts/duel_fx.gd")
const Mixer = preload("res://scripts/arena_sound.gd")
const SuperCutin = preload("res://scripts/super_cutin.gd")
const IDS = ["mirinda","doctor","orange","taffy","pudding"]
const NAMES = ["美年达","烤鸭博士","橘猪","奶糖","布丁"]
const ONE = ["飞身蹬","等离子脉冲","肚皮滑铲","沉肩靠","掠步爪"]
const TWO = ["美年达无影脚","真空磁轨炮","电车冲锋","镇岳掌","折光三叠"]
const STAGE_TIME := 45.0
const BG := preload("res://art/garden_ring.png")

var state := "select"
var picks := [0,1]
var cursor := 0
var vs_cpu := true
var fighters: Array = []
var wins := [0,0]
var seconds_left := STAGE_TIME
var round_no := 1
var round_winner := -1
var match_winner := -1
var notice := ["",""]
var notice_left := [0.0,0.0]
var announcement := ""
var state_time := 0.0
var from_pause := ""
var guide_from := ""
var cutin = SuperCutin.new()
var pending_supers: Array[int] = []
var chain_hits := [0,0]
var chain_route := ["",""]
var chain_linger := [0.0,0.0]
var controls = Controls.new()
var arena := Node2D.new()
var fx = Effects.new()
var sound = Mixer.new()
var hud = UI.new()
var shake := 0.0
var motor_active := [false,false]
var closing := false
var touch_layout := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	touch_layout=DisplayServer.is_touchscreen_available() or "--touch-preview" in OS.get_cmdline_user_args()
	add_child(sound)
	add_child(arena)
	arena.process_mode=Node.PROCESS_MODE_PAUSABLE
	var bg := Sprite2D.new()
	bg.texture=BG
	bg.centered=false
	bg.position=Vector2(-3,-2)
	bg.scale=Vector2(966,544)/BG.get_size()
	arena.add_child(bg)
	bg.z_index=-10
	arena.add_child(fx)
	fx.z_index=10
	arena.hide()
	var top := CanvasLayer.new()
	add_child(top)
	hud.game=self
	top.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top.add_child(cutin)
	cutin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad=preload("res://scripts/mobile_pad.gd").new()
	pad.game=self
	top.add_child(pad)
	touch_layout=pad.enabled
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().auto_accept_quit=false
	get_window().close_requested.connect(_close)

func _close() -> void:
	if closing: return
	closing=true
	sound.silence()
	await get_tree().create_timer(0.15,true).timeout
	get_tree().quit()

func choose(index:int) -> void:
	if state!="select": return
	picks[cursor]=posmod(index,IDS.size())
	sound.play("select")

func set_slot(index:int) -> void:
	cursor=clampi(index,0,1)

func toggle_mode() -> void:
	if state=="select":
		vs_cpu=not vs_cpu
		sound.play("select")

func start_match() -> void:
	if state!="select" and state!="match_end": return
	_dispose_fighters()
	get_tree().paused=false
	wins=[0,0]
	match_winner=-1
	round_no=1
	for side in 2:
		var cat = Fighter.new()
		arena.add_child(cat)
		cat.setup(IDS[picks[side]],side)
		cat.impact.connect(_impact.bind(side))
		cat.throw_teched.connect(_throw_tech)
		cat.move_started.connect(_move.bind(side))
		cat.wave_launched.connect(_wave_audio)
		fighters.append(cat)
	fx.fighters=fighters
	arena.show()
	_begin_round(false)
	sound.play("select")

func _begin_round(carry:bool) -> void:
	_reset_presentation()
	for cat in fighters:
		var saved: float = cat.energy if carry else 0.0
		cat.reset_round()
		cat.energy=saved
	fx.clear_fx()
	controls.reset_round()
	seconds_left=STAGE_TIME
	notice=["",""]
	notice_left=[0.0,0.0]
	motor_active=[false,false]
	round_winner=-1
	state="intro"
	state_time=1.15
	announcement="第 %d 局"%round_no
	arena.position=Vector2.ZERO

func _dispose_fighters() -> void:
	_reset_presentation()
	for side in 2: sound.stop_motor(side)
	fx.clear_fx()
	for cat in fighters:
		if is_instance_valid(cat):
			arena.remove_child(cat)
			cat.queue_free()
	fighters=[]
	fx.fighters=[]
	shake=0.0
	arena.position=Vector2.ZERO

func rematch() -> void:
	start_match()

func to_select() -> void:
	get_tree().paused=false
	_dispose_fighters()
	state="select"
	arena.hide()
	announcement=""

func toggle_guide() -> void:
	if state=="guide":
		state=guide_from
		get_tree().paused=state=="pause"
	elif state in ["select","intro","fight","pause"]:
		guide_from=state
		state="guide"
		get_tree().paused=true
	else:
		return
	sound.play("select")

func toggle_pause() -> void:
	if state=="pause":
		state=from_pause
		get_tree().paused=false
	elif state in ["intro","fight","round_end"]:
		from_pause=state
		state="pause"
		get_tree().paused=true
	else: return
	sound.play("select")

func _unhandled_key_input(e:InputEvent) -> void:
	if not e is InputEventKey or not e.pressed or e.echo: return
	var k:int=e.keycode
	if k==KEY_F11:
		var full:=DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if k==KEY_F2:
		sound.toggle()
		return
	if k==KEY_F1 or (state=="guide" and k in [KEY_ESCAPE,KEY_P,KEY_ENTER]):
		toggle_guide()
		return
	if state=="select":
		match k:
			KEY_TAB: set_slot(1-cursor)
			KEY_1,KEY_2,KEY_3,KEY_4,KEY_5: choose(k-KEY_1)
			KEY_LEFT,KEY_A: choose(picks[cursor]-1)
			KEY_RIGHT,KEY_D: choose(picks[cursor]+1)
			KEY_M: toggle_mode()
			KEY_ENTER,KEY_KP_ENTER: start_match()
	elif state=="match_end":
		if k in [KEY_ENTER,KEY_KP_ENTER,KEY_R]: rematch()
		if k in [KEY_Q,KEY_ESCAPE]: to_select()
	elif k in [KEY_ESCAPE,KEY_P] or (state=="pause" and k==KEY_ENTER):
		toggle_pause()
	elif state=="pause" and k==KEY_Q:
		to_select()

func _physics_process(delta:float) -> void:
	if state in ["select","guide","pause","match_end"] or closing: return
	if state=="cutin":
		_advance_cutin(delta)
		return
	var dt:=delta
	for side in 2:
		chain_linger[side]=maxf(0.0,chain_linger[side]-dt)
	shake=maxf(0,shake-dt)
	arena.position=Vector2(sin(shake*137),cos(shake*109))*shake*26
	for i in 2: notice_left[i]=maxf(0,notice_left[i]-dt)
	if state=="intro":
		state_time-=dt
		if state_time<0.34: announcement="开打！"
		if state_time<=0:
			state="fight"
			announcement=""
		return
	if state=="round_end":
		for cat in fighters:
			if cat.hp<=0 or cat.launched:
				cat.advance_ko_fall(dt)
		state_time-=dt
		if state_time<=0:
			if wins.max()>=2:
				match_winner=0 if wins[0]>wins[1] else 1
				state="match_end"
				announcement=""
				sound.play("clear")
			else:
				if round_winner>=0: round_no+=1
				_begin_round(true)
		return
	var p1:Dictionary=controls.read_player(0)
	var p2:Dictionary=controls.read_cpu(fighters[1],fighters[0],dt) if vs_cpu else controls.read_player(1)
	Fighter.tick_pair(fighters[0],fighters[1],p1,p2,dt)
	_sync_cast_audio()
	seconds_left=maxf(0,seconds_left-dt)
	if fighters[0].hp<=0 or fighters[1].hp<=0 or seconds_left<=0.0:
		pending_supers.clear()
		_finish_round()
	elif not pending_supers.is_empty():
		_start_next_cutin()

func _reset_presentation() -> void:
	pending_supers.clear()
	cutin.cancel()
	fx.set_process(true)
	chain_hits=[0,0]
	chain_route=["",""]
	chain_linger=[0.0,0.0]

func _start_next_cutin() -> void:
	while not pending_supers.is_empty():
		var side: int=pending_supers.pop_front()
		var actor=fighters[side]
		if actor.attack_kind!="super" or actor.hp<=0:
			continue
		state="cutin"
		fx.set_process(false)
		cutin.begin(actor.fighter_id,side)
		sound.play("charge")
		return
	cutin.cancel()
	fx.set_process(true)
	state="fight"

func _advance_cutin(delta: float) -> void:
	if not cutin.advance(delta):
		_start_next_cutin()

func _finish_round() -> void:
	for side in 2:
		sound.stop_motor(side,true)
		fighters[side].release_grip()
	var a:int=fighters[0].hp
	var b:int=fighters[1].hp
	round_winner=-1 if a==b else (0 if a>b else 1)
	if round_winner>=0:
		wins[round_winner]+=1
	announcement="双 KO · 加赛" if a==0 and b==0 else ("平手 · 加赛" if round_winner<0 else (("时间到" if seconds_left<=0 else "K.O.")+"   "+NAMES[picks[round_winner]]+" 胜"))
	state="round_end"
	state_time=1.5

func _move(kind:String,side:int) -> void:
	if kind=="super":
		pending_supers.append(side)
	if kind in ["special","super"]:
		notice[side]=ONE[picks[side]] if kind=="special" else TWO[picks[side]]
		notice_left[side]=1.0

func _wave_audio(kind: String) -> void:
	sound.play("vacuum_wave" if kind=="super" else "plasma_pulse")

func _sync_cast_audio() -> void:
	for side in 2:
		var cat=fighters[side]
		var kind:String=cat.attack_kind
		var driving: bool=cat.fighter_id=="orange" and kind=="super" and cat.move_time>=minf(0.07,cat.startup*0.5) and cat.move_time<=cat.startup+cat.active_time
		if driving and not motor_active[side]:
			motor_active[side]=true
			sound.start_motor(side)
		if motor_active[side] and not driving:
			motor_active[side]=false
			sound.stop_motor(side,true)

func _throw_tech(point:Vector2) -> void:
	fx.on_throw_tech(point)
	for side in 2:
		notice[side]="拆投"
		notice_left[side]=0.58
	sound.play("guard")

func _impact(point:Vector2,kind:String,blocked:bool,side:int) -> void:
	fx.on_impact(point,kind,blocked,fighters[side])
	if blocked:
		if fighters[side].last_block_recovery:
			notice[side]="被防 · 收招"
			notice_left[side]=0.72
		notice[1-side]="防住！"
		notice_left[1-side]=0.50
		sound.play("guard")
	else:
		var attacker=fighters[side]
		if kind=="throw":
			notice[side]="近身投"
			notice_left[side]=0.58
		chain_hits[side]=attacker.combo_hits
		chain_route[side]=attacker.last_impact_route
		chain_linger[side]=0.9
		var launcher: bool=attacker.last_launch
		if attacker.fighter_id=="taffy" and kind in ["special","super"]:
			sound.play("stone_palm" if kind=="super" else "hit")
		elif attacker.fighter_id=="pudding" and kind in ["special","super"]:
			sound.play("prism_finish" if launcher else "prism_swipe")
		elif attacker.fighter_id=="doctor" and kind in ["special","super"]:
			sound.play("wave_finish" if launcher else "wave_impact")
		elif kind=="heavy" or launcher:
			sound.play("kick_finish")
		else:
			sound.play("kick_impact_1")
		if kind=="throw":
			shake=maxf(shake,0.09)
		elif kind in ["heavy","super"]:
			shake=maxf(shake,0.16 if launcher else 0.085)
