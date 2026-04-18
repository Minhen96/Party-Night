# Last Call — Implementation Guide

> Godot 4 · GDScript · 1-2 Developers · 4-Day Jam

---

## Table of Contents

1. [Project Setup](#1-project-setup)
2. [Folder Structure](#2-folder-structure)
3. [Input Map](#3-input-map)
4. [Autoload — GameManager.gd](#4-autoload--gamemanagergd)
5. [Data Files (JSON)](#5-data-files-json)
6. [main_game.tscn — Scene Layout](#6-main_gametscn--scene-layout)
7. [GuestSpawner.gd — Guest Queue & Decisions](#7-guestspawnergd--guest-queue--decisions)
8. [guest.tscn — Assembled Guest](#8-guesttscn--assembled-guest)
9. [VibeSystem.gd — Vibe Meter](#9-vibesystemgd--vibe-meter)
10. [battle_screen.tscn — Battle Layout](#10-battle_screentscn--battle-layout)
11. [BattleManager.gd — Turn Logic](#11-battlemanagergd--turn-logic)
12. [SkillSystem.gd — Skills & Stealing](#12-skillsystemgd--skills--stealing)
13. [DeputyAI.gd — Deputy State Machine](#13-deputyaigd--deputy-state-machine)
14. [deputy.tscn — Deputy Scene](#14-deputytscn--deputy-scene)
15. [Famous Guests](#15-famous-guests)
16. [score_screen.tscn — Score Screen](#16-score_screentscn--score-screen)
17. [Difficulty Scaling](#17-difficulty-scaling)
18. [Signal Map](#18-signal-map)
19. [Build Order Checklist](#19-build-order-checklist)

---

## 1. Project Setup

### project.godot changes needed

Remove the `[dotnet]` section entirely — we are using GDScript only.

Add the autoload and input map sections:

```ini
[application]

config/name="Party Night"
config/features=PackedStringArray("4.6", "GL Compatibility")
config/icon="res://icon.svg"
run/main_scene="res://scenes/main_game.tscn"

[autoload]

GameManager="*res://scripts/GameManager.gd"

[input]

decision_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":97,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194319,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
decision_right={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":100,"location":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194321,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
skill_confirm={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194309,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

> **Easier way:** In Godot Editor → Project → Project Settings → Input Map, add:
> - `decision_left` → A key + Left arrow
> - `decision_right` → D key + Right arrow
> - `skill_confirm` → Enter / Space

---

## 2. Folder Structure

Create these folders inside `res://`:

```
res://
├── scenes/
│   ├── main_game.tscn
│   ├── battle_screen.tscn
│   ├── score_screen.tscn
│   ├── guest.tscn
│   └── deputy.tscn
├── scripts/
│   ├── GameManager.gd
│   ├── GuestSpawner.gd
│   ├── BattleManager.gd
│   ├── DeputyAI.gd
│   ├── VibeSystem.gd
│   └── SkillSystem.gd
├── data/
│   ├── guests.json
│   ├── themes.json
│   ├── famous_guests.json
│   └── skills.json
└── assets/
    ├── sprites/
    │   ├── player/
    │   ├── deputy/
    │   ├── guests/
    │   │   ├── tops/
    │   │   ├── bottoms/
    │   │   ├── shoes/
    │   │   └── accessories/
    │   ├── famous_guests/
    │   ├── backgrounds/
    │   └── ui/
    └── audio/
        └── sfx/
```

---

## 3. Input Map

| Action | Key | Used In |
|---|---|---|
| `decision_left` | A / Left Arrow | Door — reject guest |
| `decision_right` | D / Right Arrow | Door — let guest in |
| `skill_confirm` | Enter / Space | Battle — confirm selected skill |

> In battle, `decision_left` / `decision_right` cycle through skill slots. `skill_confirm` executes the selected skill. Same 2-input philosophy as the door.

---

## 4. Autoload — GameManager.gd

`GameManager` is a singleton. Every other script reads and writes through it.

### Full script

```gdscript
# scripts/GameManager.gd
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────
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
var player_skills: Array = []        # Array of skill key strings, max 4

# ── Deputy ────────────────────────────────────────────────────────────────────
var deputy_state: DeputyState = DeputyState.IDLE
var deputy_ko: bool = false

# ── Stats (for score screen) ──────────────────────────────────────────────────
var stat_guests_processed: int = 0
var stat_wrong_calls: int = 0
var stat_famous_correct: int = 0
var stat_skills_stolen: Array = []
var stat_deputy_betrayals: int = 0
var stat_best_moment: String = ""

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
	themes_data       = _load_json("res://data/themes.json")
	guests_data       = _load_json("res://data/guests.json")
	famous_guests_data = _load_json("res://data/famous_guests.json")
	skills_data       = _load_json("res://data/skills.json")

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

# ── Vibe ──────────────────────────────────────────────────────────────────────

func change_vibe(amount: float) -> void:
	vibe = clamp(vibe + amount, 0.0, 100.0)
	emit_signal("vibe_changed", vibe)
	if vibe <= 0.0:
		end_run()

# ── Difficulty ────────────────────────────────────────────────────────────────

func _update_difficulty() -> void:
	var new_diff = 1.0 + (run_time / 120.0) * 2.0   # caps at 3x at 2 minutes
	if abs(new_diff - difficulty) > 0.05:
		difficulty = new_diff
		emit_signal("difficulty_changed", difficulty)

# ── Phase ─────────────────────────────────────────────────────────────────────

func set_phase(phase: GamePhase) -> void:
	current_phase = phase

# ── Run End ───────────────────────────────────────────────────────────────────

func end_run() -> void:
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
	stat_best_moment = ""
	current_phase = GamePhase.DOOR
	_pick_theme()
	_init_skills()
```

---

## 5. Data Files (JSON)

### data/guests.json

Parts are arrays of objects. Each part has a `key`, a `display_name`, and `tags`.

```json
{
  "tops": [
    { "key": "suit_jacket",  "display": "Suit Jacket",  "tags": ["formal_top"] },
    { "key": "hoodie",       "display": "Hoodie",        "tags": ["casual_top"] },
    { "key": "band_tee",     "display": "Band Tee",      "tags": ["edgy_top"] },
    { "key": "kebaya",       "display": "Kebaya",        "tags": ["cultural_top", "formal_top"] },
    { "key": "turtleneck",   "display": "Turtleneck",    "tags": ["casual_top", "formal_top"] },
    { "key": "crop_top",     "display": "Crop Top",      "tags": ["casual_top", "edgy_top"] },
    { "key": "flannel",      "display": "Flannel",       "tags": ["casual_top", "edgy_top"] }
  ],
  "bottoms": [
    { "key": "slacks",       "display": "Slacks",        "tags": ["formal_bottom"] },
    { "key": "ripped_jeans", "display": "Ripped Jeans",  "tags": ["edgy_bottom"] },
    { "key": "shorts",       "display": "Shorts",        "tags": ["casual_bottom"] },
    { "key": "skirt",        "display": "Skirt",         "tags": ["casual_bottom"] },
    { "key": "chinos",       "display": "Chinos",        "tags": ["casual_bottom", "formal_bottom"] },
    { "key": "leather_pants","display": "Leather Pants", "tags": ["edgy_bottom"] }
  ],
  "shoes": [
    { "key": "oxford",       "display": "Oxfords",       "tags": ["formal_shoes"] },
    { "key": "sneakers",     "display": "Sneakers",      "tags": ["casual_shoes"] },
    { "key": "flip_flops",   "display": "Flip Flops",    "tags": ["casual_shoes", "sloppy_shoes"] },
    { "key": "boots",        "display": "Boots",         "tags": ["edgy_shoes", "casual_shoes"] },
    { "key": "heels",        "display": "Heels",         "tags": ["formal_shoes"] },
    { "key": "loafers",      "display": "Loafers",       "tags": ["formal_shoes", "casual_shoes"] }
  ],
  "accessories": [
    { "key": "none",         "display": "",              "tags": [] },
    { "key": "sunglasses",   "display": "Sunglasses",    "tags": ["cool"] },
    { "key": "cap",          "display": "Cap",           "tags": ["casual_acc"] },
    { "key": "wristband",    "display": "Wristband",     "tags": ["wristband"] },
    { "key": "lanyard",      "display": "Lanyard",       "tags": ["lanyard"] },
    { "key": "vip_badge",    "display": "VIP Badge",     "tags": ["vip"] },
    { "key": "backpack",     "display": "Backpack",      "tags": ["suspicious"] }
  ]
}
```

### data/themes.json

`required` is an array of tags. A guest must match ALL of them to be allowed in. `forbidden` tags instantly mark a guest as bad.

```json
{
  "black_tie": {
    "name": "Black Tie Gala",
    "description": "Formal wear only tonight",
    "required": ["formal_top", "formal_bottom", "formal_shoes"],
    "forbidden": ["sloppy_shoes", "edgy_top", "edgy_bottom"]
  },
  "rave": {
    "name": "Underground Rave",
    "description": "Wristband holders only",
    "required": ["wristband"],
    "forbidden": []
  },
  "nineties": {
    "name": "90s Night",
    "description": "Retro vibes — no suits allowed",
    "required": ["casual_top"],
    "forbidden": ["formal_top", "formal_bottom", "formal_shoes"]
  },
  "industry": {
    "name": "Industry Mixer",
    "description": "Lanyard or VIP badge required",
    "required_any": ["lanyard", "vip"],
    "required": [],
    "forbidden": []
  },
  "culture": {
    "name": "Local Culture Night",
    "description": "Celebrate local fashion",
    "required_any": ["cultural_top"],
    "required": [],
    "forbidden": []
  }
}
```

> **Note:** `required_any` means the guest needs at least ONE tag from the list (used for Industry Mixer and Culture Night). The guest checking logic handles both `required` (all must match) and `required_any` (at least one must match).

### data/skills.json

```json
{
  "tackle": {
    "name": "Tackle",
    "description": "Reliable 20 damage. Always connects.",
    "damage": 20,
    "heal": 0,
    "effect": "none",
    "cost_action": false,
    "is_base": true
  },
  "intimidate": {
    "name": "Intimidate",
    "description": "Enemy skips their next attack.",
    "damage": 0,
    "heal": 0,
    "effect": "skip_enemy_turn",
    "cost_action": false,
    "is_base": true
  },
  "call_deputy": {
    "name": "Call Deputy",
    "description": "Deputy attacks — 30 dmg OR hits you for 15 (random).",
    "damage": 0,
    "heal": 0,
    "effect": "call_deputy",
    "cost_action": false,
    "is_base": true
  },
  "stall": {
    "name": "Stall",
    "description": "Recover 15 HP. Enemy gets a free hit.",
    "damage": 0,
    "heal": 15,
    "effect": "stall",
    "cost_action": false,
    "is_base": true
  },
  "critique": {
    "name": "Critique",
    "description": "Reduces enemy attack by 50% for 2 turns.",
    "damage": 0,
    "heal": 0,
    "effect": "debuff_enemy_damage",
    "effect_duration": 2,
    "cost_action": false,
    "is_base": false
  },
  "optimise": {
    "name": "Optimise",
    "description": "Copies enemy's last move and uses it against them.",
    "damage": 0,
    "heal": 0,
    "effect": "copy_enemy_move",
    "cost_action": false,
    "is_base": false
  },
  "go_viral": {
    "name": "Go Viral",
    "description": "Spawns a second enemy immediately.",
    "damage": 0,
    "heal": 0,
    "effect": "spawn_second_enemy",
    "cost_action": false,
    "is_base": false
  },
  "bribe": {
    "name": "Bribe",
    "description": "50% chance to end battle, 50% backfires for 40 dmg.",
    "damage": 0,
    "heal": 0,
    "effect": "bribe",
    "cost_action": false,
    "is_base": false
  },
  "scene": {
    "name": "Scene",
    "description": "Forces deputy to fight entourage instead of helping you.",
    "damage": 0,
    "heal": 0,
    "effect": "deputy_redirect",
    "cost_action": false,
    "is_base": false
  }
}
```

### data/famous_guests.json

```json
{
  "gordon_flame": {
    "name": "Gordon Flamé",
    "base_hp": 80,
    "moves": ["rage", "throw_pan"],
    "signature_skill": "critique",
    "moods": {
      "good":    { "tell": "Smiling, toque on straight",    "vibe_on_enter": 15, "triggers_fight": false },
      "neutral": { "tell": "Straight face, arms crossed",   "vibe_on_enter": 0,  "triggers_fight": false },
      "bad":     { "tell": "Frowning, toque askew",         "vibe_on_enter": 0,  "triggers_fight": true  }
    }
  },
  "elon_tusk": {
    "name": "Elon Tusk",
    "base_hp": 90,
    "moves": ["disrupt", "pivot"],
    "signature_skill": "optimise",
    "moods": {
      "good":    { "tell": "Confident stride, clean suit",  "vibe_on_enter": 10, "triggers_fight": false },
      "neutral": { "tell": "Distracted, looking at phone",  "vibe_on_enter": 0,  "triggers_fight": false },
      "bad":     { "tell": "Carrying whiteboard",           "vibe_on_enter": 0,  "triggers_fight": true  }
    }
  },
  "bella_scrolls": {
    "name": "Bella Scrolls",
    "base_hp": 70,
    "moves": ["selfie_stun", "cancel"],
    "signature_skill": "go_viral",
    "moods": {
      "good":    { "tell": "Phone away, smiling",           "vibe_on_enter": 20, "triggers_fight": false },
      "neutral": { "tell": "Glancing around",               "vibe_on_enter": 0,  "triggers_fight": false },
      "bad":     { "tell": "Ring light on, phone pointed",  "vibe_on_enter": 0,  "triggers_fight": true  }
    }
  },
  "senator_spinwell": {
    "name": "Senator Spinwell",
    "base_hp": 75,
    "moves": ["handshake", "spin"],
    "signature_skill": "bribe",
    "moods": {
      "good":    { "tell": "Waving, relaxed",               "vibe_on_enter": 5,  "triggers_fight": false },
      "neutral": { "tell": "Hand outstretched",             "vibe_on_enter": 0,  "triggers_fight": false },
      "bad":     { "tell": "Sweating, eyes darting",        "vibe_on_enter": 0,  "triggers_fight": true  }
    }
  },
  "rex_rager": {
    "name": "Rex Rager",
    "base_hp": 110,
    "moves": ["stage_dive", "crowd_surf"],
    "signature_skill": "scene",
    "moods": {
      "good":    { "tell": "Fist bump at door",             "vibe_on_enter": 25, "triggers_fight": false },
      "neutral": { "tell": "Quiet, hood up",                "vibe_on_enter": 0,  "triggers_fight": false },
      "bad":     { "tell": "Leather jacket ripped",         "vibe_on_enter": 0,  "triggers_fight": true  }
    }
  },
  "dr_wellness": {
    "name": "Dr. Wellness",
    "base_hp": 65,
    "moves": ["cleanse", "lecture"],
    "signature_skill": "critique",
    "moods": {
      "good":    { "tell": "Hands clasped, calm smile",     "vibe_on_enter": 8,  "triggers_fight": false },
      "neutral": { "tell": "Reading pamphlet",              "vibe_on_enter": 0,  "triggers_fight": false },
      "bad":     { "tell": "Preaching at queue",            "vibe_on_enter": 0,  "triggers_fight": true  }
    }
  },
  "the_founder": {
    "name": "The Founder",
    "base_hp": 70,
    "moves": ["pitch", "pivot"],
    "signature_skill": "optimise",
    "moods": {
      "good":    { "tell": "Nodding, casual",               "vibe_on_enter": 5,  "triggers_fight": false },
      "neutral": { "tell": "Checking watch",                "vibe_on_enter": 0,  "triggers_fight": false },
      "bad":     { "tell": "Carrying pitch deck",           "vibe_on_enter": 0,  "triggers_fight": true  }
    }
  },
  "madam_drama": {
    "name": "Madam Drama",
    "base_hp": 85,
    "moves": ["meltdown", "entourage"],
    "signature_skill": "scene",
    "moods": {
      "good":    { "tell": "Grand entrance, smiling",       "vibe_on_enter": 10, "triggers_fight": false },
      "neutral": { "tell": "Sunglasses on, blank face",     "vibe_on_enter": 0,  "triggers_fight": false },
      "bad":     { "tell": "Entourage visible behind her",  "vibe_on_enter": 0,  "triggers_fight": true  }
    }
  }
}
```

---

## 6. main_game.tscn — Scene Layout

### Node tree

```
Node2D  [MainGame]                       ← main_game.gd
│
├── CanvasLayer  [VenueLayer]
│   ├── ColorRect  [VenueBG]             ← placeholder dark bg, top 70%
│   ├── Node2D  [CrowdContainer]         ← crowd sprites spawned here
│   ├── Node2D  [ActiveBadGuys]          ← bad guys draining vibe
│   ├── ProgressBar  [VibeMeter]         ← top-right, 0–100
│   ├── Label  [VibeLabel]               ← "VIBE: 85%"
│   └── Label  [ThemeReveal]             ← shows theme name for 3s at start
│
├── CanvasLayer  [EntranceLayer]
│   ├── ColorRect  [EntranceBG]          ← slightly lighter, bottom 30%
│   ├── Node2D  [GuestQueue]             ← GuestSpawner.gd attached here
│   │   ├── Node2D  [QueueSlot0]
│   │   ├── Node2D  [QueueSlot1]
│   │   └── Node2D  [QueueSlot2]
│   ├── Node2D  [CurrentGuestSpot]       ← spotlight area, centre
│   ├── AnimatedSprite2D  [Deputy]       ← DeputyAI.gd attached
│   ├── Label  [RejectHint]              ← "← REJECT"
│   ├── Label  [LetInHint]              ← "LET IN →"
│   └── Label  [ThemeIcon]              ← small reminder of tonight's theme
│
├── CanvasLayer  [UILayer]
│   ├── Label  [Timer]
│   └── Label  [Score]
│
└── CanvasLayer  [BattleLayer]           ← battle_screen.tscn instanced here, hidden by default
```

### main_game.gd

```gdscript
# scenes/main_game.gd
extends Node2D

@onready var theme_reveal: Label = $VenueLayer/ThemeReveal
@onready var vibe_meter: ProgressBar = $VenueLayer/VibeMeter
@onready var timer_label: Label = $UILayer/Timer
@onready var battle_layer: CanvasLayer = $BattleLayer

func _ready() -> void:
	GameManager.vibe_changed.connect(_on_vibe_changed)
	GameManager.run_ended.connect(_on_run_ended)
	GameManager.theme_changed.connect(_on_theme_changed)
	vibe_meter.value = GameManager.vibe
	_show_theme_briefly()

func _process(delta: float) -> void:
	timer_label.text = _format_time(GameManager.run_time)

func _show_theme_briefly() -> void:
	var theme = GameManager.get_theme()
	theme_reveal.text = theme.get("name", "")
	theme_reveal.visible = true
	await get_tree().create_timer(3.0).timeout
	theme_reveal.visible = false

func _on_vibe_changed(new_vibe: float) -> void:
	vibe_meter.value = new_vibe

func _on_run_ended() -> void:
	get_tree().change_scene_to_file("res://scenes/score_screen.tscn")

func _on_theme_changed(theme_key: String) -> void:
	_show_theme_briefly()

func _format_time(seconds: float) -> String:
	var m = int(seconds) / 60
	var s = int(seconds) % 60
	return "%02d:%02d" % [m, s]
```

---

## 7. GuestSpawner.gd — Guest Queue & Decisions

This script lives on the `GuestQueue` node.

```gdscript
# scripts/GuestSpawner.gd
extends Node2D

signal bad_guest_entered(guest_data: Dictionary)
signal good_guest_entered(guest_data: Dictionary)
signal wrong_reject(guest_data: Dictionary)

const FAMOUS_CHANCE_BASE = 0.15

var current_guest: Dictionary = {}
var queue: Array = []            # up to 3 pending guests
var waiting_for_decision: bool = false
var spawn_timer: Timer

func _ready() -> void:
	spawn_timer = Timer.new()
	add_child(spawn_timer)
	spawn_timer.timeout.connect(_on_spawn_timer)
	_reset_spawn_timer()
	_spawn_next_guest()

func _reset_spawn_timer() -> void:
	spawn_timer.wait_time = max(1.0, 3.0 / GameManager.difficulty)
	spawn_timer.start()

func _on_spawn_timer() -> void:
	if queue.size() < 3:
		queue.append(build_guest())
	_reset_spawn_timer()
	_try_present_guest()

func _try_present_guest() -> void:
	if waiting_for_decision or queue.is_empty():
		return
	current_guest = queue.pop_front()
	waiting_for_decision = true
	_display_guest(current_guest)

func _spawn_next_guest() -> void:
	waiting_for_decision = false
	_try_present_guest()

# ── Building a guest ─────────────────────────────────────────────────────────

func build_guest() -> Dictionary:
	var famous_chance = FAMOUS_CHANCE_BASE + (GameManager.run_time / 300.0) * 0.15
	if randf() < famous_chance:
		return build_famous_guest()
	return build_regular_guest()

func build_regular_guest() -> Dictionary:
	var gd = GameManager.guests_data
	var top   = _pick_random(gd["tops"])
	var bot   = _pick_random(gd["bottoms"])
	var shoes = _pick_random(gd["shoes"])
	var acc   = _pick_random(gd["accessories"])

	var all_tags: Array = []
	all_tags.append_array(top["tags"])
	all_tags.append_array(bot["tags"])
	all_tags.append_array(shoes["tags"])
	all_tags.append_array(acc["tags"])

	return {
		"is_famous": false,
		"top": top,
		"bottom": bot,
		"shoes": shoes,
		"accessory": acc,
		"tags": all_tags,
		"should_enter": check_against_theme(all_tags)
	}

func build_famous_guest() -> Dictionary:
	var keys = GameManager.famous_guests_data.keys()
	var key = keys[randi() % keys.size()]
	var data = GameManager.famous_guests_data[key].duplicate(true)
	var moods = data["moods"].keys()
	var mood = moods[randi() % moods.size()]
	data["mood"] = mood
	data["mood_data"] = data["moods"][mood]
	data["is_famous"] = true
	data["key"] = key
	data["should_enter"] = not data["mood_data"]["triggers_fight"]
	return data

func _pick_random(arr: Array) -> Dictionary:
	return arr[randi() % arr.size()]

# ── Theme check ───────────────────────────────────────────────────────────────

func check_against_theme(guest_tags: Array) -> bool:
	var theme = GameManager.get_theme()

	# All required tags must be present
	for tag in theme.get("required", []):
		if tag not in guest_tags:
			return false

	# At least one required_any tag must be present (if the list is non-empty)
	var required_any: Array = theme.get("required_any", [])
	if not required_any.is_empty():
		var found = false
		for tag in required_any:
			if tag in guest_tags:
				found = true
				break
		if not found:
			return false

	# No forbidden tags allowed
	for tag in theme.get("forbidden", []):
		if tag in guest_tags:
			return false

	return true

# ── Decision input ────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not waiting_for_decision:
		return
	if GameManager.current_phase != GameManager.GamePhase.DOOR:
		return

	if event.is_action_pressed("decision_left"):
		_handle_decision("reject")
	elif event.is_action_pressed("decision_right"):
		_handle_decision("let_in")

func _handle_decision(direction: String) -> void:
	GameManager.stat_guests_processed += 1
	var guest = current_guest
	var should_enter = guest["should_enter"]
	waiting_for_decision = false

	if direction == "let_in":
		if should_enter:
			emit_signal("good_guest_entered", guest)
			GameManager.change_vibe(0)    # vibe change handled by VibeSystem on enter
		else:
			GameManager.stat_wrong_calls += 1
			emit_signal("bad_guest_entered", guest)
			return    # do NOT call _spawn_next_guest — BattleManager will call it after fight
	elif direction == "reject":
		if should_enter:
			GameManager.stat_wrong_calls += 1
			GameManager.change_vibe(-5.0)
			emit_signal("wrong_reject", guest)
		else:
			GameManager.change_vibe(2.0)   # small reward for correct reject

	_spawn_next_guest()

# ── Display ───────────────────────────────────────────────────────────────────

func _display_guest(guest: Dictionary) -> void:
	# TODO: Update CurrentGuestSpot node with guest visuals
	# For now: print to confirm logic works
	if guest.get("is_famous"):
		print("Famous guest: ", guest["name"], " | Mood: ", guest["mood"], " | Tell: ", guest["mood_data"]["tell"])
	else:
		print("Regular guest | Top: ", guest["top"]["display"], " | Tags: ", guest["tags"])
```

---

## 8. guest.tscn — Assembled Guest

### Node tree

```
Node2D  [Guest]
├── Sprite2D  [Body]
├── Sprite2D  [Top]
├── Sprite2D  [Bottom]
├── Sprite2D  [Shoes]
├── Sprite2D  [Accessory]
└── Label  [NameLabel]     ← only visible for famous guests
```

### guest.gd

```gdscript
# scenes/guest.gd
extends Node2D

@onready var top_sprite: Sprite2D = $Top
@onready var bottom_sprite: Sprite2D = $Bottom
@onready var shoes_sprite: Sprite2D = $Shoes
@onready var accessory_sprite: Sprite2D = $Accessory
@onready var name_label: Label = $NameLabel

func setup(guest_data: Dictionary) -> void:
	if guest_data.get("is_famous"):
		_setup_famous(guest_data)
	else:
		_setup_regular(guest_data)

func _setup_regular(data: Dictionary) -> void:
	name_label.visible = false
	_load_part_sprite(top_sprite, "tops", data["top"]["key"])
	_load_part_sprite(bottom_sprite, "bottoms", data["bottom"]["key"])
	_load_part_sprite(shoes_sprite, "shoes", data["shoes"]["key"])
	if data["accessory"]["key"] != "none":
		_load_part_sprite(accessory_sprite, "accessories", data["accessory"]["key"])
	else:
		accessory_sprite.visible = false

func _setup_famous(data: Dictionary) -> void:
	name_label.visible = true
	name_label.text = data["name"]
	# Famous guests use a single portrait sprite, not assembled parts
	var mood = data["mood"]
	var path = "res://assets/sprites/famous_guests/%s_%s.png" % [data["key"], mood]
	if ResourceLoader.exists(path):
		top_sprite.texture = load(path)
	bottom_sprite.visible = false
	shoes_sprite.visible = false
	accessory_sprite.visible = false

func _load_part_sprite(sprite: Sprite2D, category: String, key: String) -> void:
	var path = "res://assets/sprites/guests/%s/%s.png" % [category, key]
	if ResourceLoader.exists(path):
		sprite.texture = load(path)
	else:
		sprite.texture = null    # placeholder — shows nothing until art is ready
```

---

## 9. VibeSystem.gd — Vibe Meter

Attach to a node in the venue layer that persists across scenes (or keep it as part of main_game).

```gdscript
# scripts/VibeSystem.gd
extends Node

# Passive drain rates (per second)
const DRAIN_BAD_GUEST    = 5.0 / 3.0    # -5 per 3 sec
const DRAIN_FAMOUS_BAD   = 3.0 / 3.0    # -3 per 3 sec
const RESTORE_GOOD_GUEST = 2.0 / 5.0    # +2 per 5 sec

var active_bad_guests: Array = []        # list of guest data dicts inside venue
var active_good_guests: Array = []       # good guests passively restoring

func _process(delta: float) -> void:
	if GameManager.current_phase != GameManager.GamePhase.DOOR:
		return
	var net = 0.0
	net -= active_bad_guests.size() * DRAIN_BAD_GUEST * delta
	net += active_good_guests.size() * RESTORE_GOOD_GUEST * delta
	if net != 0.0:
		GameManager.change_vibe(net)

func add_bad_guest(guest: Dictionary) -> void:
	active_bad_guests.append(guest)

func remove_bad_guest(guest: Dictionary) -> void:
	active_bad_guests.erase(guest)

func add_good_guest(guest: Dictionary) -> void:
	active_good_guests.append(guest)

# Famous guest enters with good mood — immediate vibe boost
func famous_good_enter(guest: Dictionary) -> void:
	var boost = guest["mood_data"].get("vibe_on_enter", 0)
	GameManager.change_vibe(boost)
	add_good_guest(guest)

# Vibe events (called from BattleManager or other systems)
func on_fight_win()  -> void: GameManager.change_vibe(5.0)
func on_fight_lose() -> void: GameManager.change_vibe(-10.0)
func on_correct_famous_reject() -> void: GameManager.change_vibe(3.0)
func on_wrong_famous_reject()   -> void: GameManager.change_vibe(-5.0)
func on_deputy_wrong_entry()    -> void: GameManager.change_vibe(-8.0)
```

---

## 10. battle_screen.tscn — Battle Layout

```
CanvasLayer  [BattleScreen]
├── ColorRect  [BlurOverlay]              ← semi-transparent dark overlay, covers main game
├── ColorRect  [BattleBG]                 ← battle arena background
│
├── TextureRect  [PlayerPortrait]
├── TextureRect  [EnemyPortrait]
├── ProgressBar  [PlayerHP]
├── ProgressBar  [EnemyHP]
├── Label  [PlayerHPLabel]
├── Label  [EnemyHPLabel]
│
├── AnimatedSprite2D  [PlayerSprite]
├── AnimatedSprite2D  [EnemySprite]
├── AnimatedSprite2D  [DeputyInterrupt]   ← hidden until deputy fires
│
├── HBoxContainer  [SkillBar]
│   ├── Button  [Skill1]
│   ├── Button  [Skill2]
│   ├── Button  [Skill3]
│   └── Button  [Skill4]
│
├── Label  [BattleLog]                    ← scrolling battle text
│
└── VBoxContainer  [StealPrompt]          ← hidden, shown after win
    ├── Label  [StealTitle]
    ├── Label  [StealDescription]
    ├── HBoxContainer  [SlotButtons]
    │   ├── Button  [Slot0]
    │   ├── Button  [Slot1]
    │   ├── Button  [Slot2]
    │   └── Button  [Slot3]
    └── Button  [SkipButton]
```

---

## 11. BattleManager.gd — Turn Logic

Attach to the `BattleScreen` CanvasLayer node.

```gdscript
# scripts/BattleManager.gd
extends CanvasLayer

signal battle_ended(player_won: bool)

@onready var player_hp_bar: ProgressBar        = $PlayerHP
@onready var enemy_hp_bar: ProgressBar         = $EnemyHP
@onready var player_hp_label: Label            = $PlayerHPLabel
@onready var enemy_hp_label: Label             = $EnemyHPLabel
@onready var skill_bar: HBoxContainer          = $SkillBar
@onready var battle_log: Label                 = $BattleLog
@onready var steal_prompt: VBoxContainer       = $StealPrompt
@onready var deputy_sprite: AnimatedSprite2D   = $DeputyInterrupt
@onready var player_sprite: AnimatedSprite2D   = $PlayerSprite
@onready var enemy_sprite: AnimatedSprite2D    = $EnemySprite

const PLAYER_MAX_HP = 100

var player_hp: int = PLAYER_MAX_HP
var enemy_hp: int = 0
var enemy_max_hp: int = 0
var current_enemy: Dictionary = {}
var selected_skill_index: int = 0
var player_turn: bool = true
var battle_active: bool = false
var enemy_skip_next_turn: bool = false
var enemy_damage_debuff: float = 1.0
var debuff_turns_left: int = 0
var last_enemy_damage: int = 0

func _ready() -> void:
	visible = false
	steal_prompt.visible = false

func start_battle(enemy: Dictionary) -> void:
	current_enemy = enemy
	player_hp = GameManager.player_hp
	enemy_max_hp = enemy.get("base_hp", 80)
	enemy_hp = enemy_max_hp
	enemy_skip_next_turn = false
	enemy_damage_debuff = 1.0
	debuff_turns_left = 0
	battle_active = true
	selected_skill_index = 0
	GameManager.set_phase(GameManager.GamePhase.BATTLE)
	GameManager.deputy_ko = false
	visible = true
	_refresh_skill_bar()
	_update_hp_display()
	_log("Battle start! %s vs you!" % enemy.get("name", "Guest"))

func _input(event: InputEvent) -> void:
	if not battle_active or not player_turn:
		return
	if event.is_action_pressed("decision_left"):
		selected_skill_index = (selected_skill_index - 1) % GameManager.player_skills.size()
		_refresh_skill_bar()
	elif event.is_action_pressed("decision_right"):
		selected_skill_index = (selected_skill_index + 1) % GameManager.player_skills.size()
		_refresh_skill_bar()
	elif event.is_action_pressed("skill_confirm"):
		_execute_player_turn(selected_skill_index)

# ── Player Turn ───────────────────────────────────────────────────────────────

func _execute_player_turn(skill_index: int) -> void:
	player_turn = false
	var skill_key = GameManager.player_skills[skill_index]
	var skill = GameManager.skills_data.get(skill_key, {})
	_apply_skill(skill, skill_key)
	await get_tree().create_timer(0.5).timeout
	_check_deputy_interrupt()
	await get_tree().create_timer(0.4).timeout
	_check_battle_end()
	if battle_active:
		await get_tree().create_timer(0.3).timeout
		_execute_enemy_turn()

func _apply_skill(skill: Dictionary, key: String) -> void:
	var effect = skill.get("effect", "none")
	match effect:
		"none":
			var dmg = skill.get("damage", 0)
			enemy_hp -= dmg
			_log("You use %s! %d damage." % [skill.get("name", key), dmg])
		"skip_enemy_turn":
			enemy_skip_next_turn = true
			_log("You Intimidate! Enemy will skip next turn.")
		"call_deputy":
			_call_deputy_skill()
		"stall":
			var heal = skill.get("heal", 0)
			player_hp = min(player_hp + heal, PLAYER_MAX_HP)
			_log("You Stall! Recovered %d HP. Enemy gets a free hit." % heal)
			_enemy_free_hit()
		"debuff_enemy_damage":
			enemy_damage_debuff = 0.5
			debuff_turns_left = skill.get("effect_duration", 2)
			_log("You use Critique! Enemy damage halved for %d turns." % debuff_turns_left)
		"copy_enemy_move":
			enemy_hp -= last_enemy_damage
			_log("You Optimise! Copy enemy's last move for %d damage." % last_enemy_damage)
		"bribe":
			_apply_bribe()
		_:
			_log("Used %s." % skill.get("name", key))
	_update_hp_display()

func _call_deputy_skill() -> void:
	if GameManager.deputy_ko:
		_log("Deputy is down! Can't call for help.")
		return
	if randf() < 0.5:
		enemy_hp -= 30
		_log("Deputy charges in! 30 damage to enemy!")
	else:
		player_hp -= 15
		GameManager.stat_deputy_betrayals += 1
		_log("Deputy tackles YOU by mistake! 15 damage to yourself.")
		GameManager.deputy_ko = true

func _apply_bribe() -> void:
	if randf() < 0.5:
		_log("The bribe works! Battle ends.")
		_end_battle(true)
	else:
		player_hp -= 40
		_log("The bribe backfires! 40 damage to you!")
		_update_hp_display()

func _enemy_free_hit() -> void:
	var dmg = _get_enemy_damage()
	player_hp -= dmg
	_log("Enemy hits you for %d (free hit)." % dmg)
	_update_hp_display()

# ── Deputy Interrupt (passive, mid-turn) ─────────────────────────────────────

func _check_deputy_interrupt() -> void:
	if GameManager.deputy_ko:
		return
	var roll = randf()
	if roll < 0.40:
		enemy_hp -= 15
		_log("Deputy trips enemy! +15 bonus damage.")
		GameManager.stat_deputy_betrayals   # not a betrayal, no increment
	elif roll < 0.75:
		_log("Deputy runs across the room and does nothing.")
	else:
		player_hp -= 10
		GameManager.stat_deputy_betrayals += 1
		_log("Deputy tackles you by mistake! 10 damage.")
	_update_hp_display()

# ── Enemy Turn ────────────────────────────────────────────────────────────────

func _execute_enemy_turn() -> void:
	if not battle_active:
		return
	if enemy_skip_next_turn:
		enemy_skip_next_turn = false
		_log("Enemy is intimidated — skips their turn!")
		_tick_debuffs()
		player_turn = true
		return

	var moves: Array = current_enemy.get("moves", [])
	if moves.is_empty():
		player_turn = true
		return

	var move_key = moves[randi() % moves.size()]
	var dmg = _get_enemy_damage()
	last_enemy_damage = dmg

	match move_key:
		"rage", "throw_pan", "disrupt", "handshake", "stage_dive", "crowd_surf", \
		"selfie_stun", "cancel", "cleanse", "lecture", "pitch", "meltdown":
			player_hp -= dmg
			_log("Enemy uses %s! %d damage to you." % [move_key.capitalize(), dmg])
		"spin":
			# confuse: randomise skill order
			GameManager.player_skills.shuffle()
			_log("Enemy uses Spin! Your skills are shuffled.")
			_refresh_skill_bar()
		"pivot":
			_log("Enemy Pivots — switches move next turn (no damage).")
		_:
			player_hp -= dmg
			_log("Enemy attacks! %d damage." % dmg)

	_update_hp_display()
	_tick_debuffs()
	_check_battle_end()
	if battle_active:
		player_turn = true

func _get_enemy_damage() -> int:
	var base_dmg = randi_range(15, 30)
	return int(base_dmg * enemy_damage_debuff)

func _tick_debuffs() -> void:
	if debuff_turns_left > 0:
		debuff_turns_left -= 1
		if debuff_turns_left == 0:
			enemy_damage_debuff = 1.0

# ── Battle End ────────────────────────────────────────────────────────────────

func _check_battle_end() -> void:
	if enemy_hp <= 0:
		_end_battle(true)
	elif player_hp <= 0:
		_end_battle(false)

func _end_battle(player_won: bool) -> void:
	battle_active = false
	GameManager.player_hp = player_hp
	if player_won:
		_log("You win!")
		GameManager.change_vibe(5.0)
		await get_tree().create_timer(0.8).timeout
		_show_steal_prompt()
	else:
		_log("You're knocked down! Deputy holds the door for 5 seconds.")
		GameManager.change_vibe(-10.0)
		await get_tree().create_timer(5.0).timeout
		_finish_battle(false)

func _finish_battle(player_won: bool) -> void:
	visible = false
	GameManager.set_phase(GameManager.GamePhase.DOOR)
	emit_signal("battle_ended", player_won)

# ── Skill Steal ───────────────────────────────────────────────────────────────

func _show_steal_prompt() -> void:
	var sig_key = current_enemy.get("signature_skill", "")
	if sig_key.is_empty() or sig_key not in GameManager.skills_data:
		_finish_battle(true)
		return
	var sig_skill = GameManager.skills_data[sig_key]
	steal_prompt.visible = true
	$StealPrompt/StealTitle.text = "Learn %s?" % sig_skill.get("name", sig_key)
	$StealPrompt/StealDescription.text = sig_skill.get("description", "")
	_refresh_slot_buttons(sig_key)

func _refresh_slot_buttons(new_skill_key: String) -> void:
	var slots = $StealPrompt/SlotButtons
	for i in range(slots.get_child_count()):
		var btn: Button = slots.get_child(i)
		var sk = GameManager.player_skills[i]
		var skill_data = GameManager.skills_data.get(sk, {})
		btn.text = skill_data.get("name", sk)
		btn.pressed.connect(func(): _on_steal_slot(i, new_skill_key), CONNECT_ONE_SHOT)

func _on_steal_slot(slot_index: int, new_skill_key: String) -> void:
	GameManager.replace_skill(slot_index, new_skill_key)
	GameManager.stat_skills_stolen.append(new_skill_key)
	steal_prompt.visible = false
	_finish_battle(true)

# ── UI Helpers ────────────────────────────────────────────────────────────────

func _refresh_skill_bar() -> void:
	for i in range(skill_bar.get_child_count()):
		var btn: Button = skill_bar.get_child(i)
		if i >= GameManager.player_skills.size():
			btn.visible = false
			continue
		var sk = GameManager.player_skills[i]
		var skill_data = GameManager.skills_data.get(sk, {})
		btn.text = skill_data.get("name", sk)
		btn.modulate = Color.WHITE if skill_data.get("is_base", true) else Color.CYAN
		btn.modulate = Color.YELLOW if i == selected_skill_index else btn.modulate

func _update_hp_display() -> void:
	player_hp = max(player_hp, 0)
	enemy_hp  = max(enemy_hp, 0)
	player_hp_bar.value = float(player_hp) / float(PLAYER_MAX_HP) * 100.0
	enemy_hp_bar.value  = float(enemy_hp)  / float(enemy_max_hp)  * 100.0
	player_hp_label.text = "HP: %d" % player_hp
	enemy_hp_label.text  = "HP: %d" % enemy_hp

func _log(msg: String) -> void:
	battle_log.text = msg
	print(msg)
```

---

## 12. SkillSystem.gd — Skills & Stealing

SkillSystem is kept minimal — most skill logic lives inside BattleManager since it needs access to HP, enemy state, and UI. SkillSystem only handles the data layer.

```gdscript
# scripts/SkillSystem.gd
extends Node

func get_skill(key: String) -> Dictionary:
	return GameManager.skills_data.get(key, {})

func is_stolen(key: String) -> bool:
	var skill = get_skill(key)
	return not skill.get("is_base", true)

func get_skill_display_name(key: String) -> String:
	return get_skill(key).get("name", key)
```

---

## 13. DeputyAI.gd — Deputy State Machine

Attach to the `Deputy` AnimatedSprite2D in the entrance layer.

```gdscript
# scripts/DeputyAI.gd
extends AnimatedSprite2D

var state: int = GameManager.DeputyState.IDLE
var state_timer: Timer
var advice_bubble: Label          # assign in editor or find in _ready

var INTERFERE_MIN = 15.0
var INTERFERE_MAX = 30.0
var WANDER_MIN    = 10.0
var WANDER_MAX    = 20.0

func _ready() -> void:
	state_timer = Timer.new()
	state_timer.one_shot = true
	add_child(state_timer)
	state_timer.timeout.connect(_on_timer)
	GameManager.difficulty_changed.connect(_on_difficulty_changed)
	_enter_idle()

func _on_difficulty_changed(diff: float) -> void:
	# Scale how often deputy interferes with difficulty
	INTERFERE_MIN = max(5.0, 15.0 / diff)
	INTERFERE_MAX = max(10.0, 30.0 / diff)

# ── State Machine ─────────────────────────────────────────────────────────────

func _enter_idle() -> void:
	state = GameManager.DeputyState.IDLE
	play("idle")
	var next_action = randf()
	if next_action < 0.5:
		state_timer.wait_time = randf_range(INTERFERE_MIN, INTERFERE_MAX)
	else:
		state_timer.wait_time = randf_range(WANDER_MIN, WANDER_MAX)
	state_timer.start()

func _on_timer() -> void:
	match state:
		GameManager.DeputyState.IDLE:
			if randf() < 0.5:
				_enter_interfere_door()
			else:
				_enter_wander()
		_:
			_enter_idle()

func _enter_interfere_door() -> void:
	if GameManager.current_phase == GameManager.GamePhase.BATTLE:
		_enter_idle()
		return
	state = GameManager.DeputyState.INTERFERE_DOOR
	play("walk")
	var roll = randf()
	if roll < 0.5:
		_give_wrong_advice()
	else:
		_block_view()
	await get_tree().create_timer(2.0).timeout
	_enter_idle()

func _give_wrong_advice() -> void:
	# Always wrong — opposite of correct
	var msg = "Let them in!" if randf() < 0.5 else "Reject them!"
	_show_bubble(msg)
	print("Deputy says (wrong): ", msg)

func _block_view() -> void:
	_show_bubble("...")
	# TODO: move deputy sprite over guest — cover tell
	print("Deputy blocks view!")

func _enter_wander() -> void:
	state = GameManager.DeputyState.WANDER
	play("walk")
	state_timer.wait_time = randf_range(1.5, 3.0)
	state_timer.start()

func enter_fight_assist() -> void:
	state = GameManager.DeputyState.FIGHT_ASSIST
	play("walk")

func _show_bubble(text: String) -> void:
	if advice_bubble:
		advice_bubble.text = text
		advice_bubble.visible = true
		await get_tree().create_timer(2.0).timeout
		advice_bubble.visible = false
```

---

## 14. deputy.tscn — Deputy Scene

```
AnimatedSprite2D  [Deputy]           ← DeputyAI.gd attached
└── Label  [AdviceBubble]            ← speech bubble above deputy
```

### Animation frames needed (in SpriteFrames resource):
| Animation name | Frames | Description |
|---|---|---|
| `idle` | 2-4 frames | Standing, slight sway |
| `walk` | 4-6 frames | Walking left/right |
| `attack` | 3-4 frames | Jumping/lunging |
| `ko` | 1 frame | Fallen down |

---

## 15. Famous Guests

Famous guests use the same battle flow as regular bad guests. The differences are:

1. They always visually pass the theme check
2. Their mood determines `should_enter` — bad mood = fight
3. Their mood tell is a subtle visual on the guest sprite
4. They have unique movesets and a signature skill to steal

### Wiring famous guests into BattleManager

When `bad_guest_entered` fires with a famous guest dict, BattleManager reads:
- `base_hp` for enemy HP
- `moves` for moveset
- `signature_skill` for steal prompt

No extra code needed — the existing battle loop handles it.

### Famous guest mood logic in GuestSpawner

```gdscript
func build_famous_guest() -> Dictionary:
	# ... (already shown above in section 7)
	# mood "bad" → should_enter = false → triggers fight if let in
	# mood "good"/"neutral" → should_enter = true → enters without fight
	# EXCEPT: if player rejects a "good" famous guest → -5 vibe (wrong reject)
```

---

## 16. score_screen.tscn — Score Screen

```
Node2D  [ScoreScreen]
├── Label  [Title]               ← "NIGHT OVER"
├── Label  [NightLasted]         ← "Night lasted: 1:42"
├── Label  [GuestsProcessed]
├── Label  [WrongCalls]
├── Label  [FamousCorrect]
├── Label  [StolenSkills]
├── Label  [DeputyBetrayals]
├── Label  [FinalVibe]
├── Label  [BestMoment]          ← auto-generated funny text
└── Button [PlayAgain]
```

### score_screen.gd

```gdscript
# scenes/score_screen.gd
extends Node2D

func _ready() -> void:
	$NightLasted.text      = "Night lasted: " + _fmt(GameManager.run_time)
	$GuestsProcessed.text  = "Guests processed: %d" % GameManager.stat_guests_processed
	$WrongCalls.text       = "Wrong calls: %d" % GameManager.stat_wrong_calls
	$FamousCorrect.text    = "Famous guests correctly read: %d" % GameManager.stat_famous_correct
	$StolenSkills.text     = "Skills stolen: " + ", ".join(GameManager.stat_skills_stolen)
	$DeputyBetrayals.text  = "Deputy betrayals: %d" % GameManager.stat_deputy_betrayals
	$FinalVibe.text        = "Final vibe: %.0f%%" % GameManager.vibe
	$BestMoment.text       = _generate_best_moment()
	$PlayAgain.pressed.connect(_on_play_again)

func _on_play_again() -> void:
	GameManager.reset_run()
	get_tree().change_scene_to_file("res://scenes/main_game.tscn")

func _fmt(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]

func _generate_best_moment() -> String:
	if GameManager.stat_deputy_betrayals >= 5:
		return "Your deputy hit you %d times. Consider firing them." % GameManager.stat_deputy_betrayals
	if GameManager.stat_skills_stolen.size() >= 3:
		return "You became the famous guest."
	if GameManager.stat_wrong_calls == 0:
		return "Perfect reads. The deputy tried their best to ruin it."
	if GameManager.run_time < 30.0:
		return "That was quick. The deputy sends their condolences."
	return "Another night, another disaster."
```

---

## 17. Difficulty Scaling

All difficulty changes flow through `GameManager.difficulty`. Systems that use it:

| System | How difficulty is applied |
|---|---|
| `GuestSpawner` | `spawn_timer.wait_time = max(1.0, 3.0 / difficulty)` |
| `GuestSpawner` | Famous guest chance increases over time |
| `DeputyAI` | Interfere interval shrinks with difficulty |
| `BattleManager` | Enemy HP scales: `base_hp * (1 + difficulty * 0.2)` |

### Difficulty ramp (from GameManager)

```
Time 0s    → difficulty = 1.0   (baseline)
Time 60s   → difficulty = 2.0   (queue faster, deputy wilder)
Time 120s  → difficulty = 3.0   (near-constant queue)
Time 120s+ → capped at 3.0
```

---

## 18. Signal Map

How the systems talk to each other:

```
GuestSpawner
  ├── bad_guest_entered(guest)    → BattleManager.start_battle(guest)
  ├── good_guest_entered(guest)   → VibeSystem.add_good_guest(guest)
  └── wrong_reject(guest)         → GameManager.change_vibe(-5)

BattleManager
  └── battle_ended(won)           → GuestSpawner._spawn_next_guest()
                                  → VibeSystem.on_fight_win/lose()

GameManager
  ├── vibe_changed(vibe)          → main_game._on_vibe_changed()
  ├── run_ended                   → main_game._on_run_ended()
  ├── theme_changed(key)          → main_game._show_theme_briefly()
  └── difficulty_changed(diff)    → DeputyAI._on_difficulty_changed()
```

> Connect signals in `_ready()` of the receiving node, not the emitter. This keeps coupling one-directional.

---

## 19. Build Order Checklist

### Day 1 AM — Skeleton
- [ ] Remove `[dotnet]` from project.godot
- [ ] Add autoload: `GameManager="*res://scripts/GameManager.gd"`
- [ ] Set `run/main_scene` to `res://scenes/main_game.tscn`
- [ ] Create all folders (`scenes/`, `scripts/`, `data/`, `assets/`)
- [ ] Write `GameManager.gd`
- [ ] Write all 4 JSON data files
- [ ] Build `main_game.tscn` node tree (ColorRect placeholders for zones)
- [ ] Write `main_game.gd` (theme reveal, vibe meter wiring)
- [ ] **Test:** Game opens, shows theme name for 3s, vibe bar at 100%

### Day 1 PM — Guest Loop
- [ ] Build `guest.tscn` (Sprite2D parts + NameLabel)
- [ ] Write `guest.gd`
- [ ] Write `GuestSpawner.gd`
- [ ] Attach `GuestSpawner.gd` to `GuestQueue` node
- [ ] Wire `bad_guest_entered` → placeholder print
- [ ] Wire `good_guest_entered` → placeholder print
- [ ] **Test:** Guests appear, A/D input fires, wrong guests flagged in console

### Day 2 AM — Vibe System
- [ ] Write `VibeSystem.gd`, add as Autoload or child of MainGame
- [ ] Wire `good_guest_entered` → `VibeSystem.add_good_guest()`
- [ ] Wire passive drain loop in `_process`
- [ ] Connect `GameManager.run_ended` → scene change to score screen
- [ ] Write `score_screen.tscn` + `score_screen.gd` (minimal)
- [ ] **Test:** Vibe drains over time, run ends at 0%, score screen shows

### Day 2 PM — Battle System
- [ ] Build `battle_screen.tscn` node tree
- [ ] Write `BattleManager.gd`, attach to `BattleScreen`
- [ ] Wire `bad_guest_entered` → `BattleManager.start_battle()`
- [ ] Wire `battle_ended` → `GuestSpawner._spawn_next_guest()`
- [ ] Write `SkillSystem.gd`
- [ ] **Test:** Bad guest enters → battle opens → skills cycle → win/lose → return to door

### Day 3 AM — Deputy
- [ ] Build `deputy.tscn` (AnimatedSprite2D + AdviceBubble Label)
- [ ] Write `DeputyAI.gd`, attach to Deputy node
- [ ] Wire `difficulty_changed` → `DeputyAI._on_difficulty_changed()`
- [ ] Wire battle start → `deputy.enter_fight_assist()`
- [ ] **Test:** Deputy wanders, gives wrong advice, interferes in battle

### Day 3 PM — Famous Guests
- [ ] Confirm `build_famous_guest()` in GuestSpawner works
- [ ] Wire famous guest mood → vibe changes on enter
- [ ] Add famous guest movesets to BattleManager's `_execute_enemy_turn()`
- [ ] Add mood tells to `guest.gd` `_setup_famous()`
- [ ] Track `stat_famous_correct` when player correctly reads mood
- [ ] **Test:** Famous guest appears, mood tell visible, fight triggers on bad mood

### Day 4 AM — Skill Steal + Score + Difficulty
- [ ] Complete `_show_steal_prompt()` in BattleManager
- [ ] Wire slot buttons to `GameManager.replace_skill()`
- [ ] Complete `score_screen.gd` with all stats
- [ ] Confirm `GameManager._update_difficulty()` runs and feeds all systems
- [ ] **Test:** Full loop: door → fight → steal → back to door → vibe dies → score screen

### Day 4 PM — Polish
- [ ] Record SFX (see GDD section 11.2), export as `.ogg`
- [ ] Wire audio: `AudioStreamPlayer` nodes in MainGame + BattleScreen
- [ ] Drop placeholder art into `assets/sprites/` and update `_load_part_sprite()`
- [ ] Web export: Project → Export → Add Web preset → Export PCK
- [ ] **Test:** Web build runs in browser, full loop playable
