@tool
extends MeshInstance3D

const TERRAIN_BMD_LOADER := preload("res://addons/mu_world_editor/runtime/terrain_bmd_loader_runtime.gd")

@export var bmd_path: String = ""
@export_storage var mu_object_index: int = -1
@export_storage var mu_type_id: int = -1
@export_storage var mu_world_index: int = -1
@export_storage var mu_source_obj_path: String = ""
@export_storage var mu_source_file_name: String = ""
@export_storage var mu_raw_record: PackedByteArray = PackedByteArray()
@export_storage var mu_original_position: Vector3 = Vector3.ZERO
@export_storage var mu_original_rotation: Vector3 = Vector3.ZERO
@export_storage var mu_original_scale: float = 1.0

# --- Static shared caches ---
static var _mesh_cache = {}
static var _material_cache = {}

func _ready():
	if bmd_path != "":
		load_bmd(bmd_path)

func load_bmd(path: String):
	if _mesh_cache.has(path):
		mesh = _mesh_cache[path]
		return

	var bmd_data = TERRAIN_BMD_LOADER.load_bmd(path)
	if bmd_data.is_empty(): 
		print("[ERROR] BMDInstance: Failed to load BMD via TerrainBMDLoader: ", path)
		return
	
	var meshes = bmd_data["meshes"]
	var global_bones = bmd_data["global_bones"] # Already computed by the script!
	
	var tex_loader = ClassDB.instantiate("MuTextureLoader")
	var base_dir = path.get_base_dir() + "/"
	var godot_mesh = ArrayMesh.new()
	var surface_idx := 0
	
	for i in range(meshes.size()):
		var m = meshes[i]
		var verts_out = PackedVector3Array()
		var norms_out = PackedVector3Array()
		var uvs_out = PackedVector2Array()
		
		# In TerrainBMDLoader, tris are called 'tris' and have 'v', 'n', 't' arrays
		for f in range(m.tris.size()):
			var tri = m.tris[f]
			var v = tri.v; var n = tri.n; var t = tri.t
			# MU winding: 0, 2, 1
			_push_vert(m, global_bones, verts_out, norms_out, uvs_out, v[0], n[0], t[0])
			_push_vert(m, global_bones, verts_out, norms_out, uvs_out, v[2], n[2], t[2])
			_push_vert(m, global_bones, verts_out, norms_out, uvs_out, v[1], n[1], t[1])
			
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts_out
		arrays[Mesh.ARRAY_NORMAL] = norms_out
		arrays[Mesh.ARRAY_TEX_UV] = uvs_out
		
		godot_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# Use 'tex_path' from the bmd_data meshes
		var mat = _build_material(tex_loader, base_dir, m.tex_path)
		godot_mesh.surface_set_material(surface_idx, mat)
		surface_idx += 1
		
	mesh = godot_mesh
	_mesh_cache[path] = godot_mesh
	
	# Crear colisión para selección
	if not Engine.is_editor_hint():
		_create_collision()

func _create_collision():
	# Limpiar colisiones anteriores
	for child in get_children():
		if child is Area3D or child is CollisionShape3D:
			child.queue_free()
	
	if mesh == null:
		return
	
	# Crear Area3D para detección de rayos
	var area = Area3D.new()
	area.name = "SelectionArea"
	area.input_ray_pickable = true
	area.monitoring = false
	area.monitorable = true
	
	# Crear forma de colisión basada en el AABB del mesh
	var shape = BoxShape3D.new()
	var aabb = mesh.get_aabb()
	if aabb.size.length_squared() > 0:
		# Ajustar tamaño de la caja al AABB
		shape.size = aabb.size * 1.1  # Un poco más grande para facilitar selección
		
		var collision_shape = CollisionShape3D.new()
		collision_shape.shape = shape
		
		# Posicionar el área en el centro del AABB
		area.position = aabb.position + aabb.size * 0.5
		area.add_child(collision_shape)
	
	add_child(area)

func _push_vert(m, global_bones, verts, norms, uvs, vi, ni, ti):
	var v_data = m.verts[vi]
	var n_data = m.norms[ni]
	var bone_tx = global_bones[v_data.node]
	
	verts.append(bone_tx * v_data.pos)
	norms.append((bone_tx.basis * n_data.norm).normalized())
	uvs.append(m.texs[ti])

func _build_material(tex_loader, base_dir: String, tex_name: String) -> StandardMaterial3D:
	var cache_key = base_dir + tex_name
	if _material_cache.has(cache_key): return _material_cache[cache_key]

	var mat = StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color.WHITE

	if tex_name != "":
		var tex = _resolve_texture(tex_loader, base_dir, tex_name)
		if tex:
			mat.albedo_texture = tex
			var tex_l = tex_name.to_lower()
			
			# If it's a known transparent type:
			if "curtain" in tex_l or "grass" in tex_l or "leaf" in tex_l or "banner" in tex_l or "fence" in tex_l:
				# Use Additive blending for .ozj (JPGs) since they have no alpha channel
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.blend_mode = StandardMaterial3D.BLEND_MODE_ADD
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED 
			elif tex_l.ends_with(".ozt") or tex_l.ends_with(".tga"):
				# TGA/OZT usually have real alpha channel
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.5
		else:
			# tex_name known but file not found → magenta debug color
			mat.albedo_color = Color(1, 0, 1, 1) # MAGENTA = tex_name known but file missing
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			print("[WARN] BMDInstance: Texture not found: ", base_dir, tex_name)
	
	_material_cache[cache_key] = mat
	return mat

func _resolve_texture(tex_loader, base_dir: String, tex_name: String) -> ImageTexture:
	var no_ext = tex_name.get_basename()
	var candidates = [
		base_dir + no_ext + ".ozj", base_dir + no_ext + ".ozt",
		base_dir + no_ext + ".OZJ", base_dir + no_ext + ".OZT",
		base_dir + tex_name
	]
	
	# Try all folders to find a file first
	var found_path = ""
	for cand in candidates:
		if FileAccess.file_exists(cand):
			found_path = cand
			break
			
	if found_path == "":
		var fallbacks = ["res://Data/Object1/", "res://Data/World1/"]
		for fdir in fallbacks:
			var fcand = fdir + no_ext + ".ozj"
			if FileAccess.file_exists(fcand):
				found_path = fcand
				break

	if found_path != "":
		return tex_loader.load_texture(found_path)

	return null
