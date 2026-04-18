extends Node2D

@onready var night_lasted:    Label  = $NightLasted
@onready var guests_label:    Label  = $GuestsProcessed
@onready var wrong_label:     Label  = $WrongCalls
@onready var famous_label:    Label  = $FamousCorrect
@onready var stolen_label:    Label  = $StolenSkills
@onready var betrayal_label:  Label  = $DeputyBetrayals
@onready var vibe_label:      Label  = $FinalVibe
@onready var moment_label:    Label  = $BestMoment
@onready var play_again_btn:  Button = $PlayAgain

func _ready() -> void:
	night_lasted.text   = "Night lasted: "   + _fmt(GameManager.run_time)
	guests_label.text   = "Guests processed: %d"   % GameManager.stat_guests_processed
	wrong_label.text    = "Wrong calls: %d"         % GameManager.stat_wrong_calls
	famous_label.text   = "Famous guests correctly read: %d" % GameManager.stat_famous_correct
	betrayal_label.text = "Deputy betrayals: %d"    % GameManager.stat_deputy_betrayals
	vibe_label.text     = "Final vibe: %.0f%%"      % GameManager.vibe

	if GameManager.stat_skills_stolen.is_empty():
		stolen_label.text = "Skills stolen: none"
	else:
		var names: Array = []
		for key in GameManager.stat_skills_stolen:
			var sk = GameManager.skills_data.get(key, {})
			names.append(sk.get("name", key))
		stolen_label.text = "Skills stolen: " + ", ".join(names)

	moment_label.text = _best_moment()
	play_again_btn.pressed.connect(_on_play_again)

func _on_play_again() -> void:
	GameManager.reset_run()
	get_tree().change_scene_to_file("res://scenes/main_game.tscn")

func _fmt(s: float) -> String:
	return "%02d:%02d" % [int(s) / 60, int(s) % 60]

func _best_moment() -> String:
	var betrayals = GameManager.stat_deputy_betrayals
	var stolen    = GameManager.stat_skills_stolen.size()
	var wrong     = GameManager.stat_wrong_calls
	var time      = GameManager.run_time
	var famous    = GameManager.stat_famous_correct

	if betrayals >= 5:
		return "Your deputy hit you %d times.\nConsider firing them." % betrayals
	if stolen >= 3:
		return "You stole %d skills.\nYou became the famous guest." % stolen
	if wrong == 0 and time > 60.0:
		return "Zero wrong calls.\nThe deputy tried their best to ruin it."
	if time < 30.0:
		return "That was quick.\nThe deputy sends their condolences."
	if famous >= 3:
		return "You read %d famous guests correctly.\nA true professional." % famous
	if betrayals == 0:
		return "The deputy behaved perfectly.\nSomething must be wrong."
	return "Another night, another disaster.\nSee you tomorrow."
