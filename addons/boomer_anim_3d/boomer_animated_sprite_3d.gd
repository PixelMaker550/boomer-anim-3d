@tool
@icon("res://addons/boomer_anim_3d/icon.svg")
class_name BoomerAnimatedSprite3D
extends AnimatedSprite3D

## A 2.5D 8-directional and omnidirectional [AnimatedSprite3D] node for 1990s-style boomer shooters.
##
## Automatically switches between 8 directional [SpriteFrames] resources (or 5 directions with
## automatic horizontal mirroring) based on the active [Camera3D] angle relative to
## [member orientation_node], while preserving playback frame and progress across angle changes.
## Omnidirectional animations (such as death or explosion effects) can be placed in the
## [constant Direction.OMNI] slot and automatically take priority over directional views.

## Viewing directions relative to [member orientation_node], plus [constant OMNI] for 1-direction animations.
enum Direction {
	FRONT = 0,
	FRONT_RIGHT = 1,
	RIGHT = 2,
	BACK_RIGHT = 3,
	BACK = 4,
	BACK_LEFT = 5,
	LEFT = 6,
	FRONT_LEFT = 7,
	OMNI = 8,
}

## Optional reference [Node3D] whose forward (-Z) and right (+X) axes define the character's facing.
## If left unassigned, defaults to the parent node at runtime if it is a [Node3D], or self otherwise.
@export var orientation_node: Node3D = null

## Optional animation name to start playing automatically when entering the scene at runtime.
@export var initial_animation: StringName = &""

## If enabled, empty left-side sectors (5: Back Left, 6: Left, 7: Front Left) automatically mirror
## their corresponding right-side sectors (3, 2, 1) using [member SpriteBase3D.flip_h], DOOM-style.
@export var mirror_left_if_empty: bool = true

## Sprite texel density in pixels per meter. Automatically updates [member SpriteBase3D.pixel_size].
@export_range(1.0, 512.0, 1.0, "or_greater") var pixels_per_meter: float = 32.0:
	set(value):
		pixels_per_meter = maxf(value, 1.0)
		pixel_size = 1.0 / pixels_per_meter

## Animation names listed here disable lighting ([member GeometryInstance3D.shaded] = false)
## so muzzle flashes, glowing attacks, or eyes remain fullbright in dark areas.
@export var fullbright_animations: Array[StringName] = []

## Stored [SpriteFrames] resources for the 8 directional sectors (indices 0..7).
@export_storage var frames_by_direction: Array[SpriteFrames] = []

## Stored [SpriteFrames] resource for 1-direction omnidirectional animations (e.g. death, hurt, props).
@export_storage var omni_frames: SpriteFrames = null

## Currently selected direction slot in the Inspector direction grid.
@export_storage var editor_direction: int = Direction.FRONT

var _current_anim: StringName = &""
var _current_speed: float = 1.0
var _current_from_end: bool = false
var _current_sector: int = Direction.FRONT
var _using_omni: bool = false
var _base_shaded: bool = true


class _ResolvedFrames:
	var frames: SpriteFrames = null
	var flip: bool = false
	var is_omni: bool = false

	func _init(p_frames: SpriteFrames = null, p_flip: bool = false, p_is_omni: bool = false) -> void:
		frames = p_frames
		flip = p_flip
		is_omni = p_is_omni


func _init() -> void:
	_ensure_direction_array()


func _enter_tree() -> void:
	_ensure_direction_array()
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	pixel_size = 1.0 / maxf(pixels_per_meter, 1.0)

	if Engine.is_editor_hint() and sprite_frames == null:
		var stored: SpriteFrames = _get_frames_slot(editor_direction)
		if is_instance_valid(stored):
			sprite_frames = stored


func _ready() -> void:
	_ensure_direction_array()
	if Engine.is_editor_hint():
		return

	_base_shaded = shaded
	if orientation_node == null:
		var parent_node: Node = get_parent()
		if parent_node is Node3D:
			orientation_node = parent_node as Node3D

	if initial_animation != &"":
		play_anim(initial_animation)
	elif animation != &"":
		_current_anim = animation
		_apply_fullbright(_current_anim)
		_update_directional_frames(false)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_directional_frames(false)


