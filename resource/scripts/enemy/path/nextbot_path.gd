## NextBot Path - Pathfinding and path following system
## Based on Source SDK NextBotPath.h
class_name NextBotPath
extends RefCounted

# Path segment types
enum SegmentType {
	ON_GROUND,
	DROP_DOWN,
	CLIMB_UP,
	JUMP_OVER_GAP,
	LADDER_UP,
	LADDER_DOWN
}

# Path failure types
enum FailureType {
	NO_PATH_EXISTS,
	STUCK,
	FELL_OFF
}

# Path result types
enum ResultType {
	COMPLETE_PATH,
	PARTIAL_PATH,
	NO_PATH
}

# Path segment class
class Segment:
	var area: NavigationRegion3D = null
	var how: int = 0  # Navigation traverse type
	var pos: Vector3 = Vector3.ZERO
	var ladder: Node = null
	
	var type: SegmentType = SegmentType.ON_GROUND
	var forward: Vector3 = Vector3.FORWARD
	var length: float = 0.0
	var distance_from_start: float = 0.0
	var curvature: float = 0.0
	
	var portal_center: Vector3 = Vector3.ZERO
	var portal_half_width: float = 0.0
	
	func _init(position: Vector3, segment_type: SegmentType = SegmentType.ON_GROUND):
		pos = position
		type = segment_type

# Path properties
var segments: Array[Segment] = []
var subject: Node = null
var is_valid_path: bool = false
var path_length: float = 0.0
var age_timer: float = 0.0

# Path cursor for following
var cursor_position: float = 0.0
var cursor_data: CursorData = CursorData.new()

# Cursor data class
class CursorData:
	var pos: Vector3 = Vector3.ZERO
	var forward: Vector3 = Vector3.FORWARD
	var curvature: float = 0.0
	var segment_prior: Segment = null

# Path construction
func compute_to_position(bot, goal: Vector3, max_path_length: float = 0.0) -> bool:
	invalidate()
	
	var start_pos = bot.global_position
	var nav_agent = bot.get_navigation_agent()
	
	if not nav_agent:
		print("NextBotPath: No NavigationAgent3D found on bot")
		return false
	
	# Use Godot's navigation system
	nav_agent.target_position = goal
	
	# Wait a frame for path calculation
	await bot.get_tree().process_frame
	
	if nav_agent.is_navigation_finished():
		return false
	
	# Build path from NavigationAgent3D
	return _build_path_from_nav_agent(bot, nav_agent, goal)

func compute_to_actor(bot, target: Node, max_path_length: float = 0.0) -> bool:
	if not target:
		return false

	subject = target
	return await compute_to_position(bot, target.global_position, max_path_length)

# Path validation
func is_valid() -> bool:
	return is_valid_path and not segments.is_empty()

func invalidate() -> void:
	is_valid_path = false
	segments.clear()
	path_length = 0.0
	cursor_position = 0.0
	age_timer = 0.0

# Path properties
func get_length() -> float:
	return path_length

func get_start_position() -> Vector3:
	if segments.is_empty():
		return Vector3.ZERO
	return segments[0].pos

func get_end_position() -> Vector3:
	if segments.is_empty():
		return Vector3.ZERO
	return segments[-1].pos

func get_subject() -> Node:
	return subject

func get_age() -> float:
	return age_timer

# Path navigation
func get_position_at_distance(distance: float, start_segment: Segment = null) -> Vector3:
	if segments.is_empty():
		return Vector3.ZERO
	
	var current_distance = 0.0
	var start_index = 0
	
	if start_segment:
		start_index = segments.find(start_segment)
		if start_index == -1:
			start_index = 0
	
	for i in range(start_index, segments.size()):
		var segment = segments[i]
		if current_distance + segment.length >= distance:
			# Interpolate within this segment
			var segment_progress = (distance - current_distance) / segment.length
			if i == segments.size() - 1:
				return segment.pos
			else:
				var next_segment = segments[i + 1]
				return segment.pos.lerp(next_segment.pos, segment_progress)
		current_distance += segment.length
	
	return get_end_position()

func get_closest_position(pos: Vector3, start_segment: Segment = null) -> Vector3:
	if segments.is_empty():
		return Vector3.ZERO
	
	var closest_pos = segments[0].pos
	var closest_distance = pos.distance_to(closest_pos)
	
	var start_index = 0
	if start_segment:
		start_index = segments.find(start_segment)
		if start_index == -1:
			start_index = 0
	
	for i in range(start_index, segments.size()):
		var segment = segments[i]
		var distance = pos.distance_to(segment.pos)
		if distance < closest_distance:
			closest_distance = distance
			closest_pos = segment.pos
	
	return closest_pos

