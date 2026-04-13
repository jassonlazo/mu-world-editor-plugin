@tool
extends VBoxContainer
class_name MuWorldEditorDock

const MU_WORLD_EDITOR_SCRIPT := preload("res://addons/mu_world_editor/mu_world_editor.gd")

var plugin: EditorPlugin
var _selected_editor: Node
var _tracked_object: Node3D

var _status_label: Label
var _details_label: Label
var _export_path_edit: LineEdit
var _save_dialog: EditorFileDialog
var _create_button: Button
var _import_button: Button
var _terrain_button: Button
var _export_button: Button
var _refresh_list_button: Button
var _object_tree: Tree
var _pos_x: SpinBox
var _pos_y: SpinBox
var _pos_z: SpinBox
var _selection_info: Label

var _updating_ui := false
var _tree_metadata_to_item := {}
var _last_tracked_position := Vector3.ZERO


func _ready() -> void:
	name = "MU Editor"
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	set_process(true)

	var title := Label.new()
	title.text = "MU World Editor"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	_status_label = Label.new()
	_status_label.text = "Selecciona un nodo MuWorldEditor o crea uno nuevo."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)

	_details_label = Label.new()
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_details_label)

	_create_button = Button.new()
	_create_button.text = "Usar cargador de esta escena"
	_create_button.pressed.connect(_on_create_pressed)
	add_child(_create_button)

	_import_button = Button.new()
	_import_button.text = "Importar mundo MU"
	_import_button.pressed.connect(_on_import_pressed)
	add_child(_import_button)

	_terrain_button = Button.new()
	_terrain_button.text = "Recargar terreno"
	_terrain_button.pressed.connect(_on_reload_terrain_pressed)
	add_child(_terrain_button)

	_refresh_list_button = Button.new()
	_refresh_list_button.text = "Refrescar lista de objetos"
	_refresh_list_button.pressed.connect(_refresh_object_list)
	add_child(_refresh_list_button)

	var objects_label := Label.new()
	objects_label.text = "Objetos / archivos cargados:"
	add_child(objects_label)

	_object_tree = Tree.new()
	_object_tree.columns = 4
	_object_tree.column_titles_visible = true
	_object_tree.set_column_title(0, "Objeto")
	_object_tree.set_column_title(1, "Tipo")
	_object_tree.set_column_title(2, "Posicion")
	_object_tree.set_column_title(3, "Archivo")
	_object_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_object_tree.custom_minimum_size = Vector2(0, 80)
	_object_tree.item_selected.connect(_on_object_tree_selected)
	add_child(_object_tree)

	_selection_info = Label.new()
	_selection_info.text = "Selecciona un objeto para editar su posicion."
	_selection_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_selection_info)

	var pos_grid := GridContainer.new()
	pos_grid.columns = 2
	add_child(pos_grid)

	var pos_x_label := Label.new()
	pos_x_label.text = "Pos X"
	pos_grid.add_child(pos_x_label)
	_pos_x = _make_position_spinbox()
	_pos_x.value_changed.connect(_on_position_spinbox_changed)
	pos_grid.add_child(_pos_x)

	var pos_y_label := Label.new()
	pos_y_label.text = "Pos Y"
	pos_grid.add_child(pos_y_label)
	_pos_y = _make_position_spinbox()
	_pos_y.step = 10.0
	_pos_y.value_changed.connect(_on_position_spinbox_changed)
	pos_grid.add_child(_pos_y)

	var pos_z_label := Label.new()
	pos_z_label.text = "Pos Z"
	pos_grid.add_child(pos_z_label)
	_pos_z = _make_position_spinbox()
	_pos_z.value_changed.connect(_on_position_spinbox_changed)
	pos_grid.add_child(_pos_z)

	var export_label := Label.new()
	export_label.text = "Ruta de guardado:"
	add_child(export_label)

	var export_row := HBoxContainer.new()
	add_child(export_row)

	_export_path_edit = LineEdit.new()
	_export_path_edit.placeholder_text = "res://Data/World95/EncTerrain95.edited.obj"
	_export_path_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	export_row.add_child(_export_path_edit)

	var browse_button := Button.new()
	browse_button.text = "..."
	browse_button.custom_minimum_size = Vector2(42, 0)
	browse_button.pressed.connect(_on_browse_pressed)
	export_row.add_child(browse_button)

	_export_button = Button.new()
	_export_button.text = "Guardar posiciones"
	_export_button.pressed.connect(_on_export_pressed)
	add_child(_export_button)

	var hint := Label.new()
	hint.text = "Flujo recomendado: importa el mundo, selecciona un objeto en la lista o en la escena 3D, muévelo arrastrando con el gizmo de Godot y luego pulsa Guardar posiciones."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_save_dialog = EditorFileDialog.new()
	_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_dialog.add_filter("*.obj ; MU EncTerrain object layout")
	_save_dialog.file_selected.connect(_on_export_path_selected)
	add_child(_save_dialog)

	refresh_selection(null)


