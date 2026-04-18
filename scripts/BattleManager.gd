extends CanvasLayer

signal battle_ended(player_won: bool, enemy_data: Dictionary)

@onready var player_hp_bar:   ProgressBar      = $PlayerHP
@onready var enemy_hp_bar:    ProgressBar      = $EnemyHP
@onready var player_hp_label: Label            = $PlayerHPLabel
@onready var enemy_hp_label:  Label            = $EnemyHPLabel
@onready var enemy_name_label:Label            = $EnemyName
@onready var skill_bar:       HBoxContainer    = $SkillBar
@onready var battle_log:      Label            = $BattleLog
@onready var steal_prompt:    Panel            = $StealPrompt
@onready var deputy_sprite:   AnimatedSprite2D = $DeputyInterrupt
@onready var player_sprite:   Sprite2D         = $PlayerSprite
@onready var enemy_head:      Sprite2D         = $EnemyContainer/Head
@onready var enemy_top:       Sprite2D         = $EnemyContainer/Top
@onready var enemy_bottom:    Sprite2D         = $EnemyContainer/Bottom
@onready var enemy_lleg:      Sprite2D         = $EnemyContainer/LLeg
@onready var enemy_rleg:      Sprite2D         = $EnemyContainer/RLeg
@onready var enemy_shoes:     Sprite2D         = $EnemyContainer/Shoes
@onready var enemy_acc:       Sprite2D         = $EnemyContainer/Accessory
@onready var enemy_portrait:  Sprite2D         = $EnemyContainer/EnemySprite

const PLAYER_MAX_HP = 100

var _player_hp:          int        = PLAYER_MAX_HP
var _enemy_hp:           int        = 0
var _enemy_max_hp:       int        = 0
var _enemy:              Dictionary = {}
var _selected_skill:     int        = 0
var _player_turn:        bool       = true
var _battle_active:      bool       = false
var _skip_enemy_turn:    bool       = false
var _enemy_dmg_debuff:   float      = 1.0
var _debuff_turns:       int        = 0
var _last_enemy_dmg:     int        = 0
var _deputy_redirected:  bool       = false

func _ready() -> void:
	visible = false
	steal_prompt.visible = false
	$StealPrompt/SkipButton.pressed.connect(_on_skip_steal)

func start_battle(enemy: Dictionary) -> void:
	_enemy          = enemy
	_player_hp      = GameManager.player_hp
	_enemy_max_hp   = int(enemy.get("base_hp", 80) * (1.0 + GameManager.difficulty * 0.2))
	_enemy_hp       = _enemy_max_hp
	_skip_enemy_turn    = false
	_enemy_dmg_debuff   = 1.0
	_debuff_turns       = 0
	_last_enemy_dmg     = 0
	_deputy_redirected  = false
	_selected_skill     = 0
	_player_turn        = true
	_battle_active      = true

	GameManager.set_phase(GameManager.GamePhase.BATTLE)
	GameManager.deputy_ko = false
	visible = true

	enemy_name_label.text = enemy.get("name", "Guest")
	_refresh_skill_bar()
	_update_hp()
	_setup_sprites()
	_log("Battle start! %s vs you!" % enemy.get("name", "Guest"))

func _setup_sprites() -> void:
	# Player
	player_sprite.texture = load("res://assets/sprites/player/player_battle.png")
	
	# Clear previous enemy sprites
	enemy_head.texture    = null
	enemy_top.texture     = null
	enemy_bottom.texture  = null
	enemy_lleg.texture    = null
	enemy_rleg.texture    = null
	enemy_shoes.texture   = null
	enemy_acc.texture     = null
	enemy_portrait.texture = null
	enemy_portrait.visible = false

	if _enemy.get("is_famous"):
		var key = _enemy.get("key", "")
		var path = "res://assets/sprites/famous_guests/%s.png" % key
		if ResourceLoader.exists(path):
			enemy_portrait.texture = load(path)
			enemy_portrait.visible = true
	else:
		# Regular guest — populate layers
		_load_sprite(enemy_head,   "heads",       "default_head")
		_load_sprite(enemy_top,    "tops",        _enemy.get("top", {}).get("key", ""))
		_load_sprite(enemy_shoes,  "shoes",       _enemy.get("shoes", {}).get("key", ""))
		_load_sprite(enemy_acc,    "accessories", _enemy.get("accessory", {}).get("key", ""))
		
		var b_key = _enemy.get("bottom", {}).get("key", "")
		_load_sprite(enemy_bottom, "bottoms", b_key)
		_load_sprite(enemy_lleg,   "bottoms", b_key + "_lleg")
		_load_sprite(enemy_rleg,   "bottoms", b_key + "_rleg")

