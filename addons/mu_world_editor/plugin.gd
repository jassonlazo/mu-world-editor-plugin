@tool
extends EditorPlugin

const MU_WORLD_EDITOR_EXTENSION := preload("res://addons/mu_world_editor/mu_world_editor.gdextension")

const MU_WORLD_EDITOR_SCRIPT := preload("res://addons/mu_world_editor/mu_world_editor.gd")
const MU_WORLD_EDITOR_DOCK_SCRIPT := preload("res://addons/mu_world_editor/mu_world_editor_dock.gd")
const AUTO_SCENE_NODE_NAME := "MUGameFiles"

var _dock: Control
var _selection: EditorSelection
var _last_scene_root_id: int = 0
var _editor_nav_active: bool = false
var _editor_nav_yaw: float = 0.0
var _editor_nav_pitch: float = 0.0
var _editor_nav_move_speed: float = 4500.0
var _editor_nav_sprint_multiplier: float = 4.0
var _editor_nav_slow_multiplier: float = 0.2
var _editor_nav_mouse_sensitivity: float = 0.0025
var _editor_nav_speed_factor: float = 1.25
var _editor_nav_min_speed: float = 250.0
var _editor_nav_max_speed: float = 100000.0
var _editor_nav_zoom_ratio: float = 0.12
var _editor_nav_zoom_min_step: float = 24.0
var _editor_nav_zoom_max_step: float = 1600.0
var _editor_nav_zoom_fast_multiplier: float = 1.8
var _editor_nav_zoom_slow_multiplier: float = 0.35
var _editor_nav_far_clip: float = 250000.0
var _editor_nav_keys := {}


func _handles(object: Object) -> bool:
	return object is Node


func _enter_tree() -> void:
	_selection = get_editor_interface().get_selection()
	if _selection and not _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.connect(_on_selection_changed)

	_dock = MU_WORLD_EDITOR_DOCK_SCRIPT.new()
	_dock.plugin = self
	add_control_to_bottom_panel(_dock, "MU Editor")
	add_custom_type("MuWorldEditor", "Node3D", MU_WORLD_EDITOR_SCRIPT, null)
	set_process(true)
	_sync_scene_world_editor()
	_on_selection_changed()


func _exit_tree() -> void:
	if _selection and _selection.selection_changed.is_connected(_on_selection_changed):
		_selection.selection_changed.disconnect(_on_selection_changed)

	set_process(false)
	remove_custom_type("MuWorldEditor")
	if _dock:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null


func _on_selection_changed() -> void:
	if _dock and _dock.has_method("refresh_selection"):
		_dock.refresh_selection(get_active_world_editor())


func _process(_delta: float) -> void:
	_sync_scene_world_editor()
	_process_editor_navigation(_delta)


func get_active_world_editor() -> Node:
	if _selection == null:
		return get_scene_world_editor(false)

	for selected in _selection.get_selected_nodes():
		var current: Node = selected
		while current:
			if current.get_script() == MU_WORLD_EDITOR_SCRIPT:
				return current
			current = current.get_parent()

	return get_scene_world_editor(false)


func get_scene_world_editor(create_if_missing: bool = true) -> Node:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return null

	if root.get_script() == MU_WORLD_EDITOR_SCRIPT:
		_configure_scene_world_editor(root, root)
		return root

	var existing := _find_world_editor_node(root)
	if existing != null:
		_configure_scene_world_editor(existing, root)
		return existing

	if not create_if_missing:
		return null

	return _create_scene_world_editor(root)


func _sync_scene_world_editor() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	var root_id := 0
	if root != null:
		root_id = root.get_instance_id()

	if root_id != _last_scene_root_id:
		_last_scene_root_id = root_id
		if root != null:
			get_scene_world_editor(true)
		_on_selection_changed()
		return

	if root != null and _find_world_editor_node(root) == null:
		get_scene_world_editor(true)
		_on_selection_changed()


func _find_world_editor_node(root: Node) -> Node:
	for child in root.get_children():
		var child_node: Node = child as Node
		if child_node == null:
			continue
		if child_node.get_script() == MU_WORLD_EDITOR_SCRIPT:
			return child_node
		if String(child_node.name) == AUTO_SCENE_NODE_NAME:
			return child_node
	return null


