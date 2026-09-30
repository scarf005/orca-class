class_name Course
## The road machinery shared by every stage. The road starts out toward -Z and winds through bends;
## `d` is distance along it and `u` the offset to its right, so every point near the road maps to
## exactly one (d, u). The active stage (`Course.stage`) supplies its plan and its geography.

const STEP := 1.0 ## Spacing of the precomputed centerline samples.
const SMOOTH := 30 ## Curvature box-filter half width, in samples (applied twice).
const MAP_REACH := 260.0 ## How far from the road `to_course` resolves points through the lookup grid.
const MAP_CELL := 8.0

## The debug room swaps the valley for a flat, open floor.
static var flat := false

## The stage being played. Switching it rebuilds the centerline and the lookup grid.
static var stage: StageDef = Stage1.new()

## Centerline samples every STEP metres: position (x, z), heading (0 = -Z, positive turns right)
## and signed curvature.
static var _points := PackedVector2Array()
static var _headings := PackedFloat32Array()
static var _curvature := PackedFloat32Array()
static var _map_origin := Vector2.ZERO
static var _map_size := Vector2i.ZERO
## A coarse world grid holding the nearest course d of each cell, seeding `to_course`.
static var _map := _build()


static func _build() -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	for piece: Array in stage.plan:
		var length: float = piece[0]
		var k: float = deg_to_rad(piece[1]) / length
		for i in int(length / STEP):
			raw.append(k)
	for pass_index in 2:
		var prefix := PackedFloat32Array([0.0])
		for k in raw:
			prefix.append(prefix[-1] + k)
		var smoothed := PackedFloat32Array()
		for i in raw.size():
			smoothed.append((prefix[mini(i + SMOOTH + 1, raw.size())] - prefix[maxi(i - SMOOTH, 0)]) / (SMOOTH * 2 + 1))
		raw = smoothed
	var points := PackedVector2Array()
	var headings := PackedFloat32Array()
	var heading := 0.0
	var at := Vector2(0.0, -stage.plan_start)
	for i in raw.size():
		points.append(at)
		headings.append(heading)
		var mid := heading + raw[i] * STEP * 0.5
		at += Vector2(sin(mid), -cos(mid)) * STEP
		heading += raw[i] * STEP
	# Rasterize the valley ribbon into the lookup grid, nearer-to-road samples winning.
	var low := Vector2.INF
	var high := -Vector2.INF
	for point in points:
		low = low.min(point)
		high = high.max(point)
	var origin := low - Vector2.ONE * (MAP_REACH + MAP_CELL)
	var size := Vector2i(((high - low + Vector2.ONE * (MAP_REACH + MAP_CELL) * 2.0) / MAP_CELL).ceil())
	var map := PackedFloat32Array()
	map.resize(size.x * size.y)
	map.fill(NAN)
	var nearest := PackedFloat32Array()
	nearest.resize(map.size())
	nearest.fill(INF)
	var i := 0
	while i < points.size():
		var normal := Vector2(cos(headings[i]), sin(headings[i]))
		var inside := 0.9 / maxf(absf(raw[i]), 0.0001)
		var u := -MAP_REACH
		while u <= MAP_REACH:
			if absf(u) < inside or signf(u) != signf(raw[i]):
				var cell := Vector2i(((points[i] + normal * u - origin) / MAP_CELL).floor())
				var index := cell.y * size.x + cell.x
				if absf(u) < nearest[index]:
					nearest[index] = absf(u)
					map[index] = stage.plan_start + i * STEP
			u += MAP_CELL * 0.7
		i += int(MAP_CELL * 0.5)
	_points = points
	_headings = headings
	_curvature = raw
	_map_origin = origin
	_map_size = size
	return map


static func _center(d: float) -> Vector2:
	var x := clampf((d - stage.plan_start) / STEP, 0.0, _points.size() - 1.001)
	var i := int(x)
	return _points[i].lerp(_points[i + 1], x - i)


static func _heading(d: float) -> float:
	var x := clampf((d - stage.plan_start) / STEP, 0.0, _points.size() - 1.001)
	var i := int(x)
	return lerpf(_headings[i], _headings[i + 1], x - i)


static func _curvature_at(d: float) -> float:
	return _curvature[clampi(int((d - stage.plan_start) / STEP), 0, _curvature.size() - 1)]


## Unit forward vector of the road at distance d.
static func forward(d: float) -> Vector3:
	var heading := _heading(d)
	return Vector3(sin(heading), 0.0, -cos(heading))


## Unit vector pointing to +u (the road's right) at distance d.
static func right(d: float) -> Vector3:
	var heading := _heading(d)
	return Vector3(cos(heading), 0.0, sin(heading))


## Yaw that turns a node's -Z to face along the road at d.
static func yaw_at(d: float) -> float:
	return -_heading(d)


static func to_world(d: float, u: float, y := 0.0) -> Vector3:
	var c := _center(d)
	var heading := _heading(d)
	return Vector3(c.x + cos(heading) * u, y, c.y + sin(heading) * u)


static func ground_at(d: float, u: float) -> Vector3:
	var p := to_world(d, u)
	p.y = height(d, u)
	return p


## Inverse of `to_world` for points within MAP_REACH of the road: a grid lookup seeds d, then a
## few curvature-corrected projection steps settle it onto the nearest centerline point.
static func to_course(p: Vector3) -> Vector2:
	var flat := Vector2(p.x, p.z)
	var cell := Vector2i(((flat - _map_origin) / MAP_CELL).floor())
	var d := NAN
	if cell.x >= 0 and cell.y >= 0 and cell.x < _map_size.x and cell.y < _map_size.y:
		d = _map[cell.y * _map_size.x + cell.x]
	if is_nan(d):
		d = _nearest_sample(flat)
	var u := 0.0
	for i in 3:
		var c := _center(d)
		var heading := _heading(d)
		var offset := flat - c
		u = offset.dot(Vector2(cos(heading), sin(heading)))
		var along := offset.dot(Vector2(sin(heading), -cos(heading)))
		d += along / maxf(1.0 - _curvature_at(d) * u, 0.1)
	var heading := _heading(d)
	u = (flat - _center(d)).dot(Vector2(cos(heading), sin(heading)))
	return Vector2(d, u)


## Brute-force fallback for points outside the lookup grid.
static func _nearest_sample(flat: Vector2) -> float:
	var best := 0
	var best_distance := INF
	for i in range(0, _points.size(), 10):
		var distance := _points[i].distance_squared_to(flat)
		if distance < best_distance:
			best_distance = distance
			best = i
	return stage.plan_start + best * STEP


static func height_at(p: Vector3) -> float:
	var c := to_course(p)
	return height(c.x, c.y)


## Half width of the flat valley floor around the road.
static func valley_half_width(d: float) -> float:
	return stage.valley_half_width(d)


static func deck_blend(d: float) -> float:
	return stage.deck_blend(d)


static func section_at(d: float) -> int:
	return stage.section_at(d)


static func height(d: float, u: float) -> float:
	return 0.0 if flat else stage.height(d, u)


## How overgrown the ground is (0..1).
static func fungus_at(d: float, u: float) -> float:
	return stage.fungus_at(d, u)


static func ground_color(d: float, u: float, h: float, slope: float) -> Color:
	if flat:
		return Palette.SAGE if (int(floorf(d / 10.0)) + int(floorf(u / 10.0))) % 2 == 0 else Palette.LEAF
	return stage.ground_color(d, u, h, slope)
