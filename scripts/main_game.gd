extends Node2D

const GuestScene = preload("res://scenes/guest.tscn")
const MAX_VENUE_GUESTS = 20

@onready var vibe_meter:         ProgressBar = $VenueLayer/VibePanel/VibeMeter
@onready var vibe_label:         Label       = $VenueLayer/VibePanel/VibeLabel
@onready var theme_reveal:       Label       = $VenueLayer/ThemeReveal
@onready var theme_persist:      Label       = $VenueLayer/ThemePersistPanel/ThemeName
@onready var timer_label:        Label       = $UILayer/TimerPanel/Timer
@onready var theme_tint:         ColorRect   = $TintLayer/ThemeTint
@onready var crowd_container:    Node2D      = $VenueLayer/CrowdContainer
@onready var lights_container:   Node2D      = $VenueLayer/LightsContainer
@onready var theme_hint_label:   Label       = $EntranceLayer/ThemeHintPanel/ThemeHint
@onready var battle_screen                   = $BattleScreen
@onready var guest_queue                     = $EntranceLayer/GuestQueue
@onready var deputy                          = $EntranceLayer/Deputy

var _current_bad_guest: Dictionary = {}
var _venue_guest_count: int = 0

func _ready() -> void:
	GameManager.vibe_changed.connect(_on_vibe_changed)
	GameManager.run_ended.connect(_on_run_ended)
	GameManager.theme_changed.connect(_on_theme_changed)

	guest_queue.bad_guest_entered.connect(_on_bad_guest_entered)
	guest_queue.good_guest_entered.connect(_on_good_guest_entered)
	guest_queue.wrong_reject.connect(_on_wrong_reject)

	battle_screen.battle_ended.connect(_on_battle_ended)

	vibe_meter.value = GameManager.vibe
	vibe_label.text  = "VIBE  100%"

	_apply_theme_tint()
	_update_theme_labels()
	_show_theme_briefly()
	_spawn_lights()
	_spawn_crowd()

func _process(_delta: float) -> void:
	timer_label.text = _fmt_clock(GameManager.run_time)

# ── Guest events ──────────────────────────────────────────────────────────────

func _on_bad_guest_entered(guest: Dictionary) -> void:
	_current_bad_guest = guest
	VibeSystem.add_bad_guest(guest)
	battle_screen.start_battle(guest)
	deputy.enter_fight_assist()

func _on_good_guest_entered(guest: Dictionary) -> void:
	VibeSystem.add_good_guest(guest)
	_spawn_guest_in_venue(guest)

func _on_wrong_reject(guest: Dictionary) -> void:
	if guest.get("is_famous") and guest.get("should_enter"):
		VibeSystem.on_wrong_famous_reject()

# ── Battle events ─────────────────────────────────────────────────────────────

func _on_battle_ended(player_won: bool, enemy_data: Dictionary) -> void:
	VibeSystem.remove_bad_guest(_current_bad_guest)
	if player_won:
		VibeSystem.on_fight_win()
	else:
		VibeSystem.on_fight_lose()
		# Bad guy forced their way in — show them in the venue
		_spawn_guest_in_venue(enemy_data)
	guest_queue.resume_after_battle()

# ── Venue crowd ───────────────────────────────────────────────────────────────

func _spawn_guest_in_venue(data: Dictionary) -> void:
	if _venue_guest_count >= MAX_VENUE_GUESTS:
		return

	var node = GuestScene.instantiate()
	node.setup(data)
	# Scale down and position randomly across the venue area
	var scale_factor = randf_range(0.28, 0.40)
	node.scale = Vector2(scale_factor, scale_factor)
	# Venue area is 0–1280 wide, 0–504 tall (VenueLayer)
	# Keep guests near the bottom 2/3 of the venue (the dance floor)
	var x = randf_range(60.0, 1220.0)
	var y = randf_range(280.0, 490.0)
	node.position = Vector2(x, y)
	# Hide labels — they're in the crowd now
	node.hide_ui()
	crowd_container.add_child(node)
	_venue_guest_count += 1

