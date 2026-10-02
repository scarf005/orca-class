class_name RunStats
extends RefCounted
## Score, the style meter and the numbers shown on the results screen.
## Style rises with varied, violent play and drains over time and when the tank gets hit; its
## rank multiplies every kill's score. Repeating the same trick earns less each time, however many
## other tricks come in between, until it has rested for a while.

const COMBO_WINDOW := 2.6
const STYLE_RANKS: Array[float] = [0.0, 90.0, 200.0, 340.0, 500.0, 680.0, 880.0] ## D C B A S SS SSS
const STYLE_LETTERS: Array[String] = ["D", "C", "B", "A", "S", "SS", "SSS"]
## Each rank spelled out, in English whatever the language, as arcade style ranks are.
const STYLE_WORDS: Array[String] = ["DOPE", "COOL", "BRUTAL", "AWESOME", "SAVAGE", "SICK SKILLS", "SMOKIN' SICK STYLE"]
const STYLE_MULTIPLIERS: Array[int] = [1, 2, 3, 4, 5, 6, 8]
const STYLE_MAX := 1000.0
const STYLE_DECAY := 14.0 ## Per second at rank D; faster at higher ranks.
const STYLE_HIT_PENALTY := 70.0
const FATIGUE_RECOVERY := 0.5 ## Repeats a trick sheds per second; each use adds one and halves the next.
const FATIGUE_MAX := 3.0 ## A spammed trick still pays an eighth, and a short rest brings it back.

var score := 0
var combo := 0 ## Kills in a row without a gap longer than COMBO_WINDOW (results stat).
var max_combo := 0
var combo_timer := 0.0
var kills := 0
var spawned := 0
var shots := 0
var charged_shots := 0
var melee_healing := 0.0
var repair_healing := 0.0
var shot_hits := 0
var damage_taken := 0.0
var time := 0.0
var lives := 3
var ranked := true ## False after starting from a checkpoint or continuing.
var section_damage := 0.0 ## Damage taken since the current section began.
var style := 0.0
var style_feed: Array[Dictionary] = [] ## Recent tricks for the HUD: {name, points, age}.
var _fatigue := {} ## Trick name -> repeats still counting against it.


func tick(delta: float) -> void:
	time += delta
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo = 0
	style = maxf(0.0, style - STYLE_DECAY * (1.0 + style_rank() * 0.35) * delta)
	for trick: String in _fatigue.keys():
		_fatigue[trick] -= FATIGUE_RECOVERY * delta
		if _fatigue[trick] <= 0.0:
			_fatigue.erase(trick)
	for entry in style_feed:
		entry.age += delta
	style_feed = style_feed.filter(func(e: Dictionary) -> bool: return e.age < 2.5)


func style_rank() -> int:
	var rank := 0
	for i in STYLE_RANKS.size():
		if style >= STYLE_RANKS[i]:
			rank = i
	return rank


## Progress (0..1) toward the next rank.
func style_progress() -> float:
	var rank := style_rank()
	if rank >= STYLE_RANKS.size() - 1:
		return clampf((style - STYLE_RANKS[rank]) / (STYLE_MAX - STYLE_RANKS[rank]), 0.0, 1.0)
	return (style - STYLE_RANKS[rank]) / (STYLE_RANKS[rank + 1] - STYLE_RANKS[rank])


func multiplier() -> int:
	return STYLE_MULTIPLIERS[style_rank()]


## Adds style for a named trick, halved for each recent use of the same trick. Returns the style
## actually gained.
func add_style(trick: String, points: float) -> float:
	var repeats: float = _fatigue.get(trick, 0.0)
	var gained := points * pow(0.5, repeats)
	_fatigue[trick] = minf(repeats + 1.0, FATIGUE_MAX)
	style = minf(STYLE_MAX, style + gained)
	if not style_feed.is_empty() and style_feed[0].name == trick:
		style_feed[0].count += 1
		style_feed[0].age = 0.0
	else:
		style_feed.push_front({"name": trick, "count": 1, "age": 0.0})
		if style_feed.size() > 5:
			style_feed.pop_back()
	return gained


func lose_style(amount: float) -> void:
	style = maxf(0.0, style - amount)


## Returns the points actually gained after the multiplier.
func add_score(points: int, is_kill: bool) -> int:
	if is_kill:
		combo += 1
		max_combo = maxi(max_combo, combo)
		combo_timer = COMBO_WINDOW
		kills += 1
	var gained := points * multiplier()
	score += gained
	return gained


func kill_ratio() -> float:
	return float(kills) / float(maxi(spawned, 1))


func accuracy() -> float:
	return float(shot_hits) / float(maxi(shots, 1))


## Rank from score per difficulty plus kill ratio and damage taken.
func rank() -> String:
	var points := score / 4000.0
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
