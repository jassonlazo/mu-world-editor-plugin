@tool
extends Node3D
class_name MuWorldEditor

const TERRAIN_WORLD_SIZE := 25600.0
const WORLD1_MAPPING := {
	0: "Tree01", 1: "Tree02", 2: "Tree03", 3: "Tree04", 4: "Tree05", 5: "Tree06", 6: "Tree07", 7: "Tree08",
	8: "Tree09", 9: "Tree10", 10: "Tree11", 11: "Tree12", 12: "Tree13", 20: "Grass01", 21: "Grass02",
	22: "Grass03", 23: "Grass04", 24: "Grass05", 25: "Grass06", 26: "Grass07", 27: "Grass08", 30: "Stone01",
	31: "Stone02", 32: "Stone03", 33: "Stone04", 34: "Stone05", 40: "StoneStatue01", 41: "StoneStatue02",
	42: "StoneStatue03", 43: "SteelStatue01", 44: "Tomb01", 45: "Tomb02", 46: "Tomb03", 50: "FireLight01",
	51: "FireLight02", 52: "Bonfire01", 55: "DoungeonGate01", 56: "MerchantAnimal01", 57: "MerchantAnimal02",
	58: "TreasureDrum01", 59: "TreasureChest01", 60: "Shop01", 65: "SteelWall01", 66: "SteelWall02",
	67: "SteelWall03", 68: "SteelDoor01", 69: "StoneWall01", 70: "StoneWall02", 71: "StoneWall03",
	72: "StoneWall04", 73: "StoneWall05", 74: "StoneWall06", 75: "StoneMuWall01", 76: "StoneMuWall02",
	77: "StoneMuWall03", 78: "StoneMuWall04", 80: "Bridge01", 81: "Fence01", 82: "Fence02", 83: "Fence03",
	84: "Fence04", 85: "BridgeStone01", 90: "StreetLight01", 91: "Cannon01", 92: "Cannon02", 93: "Cannon03",
	95: "Curtain01", 96: "Sign01", 97: "Sign02", 98: "Carriage01", 99: "Carriage02", 100: "Carriage03",
	101: "Carriage04", 102: "Straw01", 103: "Straw02", 105: "Waterspout01", 106: "Well01", 107: "Well02",
	108: "Well03", 109: "Well04", 110: "Hanging01", 111: "Stair01", 115: "House01", 116: "House02",
	117: "House03", 118: "House04", 119: "House05", 120: "Tent01", 121: "HouseWall01", 122: "HouseWall02",
	123: "HouseWall03", 124: "HouseWall04", 125: "HouseWall05", 126: "HouseWall06", 127: "HouseEtc01",
	128: "HouseEtc02", 129: "HouseEtc03", 130: "Light01", 131: "Light02", 132: "Light03", 133: "PoseBox01",
	140: "Furniture01", 141: "Furniture02", 142: "Furniture03", 143: "Furniture04", 144: "Furniture05",
	145: "Furniture06", 146: "Furniture07", 150: "Candle01", 151: "Beer01", 152: "Beer02", 153: "Beer03",
}

const TERRAIN_SCRIPT := preload("res://addons/mu_world_editor/runtime/mu_terrain_runtime.gd")
const BMD_INSTANCE_SCRIPT := preload("res://addons/mu_world_editor/runtime/bmd_instance_runtime.gd")
const OBJECT_CODEC_SCRIPT := preload("res://addons/mu_world_editor/mu_object_codec.gd")

@export_range(1, 200, 1) var world_index: int = 95
@export var data_path: String = "res://Data/"
@export var load_terrain_preview: bool = true
@export var load_objects_from_source: bool = true
@export var auto_load_in_editor: bool = true
@export var limit_imported_objects: bool = false
@export_range(1, 10000, 1) var object_limit: int = 500
@export var source_obj_path: String = ""
@export_storage var source_obj_version: int = -1
@export_storage var source_map_number: int = -1
@export_storage var source_struct_size: int = -1
@export_storage var last_export_path: String = ""

var _auto_load_queued := false
var _last_auto_load_signature := ""


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_ensure_container_nodes()
		_queue_auto_load()


