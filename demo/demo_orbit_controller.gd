extends Node3D

## Quick test orbit controller for demonstrating a [BoomerAnimatedSprite3D] in a 3D scene.
##
## Attach this script to any [Node3D], assign [member target_sprite] and [member orbit_camera],
## then orbit 360 degrees using A/D, Left/Right arrows, or mouse drag, and switch animations
## with keys 1, 2, and 3.

const DIRECTION_NAMES: Array[String] = [
	"FRONT (0)",
	"FRONT_RIGHT (1)",
	"RIGHT (2)",
	"BACK_RIGHT (3)",
	"BACK (4)",
	"BACK_LEFT (5)",
	"LEFT (6)",
	"FRONT_LEFT (7)",
	"OMNI (8)",
]

## The [BoomerAnimatedSprite3D] node to orbit around and animate.
@export var target_sprite: BoomerAnimatedSprite3D = null

## The [Camera3D] that orbits around [member target_sprite].
@export var orbit_camera: Camera3D = null

## Distance from [member target_sprite] to [member orbit_camera] on the XZ plane.
@export_range(0.5, 50.0, 0.1) var orbit_radius: float = 4.0

## Vertical offset of [member orbit_camera] relative to [member target_sprite].
@export var orbit_height: float = 1.0

## Keyboard angular orbit speed in radians per second.
@export var orbit_speed: float = 1.8

## Mouse horizontal drag sensitivity in radians per pixel.
@export var mouse_sensitivity: float = 0.008

## Animation names mapped to number keys 1, 2, 3...
@export var test_animations: Array[StringName] = [&"walk", &"attack", &"death"]

## Optional UI [Label] to display live angle, direction sector, and active animation.
@export var debug_label: Label = null

var _orbit_angle: float = 0.0
var _is_dragging: bool = false
var _last_printed_state: String = ""


func _ready() -> void:
	if is_instance_valid(target_sprite) and not test_animations.is_empty():
		target_sprite.play_anim(test_animations[0])
	_update_camera_transform()
	_update_debug_output()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_btn: InputEventMouseButton = event as InputEventMouseButton
		if mouse_btn.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = mouse_btn.pressed

	elif event is InputEventMouseMotion and _is_dragging:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_orbit_angle -= motion.relative.x * mouse_sensitivity

	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			var index: int = -1
			match key_event.keycode:
				KEY_1, KEY_KP_1:
					index = 0
				KEY_2, KEY_KP_2:
					index = 1
				KEY_3, KEY_KP_3:
					index = 2
			if index >= 0 and index < test_animations.size() and is_instance_valid(target_sprite):
				target_sprite.play_anim(test_animations[index])


func _process(delta: float) -> void:
	var dir_input: float = 0.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir_input += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir_input -= 1.0

	if not is_zero_approx(dir_input):
		_orbit_angle += dir_input * orbit_speed * delta

	_update_camera_transform()
	_update_debug_output()


func _update_camera_transform() -> void:
	if not is_instance_valid(orbit_camera):
		return

	var center: Vector3 = target_sprite.global_position if is_instance_valid(target_sprite) else global_position
	var cam_offset: Vector3 = Vector3(
		sin(_orbit_angle) * orbit_radius,
		orbit_height,
		-cos(_orbit_angle) * orbit_radius
	)
	orbit_camera.global_position = center + cam_offset
	orbit_camera.look_at(center, Vector3.UP)


func _update_debug_output() -> void:
	var deg: float = fposmod(rad_to_deg(_orbit_angle), 360.0)
	var anim_name: String = "none"
	var dir_label: String = "N/A"

	if is_instance_valid(target_sprite):
		anim_name = String(target_sprite.animation) if target_sprite.animation != &"" else "none"
		var dir_idx: int = target_sprite.get_current_direction()
		if dir_idx >= 0 and dir_idx < DIRECTION_NAMES.size():
			dir_label = DIRECTION_NAMES[dir_idx]

	var status_text: String = "Angle: %5.1f deg | Direction: %s | Animation: %s" % [deg, dir_label, anim_name]
	if is_instance_valid(debug_label):
		debug_label.text = "%s\nControls: A/D or Arrows or Drag = Orbit | 1/2/3 = Switch Animation" % status_text
	elif status_text != _last_printed_state:
		_last_printed_state = status_text
		print("[BoomerAnim3D Demo] ", status_text)
