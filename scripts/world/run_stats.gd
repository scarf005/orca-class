class_name RunStats
extends RefCounted
## Score, combo and the numbers shown on the results screen.

const COMBO_WINDOW := 2.6
const MAX_MULTIPLIER := 8

var score := 0
var combo := 0
var max_combo := 0
var combo_timer := 0.0
var kills := 0
var spawned := 0
var shots := 0
var shot_hits := 0
var damage_taken := 0.0
var time := 0.0
var lives := 3
var ranked := true ## False after starting from a checkpoint or continuing.
var section_damage := 0.0 ## Damage taken since the current section began.


func tick(delta: float) -> void:
	time += delta
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0


func multiplier() -> int:
	return mini(1 + combo / 6, MAX_MULTIPLIER)


## Returns the points actually gained after the multiplier.
func add_score(points: int, is_kill: bool) -> int:
	if is_kill:
		combo += 1
		max_combo = maxi(max_combo, combo)
		combo_timer = COMBO_WINDOW
		kills += 1
	var gained := points * (multiplier() if is_kill else 1)
	score += gained
	return gained


func kill_ratio() -> float:
	return float(kills) / float(maxi(spawned, 1))


func accuracy() -> float:
	return float(shot_hits) / float(maxi(shots, 1))


## Rank from score per difficulty plus kill ratio and damage taken.
func rank() -> String:
	var points := score / 1000.0
	points += kill_ratio() * 60.0
	points -= damage_taken / 25.0
	points += accuracy() * 20.0
	if points >= 150.0:
		return "S"
	if points >= 110.0:
		return "A"
	if points >= 70.0:
		return "B"
	return "C"
