extends SceneTree
const F=preload("res://scripts/fighter.gd")
const DT:=1.0/60.0
const IDS:=["taffy","pudding"]
var checks:=0
var errors:=0

func _initialize()->void:
	call_deferred("_run")

func _check(ok:bool,what:String)->void:
	checks+=1
	if not ok:
		errors+=1
		printerr("FAIL ",what)

func _trial(id:String,move:String,scenario:String,swap:bool)->Dictionary:
	var a=F.new()
	var b=F.new()
	a.setup(id,1 if swap else 0)
	b.setup("mirinda",0 if swap else 1)
	var distance:float=345.0 if scenario in ["miss","brake"] else a.config.width+b.config.width+3
	if scenario=="edge":distance=145
	var d:int=-1 if swap else 1
	a.position.x=640.0 if swap else 300.0
	b.position.x=a.position.x+d*distance
	a.energy=200 if scenario!="poor" else (199 if move=="super" else 99)
	var old_hp:int=b.hp
	var old_x:float=a.position.x
	var next_button:=0
	var events:=[]
	var paths:=[]
	var victim_free:=false
	var max_height:=0.0
	var victim_original_x:float=b.position.x
	var before_launch:=false
	var min_gap:=9999.0
	var first_brake:=false
	var x_at_brake:=0.0
	var dir_samples:=[]
	a.move_started.connect(func(k):paths.append([k,a.combo_route]))
	a.impact.connect(func(_pt,k,blk):events.append([k,blk,a.combo_hits,a.last_pudding_hit,a.last_launch]))
	for frame in 210:
		var ka:={}
		var kb:={}
		if scenario in ["confirm","throw","jjjj","jjjk","kkk"]:
			var route:String={"confirm":"JJ"+("I" if move=="super" else "U"),"throw":"T","jjjj":"JJJJ","jjjk":"JJJK","kkk":"KKK"}[scenario]
			if next_button<route.length() and events.size()>=next_button and frame%2==0:
				var button:String={"J":"light","K":"heavy","T":"throw","U":"special","I":"super"}[route[next_button]]
				ka[button]=true
				next_button+=1
			if not events.is_empty(): kb.down=true
		elif frame==0:ka[move]=true
		if scenario=="block":kb.down=true
		if scenario=="brake" and a.pudding_braked and not first_brake:
			first_brake=true
			x_at_brake=a.position.x
			b.position.x=a.position.x+d*(a.config.width+b.config.width+4)
		if scenario=="edge" and frame==12:kb.right=not swap;kb.left=swap
		if swap:F.tick_pair(b,a,kb,ka,DT)
		else:F.tick_pair(a,b,ka,kb,DT)
		min_gap=minf(min_gap,(b.position.x-a.position.x)*d)
		if b.launched:
			before_launch=true
			max_height=maxf(max_height,F.FLOOR_Y-b.position.y)
		elif before_launch and b.grounded:victim_free=true
		if a.attack_kind=="super" and (a.velocity.x*d)<-10:dir_samples.append(-1)
	var report:={"hits":events,"paths":paths,"damage":old_hp-b.hp,"energy":a.energy,
		"travel":(a.position.x-old_x)*d,"drift":absf(a.position.x-x_at_brake) if first_brake else -1.0,"braked":first_brake,
		"rise":max_height,"land":victim_free,"send":(b.position.x-victim_original_x)*d,"gap":min_gap,"reversed":dir_samples.size()>0}
	a.free()
	b.free()
	return report

