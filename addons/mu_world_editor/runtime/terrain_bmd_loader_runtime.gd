extends RefCounted

const BMD_DECRYPTION := preload("res://addons/mu_world_editor/runtime/bmd_decryption_runtime.gd")

static func load_bmd(file_path: String) -> Dictionary:
	var f = FileAccess.open(file_path, FileAccess.READ)
	if not f: return {}
	
	var raw = f.get_buffer(f.get_length())
	f.close()
	if raw.size() < 4: return {}
	
	# BMD Signature check
	var version = raw[3]
	if raw[0] != 0x42 or raw[1] != 0x4D: # 'BM'
		# Apply simple 0x5E XOR if completely raw (very old format)
		for i in range(raw.size()):
			raw[i] = raw[i] ^ 0x5E
		version = raw[3]
			
	if version == 12 or version == 15:
		var stream_temp = StreamPeerBuffer.new()
		stream_temp.data_array = raw
		stream_temp.big_endian = false
		stream_temp.seek(4)
		var enc_size = stream_temp.get_32()
		
		# Decrypt payload inline
		if enc_size + 8 <= raw.size():
			if version == 12:
				BMD_DECRYPTION.decrypt_xor(raw, 8, enc_size)
			elif version == 15:
				BMD_DECRYPTION.decrypt_lea(raw, 8, enc_size)
				
			# Shift decrypted data down 4 bytes (removing enc_size integer)
			# to simulate C# continuous linear stream mapping
			for i in range(enc_size):
				raw[4 + i] = raw[8 + i]

	var stream = StreamPeerBuffer.new()
	stream.data_array = raw
	stream.big_endian = false
	
	stream.seek(0)
	var magic = stream.get_string(3)
	if magic != "BMD": 
		print("[ERROR] TerrainBMDLoader: Invalid magic '", magic, "' for ", file_path)
		return {}

	stream.seek(4)
	var name = _read_string(stream, 32)
	var mesh_count = stream.get_u16()
	var bone_count = stream.get_u16()
	var action_count = stream.get_u16()
	
	var meshes = []
	for m in range(mesh_count):
		var num_verts = stream.get_16()
		var num_norms = stream.get_16()
		var num_texs = stream.get_16()
		var num_tris = stream.get_16()
		var tex_idx = stream.get_16()
		
		var verts = []
		for i in range(num_verts):
			var node = stream.get_16()
			stream.get_16() # pad
			verts.append({"node": node, "pos": Vector3(stream.get_float(), stream.get_float(), stream.get_float())})
			
		var norms = []
		for i in range(num_norms):
			var node = stream.get_16()
			stream.get_16() # pad
			var n = Vector3(stream.get_float(), stream.get_float(), stream.get_float())
			var bind = stream.get_16()
			stream.get_16() # pad
			norms.append({"node": node, "norm": n})
			
		var texs = []
		for i in range(num_texs):
			texs.append(Vector2(stream.get_float(), stream.get_float()))
			
		var tris = []
		for i in range(num_tris):
			var poly = stream.get_u8()
			stream.seek(stream.get_position() + 1) # 1 byte pad (TS ref: vertexIndex @ start+2)
			var v_idx = [stream.get_16(), stream.get_16(), stream.get_16(), stream.get_16()] # bytes 2-9
			var n_idx = [stream.get_16(), stream.get_16(), stream.get_16(), stream.get_16()] # bytes 10-17
			var t_idx = [stream.get_16(), stream.get_16(), stream.get_16(), stream.get_16()] # bytes 18-25
			stream.seek(stream.get_position() + 38) # skip bytes 26-63: lightmap(32)+lm_idx(2)+pad(4)
			tris.append({"poly": poly, "v": v_idx, "n": n_idx, "t": t_idx})
			
		var tex_path = _read_string(stream, 32)
		
		meshes.append({
			"verts": verts,
			"norms": norms,
			"texs": texs,
			"tris": tris,
			"tex_path": tex_path
		})
		
	var actions = []
	for a in range(action_count):
		var num_keys = stream.get_16()
		var lock_pos = stream.get_u8() > 0
		if lock_pos:
			stream.seek(stream.get_position() + num_keys * 12)
		actions.append({"keys": num_keys})
		
	var bones = []
	for b in range(bone_count):
		var dummy = stream.get_u8() > 0
		if dummy:
			bones.append({"dummy": true, "parent": -1, "pos": Vector3.ZERO, "quat": Quaternion()})
			continue
			
		var bone_name = _read_string(stream, 32)
		var parent = stream.get_16()
		var act0_pos = Vector3.ZERO
		var act0_quat = Quaternion()
		
		for a in range(action_count):
			var keys = actions[a].keys
			if keys == 0: continue
			
			var first_pos = Vector3.ZERO
			for k in range(keys):
				var p = Vector3(stream.get_float(), stream.get_float(), stream.get_float())
				if k == 0 and a == 0: first_pos = p
				
			var first_rot = Vector3.ZERO
			for k in range(keys):
				var r = Vector3(stream.get_float(), stream.get_float(), stream.get_float())
				if k == 0 and a == 0: first_rot = r
				
			if a == 0:
				act0_pos = first_pos
				act0_quat = _bmd_angle_to_quat(first_rot)
				
		bones.append({"dummy": false, "parent": parent, "pos": act0_pos, "quat": act0_quat})
		
	# Compute global bone transforms (World Matrix for frame 0)
	var global_bones = []
	for i in range(bones.size()):
		global_bones.append(Transform3D())
		
	for i in range(bones.size()):
		var b = bones[i]
		if b.dummy: continue
		var local_tx = Transform3D(Basis(b.quat), b.pos)
		if b.parent >= 0 and b.parent < i: # parents are always defined before children
			global_bones[i] = global_bones[b.parent] * local_tx
		else:
			global_bones[i] = local_tx

	return {"name": name, "meshes": meshes, "global_bones": global_bones}

static func _read_string(stream: StreamPeerBuffer, length: int) -> String:
	var bytes = stream.get_partial_data(length)[1]
	var s = ""
	for b in bytes:
		if b == 0: break
		s += char(b)
	return s

static func _bmd_angle_to_quat(euler: Vector3) -> Quaternion:
	# Same logic as TS bmdAngleToQuaternion
	var half_x = (euler.x) * 0.5
	var half_y = (euler.y) * 0.5
	var half_z = (euler.z) * 0.5

	var sin_x = sin(half_x); var cos_x = cos(half_x)
	var sin_y = sin(half_y); var cos_y = cos(half_y)
	var sin_z = sin(half_z); var cos_z = cos(half_z)

	var w = cos_x * cos_y * cos_z + sin_x * sin_y * sin_z
	var x = sin_x * cos_y * cos_z - cos_x * sin_y * sin_z
	var y = cos_x * sin_y * cos_z + sin_x * cos_y * sin_z
	var z = cos_x * cos_y * sin_z - sin_x * sin_y * cos_z
	
	return Quaternion(x, y, z, w).normalized()
