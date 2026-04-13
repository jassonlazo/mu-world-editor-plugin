@tool
extends RefCounted
class_name MuObjectCodec

const XOR_KEY := [
	0xD1, 0x73, 0x52, 0xF6, 0xD2, 0x9A, 0xCB, 0x27,
	0x3E, 0xAF, 0x59, 0x31, 0x37, 0xB3, 0xE7, 0xA2,
]


static func load_object_records(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"message": "Object file not found: %s" % path,
		}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"message": "Could not open object file: %s" % path,
		}

	var encrypted := file.get_buffer(file.get_length())
	var decoded := _decrypt_bytes(encrypted)
	if decoded.size() < 4:
		return {
			"ok": false,
			"message": "Object file is too small: %s" % path,
		}

	var header := StreamPeerBuffer.new()
	header.big_endian = false
	header.data_array = decoded
	header.seek(0)
	var version := header.get_u8()
	var map_number := header.get_u8()
	var count := header.get_u16()
	var struct_size := _get_struct_size(version)
	if struct_size <= 0:
		return {
			"ok": false,
			"message": "Unsupported EncTerrain version %d in %s" % [version, path],
		}

	var available_records := int((decoded.size() - 4) / struct_size)
	var safe_count := min(count, available_records)
	var objects: Array = []
	var offset := 4

	for i in range(safe_count):
		var raw_record := decoded.slice(offset, offset + struct_size)
		var stream := StreamPeerBuffer.new()
		stream.big_endian = false
		stream.data_array = raw_record
		stream.seek(0)

		var type_id := stream.get_16()
		var position := Vector3(
			stream.get_float(),
			stream.get_float(),
			stream.get_float()
		)
		var rotation := Vector3(
			stream.get_float(),
			stream.get_float(),
			stream.get_float()
		)
		var scale := stream.get_float()

		objects.append({
			"index": i,
			"type": type_id,
			"position": position,
			"rotation": rotation,
			"scale": scale,
			"raw_record": raw_record,
		})
		offset += struct_size

	return {
		"ok": true,
		"path": path,
		"version": version,
		"map_number": map_number,
		"struct_size": struct_size,
		"count": safe_count,
		"objects": objects,
	}


static func write_object_records(path: String, metadata: Dictionary, objects: Array) -> Dictionary:
	var version := int(metadata.get("version", -1))
	var map_number := int(metadata.get("map_number", 0))
	var struct_size := int(metadata.get("struct_size", _get_struct_size(version)))
	if struct_size <= 0:
		return {
			"ok": false,
			"message": "Unsupported EncTerrain version for export: %s" % str(version),
		}

	var output_dir := path.get_base_dir()
	if not output_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))

	var decoded := PackedByteArray()
	decoded.resize(4 + objects.size() * struct_size)

	var header := StreamPeerBuffer.new()
	header.big_endian = false
	header.data_array = decoded
	header.seek(0)
	header.put_u8(version & 0xFF)
	header.put_u8(map_number & 0xFF)
	header.put_u16(objects.size())
	decoded = header.data_array

	var offset := 4
	for obj in objects:
		var raw_record: PackedByteArray = obj.get("raw_record", PackedByteArray())
		var record := raw_record.duplicate()
		record.resize(struct_size)

		var stream := StreamPeerBuffer.new()
		stream.big_endian = false
		stream.data_array = record
		stream.seek(0)
		stream.put_16(int(obj.get("type", 0)))

		var position: Vector3 = obj.get("position", Vector3.ZERO)
		var rotation: Vector3 = obj.get("rotation", Vector3.ZERO)
		var scale := float(obj.get("scale", 1.0))

		stream.seek(2)
		stream.put_float(position.x)
		stream.put_float(position.y)
		stream.put_float(position.z)
		stream.put_float(rotation.x)
		stream.put_float(rotation.y)
		stream.put_float(rotation.z)
		stream.put_float(scale)
		record = stream.data_array

		for i in range(struct_size):
			decoded[offset + i] = record[i]
		offset += struct_size

	var encrypted := _encrypt_bytes(decoded)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"message": "Could not write object file: %s" % path,
		}

	file.store_buffer(encrypted)
	return {
		"ok": true,
		"message": "Layout exported to %s (%d objects)." % [path, objects.size()],
		"path": path,
		"count": objects.size(),
	}


static func _get_struct_size(version: int) -> int:
	match version:
		0:
			return 30
		1:
			return 32
		2:
			return 33
		3:
			return 45
		4:
			return 46
		5:
			return 54
		_:
			return -1


static func _decrypt_bytes(buffer: PackedByteArray) -> PackedByteArray:
	var out := buffer.duplicate()
	var map_key := 0x5E
	for i in range(out.size()):
		var current := out[i]
		out[i] = (((current ^ XOR_KEY[i % XOR_KEY.size()]) - map_key) & 0xFF)
		map_key = (current + 0x3D) & 0xFF
	return out


static func _encrypt_bytes(buffer: PackedByteArray) -> PackedByteArray:
	var out := buffer.duplicate()
	var map_key := 0x5E
	for i in range(out.size()):
		var plain: int = out[i]
		var encrypted: int = (((plain + map_key) & 0xFF) ^ int(XOR_KEY[i % XOR_KEY.size()])) & 0xFF
		out[i] = encrypted
		map_key = (encrypted + 0x3D) & 0xFF
	return out