func refresh_selection(editor_node: Node) -> void:
	if _status_label == null:
		return

	_selected_editor = editor_node
	var has_editor := _selected_editor != null

	_import_button.disabled = not has_editor
	_terrain_button.disabled = not has_editor
	_export_button.disabled = not has_editor
	_refresh_list_button.disabled = not has_editor
	_object_tree.visible = has_editor

	if not has_editor:
		_status_label.text = "Selecciona un nodo MuWorldEditor o crea uno nuevo."
		_details_label.text = ""
		if _export_path_edit:
			_export_path_edit.text = ""
		_clear_object_list()
		_set_tracked_object(null)
		return

	_status_label.text = "Nodo activo en la escena: %s" % _selected_editor.name
	_details_label.text = "World %d\nFuente OBJ: %s" % [
		int(_selected_editor.get("world_index")),
		_selected_editor.call("get_source_obj_path"),
	]
	_export_path_edit.text = _selected_editor.call("get_default_export_path")
	_refresh_object_list()
	_set_tracked_object(_get_selected_world_object())


func _on_create_pressed() -> void:
	if plugin == null:
		return

	var root := plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		_status_label.text = "Abre o crea una escena antes de crear el nodo."
		return

	var node: Node = plugin.call("get_scene_world_editor", true)
	if node and node.has_method("queue_reload"):
		node.call("queue_reload")

	var selection: EditorSelection = plugin.get_editor_interface().get_selection()
	selection.clear()
	if node:
		selection.add_node(node)
	refresh_selection(node)
	_status_label.text = "El cargador MU de esta escena esta listo."


func _on_import_pressed() -> void:
	if _selected_editor == null:
		return
	var result: Dictionary = _selected_editor.call("import_world")
	_status_label.text = result.get("message", "Importacion completada.")
	refresh_selection(_selected_editor)


func _on_reload_terrain_pressed() -> void:
	if _selected_editor == null:
		return
	var result: Dictionary = _selected_editor.call("rebuild_terrain")
	_status_label.text = result.get("message", "Terreno actualizado.")


func _on_export_pressed() -> void:
	if _selected_editor == null:
		return
	var result: Dictionary = _selected_editor.call("export_current_layout", _export_path_edit.text)
	_status_label.text = result.get("message", "Exportacion completada.")
	if result.get("ok", false):
		var filesystem := plugin.get_editor_interface().get_resource_filesystem()
		if filesystem:
			filesystem.scan()
		refresh_selection(_selected_editor)


func _on_browse_pressed() -> void:
	if _selected_editor:
		_save_dialog.current_path = _export_path_edit.text if not _export_path_edit.text.is_empty() else _selected_editor.call("get_default_export_path")
	_save_dialog.popup_centered_ratio(0.7)


func _on_export_path_selected(path: String) -> void:
	_export_path_edit.text = path


func _process(_delta: float) -> void:
	if _tracked_object == null or not is_instance_valid(_tracked_object):
		return
	if _tracked_object.global_position.is_equal_approx(_last_tracked_position):
		return
	_last_tracked_position = _tracked_object.global_position
	_update_position_fields()
	_update_tree_item_for_node(_tracked_object)


func _make_position_spinbox() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -100000.0
	spin.max_value = 100000.0
	spin.step = 100.0
	spin.size_flags_horizontal = SIZE_EXPAND_FILL
	return spin


