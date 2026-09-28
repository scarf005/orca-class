class_name Icons
## Pixel-art HUD icons drawn cell by cell. Letters pick colors: K ink outline, W highlight, A tint,
## D tint shadow, L tint light, B brass, O dark brass, G stone, M metal, H hull, h hull light,
## P pine, R hot. Anything else is transparent.

const SPRITES := {
	"shield": [
		"...KKKKKKKKKK...",
		"..KLLLLLLLLLAK..",
		".KLWAAAAAAAAADK.",
		".KLAAAAKKAAAADK.",
		".KLAAAKWWKAAADK.",
		".KLAAKWAAWKAADK.",
		".KLAAKAAAAKAADK.",
		".KLAAAKAAKAAADK.",
		".KLAAAAKKAAAADK.",
		"..KLAAAAAAAADK..",
		"..KLAAAAAAAADK..",
		"...KLAAAAAADK...",
		"....KLAAAADK....",
		".....KLAADK.....",
		"......KDDK......",
		".......KK.......",
	],
	"tail": [
		"..........KKK...",
		".........KAWAK.K",
		"........KAAAKKAK",
		"....KKK.KDAK.KAK",
		"...KAWAKKDAK.KAK",
		"..KAAAAKKAAKKAK.",
		"..KDAAAKKAAAAK..",
		".KKKDDKKKDAAK...",
		"KAWAKKAWAKKK....",
		"KAAAKKAAAK......",
		"KDAAKKDAAK......",
		".KDDK.KDDK......",
		"..KK...KK.......",
	],
	"shell": [
		"..KKKKKKKKKKKK......",
		".KOBBBBBBBBBOKKKK...",
		".KOBWWWWWWWBOKLAAK..",
		".KOBBBBBBBBBOKAAWAK.",
		".KOBBBBBBBBBOKAAAAAK",
		".KOOOOOOOOOOOKDAAAK.",
		".KOBBBBBBBBBOKDDDK..",
		"..KKKKKKKKKKKKKKK...",
	],
	"laser": [
		"......KKKK......",
		".....KhhhhK.....",
		"...KKhWhhhhKKKK.",
		"..KHHHHHHHHKAAAK",
		"..KHKKKKKKHKLWAK",
		"..KHHHHHHHHKAAAK",
		"...KKKHHKKKKKKK.",
		".....KGGK.......",
		"....KGMMGK......",
		"...KKKKKKKK.....",
	],
	"tank": [
		".....KKKK..........",
		"....KhhhhKKKKKKKK..",
		"...KhWhhhhHHHHHHK..",
		"..KKKKHHHKKKKKKKK..",
		".KhhhhhhhhhhhhhK...",
		"KHHHHHHHHHHHHHHHK..",
		"KKGKKGKKGKKGKKGK...",
		".KKKKKKKKKKKKKKK...",
	],
	"boost": [
		"KK.....KK......",
		"KAK....KAK.....",
		"KLAK...KLAK....",
		".KLAK...KLAK...",
		"..KLAK...KLAK..",
		"..KDAK...KDAK..",
		".KDAK...KDAK...",
		"KDAK...KDAK....",
		"KAK....KAK.....",
		"KK.....KK......",
	],
}


static func draw(canvas: CanvasItem, name: String, at: Vector2, tint: Color, scale := 1.0, mirror := false) -> void:
	var rows: Array = SPRITES[name]
	var width: int = (rows[0] as String).length()
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			var color := _color(row[x], tint)
			if color.a == 0.0:
				continue
			var px := (width - 1 - x) if mirror else x
			canvas.draw_rect(Rect2(at + Vector2(px, y) * scale, Vector2.ONE * scale), color)


static func size(name: String) -> Vector2:
	var rows: Array = SPRITES[name]
	return Vector2((rows[0] as String).length(), rows.size())


static func _color(letter: String, tint: Color) -> Color:
	match letter:
		"K": return Palette.INK
		"W": return Palette.WHITE
		"A": return tint
		"D": return tint.darkened(0.35)
		"L": return tint.lightened(0.35)
		"B": return Palette.BUTTER
		"O": return Palette.OCHRE
		"G": return Palette.STONE
		"M": return Palette.ASH
		"H": return Palette.HULL
		"h": return Palette.HULL_LIGHT
		"P": return Palette.PINE
		"R": return Palette.HOT
	return Color(0, 0, 0, 0)


## A cartridge standing upright, sized by caliber: brass case with rim and neck, tinted bullet.
static func cartridge(canvas: CanvasItem, at: Vector2, caliber: int, tint: Color) -> void:
	var w := 3 + caliber / 6
	var case_h := 5 + caliber / 3
	var tip_h := 3 + caliber / 7
	var o := at
	# Outline.
	canvas.draw_rect(Rect2(o + Vector2(-1, tip_h - 1), Vector2(w + 2, case_h + 2)), Palette.INK)
	canvas.draw_rect(Rect2(o + Vector2(0, 0), Vector2(w, tip_h)), Palette.INK)
	canvas.draw_rect(Rect2(o + Vector2(-1, 1), Vector2(w + 2, tip_h)), Palette.INK)
	# Bullet with a highlight, then the case with rim and a shine.
	canvas.draw_rect(Rect2(o + Vector2(1, 1), Vector2(maxi(w - 2, 1), 1)), tint.lightened(0.3))
	canvas.draw_rect(Rect2(o + Vector2(0, 2), Vector2(w, tip_h - 1)), tint)
	canvas.draw_rect(Rect2(o + Vector2(0, tip_h), Vector2(w, case_h)), Palette.BUTTER)
	canvas.draw_rect(Rect2(o + Vector2(w - 1, tip_h), Vector2(1, case_h)), Palette.OCHRE)
	canvas.draw_rect(Rect2(o + Vector2(1, tip_h + 1), Vector2(1, case_h - 2)), Palette.WHITE)
	canvas.draw_rect(Rect2(o + Vector2(-1, tip_h + case_h - 1), Vector2(w + 2, 2)), Palette.OCHRE)
