extends Control

var game
const Fonts = preload("res://scripts/arena_fonts.gd")
var body_font: Font
var heavy_font: Font
var digits: Font
var elapsed := 0.0
var poster: Texture2D = preload("res://art/keyart.png")
var mirinda_portrait: Texture2D = preload("res://art/mirinda_portrait.png")

const INK := Color("#152736")
const BLACK := Color("#101e28")
const DARK := Color("#2b4049")
const MIST := Color("#bfc8bc")
const PAPER := Color("#fff0d1")
const GOLD := Color("#ffcf67")
const BLUE := Color("#73cdec")
const CORAL := Color("#ff8c61")
const TEAMS := [CORAL,BLUE]
const TONES := [Color("#ef9b53"),Color("#76c9ab"),Color("#b495df"),Color("#dcad6f"),Color("#fb8775")]
const STYLES := ["连踢快攻","电浆控场","滑铲重击","近身重掌","变速爪击"]
const FACE := [Rect2(144,367,165,165),Rect2(641,365,165,165),Rect2(1152,389,195,195)]
const BANNER_ART := [Rect2(16,310,490,223),Rect2(533,313,477,217),Rect2(1039,329,479,218)]
# Face crops in normalized cut-in coordinates.
const NEW_FACES := [Rect2(436.0/2061,10.0/763,453.0/2061,453.0/763),Rect2(1070.0/2061,22.0/763,415.0/2061,415.0/763)]
const SELECT_GUIDE := Rect2(448,20,130,38)
const FIGHT_GUIDE := Rect2(434,100,92,22)
const PAUSE_GUIDE := Rect2(525,118,178,27)
const GUIDE_CLOSE := Rect2(681,432,119,30)
const MODE_BUTTON := Rect2(588,20,167,38)

