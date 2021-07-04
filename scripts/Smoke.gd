extends AnimatedSprite

var wait := 0.1
var counter := 0.5


func _ready():
	frame = 0


func _process(delta):
	if frame == 7:
		queue_free()
	if counter > 0:
		counter -= delta
	else:
		counter = wait
		frame += 1
