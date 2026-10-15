class_name Husk
extends Charger
## Stage 1 fungal rhino beetle. Its horned shell turns the coax from the front; flank it, burn it or
## shoot its charge lane clear with a shell.

const FRONT_ARMOR := 0.25 ## Share of coax damage that gets through the horned shell.


func _init() -> void:
	super()
	max_hp = 45.0
	hp = 45.0
	radius = 1.6
	center_height = 1.1
	stabbable = true
	score = 300
	walk_speed = 11.0
	charge_speed = 34.0
	ram_damage = 24.0
	debris = [Fx.Debris.FLESH, Fx.Debris.SPORE]
	weakness = {Hit.Kind.FIRE: 2.0, Hit.Kind.TAIL: 1.5}


func build() -> void:
	var body := MeshInstance3D.new()
	body.mesh = ActorMeshes.mesh("husk", "body")
	model.add_child(body)


func damage_multiplier(hit: Hit) -> float:
	return super(hit) * frontal_armor(hit, FRONT_ARMOR)


func on_death(hit: Hit) -> void:
	soft_death(hit)