func _load_sprite(sprite_node: Sprite2D, folder: String, key: String) -> void:
	if key == "" or key == "none":
		sprite_node.texture = null
		return
	var path = "res://assets/sprites/guests/%s/%s.png" % [folder, key]
	if ResourceLoader.exists(path):
		sprite_node.texture = load(path)
	else:
		sprite_node.texture = null

func _input(event: InputEvent) -> void:
	if not _battle_active or not _player_turn:
		return
	if event.is_action_pressed("decision_left"):
		get_viewport().set_input_as_handled()
		_selected_skill = (_selected_skill - 1 + GameManager.player_skills.size()) % GameManager.player_skills.size()
		_refresh_skill_bar()
	elif event.is_action_pressed("decision_right"):
		get_viewport().set_input_as_handled()
		_selected_skill = (_selected_skill + 1) % GameManager.player_skills.size()
		_refresh_skill_bar()
	elif event.is_action_pressed("skill_confirm"):
		get_viewport().set_input_as_handled()
		_execute_player_turn(_selected_skill)

# ── Player turn ───────────────────────────────────────────────────────────────

func _execute_player_turn(slot: int) -> void:
	_player_turn = false
	var key   = GameManager.player_skills[slot]
	var skill = GameManager.skills_data.get(key, {})
	_apply_skill(skill, key)
	_update_hp()

	if not _battle_active:
		return

	await get_tree().create_timer(0.5).timeout
	_check_deputy_interrupt()
	_update_hp()

	if not _battle_active:
		return

	await get_tree().create_timer(0.4).timeout
	_check_battle_end()

	if _battle_active:
		await get_tree().create_timer(0.3).timeout
		_execute_enemy_turn()

func _apply_skill(skill: Dictionary, key: String) -> void:
	var label = skill.get("name", key)
	match skill.get("effect", "none"):
		"none":
			var dmg = skill.get("damage", 0)
			_enemy_hp -= dmg
			_log("You use %s! %d damage." % [label, dmg])
		"skip_enemy_turn":
			_skip_enemy_turn = true
			_log("You Intimidate! Enemy will skip next turn.")
		"call_deputy":
			_skill_call_deputy()
		"stall":
			var heal = skill.get("heal", 15)
			_player_hp = mini(_player_hp + heal, PLAYER_MAX_HP)
			_log("You Stall! Recovered %d HP. Enemy gets a free hit." % heal)
			_update_hp()
			_enemy_free_hit()
		"debuff_enemy_damage":
			_enemy_dmg_debuff = 0.5
			_debuff_turns = skill.get("effect_duration", 2)
			_log("Critique! Enemy damage halved for %d turns." % _debuff_turns)
		"copy_enemy_move":
			_enemy_hp -= _last_enemy_dmg
			_log("Optimise! Copied enemy's last move for %d damage." % _last_enemy_dmg)
		"go_viral":
			var dmg = skill.get("damage", 25)
			_enemy_hp -= dmg
			_skip_enemy_turn = true
			_log("Go Viral! %d damage and enemy stunned." % dmg)
		"bribe":
			_skill_bribe()
		"scene":
			var dmg = skill.get("damage", 20)
			_enemy_hp -= dmg
			_deputy_redirected = true
			_log("Scene! %d damage. Deputy drawn away this turn." % dmg)
		"detox":
			var heal = skill.get("heal", 25)
			_player_hp = mini(_player_hp + heal, PLAYER_MAX_HP)
			_enemy_dmg_debuff = 1.0
			_log("Detox! Healed %d HP." % heal)
		"disrupt":
			var dmg = skill.get("damage", 15)
			_enemy_hp -= dmg
			_log("Disrupt! %d damage." % dmg)
		_:
			_log("Used %s." % label)

