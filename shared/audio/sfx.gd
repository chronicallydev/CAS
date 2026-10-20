extends Node

# Sound effects synthesized in code at startup (no audio files needed).
#
# One of the two autoloads (with PixelArt). Game state is not global: it
# lives in GameServices and the contexts. Audio stays global because every
# context and many short-lived nodes (projectiles, debris) play sounds, and
# it holds no game state.
#
# Autoloaded as "Sfx":
#   Sfx.play_3d("explosion", position)  - positional, in the current scene
#   (volume_db arguments are offsets on top of the MIX level)
#   Sfx.play_2d("ui_click")             - non-positional, survives scene changes
#   Sfx.get_stream("rotor_loop")        - for looping players owned elsewhere

const RATE := 22050

# Every sound is normalised to the same loudness (RMS of its loudest
# stretch), then MIX sets how loud it plays in context, in dB.
# Rule of thumb: things that need the player's attention (warnings, the
# helicopter being hit, enemy missile launches) are loud; frequent sounds
# (minigun impacts, car fire) and the constant rotor sit underneath.
const TARGET_RMS := 0.22
const MIX := {
	# Warnings and damage to the player: must cut through.
	"inbound_tone": -4.0,
	"lock_tone": -8.0,
	"heli_hit": 0.0,
	"missile_launch": -1.0,
	# Big events.
	"explosion": -2.0,
	"tank_fire": -4.0,
	"base_hit": -5.0,
	# Player weapons. shooting.wav is not normalised and is ~4 dB quieter
	# than the synthesised sounds, so its levels are set ~4 dB higher.
	"gun_cannon": -2.0,
	"gun_minigun": -10.0,
	"javelin_launch": -7.0,
	# Frequent, background.
	"explosion_small": -15.0,
	"car_gun": -13.0,
	"rotor_loop": -17.0,
	"ui_click": -10.0,
	# Hit and kill confirmation (heard constantly, so kept small).
	"hit_tick": -18.0,
	"kill_tick": -11.0,
	"combo": -6.0,
	# Minigun spin-up whine and overheat hiss.
	"spin_up": -15.0,
	"overheat": -5.0,
	# Rocket pods and the FAB bomb.
	"rocket_fire": -9.0,
	"bomb_release": -6.0,
	"bomb_whistle": -9.0,
	# Infantry deaths.
	"body_thud": -12.0,
	"gear_clank": -17.0,
	"scream": -11.0,
	# Flare pop when the helicopter drops decoys.
	"flare": -9.0,
	# The helicopter's dash.
	"dash_whoosh": -8.0,
}

# Per sound: [max voices at once, min milliseconds between starts].
const LIMITS := {
	"explosion": [6, 40],
	"explosion_small": [4, 80],
	"car_gun": [6, 30],
	"base_hit": [2, 250],
	"heli_hit": [2, 100],
	"tank_fire": [3, 60],
	"hit_tick": [2, 70],
	"kill_tick": [3, 40],
	"rocket_fire": [6, 40],
	"body_thud": [4, 40],
	"gear_clank": [3, 50],
	"scream": [1, 1200],
}

var streams: Dictionary = {}
var active: Dictionary = {}
var last_played: Dictionary = {}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 7
	streams["explosion"] = make_stream(synth_explosion(1.6, 0.0, 55.0))
	streams["explosion_small"] = make_stream(synth_explosion(0.55, 0.7, 90.0))
	streams["tank_fire"] = make_stream(synth_tank_fire())
	streams["car_gun"] = make_stream(synth_car_gun())
	streams["missile_launch"] = make_stream(synth_missile_launch())
	# Same whoosh, mixed separately for the player's own launches.
	streams["javelin_launch"] = streams["missile_launch"]
	streams["base_hit"] = make_stream(synth_structure_hit())
	streams["heli_hit"] = make_stream(synth_clang(0.45, [400.0, 1150.0, 2300.0], 10.0))
	streams["lock_tone"] = make_stream(synth_beep_loop(0.6, 0.18, 950.0), true)
	streams["inbound_tone"] = make_stream(synth_beep_loop(0.16, 0.08, 1500.0), true)
	streams["rotor_loop"] = make_stream(synth_rotor_loop(), true)
	streams["ui_click"] = make_stream(synth_click())
	streams["hit_tick"] = make_stream(synth_blips([2600.0], 0.03))
	streams["kill_tick"] = make_stream(synth_blips([1700.0, 2550.0], 0.05))
	streams["combo"] = make_stream(synth_blips([880.0, 1175.0, 1760.0], 0.08))
	streams["spin_up"] = make_stream(synth_spin_up())
	streams["overheat"] = make_stream(synth_overheat())
	streams["rocket_fire"] = streams["missile_launch"]
	streams["bomb_release"] = make_stream(synth_clang(0.4, [140.0, 390.0, 820.0], 9.0))
	streams["bomb_whistle"] = make_stream(synth_whistle())
	streams["body_thud"] = make_stream(synth_thud())
	streams["gear_clank"] = make_stream(synth_clang(0.3, [930.0, 2150.0, 3400.0], 16.0))
	streams["scream"] = make_stream(synth_scream())
	streams["flare"] = make_stream(synth_explosion(0.35, 0.95, 260.0))
	streams["dash_whoosh"] = make_stream(synth_whoosh())


