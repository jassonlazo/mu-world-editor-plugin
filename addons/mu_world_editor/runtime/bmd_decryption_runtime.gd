const KEY_DELTA = [0xc3efe9db, 0x44626b02, 0x79e27c8a, 0x78df30ec, 0x715ea49e, 0xc785da0a, 0xe04ef22a, 0xe5c40957]
const LEA_KEY = [
	0xcc, 0x50, 0x45, 0x13, 0xc2, 0xa6, 0x57, 0x4e, 
	0xd6, 0x9a, 0x45, 0x89, 0xbf, 0x2f, 0xbc, 0xd9, 
	0x39, 0xb3, 0xb3, 0xbd, 0x50, 0xbd, 0xcc, 0xb6, 
	0x85, 0x46, 0xd1, 0xd6, 0x16, 0x54, 0xe0, 0x87
]
const MAP_XOR_KEY = [
	0xD1, 0x73, 0x52, 0xF6, 0xD2, 0x9A, 0xCB, 0x27,
	0x3E, 0xAF, 0x59, 0x31, 0x37, 0xB3, 0xE7, 0xA2
]

static func rol32(x: int, n: int) -> int:
	n = n & 31
	var left = (x << n) & 0xFFFFFFFF
	var right = (x >> ((32 - n) & 31)) & 0xFFFFFFFF
	return left | right

static func ror32(x: int, n: int) -> int:
	n = n & 31
	var right = (x >> n) & 0xFFFFFFFF
	var left = (x << ((32 - n) & 31)) & 0xFFFFFFFF
	return left | right

static func le_to_u32(p: PackedByteArray, offset: int) -> int:
	var b0 = p[offset]
	var b1 = p[offset+1]
	var b2 = p[offset+2]
	var b3 = p[offset+3]
	return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)

static func u32_to_le(v: int, p: PackedByteArray, offset: int):
	p[offset] = v & 0xFF
	p[offset+1] = (v >> 8) & 0xFF
	p[offset+2] = (v >> 16) & 0xFF
	p[offset+3] = (v >> 24) & 0xFF

static func key_schedule_256(key_words: Array, rk_out: Array):
	var T = key_words.duplicate()
	for i in range(32):
		var d = KEY_DELTA[i & 7]
		var s = (i * 6) & 7
		T[(s + 0) & 7] = rol32((T[(s + 0) & 7] + rol32(d, i + 0)) & 0xFFFFFFFF, 1)
		T[(s + 1) & 7] = rol32((T[(s + 1) & 7] + rol32(d, i + 1)) & 0xFFFFFFFF, 3)
		T[(s + 2) & 7] = rol32((T[(s + 2) & 7] + rol32(d, i + 2)) & 0xFFFFFFFF, 6)
		T[(s + 3) & 7] = rol32((T[(s + 3) & 7] + rol32(d, i + 3)) & 0xFFFFFFFF, 11)
		T[(s + 4) & 7] = rol32((T[(s + 4) & 7] + rol32(d, i + 4)) & 0xFFFFFFFF, 13)
		T[(s + 5) & 7] = rol32((T[(s + 5) & 7] + rol32(d, i + 5)) & 0xFFFFFFFF, 17)
		
		rk_out[i * 6 + 0] = T[(s + 0) & 7]
		rk_out[i * 6 + 1] = T[(s + 1) & 7]
		rk_out[i * 6 + 2] = T[(s + 2) & 7]
		rk_out[i * 6 + 3] = T[(s + 3) & 7]
		rk_out[i * 6 + 4] = T[(s + 4) & 7]
		rk_out[i * 6 + 5] = T[(s + 5) & 7]

static func round_dec(s: Array, t: Array, rk6: Array):
	t[0] = s[3]
	t[1] = (((ror32(s[0], 9) - (t[0] ^ rk6[0])) & 0xFFFFFFFF) ^ rk6[1])
	t[2] = (((rol32(s[1], 5) - (t[1] ^ rk6[2])) & 0xFFFFFFFF) ^ rk6[3])
	t[3] = (((rol32(s[2], 3) - (t[2] ^ rk6[4])) & 0xFFFFFFFF) ^ rk6[5])

static func decrypt_lea(buffer: PackedByteArray, offset: int, length: int):
	if offset + length > buffer.size() or (length % 16) != 0:
		return
		
	var key_words = []
	key_words.resize(8)
	var lea_key_bytes = PackedByteArray(LEA_KEY)
	for i in range(8):
		key_words[i] = le_to_u32(lea_key_bytes, i * 4)
		
	var RK = []
	RK.resize(192)
	key_schedule_256(key_words, RK)
	
	var state = [0, 0, 0, 0]
	var next_s = [0, 0, 0, 0]
	var rk6 = [0, 0, 0, 0, 0, 0]
	
	var off = 0
	while off < length:
		var ptr = offset + off
		for i in range(4):
			state[i] = le_to_u32(buffer, ptr + i * 4)
			
		for r in range(32):
			var idx = 31 - r
			for k in range(6):
				rk6[k] = RK[idx * 6 + k]
			round_dec(state, next_s, rk6)
			for k in range(4):
				state[k] = next_s[k]
				
		for i in range(4):
			u32_to_le(state[i], buffer, ptr + i * 4)
			
		off += 16

static func decrypt_xor(buffer: PackedByteArray, offset: int, length: int):
	if offset + length > buffer.size():
		return
	var mapKey = 0x5E
	for i in range(length):
		var current_val = buffer[offset + i]
		var sub = (current_val ^ MAP_XOR_KEY[i % 16]) - mapKey
		# Godot 4 bytes implicitly wrap if inserted into PackedByteArray, but let's be safe
		buffer[offset + i] = int(sub) & 0xFF
		mapKey = (current_val + 0x3D) & 0xFF
