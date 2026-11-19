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
		draw_rect(rect, Color(0.20, 0.24, 0.32))
		draw_rect(rect, Color(0.40, 0.48, 0.62), false, 2.0)
