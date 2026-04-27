@tool
extends Node3D

@export var world_index: int = 95
@export var data_path: String = "res://Data/"

var _loader
var _mesh_instance: MeshInstance3D
var _loaded_world_index: int = -1

# Per-world tile slot lists. The byte values stored in EncTerrain*.map's
# layer1/layer2 are indices into the tile array passed to the shader, so the
# order here matters. World 1 (Lorencia) is the legacy default; add an entry
# whenever a world ships with a different naming scheme. If a world is not in
# this dict, we fall back to scanning the world directory for Tile*.OZJ/OZT
# files in alphabetical order — good enough to render *something* even when
# the canonical slot order is unknown.
const WORLD_TILE_NAMES := {
	1: [
		"TileGrass01", "TileGrass02", "TileGround01", "TileGround02", "TileGround03",
		"TileWater01", "TileWood01", "TileRock01", "TileRock02", "TileRock03",
		"TileRock04", "TileRock05", "TileRock06", "TileRock07",
	],
}
const DEFAULT_TILE_NAMES: Array = [
	"TileGrass01", "TileGrass02", "TileGround01", "TileGround02", "TileGround03",
	"TileWater01", "TileWood01", "TileRock01", "TileRock02", "TileRock03",
	"TileRock04", "TileRock05", "TileRock06", "TileRock07",
]

func _ready():
	print("[DEBUG] MuTerrain: _ready starting for World ", world_index)
	# Defer the auto-load by one frame so that scenes which embed MuTerrain as
	# a static .tscn child (Game.tscn) have a chance to call load_world(real_id)
	# from their own _ready *before* the auto-load fires. The idempotency guard
	# in load_world() makes the deferred call a no-op if the explicit one
	# already ran. Scenes that build the node at runtime (TerrainVisualizer,
	# Login) keep working unchanged because by the time the deferred call
	# resolves their world_index is already set.
	call_deferred("load_world")


