extends Node2D

# Fondo de la estación dibujado por código (sin assets). Se dibuja una sola vez:
# no hay redibujado por cuadro. Modos:
#   PLAYFIELD → piso degradado del área de juego + líneas de la cuadrícula de
#               Spark (64 px, alineadas a sus casillas) + pocas estrellas fuera de ella.
#   TITLE     → campo de estrellas a pantalla completa para el menú.

enum Mode { PLAYFIELD, TITLE }

@export var mode: Mode = Mode.PLAYFIELD

const PLAYFIELD_SIZE: Vector2 = Vector2(790, 720)
const SCREEN_SIZE: Vector2 = Vector2(1280, 720)
# Casillas de Spark: centros x = 150 + 64 i, y = 600 - 64 j; las líneas van en los bordes
const GRID_X0: float = 118.0
const GRID_Y_TOP: float = -8.0
const GRID_CELL: float = 64.0
const GRID_LINES: int = 11
const GRID_COLOR: Color = Color(0.5, 0.85, 1.0, 0.07)

func _draw() -> void:
	if mode == Mode.TITLE:
		_draw_gradient(SCREEN_SIZE, Color(0.02, 0.03, 0.07), Color(0.06, 0.1, 0.18))
		_draw_stars(SCREEN_SIZE, 140, Rect2())
		return
	_draw_gradient(PLAYFIELD_SIZE, Color(0.04, 0.07, 0.12), Color(0.07, 0.11, 0.19))
	var grid_rect: Rect2 = Rect2(GRID_X0, GRID_Y_TOP, GRID_CELL * (GRID_LINES - 1), GRID_CELL * (GRID_LINES - 1))
	for i in range(GRID_LINES):
		var x: float = GRID_X0 + GRID_CELL * i
		var y: float = GRID_Y_TOP + GRID_CELL * i
		draw_line(Vector2(x, grid_rect.position.y), Vector2(x, grid_rect.end.y), GRID_COLOR, 1.0)
		draw_line(Vector2(grid_rect.position.x, y), Vector2(grid_rect.end.x, y), GRID_COLOR, 1.0)
	_draw_stars(PLAYFIELD_SIZE, 45, grid_rect)

# Degradado vertical con un polígono de 4 vértices coloreados
func _draw_gradient(size: Vector2, top: Color, bottom: Color) -> void:
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)

# Estrellas estáticas (semilla fija); se omiten las que caerían dentro de `exclude`
func _draw_stars(size: Vector2, count: int, exclude: Rect2) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260
	for i in range(count):
		var p: Vector2 = Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var radius: float = 0.8 + rng.randf() * 1.2
		var alpha: float = 0.25 + rng.randf() * 0.55
		if exclude.has_point(p):
			continue
		draw_circle(p, radius, Color(0.8, 0.9, 1.0, alpha))
