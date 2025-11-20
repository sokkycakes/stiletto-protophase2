extends Node

const MAX_TEAMS := 4
const TEAM_COLORS := [
	Color.BLUE,
	Color.RED,
	Color.GREEN,
	Color.YELLOW,
]

const TEAM_NAMES := [
	"Blue Team",
	"Red Team",
	"Green Team",
	"Yellow Team",
]

var teams: Dictionary = {}
var player_teams: Dictionary = {}
var team_scores: Dictionary = {}
var auto_balance: bool = true

signal team_changed(peer_id: int, old_team: int, new_team: int)
signal team_scores_updated(scores: Dictionary)
signal teams_rebalanced()

func _ready() -> void:
	for i in range(MAX_TEAMS):
		teams[i] = []
		team_scores[i] = 0
	if MultiplayerManager:
		MultiplayerManager.player_connected.connect(_on_player_connected)
		MultiplayerManager.player_disconnected.connect(_on_player_disconnected)


func assign_player_to_team(peer_id: int, team_id: int, force: bool = false) -> bool:
	if not MultiplayerManager:
		return false
	if not MultiplayerManager.is_server() and not force:
		return false
	if team_id < 0 or team_id >= MAX_TEAMS:
		return false
	var old_team: int = player_teams.get(peer_id, -1)
	if old_team != -1 and old_team in teams:
		teams[old_team].erase(peer_id)
	teams[team_id].append(peer_id)
	player_teams[peer_id] = team_id
	var info: Dictionary = MultiplayerManager.get_player_info(peer_id)
	if info:
		info["team"] = team_id
		MultiplayerManager.connected_players[peer_id] = info
	team_changed.emit(peer_id, old_team, team_id)
	if MultiplayerManager.is_server():
		sync_team_assignments.rpc(player_teams)
	return true


func balance_teams() -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	var connected_players: Array = MultiplayerManager.get_connected_peer_ids()
	if connected_players.is_empty():
		return
	for key in teams.keys():
		teams[key].clear()
	player_teams.clear()
	var active_team_count: int = min(2, MAX_TEAMS)
	if connected_players.size() >= 6:
		active_team_count = min(3, MAX_TEAMS)
	if connected_players.size() >= 8:
		active_team_count = MAX_TEAMS
	var index: int = 0
	for peer_id in connected_players:
		assign_player_to_team(peer_id, index % active_team_count, true)
		index += 1
	teams_rebalanced.emit()


func get_player_team(peer_id: int) -> int:
	return player_teams.get(peer_id, 0)


func get_team_players(team_id: int) -> Array:
	return teams.get(team_id, [])


func get_team_info(team_id: int) -> Dictionary:
	return {
		"id": team_id,
		"name": TEAM_NAMES[team_id] if team_id < TEAM_NAMES.size() else "Team %d" % team_id,
		"color": TEAM_COLORS[team_id] if team_id < TEAM_COLORS.size() else Color.WHITE,
		"players": teams.get(team_id, []),
		"player_count": teams.get(team_id, []).size(),
		"score": team_scores.get(team_id, 0),
	}


func get_all_teams_info() -> Dictionary:
	var info: Dictionary = {}
	for team_id in teams.keys():
		if teams[team_id].size() > 0:
			info[team_id] = get_team_info(team_id)
	return info


func are_teammates(peer_a: int, peer_b: int) -> bool:
	return get_player_team(peer_a) == get_player_team(peer_b)


func add_team_score(team_id: int, points: int) -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	if team_id in team_scores:
		team_scores[team_id] += points
		team_scores_updated.emit(team_scores)
		sync_team_scores.rpc(team_scores)


func reset_team_scores() -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	for team_id in team_scores.keys():
		team_scores[team_id] = 0
	team_scores_updated.emit(team_scores)
	sync_team_scores.rpc(team_scores)


func set_auto_balance(enabled: bool) -> void:
	auto_balance = enabled


func switch_player_team(peer_id: int) -> bool:
	var current: int = get_player_team(peer_id)
	var target: int = 1 if current == 0 else 0
	return assign_player_to_team(peer_id, target)


@rpc("authority", "call_local", "reliable")
func sync_team_assignments(assignments: Dictionary) -> void:
	player_teams = assignments
	for key in teams.keys():
		teams[key].clear()
	for peer_id in assignments.keys():
		var team_id: int = int(assignments[peer_id])
		if team_id in teams:
			teams[team_id].append(peer_id)


@rpc("authority", "call_local", "reliable")
func sync_team_scores(scores: Dictionary) -> void:
	team_scores = scores
	team_scores_updated.emit(team_scores)


func _on_player_connected(peer_id: int) -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	var smallest := _find_smallest_team()
	assign_player_to_team(peer_id, smallest, true)
	if auto_balance and MultiplayerManager.get_connected_peer_ids().size() >= 4:
		balance_teams()


func _on_player_disconnected(peer_id: int) -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	var old_team: int = player_teams.get(peer_id, -1)
	if old_team != -1 and old_team in teams:
		teams[old_team].erase(peer_id)
	player_teams.erase(peer_id)
	if auto_balance and MultiplayerManager.get_connected_peer_ids().size() > 1:
		await get_tree().create_timer(1.0).timeout
		balance_teams()


func _find_smallest_team() -> int:
	var smallest_team: int = 0
	var smallest_size: int = teams[0].size()
	for team_id in teams.keys():
		if teams[team_id].size() < smallest_size:
			smallest_size = teams[team_id].size()
			smallest_team = team_id
	return smallest_team


func get_team_stats() -> Dictionary:
	var stats: Dictionary = {}
	for team_id in teams.keys():
		if teams[team_id].size() == 0:
			continue
		var info: Dictionary = get_team_info(team_id)
		var player_names: Array = []
		for peer_id in teams[team_id]:
			var player_info: Dictionary = MultiplayerManager.get_player_info(peer_id)
			player_names.append(player_info.get("name", "Player %d" % peer_id))
		stats[team_id] = {
			"name": info["name"],
			"color": info["color"],
			"score": info["score"],
			"player_count": info["player_count"],
			"players": player_names,
		}
	return stats


func are_teams_balanced() -> bool:
	var sizes: Array = []
	for team_id in teams.keys():
		if teams[team_id].size() > 0:
			sizes.append(teams[team_id].size())
	if sizes.size() <= 1:
		return true
	var min_size: int = int(sizes.min())
	var max_size: int = int(sizes.max())
	return (max_size - min_size) <= 1