func _rules()->void:
	_check(F.STATS.taffy.width>F.STATS.orange.width and F.STATS.taffy.speed<F.STATS.orange.speed,"taffy is widest and slowest")
	_check(F.STATS.pudding.width<F.STATS.doctor.width and F.STATS.pudding.speed>F.STATS.mirinda.speed,"pudding is fastest with a slim body")
	for id in IDS:
		for swap in [false,true]:
			for m in ["special","super"]:
				for scenario in ["raw","confirm","poor","miss","block"]:
					var r:=_trial(id,m,scenario,swap)
					var who:=str([id,m,scenario,swap,r])
					match scenario:
						"poor":_check(r.paths.is_empty() and r.hits.is_empty(),"insufficient stocks "+who)
						"miss":_check(r.hits.is_empty() and r.energy==(0.0 if m=="super" else 100.0),"proper whiff "+who)
						"block":_check(r.hits.size()==1 and r.hits[0][1] and not r.land and r.damage==(2 if m=="super" else 1),"one guard stops all stages "+who)
						"raw","confirm":
							var extra:int=2 if scenario=="confirm" else 0
							var count:int=3 if id=="pudding" and m=="super" else 1
							_check(r.hits.size()==count+extra and not r.hits[-1][1] and r.hits[-1][2]==count+extra,"genuine confirmed hits "+who)
							_check(r.energy==(0.0 if m=="super" else 100.0),"full meter spent "+who)
							if m=="super":
								_check(r.land and r.rise>65.0 and r.send>120.0,"upward finisher and landing "+who)
								for i in r.hits.size():_check(r.hits[i][4]==(i==r.hits.size()-1),"launch only on final impact "+who)
							if id=="pudding" and m=="super" and r.hits.size()==count+extra:
								_check(r.hits[extra][3]==1 and r.hits[extra+1][3]==2 and r.hits[extra+2][3]==3 and r.reversed and r.gap>=0,"three distinct same-side stages "+who)
							if m=="special":_check(not r.land,"one stock stays grounded "+who)
			for mode in ["throw","jjjj","jjjk","kkk"]:
				var r:=_trial(id,"special",mode,swap)
				var n:int={"throw":1,"jjjj":4,"jjjk":4,"kkk":3}[mode]
				_check(r.hits.size()==n and r.hits[-1][2]==n,"existing common route "+str([id,mode,r]))
	var t:=_trial("taffy","special","miss",false)
	var p:=_trial("pudding","super","brake",false)
	_check(t.travel>40.0 and t.travel<90.0,"taffy shoulder travels a half body "+str(t))
	_check(p.braked and p.hits.is_empty() and p.drift<12.0,"missed opening cannot reacquire at point blank "+str(p))

func _frames(n:int)->void:
	for i in n:await physics_frame

func _press(code:Key,down:bool)->void:
	var ev:=InputEventKey.new()
	ev.physical_keycode=code
	ev.keycode=code
	ev.pressed=down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _snapshot(suffix:String)->void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var screenshot:=root.get_texture().get_image()
	_check(screenshot.save_png(ProjectSettings.globalize_path("res://dev/roster_"+suffix+".png"))==OK,"capture "+suffix)