# load_world can be called externally with an explicit world index, e.g. from
# Game.gd when the server tells us which map to enter. Idempotent: if the
# requested world is already loaded we no-op; if a different one is loaded we
# tear it down before reloading. The optional argument keeps backwards-compat
# with the auto-load path in _ready().
func load_world(p_world_index: int = -1):
	if p_world_index >= 0:
		world_index = p_world_index

	if _loaded_world_index == world_index:
		print("[DEBUG] MuTerrain: world ", world_index, " already loaded, skipping")
		return

	# Tear down any previous terrain so calling load_world(N) twice doesn't
	# stack two PlaneMeshes on top of each other.
	if _mesh_instance and is_instance_valid(_mesh_instance):
		_mesh_instance.queue_free()
		_mesh_instance = null

	if _loader == null:
		_loader = ClassDB.instantiate("MuTerrainLoader")
		if _loader == null:
			_loader = ClassDB.instantiate("MapReader")
		if _loader == null:
			push_error("MuTerrain: No GDExtension loader available")
			return

	print("[DEBUG] MuTerrain: load_world() started.")
	var world_dir = data_path + "World" + str(world_index) + "/"
	print("[DEBUG] MuTerrain: world_dir is: ", world_dir)
	
	var ozb_path = world_dir + "TerrainHeight.OZB"
	print("[DEBUG] MuTerrain: Checking OZB path: ", ozb_path)
	if not FileAccess.file_exists(ozb_path):

		push_error("MuTerrain: Heightmap not found at " + ozb_path)
		return
		
	print("[DEBUG] MuTerrain: Heightmap path is valid. Loading via GDExtension...")
	# OZB files are wrapped in a BMP header but with non-standard row padding,
	# so we always go through the C++ loader which knows the real layout.
	var heightmap_img: Image = _loader.load_ozb(ozb_path)
	print("[DEBUG] MuTerrain: _loader.load_ozb returned. Valid: ", heightmap_img != null)

	if heightmap_img == null:
		push_error("Failed to load TerrainHeight.OZB")
		return
		
	print("[DEBUG] MuTerrain: Heightmap Valid. Moving to MAP loading...")
	var map_path = world_dir + "EncTerrain" + str(world_index) + ".map"
	var map_textures: Dictionary = {}
	print("[DEBUG] MuTerrain: Checking MAP at: ", map_path)
	if FileAccess.file_exists(map_path):
		# Always go through the GDExtension loader. It now handles both
		# the legacy XOR FileCryptor AND the Season 6 ModulusCryptor (MAP\x01).
		print("[DEBUG] MuTerrain: Calling _loader.load_map(map_path)...")
		map_textures = _loader.load_map(map_path)
		print("[DEBUG] MuTerrain: MAP load returned. Empty: ", map_textures.is_empty())

	
	if map_textures.is_empty():
		push_warning("MuTerrain: Using fallback for MAP: " + map_path)
		var blank = Image.create(256, 256, false, Image.FORMAT_RGBA8)
		map_textures = {"layer1": blank, "layer2": blank, "alpha": blank}
		
	var layer1_img: Image = map_textures.get("layer1")
	var layer2_img: Image = map_textures.get("layer2")
	var alpha_img: Image = map_textures.get("alpha")
	
	var att_path = world_dir + "EncTerrain" + str(world_index) + ".att"
	var att_img: Image = null
	print("[DEBUG] MuTerrain: Checking ATT at: ", att_path)
	if FileAccess.file_exists(att_path):
		# Same as the MAP path: the GDExtension knows about both encryptions.
		print("[DEBUG] MuTerrain: Calling _loader.load_att(att_path)...")
		att_img = _loader.load_att(att_path)
		print("[DEBUG] MuTerrain: ATT load returned. Valid: ", att_img != null)
			
	if att_img == null:
		push_warning("MuTerrain: Using fallback for ATT: " + att_path)
		att_img = Image.create(256, 256, false, Image.FORMAT_R8)
	
	print("[DEBUG] MuTerrain: Defining PlaneMesh...")
	# 1:1 with the bmd-viewer: TERRAIN_SIZE * TERRAIN_SCALE = 256 * 100 MU.
	const TERRAIN_WORLD_SIZE := 25600.0
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(TERRAIN_WORLD_SIZE, TERRAIN_WORLD_SIZE)
	plane_mesh.subdivide_width = 255
	plane_mesh.subdivide_depth = 255
	
	print("[DEBUG] MuTerrain: Compiling/Setting up ShaderMaterial...")
	var shader_material = ShaderMaterial.new()
	var shader = load("res://addons/mu_world_editor/runtime/mu_terrain.gdshader")
	shader_material.shader = shader

	print("[DEBUG] MuTerrain: Passing heightmap and splat textures to shader...")
	shader_material.set_shader_parameter("heightmap_tex", ImageTexture.create_from_image(heightmap_img))
	shader_material.set_shader_parameter("att_tex", ImageTexture.create_from_image(att_img))
	shader_material.set_shader_parameter("layer1_tex", ImageTexture.create_from_image(layer1_img))
	shader_material.set_shader_parameter("layer2_tex", ImageTexture.create_from_image(layer2_img))
	shader_material.set_shader_parameter("alpha_tex", ImageTexture.create_from_image(alpha_img))

	var tex_loader = ClassDB.instantiate("MuTextureLoader")
	var tile_images: Array[Image] = []
	var mappings: Array = _resolve_tile_names(world_dir)
	print("[DEBUG] MuTerrain: resolved %d tile slots for world %d" % [mappings.size(), world_index])
	var tiles_loaded := 0
	for tile_name in mappings:
		var ozj_path = world_dir + tile_name + ".OZJ"
		var ozt_path = world_dir + tile_name + ".OZT"
		var tex: ImageTexture = null
		if FileAccess.file_exists(ozj_path):
			tex = tex_loader.load_texture(ozj_path)
		elif FileAccess.file_exists(ozt_path):
			tex = tex_loader.load_texture(ozt_path)

		if tex:
			tiles_loaded += 1
			var img = tex.get_image()
			img.convert(Image.FORMAT_RGBA8)
			if img.get_size() != Vector2i(256, 256):
				img.resize(256, 256)
			tile_images.append(img)
		else:
			# Use a magenta placeholder so missing tiles are obviously broken,
			# not invisible.
			var ph := Image.create(256, 256, false, Image.FORMAT_RGBA8)
			ph.fill(Color(1, 0, 1, 1))
			tile_images.append(ph)
	print("[DEBUG] MuTerrain: %d/%d tile textures loaded" % [tiles_loaded, mappings.size()])

	if tile_images.size() > 0:
		var tex_array = Texture2DArray.new()
		tex_array.create_from_images(tile_images)
		shader_material.set_shader_parameter("tile_texture_array", tex_array)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = plane_mesh
	if tiles_loaded > 0:
		_mesh_instance.material_override = shader_material
	else:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(1.0, 0.5, 0.0)
		fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh_instance.material_override = fallback
		print("[WARN] MuTerrasass aain: no tile textures, using orange fallback material")
	# Center the plane in the same coordinate space the decorator uses:
	# instances live at (x ∈ [0, 25600], y ∈ [0, 25600]), so the plane center
	# must be at (12800, 0, 12800).
	_mesh_instance.position = Vector3(TERRAIN_WORLD_SIZE * 0.5, 0, TERRAIN_WORLD_SIZE * 0.5)

	# IMPORTANT: PlaneMesh has a flat (zero-height) AABB in Y, so when the
	# vertex shader displaces vertices upward by heightmap*height_scale, Godot
	# still does frustum culling against the original (flat) bounds and ends
	# up culling the entire terrain off-screen at most camera angles. Force a
	# tall custom AABB so the renderer never culls us.
	_mesh_instance.custom_aabb = AABB(
		Vector3(-TERRAIN_WORLD_SIZE * 0.5, -5000, -TERRAIN_WORLD_SIZE * 0.5),
		Vector3(TERRAIN_WORLD_SIZE, 20000, TERRAIN_WORLD_SIZE))
	_mesh_instance.extra_cull_margin = 25600.0

	add_child(_mesh_instance)
	_loaded_world_index = world_index
	var mesh_pos := _mesh_instance.position
	if _mesh_instance.is_inside_tree():
		mesh_pos = _mesh_instance.global_position
	print("[DEBUG] MuTerrain: mesh position=", mesh_pos,
		  " AABB=", _mesh_instance.get_aabb(),
		  " custom_aabb=", _mesh_instance.custom_aabb)

