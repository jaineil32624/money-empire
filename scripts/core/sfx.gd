extends Node
## Sfx — every sound in the game is synthesized at startup (no audio files, no licensing).
## Includes a looping lo-fi "money" beat for the background music.

const RATE := 22050

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	_streams.coin = _make(_coin())
	_streams.click = _make(_tone([[900.0, 0.03]], 0.25, "square"))
	_streams.error = _make(_tone([[180.0, 0.09], [140.0, 0.12]], 0.35, "square"))
	_streams.buy = _make(_tone([[523.0, 0.07], [659.0, 0.07], [784.0, 0.07], [1047.0, 0.16]], 0.4, "triangle"))
	_streams.levelup = _make(_tone([[523.0, 0.09], [659.0, 0.09], [784.0, 0.09], [1047.0, 0.09], [1319.0, 0.3]], 0.45, "square"))
	_streams.news = _make(_tone([[880.0, 0.08], [660.0, 0.12]], 0.3, "sine"))
	_streams.job = _make(_tone([[784.0, 0.06], [988.0, 0.06], [1175.0, 0.14]], 0.4, "triangle"))
	_streams.alarm = _make(_siren())
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	music = AudioStreamPlayer.new()
	music.stream = _make(_music(), true)
	add_child(music)
	apply_volumes()
	music.play()


func apply_volumes() -> void:
	if music == null:
		return
	var mv: float = float(Game.settings.music)
	music.volume_db = linear_to_db(maxf(0.0001, mv * 0.5))
	music.stream_paused = mv <= 0.001
	var sv: float = float(Game.settings.sfx)
	for p in _pool:
		p.volume_db = linear_to_db(maxf(0.0001, sv))


func play(id: String) -> void:
	if not _streams.has(id) or _pool.is_empty():
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[id]
	p.play()


# ------------------------------------------------------------- synthesis
func _make(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _osc(kind: String, phase: float) -> float:
	match kind:
		"square": return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"triangle": return 4.0 * absf(fmod(phase, 1.0) - 0.5) - 1.0
		"saw": return 2.0 * fmod(phase, 1.0) - 1.0
	return sin(phase * TAU)


func _tone(notes: Array, vol: float, kind: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n in notes:
		var f: float = n[0]
		var count := int(float(n[1]) * RATE)
		for i in count:
			var t := float(i) / RATE
			var env := minf(1.0, t * 200.0) * (1.0 - float(i) / count)
			out.append(_osc(kind, f * t) * env * vol)
	return out


func _coin() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(0.32 * RATE)
	for i in n:
		var t := float(i) / RATE
		var f := 1319.0 if t < 0.06 else 1760.0
		var env := exp(-t * 9.0)
		out.append((sin(TAU * f * t) * 0.6 + sin(TAU * f * 2.0 * t) * 0.2) * env * 0.45)
	return out


func _siren() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(1.2 * RATE)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 700.0 + 300.0 * sin(t * TAU * 1.6)
		ph += f / RATE
		out.append(_osc("triangle", ph) * 0.3 * (1.0 - t / 1.2))
	return out


## 4 bars of laid-back 90 BPM loop: kick, hat, bass and a Rhodes-ish chord stab.
func _music() -> PackedFloat32Array:
	var bpm := 90.0
	var beat := 60.0 / bpm
	var bars := 4
	var total := int(beat * 4.0 * bars * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	# chord progression (root hz + chord tones): Am7 - Dm7 - G7 - Cmaj7
	var prog := [[110.0, [220.0, 261.63, 329.63, 392.0]], [146.83, [293.66, 349.23, 440.0, 523.25]],
		[98.0, [196.0, 246.94, 293.66, 349.23]], [130.81, [261.63, 329.63, 392.0, 493.88]]]
	var nz := 12345
	for i in total:
		var t := float(i) / RATE
		var b := t / beat
		var bar := int(b / 4.0)
		var chord: Array = prog[bar % 4]
		var in_beat := fmod(b, 1.0) * beat
		var s := 0.0
		# kick on 1 and 3, plus the "and" of 4
		var kb := fmod(b, 4.0)
		var kick_t := -1.0
		if kb < 1.0: kick_t = kb * beat
		elif kb >= 2.0 and kb < 3.0: kick_t = (kb - 2.0) * beat
		elif kb >= 3.5: kick_t = (kb - 3.5) * beat
		if kick_t >= 0.0 and kick_t < 0.25:
			s += sin(TAU * (55.0 + 90.0 * exp(-kick_t * 30.0)) * kick_t) * exp(-kick_t * 9.0) * 0.55
		# snare on 2 and 4 (noise)
		if (int(kb) == 1 or int(kb) == 3) and in_beat < 0.18:
			nz = (nz * 1103515245 + 12345) & 0x7fffffff
			s += (float(nz % 2000) / 1000.0 - 1.0) * exp(-in_beat * 22.0) * 0.18
		# swung hats
		var hb := fmod(b * 2.0, 1.0) * beat * 0.5
		if hb < 0.04:
			nz = (nz * 1103515245 + 12345) & 0x7fffffff
			s += (float(nz % 2000) / 1000.0 - 1.0) * (1.0 - hb / 0.04) * 0.06
		# bass follows the root, walking up a fifth on beat 3
		var root: float = chord[0]
		var bf := root if kb < 2.0 else root * 1.5
		s += sin(TAU * bf * t) * 0.16 * (0.6 + 0.4 * exp(-in_beat * 3.0))
		# chord stab on beat 1 and the "and" of 2
		var stab_t := -1.0
		if kb < 1.5: stab_t = kb * beat
		elif kb >= 1.5 and kb < 3.0: stab_t = (kb - 1.5) * beat
		if stab_t >= 0.0:
			var env := exp(-stab_t * 2.8) * 0.05
			for f in chord[1]:
				s += (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env
		out[i] = tanh(s * 1.1) * 0.8
	return out