func _skill_call_deputy() -> void:
	if GameManager.deputy_ko:
		_log("Deputy is KO'd! Can't call for help.")
		return
	if randf() < 0.5:
		_enemy_hp -= 30
		_log("Deputy charges in! 30 damage to enemy!")
	else:
		_player_hp -= 15
		GameManager.stat_deputy_betrayals += 1
		GameManager.deputy_ko = true
		_log("Deputy tackles YOU by mistake! 15 damage.")

func _skill_bribe() -> void:
	if randf() < 0.5:
		_log("The bribe works! Battle ends early.")
		_end_battle(true)
	else:
		_player_hp -= 40
		_update_hp()
		_log("Bribe backfires! 40 damage.")
		_check_battle_end()

func _enemy_free_hit() -> void:
	var dmg = _get_enemy_dmg()
	_player_hp -= dmg
	_log("Enemy hits you for %d (free hit)." % dmg)

# ── Deputy interrupt ──────────────────────────────────────────────────────────

func _check_deputy_interrupt() -> void:
	if GameManager.deputy_ko or _deputy_redirected:
		return
	var roll = randf()
	if roll < 0.40:
		_enemy_hp -= 15
		_log("Deputy trips enemy! Bonus 15 damage.")
		_animate_deputy_pass()
	elif roll < 0.75:
		_log("Deputy runs across the room... does nothing.")
		_animate_deputy_pass()
	else:
		_player_hp -= 10
		GameManager.stat_deputy_betrayals += 1
		_log("Deputy tackles you by mistake! 10 damage.")
		_animate_deputy_pass()

func _animate_deputy_pass() -> void:
	deputy_sprite.position.x = -100
	deputy_sprite.visible = true
	deputy_sprite.play("walk")
	var tween = create_tween()
	tween.tween_property(deputy_sprite, "position:x", 1380, 1.5)
	await tween.finished
	deputy_sprite.visible = false
	deputy_sprite.stop()

# ── Enemy turn ────────────────────────────────────────────────────────────────

func _execute_enemy_turn() -> void:
	if not _battle_active:
		return

	if _skip_enemy_turn:
		_skip_enemy_turn = false
		_log("Enemy is intimidated — skips their turn!")
		_tick_debuffs()
		_player_turn = true
		return

	var moves: Array = _enemy.get("moves", [])
	if moves.is_empty():
		_player_turn = true
		return

	var move = moves[randi() % moves.size()]
	_execute_enemy_move(move)
	_update_hp()
	_tick_debuffs()
	_check_battle_end()
	if _battle_active:
		_player_turn = true

func _execute_enemy_move(move: String) -> void:
	match move:
		"rage", "throw_pan", "stage_dive", "crowd_surf", \
		"handshake", "pitch", "meltdown", "cancel", "lecture":
			var dmg = _get_enemy_dmg()
			_last_enemy_dmg = dmg
			_player_hp -= dmg
			_log("Enemy uses %s! %d damage." % [move.capitalize().replace("_", " "), dmg])
		"selfie_stun":
			_skip_enemy_turn = false
			_player_turn     = false
			_log("Selfie Stun! You're stunned — skip your next action.")
			await get_tree().create_timer(1.0).timeout
			_player_turn = true
			return
		"disrupt", "pivot":
			GameManager.player_skills.shuffle()
			_refresh_skill_bar()
			_log("Enemy disrupts you! Your skills are shuffled.")
		"spin":
			_selected_skill = randi() % GameManager.player_skills.size()
			_refresh_skill_bar()
			_log("Enemy Spins — your selection scrambled!")
		"cleanse":
			_enemy_hp = mini(_enemy_hp + 20, _enemy_max_hp)
			_log("Enemy Cleanses! Recovered 20 HP.")
		"entourage":
			_player_hp -= 10
			_log("Entourage pushes through! 10 damage.")
		_:
			var dmg = _get_enemy_dmg()
			_last_enemy_dmg = dmg
			_player_hp -= dmg
			_log("Enemy attacks! %d damage." % dmg)