# Returns the ordered list of tile slot basenames for the current world.
# Priority:
#   1. Explicit override in WORLD_TILE_NAMES
#   2. Auto-discovery: scan world_dir for Tile*.OZJ / Tile*.OZT (alphabetical)
#   3. DEFAULT_TILE_NAMES (Lorencia layout) as last resort
func _resolve_tile_names(world_dir: String) -> Array:
	if WORLD_TILE_NAMES.has(world_index):
		return WORLD_TILE_NAMES[world_index]

	var dir = DirAccess.open(world_dir)
	if dir == null:
		print("[WARN] MuTerrain: cannot open world dir for tile scan: ", world_dir)
		return DEFAULT_TILE_NAMES

	var found: Array = []
	var seen := {}
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var lower = fname.to_lower()
			if lower.begins_with("tile") and (lower.ends_with(".ozj") or lower.ends_with(".ozt")):
				var base = fname.get_basename()
				if not seen.has(base):
					seen[base] = true
					found.append(base)
		fname = dir.get_next()
	dir.list_dir_end()

	if found.is_empty():
		print("[WARN] MuTerrain: no Tile*.OZJ/OZT found in ", world_dir, ", using Lorencia defaults")
		return DEFAULT_TILE_NAMES

	found.sort()
	return found


func _is_file_encrypted(path: String) -> bool:
	var fa = FileAccess.open(path, FileAccess.READ)
	if not fa: return false
	if fa.get_length() < 4: return false
	fa.seek(3)
	var version = fa.get_8()
	return version == 0x01

