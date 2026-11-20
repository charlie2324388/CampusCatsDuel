extends Control

const LABELS := {"throw":"投", "special":"一气", "super":"两气", "light":"轻", "heavy":"重"}
# Distances from the safe area's bottom-right corner, in nominal CSS pixels.
const BUTTON_OFFSETS := {"light":Vector2(116,50), "heavy":Vector2(41,61),
	"throw":Vector2(170,89), "special":Vector2(120,121), "super":Vector2(55,131)}
const BUTTON_RADII := {"light":33.0, "heavy":34.0, "throw":25.0, "special":27.0, "super":28.0}
const ACCENTS := {"light":Color("#f0e6c8"), "heavy":Color("#ffb489"), "throw":Color("#bedbd8"),
	"special":Color("#ffda85"), "super":Color("#ffd478")}
const STICK_RADIUS := 61.0
const STICK_OFFSET := Vector2(77,77)
const THUMB_RADIUS := 20.0
const DIRECTIONS := {"left":Vector2i.LEFT, "right":Vector2i.RIGHT, "jump":Vector2i.UP, "down":Vector2i.DOWN}
const CYAN := Color("#abe3e9")
const EDGE_ACTIONS := ["light","heavy","throw","special","super","jump"]

var game
var enabled := false
var stick_finger := -1
var stick_direction := Vector2i.ZERO
var stick_travel := Vector2.ZERO
var button_fingers := {}
var held_counts := {}
var pressed_at := {}
var release_after := {}
var viewing_fight := false

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	process_mode=Node.PROCESS_MODE_ALWAYS
	process_physics_priority=50
	enabled=DisplayServer.is_touchscreen_available() or "--touch-preview" in OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		enabled=enabled or bool(JavaScriptBridge.eval("navigator.maxTouchPoints > 0"))
	set_process_input(enabled)
	set_process(enabled)
	set_physics_process(enabled)
	hide()
	if enabled:
		get_window().focus_exited.connect(_lose_focus)
		resized.connect(release_all)

func _active() -> bool:
	return enabled and game!=null and game.state=="fight"

func _lose_focus() -> void:
	release_all()
	if _active(): game.toggle_pause()

func release_all() -> void:
	for key in pressed_at:
		Input.action_release(_action(key))
	stick_finger=-1
	stick_direction=Vector2i.ZERO
	stick_travel=Vector2.ZERO
	button_fingers.clear()
	held_counts.clear()
	pressed_at.clear()
	release_after.clear()
	queue_redraw()

func _action(key: String) -> StringName:
	return StringName("duel_p1_"+key)

func _process(_dt: float) -> void:
	var wanted := _active()
	if wanted!=viewing_fight:
		if not wanted: release_all()
		viewing_fight=wanted
		visible=wanted
		if wanted: queue_redraw()

func _physics_process(_dt: float) -> void:
	# A touch shorter than one physics tick must still reach the fighter's input buffer.
	for key in release_after.keys():
		if Engine.get_physics_frames() > int(release_after[key]):
			Input.action_release(_action(key))
			pressed_at.erase(key)
			release_after.erase(key)

func _press(key: String) -> void:
	if not held_counts.has(key):
		Input.action_press(_action(key))
		pressed_at[key]=Engine.get_physics_frames()
		release_after.erase(key)
	held_counts[key]=int(held_counts.get(key,0))+1

func _release(key: String, canceled: bool=false) -> void:
	held_counts[key]=int(held_counts[key])-1
	if held_counts[key]>0: return
	held_counts.erase(key)
	if not canceled and key in EDGE_ACTIONS and Engine.get_physics_frames()==int(pressed_at[key]):
		release_after[key]=pressed_at[key]
	else:
		Input.action_release(_action(key))
		pressed_at.erase(key)
		release_after.erase(key)

func _unit() -> float:
	var css:float=game.touch_css_scale
	var safe_size:Vector2=game.touch_safe_rect().size / css
	# A small phone in browser mode still needs space between both thumbs.
	return css*clampf(minf(safe_size.x/660.0,safe_size.y/355.0),0.84,1.07)

func _stick_center() -> Vector2:
	var safe:Rect2=game.touch_safe_rect()
	return Vector2(safe.position.x,safe.end.y)+Vector2(STICK_OFFSET.x,-STICK_OFFSET.y)*_unit()

func _center(key: String) -> Vector2:
	if DIRECTIONS.has(key):
		return _stick_center()+Vector2(DIRECTIONS[key])*STICK_RADIUS*0.72*_unit()
	var safe:Rect2=game.touch_safe_rect()
	return safe.end-Vector2(BUTTON_OFFSETS[key])*_unit()

func _button_at(point: Vector2) -> String:
	var chosen := ""
	var nearest := INF
	var unit := _unit()
	for key in BUTTON_OFFSETS:
		var distance:=point.distance_to(_center(key))/unit
		if distance<=float(BUTTON_RADII[key])+3.0 and distance<nearest:
			chosen=key
			nearest=distance
	return chosen

func _stick_axis(value: float, previous: int) -> int:
	var sign_now := int(signf(value))
	var threshold := 0.43 if sign_now==previous and previous!=0 else 0.56
	return sign_now if absf(value)>=threshold else 0

