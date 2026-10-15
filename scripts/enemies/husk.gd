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
	var b := LowPoly.new()
	b.blob(Transform3D(Basis().scaled(Vector3(1.1, 0.8, 1.5)), Vector3(0, 1.3, 0)), 1.4, Palette.MAUVE, 1, 0.12, 3)
	b.blob(Transform3D(Basis().scaled(Vector3(0.8, 0.7, 0.9)), Vector3(0, 1.4, -1.6)), 0.9, Palette.LILAC, 0, 0.1, 5)
	b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 1.5, -2.2)), 0.3, 1.7, 5, Palette.CREAM, 0.02)
	for i in 3:
		b.blob(Transform3D(Basis(), Vector3((i - 1) * 0.6, 2.2 - absf(i - 1) * 0.2, 0.3 + i * 0.3)), 0.5, Palette.FUNGUS, 0, 0.3, i)
	for side in [-1.0, 1.0]:
		for z in [-0.8, 0.5, 1.5]:
			b.prism(Transform3D(Basis(Vector3.FORWARD, side * 1.0), Vector3(side * 0.9, 0.9, z)), 0.16, 1.2, 5, Palette.DUSK, 0.08)
	b.glow = true
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(), Vector3(side * 0.4, 1.7, -2.4)), Vector3(0.2, 0.15, 0.1), Palette.HOT)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)


func damage_multiplier(hit: Hit) -> float:
	return super(hit) * frontal_armor(hit, FRONT_ARMOR)


func on_death(hit: Hit) -> void:
	soft_death(hit)
