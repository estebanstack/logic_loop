extends Node2D

# Dibuja las casillas de muro que Main declara bloqueadas para Spark.
# Es solo visual: el bloqueo real lo decide Main.is_cell_blocked().

const HALF_SIZE: float = 28.0

func _draw() -> void:
	var environment: Node = get_parent()
	if environment == null or not environment.has_method("get_wall_cells"):
		return
	for cell in environment.get_wall_cells():
		var rect: Rect2 = Rect2(cell - Vector2(HALF_SIZE, HALF_SIZE), Vector2(HALF_SIZE, HALF_SIZE) * 2.0)
		draw_rect(rect, Color(0.13, 0.19, 0.29))
		draw_rect(rect, Color(0.36, 0.62, 0.82), false, 2.0)
