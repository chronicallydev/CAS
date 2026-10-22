extends Node

# Background music: playlists from the Ideologies soundtrack
# (assets/music/), crossfaded on its own "Music" bus. The tracks aren't in
# the repo (see .gitignore): without them the game just runs silent.
#
# Autoloaded as "Music", like Sfx: it holds no game state and keeps
# playing through pauses, slow motion and scene changes.
#   Music.play("arena")  - switch playlist (does nothing if already on it)
#   Music.duck(true)     - lower the music while a menu is up

const DIR := "res://assets/music/"
const BUS := "Music"
# Bus level, under the sound effects (Sfx MIX), and the extra drop while
# ducked.
const LEVEL_DB := -9.0
const DUCK_DB := -8.0
const FADE_SECONDS := 1.5

# Each playlist plays its tracks in order, then wraps. Switching back to a
# playlist carries on with its next track rather than replaying the last.
const PLAYLISTS := {
	"travel": [
		"06_travel_together",
		"20_ascend_the_castle",
		"14_city_in_the_sky_bron_laukra",
		"02_twin_legends_prologue",
		"19_castleopolis",
	],
	"arena": [
		"08_synchronus_battle",
		"12_miniboss",
		"23_mick_gordon_at_home_part_1",
		"24_mick_gordon_at_home_part_2",
	],
	"final_travel": ["21_two_sons_elegy_decisive_battle_1"],
	"final_arena": ["16_dangerous_foes_boss_battle", "22_ideologies_decisive_battle_2"],
	"shot_down": ["18_waiting"],
	"run_complete": ["05_brotherhood"],
	"test_range": ["04_sparring_session", "11_squad_building"],
	"menu": ["01_title_screen"],
}

var players: Array[AudioStreamPlayer] = []
# Which of the two players is the one fading in / playing.
var front: int = 0
var playlist: String = ""
var next_track: Dictionary = {}
var bus_tween: Tween
var fade_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, BUS)
	AudioServer.set_bus_volume_db(bus, LEVEL_DB)

	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		player.volume_db = -80.0
		add_child(player)
		player.finished.connect(_on_finished.bind(player))
		players.append(player)


# Quitting mid-track: let go of the stream, or it's reported leaked at exit.
func _exit_tree() -> void:
	for player in players:
		player.stop()
		player.stream = null


func play(list: String) -> void:
	if list == playlist or not PLAYLISTS.has(list):
		return
	playlist = list
	crossfade(take_track(list))


func stop() -> void:
	playlist = ""
	crossfade(null)


func duck(on: bool) -> void:
	if bus_tween != null:
		bus_tween.kill()
	bus_tween = create_tween().set_ignore_time_scale()
	var bus := AudioServer.get_bus_index(BUS)
	bus_tween.tween_method(func(db: float) -> void: AudioServer.set_bus_volume_db(bus, db),
		AudioServer.get_bus_volume_db(bus), LEVEL_DB + (DUCK_DB if on else 0.0), 0.4)


func take_track(list: String) -> AudioStream:
	var tracks: Array = PLAYLISTS[list]
	var index: int = next_track.get(list, 0)
	next_track[list] = (index + 1) % tracks.size()
	var path: String = DIR + tracks[index] + ".mp3"
	# Null (silence) when the track isn't there.
	return load(path) if ResourceLoader.exists(path) else null


# Fades the playing track out and the new one in on the other player.
func crossfade(stream: AudioStream) -> void:
	var old := players[front]
	front = 1 - front
	var new := players[front]

	if fade_tween != null:
		fade_tween.kill()
	fade_tween = create_tween().set_ignore_time_scale().set_parallel()
	if stream != null:
		new.stream = stream
		new.volume_db = -30.0
		new.play()
		fade_tween.tween_property(new, "volume_db", 0.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_tween.tween_property(old, "volume_db", -80.0, FADE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade_tween.chain().tween_callback(old.stop)


# A track ran out: go straight on to the playlist's next one.
func _on_finished(player: AudioStreamPlayer) -> void:
	if player != players[front] or playlist == "":
		return
	player.stream = take_track(playlist)
	if player.stream != null:
		player.play()
