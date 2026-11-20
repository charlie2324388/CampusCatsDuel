extends SceneTree

const Fighter = preload("res://scripts/fighter.gd")
var game
var pad
var failed := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok:bool, label:String) -> void:
	checks+=1
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failed+=1

func touch(index:int, pos:Vector2, pressed:bool, canceled:bool=false) -> void:
	var event:=InputEventScreenTouch.new()
	event.index=index
	event.position=pad.get_global_transform_with_canvas()*pos
	event.pressed=pressed
	event.canceled=canceled
	root.push_input(event,true)

func drag(index:int, pos:Vector2) -> void:
	var event:=InputEventScreenDrag.new()
	event.index=index
	event.position=pad.get_global_transform_with_canvas()*pos
	root.push_input(event,true)

func actions() -> Dictionary:
	return game.controls.read_player(0)

func settled() -> void:
	await physics_frame
	await physics_frame

func _run() -> void:
	root.size=Vector2i(844,390)
	game=load("res://duel.tscn").instantiate()
	root.add_child(game)
	game.start_match()
	game.state="fight"
	game.set_physics_process(false)
	await process_frame
	await process_frame
	for node in game.find_children("*","Control",true,false):
		if node.get_script()!=null and node.get_script().resource_path=="res://scripts/mobile_pad.gd":
			pad=node
	check(pad!=null and pad.visible,"touchscreen match shows the mobile controls")
	if not pad or not pad.visible:
		quit(1)
		return

	var safe:Rect2=game.touch_safe_rect()
	var unit:float=pad._unit()
	var center:Vector2=pad._stick_center()
	print("Controls geometry: ", safe, " / unit ",unit," / screen ",root.size)
	for key in pad.BUTTON_OFFSETS:
		var point:Vector2=pad._center(key)
		var radius:float=float(pad.BUTTON_RADII[key])*unit
		check(safe.encloses(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2)),"inside safe area "+key)
		check(pad._button_at(point)==key,"independent touch target "+key)
		for other in pad.BUTTON_OFFSETS:
			if str(key)>=str(other): continue
			check(point.distance_to(pad._center(other))>(float(pad.BUTTON_RADII[key])+float(pad.BUTTON_RADII[other])+6.0)*unit,"separate touch targets "+key+" "+other)
		touch(2,point,true)
		check(actions()[key],"physical touch presses "+key)
		await physics_frame
		touch(2,point,false)
		await settled()
		check(not actions()[key],"physical release clears "+key)
	check(center.x<safe.position.x+safe.size.x*0.30 and pad._center("throw").x>safe.position.x+safe.size.x*0.65,"controls leave the central fight clear")
	for key in pad.DIRECTIONS:
		touch(2,pad._center(key),true)
		check(actions()[key],"ring press activates "+key)
		await physics_frame
		touch(2,pad._center(key),false)
		await settled()
		check(not actions()[key],"ring release clears "+key)

	touch(1,center,true)
	drag(1,center+Vector2(5,5)*unit)
	check(not actions().right and not actions().down and not actions().jump,"dead zone absorbs drift")
	touch(7,pad._center("left"),true)
	drag(7,pad._center("right"))
	check(pad.stick_finger==1 and not actions().right and not actions().left,"second finger cannot steal the stick")
	touch(7,pad._center("right"),false)
	drag(1,pad._center("right"))
	check(actions().right and pad.stick_travel.x>0,"drag moves and displaces the thumb")
	touch(2,pad._center("light"),true)
	touch(3,pad._center("light"),true)
	check(actions().right and actions().light and not game.controls.read_player(1).light,"hold travel and tap P1 light together")
	touch(2,pad._center("light"),false)
	check(actions().light,"second finger keeps same button held")
	drag(3,pad._center("heavy"))
	await settled()
	check(not actions().light and actions().heavy,"sliding the right thumb changes attack")
	drag(3,center)
	await settled()
	check(not actions().heavy and actions().right,"attack finger cannot take over the stick")
	touch(3,center,false)
	drag(1,pad._center("down"))
	check(actions().down and not actions().right,"down holds guard and stops the previous direction")
	drag(1,center)
	check(not actions().down and pad.stick_travel==Vector2.ZERO,"centering the stick releases guard")
	var from_x:float=game.fighters[0].position.x
	drag(1,center+Vector2(42,-42)*unit)
	check(actions().right and actions().jump and not actions().down,"up-forward produces both inputs")
	var jumps:=0
	for frame in 150:
		var grounded:bool=game.fighters[0].grounded
		Fighter.tick_pair(game.fighters[0],game.fighters[1],actions(),{},1.0/60.0)
		if grounded and not game.fighters[0].grounded: jumps+=1
	check(jumps==1 and game.fighters[0].grounded,"holding up gives exactly one physical jump")
	check(game.fighters[0].position.x>from_x+10,"diagonal jump covers ground")
	drag(1,center+Vector2(-40,-38)*unit)
	check(actions().left and actions().jump and not actions().right,"backward jump keeps its direction")
	touch(1,center,false,true)
	check(not actions().left and not actions().jump and pad.stick_finger==-1,"touchcancel clears a held stick")

	touch(1,pad._center("down"),true)
	touch(5,pad._center("special"),true)
	pad._lose_focus()
	check(game.state=="pause" and not actions().special and not actions().down and pad.stick_travel==Vector2.ZERO,"focus loss resets controls and pauses")
	game.toggle_pause()
	await process_frame
	touch(6,pad._center("super"),true)
	touch(6,pad._center("super"),false)
	check(actions().super,"subframe tap survives until fighter sampling")
	await settled()
	check(not actions().super,"short tap releases after sampling")
	touch(8,pad._center("throw"),true)
	touch(8,pad._center("throw"),false,true)
	check(not actions().throw,"canceling a just-started attack clears it immediately")
	touch(9,pad._center("right"),true)
	touch(10,pad._center("light"),true)
	game.toggle_guide()
	await process_frame
	await process_frame
	check(not pad.visible and not actions().right and not actions().light,"opening a HUD overlay releases both thumbs")
	print("Mobile controls: %d checks, %d failures"%[checks,failed])
	quit(1 if failed else 0)
