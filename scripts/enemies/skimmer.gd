class_name Skimmer
extends Charger
## Stage 3 dune skimmer: a wedge sled that rides the sand on a cushion of air. It rams like the husk but
## faster and from farther off, so sidestep the marked lane early and shoot it as it drifts past.


func _init() -> void:
	super()
	wreck_on_death = true
	max_hp = 30.0
	hp = 30.0
	radius = 1.5
	center_height = 0.7
	stabbable = true
	score = 300
	walk_speed = 22.0
	charge_speed = 50.0
	wind_time = 0.8
	charge_range = 55.0
	ram_damage = 22.0
	hover = 0.6
	debris = [Fx.Debris.METAL, Fx.Debris.PAINT]
	weakness = {Hit.Kind.BLAST: 1.3, Hit.Kind.THROWN: 1.5}


func build() -> void:
	var body := MeshInstance3D.new()
	body.mesh = ActorMeshes.mesh("skimmer", "body")
	model.add_child(body)