func get_stream(sound: String) -> AudioStream:
	return streams.get(sound)


# Context level for a sound, in dB (see MIX).
func mix_db(sound: String) -> float:
	return MIX.get(sound, 0.0)


func can_play(sound: String) -> bool:
	if not streams.has(sound):
		return false
	var limit: Array = LIMITS.get(sound, [8, 0])
	var now := Time.get_ticks_msec()
	if active.get(sound, 0) >= limit[0]:
		return false
	if now - last_played.get(sound, -100000) < limit[1]:
		return false
	return true


func track(sound: String, player: Node) -> void:
	active[sound] = active.get(sound, 0) + 1
	last_played[sound] = Time.get_ticks_msec()
	# tree_exiting also fires when a scene reload frees the player.
	player.tree_exiting.connect(func() -> void: active[sound] = maxi(active.get(sound, 1) - 1, 0))


func play_3d(sound: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0, jitter: float = 0.08) -> void:
	var scene := get_tree().current_scene
	if scene == null or not can_play(sound):
		return

	var player := AudioStreamPlayer3D.new()
	player.stream = streams[sound]
	player.volume_db = mix_db(sound) + volume_db
	player.pitch_scale = pitch * rng.randf_range(1.0 - jitter, 1.0 + jitter)
	# The camera listens from high above, so keep sounds loud over distance.
	player.unit_size = 45.0
	player.max_db = 6.0
	scene.add_child(player)
	player.global_position = position
	track(sound, player)
	player.finished.connect(player.queue_free)
	player.play()


