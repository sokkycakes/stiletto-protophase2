class_name EnemyWavePool
extends Resource

@export var entries: Array[Resource] = []

func is_empty() -> bool:
	return entries.is_empty()

func pick_scene(rng: RandomNumberGenerator) -> PackedScene:
	if entries.is_empty():
		return null
	var total: float = 0.0
	for e in entries:
		var w: float = 0.0
		if e and "weight" in e:
			w = float(e.weight)
		total += max(w, 0.0)
	if total <= 0.0:
		var first = entries[0]
		return first.scene if first and "scene" in first else null
	var roll := rng.randf() * total
	var accum: float = 0.0
	for e in entries:
		var w2: float = 0.0
		if e and "weight" in e:
			w2 = float(e.weight)
		accum += max(w2, 0.0)
		if roll <= accum:
			return e.scene if e and "scene" in e else null
	var last = entries.back()
	return last.scene if last and "scene" in last else null