## Plays either a directional or omnidirectional animation by name, applying fullbright settings
## and resolving the best matching [SpriteFrames] slot for the current camera angle.
func play_anim(anim_name: StringName, custom_speed: float = 1.0, from_end: bool = false) -> void:
	_current_anim = anim_name
	_current_speed = custom_speed
	_current_from_end = from_end
	_apply_fullbright(anim_name)

	if Engine.is_editor_hint():
		return

	_update_directional_frames(true)


## Returns the [SpriteFrames] resource assigned to [param dir] (0..7 or [constant Direction.OMNI]),
## creating and storing a new [SpriteFrames] instance if that slot is currently empty.
func get_or_create_frames(dir: int) -> SpriteFrames:
	_ensure_direction_array()
	if dir == Direction.OMNI:
		if not is_instance_valid(omni_frames):
			omni_frames = SpriteFrames.new()
		return omni_frames

	if dir < 0 or dir >= 8:
		return null

	if not is_instance_valid(frames_by_direction[dir]):
		frames_by_direction[dir] = SpriteFrames.new()
	return frames_by_direction[dir]


## Returns [code]true[/code] if the [SpriteFrames] resource in [param dir] exists and contains
## at least one animation with more than zero frames.
func has_configured_frames(dir: int) -> bool:
	_ensure_direction_array()
	var sf: SpriteFrames = _get_frames_slot(dir)
	return _frames_has_any_frame(sf)


## Copies animation names, FPS speeds, and loop flags from [param source_dir] (0..7) to the
## remaining 7 directional slots without modifying [member omni_frames] or erasing existing frames.
func sync_animation_names_from(source_dir: int) -> void:
	_ensure_direction_array()
	if source_dir < 0 or source_dir >= 8:
		return

	var source_frames: SpriteFrames = frames_by_direction[source_dir]
	if not is_instance_valid(source_frames):
		return

	var anim_names: PackedStringArray = source_frames.get_animation_names()
	for target_dir: int in range(8):
		if target_dir == source_dir:
			continue

		var target_frames: SpriteFrames = get_or_create_frames(target_dir)
		if not is_instance_valid(target_frames):
			continue

		for anim_str: String in anim_names:
			var anim_name: StringName = StringName(anim_str)
			if not target_frames.has_animation(anim_name):
				target_frames.add_animation(anim_name)
			target_frames.set_animation_speed(anim_name, source_frames.get_animation_speed(anim_name))
			target_frames.set_animation_loop(anim_name, source_frames.get_animation_loop(anim_name))


## Returns the currently active [enum Direction] index ([constant Direction.OMNI] when using
## omnidirectional frames, or the resolved 0..7 viewing sector).
func get_current_direction() -> int:
	if _using_omni:
		return Direction.OMNI
	return _current_sector


func _ensure_direction_array() -> void:
	if frames_by_direction.size() != 8:
		frames_by_direction.resize(8)


func _get_frames_slot(dir: int) -> SpriteFrames:
	if dir == Direction.OMNI:
		return omni_frames
	if dir >= 0 and dir < frames_by_direction.size():
		return frames_by_direction[dir]
	return null


func _apply_fullbright(anim_name: StringName) -> void:
	if anim_name != &"" and anim_name in fullbright_animations:
		shaded = false
	else:
		shaded = _base_shaded


func _compute_view_sector() -> int:
	var viewport: Viewport = get_viewport()
	if not is_instance_valid(viewport):
		return -1

	var camera: Camera3D = viewport.get_camera_3d()
	if not is_instance_valid(camera):
		return -1

	var ref_node: Node3D = orientation_node if is_instance_valid(orientation_node) else self
	var ref_basis: Basis = ref_node.global_basis

	var forward: Vector3 = -ref_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	var right: Vector3 = ref_basis.x
	right.y = 0.0
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()

	var to_camera: Vector3 = camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.000001:
		return _current_sector

	var angle: float = atan2(to_camera.dot(right), to_camera.dot(forward))
	return posmod(int(round(angle / (PI / 4.0))), 8)


func _has_animation_with_frames(sf: SpriteFrames, anim_name: StringName) -> bool:
	if not is_instance_valid(sf):
		return false
	if anim_name == &"":
		return false
	if not sf.has_animation(anim_name):
		return false
	return sf.get_frame_count(anim_name) > 0