func _get_enemy_dmg() -> int:
	var base = randi_range(15, 30)
	return int(base * _enemy_dmg_debuff)

func _tick_debuffs() -> void:
	if _debuff_turns > 0:
		_debuff_turns -= 1
		if _debuff_turns == 0:
			_enemy_dmg_debuff = 1.0
	_deputy_redirected = false

# ── Battle end ────────────────────────────────────────────────────────────────

func _check_battle_end() -> void:
	if _enemy_hp <= 0:
		_end_battle(true)
	elif _player_hp <= 0:
		_end_battle(false)

func _end_battle(player_won: bool) -> void:
	if not _battle_active:
		return
	_battle_active = false

	if player_won:
		# Keep remaining HP — skill, not luck
		GameManager.player_hp = maxi(_player_hp, 1)
	else:
		# Full restore on loss: bad guy forced in, you pay with dignity not HP
		GameManager.player_hp = 100

	if player_won:
		_log("You win!")
		await get_tree().create_timer(0.8).timeout
		if not _battle_active:
			_show_steal_prompt()
	else:
		_log("You're knocked down! The guest forces their way in.")
		await get_tree().create_timer(2.5).timeout
		_finish(false)

func _finish(player_won: bool) -> void:
	visible = false
	GameManager.set_phase(GameManager.GamePhase.DOOR)
	emit_signal("battle_ended", player_won, _enemy)

# ── Skill steal ───────────────────────────────────────────────────────────────

func _show_steal_prompt() -> void:
	var sig_key = _enemy.get("signature_skill", "")
	if sig_key.is_empty() or sig_key not in GameManager.skills_data:
		_finish(true)
		return

	var sig = GameManager.skills_data[sig_key]
	steal_prompt.get_node("StealTitle").text       = "Learn %s?" % sig.get("name", sig_key)
	steal_prompt.get_node("StealDescription").text = sig.get("description", "")
	steal_prompt.visible = true

	var slots_box = steal_prompt.get_node("SlotButtons")
	for i in range(slots_box.get_child_count()):
		var btn: Button = slots_box.get_child(i)
		if i < GameManager.player_skills.size():
			var sk_data = GameManager.skills_data.get(GameManager.player_skills[i], {})
			btn.text = sk_data.get("name", GameManager.player_skills[i])
			# Disconnect old connections before reconnecting
			if btn.pressed.is_connected(_on_steal_slot.bind(i, sig_key)):
				btn.pressed.disconnect(_on_steal_slot.bind(i, sig_key))
			btn.pressed.connect(_on_steal_slot.bind(i, sig_key), CONNECT_ONE_SHOT)
		else:
			btn.visible = false

func _on_steal_slot(slot: int, new_key: String) -> void:
	steal_prompt.visible = false
	GameManager.replace_skill(slot, new_key)
	_finish(true)

func _on_skip_steal() -> void:
	steal_prompt.visible = false
	_finish(true)

# ── UI helpers ────────────────────────────────────────────────────────────────

func _refresh_skill_bar() -> void:
	for i in range(skill_bar.get_child_count()):
		var btn: Button = skill_bar.get_child(i)
		if i >= GameManager.player_skills.size():
			btn.visible = false
			continue
		btn.visible = true
		var key  = GameManager.player_skills[i]
		var data = GameManager.skills_data.get(key, {})
		btn.text = data.get("name", key)
		if i == _selected_skill:
			btn.modulate = Color.YELLOW
		elif not data.get("is_base", true):
			btn.modulate = Color.CYAN
		else:
			btn.modulate = Color.WHITE

func _update_hp() -> void:
	_player_hp = maxi(_player_hp, 0)
	_enemy_hp  = maxi(_enemy_hp,  0)
	player_hp_bar.value = float(_player_hp) / float(PLAYER_MAX_HP) * 100.0
	enemy_hp_bar.value  = float(_enemy_hp)  / float(_enemy_max_hp) * 100.0
	player_hp_label.text = "HP: %d" % _player_hp
	enemy_hp_label.text  = "HP: %d" % _enemy_hp

func _log(msg: String) -> void:
	battle_log.text = msg
