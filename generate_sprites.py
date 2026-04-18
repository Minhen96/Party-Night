import json
import os
import hashlib
from PIL import Image, ImageDraw

def string_to_color(s):
    h = hashlib.md5(s.encode('utf-8')).hexdigest()
    r = (int(h[0:2], 16) % 150) + 70
    g = (int(h[2:4], 16) % 150) + 70
    b = (int(h[4:6], 16) % 150) + 70
    return (r, g, b, 255)

def create_sprite(path, size, base_color, shape="rect", key_string=""):
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w, h = size
    
    color = string_to_color(key_string) if key_string else base_color

    if shape == "rect":
        d.rectangle([0, 0, w-1, h-1], fill=color, outline=(0, 0, 0, 255))
    elif shape == "circle":
        d.ellipse([0, 0, w-1, h-1], fill=color, outline=(0, 0, 0, 255))
    elif shape == "top":
        d.polygon([(0, 10), (10, 0), (w-10, 0), (w-1, 10), (w-1, h-1), (0, h-1)], fill=color, outline=(0, 0, 0, 255))
    elif shape == "shoe":
        d.rectangle([0, h//2, w-1, h-1], fill=color, outline=(0, 0, 0, 255))
    elif shape == "chain":
        d.line([(0, 0), (w//2, h-1), (w-1, 0)], fill=color, width=3)
        
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)

create_sprite("assets/sprites/guests/heads/default_head.png", (26, 24), (200, 160, 120, 255), "circle")

with open('data/guests.json', 'r') as f:
    guests = json.load(f)

for top in guests['tops']:
    create_sprite(f"assets/sprites/guests/tops/{top['key']}.png", (42, 40), None, "top", top['key'])

for bottom in guests['bottoms']:
    create_sprite(f"assets/sprites/guests/bottoms/{bottom['key']}.png", (34, 36), None, "rect", bottom['key'])
    create_sprite(f"assets/sprites/guests/bottoms/{bottom['key']}_lleg.png", (12, 34), None, "rect", bottom['key'])
    create_sprite(f"assets/sprites/guests/bottoms/{bottom['key']}_rleg.png", (12, 34), None, "rect", bottom['key'])

for shoe in guests['shoes']:
    create_sprite(f"assets/sprites/guests/shoes/{shoe['key']}.png", (34, 12), None, "shoe", shoe['key'])

for acc in guests['accessories']:
    if acc['key'] != "none":
        create_sprite(f"assets/sprites/guests/accessories/{acc['key']}.png", (18, 12), None, "chain", acc['key'])

with open('data/famous_guests.json', 'r') as f:
    famous = json.load(f)

def create_humanoid(path, size, color):
    img = Image.new('RGBA', size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w, h = size
    # Head
    head_r = w // 5
    head_cx = w // 2
    head_cy = head_r + 4
    d.ellipse([head_cx - head_r, head_cy - head_r, head_cx + head_r, head_cy + head_r], fill=color, outline=(0,0,0,255), width=1)
    # Torso
    torso_top = head_cy + head_r
    torso_bot = int(h * 0.62)
    torso_l = w // 2 - int(w * 0.28)
    torso_r = w // 2 + int(w * 0.28)
    d.rectangle([torso_l, torso_top, torso_r, torso_bot], fill=color, outline=(0,0,0,255), width=1)
    # Legs
    leg_w = int(w * 0.17)
    # Left leg
    d.rectangle([w//2 - leg_w - 2, torso_bot, w//2 - 2, h - 1], fill=color, outline=(0,0,0,255), width=1)
    # Right leg
    d.rectangle([w//2 + 2, torso_bot, w//2 + leg_w + 2, h - 1], fill=color, outline=(0,0,0,255), width=1)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)

# Deputy (48x64)
create_sprite("assets/sprites/deputy/idle_0.png", (48, 64), (100, 100, 220, 255), "rect", "deputy_idle")
create_sprite("assets/sprites/deputy/walk_0.png", (48, 64), (120, 120, 240, 255), "rect", "deputy_walk0")
create_sprite("assets/sprites/deputy/walk_1.png", (48, 64), (120, 120, 240, 255), "rect", "deputy_walk1")

# Player battle portrait (64x128) — humanoid
import hashlib as _hs
create_humanoid("assets/sprites/player/player_battle.png", (64, 128), (80, 200, 100, 255))

# Famous guest portraits (64x128) — humanoid with unique colors
with open('data/famous_guests.json', 'r') as f:
    famous = json.load(f)

for key, val in famous.items():
    h = _hs.md5(key.encode()).hexdigest()
    r = (int(h[0:2], 16) % 130) + 80
    g = (int(h[2:4], 16) % 130) + 80
    b = (int(h[4:6], 16) % 130) + 80
    create_humanoid(f"assets/sprites/famous_guests/{key}.png", (64, 128), (r, g, b, 255))
    # "good" mood version is slightly brighter
    create_humanoid(f"assets/sprites/famous_guests/{key}_good.png", (64, 128), (min(r+40,255), min(g+40,255), min(b+40,255), 255))

print("Randomly colored JSON and actor sprites generated!")
