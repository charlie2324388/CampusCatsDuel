extends SceneTree
var g
var pad
var failed:=0
func _initialize(): call_deferred("run")
func check(ok:bool,label:String):
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failed+=1
func touch(i:int,k:String,is_down:bool):
	var e=InputEventScreenTouch.new()
	e.pressed=is_down
	e.position=pad._center(k)
	e.index=i
	root.push_input(e,true)
func drag(i:int,where:Vector2):
	var e=InputEventScreenDrag.new()
	e.index=i
	e.position=where
	root.push_input(e,true)
func run():
	g=load("res://duel.tscn").instantiate()
	root.add_child(g)
	g.start_match()
	g.state="fight"
	g.set_physics_process(false)
	await process_frame
	await process_frame
	for node in g.find_children("*","Control",true,false):
		if node.get_script()!=null and node.get_script().resource_path=="res://scripts/mobile_pad.gd": pad=node
	check(pad!=null and pad.visible,"mobile pad opens")
	for k in pad.CENTERS:
		touch(1,k,true)
		check(g.controls.read_player(0)[k],"original action "+k)
		await physics_frame
		touch(1,k,false)
		await physics_frame
		await physics_frame
		check(not g.controls.read_player(0)[k],"release "+k)
	touch(1,"down",true)
	touch(2,"light",true)
	touch(3,"light",true)
	check(g.controls.read_player(0).down and g.controls.read_player(0).light and not g.controls.read_player(1).light,"three touch P1 chord")
	touch(2,"light",false)
	check(g.controls.read_player(0).light,"second finger on same key keeps it pressed")
	drag(1,pad._center("left"))
	check(g.controls.read_player(0).left and not g.controls.read_player(0).down,"sliding changes directions")
	drag(1,Vector2(400,300))
	check(not g.controls.read_player(0).left,"dragging out lifts direction")
	pad._lose_focus()
	check(g.state=="pause" and not g.controls.read_player(0).light,"focus loss releases all, pauses fight")
	g.toggle_pause()
	await process_frame
	touch(6,"super",true)
	touch(6,"super",false)
	check(g.controls.read_player(0).super,"subframe tap survives until fighter sampling")
	await physics_frame
	await physics_frame
	check(not g.controls.read_player(0).super,"short tap releases after sampling")
	print("Mobile touch failures=",failed)
	quit(1 if failed else 0)