func _frames_has_any_frame(sf: SpriteFrames) -> bool:
	if not is_instance_valid(sf):
		return false
	var anim_names: PackedStringArray = sf.get_animation_names()
	for anim_str: String in anim_names:
		var anim_name: StringName = StringName(anim_str)
		if sf.get_frame_count(anim_name) > 0:
			return true
	return false


func _has_usable_frames(sf: SpriteFrames, anim_name: StringName) -> bool:
	if anim_name != &"":
		return _has_animation_with_frames(sf, anim_name)
	return _frames_has_any_frame(sf)


func _resolve_frames(sector: int, anim_name: StringName) -> _ResolvedFrames:
	# 1. Omni takes priority if the active animation exists and has frames in omni_frames.
	if _has_animation_with_frames(omni_frames, anim_name):
		return _ResolvedFrames.new(omni_frames, false, true)

	# 2. Exact sector in the 8-direction array.
	if sector >= 0 and sector < 8:
		var direct_sf: SpriteFrames = frames_by_direction[sector]
		if _has_usable_frames(direct_sf, anim_name):
			return _ResolvedFrames.new(direct_sf, false, false)

		# 3. Auto-mirror left sectors (5, 6, 7) from right sectors (3, 2, 1) if empty.
		if mirror_left_if_empty and (sector == Direction.BACK_LEFT or sector == Direction.LEFT or sector == Direction.FRONT_LEFT):
			var opposite_sector: int = 8 - sector
			var mirror_sf: SpriteFrames = frames_by_direction[opposite_sector]
			if _has_usable_frames(mirror_sf, anim_name):
				return _ResolvedFrames.new(mirror_sf, true, false)

	# 4. Fallback chain: FRONT -> omni_frames.
	var front_sf: SpriteFrames = frames_by_direction[Direction.FRONT]
	if _has_usable_frames(front_sf, anim_name):
		return _ResolvedFrames.new(front_sf, false, false)

	if _frames_has_any_frame(omni_frames):
		return _ResolvedFrames.new(omni_frames, false, true)

	# Return existing non-null slot even if empty so callers have a reference if needed.
	if sector >= 0 and sector < 8 and is_instance_valid(frames_by_direction[sector]):
		return _ResolvedFrames.new(frames_by_direction[sector], false, false)
	if is_instance_valid(front_sf):
		return _ResolvedFrames.new(front_sf, false, false)
	if is_instance_valid(omni_frames):
		return _ResolvedFrames.new(omni_frames, false, true)

	return _ResolvedFrames.new(null, false, false)


func _update_directional_frames(force_play: bool) -> void:
	var sector: int = _compute_view_sector()
	if sector < 0:
		if not force_play:
			return
		sector = _current_sector

	var active_anim: StringName = _current_anim if _current_anim != &"" else animation
	var resolved: _ResolvedFrames = _resolve_frames(sector, active_anim)

	_current_sector = sector
	_using_omni = resolved.is_omni

	if not is_instance_valid(resolved.frames):
		return

	var frames_changed: bool = sprite_frames != resolved.frames
	var flip_changed: bool = flip_h != resolved.flip

	if not frames_changed and not flip_changed and not force_play:
		return

	var was_playing: bool = is_playing()
	var saved_frame: int = frame
	var saved_progress: float = frame_progress
	var prev_anim: StringName = animation

	flip_h = resolved.flip
	if frames_changed:
		sprite_frames = resolved.frames

	var target_anim: StringName = active_anim if active_anim != &"" else prev_anim
	if target_anim == &"" or not sprite_frames.has_animation(target_anim):
		return

	var frame_count: int = sprite_frames.get_frame_count(target_anim)
	if frame_count <= 0:
		return

	var clamped_frame: int = mini(saved_frame, frame_count - 1)

	if force_play:
		if frames_changed and prev_anim == target_anim and was_playing:
			play(target_anim, _current_speed, _current_from_end)
			set_frame_and_progress(clamped_frame, saved_progress)
		else:
			play(target_anim, _current_speed, _current_from_end)
	elif frames_changed:
		if was_playing:
			play(target_anim, _current_speed, _current_from_end)
			set_frame_and_progress(clamped_frame, saved_progress)
		else:
			animation = target_anim
			set_frame_and_progress(clamped_frame, saved_progress)