func _set_stick(point: Vector2, canceled: bool=false) -> void:
	var offset:Vector2=(point-_stick_center())/_unit()
	stick_travel=offset.limit_length(STICK_RADIUS-THUMB_RADIUS-5.0)
	var direction:=Vector2i.ZERO
	# Hysteresis around the dead zone and diagonals prevents tiny movements from
	# releasing guard or generating a second jump. A diagonal up also holds travel.
	var dead_zone:=11.0 if stick_direction!=Vector2i.ZERO else 15.0
	if offset.length()>dead_zone:
		var axis:=offset.normalized()
		direction=Vector2i(_stick_axis(axis.x,stick_direction.x),_stick_axis(axis.y,stick_direction.y))
	for key in DIRECTIONS:
		var axis:Vector2i=DIRECTIONS[key]
		var was_on:=stick_direction.x*axis.x+stick_direction.y*axis.y>0
		var is_on:=direction.x*axis.x+direction.y*axis.y>0
		if was_on and not is_on: _release(key,canceled)
		elif is_on and not was_on: _press(key)
	stick_direction=direction
	queue_redraw()

func _set_button(index: int, key: String, canceled: bool=false) -> void:
	var old: String=button_fingers.get(index,"")
	if key==old: return
	if old!="": _release(old,canceled)
	if key!="": _press(key)
	button_fingers[index]=key
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not _active(): return
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag): return
	var point:Vector2=get_global_transform_with_canvas().affine_inverse()*event.position
	var index:int=event.index
	if event is InputEventScreenTouch and (not event.pressed or event.canceled):
		if index==stick_finger:
			_set_stick(_stick_center(),event.canceled)
			stick_finger=-1
		elif button_fingers.has(index):
			_set_button(index,"",event.canceled)
			button_fingers.erase(index)
		else: return
	elif index==stick_finger:
		_set_stick(point)
	elif button_fingers.has(index):
		_set_button(index,_button_at(point))
	elif event is InputEventScreenTouch:
		if point.distance_to(_stick_center())<=(STICK_RADIUS+7.0)*_unit():
			if stick_finger==-1:
				stick_finger=index
				_set_stick(point)
		else:
			var key:=_button_at(point)
			if key=="": return
			_set_button(index,key)
	else: return
	get_viewport().set_input_as_handled()

func _draw() -> void:
	if not _active(): return
	var unit:=_unit()
	draw_set_transform(_stick_center(),0.0,Vector2.ONE*unit)
	draw_circle(Vector2.ZERO,STICK_RADIUS,Color("#111d2e70"),true,-1,true)
	draw_arc(Vector2.ZERO,STICK_RADIUS,0,TAU,72,Color("#101e2cbe"),3.6,true)
	draw_arc(Vector2.ZERO,STICK_RADIUS-0.8,0,TAU,72,Color("#b0e6e4c4"),1.6,true)
	for key in DIRECTIONS:
		var axis:=Vector2(DIRECTIONS[key])
		var side:=axis.orthogonal()
		var active:bool=held_counts.has(key)
		var ink:=Color.WHITE if active else Color("#c5e5e5d9")
		var a:=axis.angle()
		draw_arc(Vector2.ZERO,STICK_RADIUS-5.5,a-0.54,a+0.54,15,Color(CYAN,0.95 if active else 0.3),3.5,true)
		var tip:=axis*(STICK_RADIUS-10.0)
		draw_polyline(PackedVector2Array([tip-axis*5.5+side*5.5,tip,tip-axis*5.5-side*5.5]),ink,2.6,true)
	var thumb:=stick_travel
	draw_circle(thumb+Vector2(0,2),THUMB_RADIUS,Color("#1017288c"),true,-1,true)
	draw_circle(thumb,THUMB_RADIUS,Color("#57818fda") if stick_finger>=0 else Color("#426575bd"),true,-1,true)
	draw_arc(thumb,THUMB_RADIUS-0.7,0,TAU,42,Color("#bce8efcd"),1.4,true)
	draw_circle(thumb,3.4,Color("#deeff0dd"),true,-1,true)
	for key in BUTTON_OFFSETS:
		draw_set_transform(_center(key),0.0,Vector2.ONE*unit)
		var radius:=float(BUTTON_RADII[key])
		var held:bool=held_counts.has(key)
		var accent:Color=ACCENTS[key]
		if held: radius-=1
		draw_circle(Vector2.ZERO,radius,Color("#172536b3") if not held else Color("#344659ed"),true,-1,true)
		draw_arc(Vector2.ZERO,radius,0,TAU,50,Color("#152233bc"),3.5,true)
		draw_arc(Vector2.ZERO,radius-0.7,0,TAU,50,Color(accent,0.99 if held else 0.80),1.6,true)
		if held:
			draw_circle(Vector2.ZERO,radius-3,Color(accent,0.36),true,-1,true)
		if key in ["special","super"]:
			draw_arc(Vector2.ZERO,radius-4.0,PI*0.67,PI*1.06,12,accent,2.0,true)
			if key=="super":
				draw_arc(Vector2.ZERO,radius-4.0,PI*1.10,PI*1.48,12,accent,2.0,true)
		var font:Font=game.hud.heavy_font
		var text_size:=17 if key in ["special","super"] else (19 if key=="throw" else 23)
		var baseline:=0.5*(font.get_ascent(text_size)-font.get_descent(text_size))
		draw_string(font,Vector2(-radius,baseline),LABELS[key],HORIZONTAL_ALIGNMENT_CENTER,radius*2,text_size,accent)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
