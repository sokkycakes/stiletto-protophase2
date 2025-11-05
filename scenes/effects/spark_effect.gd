extends Node3D

signal finished

@onready var particles: CPUParticles3D = $CPUParticles3D

func _ready() -> void:
	if not particles:
		push_error("SparkEffect: CPUParticles3D node not found!")
		queue_free()
		return
	
	# Wait one frame to ensure everything is properly initialized
	await get_tree().process_frame
	
	# Start emitting particles
	particles.emitting = true
	
	# Wait for particles to finish
	await get_tree().create_timer(particles.lifetime + 0.1).timeout
	finished.emit() 
