extends AnimatedSprite2D

var _state:          int   = GameManager.DeputyState.IDLE
var _state_timer:    Timer
var _advice_bubble:  Label = null
var _interfere_min:  float = 15.0
var _interfere_max:  float = 30.0
var _wander_min:     float = 10.0
var _wander_max:     float = 20.0
var _start_x:        float = 0.0

func _ready() -> void:
	_start_x = position.x
	_advice_bubble = get_parent().get_node_or_null("AdviceBubble")

	_state_timer = Timer.new()
	_state_timer.one_shot = true
	add_child(_state_timer)
	_state_timer.timeout.connect(_on_timer)

	GameManager.difficulty_changed.connect(_on_difficulty_changed)
	_enter_idle()

func _on_difficulty_changed(diff: float) -> void:
	_interfere_min = max(5.0,  15.0 / diff)
	_interfere_max = max(10.0, 30.0 / diff)

# ── State machine ─────────────────────────────────────────────────────────────

func _enter_idle() -> void:
	_state = GameManager.DeputyState.IDLE
	GameManager.deputy_state = _state
	_safe_play("idle")
	var wait = randf_range(_interfere_min, _interfere_max)
	_state_timer.start(wait)

func _on_timer() -> void:
	match _state:
		GameManager.DeputyState.IDLE:
			if randf() < 0.55:
				_enter_interfere()
			else:
				_enter_wander()
		_:
			_enter_idle()

func _enter_interfere() -> void:
	if GameManager.current_phase != GameManager.GamePhase.DOOR:
		_enter_idle()
		return
	_state = GameManager.DeputyState.INTERFERE_DOOR
	GameManager.deputy_state = _state
	_safe_play("walk")

	var roll = randf()
	if roll < 0.5:
		_give_wrong_advice()
	else:
		_block_view()

	await get_tree().create_timer(2.0).timeout
	_enter_idle()

func _give_wrong_advice() -> void:
	var msg = "Let them in! →" if randf() < 0.5 else "← Reject them!"
	_show_bubble(msg)

func _block_view() -> void:
	_show_bubble("...")
	var tween = create_tween()
	tween.tween_property(self, "position:x", _start_x - 60.0, 0.4)
	await get_tree().create_timer(1.5).timeout
	tween = create_tween()
	tween.tween_property(self, "position:x", _start_x, 0.4)

func _enter_wander() -> void:
	_state = GameManager.DeputyState.WANDER
	GameManager.deputy_state = _state
	_safe_play("walk")
	var tween = create_tween()
	var target_x = _start_x + randf_range(-120.0, 120.0)
	tween.tween_property(self, "position:x", target_x, 0.8)
	_state_timer.start(randf_range(_wander_min, _wander_max))

func enter_fight_assist() -> void:
	_state = GameManager.DeputyState.FIGHT_ASSIST
	GameManager.deputy_state = _state
	_safe_play("walk")
	_state_timer.stop()

	# Deputy runs across screen during battle
	var tween = create_tween()
	tween.tween_property(self, "position:x", _start_x + 200.0, 0.6)
	await get_tree().create_timer(1.0).timeout
	tween = create_tween()
	tween.tween_property(self, "position:x", _start_x, 0.6)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _show_bubble(text: String) -> void:
	if _advice_bubble == null:
		return
	_advice_bubble.text    = text
	_advice_bubble.visible = true
	await get_tree().create_timer(2.0).timeout
	_advice_bubble.visible = false

func _safe_play(anim: String) -> void:
	if sprite_frames != null and sprite_frames.has_animation(anim):
		play(anim)