func _create_scene_world_editor(root: Node) -> Node:
	var node := Node3D.new()
	node.name = AUTO_SCENE_NODE_NAME
	node.set_script(MU_WORLD_EDITOR_SCRIPT)
	node.set("auto_load_in_editor", true)
	node.set("load_terrain_preview", true)
	node.set("load_objects_from_source", true)
	node.set("limit_imported_objects", false)
	node.set("object_limit", 500)
	root.add_child(node)
	node.owner = root
	_configure_scene_world_editor(node, root)
	return node


func _configure_scene_world_editor(node: Node, root: Node) -> void:
	if node == null or root == null:
		return

	var desired_world := _guess_world_for_scene(root)
	var changed := false

	if int(node.get("world_index")) != desired_world:
		node.set("world_index", desired_world)
		changed = true

	if String(node.get("data_path")) != "res://Data/":
		node.set("data_path", "res://Data/")
		changed = true

	if String(node.get("source_obj_path")) != "":
		node.set("source_obj_path", "")
		changed = true

	node.set("auto_load_in_editor", true)
	node.set("load_terrain_preview", true)
	node.set("load_objects_from_source", true)

	if changed and node.has_method("queue_reload"):
		node.call("queue_reload")


func _guess_world_for_scene(root: Node) -> int:
	var scene_path := String(root.scene_file_path).to_lower()
	if "selectcharacter" in scene_path:
		return 75
	if "login" in scene_path:
		for candidate in [74, 78, 56, 95, 1]:
			if FileAccess.file_exists("res://Data/World" + str(candidate) + "/TerrainHeight.OZB"):
				return candidate
	return 95


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if get_scene_world_editor(false) == null or viewport_camera == null:
		return AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var picked_node: Node3D = _pick_world_object_at_cursor(viewport_camera, mouse_event.position)
			var selected_node: Node3D = _get_selected_world_object()
			if picked_node != null and picked_node != selected_node:
				call_deferred("_apply_editor_selection", picked_node)
				return AFTER_GUI_INPUT_STOP

		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_editor_nav_active = mouse_event.pressed
			if _editor_nav_active:
				_sync_editor_navigation_angles(viewport_camera)
			else:
				_editor_nav_keys.clear()
			return AFTER_GUI_INPUT_STOP

		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_handle_editor_wheel(viewport_camera, true, mouse_event.alt_pressed, mouse_event.shift_pressed, mouse_event.ctrl_pressed)
			return AFTER_GUI_INPUT_STOP

		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_handle_editor_wheel(viewport_camera, false, mouse_event.alt_pressed, mouse_event.shift_pressed, mouse_event.ctrl_pressed)
			return AFTER_GUI_INPUT_STOP

	if event is InputEventMouseMotion and _editor_nav_active:
		var motion_event := event as InputEventMouseMotion
		_editor_nav_yaw -= motion_event.relative.x * _editor_nav_mouse_sensitivity
		_editor_nav_pitch -= motion_event.relative.y * _editor_nav_mouse_sensitivity
		_editor_nav_pitch = clamp(_editor_nav_pitch, -PI / 2.0 + 0.05, PI / 2.0 - 0.05)
		_apply_editor_camera_rotation(viewport_camera)
		return AFTER_GUI_INPUT_STOP

	if event is InputEventKey:
		var key_event := event as InputEventKey
		var keycode := _get_input_keycode(key_event)
		if keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_SHIFT, KEY_CTRL]:
			if _editor_nav_active:
				_editor_nav_keys[keycode] = key_event.pressed
				return AFTER_GUI_INPUT_STOP
			_editor_nav_keys.erase(keycode)

	return AFTER_GUI_INPUT_PASS


func _process_editor_navigation(delta: float) -> void:
	if not _editor_nav_active:
		return

	var camera := _get_editor_camera()
	if camera == null:
		return
	_prepare_editor_camera(camera)

	var forward := -camera.global_transform.basis.z.normalized()
	var right   :=  camera.global_transform.basis.x.normalized()

	var move := Vector3.ZERO
	if _is_editor_nav_key_pressed(KEY_W):
		move += forward
	if _is_editor_nav_key_pressed(KEY_S):
		move -= forward
	if _is_editor_nav_key_pressed(KEY_A):
		move -= right
	if _is_editor_nav_key_pressed(KEY_D):
		move += right
	if _is_editor_nav_key_pressed(KEY_E):
		move += Vector3.UP
	if _is_editor_nav_key_pressed(KEY_Q):
		move += Vector3.DOWN

	if move.length_squared() <= 0.0001:
		return

	var speed := _editor_nav_move_speed
	if _is_editor_nav_key_pressed(KEY_SHIFT):
		speed *= _editor_nav_sprint_multiplier
	elif _is_editor_nav_key_pressed(KEY_CTRL):
		speed *= _editor_nav_slow_multiplier

	camera.global_position += move.normalized() * speed * delta


