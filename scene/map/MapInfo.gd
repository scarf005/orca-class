extends RichTextLabel


func print_mapinfo(gamemap: Array) -> void:
	for y in Const.MAPSIZE.y:
		push_table(int(Const.MAPSIZE.x))
		for x in Const.MAPSIZE.x:
			push_cell()
			var __ = append_bbcode(
				"%s %s" % [gamemap[x][y].x, gamemap[x][y].y]
			)
			pop()
		pop()

	# print(text)
	# print(bbcode_text)
