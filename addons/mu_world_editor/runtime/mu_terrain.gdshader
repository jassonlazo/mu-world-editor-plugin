shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Terrain Metrics
// The terrain plane is 25600 x 25600 MU units (256 tiles * 100 MU/tile),
// matching the bmd-viewer convention. Heights from OZB are 0..255, so a
// scale of 4 gives a max swell of ~1000 MU which looks right for the
// ship/water area.
uniform float height_scale = 382.5;
uniform float uv_scale = 1.0;

// Data Maps (From MuTerrainLoader)
uniform sampler2D heightmap_tex : filter_linear, repeat_disable;
uniform sampler2D att_tex : filter_nearest, repeat_disable;
uniform sampler2D layer1_tex : filter_nearest, repeat_disable;
uniform sampler2D layer2_tex : filter_nearest, repeat_disable;
uniform sampler2D alpha_tex : filter_nearest, repeat_disable;

// Tile Texture Array (All ExtTile01-16 packed)
uniform sampler2DArray tile_texture_array : filter_linear_mipmap, repeat_enable;
uniform int tile_count = 14;  // We pack 14 tiles in MuTerrain.gd; clamp indices.

// Special Effects (Water animation)
uniform float water_speed = 0.15;
uniform float distortion_amplitude = 0.2;
uniform vec2 water_flow_direction = vec2(0.0, 1.0);

varying vec2 base_uv;
varying vec2 tile_uv;

void vertex() {
	base_uv = UV;

	// Sample height mapping from OZB (R channel mapped to actual Y bounds)
	float h = texture(heightmap_tex, base_uv).r;
	float final_h = h * height_scale;

	// Add special height offset (1200 MU) if attribute bit 64 (0x40) is set.
	float att = texture(att_tex, base_uv).r;
	if (int(att * 255.1) >= 64) {
		final_h += 1200.0;
	}
	VERTEX.y += final_h;

	// Compute normals for vertex displacement. 
	// We sample neighbors (1.0/256.0 offset) to find the slope.
	float eps = 1.0 / 256.0;
	float hr = texture(heightmap_tex, base_uv + vec2(eps, 0.0)).r * height_scale;
	float hu = texture(heightmap_tex, base_uv + vec2(0.0, eps)).r * height_scale;
	
	// Add potential neighbor offsets
	float att_r = texture(att_tex, base_uv + vec2(eps, 0.0)).r;
	if (int(att_r * 255.1) >= 64) hr += 1200.0;
	float att_u = texture(att_tex, base_uv + vec2(0.0, eps)).r;
	if (int(att_u * 255.1) >= 64) hu += 1200.0;

	// In MU, each tile is 100x100 units.
	vec3 v1 = vec3(100.0, hr - final_h, 0.0);
	vec3 v2 = vec3(0.0, hu - final_h, -100.0); // flip Z to match Godot PlaneMesh orientation
	NORMAL = normalize(cross(v1, v2));

	// Prepare UV for individual tiles
	tile_uv = UV * 255.0 * uv_scale;
}

void fragment() {
	// MAP layers come already decrypted from MuTerrainLoader (C++ side
	// handles both the legacy XOR FileCryptor and the Season 6 ModulusCryptor).
	// Clamp the indices into the valid tile range to avoid sampling junk.
	float max_idx = float(tile_count - 1);
	float index1 = clamp(texture(layer1_tex, base_uv).r * 255.0, 0.0, max_idx);
	float index2 = clamp(texture(layer2_tex, base_uv).r * 255.0, 0.0, max_idx);
	float alpha  = texture(alpha_tex, base_uv).r;

	vec2 dynamic_uv = tile_uv;

	vec4 col1 = texture(tile_texture_array, vec3(dynamic_uv, index1));
	vec4 col2 = texture(tile_texture_array, vec3(dynamic_uv, index2));

	ALBEDO = mix(col1.rgb, col2.rgb, alpha);

	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
}