func _handle_editor_wheel(camera: Camera3D, wheel_up: bool, alt_pressed: bool, shift_pressed: bool, ctrl_pressed: bool) -> void:
	_prepare_editor_camera(camera)

	if alt_pressed:
		if wheel_up:
			_editor_nav_move_speed = clamp(_editor_nav_move_speed * _editor_nav_speed_factor, _editor_nav_min_speed, _editor_nav_max_speed)
		else:
			_editor_nav_move_speed = clamp(_editor_nav_move_speed / _editor_nav_speed_factor, _editor_nav_min_speed, _editor_nav_max_speed)
		return

	var step: float = _get_editor_wheel_step(camera)
	if shift_pressed:
		step *= _editor_nav_zoom_fast_multiplier
	elif ctrl_pressed:
		step *= _editor_nav_zoom_slow_multiplier

	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var direction: float = 1.0 if wheel_up else -1.0
	camera.global_position += forward * step * direction


func _get_editor_wheel_step(camera: Camera3D) -> float:
	var focus_position: Vector3 = _get_editor_focus_position(camera)
	var focus_distance: float = camera.global_position.distance_to(focus_position)
	if focus_distance <= 0.001:
		focus_distance = max(_editor_nav_move_speed * 0.18, _editor_nav_zoom_min_step)
	return clamp(focus_distance * _editor_nav_zoom_ratio, _editor_nav_zoom_min_step, _editor_nav_zoom_max_step)


func _get_editor_focus_position(camera: Camera3D) -> Vector3:
	if _selection != null:
		for selected in _selection.get_selected_nodes():
			var selected_node: Node3D = selected as Node3D
			if selected_node != null:
				return selected_node.global_position

	var forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var fallback_distance: float = max(_editor_nav_move_speed * 0.35, _editor_nav_zoom_min_step)
	return camera.global_position + forward * fallback_distance


func _pick_world_object_at_cursor(camera: Camera3D, mouse_position: Vector2) -> Node3D:
	var editor_node: Node = get_scene_world_editor(false)
	if editor_node == null or not editor_node.has_method("get_world_objects"):
		return null

	var ray_origin: Vector3 = camera.project_ray_origin(mouse_position)
	var ray_direction: Vector3 = camera.project_ray_normal(mouse_position).normalized()
	var best_node: Node3D = null
	var best_distance: float = INF
	var objects: Array = editor_node.call("get_world_objects")
	for object_variant in objects:
		var node: MeshInstance3D = object_variant as MeshInstance3D
		if node == null or not is_instance_valid(node):
			continue
		if node.mesh == null:
			continue

		var pick_aabb: AABB = _get_world_pick_aabb(node)
		var hit_distance: float = _ray_aabb_distance(ray_origin, ray_direction, pick_aabb)
		if hit_distance < best_distance:
			best_distance = hit_distance
			best_node = node

	return best_node


