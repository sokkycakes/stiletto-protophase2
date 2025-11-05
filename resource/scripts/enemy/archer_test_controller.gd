extends Node3D
class_name ArcherTestController

@onready var archer: ArcherEnemy = $ArcherEnemy
@onready var player: TestPlayer = $TestPlayer

func _ready():
	print("=== Archer Test Controller ===")
	
	# Wait a frame for everything to initialize
	await get_tree().process_frame
	
	# Check if archer found the player
	if archer and archer.target_player:
		print("✓ Archer found player: ", archer.target_player.name)
	else:
		print("✗ Archer did not find player!")
		if archer:
			print("  Archer exists but target_player is null")
		else:
			print("  Archer node not found!")
	
	# Print archer settings
	if archer:
		print("Archer Settings:")
		print("  Attack Range: ", archer.attack_range)
		print("  Sight Range: ", archer.sight_range)
		print("  Preferred Distance: ", archer.preferred_distance)
		print("  Min Distance: ", archer.min_distance)
		print("  Projectile Speed: ", archer.projectile_speed)
		print("  Attack Damage: ", archer.attack_damage)
		print("  Debug Enabled: ", archer.debug_enabled)
	
	# Print player info
	if player:
		print("Player Info:")
		print("  Position: ", player.global_position)
		print("  Groups: ", player.get_groups())
		print("  Health: ", player.current_health)

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				print("\n--- Manual Test: Archer Status ---")
				print_archer_status()
			KEY_2:
				print("\n--- Manual Test: Force Archer Attack ---")
				force_archer_attack()
			KEY_3:
				print("\n--- Manual Test: Distance Check ---")
				check_distances()
			KEY_4:
				print("\n--- Manual Test: Line of Sight ---")
				check_line_of_sight()
			KEY_5:
				print("\n--- Manual Test: Spawn Projectile ---")
				spawn_test_projectile()

func print_archer_status():
	if not archer:
		print("No archer found!")
		return
	
	print("Archer Status:")
	print("  Position: ", archer.global_position)
	print("  Current State: ", archer.current_state)
	print("  Target Player: ", archer.target_player)
	print("  Can See Player: ", archer.can_see_player())
	print("  Attack Timer: ", archer.attack_timer)
	print("  Aim Timer: ", archer.aim_timer)
	print("  Is Aiming: ", archer.is_aiming)
	print("  Is Retreating: ", archer.is_retreating)
	
	if archer.target_player:
		var distance = archer.global_position.distance_to(archer.target_player.global_position)
		print("  Distance to Player: ", distance)
		print("  In Attack Range: ", distance <= archer.attack_range)
		print("  In Sight Range: ", distance <= archer.sight_range)

func force_archer_attack():
	if not archer:
		print("No archer found!")
		return
	
	print("Forcing archer to attack...")
	archer.change_state(archer.EnemyState.ATTACK)

func check_distances():
	if not archer or not player:
		print("Missing archer or player!")
		return
	
	var distance = archer.global_position.distance_to(player.global_position)
	print("Distance Analysis:")
	print("  Actual Distance: ", distance)
	print("  Attack Range: ", archer.attack_range, " (", "IN RANGE" if distance <= archer.attack_range else "OUT OF RANGE", ")")
	print("  Sight Range: ", archer.sight_range, " (", "IN RANGE" if distance <= archer.sight_range else "OUT OF RANGE", ")")
	print("  Preferred Distance: ", archer.preferred_distance)
	print("  Min Distance: ", archer.min_distance)

func check_line_of_sight():
	if not archer or not player:
		print("Missing archer or player!")
		return
	
	print("Line of Sight Check:")
	var can_see = archer.can_see_player()
	print("  Can See Player: ", can_see)
	
	# Manual raycast
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		archer.global_position + Vector3(0, 1.5, 0),
		player.global_position + Vector3(0, 1, 0)
	)
	query.exclude = [archer]
	
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		print("  Manual Raycast: Clear line of sight")
	else:
		print("  Manual Raycast: Blocked by ", result.collider.name)

func spawn_test_projectile():
	if not archer:
		print("No archer found!")
		return
	
	print("Spawning test projectile...")
	archer.shoot_projectile()
