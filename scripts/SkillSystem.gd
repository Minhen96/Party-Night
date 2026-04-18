extends Node

func get_skill(key: String) -> Dictionary:
	return GameManager.skills_data.get(key, {})

func is_stolen(key: String) -> bool:
	return not get_skill(key).get("is_base", true)

func get_display_name(key: String) -> String:
	return get_skill(key).get("name", key)
