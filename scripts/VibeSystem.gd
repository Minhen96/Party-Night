extends Node

const DRAIN_BAD_GUEST:   float = 5.0 / 3.0
const DRAIN_FAMOUS_BAD:  float = 3.0 / 3.0
const RESTORE_GOOD:      float = 2.0 / 5.0

var _active_bad:  Array = []
var _active_good: Array = []

func _process(delta: float) -> void:
	if GameManager.current_phase != GameManager.GamePhase.DOOR:
		return
	var net = 0.0
	net -= _active_bad.size()  * DRAIN_BAD_GUEST * delta
	net += _active_good.size() * RESTORE_GOOD    * delta
	if not is_zero_approx(net):
		GameManager.change_vibe(net)

func add_bad_guest(guest: Dictionary) -> void:
	_active_bad.append(guest)

func remove_bad_guest(guest: Dictionary) -> void:
	_active_bad.erase(guest)

func add_good_guest(guest: Dictionary) -> void:
	if guest.get("is_famous"):
		var boost = guest.get("mood_data", {}).get("vibe_on_enter", 0)
		GameManager.change_vibe(float(boost))
	_active_good.append(guest)

func on_fight_win() -> void:
	GameManager.change_vibe(5.0)

func on_fight_lose() -> void:
	GameManager.change_vibe(-10.0)

func on_correct_famous_reject() -> void:
	GameManager.change_vibe(3.0)

func on_wrong_famous_reject() -> void:
	GameManager.change_vibe(-5.0)

func on_deputy_wrong_entry() -> void:
	GameManager.change_vibe(-8.0)

func reset() -> void:
	_active_bad.clear()
	_active_good.clear()