func play_2d(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not can_play(sound):
		return

	var player := AudioStreamPlayer.new()
	player.stream = streams[sound]
	player.volume_db = mix_db(sound) + volume_db
	player.pitch_scale = pitch
	add_child(player)
	track(sound, player)
	player.finished.connect(player.queue_free)
	player.play()


# --- Synthesis -----------------------------------------------------------

# RMS of the loudest stretch of the sound (or all of it, if shorter).
# Using the loudest window instead of the whole file means a long fading
# tail doesn't make a sound count as quieter than it is.
static func loudness(samples: PackedFloat32Array, window_seconds: float = 0.3) -> float:
	var window := mini(int(window_seconds * RATE), samples.size())
	if window <= 0:
		return 0.0

	var sum := 0.0
	for i in window:
		sum += samples[i] * samples[i]
	var best := sum

	for i in range(window, samples.size()):
		sum += samples[i] * samples[i] - samples[i - window] * samples[i - window]
		best = maxf(best, sum)

	return sqrt(best / window)


func make_stream(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	# Bring every sound to the same loudness; a soft limiter (tanh) keeps
	# the peaks of punchy sounds from clipping.
	var level := loudness(samples)
	var gain := TARGET_RMS / level if level > 0.0 else 1.0

	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var value := tanh(samples[i] * gain * 1.1) / tanh(1.1)
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32000.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


func noise() -> float:
	return rng.randf() * 2.0 - 1.0


# Rumbling blast: filtered noise whose brightness falls over time, plus a
# low pitch-dropping thump.
func synth_explosion(duration: float, brightness: float, thump_hz: float) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var phase := 0.0

	for i in n:
		var t := float(i) / RATE
		var progress := t / duration
		var env := minf(t / 0.004, 1.0) * exp(-t * 4.5 / duration)
		var cutoff := lerpf(0.2 + 0.5 * brightness, 0.02, minf(progress * 1.5, 1.0))
		lp += cutoff * (noise() - lp)
		lp2 += cutoff * (lp - lp2)

		var freq := thump_hz * exp(-t * 2.0)
		phase += freq / RATE
		var thump := sin(TAU * phase) * exp(-t * 7.0) * minf(t / 0.003, 1.0)

		out[i] = lp2 * 2.5 * env + thump * 0.9
	return out


# Heavy gun: sharp crack, then a deep boom.
func synth_tank_fire() -> PackedFloat32Array:
	var out := synth_explosion(0.9, 0.3, 75.0)
	for i in mini(int(0.03 * RATE), out.size()):
		var t := float(i) / RATE
		out[i] += noise() * exp(-t * 120.0) * 1.2
	return out


# One short rifle-calibre shot.
func synth_car_gun() -> PackedFloat32Array:
	var n := int(0.11 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var white := noise()
		# Crude high-pass so it cracks rather than rumbles.
		var hp := white - prev
		prev = white
		out[i] = hp * exp(-t * 55.0) + sin(TAU * 140.0 * t) * exp(-t * 40.0) * 0.6
	return out


# Rocket motor whoosh: noise swelling in brightness, then fading.
func synth_missile_launch() -> PackedFloat32Array:
	var duration := 1.4
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var cutoff := lerpf(0.04, 0.45, minf(t / 0.25, 1.0))
		lp += cutoff * (noise() - lp)
		var env := minf(t / 0.03, 1.0) * (1.0 if t < 0.4 else exp(-(t - 0.4) * 3.0))
		var pop := noise() * exp(-t * 60.0)
		out[i] = lp * env + pop * 0.8
	return out


# Metallic impact: decaying inharmonic partials plus a noise transient.
func synth_clang(duration: float, partials: Array, decay: float) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in partials.size():
			var amp := 1.0 / (1.0 + k * 0.6)
			s += sin(TAU * partials[k] * t) * amp * exp(-t * decay * (1.0 + k * 0.5))
		s += noise() * exp(-t * 90.0) * 0.8
		out[i] = s
	return out


# Base taking damage: a heavy low thud into the structure, a rattle of
# debris, and a short groan of stressed steel.
func synth_structure_hit() -> PackedFloat32Array:
	var duration := 1.1
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var groan_phase := 0.0
	var lp := 0.0

	# Debris grains: short bursts scattered over the first 0.4 s.
	var grains: Array = []
	for g in 14:
		grains.append([rng.randf_range(0.02, 0.4), rng.randf_range(0.2, 1.0)])

	for i in n:
		var t := float(i) / RATE

		# Thud: sine dropping from 70 Hz, with a soft attack.
		phase += 70.0 * exp(-t * 3.0) / RATE
		var thud := sin(TAU * phase) * exp(-t * 7.0) * minf(t / 0.004, 1.0)

		# Impact body: dark noise burst.
		lp += 0.08 * (noise() - lp)
		var body := lp * 3.0 * exp(-t * 14.0)

		# Debris rattle.
		var rattle := 0.0
		for grain in grains:
			var dt: float = t - grain[0]
			if dt >= 0.0 and dt < 0.03:
				rattle += noise() * exp(-dt * 160.0) * grain[1]

		# Steel groan: low wavering tone that swells and fades.
		groan_phase += (95.0 + sin(t * 9.0) * 6.0) / RATE
		var groan := (sin(TAU * groan_phase) + 0.4 * sin(TAU * groan_phase * 2.01)) \
			* sin(PI * clampf((t - 0.1) / 0.9, 0.0, 1.0)) * 0.25

		out[i] = thud * 1.2 + body + rattle * 0.35 + groan
	return out


# Warning tone: one beep per loop, with short fades to avoid clicks.
func synth_beep_loop(period: float, beep: float, freq: float) -> PackedFloat32Array:
	var n := int(period * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		if t >= beep:
			continue
		var fade := minf(minf(t / 0.005, (beep - t) / 0.005), 1.0)
		var tone := sin(TAU * freq * t) * 0.6 + signf(sin(TAU * freq * t)) * 0.25
		out[i] = tone * fade
	return out


# Rotor: low noise chopped by blade passes (16 per second, so it loops).
func synth_rotor_loop() -> PackedFloat32Array:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += 0.06 * (noise() - lp)
		lp2 += 0.06 * (lp - lp2)
		var blade := fmod(t * 16.0, 1.0)
		var pulse := exp(-blade * 9.0)
		out[i] = lp2 * (0.3 + 1.4 * pulse) + sin(TAU * 16.0 * t) * 0.08 * pulse
	# Crossfade the ends so the loop seam doesn't click.
	var fade := int(0.02 * RATE)
	for i in fade:
		var w := float(i) / fade
		out[i] = out[i] * w + out[n - fade + i] * (1.0 - w)
	return out


func synth_click() -> PackedFloat32Array:
	var n := int(0.05 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 1300.0 * t) * exp(-t * 90.0)
	return out


# Short rising blips (hit / kill confirmation, combo sting).
func synth_blips(freqs: Array, length: float) -> PackedFloat32Array:
	var n := int(length * freqs.size() * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var per := int(length * RATE)
	for i in n:
		var k := mini(i / per, freqs.size() - 1)
		var t := float(i - k * per) / RATE
		var env := minf(t / 0.002, 1.0) * exp(-t * 6.0 / length)
		out[i] = (sin(TAU * freqs[k] * t) + 0.3 * sin(TAU * freqs[k] * 2.0 * t)) * env
	return out


# Minigun barrels spinning up: a rising motor whine.
func synth_spin_up() -> PackedFloat32Array:
	var duration := 0.45
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var progress := t / duration
		phase += lerpf(180.0, 720.0, progress * progress) / RATE
		var env := minf(t / 0.02, 1.0) * (1.0 if progress < 0.85 else (1.0 - progress) / 0.15)
		out[i] = (sin(TAU * phase) * 0.6 + sin(TAU * phase * 3.0) * 0.25 + noise() * 0.05) * env
	return out


# Overheat: a metallic clunk followed by a steam hiss.
func synth_overheat() -> PackedFloat32Array:
	var duration := 0.8
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var clunk := (sin(TAU * 220.0 * t) + 0.5 * sin(TAU * 610.0 * t)) * exp(-t * 30.0)
		var white := noise()
		var hiss := (white - prev) * minf(t / 0.05, 1.0) * exp(-t * 3.5)
		prev = white
		out[i] = clunk * 0.9 + hiss * 0.6
	return out


# Falling bomb: a whistle that drops in pitch as it comes down.
func synth_whistle() -> PackedFloat32Array:
	var duration := 1.7
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var progress := t / duration
		var freq := lerpf(1500.0, 520.0, progress) + sin(t * 30.0) * 12.0
		phase += freq / RATE
		var env := minf(t / 0.4, 1.0) * minf((duration - t) / 0.05, 1.0)
		out[i] = (sin(TAU * phase) + noise() * 0.08) * env
	return out


# Dash: a short rising-then-falling band of air noise.
func synth_whoosh() -> PackedFloat32Array:
	var duration := 0.32
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var progress := t / duration
		var cutoff := lerpf(0.05, 0.35, sin(progress * PI))
		lp += cutoff * (noise() - lp)
		lp2 += cutoff * 0.5 * (lp - lp2)
		var env := minf(t / 0.015, 1.0) * pow(1.0 - progress, 1.6)
		# Band-pass: the difference of two low-passes.
		out[i] = (lp - lp2) * env
	return out


# Body hitting the ground: a dull low thump with a little grit.
func synth_thud() -> PackedFloat32Array:
	var duration := 0.3
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += 85.0 * exp(-t * 6.0) / RATE
		lp += 0.12 * (noise() - lp)
		out[i] = sin(TAU * phase) * exp(-t * 16.0) * minf(t / 0.003, 1.0) + lp * exp(-t * 25.0) * 1.5
	return out


# A few distant shouting voices: vowel-like buzz with vibrato, falling in
# pitch, softened so it sounds far away.
func synth_scream() -> PackedFloat32Array:
	var duration := 1.0
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var voices := [[520.0, 0.0], [430.0, 0.08], [610.0, 0.15]]
	for voice in voices:
		var base: float = voice[0]
		var start: float = voice[1]
		var phase := 0.0
		for i in n:
			var t := float(i) / RATE - start
			if t < 0.0:
				continue
			var life := 0.8
			if t > life:
				break
			var f := base * (1.0 - 0.3 * t / life) * (1.0 + 0.02 * sin(t * TAU * 6.0))
			phase += f / RATE
			# Harmonics shaped by "ah" formants (~800 and ~1200 Hz).
			var s := 0.0
			for k in range(1, 9):
				var hz := f * k
				var gain := exp(-pow((hz - 800.0) / 220.0, 2.0)) + 0.7 * exp(-pow((hz - 1200.0) / 260.0, 2.0)) + 0.05
				s += sin(TAU * phase * k) * gain
			var env := minf(t / 0.05, 1.0) * clampf((life - t) / 0.3, 0.0, 1.0)
			out[i] += (s + noise() * 0.15) * env
	# Distance: smooth off the highs.
	var lp := 0.0
	for i in n:
		lp += 0.35 * (out[i] - lp)
		out[i] = lp
	return out
