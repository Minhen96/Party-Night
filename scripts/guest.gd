extends Node2D

@onready var head_sprite:      Sprite2D = $Head
@onready var top_sprite:       Sprite2D = $Top
@onready var bottom_sprite:    Sprite2D = $Bottom
@onready var lleg_sprite:      Sprite2D = $LLeg
@onready var rleg_sprite:      Sprite2D = $RLeg
@onready var shoes_sprite:     Sprite2D = $Shoes
@onready var accessory_sprite: Sprite2D = $Accessory
@onready var name_label:     Label     = $NameLabel
@onready var tell_label:     Label     = $TellLabel

var _pending_data: Dictionary = {}

func setup(data: Dictionary) -> void:
	_pending_data = data

func hide_ui() -> void:
	if name_label:
		name_label.visible = false
	if tell_label:
		tell_label.visible = false

func _ready() -> void:
	if not _pending_data.is_empty():
		if _pending_data.get("is_famous"):
			_setup_famous(_pending_data)
		else:
			_setup_regular(_pending_data)

func _load_sprite(sprite: Sprite2D, folder: String, key: String) -> void:
	var path = "res://assets/sprites/%s/%s.png" % [folder, key]
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	else:
		push_warning("Missing sprite: " + path)
		sprite.texture = null

func _setup_regular(data: Dictionary) -> void:
	name_label.visible = false
	tell_label.visible = false

	# We check if data has head, else provide a default
	_load_sprite(head_sprite, "guests/heads", data.get("head", {}).get("key", "default_head"))
	_load_sprite(top_sprite, "guests/tops", data["top"]["key"])
	_load_sprite(bottom_sprite, "guests/bottoms", data["bottom"]["key"])
	_load_sprite(lleg_sprite, "guests/bottoms", data["bottom"]["key"] + "_lleg")
	_load_sprite(rleg_sprite, "guests/bottoms", data["bottom"]["key"] + "_rleg")
	_load_sprite(shoes_sprite, "guests/shoes", data["shoes"]["key"])

	if data["accessory"]["key"] != "none":
		accessory_sprite.visible = true
		_load_sprite(accessory_sprite, "guests/accessories", data["accessory"]["key"])
	else:
		accessory_sprite.visible = false

	# Dev aid: show outfit summary
	name_label.text    = "%s  %s" % [data["top"]["display"], data["accessory"]["display"]]
	name_label.visible = true

func _setup_famous(data: Dictionary) -> void:
	# Hide regular body parts to show full portrait
	head_sprite.visible = false
	bottom_sprite.visible = false
	lleg_sprite.visible = false
	rleg_sprite.visible = false
	shoes_sprite.visible = false
	accessory_sprite.visible = false

	var mood_suffix = "_good"
	if data.get("mood_data", {}).get("tell", "") != "":
		# Usually good/bad based on some vibe info, but letting it be simple for now
		mood_suffix = ""

	var key = data.get("key", "famous")
	_load_sprite(top_sprite, "famous_guests", key + mood_suffix)

	name_label.text    = data.get("name", "???")
	name_label.visible = true
	name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))

	tell_label.text    = "[ " + data.get("mood_data", {}).get("tell", "") + " ]"
	tell_label.visible = true
