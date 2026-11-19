## A squad member drawn the way the original composes soldiers: legs (L*), torso (AM*/AF*/EM*)
## and head (AFH/AMH strips) for 8 compass directions, frames cut from the original strips.
class_name Soldier
extends Node2D

const DIRS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
static var cache := {}              # strip name -> Array[Image frames]
const SCALE := 3.0                  # on-screen size: original pixels x3
static var remastered := false      # 4x AI strips from res://remastered/ANIMS only when F2 turns them on

var body := "AM"                    # AM male, AF female, EM enemy
var head := 0                       # 0..14 head variant
var dir := 4                        # index in DIRS
var walking := false
var anim_t := 0.0
var tex_cache := {}
var visible_body := true            # false: another pose (kneeling, lying) is drawn by a child

static func _path(name: String) -> String:
	var r := "res://remastered/ANIMS/%s_rgba.png" % name
	if remastered and ResourceLoader.exists(r):
		return r
	return "res://original/graphics/ANIMS/%s_rgba.png" % name

static func _div() -> float:
	return 4.0 if remastered and ResourceLoader.exists("res://remastered/ANIMS/LS_rgba.png") else 1.0

static func _frames(name: String) -> Array:
	var key := name + ("+" if remastered else "")
	if cache.has(key):
		return cache[key]
	var path := _path(name)
	if not ResourceLoader.exists(path):
		cache[key] = []
		return []
	var img: Image = load(path).get_image()
	var frames: Array = []
	var runs: Array = []
	var start := -1
	for x in range(img.get_width() + 1):
		var empty := true
		if x < img.get_width():
			for y in range(img.get_height()):
				if img.get_pixel(x, y).a > 0.5:
					empty = false
					break
		if not empty and start < 0:
			start = x
		elif empty and start >= 0:
			runs.append(Vector2i(start, x - start))
			start = -1
	# some neighbouring frames touch (no empty column between them): split runs that are much
	# wider than the typical frame into equal parts
	var widths: Array = runs.map(func(r): return r.y)
	widths.sort()
	var typical: float = widths[widths.size() / 2] if not widths.is_empty() else 1.0
	for r in runs:
		var n := maxi(1, roundi(r.y / typical))
		for i in range(n):
			var x0: int = r.x + r.y * i / n
			var x1: int = r.x + r.y * (i + 1) / n
			frames.append(img.get_region(Rect2i(x0, 0, x1 - x0, img.get_height())))
	cache[key] = frames
	return frames

## Leg frames split by tools/split_leg_frames.py: equal cells with the belt in the middle.
static func _legs(d: String) -> Array:
	var key := "cells/L" + d
	if cache.has(key):
		return cache[key]
	var path := "res://original/graphics/ANIMS/cells/L%s.png" % d
	var frames: Array = []
	if ResourceLoader.exists(path):
		var img: Image = load(path).get_image()
		var n: int = int(GameData._json("res://data/leg_frames.json")[d]["frames"])
		var w := img.get_width() / n
		for i in range(n):
			frames.append(img.get_region(Rect2i(i * w, 0, w, img.get_height())))
	cache[key] = frames
	return frames

## Lowest row of the torso's body (the hands hang lower at the sides): this row meets the belt.
static func _waist(tf: Image) -> int:
	var key := "waist%d" % tf.get_instance_id()
	if cache.has(key):
		return cache[key]
	var cx := tf.get_width() / 2
	var row := tf.get_height() - 1
	while row > 0:
		var solid := true
		for x in range(cx - 1, cx + 2):
			if tf.get_pixel(x, row).a < 0.5:
				solid = false
		if solid:
			break
		row -= 1
	cache[key] = row
	return row

static func _head(variant: int, body: String, row: int) -> Image:
	var key := "%sH%d/%d%s" % [body, variant, row, "+" if remastered else ""]
	if cache.has(key):
		return cache[key]
	var path := _path("%sH%d" % [body if body != "EM" else "EM", variant if body != "EM" else 0])
	if not ResourceLoader.exists(path):
		path = _path("AMH0")
	var img: Image = load(path).get_image()
	# 8 heads stacked in DIRS order, 8 px each; the strip starts one row into the first (63 px)
	var d := int(img.get_height() / 63)          # 1 original, 4 remastered
	var top := maxi(0, row * 8 - 1) * d
	var bottom := (row * 8 + 7) * d
	var r := img.get_region(Rect2i(0, top, img.get_width(), bottom - top))
	cache[key] = r
	return r

## The head drawn facing the camera (row 4 = S) - the battle screen's close-ups use this.
static func head_image(body: String, variant: int, dir_row := 4) -> Image:
	return _head(variant, body, dir_row)

func _tex(img: Image) -> Texture2D:
	var k := img.get_instance_id()
	if not tex_cache.has(k):
		var im := img
		if _div() > 1.0:
			im = img.duplicate()
			im.generate_mipmaps()           # remastered strips are drawn shrunk: filter them smoothly
		tex_cache[k] = ImageTexture.create_from_image(im)
	return tex_cache[k]

func set_heading(world_dir: Vector2) -> void:
	# world_dir: (east, south). Compass angle 0 = north, clockwise.
	if world_dir.length() < 0.001:
		return
	var ang := atan2(world_dir.x, -world_dir.y)
	dir = int(round(ang / (PI / 4.0))) % 8
	if dir < 0:
		dir += 8

func _process(delta: float) -> void:
	anim_t += delta * (8.0 if walking else 0.0)
	queue_redraw()

func _draw() -> void:
	if not visible_body:
		return
	var d: String = DIRS[dir]
	var legs := _legs(d)
	if legs.is_empty():
		legs = _frames("L" + d)
	var torso := _frames(body + d)
	if torso.is_empty():
		torso = _frames("AM" + d)       # the original has no AF strips for N, NE and NW
	if legs.is_empty() or torso.is_empty():
		draw_circle(Vector2.ZERO, 8, Color.OLIVE)
		return
	var lf: Image = legs[int(anim_t) % legs.size()] if walking else legs[0]
	var tf: Image = torso[0]
	var hf := _head(head, body, dir)
	var s := SCALE                    # screen pixels per original pixel
	var u := s / _div()               # screen pixels per texture pixel
	# a step lifts the body: two small bumps per walk cycle (the strips themselves have no bob)
	var bob := 0.0 if not walking else -1.2 * absf(sin(anim_t / legs.size() * TAU))
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if _div() > 1.0 else CanvasItem.TEXTURE_FILTER_NEAREST
	var y := 0.0
	var lw := lf.get_width() * u
	draw_texture_rect(_tex(lf), Rect2(-lw / 2, -lf.get_height() * u, lw, lf.get_height() * u), false)
	# the torso's body sits on the belt (its bottom body row over the legs' top row)
	var top := -lf.get_height() * u - _waist(tf) * u + bob * u
	var tw := tf.get_width() * u
	draw_texture_rect(_tex(tf), Rect2(-tw / 2, top, tw, tf.get_height() * u), false)
	y = top + 2 * s
	var hw := hf.get_width() * u
	draw_texture_rect(_tex(hf), Rect2(-hw / 2, y - hf.get_height() * u, hw, hf.get_height() * u), false)
