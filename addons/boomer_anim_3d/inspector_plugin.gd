@tool
extends EditorInspectorPlugin

const COLOR_DIR_CONFIGURED: Color = Color(0.72, 0.98, 0.76, 1.0)
const COLOR_DIR_EMPTY: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_OMNI_CONFIGURED: Color = Color(0.68, 0.90, 1.0, 1.0)
const COLOR_OMNI_EMPTY: Color = Color(1.0, 0.95, 0.82, 1.0)


func _can_handle(object: Object) -> bool:
	return object is BoomerAnimatedSprite3D


func _parse_begin(object: Object) -> void:
	var sprite: BoomerAnimatedSprite3D = object as BoomerAnimatedSprite3D
	if not is_instance_valid(sprite):
		return

	var root_margin: MarginContainer = MarginContainer.new()
	root_margin.add_theme_constant_override("margin_left", 4)
	root_margin.add_theme_constant_override("margin_right", 4)
	root_margin.add_theme_constant_override("margin_top", 4)
	root_margin.add_theme_constant_override("margin_bottom", 4)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	root_margin.add_child(vbox)

	var title_label: Label = Label.new()
	title_label.text = "BoomerAnim3D — Direction Grid"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(grid)

	# Top-down layout around the character:
	# Row 1: Back Right  | Back         | Back Left
	# Row 2: Right       | Omni (1 Dir) | Left
	# Row 3: Front Right | Front        | Front Left
	var cell_dirs: Array[int] = [
		BoomerAnimatedSprite3D.Direction.BACK_RIGHT,
		BoomerAnimatedSprite3D.Direction.BACK,
		BoomerAnimatedSprite3D.Direction.BACK_LEFT,
		BoomerAnimatedSprite3D.Direction.RIGHT,
		BoomerAnimatedSprite3D.Direction.OMNI,
		BoomerAnimatedSprite3D.Direction.LEFT,
		BoomerAnimatedSprite3D.Direction.FRONT_RIGHT,
		BoomerAnimatedSprite3D.Direction.FRONT,
		BoomerAnimatedSprite3D.Direction.FRONT_LEFT,
	]
	var cell_labels: Array[String] = [
		"Back Right",
		"Back",
		"Back Left",
		"Right",
		"Omni (1 Dir)",
		"Left",
		"Front Right",
		"Front",
		"Front Left",
	]
	var cell_tooltips: Array[String] = [
		"Edit Back Right (135 deg) SpriteFrames.",
		"Edit Back (180 deg) SpriteFrames.",
		"Edit Back Left (-135 deg) SpriteFrames. Mirrors Back Right if empty when mirror_left_if_empty is enabled.",
		"Edit Right (90 deg) SpriteFrames.",
		"Edit Omni (1-direction) SpriteFrames. Animations with frames here override all 8 directions (ideal for death, hurt, or props).",
		"Edit Left (-90 deg) SpriteFrames. Mirrors Right if empty when mirror_left_if_empty is enabled.",
		"Edit Front Right (45 deg) SpriteFrames.",
		"Edit Front (0 deg) SpriteFrames.",
		"Edit Front Left (-45 deg) SpriteFrames. Mirrors Front Right if empty when mirror_left_if_empty is enabled.",
	]

	var buttons_by_dir: Dictionary = {}

	for i: int in range(cell_dirs.size()):
		var dir: int = cell_dirs[i]
		var label_text: String = cell_labels[i]
		var base_tooltip: String = cell_tooltips[i]

		var btn: Button = Button.new()
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0.0, 56.0)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.button_pressed = (sprite.editor_direction == dir)
		_update_button_visual(btn, sprite, label_text, dir, base_tooltip)
		btn.pressed.connect(_on_direction_pressed.bind(sprite, dir))
		grid.add_child(btn)
		buttons_by_dir[dir] = btn

	var active_frames: SpriteFrames = sprite.sprite_frames
	if is_instance_valid(active_frames):
		var on_frames_changed: Callable = func() -> void:
			if not is_instance_valid(sprite):
				return
			for idx: int in range(cell_dirs.size()):
				var d: int = cell_dirs[idx]
				var button_obj: Button = buttons_by_dir.get(d, null) as Button
				if is_instance_valid(button_obj):
					_update_button_visual(button_obj, sprite, cell_labels[idx], d, cell_tooltips[idx])

		active_frames.changed.connect(on_frames_changed)
		root_margin.tree_exited.connect(func() -> void:
			if is_instance_valid(active_frames) and active_frames.changed.is_connected(on_frames_changed):
				active_frames.changed.disconnect(on_frames_changed)
		)

	var sync_btn: Button = Button.new()
	sync_btn.text = "Sync Animation Names to All 8 Directions"
	sync_btn.disabled = (sprite.editor_direction == BoomerAnimatedSprite3D.Direction.OMNI)
	sync_btn.tooltip_text = "Copies animation names, FPS, and loop flags from the active direction to all other 7 directional slots without modifying Omni or existing frames."
	sync_btn.pressed.connect(_on_sync_pressed.bind(sprite))
	vbox.add_child(sync_btn)

	var separator: HSeparator = HSeparator.new()
	vbox.add_child(separator)

	add_custom_control(root_margin)


func _update_button_visual(btn: Button, sprite: BoomerAnimatedSprite3D, label_text: String, dir: int, base_tooltip: String) -> void:
	var configured: bool = sprite.has_configured_frames(dir)
	btn.text = "%s\n●" % label_text if configured else label_text

	if dir == BoomerAnimatedSprite3D.Direction.OMNI:
		btn.self_modulate = COLOR_OMNI_CONFIGURED if configured else COLOR_OMNI_EMPTY
	else:
		btn.self_modulate = COLOR_DIR_CONFIGURED if configured else COLOR_DIR_EMPTY

	var status_line: String = "Status: Configured" if configured else "Status: Empty"
	btn.tooltip_text = "%s\n%s" % [base_tooltip, status_line]


func _on_direction_pressed(sprite: BoomerAnimatedSprite3D, dir: int) -> void:
	if not is_instance_valid(sprite):
		return

	var sf: SpriteFrames = sprite.get_or_create_frames(dir)
	if not is_instance_valid(sf):
		return

	sprite.editor_direction = dir
	sprite.sprite_frames = sf
	EditorInterface.mark_scene_as_unsaved()
	call_deferred("_refresh_node_selection", sprite)


func _on_sync_pressed(sprite: BoomerAnimatedSprite3D) -> void:
	if not is_instance_valid(sprite):
		return
	if sprite.editor_direction == BoomerAnimatedSprite3D.Direction.OMNI:
		return

	sprite.sync_animation_names_from(sprite.editor_direction)
	EditorInterface.mark_scene_as_unsaved()
	call_deferred("_refresh_node_selection", sprite)


func _refresh_node_selection(sprite: BoomerAnimatedSprite3D) -> void:
	if not is_instance_valid(sprite) or not sprite.is_inside_tree():
		return

	var selection: EditorSelection = EditorInterface.get_selection()
	if not is_instance_valid(selection):
		return

	selection.remove_node(sprite)
	call_deferred("_reselect_node", sprite)


func _reselect_node(sprite: BoomerAnimatedSprite3D) -> void:
	if not is_instance_valid(sprite) or not sprite.is_inside_tree():
		return

	var selection: EditorSelection = EditorInterface.get_selection()
	if not is_instance_valid(selection):
		return

	selection.add_node(sprite)
