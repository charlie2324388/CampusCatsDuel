extends Node

const MIX := {"guard":-6,"select":-11,"strike":-12,"hit":-8,"plasma_pulse":-8,"vacuum_wave":-6,"wave_impact":-10,"wave_finish":-7,"kick_impact_1":-6,"kick_finish":-4,"motor_start":-7,"motor_brake":-10,"clear":-12,"charge":-15,"stone_palm":-5,"prism_swipe":-8,"prism_finish":-6}
var clips := {}
var voices: Array[AudioStreamPlayer] = []
var motors: Array[AudioStreamPlayer]=[]
var loop_track: AudioStreamWAV
var music := AudioStreamPlayer.new()
var voice_i := 0
var muted := false

func _ready() -> void:
	add_child(music)
	for key in MIX:
		var path := "res://art/audio/%s.wav"%key
		if ResourceLoader.exists(path): clips[key]=load(path)
	for i in 8:
		var v := AudioStreamPlayer.new()
		add_child(v)
		voices.append(v)
	for side in 2:
		var motor := AudioStreamPlayer.new()
		motor.process_mode=Node.PROCESS_MODE_PAUSABLE
		add_child(motor)
		motor.volume_db=-9.0
		motors.append(motor)
		motor.finished.connect(_sustain_motor.bind(side))
	loop_track=load("res://art/audio/motor_loop.wav")
	loop_track.loop_mode=AudioStreamWAV.LOOP_FORWARD
	loop_track.loop_end=roundi(loop_track.get_length()*loop_track.mix_rate)
	var track := load("res://art/audio/campus_theme.wav") as AudioStreamWAV
	track.loop_mode=AudioStreamWAV.LOOP_FORWARD
	track.loop_end=roundi(track.get_length()*track.mix_rate)
	music.stream=track
	music.volume_db=-15.0
	if DisplayServer.get_name()!="headless": music.play()

func play(id: String) -> void:
	if muted or not clips.has(id) or DisplayServer.get_name()=="headless": return
	var voice := voices[voice_i]
	voice_i=(voice_i+1)%voices.size()
	voice.stream=clips[id]
	voice.volume_db=float(MIX[id])
	voice.play()

func start_motor(side:int) -> void:
	if DisplayServer.get_name()=="headless": return
	var motor:=motors[side]
	motor.stream=clips["motor_start"]
	motor.volume_db=-80 if muted else -8
	motor.play()

func _sustain_motor(side:int) -> void:
	motors[side].stream=loop_track
	motors[side].play()

func stop_motor(side:int,brake:bool=false) -> void:
	if not motors[side].playing: return
	motors[side].stop()
	if brake: play("motor_brake")

func toggle() -> void:
	muted=not muted
	for m in motors: m.volume_db=-80 if muted else -8
	music.volume_db=-80 if muted else -15
	if muted:
		for v in voices: v.stop()

func silence() -> void:
	music.stop()
	for m in motors: m.stop()
	for v in voices: v.stop()