func _ready() -> void:
	if Engine.is_editor_hint():
		_ensure_container_nodes()
		_queue_auto_load()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not ClassDB.class_exists("MuObjectLoader"):
		warnings.append("MuObjectLoader no esta disponible. Revisa la GDExtension.")
	if load_terrain_preview and not ClassDB.class_exists("MuTerrainLoader"):
		warnings.append("MuTerrainLoader no esta disponible. El preview del terreno no podra cargarse.")
	if load_objects_from_source and not FileAccess.file_exists(get_source_obj_path()):
		warnings.append("No se encontro el EncTerrain: %s" % get_source_obj_path())
	return warnings


func get_source_obj_path() -> String:
	if not source_obj_path.strip_edges().is_empty():
		return source_obj_path
	return "%sWorld%d/EncTerrain%d.obj" % [_normalized_data_path(), world_index, world_index]


func get_default_export_path() -> String:
	if not last_export_path.strip_edges().is_empty():
		return last_export_path
	return "%sWorld%d/EncTerrain%d.edited.obj" % [_normalized_data_path(), world_index, world_index]


func queue_reload() -> void:
	_last_auto_load_signature = ""
	_queue_auto_load()


func rebuild_terrain() -> Dictionary:
	_ensure_container_nodes()
	_clear_children(_terrain_root())

	if not load_terrain_preview:
		return {
			"ok": true,
			"message": "Terrain preview disabled.",
		}

	if not ClassDB.class_exists("MuTerrainLoader"):
		return {
			"ok": false,
			"message": "MuTerrainLoader is not available.",
		}

	var terrain := Node3D.new()
	terrain.name = "MuTerrain"
	terrain.set_script(TERRAIN_SCRIPT)
	terrain.set("world_index", world_index)
	terrain.set("data_path", _normalized_data_path())
	_terrain_root().add_child(terrain)
	_assign_scene_owner(terrain)
	if terrain.has_method("load_world"):
		terrain.call_deferred("load_world", world_index)

	return {
		"ok": true,
		"message": "Terrain preview loaded for World %d." % world_index,
	}


func import_world() -> Dictionary:
	_ensure_container_nodes()
	if load_terrain_preview:
		rebuild_terrain()

	if not load_objects_from_source:
		return {
			"ok": true,
			"message": "Object import is disabled for this node.",
		}

	var obj_path := get_source_obj_path()
	var payload := OBJECT_CODEC_SCRIPT.load_object_records(obj_path)
	if not payload.get("ok", false):
		return payload

	source_obj_version = int(payload.get("version", -1))
	source_map_number = int(payload.get("map_number", -1))
	source_struct_size = int(payload.get("struct_size", -1))

	_clear_children(_objects_root())

	var objects: Array = payload.get("objects", [])
	if limit_imported_objects and objects.size() > object_limit:
		objects = objects.slice(0, object_limit)

	var imported_count := 0
	var missing_models := 0
	var object_name_counts := {}
	for record in objects:
		var type_id := int(record.get("type", -1))
		var bmd_path := _resolve_bmd_path(type_id)
		var source_file_name: String = _get_object_source_file_name(type_id, bmd_path)
		var node := MeshInstance3D.new()
		node.set_script(BMD_INSTANCE_SCRIPT)
		node.name = _make_unique_object_name(source_file_name, object_name_counts)
		node.set("mu_object_index", int(record.get("index", imported_count)))
		node.set("mu_type_id", type_id)
		node.set("mu_world_index", world_index)
		node.set("mu_source_obj_path", obj_path)
		node.set("mu_source_file_name", source_file_name)
		node.set("mu_raw_record", record.get("raw_record", PackedByteArray()))
		node.set("mu_original_position", record.get("position", Vector3.ZERO))
		node.set("mu_original_rotation", record.get("rotation", Vector3.ZERO))
		node.set("mu_original_scale", float(record.get("scale", 1.0)))

		node.set("bmd_path", bmd_path)
		_apply_mu_transform(node, record)

		_objects_root().add_child(node)
		_assign_scene_owner(node)

		if node.has_method("load_bmd") and not bmd_path.is_empty():
			node.call("load_bmd", bmd_path)
		elif bmd_path.is_empty():
			_apply_missing_model_placeholder(node)
			missing_models += 1

		imported_count += 1

	return {
		"ok": true,
		"message": "Imported %d objects for World %d%s." % [
			imported_count,
			world_index,
			" (%d missing BMDs)" % missing_models if missing_models > 0 else "",
		],
	}


