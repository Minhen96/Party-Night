extends Node2D

@onready var vibe_meter:    ProgressBar = $VenueLayer/VibeMeter
@onready var vibe_label:    Label       = $VenueLayer/VibeLabel
@onready var theme_reveal:  Label       = $VenueLayer/ThemeReveal
@onready var timer_label:   Label       = $UILayer/Timer
@onready var theme_tint:    ColorRect   = $TintLayer/ThemeTint
@onready var battle_screen              = $BattleScreen
@onready var guest_queue                = $EntranceLayer/GuestQueue
@onready var deputy                     = $EntranceLayer/Deputy

var _current_bad_guest: Dictionary = {}

func _ready() -> void:
	GameManager.vibe_changed.connect(_on_vibe_changed)
	GameManager.run_ended.connect(_on_run_ended)
	GameManager.theme_changed.connect(_on_theme_changed)

	guest_queue.bad_guest_entered.connect(_on_bad_guest_entered)
	guest_queue.good_guest_entered.connect(_on_good_guest_entered)
	guest_queue.wrong_reject.connect(_on_wrong_reject)

	battle_screen.battle_ended.connect(_on_battle_ended)

	vibe_meter.value = GameManager.vibe
	vibe_label.text  = "VIBE: 100%"

	_apply_theme_tint()
	_show_theme_briefly()

func _process(_delta: float) -> void:
	timer_label.text = _fmt_time(GameManager.run_time)

# ── Guest events ──────────────────────────────────────────────────────────────

func _on_bad_guest_entered(guest: Dictionary) -> void:
	_current_bad_guest = guest
	VibeSystem.add_bad_guest(guest)
	battle_screen.start_battle(guest)
	deputy.enter_fight_assist()

func _on_good_guest_entered(guest: Dictionary) -> void:
	VibeSystem.add_good_guest(guest)

func _on_wrong_reject(guest: Dictionary) -> void:
	if guest.get("is_famous") and guest.get("should_enter"):
		VibeSystem.on_wrong_famous_reject()

# ── Battle events ─────────────────────────────────────────────────────────────

func _on_battle_ended(player_won: bool) -> void:
	VibeSystem.remove_bad_guest(_current_bad_guest)
	if player_won:
		VibeSystem.on_fight_win()
	else:
		VibeSystem.on_fight_lose()
	guest_queue.resume_after_battle()

# ── Vibe ──────────────────────────────────────────────────────────────────────

func _on_vibe_changed(new_vibe: float) -> void:
	vibe_meter.value = new_vibe
	vibe_label.text  = "VIBE: %.0f%%" % new_vibe

func _on_run_ended() -> void:
	get_tree().change_scene_to_file("res://scenes/score_screen.tscn")

# ── Theme tint ────────────────────────────────────────────────────────────────

func _on_theme_changed(_key: String) -> void:
	_apply_theme_tint()
	_show_theme_briefly()

func _apply_theme_tint() -> void:
	var theme = GameManager.get_theme()
	var hex = theme.get("tint_color", "#00000000")
	theme_tint.color = Color(hex)

func _show_theme_briefly() -> void:
	var theme = GameManager.get_theme()
	theme_reveal.text    = theme.get("name", "")
	theme_reveal.visible = true
	await get_tree().create_timer(3.0).timeout
	theme_reveal.visible = false

# ── Helpers ───────────────────────────────────────────────────────────────────

func _fmt_time(s: float) -> String:
	return "%02d:%02d" % [int(s) / 60, int(s) % 60]