func _apply_editor_selection(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var selection: EditorSelection = get_editor_interface().get_selection()
	if selection == null:
		return
	selection.clear()
	selection.add_node(node)


func _get_selected_world_object() -> Node3D:
	if _selection == null:
		return null

	var editor_node: Node = get_scene_world_editor(false)
	if editor_node == null:
		return null

	for selected in _selection.get_selected_nodes():
		var selected_node: Node3D = selected as Node3D
		if selected_node == null:
			continue
		var current: Node = selected_node
		while current != null:
			if current == editor_node:
				return selected_node
			current = current.get_parent()

	return null


func _get_world_pick_aabb(node: MeshInstance3D) -> AABB:
	var local_aabb: AABB = node.get_aabb()
	if local_aabb.size.length_squared() <= 0.0001:
		local_aabb = AABB(Vector3(-20.0, -20.0, -20.0), Vector3(40.0, 40.0, 40.0))

	var corners: Array[Vector3] = [
		local_aabb.position,
		local_aabb.position + Vector3(local_aabb.size.x, 0.0, 0.0),
		local_aabb.position + Vector3(0.0, local_aabb.size.y, 0.0),
		local_aabb.position + Vector3(0.0, 0.0, local_aabb.size.z),
		local_aabb.position + Vector3(local_aabb.size.x, local_aabb.size.y, 0.0),
		local_aabb.position + Vector3(local_aabb.size.x, 0.0, local_aabb.size.z),
		local_aabb.position + Vector3(0.0, local_aabb.size.y, local_aabb.size.z),
		local_aabb.position + local_aabb.size,
	]

	var min_corner: Vector3 = node.global_transform * corners[0]
	var max_corner: Vector3 = min_corner
	for corner in corners:
		var world_corner: Vector3 = node.global_transform * corner
		min_corner = Vector3(
			minf(min_corner.x, world_corner.x),
			minf(min_corner.y, world_corner.y),
			minf(min_corner.z, world_corner.z)
		)
		max_corner = Vector3(
			maxf(max_corner.x, world_corner.x),
			maxf(max_corner.y, world_corner.y),
			maxf(max_corner.z, world_corner.z)
		)

	return AABB(min_corner, max_corner - min_corner).grow(18.0)


func _ray_aabb_distance(ray_origin: Vector3, ray_direction: Vector3, aabb: AABB) -> float:
	var box_min: Vector3 = aabb.position
	var box_max: Vector3 = aabb.position + aabb.size
	var tmin: float = 0.0
	var tmax: float = INF

	var x_result: Dictionary = _update_ray_aabb_axis(ray_origin.x, ray_direction.x, box_min.x, box_max.x, tmin, tmax)
	if not x_result.get("ok", false):
		return INF
	tmin = float(x_result.get("tmin", tmin))
	tmax = float(x_result.get("tmax", tmax))

	var y_result: Dictionary = _update_ray_aabb_axis(ray_origin.y, ray_direction.y, box_min.y, box_max.y, tmin, tmax)
	if not y_result.get("ok", false):
		return INF
	tmin = float(y_result.get("tmin", tmin))
	tmax = float(y_result.get("tmax", tmax))

	var z_result: Dictionary = _update_ray_aabb_axis(ray_origin.z, ray_direction.z, box_min.z, box_max.z, tmin, tmax)
	if not z_result.get("ok", false):
		return INF
	tmin = float(z_result.get("tmin", tmin))
	tmax = float(z_result.get("tmax", tmax))

	if tmax < 0.0:
		return INF
	return tmin if tmin >= 0.0 else tmax


func _update_ray_aabb_axis(origin_value: float, direction_value: float, min_value: float, max_value: float, current_tmin: float, current_tmax: float) -> Dictionary:
	if absf(direction_value) <= 0.000001:
		return {
			"ok": origin_value >= min_value and origin_value <= max_value,
			"tmin": current_tmin,
			"tmax": current_tmax,
		}

	var inv_direction: float = 1.0 / direction_value
	var t1: float = (min_value - origin_value) * inv_direction
	var t2: float = (max_value - origin_value) * inv_direction
	if t1 > t2:
		var swapped: float = t1
		t1 = t2
		t2 = swapped

	current_tmin = maxf(current_tmin, t1)
	current_tmax = minf(current_tmax, t2)
	return {
		"ok": current_tmin <= current_tmax,
		"tmin": current_tmin,
		"tmax": current_tmax,
	}


func _sync_editor_navigation_angles(camera: Camera3D) -> void:
	_prepare_editor_camera(camera)
	var euler := camera.global_transform.basis.get_euler(EULER_ORDER_YXZ)
	_editor_nav_pitch = euler.x
	_editor_nav_yaw = euler.y


func _apply_editor_camera_rotation(camera: Camera3D) -> void:
	camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(_editor_nav_pitch, _editor_nav_yaw, 0.0), EULER_ORDER_YXZ),
		camera.global_position
	)


func _get_editor_camera() -> Camera3D:
	var viewport := get_editor_interface().get_editor_viewport_3d()
	if viewport == null:
		return null
	return viewport.get_camera_3d()


func _prepare_editor_camera(camera: Camera3D) -> void:
	camera.near = min(camera.near, 0.05)
	camera.far = max(camera.far, _editor_nav_far_clip)


func _get_input_keycode(event: InputEventKey) -> int:
	if event.physical_keycode != 0:
		return event.physical_keycode
	return event.keycode


func _is_editor_nav_key_pressed(keycode: int) -> bool:
	return _editor_nav_keys.get(keycode, false)