func _showcase()->void:
	var game=load("res://duel.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	# Demonstrate the true select and play flow with stocked local players.
	var a_idx:int=game.IDS.find("taffy")
	var b_idx:int=game.IDS.find("pudding")
	if a_idx<0 or b_idx<0:
		_check(false,"both new fighters appear on the real selection screen")
		game.free()
		return
	game.vs_cpu=false
	for key in [KEY_4,KEY_TAB,KEY_5,KEY_RIGHT,KEY_LEFT,KEY_TAB]:
		_press(key,true)
		await _frames(1)
		_press(key,false)
		await _frames(1)
	_check(game.picks==[a_idx,b_idx] and game.cursor==0,"keyboard select fourth/fifth, switch slot and wrap")
	await _frames(15)
	await _snapshot("select")
	await _frames(22)
	for hero in [a_idx,b_idx]:
		for kind in ["special","super"]:
			if game.state!="select":game.to_select()
			game.picks=[hero,b_idx if hero==a_idx else a_idx]
			game.vs_cpu=false
			game.start_match()
			var a=game.fighters[0]
			var b=game.fighters[1]
			a.position.x=370 if hero==a_idx else 410
			b.position.x=a.position.x+a.config.width+b.config.width+6.0
			a.energy=200
			game.state_time=0.15
			var hits:=[]
			a.impact.connect(func(_pt,k,blocked):hits.append([k,blocked]))
			await _frames(22)
			var key:Key=KEY_U if kind=="special" else KEY_I
			_press(key,true)
			await _frames(2)
			_press(key,false)
			var card:=false
			var action:=false
			var apex:=false
			var count:int=3 if hero==b_idx and kind=="super" else 1
			for frame in 220:
				if game.cutin.active and game.cutin.elapsed>=0.22 and not card:
					card=true
					await _snapshot(a.fighter_id+"_cg")
				if not action and hits.size()>=(2 if count==3 else 1):
					action=true
					await _frames(2)
					await _snapshot(a.fighter_id+"_"+kind)
				if b.launched and b.velocity.y>0 and not apex:
					apex=true
					await _snapshot(a.fighter_id+"_launch")
				if (action and kind=="special" and a.attack_kind.is_empty()) or (apex and b.grounded): break
				await _frames(1)
			_check(hits.size()==count and action,"movie real contacts "+str([a.fighter_id,kind,hits]))
			if kind=="super":_check(card and apex,"movie genuine CG and launch "+a.fighter_id)
			await _frames(15)
	game.sound.silence()
	await _frames(10)
	game.to_select()
	game.free()
	await process_frame

func _run()->void:
	var args:=OS.get_cmdline_user_args()
	if "--movie" in args or "--capture" in args:
		await _showcase()
	else:
		_rules()
		_reversals_and_punishes()
	print("New roster: %d checks, %d failures"%[checks,errors])
	quit(1 if errors else 0)

func _reversals_and_punishes()->void:
	for id in IDS:
		for m in ["special","super"]:
			for direction in [-1,1]:
				var a=F.new()
				var b=F.new()
				a.setup(id,0)
				b.setup("mirinda",1)
				a.position.x=F.RIGHT_EDGE-a.config.width-b.config.width if direction>0 else F.LEFT_EDGE+a.config.width+b.config.width
				b.position.x=F.RIGHT_EDGE if direction>0 else F.LEFT_EDGE
				a.energy=200
				var blocked:=[]
				var answers:=[]
				var answered:=false
				a.impact.connect(func(_p,_k,guard):blocked.append(guard))
				b.impact.connect(func(_p,k,guard):answers.append([k,guard]))
				for frame in 125:
					var keys:={"down":true}
					if not answered and blocked.size()>0 and b.stun_left<=0 and b.hitstop_left<=0:
						keys={"heavy":true}
						answered=true
					F.tick_pair(a,b,{m:frame==0,"down":true},keys,DT)
				_check(blocked==[true] and answers==[["heavy",false]] and a.max_hp-a.hp==roundi(1.2*F.NORMALS.heavy.damage),"blocked move is genuinely heavy punishable "+str([id,m,direction]))
				a.free()
				b.free()
		for shadow in [false,true]:
			var a=F.new()
			var b=F.new()
			a.setup(id,0)
			b.setup(id,1)
			a.position.x=460
			b.position.x=a.position.x+a.config.width+b.config.width
			a.energy=200
			b.energy=100 if shadow else 200
			for n in 150:
				F.tick_pair(a,b,{"super":n==0},{"special" if shadow else "super":n==0},DT)
			if shadow:_check(a.hp==a.max_hp and b.hp<b.max_hp,"two stocks defeat one when attacks overlap "+id)
			else:_check(a.hp==b.hp and a.hp<a.max_hp,"same-tier/same-frame trade "+id)
			a.free()
			b.free()
	for id in IDS:
		var quick:=_trial(id,"super","raw",false)
		_check(quick.damage==(35 if id=="taffy" else 30),"unscaled raw super exactly one move "+id)
		var confirmed:=_trial(id,"super","confirm",false)
		var expected:int=13+roundi(35.0*0.8) if id=="taffy" else 9+roundi(8.0*0.8)+roundi(9.0*0.8)+roundi(13.0*0.8)
		_check(confirmed.damage==expected,"two jabs -> third-move damage factor across every super pulse "+str([id,expected,confirmed.damage]))