# Cursor management
func move_cursor_to_closest_position(pos: Vector3) -> void:
	if segments.is_empty():
		return
	
	var closest_distance = INF
	var closest_cursor_pos = 0.0
	var current_distance = 0.0
	
	for i in range(segments.size()):
		var segment = segments[i]
		var distance = pos.distance_to(segment.pos)
		if distance < closest_distance:
			closest_distance = distance
			closest_cursor_pos = current_distance
		current_distance += segment.length
	
	cursor_position = closest_cursor_pos
	_update_cursor_data()

func move_cursor_to_start() -> void:
	cursor_position = 0.0
	_update_cursor_data()

func move_cursor_to_end() -> void:
	cursor_position = path_length
	_update_cursor_data()

func move_cursor(distance: float, absolute: bool = true) -> void:
	if absolute:
		cursor_position = clamp(distance, 0.0, path_length)
	else:
		cursor_position = clamp(cursor_position + distance, 0.0, path_length)
	_update_cursor_data()

func get_cursor_position() -> float:
	return cursor_position

func get_cursor_data() -> CursorData:
	return cursor_data

# Segment access
func first_segment() -> Segment:
	if segments.is_empty():
		return null
	return segments[0]

func last_segment() -> Segment:
	if segments.is_empty():
		return null
	return segments[-1]

func next_segment(current_segment: Segment) -> Segment:
	var index = segments.find(current_segment)
	if index == -1 or index >= segments.size() - 1:
		return null
	return segments[index + 1]

func prior_segment(current_segment: Segment) -> Segment:
	var index = segments.find(current_segment)
	if index <= 0:
		return null
	return segments[index - 1]

# Path building from NavigationAgent3D
func _build_path_from_nav_agent(bot: INextBot, nav_agent: NavigationAgent3D, goal: Vector3) -> bool:
	var nav_path = nav_agent.get_current_navigation_path()
	if nav_path.is_empty():
		return false
	
	# Convert navigation path to segments
	var total_length = 0.0
	
	for i in range(nav_path.size()):
		var segment = Segment.new(nav_path[i])
		
		if i > 0:
			var prev_segment = segments[i - 1]
			segment.length = prev_segment.pos.distance_to(segment.pos)
			segment.forward = (segment.pos - prev_segment.pos).normalized()
			segment.distance_from_start = total_length
			total_length += segment.length
		else:
			segment.distance_from_start = 0.0
		
		segments.append(segment)
	
	path_length = total_length
	is_valid_path = true
	age_timer = 0.0
	
	# Initialize cursor
	move_cursor_to_start()
	
	return true

# Update cursor data based on current position
func _update_cursor_data() -> void:
	if segments.is_empty():
		return
	
	var current_distance = 0.0
	cursor_data.segment_prior = null
	
	for i in range(segments.size()):
		var segment = segments[i]
		
		if current_distance + segment.length >= cursor_position:
			# Cursor is within this segment
			cursor_data.pos = get_position_at_distance(cursor_position)
			cursor_data.forward = segment.forward
			cursor_data.curvature = segment.curvature
			cursor_data.segment_prior = segment if i > 0 else null
			return
		
		current_distance += segment.length
		cursor_data.segment_prior = segment
	
	# Cursor is at the end
	var last_seg = segments[-1]
	cursor_data.pos = last_seg.pos
	cursor_data.forward = last_seg.forward
	cursor_data.curvature = last_seg.curvature

# Update age
func update(delta: float) -> void:
	age_timer += delta

# Debug drawing
func draw_debug(bot: INextBot) -> void:
	if not is_valid() or not NextBotManager.is_debugging(NextBotManager.DebugType.PATH):
		return
	
	# Draw path segments
	for i in range(segments.size() - 1):
		var start_pos = segments[i].pos
		var end_pos = segments[i + 1].pos
		
		# In a real implementation, you'd use DebugDraw3D or similar
		# This is a placeholder for the debug drawing system
		_debug_draw_line(start_pos, end_pos, Color.YELLOW)
	
	# Draw cursor position
	_debug_draw_sphere(cursor_data.pos, 0.2, Color.RED)

func _debug_draw_line(from: Vector3, to: Vector3, color: Color) -> void:
	# Placeholder for debug line drawing
	pass

func _debug_draw_sphere(pos: Vector3, radius: float, color: Color) -> void:
	# Placeholder for debug sphere drawing
	pass
