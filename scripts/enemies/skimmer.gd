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
	var b := LowPoly.new()
	b.frustum(Transform3D(), Vector2(1.6, 4.4), Vector2(1.0, 3.4), 0.7, Palette.SLATE, Palette.CORAL)
	b.blob(Transform3D(Basis().scaled(Vector3(1.0, 0.7, 1.4)), Vector3(0, 0.85, 0.2)), 0.55, Palette.SKY)
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(Vector3.FORWARD, side * 0.25), Vector3(side * 1.2, 0.2, 0.6)), Vector3(0.9, 0.12, 2.6), Palette.DUSK)
	b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.35, -2.1)), 0.35, 1.6, 5, Palette.CREAM, 0.02)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0, 0.35, 2.25)), Vector3(0.9, 0.25, 0.15), Palette.AMBER)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)
