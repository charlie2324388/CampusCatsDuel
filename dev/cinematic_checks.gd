extends SceneTree

const STEP := 1.0/60.0
var game
var checks := 0
var failed := 0
var movie := false
var captures := false
var feed: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print(("PASS " if ok else "FAIL ")+label)

func _frames(n: int) -> void:
	for i in n: await physics_frame

func _button(side: int, move: String, down: bool) -> void:
	var action:=StringName("duel_p%d_%s"%[side+1,move])
	if down: Input.action_press(action)
	else: Input.action_release(action)

func _tap(side: int, move: String) -> void:
	_button(side,move,true)
	await _frames(2)
	_button(side,move,false)
	await _frames(1)

func _until(fn: Callable, cap: int=160) -> bool:
	for _i in cap:
		if fn.call(): return true
		await _frames(1)
	return bool(fn.call())

func _capture(filename: String) -> void:
	if not captures: return
	await RenderingServer.frame_post_draw
	var frame:=root.get_texture().get_image()
	_check(frame!=null and frame.save_png(ProjectSettings.globalize_path("res://dev/v2_"+filename+".png"))==OK,"capture "+filename)

func _hit(_point: Vector2, kind: String, block: bool, side: int) -> void:
	feed.append([side,kind,block])

func _start(a: int, b: int, ax: float=396, bx: float=510) -> void:
	if game.state!="select": game.to_select()
	game.picks=[a,b]
	game.vs_cpu=false
	game.start_match()
	game.fighters[0].position.x=ax
	game.fighters[1].position.x=bx
	await _until(func(): return game.state=="fight")
	for i in 2:
		game.fighters[i].energy=200
		game.fighters[i].impact.connect(_hit.bind(i))
	await _frames(5)

func _test_cutin(id: String) -> void:
	var showing:=await _until(func(): return game.state=="cutin" and game.cutin.fighter_id==id)
	_check(showing,id+" opens its own two-stock portrait")
	if not showing: return
	var a=game.fighters[0]
	var b=game.fighters[1]
	var saved: Array=[game.seconds_left,a.position,b.position,a.move_time,b.move_time,a.hp,b.hp]
	await _frames(19)
	_check(saved==[game.seconds_left,a.position,b.position,a.move_time,b.move_time,a.hp,b.hp],id+" holds positions, life, attacks and round timer")
	await _capture(id+"_cutin")
	await _until(func(): return game.state=="fight")

func _run() -> void:
	movie="--movie" in OS.get_cmdline_user_args()
	captures="--capture" in OS.get_cmdline_user_args()
	game=load("res://duel.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await _frames(3)
	game.toggle_guide()
	_check(game.state=="guide" and paused,"select opens move list")
	await _capture("guide")
	game.toggle_guide()
	_check(game.state=="select" and not paused,"move list returns to select")

	await _start(1,0,251,680)
	var caster=game.fighters[0]
	var jumper=game.fighters[1]
	await _tap(0,"special")
	var travel:=await _until(func(): return not caster.projectiles.is_empty() and caster.projectiles[0].point.x>=398)
	_check(travel and jumper.hp==jumper.max_hp,"one-stock projectile travels before contact")
	await _capture("plasma")
	await _until(func(): return not caster.projectiles.is_empty() and jumper.position.x-caster.projectiles[0].point.x<=185)
	await _tap(1,"jump")
	await _frames(62)
	_check(jumper.hp==jumper.max_hp and caster.projectiles.is_empty(),"normal wave can be jumped")
	await _start(0,1)
	var a=game.fighters[0]
	var b=game.fighters[1]
	game.toggle_guide()
	var time: float=game.seconds_left
	await _frames(4)
	_check(game.seconds_left==time and game.state=="guide","match move list suspends combat")
	game.toggle_guide()
	game.toggle_pause()
	game.toggle_guide()
	game.toggle_guide()
	_check(game.state=="pause" and paused,"returning to pause menu preserves pause")
	game.toggle_pause()
	await _tap(0,"light")
	var jab:=await _until(func(): return a.normal_confirmed and a.combo_route=="J")
	_check(jab,"first jab hits")
	await _tap(0,"light")
	var two:=await _until(func(): return a.normal_confirmed and a.combo_route=="JJ")
	_check(two and game.chain_hits[0]==2,"two confirmed jabs show two hits")
	await _tap(0,"super")
	await _test_cutin("mirinda")
	var four:=await _until(func(): return a.combo_hits>=6)
	_check(four and a.energy==0 and b.hp<b.max_hp-10,"J J I converts to a six-hit shadow-kick string")
	await _capture("mirinda_finish")
	await _frames(45)
	_button(0,"left",true)
	_button(1,"right",true)
	await _frames(33)
	_button(0,"left",false)
	_button(1,"right",false)
	await _frames(8)
	await _tap(1,"super")
	await _test_cutin("doctor")
	var active:=await _until(func(): return not b.projectiles.is_empty() and b.projectiles[0].age>=0.20)
	_check(active and a.hp==a.max_hp,"vacuum wave travels on screen after the freeze")
	await _capture("vacuum")
	var five:=await _until(func(): return b.last_projectile_hit==5)
	_check(five and a.hp<a.max_hp and game.chain_hits[1]==5,"vacuum wave lands five real hits")
	await _capture("vacuum_finish")
	await _frames(48)

	await _start(2,0)
	a=game.fighters[0]
	b=game.fighters[1]
	_button(1,"down",true)
	await _tap(0,"super")
	await _test_cutin("orange")
	var blocked:=await _until(func(): return [0,"super",true] in feed)
	_check(blocked and game.notice[0]=="被防 · 收招","blocked scooter exposes a punish")
	await _capture("orange_block")
	_button(1,"down",false)
	await _until(func(): return b.stun_left<=0 and b.hitstop_left<=0,50)
	await _tap(1,"heavy")
	var punished:=await _until(func(): return a.hp<a.max_hp,80)
	_check(punished,"heavy punishes the blocked two-stock super")
	await _frames(35)

	if not movie:
		await _start(1,1)
		a=game.fighters[0]
		b=game.fighters[1]
		_button(0,"super",true)
		_button(1,"super",true)
		await _frames(2)
		_button(0,"super",false)
		_button(1,"super",false)
		_check(game.state=="cutin" and game.cutin.player_side==0,"first simultaneous cinematic")
		var next:=await _until(func(): return game.state=="cutin" and game.cutin.player_side==1)
		_check(next,"second simultaneous cinematic")
		await _until(func(): return game.state=="fight")
		var trade:=await _until(func(): return a.hp<a.max_hp and b.hp<b.max_hp)
		_check(trade and a.hp==b.hp and a.energy==b.energy,"same-frame two-stock trade survives both cinematic holds")
	game.sound.silence()
	await _frames(10)
	game.to_select()
	game.free()
	print("Cinematic integration: %d checks, %d failures" % [checks,failed])
	quit(1 if failed else 0)