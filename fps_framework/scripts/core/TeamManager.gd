extends Node
# TeamManager - Autoload Singleton
# Note: No class_name needed for autoload singletons

## Manages team assignment, balancing, and team-based functionality

# --- Team Configuration ---
const MAX_TEAMS = 4
const TEAM_COLORS = [
	Color.BLUE,      # Team 0
	Color.RED,       # Team 1  
	Color.GREEN,     # Team 2
	Color.YELLOW     # Team 3
]

const TEAM_NAMES = [
	"Blue Team",
	"Red Team", 
	"Green Team",
	"Yellow Team"
]

# --- Current State ---
var teams: Dictionary = {}  # team_id -> Array[peer_ids]
var player_teams: Dictionary = {}  # peer_id -> team_id
var team_scores: Dictionary = {}  # team_id -> score
var auto_balance: bool = true

# --- Signals ---
signal team_changed(peer_id: int, old_team: int, new_team: int)
signal team_scores_updated(scores: Dictionary)
signal teams_rebalanced()

func _ready() -> void:
	# Initialize teams
	for i in range(MAX_TEAMS):
		teams[i] = []
		team_scores[i] = 0
	
	# Connect to multiplayer events
	if MultiplayerManager:
		MultiplayerManager.player_connected.connect(_on_player_connected)
		MultiplayerManager.player_disconnected.connect(_on_player_disconnected)

# --- Public API ---

## Assign a player to a specific team
func assign_player_to_team(peer_id: int, team_id: int, force: bool = false) -> bool:
	if not MultiplayerManager.is_server() and not force:
		print("Only server can assign teams")
		return false
	
	if team_id < 0 or team_id >= MAX_TEAMS:
		print("Invalid team ID: ", team_id)
		return false
	
	var old_team = player_teams.get(peer_id, -1)
	
	# Remove from old team
	if old_team != -1 and old_team in teams:
		teams[old_team].erase(peer_id)
	
	# Add to new team
	teams[team_id].append(peer_id)
	player_teams[peer_id] = team_id
	
	# Update player info in MultiplayerManager
	var player_info = MultiplayerManager.get_player_info(peer_id)
	if player_info:
		player_info["team"] = team_id
		MultiplayerManager.connected_players[peer_id] = player_info
	
	print("Player ", peer_id, " assigned to team ", team_id)
	team_changed.emit(peer_id, old_team, team_id)
	
	# Sync to all clients
	if MultiplayerManager.is_server():
		sync_team_assignments.rpc(player_teams)
	
	return true

## Auto-balance teams based on player count
func balance_teams() -> void:
	if not MultiplayerManager.is_server():
		return
	
	var connected_players = MultiplayerManager.get_connected_players()
	var player_count = connected_players.size()
	
	if player_count <= 1:
		return
	
	# Determine number of active teams based on player count
	var active_teams = min(2, MAX_TEAMS)  # Default to 2 teams
	if player_count >= 6:
		active_teams = min(3, MAX_TEAMS)
	if player_count >= 8:
		active_teams = MAX_TEAMS
	
	# Clear current assignments
	for team_id in teams:
		teams[team_id].clear()
	player_teams.clear()
	
	# Distribute players evenly
	var team_index = 0
	for peer_id in connected_players:
		assign_player_to_team(peer_id, team_index % active_teams, true)
		team_index += 1
	
	print("Teams rebalanced for ", player_count, " players across ", active_teams, " teams")
	teams_rebalanced.emit()

## Get the team ID for a specific player
func get_player_team(peer_id: int) -> int:
	return player_teams.get(peer_id, 0)  # Default to team 0

## Get all players on a specific team
func get_team_players(team_id: int) -> Array:
	return teams.get(team_id, [])

## Get team information
func get_team_info(team_id: int) -> Dictionary:
	return {
		"id": team_id,
		"name": TEAM_NAMES[team_id] if team_id < TEAM_NAMES.size() else "Team " + str(team_id),
		"color": TEAM_COLORS[team_id] if team_id < TEAM_COLORS.size() else Color.WHITE,
		"players": teams.get(team_id, []),
		"player_count": teams.get(team_id, []).size(),
		"score": team_scores.get(team_id, 0)
	}

