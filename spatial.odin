package spatial_hash

import "core:math"
import ln "core:math/linalg"
import "core:mem"

SpatialHash :: struct($T: typeid) {
	spacing:      f32,
	table_size:   u32,
	cell_start:   []u32,
	cell_entries: []u32,
	query_ids:    []u32,
	query_size:   u32,
	pos_fn:       proc(item: ^T) -> [2]f32,
}

init :: proc(
	self: ^SpatialHash($T),
	spacing: f32,
	max_objects: u32,
	pos_fn: proc(item: ^T) -> [2]f32,
) {
	assert(pos_fn != nil, "position function was nil")
	desired_size := 2 * max_objects
	table_size := u32(1) << uint(math.log2(f32(desired_size)) + 1)
	if table_size < 2 {table_size = 2}
	self^ = {
		spacing      = spacing,
		table_size   = table_size,
		cell_start   = make([]u32, table_size + 1),
		cell_entries = make([]u32, max_objects),
		query_ids    = make([]u32, max_objects),
		pos_fn       = pos_fn,
	}
}

free :: proc(self: ^SpatialHash($T)) {
	delete(self.query_ids)
	delete(self.cell_entries)
	delete(self.cell_start)
}

create :: proc(self: ^SpatialHash($T), items: []T) {
	mem.zero_slice(self.cell_start[:])
	mem.zero_slice(self.cell_entries[:])

	table_size_mask := self.table_size - 1
	for &item in items {
		pos := self.pos_fn(&item)
		h := hash_pos(self.spacing, table_size_mask, pos)
		self.cell_start[h] += 1
	}

	start := u32(0)
	for i in 0 ..< self.table_size {
		start += self.cell_start[i]
		self.cell_start[i] = start
	}
	self.cell_start[self.table_size] = start

	for &item, i in items {
		pos := self.pos_fn(&item)
		h := hash_pos(self.spacing, table_size_mask, pos)
		self.cell_start[h] -= 1
		self.cell_entries[self.cell_start[h]] = u32(i)
	}
}

query :: proc(self: ^SpatialHash($T), pos: [2]f32, max_dist: f32) {
	pos0 := int_coord(self.spacing, pos - max_dist)
	pos1 := int_coord(self.spacing, pos + max_dist)

	mask := self.table_size - 1
	self.query_size = 0
	for x := pos0.x; x <= pos1.x; x += 1 {
		for y := pos0.y; y <= pos1.y; y += 1 {
			h := hash(mask, x, y)
			start := self.cell_start[h]
			end := self.cell_start[h + 1]

			for i := start; i < end; i += 1 {
				if self.query_size >= u32(len(self.query_ids)) {return}
				self.query_ids[self.query_size] = self.cell_entries[i]
				self.query_size += 1
			}
		}
	}
}


// utils
@(private = "file")
int_coord :: proc(spacing: f32, pos: [2]f32) -> [2]i32 {
	return ln.array_cast(ln.floor(pos / spacing), i32)
}

@(private = "file")
hash_pos :: proc(spacing: f32, table_size_mask: u32, pos: [2]f32) -> u32 {
	int_coords := int_coord(spacing, pos)
	return hash(table_size_mask, int_coords.x, int_coords.y)
}


@(private = "file")
hash :: proc(table_size_mask: u32, x, y: i32) -> u32 {
	// Treat as unsigned to avoid signed overflow issues
	ux := u32(x) * 73856093
	uy := u32(y) * 19349663
	h := ux ~ uy

	// Final bit mixer (very important for power-of-two masks)
	h ~= h >> 16
	h *= 0x85ebca6b
	h ~= h >> 13
	h *= 0xc2b2ae35
	h ~= h >> 16

	return h & table_size_mask
}