func _clear_object_list() -> void:
	_tree_metadata_to_item.clear()
	if _object_tree:
		_object_tree.clear()


func _refresh_object_list() -> void:
	_clear_object_list()
	if _selected_editor == null:
		return

	var root: TreeItem = _object_tree.create_item()
	var objects: Array = _selected_editor.call("get_world_objects")
	for node in objects:
		if node == null or not is_instance_valid(node):
			continue
		var item: TreeItem = _object_tree.create_item(root)
		var object_id: int = node.get_instance_id()
		var source_file_name: String = String(node.get("mu_source_file_name"))
		var display_name: String = source_file_name if not source_file_name.is_empty() else node.name
		item.set_metadata(0, object_id)
		item.set_text(0, display_name)
		item.set_text(1, str(node.get("mu_type_id")))
		item.set_text(2, _format_position(node.global_position))
		item.set_text(3, display_name)
		_tree_metadata_to_item[object_id] = item

	if root and root.get_first_child():
		root.collapsed = false
	_selection_info.text = "%d objetos cargados." % objects.size()
	_select_tree_item_for_object(_tracked_object)


func _format_position(pos: Vector3) -> String:
	return "%.1f, %.1f, %.1f" % [pos.x, pos.y, pos.z]


func _on_object_tree_selected() -> void:
	var item: TreeItem = _object_tree.get_selected()
	if item == null or plugin == null:
		return

	var object_id: int = int(item.get_metadata(0))
	var node: Node = instance_from_id(object_id) as Node
	if node == null:
		return

	var selection: EditorSelection = plugin.get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(node)
	_set_tracked_object(node as Node3D)


func _get_selected_world_object() -> Node3D:
	if plugin == null or _selected_editor == null:
		return null

	var selection: EditorSelection = plugin.get_editor_interface().get_selection()
	if selection == null or selection.get_selected_nodes().is_empty():
		return null

	var candidate: Node = selection.get_selected_nodes()[0] as Node
	if candidate == null:
		return null

	if candidate == _selected_editor:
		return null

	var current: Node = candidate
	while current:
		if current == _selected_editor:
			return candidate as Node3D
		current = current.get_parent()

	return null


func _set_tracked_object(node: Node3D) -> void:
	if node != null and not is_instance_valid(node):
		node = null

	_tracked_object = node
	_update_position_fields()
	_select_tree_item_for_object(_tracked_object)

	if _tracked_object:
		_last_tracked_position = _tracked_object.global_position
		_selection_info.text = "Objeto seleccionado: %s" % _tracked_object.name
	else:
		_last_tracked_position = Vector3.ZERO
		_selection_info.text = "Selecciona un objeto en la lista o en la vista 3D."


func _update_position_fields() -> void:
	_updating_ui = true
	if _tracked_object and is_instance_valid(_tracked_object):
		_pos_x.value = _tracked_object.global_position.x
		_pos_y.value = _tracked_object.global_position.y
		_pos_z.value = _tracked_object.global_position.z
	else:
		_pos_x.value = 0.0
		_pos_y.value = 0.0
		_pos_z.value = 0.0
	_updating_ui = false


func _on_position_spinbox_changed(_value: float) -> void:
	if _updating_ui or _tracked_object == null or not is_instance_valid(_tracked_object):
		return

	_tracked_object.global_position = Vector3(
		_pos_x.value,
		_pos_y.value,
		_pos_z.value
	)
	_last_tracked_position = _tracked_object.global_position
	_update_tree_item_for_node(_tracked_object)


func _update_tree_item_for_node(node: Node3D) -> void:
	if node == null:
		return
	var object_id: int = node.get_instance_id()
	if not _tree_metadata_to_item.has(object_id):
		return
	var item: TreeItem = _tree_metadata_to_item[object_id]
	if item:
		item.set_text(2, _format_position(node.global_position))


func _select_tree_item_for_object(node: Node3D) -> void:
	if node == null:
		return
	var object_id: int = node.get_instance_id()
	if not _tree_metadata_to_item.has(object_id):
		return
	var item: TreeItem = _tree_metadata_to_item[object_id]
	if item:
		item.select(0)
