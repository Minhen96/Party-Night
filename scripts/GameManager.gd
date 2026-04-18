extends Node

# ── Signals ───────────────────────────────────────────────────────────────────
signal vibe_changed(new_vibe: float)
signal run_ended
signal theme_changed(theme_key: String)
signal difficulty_changed(new_difficulty: float)

# ── Enums ─────────────────────────────────────────────────────────────────────
enum DeputyState { IDLE, INTERFERE_DOOR, WANDER, FIGHT_ASSIST }
enum GamePhase { DOOR, BATTLE, SCORE }

# ── Run State ─────────────────────────────────────────────────────────────────
var vibe: float = 100.0
var run_time: float = 0.0
var current_phase: GamePhase = GamePhase.DOOR
var current_theme: String = ""
var difficulty: float = 1.0

# ── Player ────────────────────────────────────────────────────────────────────
var player_hp: int = 100
var player_skills: Array = []

# ── Deputy ────────────────────────────────────────────────────────────────────
var deputy_state: DeputyState = DeputyState.IDLE
var deputy_ko: bool = false

# ── Stats ─────────────────────────────────────────────────────────────────────
var stat_guests_processed: int = 0
var stat_wrong_calls: int = 0
var stat_famous_correct: int = 0
var stat_skills_stolen: Array = []
var stat_deputy_betrayals: int = 0

# ── Data Cache ────────────────────────────────────────────────────────────────
var themes_data: Dictionary = {}
var guests_data: Dictionary = {}
var famous_guests_data: Dictionary = {}
var skills_data: Dictionary = {}

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_data()
	_pick_theme()
	_init_skills()

func _process(delta: float) -> void:
	if current_phase == GamePhase.DOOR:
		run_time += delta
		_update_difficulty()

# ── Data Loading ──────────────────────────────────────────────────────────────

func _load_data() -> void:
	themes_data        = _load_json("res://data/themes.json")
	guests_data        = _load_json("res://data/guests.json")
	famous_guests_data = _load_json("res://data/famous_guests.json")
	skills_data        = _load_json("res://data/skills.json")

func _load_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open: " + path)
		return {}
	var text = file.get_as_text()
	file.close()
	var result = JSON.parse_string(text)
	if result == null:
		push_error("Failed to parse JSON: " + path)
		return {}
	return result

# ── Theme ─────────────────────────────────────────────────────────────────────

func _pick_theme() -> void:
	var keys = themes_data.keys()
	if keys.is_empty():
		return
	current_theme = keys[randi() % keys.size()]
	emit_signal("theme_changed", current_theme)

func get_theme() -> Dictionary:
	return themes_data.get(current_theme, {})

# ── Skills ────────────────────────────────────────────────────────────────────

func _init_skills() -> void:
	player_skills = ["tackle", "intimidate", "call_deputy", "stall"]

func replace_skill(slot_index: int, new_skill_key: String) -> void:
	if slot_index >= 0 and slot_index < player_skills.size():
		player_skills[slot_index] = new_skill_key
		stat_skills_stolen.append(new_skill_key)

# ── Vibe ──────────────────────────────────────────────────────────────────────

func change_vibe(amount: float) -> void:
	vibe = clamp(vibe + amount, 0.0, 100.0)
	emit_signal("vibe_changed", vibe)
	if vibe <= 0.0:
		end_run()

# ── Difficulty ────────────────────────────────────────────────────────────────

func _update_difficulty() -> void:
	var new_diff = clamp(1.0 + (run_time / 120.0) * 2.0, 1.0, 3.0)
	if abs(new_diff - difficulty) > 0.05:
		difficulty = new_diff
		emit_signal("difficulty_changed", difficulty)

# ── Phase ─────────────────────────────────────────────────────────────────────

func set_phase(phase: GamePhase) -> void:
	current_phase = phase

# ── Run ───────────────────────────────────────────────────────────────────────

func end_run() -> void:
	if current_phase == GamePhase.SCORE:
		return
	current_phase = GamePhase.SCORE
	emit_signal("run_ended")

func reset_run() -> void:
	vibe = 100.0
	run_time = 0.0
	difficulty = 1.0
	player_hp = 100
	deputy_ko = false
	deputy_state = DeputyState.IDLE
	stat_guests_processed = 0
	stat_wrong_calls = 0
	stat_famous_correct = 0
	stat_skills_stolen = []
	stat_deputy_betrayals = 0
	current_phase = GamePhase.DOOR
	_pick_theme()
	_init_skills()
	VibeSystem.reset()
