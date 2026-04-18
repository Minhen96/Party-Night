extends Node2D

signal bad_guest_entered(guest_data: Dictionary)
signal good_guest_entered(guest_data: Dictionary)
signal wrong_reject(guest_data: Dictionary)

const GuestScene = preload("res://scenes/guest.tscn")
const FAMOUS_CHANCE_BASE = 0.15

var _current_guest:      Dictionary = {}
var _queue:              Array      = []
var _waiting_for_input:  bool       = false
var _spawn_timer:        Timer
var _current_guest_node: Node       = null
var _current_guest_spot: Node2D

func _ready() -> void:
	_current_guest_spot = get_parent().get_node("CurrentGuestSpot")

	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = false
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_on_spawn_timer)
	_reset_timer()

	# Spawn first guest right away
	_queue.append(_build_guest())
	_try_present()

func resume_after_battle() -> void:
	_waiting_for_input = false
	_try_present()

# ── Timer ─────────────────────────────────────────────────────────────────────

func _reset_timer() -> void:
	_spawn_timer.wait_time = max(1.0, 3.0 / GameManager.difficulty)
	_spawn_timer.start()

func _on_spawn_timer() -> void:
	if _queue.size() < 3:
		_queue.append(_build_guest())
	_reset_timer()
	_try_present()

# ── Guest building ────────────────────────────────────────────────────────────

func _build_guest() -> Dictionary:
	var famous_chance = FAMOUS_CHANCE_BASE + (GameManager.run_time / 300.0) * 0.15
	if randf() < famous_chance:
		return _build_famous()
	return _build_regular()

func _build_regular() -> Dictionary:
	var gd    = GameManager.guests_data
	var top   = _pick(gd["tops"])
	var bot   = _pick(gd["bottoms"])
	var shoes = _pick(gd["shoes"])
	var acc   = _pick(gd["accessories"])

	var all_tags: Array = []
	all_tags.append_array(top["tags"])
	all_tags.append_array(bot["tags"])
	all_tags.append_array(shoes["tags"])
	all_tags.append_array(acc["tags"])

	return {
		"is_famous":    false,
		"top":          top,
		"bottom":       bot,
		"shoes":        shoes,
		"accessory":    acc,
		"tags":         all_tags,
		"should_enter": _check_theme(all_tags)
	}

func _build_famous() -> Dictionary:
	var keys = GameManager.famous_guests_data.keys()
	var key  = keys[randi() % keys.size()]
	var data = GameManager.famous_guests_data[key].duplicate(true)
	var moods = data["moods"].keys()
	var mood  = moods[randi() % moods.size()]
	data["mood"]       = mood
	data["mood_data"]  = data["moods"][mood]
	data["is_famous"]  = true
	data["key"]        = key
	data["tags"]       = []
	data["should_enter"] = not data["mood_data"]["triggers_fight"]
	return data

func _pick(arr: Array) -> Dictionary:
	return arr[randi() % arr.size()]

# ── Theme check ───────────────────────────────────────────────────────────────

func _check_theme(tags: Array) -> bool:
	var theme = GameManager.get_theme()

	for tag in theme.get("required", []):
		if tag not in tags:
			return false

	var req_any: Array = theme.get("required_any", [])
	if not req_any.is_empty():
		var found = false
		for tag in req_any:
			if tag in tags:
				found = true
				break
		if not found:
			return false

	for tag in theme.get("forbidden", []):
		if tag in tags:
			return false

	return true

# ── Display ───────────────────────────────────────────────────────────────────

func _try_present() -> void:
	if _waiting_for_input or _queue.is_empty():
		return
	_current_guest = _queue.pop_front()
	_waiting_for_input = true
	_show_guest(_current_guest)

func _show_guest(guest: Dictionary) -> void:
	if _current_guest_node:
		_current_guest_node.queue_free()
		_current_guest_node = null
	var node = GuestScene.instantiate()
	node.setup(guest)              # store data before _ready() runs
	_current_guest_spot.add_child(node)  # _ready() fires here, reads stored data
	_current_guest_node = node

func _clear_guest() -> void:
	if _current_guest_node:
		_current_guest_node.queue_free()
		_current_guest_node = null

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _waiting_for_input:
		return
	if GameManager.current_phase != GameManager.GamePhase.DOOR:
		return
	if event.is_action_pressed("decision_left"):
		get_viewport().set_input_as_handled()
		_decide("reject")
	elif event.is_action_pressed("decision_right"):
		get_viewport().set_input_as_handled()
		_decide("let_in")

func _decide(direction: String) -> void:
	GameManager.stat_guests_processed += 1
	var guest = _current_guest
	var should_enter = guest.get("should_enter", false)
	_waiting_for_input = false

	if direction == "let_in":
		if should_enter:
			_clear_guest()
			emit_signal("good_guest_entered", guest)
			_try_present()
		else:
			# Bad guest — battle triggers, do NOT call _try_present here
			# main_game will call resume_after_battle() after battle ends
			GameManager.stat_wrong_calls += 1
			_clear_guest()
			emit_signal("bad_guest_entered", guest)
	else:  # reject
		if should_enter:
			GameManager.stat_wrong_calls += 1
			GameManager.change_vibe(-5.0)
			if guest.get("is_famous"):
				emit_signal("wrong_reject", guest)
		else:
			GameManager.change_vibe(2.0)
			if guest.get("is_famous") and guest.get("mood_data", {}).get("triggers_fight"):
				GameManager.stat_famous_correct += 1
				VibeSystem.on_correct_famous_reject()
		_clear_guest()
		_try_present()