## Get all teams information
func get_all_teams_info() -> Dictionary:
	var info = {}
	for team_id in teams:
		if teams[team_id].size() > 0:  # Only include teams with players
			info[team_id] = get_team_info(team_id)
	return info

## Check if two players are on the same team
func are_teammates(peer_id1: int, peer_id2: int) -> bool:
	var team1 = get_player_team(peer_id1)
	var team2 = get_player_team(peer_id2)
	return team1 == team2 and team1 != -1

## Update team score
func add_team_score(team_id: int, points: int) -> void:
	if not MultiplayerManager.is_server():
		return
	
	if team_id in team_scores:
		team_scores[team_id] += points
		team_scores_updated.emit(team_scores)
		sync_team_scores.rpc(team_scores)

## Reset all team scores
func reset_team_scores() -> void:
	if not MultiplayerManager.is_server():
		return
	
	for team_id in team_scores:
		team_scores[team_id] = 0
	
	team_scores_updated.emit(team_scores)
	sync_team_scores.rpc(team_scores)

## Enable/disable auto-balancing
func set_auto_balance(enabled: bool) -> void:
	auto_balance = enabled

## Switch a player to the opposite team (for 2-team games)
func switch_player_team(peer_id: int) -> bool:
	var current_team = get_player_team(peer_id)
	var new_team = 1 if current_team == 0 else 0
	return assign_player_to_team(peer_id, new_team)

# --- RPC Methods ---

@rpc("authority", "call_local", "reliable")
func sync_team_assignments(assignments: Dictionary) -> void:
	player_teams = assignments
	
	# Rebuild teams dictionary
	for team_id in teams:
		teams[team_id].clear()
	
	for peer_id in assignments:
		var team_id = assignments[peer_id]
		if team_id in teams:
			teams[team_id].append(peer_id)

@rpc("authority", "call_local", "reliable")
func sync_team_scores(scores: Dictionary) -> void:
	team_scores = scores
	team_scores_updated.emit(team_scores)

# --- Signal Handlers ---

func _on_player_connected(peer_id: int, player_info: Dictionary) -> void:
	if MultiplayerManager.is_server():
		# Auto-assign to team with fewest players
		var smallest_team = _find_smallest_team()
		assign_player_to_team(peer_id, smallest_team, true)
		
		# Auto-balance if enabled and enough players
		if auto_balance and MultiplayerManager.get_connected_players().size() >= 4:
			balance_teams()

func _on_player_disconnected(peer_id: int) -> void:
	if MultiplayerManager.is_server():
		var old_team = player_teams.get(peer_id, -1)
		
		# Remove from team
		if old_team != -1 and old_team in teams:
			teams[old_team].erase(peer_id)
		player_teams.erase(peer_id)
		
		# Auto-balance remaining players if enabled
		if auto_balance and MultiplayerManager.get_connected_players().size() > 1:
			# Small delay to allow cleanup
			await get_tree().create_timer(1.0).timeout
			balance_teams()

# --- Internal Methods ---

func _find_smallest_team() -> int:
	var smallest_team = 0
	var smallest_size = teams[0].size()
	
	for team_id in teams:
		if teams[team_id].size() < smallest_size:
			smallest_size = teams[team_id].size()
			smallest_team = team_id
	
	return smallest_team

## Get team statistics for display
func get_team_stats() -> Dictionary:
	var stats = {}
	
	for team_id in teams:
		if teams[team_id].size() > 0:
			var team_info = get_team_info(team_id)
			var player_names = []
			
			for peer_id in teams[team_id]:
				var player_info = MultiplayerManager.get_player_info(peer_id)
				player_names.append(player_info.get("name", "Player " + str(peer_id)))
			
			stats[team_id] = {
				"name": team_info["name"],
				"color": team_info["color"],
				"score": team_info["score"],
				"player_count": team_info["player_count"],
				"players": player_names
			}
	
	return stats

## Check if teams are balanced (for auto-balance logic)
func are_teams_balanced() -> bool:
	var team_sizes = []
	for team_id in teams:
		if teams[team_id].size() > 0:
			team_sizes.append(teams[team_id].size())
	
	if team_sizes.size() <= 1:
		return true
	
	var min_size = team_sizes.min()
	var max_size = team_sizes.max()
	
	# Teams are balanced if difference is 1 or less
	return (max_size - min_size) <= 1