# ── Vibe ──────────────────────────────────────────────────────────────────────

func _on_vibe_changed(new_vibe: float) -> void:
	vibe_meter.value = new_vibe
	vibe_label.text  = "VIBE  %.0f%%" % new_vibe
	# Tint vibe bar color: green → yellow → red
	if new_vibe > 60.0:
		vibe_meter.modulate = Color(1, 1, 1)
	elif new_vibe > 30.0:
		vibe_meter.modulate = Color(1.0, 0.85, 0.1)
	else:
		vibe_meter.modulate = Color(1.0, 0.25, 0.25)

func _on_run_ended() -> void:
	get_tree().change_scene_to_file("res://scenes/score_screen.tscn")

# ── Theme ─────────────────────────────────────────────────────────────────────

func _on_theme_changed(_key: String) -> void:
	_apply_theme_tint()
	_update_theme_labels()
	_show_theme_briefly()

func _apply_theme_tint() -> void:
	var theme = GameManager.get_theme()
	theme_tint.color = Color(theme.get("tint_color", "#00000000"))

func _update_theme_labels() -> void:
	var theme = GameManager.get_theme()
	theme_persist.text   = theme.get("name", "")
	theme_hint_label.text = theme.get("hint", "")

func _show_theme_briefly() -> void:
	var theme = GameManager.get_theme()
	theme_reveal.text    = theme.get("name", "")
	theme_reveal.visible = true
	await get_tree().create_timer(3.0).timeout
	theme_reveal.visible = false

# ── Atmosphere ────────────────────────────────────────────────────────────────

func _spawn_lights() -> void:
	var beams = [
		{ "x": 120.0, "w": 38.0, "c": Color(0.70, 0.20, 1.00, 0.04) },
		{ "x": 310.0, "w": 52.0, "c": Color(0.00, 0.60, 1.00, 0.03) },
		{ "x": 560.0, "w": 34.0, "c": Color(0.95, 0.10, 0.55, 0.03) },
		{ "x": 790.0, "w": 48.0, "c": Color(1.00, 0.75, 0.00, 0.025) },
		{ "x": 1060.0,"w": 42.0, "c": Color(0.35, 0.90, 0.55, 0.03) },
	]
	for d in beams:
		var beam = ColorRect.new()
		beam.size     = Vector2(d["w"], 504.0)
		beam.position = Vector2(d["x"], 0.0)
		beam.color    = d["c"]
		beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lights_container.add_child(beam)

func _spawn_crowd() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(32):
		var w  = rng.randf_range(16, 36)
		var h  = rng.randf_range(55, 115)
		var x  = rng.randf_range(8, 1264)
		var brt = rng.randf_range(0.04, 0.10)

		# Body silhouette
		var body = ColorRect.new()
		body.size     = Vector2(w, h)
		body.position = Vector2(x - w * 0.5, 492.0 - h)
		body.color    = Color(brt * 0.55, brt * 0.35, brt, rng.randf_range(0.7, 1.0))
		crowd_container.add_child(body)

		# Head silhouette
		var hw = w * 0.65
		var head = ColorRect.new()
		head.size     = Vector2(hw, 18.0)
		head.position = Vector2(x - hw * 0.5, body.position.y - 18.0)
		head.color    = body.color
		crowd_container.add_child(head)

# ── Helpers ───────────────────────────────────────────────────────────────

# 1 real second == 1 in-game minute.  Start time: 21:00 (9 PM).  End: 24:00 (12 AM).
func _fmt_clock(elapsed: float) -> String:
	var total_mins: int = int(clamp(elapsed, 0, GameManager.GAME_DURATION))
	var game_hour: int  = 21 + total_mins / 60
	var game_min:  int  = total_mins % 60
	if game_hour >= 24:
		return "12:00 AM"
	var h12: int        = game_hour - 12   # 21-12=9, 22-12=10, 23-12=11
	return "%d:%02d PM" % [h12, game_min]
