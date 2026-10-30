extends Node2D
## One draw layer of the world. WorldView does the drawing; this just orders it.

var view
var kind := ""

func _draw() -> void:
	if view:
		view.draw_layer(self, kind)