func export_current_layout(output_path: String = "") -> Dictionary:
	_ensure_container_nodes()

	var final_path := output_path.strip_edges()
	if final_path.is_empty():
		final_path = get_default_export_path()

	var metadata := {
		"version": source_obj_version,
		"map_number": source_map_number if source_map_number >= 0 else world_index,
		"struct_size": source_struct_size,
	}
	if int(metadata.get("version", -1)) < 0 or int(metadata.get("struct_size", -1)) < 0:
		var source_payload := OBJECT_CODEC_SCRIPT.load_object_records(get_source_obj_path())
		if not source_payload.get("ok", false):
			return {
				"ok": false,
				"message": "No export metadata available. Import the world first.",
			}
		metadata["version"] = int(source_payload.get("version", -1))
		metadata["map_number"] = int(source_payload.get("map_number", world_index))
		metadata["struct_size"] = int(source_payload.get("struct_size", -1))

	var nodes := _collect_exportable_objects()
	var objects: Array = []
	for node in nodes:
		var node_scale: Vector3 = node.scale
		var uniform_scale := (node_scale.x + node_scale.y + node_scale.z) / 3.0
		var type_id := int(node.get("mu_type_id"))
		objects.append({
			"type": type_id,
			"position": _godot_to_mu_position(node.global_position, type_id),
			"rotation": _godot_to_mu_rotation(node.quaternion),
			"scale": uniform_scale,
			"raw_record": node.get("mu_raw_record"),
		})

	var result := OBJECT_CODEC_SCRIPT.write_object_records(final_path, metadata, objects)
	if result.get("ok", false):
		last_export_path = final_path
	return result


func get_world_objects() -> Array:
	return _collect_exportable_objects()


func _collect_exportable_objects() -> Array:
	var nodes: Array = []
	for child in _objects_root().get_children():
		if child is MeshInstance3D:
			nodes.append(child)

	nodes.sort_custom(func(a: Node, b: Node) -> bool:
		var a_idx := int(a.get("mu_object_index"))
		var b_idx := int(b.get("mu_object_index"))
		if a_idx == b_idx:
			return String(a.name).naturalnocasecmp_to(String(b.name)) < 0
		return a_idx < b_idx
	)
	return nodes


func _get_object_source_file_name(type_id: int, bmd_path: String) -> String:
	if not bmd_path.is_empty():
		return bmd_path.get_file()
	if world_index == 1 and WORLD1_MAPPING.has(type_id):
		return "%s.bmd" % str(WORLD1_MAPPING[type_id])
	return "Object%02d.bmd" % (type_id + 1)


func _make_unique_object_name(base_name: String, name_counts: Dictionary) -> String:
	var clean_name: String = base_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Object"
	var current_count: int = int(name_counts.get(clean_name, 0))
	name_counts[clean_name] = current_count + 1
	if current_count == 0:
		return clean_name
	return "%s_%03d" % [clean_name, current_count + 1]


func _apply_mu_transform(node: Node3D, record: Dictionary) -> void:
	var type_id := int(record.get("type", -1))
	var mu_pos: Vector3 = record.get("position", Vector3.ZERO)
	var mu_rot: Vector3 = record.get("rotation", Vector3.ZERO)
	var mu_scale := float(record.get("scale", 1.0))

	var godot_pos := Vector3(mu_pos.x, mu_pos.z, TERRAIN_WORLD_SIZE - mu_pos.y)
	if world_index == 95 and type_id in [5, 12, 13]:
		godot_pos.y += 15.0

	node.position = godot_pos
	node.quaternion = _get_base_rotation() * _mu_rotation_to_quaternion(mu_rot)
	node.scale = Vector3.ONE * mu_scale


func _godot_to_mu_position(godot_position: Vector3, type_id: int) -> Vector3:
	var y := godot_position.y
	if world_index == 95 and type_id in [5, 12, 13]:
		y -= 15.0
	return Vector3(
		godot_position.x,
		TERRAIN_WORLD_SIZE - godot_position.z,
		y
	)


