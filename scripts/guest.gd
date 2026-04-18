extends Node2D

@onready var top_rect:       ColorRect = $Top
@onready var bottom_rect:    ColorRect = $Bottom
@onready var shoes_rect:     ColorRect = $Shoes
@onready var accessory_rect: ColorRect = $Accessory
@onready var name_label:     Label     = $NameLabel
@onready var tell_label:     Label     = $TellLabel

var _pending_data: Dictionary = {}

# Color palette for outfit parts (placeholder art)
const TOP_COLORS = {
	"formal_top":   Color(0.15, 0.15, 0.25),
	"casual_top":   Color(0.30, 0.25, 0.20),
	"edgy_top":     Color(0.20, 0.05, 0.05),
	"cultural_top": Color(0.55, 0.35, 0.10),
}
const BOTTOM_COLORS = {
	"formal_bottom": Color(0.10, 0.10, 0.20),
	"casual_bottom": Color(0.20, 0.30, 0.40),
	"edgy_bottom":   Color(0.15, 0.05, 0.05),
}
const SHOES_COLORS = {
	"formal_shoes": Color(0.08, 0.06, 0.04),
	"casual_shoes": Color(0.50, 0.50, 0.55),
	"edgy_shoes":   Color(0.10, 0.10, 0.10),
	"sloppy_shoes": Color(0.70, 0.60, 0.40),
}

func setup(guest: Dictionary) -> void:
	_pending_data = guest

func _ready() -> void:
	if not _pending_data.is_empty():
		if _pending_data.get("is_famous"):
			_setup_famous(_pending_data)
		else:
			_setup_regular(_pending_data)

func _setup_regular(data: Dictionary) -> void:
	name_label.visible = false
	tell_label.visible = false

	top_rect.color       = _tag_color(data["top"]["tags"],       TOP_COLORS,    Color(0.3, 0.3, 0.3))
	bottom_rect.color    = _tag_color(data["bottom"]["tags"],    BOTTOM_COLORS, Color(0.25, 0.25, 0.35))
	shoes_rect.color     = _tag_color(data["shoes"]["tags"],     SHOES_COLORS,  Color(0.2, 0.2, 0.2))

	if data["accessory"]["key"] != "none":
		accessory_rect.visible = true
		accessory_rect.color   = Color(0.9, 0.7, 0.1)
	else:
		accessory_rect.visible = false

	# Show outfit summary as tooltip-style label (dev aid, remove for final)
	name_label.text    = "%s / %s" % [data["top"]["display"], data["accessory"]["display"]]
	name_label.visible = true

func _setup_famous(data: Dictionary) -> void:
	# Famous guests show as a distinct solid color with name + mood tell
	top_rect.color       = Color(0.6, 0.5, 0.1)
	bottom_rect.color    = Color(0.5, 0.4, 0.08)
	shoes_rect.color     = Color(0.15, 0.12, 0.05)
	accessory_rect.visible = false

	name_label.text    = data.get("name", "???")
	name_label.visible = true

	tell_label.text    = data.get("mood_data", {}).get("tell", "")
	tell_label.visible = true

func _tag_color(tags: Array, palette: Dictionary, fallback: Color) -> Color:
	for tag in tags:
		if tag in palette:
			return palette[tag]
	return fallback