const START_BUTTON := Rect2(694,412,235,47)
const PAUSE_BUTTON := Rect2(455,74,50,23)
const OVER_MAIN := Rect2(274,320,412,45)
const OVER_BACK := Rect2(302,378,356,37)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	body_font=Fonts.interface_font(400)
	heavy_font=Fonts.interface_font(800)
	digits=Fonts.interface_font(750,true)

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _txt(at: Vector2, content: String, size_px: int=16, color: Color=PAPER, face: Font=null, width: float=-1, alignment: HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(body_font if face==null else face,at,content,alignment,width,size_px,color)

func _shape(p: PackedVector2Array, fill: Color, edge: Color=Color.TRANSPARENT, weight: float=2.0) -> void:
	draw_colored_polygon(p,fill)
	if edge.a>0:
		var line := p.duplicate()
		line.append(p[0])
		draw_polyline(line,edge,weight,true)

func _slab(rect: Rect2, lean: float=7) -> PackedVector2Array:
	return PackedVector2Array([Vector2(rect.position.x+lean,rect.position.y),Vector2(rect.end.x,rect.position.y),Vector2(rect.end.x-lean,rect.end.y),Vector2(rect.position.x,rect.end.y)])

func _facet(rect: Rect2, tint: Color, lean: float=7, outline: Color=Color.TRANSPARENT, weight: float=2.0) -> void:
	_shape(_slab(rect,lean),tint,outline,weight)

func _patch(p: PackedVector2Array, box: Rect2, source: Rect2, sheet: Texture2D, mirror: bool=false) -> void:
	var coords := PackedVector2Array()
	for point in p:
		var local := (point-box.position)/box.size
		if mirror: local.x=1.0-local.x
		coords.append((source.position+local*source.size)/sheet.get_size())
	draw_polygon(p,PackedColorArray([Color.WHITE]),coords,sheet)

func _badge(center: Vector2,radius: float,hero: int,col: Color) -> void:
	draw_circle(center,radius+2,BLACK,true,-1,true)
	draw_circle(center,radius,col,true,-1,true)
	var rr := radius-2
	var ring := PackedVector2Array()
	for j in range(36):
		ring.append(center+Vector2.from_angle(TAU*j/36)*rr)
	var sq := Rect2(center-Vector2.ONE*rr,Vector2.ONE*rr*2)
	if hero==0:
		_patch(ring,sq,Rect2(560,0,540,540),mirinda_portrait)
	elif hero<FACE.size():
		_patch(ring,sq,FACE[hero],poster)
	elif game.cutin.ART.has(game.IDS[hero]):
		var img: Texture2D=game.cutin.ART[game.IDS[hero]]
		var face: Rect2=NEW_FACES[hero-FACE.size()]
		_patch(ring,sq,Rect2(face.position*img.get_size(),face.size*img.get_size()),img)

func _button(r: Rect2, text: String, primary: bool=false, small: bool=false) -> void:
	var cut := minf(15,r.size.y*0.28)
	var p := PackedVector2Array([r.position+Vector2(cut,0),Vector2(r.end.x-4,r.position.y),Vector2(r.end.x,r.position.y+cut),Vector2(r.end.x-cut,r.end.y),Vector2(r.position.x+4,r.end.y),r.position+Vector2(0,r.size.y-cut)])
	_shape(Transform2D(0,Vector2(2,3))*p,BLACK)
	_shape(p,GOLD if primary else PAPER,INK,2)
	_txt(Vector2(r.position.x,r.get_center().y+6),text,15 if small else 19,INK,heavy_font,r.size.x,HORIZONTAL_ALIGNMENT_CENTER)

func _slot(side: int) -> String:
	return "1P" if side==0 else ("CPU" if game.vs_cpu else "2P")

func _side_rect(side: int) -> Rect2:
	return Rect2(23+side*456,78,458,228)

func _roster_rect(index: int) -> Rect2:
	var stride: float=912.0/game.IDS.size()
	return Rect2(24+index*stride,325,stride-4,68)

func _draw() -> void:
	if game==null: return
	if game.state=="guide":
		if game.guide_from=="select": _select_screen()
		else: _battle()
		_combo_guide()
		return
	if game.state=="select":
		_select_screen()
		return
	if game.fighters.size()<2 or not is_instance_valid(game.fighters[0]) or not is_instance_valid(game.fighters[1]): return
	_battle()
	match game.state:
		"pause","match_end": _sheet()
		"intro","round_end": _announcer()
		"fight":
			if str(game.announcement)!="": _announcer()

func _select_screen() -> void:
	draw_rect(Rect2(0,0,960,540),INK)
	_shape(PackedVector2Array([Vector2(0,0),Vector2(521,0),Vector2(398,78),Vector2(0,98)]),DARK)
	_shape(PackedVector2Array([Vector2(23,18),Vector2(322,11),Vector2(300,62),Vector2(18,67)]),PAPER)
	_shape(PackedVector2Array([Vector2(20,66),Vector2(210,61),Vector2(195,68),Vector2(19,72)]),CORAL)
	_txt(Vector2(42,54),"课间猫擂台",37,INK,heavy_font)
	_button(SELECT_GUIDE,"连招表" if game.touch_layout else "F1  连招表",false,true)
	_button(MODE_BUTTON,"触屏 · 人机对战" if game.touch_layout and game.vs_cpu else "M  "+("人机对战" if game.vs_cpu else "双人对战"),false,true)
	_txt(Vector2(761,44),"按住防键格挡" if game.touch_layout else "S / ↓  按住格挡",17,PAPER,heavy_font,168,HORIZONTAL_ALIGNMENT_RIGHT)
	_side_panel(0)
	_side_panel(1)
	var vs := PackedVector2Array([Vector2(478,130),Vector2(516,153),Vector2(499,186),Vector2(476,200),Vector2(444,178),Vector2(455,147)])
	_shape(vs,GOLD,INK,3)
	_txt(Vector2(445,178),"VS",32,INK,digits,70,HORIZONTAL_ALIGNMENT_CENTER)
	for i in game.IDS.size(): _roster(i)
	_txt(Vector2(27,430),"正在为 "+_slot(game.cursor)+" 选猫",19,TEAMS[game.cursor],heavy_font)
	_txt(Vector2(27,455),"先点上方头像选一方，再点下方的猫" if game.touch_layout else "Tab  切换选角方     ← → 或数字 1–5 选猫",14,MIST)
	_button(START_BUTTON,"进入擂台  →" if game.touch_layout else "进入擂台     ENTER  →",true)
	draw_line(Vector2(25,474),Vector2(933,474),Color("#4a5d63"),1,true)
	if game.touch_layout:
		_txt(Vector2(29,504),"左手移动、跳跃与格挡　　右手轻击、重击、投与必杀",16,PAPER)
		_txt(Vector2(755,504),"三局两胜  ·  45 秒",15,MIST,heavy_font,174,HORIZONTAL_ALIGNMENT_RIGHT)
		return
	_txt(Vector2(29,500),"1P",17,CORAL,digits)
	_txt(Vector2(73,500),"A / D 移动   W 跳跃   S 格挡   J 轻击   K 重击   L 投   U 一气   I 两气",15,PAPER)
	_txt(Vector2(29,525),"2P",17,BLUE,digits)
	_txt(Vector2(73,525),"← / → 移动   ↑ 跳跃   ↓ 格挡   逗号轻击   句号重击   / 投   [ 一气   ] 两气",15,PAPER)
	_txt(Vector2(755,512),"三局两胜  ·  45 秒",15,MIST,heavy_font,174,HORIZONTAL_ALIGNMENT_RIGHT)

func _side_panel(side: int) -> void:
	var r := _side_rect(side)
	var id: int=game.picks[side]
	var active: bool=game.cursor==side
	var col: Color=TEAMS[side]
	var x:=r.position.x
	var y:=r.position.y
	var outer:=PackedVector2Array([Vector2(x+14,y+2),Vector2(r.end.x-2,y),Vector2(r.end.x-9,r.end.y-15),Vector2(r.end.x-25,r.end.y),Vector2(x+1,r.end.y-4)])
	_shape(Transform2D(0,Vector2(2,4))*outer,BLACK)
	_shape(outer,PAPER if active else Color("#d8d7c8"),col if active else DARK,3)
	var art:=Rect2(x+7,y+4,r.size.x-13,151)
	var cutout:=PackedVector2Array([Vector2(x+16,y+4),Vector2(r.end.x-6,y+3),Vector2(r.end.x-10,y+138),Vector2(x+6,y+153)])
	if id==0:
		_patch(cutout,art,Rect2(0,0,1774,604),mirinda_portrait,side==1)
	elif id<BANNER_ART.size():
		_patch(cutout,art,BANNER_ART[id],poster,(side==0 and id==2) or (side==1 and id==1))
	elif game.cutin.ART.has(game.IDS[id]):
		var img: Texture2D=game.cutin.ART[game.IDS[id]]
		var focus:Rect2=NEW_FACES[id-FACE.size()]
		var h:float=minf(img.get_height(),img.get_width()/art.size.aspect())
		var crop_y:=clampf(img.get_height()*focus.get_center().y-h*0.5,0.0,img.get_height()-h)
		_patch(cutout,art,Rect2(0,crop_y,img.get_width(),h),img,side==1)
	var tag:=Rect2(x+15 if side==0 else r.end.x-112,y+10,95,25)
	_facet(tag,col,6,INK,1)
	_txt(Vector2(tag.position.x,tag.position.y+18),_slot(side)+(" 选角中" if active else ""),13,INK,heavy_font,tag.size.x,HORIZONTAL_ALIGNMENT_CENTER)
	_shape(PackedVector2Array([Vector2(x+5,y+138),Vector2(r.end.x-8,y+125),Vector2(r.end.x-10,y+167),Vector2(x+3,y+177)]),INK)
	_txt(Vector2(x+20,y+166),game.NAMES[id],28,PAPER,heavy_font)
	_txt(Vector2(x+240,y+157),STYLES[id],16,col,heavy_font,185,HORIZONTAL_ALIGNMENT_RIGHT)
	_txt(Vector2(x+20,y+201),"一气",14,INK,heavy_font)
	_txt(Vector2(x+64,y+201),game.ONE[id],17,INK,heavy_font)
	draw_line(Vector2(x+203,y+184),Vector2(x+197,y+208),Color("#b29e81"),1.4,true)
	_txt(Vector2(x+216,y+201),"两气",14,INK,heavy_font)
	_txt(Vector2(x+262,y+201),game.TWO[id],17,INK,heavy_font)

func _roster(i: int) -> void:
	var r:=_roster_rect(i)
	var selected: bool=game.picks[game.cursor]==i
	_facet(r,DARK if not selected else Color("#3d5056"),8,TEAMS[game.cursor] if selected else Color("#596970"),2.5 if selected else 1)
	_badge(r.position+Vector2(31,34),21,i,TONES[i])
	_txt(r.position+Vector2(59,29),game.NAMES[i],19,PAPER,heavy_font)
	var assignments:=PackedStringArray()
	for side in 2:
		if game.picks[side]==i: assignments.append(_slot(side))
	var shortcut: String="" if game.touch_layout else str(i+1)+"   "
	var subline: String=shortcut+(" / ".join(assignments) if not assignments.is_empty() else STYLES[i])
	_txt(r.position+Vector2(60,51),subline,12,TEAMS[game.cursor] if selected else MIST,body_font)

func _meter(r: Rect2,portion: float,c: Color,reverse: bool) -> void:
	var fraction:=clampf(portion,0,1)
	_facet(r,Color("#455763"),4)
	if fraction<=0.0: return
	var span: float=(r.size.x-4)*fraction
	var x:=r.end.x-span-4 if reverse else r.position.x
	_facet(Rect2(x,r.position.y,span+4,r.size.y),c,4)

func _battle() -> void:
	for side in range(2):
		_status(side)
		_energy(side)
		_foot_tag(side)
		if int(game.chain_hits[side])>=2 and float(game.chain_linger[side])>0.0:
			_combo_readout(side)
		if float(game.notice_left[side])>0.0 and str(game.notice[side])!="":
			var r:=Rect2(24 if side==0 else 717,82,219,30)
			_facet(r,Color("#162b39eb"),7,TEAMS[side],1)
			_txt(r.position+Vector2(0,21),game.notice[side],15,TEAMS[side],heavy_font,r.size.x,HORIZONTAL_ALIGNMENT_CENTER)
	var hex:=PackedVector2Array([Vector2(459,6),Vector2(501,6),Vector2(522,21),Vector2(517,58),Vector2(498,72),Vector2(462,72),Vector2(443,58),Vector2(438,21)])
	_shape(hex,INK,PAPER,2)
	_txt(Vector2(442,48),"%02d"%ceili(game.seconds_left),36,GOLD if game.seconds_left>10 else CORAL,digits,76,HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(445,64),"第 %d 局"%game.round_no,12,PAPER,heavy_font,70,HORIZONTAL_ALIGNMENT_CENTER)
	if game.state=="fight":
		_facet(PAUSE_BUTTON,Color("#172933e6"),5)
		_txt(Vector2(455,90),"暂停",12,PAPER,heavy_font,50,HORIZONTAL_ALIGNMENT_CENTER)
		_facet(FIGHT_GUIDE,Color("#172933df"),5)
		_txt(Vector2(434,115),"连招表" if game.touch_layout else "F1   连招表",12,PAPER,heavy_font,92,HORIZONTAL_ALIGNMENT_CENTER)

func _combo_readout(side: int) -> void:
	var left: bool=side==0
	var align:=HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	var origin:=Vector2(24 if left else 716,119)
	var count_string:=str(game.chain_hits[side])+" 连击"
	var route:=str(game.chain_route[side])
	var keys: PackedStringArray=[]
	for letter in route:
		if left: keys.append(letter)
		elif game.vs_cpu: keys.append({"J":"轻","K":"重","U":"一气","I":"两气"}.get(letter,letter))
		else: keys.append({"J":"逗","K":"句","U":"[","I":"]"}.get(letter,letter))
	var sequence:=" › ".join(keys)
	var label_width:=maxf(95,heavy_font.get_string_size(sequence,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+28)
	var x:=origin.x if left else origin.x+220-label_width
	_facet(Rect2(x,origin.y,label_width,60),Color("#142733ed"),6,TEAMS[side],1.5)
	_txt(Vector2(x+10,origin.y+29),count_string,23,GOLD,heavy_font,label_width-20,align)
	_txt(Vector2(x+10,origin.y+49),sequence,14,PAPER,heavy_font,label_width-20,align)

func _combo_guide() -> void:
	draw_rect(Rect2(0,0,960,540),Color("#0a1726cf"))
	var panel:=PackedVector2Array([Vector2(145,73),Vector2(792,64),Vector2(821,88),Vector2(817,464),Vector2(793,484),Vector2(137,474)])
	_shape(Transform2D(0,Vector2(5,6))*panel,BLACK)
	_shape(panel,PAPER,INK,3)
	_txt(Vector2(169,120),"连招表",36,INK,heavy_font)
	_txt(Vector2(379,115),"贴近对手，看到命中火花就按下一键",16,DARK,heavy_font)
	draw_line(Vector2(163,138),Vector2(794,138),Color("#beac8e"),1.5,true)
	_txt(Vector2(174,169),"轻重连段",19,INK,heavy_font)
	_txt(Vector2(495,169),"命中接必杀",19,INK,heavy_font)
	draw_line(Vector2(471,155),Vector2(471,318),Color("#cfbea1"),1,true)
	_guide_route(Vector2(170,185),"JJJJ","疾爪四连",false)
	_guide_route(Vector2(170,229),"JJJK","挑空踢",false)
	_guide_route(Vector2(170,273),"KKK","破阵重击",false)
	_guide_route(Vector2(491,185),"JJU","接一气技",true)
	_guide_route(Vector2(491,229),"JJI","接两气大招",true)
	_guide_route(Vector2(491,273),"KKI","重击接两气",true)
	draw_line(Vector2(163,329),Vector2(794,329),Color("#beac8e"),1.5,true)
	_txt(Vector2(171,354),"1P   J 轻击   K 重击   L 投   U 一气   I 两气",16,INK,heavy_font)
	_txt(Vector2(171,383),"横屏双手操作，按住方向的同时可以出招。" if game.touch_layout else "2P   逗号轻击   句号重击   / 投   [ 一气   ] 两气",15,INK)
	_txt(Vector2(171,411),"贴身投可破格挡；起跳躲投，双方同时出投可拆。",15,INK,heavy_font)
	_txt(Vector2(171,444),"两气压一气，一气压普通攻击。同级先打中的一方占先。",14,DARK)
	_txt(Vector2(171,463),"截住起手多 2 帧硬直，抓到收招多 4 帧，两者伤害均加 20%。",14,DARK)
	_button(GUIDE_CLOSE,"返回" if game.touch_layout else "返回    F1",false,true)

func _guide_route(at: Vector2, route: String, caption: String, meter: bool) -> void:
	var x:=at.x
	for i in route.length():
		var key:=route[i]
		var fill:=GOLD if key in ["I","U"] else (CORAL if key=="K" else Color("#92d4df"))
		if i>0: draw_line(Vector2(x-6,at.y+14),Vector2(x,at.y+14),DARK,2,true)
		_facet(Rect2(x,at.y,28,28),fill,3,INK,1.5)
		_txt(Vector2(x,at.y+21),key,18,INK,digits,28,HORIZONTAL_ALIGNMENT_CENTER)
		x+=34
	_txt(at+Vector2(116 if meter else 147,21),caption,16,INK,heavy_font)

func _status(side: int) -> void:
	var f=game.fighters[side]
	var id: int=game.picks[side]
	var col: Color=TEAMS[side]
	var x:=13.0 if side==0 else 525.0
	_facet(Rect2(x,11,423,62),Color("#162a39ef"),10,BLACK,2)
	var left: bool=side==0
	var av:=Vector2(48 if left else 912,42)
	_badge(av,24,id,col)
	var tag:=Rect2(81 if left else 836,18,43,19)
	_facet(tag,col,4)
	_txt(tag.position+Vector2(0,15),_slot(side),13,INK,digits,tag.size.x,HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(133 if left else 629,34),game.NAMES[id],18,PAPER,heavy_font,197,HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT)
	var hp_left:=81.0 if left else 543.0
	_meter(Rect2(hp_left,44,336,13),float(f.hp)/maxf(1,f.max_hp),col,not left)
	for unit in range(2):
		var at:=Vector2(93+unit*16 if left else 867-unit*16,65)
		draw_circle(at,5.1,Color("#566772"),true,-1,true)
		if int(game.wins[side])>unit: draw_circle(at,4.1,GOLD,true,-1,true)
	_txt(Vector2(262 if left else 542,68),"%d / %d"%[f.hp,f.max_hp],11,MIST,digits,153,HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT)

func _energy(side: int) -> void:
	var f=game.fighters[side]
	var left: bool=side==0
	var id: int=game.picks[side]
	var x:=12.0 if left else 516.0
	_facet(Rect2(x,485,432,44),Color("#172b38f0"),8,BLACK,1.5)
	for i in range(2):
		var cell:=i if left else 1-i
		var cx:=x+12+cell*204
		var ready_now: bool=float(f.energy)>=(i+1)*100.0
		var fraction:=clampf((float(f.energy)-i*100.0)/100.0,0,1)
		_meter(Rect2(cx,513,193,8),fraction,GOLD if ready_now else TEAMS[side],not left)
		var key: String = (["U","I"] if left else ["[","]"])[i] if (left or not game.vs_cpu) and not game.touch_layout else ""
		var move_title: String=game.ONE[id] if i==0 else game.TWO[id]
		var caption: String=(key+"  " if key!="" else "")+("一气" if i==0 else "两气")+" · "+move_title
		_txt(Vector2(cx,506),caption,13,GOLD if ready_now else PAPER,heavy_font,193,HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT)

func _foot_tag(side: int) -> void:
	var f=game.fighters[side]
	var point: Vector2=get_viewport().canvas_transform*f.global_position
	var center:=Vector2(clampf(point.x,25,935),minf(466,point.y+15))
	var r:=Rect2(center-Vector2(18,9),Vector2(36,17))
	_facet(r,TEAMS[side],4,INK,1.5)
	_txt(Vector2(r.position.x,r.position.y+13),_slot(side),11,INK,digits,36,HORIZONTAL_ALIGNMENT_CENTER)

func _announcer() -> void:
	var line:=str(game.announcement)
	if line.is_empty(): return
	var fw:=clampf(heavy_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,41).x+68,175,770)
	var r:=Rect2((960-fw)*0.5,140,fw,70)
	_facet(Rect2(r.position+Vector2(5,5),r.size),BLACK,15)
	_facet(r,GOLD,15,INK,3)
	_txt(Vector2(r.position.x,r.position.y+51),line,41,INK,heavy_font,r.size.x,HORIZONTAL_ALIGNMENT_CENTER)

func _sheet() -> void:
	var paused_screen: bool=game.state=="pause"
	draw_rect(Rect2(0,0,960,540),Color("#0b1829b8"))
	var sheet:=PackedVector2Array([Vector2(210,106),Vector2(720,95),Vector2(750,119),Vector2(739,415),Vector2(722,438),Vector2(201,428)])
	_shape(Transform2D(0,Vector2(5,6))*sheet,BLACK)
	_shape(sheet,PAPER,INK,3)
	for k in range(4):
		draw_line(Vector2(220,219+k*30),Vector2(722,214+k*30),Color("#d4c4a6"),1)
	var top := "暂停" if paused_screen else "对战成绩单"
	_facet(Rect2(244,118,136,27),GOLD,7,INK,1.5)
	_txt(Vector2(244,138),top,16,INK,heavy_font,136,HORIZONTAL_ALIGNMENT_CENTER)
	if paused_screen:
		_button(PAUSE_GUIDE,"查看连招表" if game.touch_layout else "F1  查看连招表",false,true)
		_txt(Vector2(247,193),"课间休息",37,INK,heavy_font)
		_txt(Vector2(247,227),"左手按方向移动，按跳起跳，按住防键格挡。" if game.touch_layout else "1P   A / D 移动   W 跳   S 格挡   J 轻   K 重   L 投   U 一气   I 两气",15,INK,heavy_font)
		_txt(Vector2(247,255),"右手点轻、重或投，攒气后可点一气或两气。" if game.touch_layout else "2P   ← / → 移动   ↑ 跳   ↓ 格挡   逗号轻   句号重   / 投   [ 一气   ] 两气",15,INK,heavy_font)
		_txt(Vector2(247,282),"轻、轻命中后接两气，可以打出带特写的连招。" if game.touch_layout else "2P 小键盘：1 轻击、2 重击、3 投、4 一气、5 两气。",14,DARK)
		_txt(Vector2(247,304),"贴身投能破站防；起跳可躲，双方同时出投可拆。",14,DARK)
	else:
		var winner:int=game.match_winner
		if winner>=0:
			_badge(Vector2(665,182),43,game.picks[winner],TEAMS[winner])
		var title: String = _slot(winner)+"  "+game.NAMES[game.picks[winner]]+" 胜出！" if winner>=0 else "平局"
		_txt(Vector2(244,202),title,34,INK,heavy_font)
		_txt(Vector2(248,250),"%s    %d   :   %d    %s"%[_slot(0),game.wins[0],game.wins[1],_slot(1)],25,INK,heavy_font)
		_txt(Vector2(248,284),"三局两胜",16,DARK)
	_button(OVER_MAIN,("继续比赛" if paused_screen else "再战一场") if game.touch_layout else ("继续比赛   ESC" if paused_screen else "再战一场   ENTER"),true)
	_button(OVER_BACK,"返回选角" if paused_screen or game.touch_layout else "返回选角    Q",false,true)

func _gui_input(event: InputEvent) -> void:
	if game==null or not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT or not event.pressed: return
	var at: Vector2=event.position
	match game.state:
		"select":
			if SELECT_GUIDE.has_point(at): game.toggle_guide()
			elif START_BUTTON.has_point(at): game.start_match()
			elif MODE_BUTTON.has_point(at) and not game.touch_layout: game.toggle_mode()
			else:
				for s in range(2):
					if _side_rect(s).has_point(at):
						game.set_slot(s)
						return
				for i in game.IDS.size():
					if _roster_rect(i).has_point(at):
						game.choose(i)
						return
		"fight":
			if PAUSE_BUTTON.has_point(at): game.toggle_pause()
			elif FIGHT_GUIDE.has_point(at): game.toggle_guide()
		"guide":
			if GUIDE_CLOSE.has_point(at): game.toggle_guide()
		"pause":
			if PAUSE_GUIDE.has_point(at): game.toggle_guide()
			elif OVER_MAIN.has_point(at): game.toggle_pause()
			elif OVER_BACK.has_point(at): game.to_select()
		"match_end":
			if OVER_MAIN.has_point(at): game.rematch()
			elif OVER_BACK.has_point(at): game.to_select()