func _mu_rotation_to_quaternion(mu_rotation: Vector3) -> Quaternion:
	var ax := deg_to_rad(mu_rotation.x)
	var ay := deg_to_rad(mu_rotation.y)
	var az := deg_to_rad(mu_rotation.z)
	var half_x := ax * 0.5
	var half_y := ay * 0.5
	var half_z := az * 0.5
	var sx := sin(half_x)
	var cx := cos(half_x)
	var sy := sin(half_y)
	var cy := cos(half_y)
	var sz := sin(half_z)
	var cz := cos(half_z)

	return Quaternion(
		sx * cy * cz - cx * sy * sz,
		cx * sy * cz + sx * cy * sz,
		cx * cy * sz - sx * sy * cz,
		cx * cy * cz + sx * sy * sz
	).normalized()


func _godot_to_mu_rotation(world_quaternion: Quaternion) -> Vector3:
	var mu_quaternion := _get_base_rotation().inverse() * world_quaternion
	var euler := Basis(mu_quaternion).get_euler(EULER_ORDER_XYZ)
	return Vector3(
		rad_to_deg(euler.x),
		rad_to_deg(euler.y),
		rad_to_deg(euler.z)
	)


func _resolve_bmd_path(type_id: int) -> String:
	var object_dir: String = "%sObject%d/" % [_normalized_data_path(), world_index]
	var numeric_name1: String = "Object%02d.bmd" % (type_id + 1)
	var numeric_name2: String = "Object%d.bmd" % (type_id + 1)
	var candidates: Array[String] = [numeric_name1, numeric_name2]

	if world_index == 1 and WORLD1_MAPPING.has(type_id):
		var mapped_name: String = str(WORLD1_MAPPING[type_id])
		candidates.append(mapped_name + ".bmd")
		candidates.append(mapped_name.to_upper() + ".bmd")
		candidates.append(mapped_name.to_lower() + ".bmd")

	for candidate in candidates:
		var full_path: String = object_dir + candidate
		if FileAccess.file_exists(full_path):
			return full_path

	var dir := DirAccess.open(object_dir)
	if dir == null:
		return ""

	for candidate in candidates:
		var lower_candidate: String = candidate.to_lower()
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.to_lower() == lower_candidate:
				dir.list_dir_end()
				return object_dir + file_name
			file_name = dir.get_next()
		dir.list_dir_end()

	return ""


func _apply_missing_model_placeholder(node: MeshInstance3D) -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 120.0
	node.mesh = box

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.1, 0.1, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = material


func _ensure_container_nodes() -> void:
	if _terrain_root() == null:
		var terrain_root := Node3D.new()
		terrain_root.name = "TerrainPreview"
		add_child(terrain_root)
		_assign_scene_owner(terrain_root)

	if _objects_root() == null:
		var objects_root := Node3D.new()
		objects_root.name = "WorldObjects"
		add_child(objects_root)
		_assign_scene_owner(objects_root)


func _terrain_root() -> Node3D:
	return get_node_or_null("TerrainPreview") as Node3D


func _objects_root() -> Node3D:
	return get_node_or_null("WorldObjects") as Node3D


func _assign_scene_owner(node: Node) -> void:
	var tree := get_tree()
	if tree and tree.edited_scene_root:
		node.owner = tree.edited_scene_root
	elif owner:
		node.owner = owner
	elif self != node:
		node.owner = self


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.free()


func _normalized_data_path() -> String:
	return data_path if data_path.ends_with("/") else data_path + "/"


func _get_base_rotation() -> Quaternion:
	return Quaternion(Vector3.RIGHT, deg_to_rad(-90.0))


func _queue_auto_load() -> void:
	if not Engine.is_editor_hint() or not auto_load_in_editor:
		return
	if _auto_load_queued:
		return

	var signature := "%s|%s|%s|%s|%s" % [
		str(world_index),
		_normalized_data_path(),
		get_source_obj_path(),
		str(load_terrain_preview),
		str(load_objects_from_source),
	]
	if signature == _last_auto_load_signature:
		return

	_auto_load_queued = true
	call_deferred("_run_auto_load", signature)


func _run_auto_load(signature: String) -> void:
	_auto_load_queued = false
	if not is_inside_tree():
		return
	if not Engine.is_editor_hint() or not auto_load_in_editor:
		return
	if signature == _last_auto_load_signature:
		return

	_last_auto_load_signature = signature
	import_world()