func _attempt_manual_decrypt_map(path: String) -> Dictionary:
	print("[DEBUG] _attempt_manual_decrypt_map: starting for ", path)
	var fa = FileAccess.open(path, FileAccess.READ)
	if not fa: return {}
	var data = fa.get_buffer(fa.get_length())
	print("[DEBUG] _attempt_manual_decrypt_map: buffer size: ", data.size())
	
	var _xor_key = [0x98, 0xF2, 0x51, 0xD4, 0xAA, 0x11, 0x22, 0x33]
	if data.size() < 196612: 
		print("[ERROR] _attempt_manual_decrypt_map: File too small (", data.size(), "), need 196612.")
		return {}
		
	# Perform XOR on memory buffer 1:1 - TEMPORARILY DISABLED
	# for i in range(4, data.size()):
	# 	data[i] = data[i] ^ xor_key[i % xor_key.size()]
	
	print("[DEBUG] _attempt_manual_decrypt_map: XOR loop BYPASSED for testing.")

		
	var l1 = data.slice(4, 4+65536)
	var l2 = data.slice(4+65536, 4+131072)
	var alpha = data.slice(4+131072, 4+196608)
	
	print("[DEBUG] _attempt_manual_decrypt_map: Creating 3 R8 layers...")
	return {
		"layer1": Image.create_from_data(256, 256, false, Image.FORMAT_R8, l1),
		"layer2": Image.create_from_data(256, 256, false, Image.FORMAT_R8, l2),
		"alpha": Image.create_from_data(256, 256, false, Image.FORMAT_R8, alpha)
	}


func _attempt_manual_decrypt_att(path: String) -> Image:
	print("[DEBUG] _attempt_manual_decrypt_att: starting for ", path)
	var fa = FileAccess.open(path, FileAccess.READ)
	if not fa: return null
	var data = fa.get_buffer(fa.get_length())
	print("[DEBUG] _attempt_manual_decrypt_att: buffer sized ", data.size())
	
	# XOR decrpyt loop 1:1 - TEMPORARILY DISABLED TO DISCARD CRASH SOURCE
	# print("[DEBUG] _attempt_manual_decrypt_att: Entering XOR loop...")
	# var size = data.size()
	# for i in range(size):
	# 	if i % 50000 == 0:
	# 		print("[DEBUG] _attempt_manual_decrypt_att: Processing byte ", i, " of ", size)
	# 	data[i] = data[i] ^ 0xD1
	print("[DEBUG] _attempt_manual_decrypt_att: XOR loop BYPASSED for testing.")


	
	# Skip 'ATT' + Version (4 bytes) safely
	var offset = 0
	if data.size() >= 4 and data[0] == 65 and data[1] == 84 and data[2] == 84: # 'A', 'T', 'T'
		print("[DEBUG] _attempt_manual_decrypt_att: Detected 4-byte ATT header.")
		offset = 4
	
	var grid = data.slice(offset)
	print("[DEBUG] _attempt_manual_decrypt_att: Grid slice size: ", grid.size())
	
	if grid.size() < 65536:
		print("[ERROR] _attempt_manual_decrypt_att: Grid size insufficient (", grid.size(), ")")
		return null
		
	# Build R8 image (1 byte per pixel for attributes)
	print("[DEBUG] _attempt_manual_decrypt_att: Creating image from manual data...")
	var att = Image.create_from_data(256, 256, false, Image.FORMAT_R8, grid.slice(0, 65536))
	print("[DEBUG] _attempt_manual_decrypt_att: Image created. Valid: ", att != null)
	return att
