extends Control

# Game advances this presentation while the fighters and round clock are stopped.
const DURATION := 0.82
var ART := {
	"mirinda": preload("res://art/cutins/mirinda.webp"),
	"doctor": preload("res://art/cutins/doctor.webp"),
	"orange": preload("res://art/cutins/orange.webp"),
}
const COLORS := {"mirinda": Color("#ff9145"), "doctor": Color("#77f4df"), "orange": Color("#c6a6ff"),"taffy":Color("#edbb7b"),"pudding":Color("#ff957e")}
const TITLES := {"mirinda": "美年达无影脚", "doctor": "真空磁轨炮", "orange": "电车冲锋","taffy":"镇岳掌","pudding":"折光三叠"}
const NAMES := {"mirinda": "美年达", "doctor": "烤鸭博士", "orange": "橘猪","taffy":"奶糖","pudding":"布丁"}
const INK := Color("#10131d")
const CREAM := Color("#fff2d7")

var active := false
var elapsed := 0.0
var fighter_id := "mirinda"
var player_side := 0
var headline: Font = preload("res://scripts/arena_fonts.gd").interface_font(900)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for id in ["taffy","pudding"]:
		var path: String="res://art/cutins/%s.webp"%id
		if ResourceLoader.exists(path):
			ART[id]=load(path)
	visible = active

func begin(cat_id: String, side: int) -> void:
	if not ART.has(cat_id):
		cancel()
		return
	fighter_id = cat_id
	player_side = clampi(side, 0, 1)
	elapsed = 0.0
	active = true
	show()
	queue_redraw()

func advance(real_seconds: float) -> bool:
	if active:
		elapsed += maxf(0.0, real_seconds)
		if elapsed >= DURATION:
			cancel()
		else:
			queue_redraw()
	return active

func cancel() -> void:
	active = false
	elapsed = 0.0
	hide()

func _draw() -> void:
	if not active or size.x < 1.0:
		return
	var reveal := smoothstep(0.0, 0.12, elapsed)
	var retract := smoothstep(DURATION - 0.12, DURATION, elapsed)
	var open := reveal * (1.0 - retract)
	var tint: Color = COLORS[fighter_id]
	var scale_to_screen := size / Vector2(960.0, 540.0)
	draw_set_transform(Vector2.ZERO, 0, scale_to_screen)
	draw_rect(Rect2(0, 0, 960, 540), Color(0.035, 0.045, 0.07, open * 0.75))
	# The envelope opens from a single diagonal seam. The illustration keeps its
	# aspect ratio as the panel opens and drifts forward during the held pose.
	var top := lerpf(267, 87, open)
	var bottom := lerpf(267, 431, open)
	var edge := 25.0
	var panel := PackedVector2Array([Vector2(0, top+edge), Vector2(960, top-edge), Vector2(960, bottom-edge), Vector2(0, bottom+edge)])
	if bottom - top < 1.0:
		draw_line(panel[0], panel[1], Color(tint, 0.8), 2.0, true)
		return
	var art: Texture2D = ART[fighter_id]
	var zoom := 1.0 + 0.045 * elapsed / DURATION
	var sample_size := Vector2(960.0, 395.0) * maxf(1.0, (960.0 / 395.0) / art.get_size().aspect()) * zoom
	# Fill both axes with the source aspect, centering the eyes well inside the frame.
	sample_size.x = sample_size.y * art.get_size().aspect()
	var origin := Vector2(480, 259) - sample_size * 0.5
	origin.x += lerpf(-8.0, 5.0, elapsed / DURATION)
	var uv := PackedVector2Array()
	for point in panel:
		uv.append((point - origin) / sample_size)
	draw_polygon(panel, PackedColorArray([Color.WHITE]), uv, art)
	draw_line(panel[0] + Vector2(0, -4), panel[1] + Vector2(0, -4), INK, 7.0, true)
	draw_line(panel[0], panel[1], tint, 3.0, true)
	draw_line(panel[2], panel[3], INK, 9.0, true)
	draw_line(panel[2] + Vector2(0, 5), panel[3] + Vector2(0, 5), tint, 2.0, true)
	var letters := smoothstep(0.045, 0.16, elapsed) * (1.0 - smoothstep(DURATION - 0.14, DURATION - 0.045, elapsed))
	if letters < 0.005:
		return
	var title: String = TITLES[fighter_id]
	var text_width := headline.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x
	var x := 912.0 - text_width + 48 * (1.0 - letters)
	var y := bottom - 10
	var leg := PackedVector2Array([Vector2(x-35,y-51), Vector2(960,y-70), Vector2(960,y+16), Vector2(x-61,y+32)])
	draw_colored_polygon(leg, Color(INK, 0.93 * letters))
	draw_line(leg[3], leg[2], Color(tint, letters), 3, true)
	draw_string_outline(headline, Vector2(x+1,y+4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, 6, Color(INK, letters))
	draw_string(headline, Vector2(x,y+1), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(CREAM, letters))
	var label := "%dP  /  %s    ·    两气奥义" % [player_side+1, NAMES[fighter_id]]
	var tag_y := top+14
	var tag_width := headline.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 48
	var tag := PackedVector2Array([Vector2(0,tag_y-32), Vector2(tag_width+19,tag_y-40), Vector2(tag_width,tag_y-8), Vector2(0,tag_y)])
	draw_colored_polygon(tag, Color(INK, letters))
	draw_string(headline, Vector2(20,tag_y-13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(tint, letters))
