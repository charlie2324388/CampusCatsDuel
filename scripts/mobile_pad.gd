extends Control

# One finger owns one touch control; any number of fingers can use the same control.
const LABELS := {"left":"←","right":"→","jump":"跳","down":"防","light":"轻","heavy":"重","throw":"投","special":"一气","super":"两气"}
const DIRECTIONS := ["left","right","jump","down"]
const PULSE := ["light","heavy","throw","special","super","jump"]
const CENTERS := {"left":Vector2(48,443),"right":Vector2(121,443),
	"jump":Vector2(48,377),"down":Vector2(121,377),"throw":Vector2(772,377),
	"special":Vector2(839,377),"super":Vector2(909,377),"light":Vector2(843,443),"heavy":Vector2(913,443)}
const RADIUS := 28.0
const HIT_RADIUS := 33.0
var game
var enabled := false
var fingers := {}
var pressed_at := {}
var release_after := {}
var pressed_counts := {}
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
	if enabled: get_window().focus_exited.connect(_lose_focus)

func _active() -> bool:
	return enabled and game!=null and game.state=="fight"

func _lose_focus() -> void:
	release_all()
	if _active(): game.toggle_pause()

func release_all() -> void:
	for key in pressed_at.keys(): Input.action_release(_action(key))
	fingers.clear()
	pressed_at.clear()
	pressed_counts.clear()
	release_after.clear()
	queue_redraw()

func _action(key: String) -> StringName:
	return StringName("duel_p1_"+key)

func _process(_dt: float) -> void:
	var wanted := _active()
	if viewing_fight and not wanted: release_all()
	viewing_fight=wanted
	visible=wanted
	if wanted: queue_redraw()

func _physics_process(_dt: float) -> void:
	# A tap shorter than a physics tick still reaches the normal read_player() path once.
	for key in release_after.keys():
		if Engine.get_physics_frames() > int(release_after[key]):
			if not pressed_counts.has(key):
				Input.action_release(_action(key))
				pressed_at.erase(key)
			release_after.erase(key)

func _center(key: String) -> Vector2:
	var p: Vector2=CENTERS[key]
	return Vector2(p.x if p.x<480.0 else size.x-(960.0-p.x),size.y-(540.0-p.y))

func _key_at(p: Vector2) -> String:
	var chosen := ""
	var nearest := HIT_RADIUS*HIT_RADIUS
	for key in CENTERS:
		var distance := p.distance_squared_to(_center(key))
		if distance<=nearest:
			nearest=distance
			chosen=key
	return chosen

func _move_finger(index: int, key: String) -> void:
	var prior: String=fingers.get(index,"")
	if prior==key: return
	if prior!="":
		pressed_counts[prior]=int(pressed_counts[prior])-1
		if pressed_counts[prior]==0:
			pressed_counts.erase(prior)
			if prior in PULSE and Engine.get_physics_frames()==int(pressed_at[prior]):
				release_after[prior]=pressed_at[prior]
			else:
				Input.action_release(_action(prior))
				pressed_at.erase(prior)
	if key!="":
		if not pressed_counts.has(key):
			Input.action_press(_action(key))
			pressed_at[key]=Engine.get_physics_frames()
			release_after.erase(key)
		pressed_counts[key]=int(pressed_counts.get(key,0))+1
	fingers[index]=key
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not _active(): return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			var key := _key_at(get_global_transform().affine_inverse()*event.position)
			if key=="": return
			_move_finger(event.index,key)
		elif fingers.has(event.index):
			_move_finger(event.index,"")
			fingers.erase(event.index)
		else: return
	elif event is InputEventScreenDrag and fingers.has(event.index):
		_move_finger(event.index,_key_at(get_global_transform().affine_inverse()*event.position))
	else: return
	get_viewport().set_input_as_handled()

func _draw() -> void:
	if not _active(): return
	var font: Font=game.hud.heavy_font
	for key in CENTERS:
		var at := _center(key)
		var held: bool=pressed_counts.has(key)
		var accent := Color("#b2e7f4") if key in DIRECTIONS else (Color("#ffd37e") if key in ["special","super"] else Color("#ffe2c4"))
		var face := Color("#1b293ad4") if held else Color("#131f34a3")
		var r := RADIUS-1.4 if held else RADIUS
		draw_circle(at,r,face,true,-1.0,true)
		draw_arc(at,r,0,TAU,40,Color("#16203ade"),3.4,true)
		draw_arc(at,r-0.8,0,TAU,40,Color(accent,0.96 if held else 0.75),1.8,true)
		if held:
			draw_circle(at,r-4,Color(accent,0.36),true,-1.0,true)
		elif key in ["special","super"]:
			draw_arc(at,r-4,0.58*PI,1.30*PI,18,Color(accent,0.69),2.2,true)
		var text_size:=20 if key in ["special","super"] else 24
		draw_string(font,at+Vector2(-r,0.5*(font.get_ascent(text_size)-font.get_descent(text_size))),LABELS[key],HORIZONTAL_ALIGNMENT_CENTER,r*2,text_size,accent)
