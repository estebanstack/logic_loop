extends Node2D
class_name BayesSearch

# ==============================================================================
# PARADIGMA 7: BÚSQUEDA BAYESIANA (FILTRO DE BAYES SOBRE LA CUADRÍCULA DE SPARK)
# ==============================================================================
# Cuando el Bot pierde a Spark ya no camina solo a la última posición conocida:
# mantiene una CREENCIA b(c) = P(Spark está en la casilla c) y la actualiza:
#   1. PREDICCIÓN (modelo de movimiento):  b'(c) = Σ_n b(n) · T(n → c)
#   2. ACTUALIZACIÓN (información negativa): b(c) ∝ b(c) · L(c)
#      con L(c) = 1 − P_d si c está dentro del radio de visión y no se vio a Spark,
#      y L(c) = 1 fuera. P_d < 1 mantiene la coherencia con el camuflaje.
# El Bot va a la casilla más probable (estimador MAP).
# Esta clase NO conoce a Main: el bloqueo de casillas llega como un Callable.
# ==============================================================================

signal belief_changed

# Cuadrícula de Spark: x = 150 + 64 i, y = 600 - 64 j, con i, j = 0..9
const GRID_N: int = 10
const ORIGIN: Vector2 = Vector2(150, 600)
const CELL: float = 64.0

const P_DETECT: float = 0.9         # P_d: probabilidad de ver a Spark si está dentro del radio
const STAY_PROB: float = 0.2        # Fracción de masa que se queda en su casilla en cada paso
const START_CENTER: float = 0.6     # Masa inicial en la casilla de la última posición conocida
const TICK: float = 0.5             # s por paso del modelo (igual que los pasos de Spark)
const GIVE_UP_PROB: float = 0.05    # Si la casilla más probable baja de este valor, el Bot se rinde
const MAX_SEARCH_TIME: float = 10.0 # s máximos de búsqueda antes de volver a patrullar

var is_blocked: Callable = Callable()   # (Vector2) -> bool; la inyecta Main
var belief: Array[float] = []
var active: bool = false
var elapsed: float = 0.0
var _tick_acc: float = 0.0

func _init() -> void:
	belief.resize(GRID_N * GRID_N)
	belief.fill(0.0)

func setup(blocked: Callable) -> void:
	is_blocked = blocked

# ------------------------------------------------------------------------------
# Utilidades de cuadrícula (índice = i + j · GRID_N)
# ------------------------------------------------------------------------------
func cell_pos(idx: int) -> Vector2:
	return Vector2(ORIGIN.x + CELL * float(idx % GRID_N), ORIGIN.y - CELL * float(idx / GRID_N))

func nearest_index(pos: Vector2) -> int:
	var i: int = clampi(roundi((pos.x - ORIGIN.x) / CELL), 0, GRID_N - 1)
	var j: int = clampi(roundi((ORIGIN.y - pos.y) / CELL), 0, GRID_N - 1)
	return i + j * GRID_N

func _blocked(idx: int) -> bool:
	return is_blocked.is_valid() and bool(is_blocked.call(cell_pos(idx)))

# Vecinos en 4 direcciones que están dentro de la cuadrícula y no están bloqueados
func free_neighbours(idx: int) -> Array[int]:
	var result: Array[int] = []
	var i: int = idx % GRID_N
	var j: int = idx / GRID_N
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var ni: int = i + d.x
		var nj: int = j + d.y
		if ni < 0 or ni >= GRID_N or nj < 0 or nj >= GRID_N:
			continue
		var n: int = ni + nj * GRID_N
		if not _blocked(n):
			result.append(n)
	return result

# ------------------------------------------------------------------------------
# Creencia inicial, predicción, actualización
# ------------------------------------------------------------------------------
# Masa inicial: 0.6 en la casilla más cercana a `pos`, el resto repartido en sus vecinas libres
func start(pos: Vector2) -> void:
	belief.fill(0.0)
	var c: int = nearest_index(pos)
	var neighbours: Array[int] = free_neighbours(c)
	if neighbours.is_empty():
		belief[c] = 1.0
	else:
		if not _blocked(c):
			belief[c] = START_CENTER
		for n in neighbours:
			belief[n] += (1.0 - START_CENTER) / float(neighbours.size())
		_normalize()
	active = true
	elapsed = 0.0
	_tick_acc = 0.0
	queue_redraw()
	belief_changed.emit()

# Modelo de movimiento: cada casilla conserva STAY_PROB y reparte el resto en partes iguales
# entre sus vecinas libres. Sin vecinas libres, toda la masa se queda. Conserva Σ b = 1.
func predict() -> void:
	var next: Array[float] = []
	next.resize(belief.size())
	next.fill(0.0)
	for c in range(belief.size()):
		var m: float = belief[c]
		if m <= 0.0:
			continue
		var neighbours: Array[int] = free_neighbours(c)
		if neighbours.is_empty():
			next[c] += m
			continue
		next[c] += STAY_PROB * m
		for n in neighbours:
			next[n] += (1.0 - STAY_PROB) * m / float(neighbours.size())
	belief = next
	queue_redraw()
	belief_changed.emit()

# Observación. Si se vio a Spark, la creencia colapsa a su casilla. Si no, las casillas
# dentro del radio se multiplican por (1 − P_d) y se normaliza (información negativa).
func update(bot_pos: Vector2, radius: float, seen: bool, spark_pos: Vector2 = Vector2.ZERO) -> void:
	if seen:
		belief.fill(0.0)
		belief[nearest_index(spark_pos)] = 1.0
	else:
		for c in range(belief.size()):
			if cell_pos(c).distance_to(bot_pos) <= radius:
				belief[c] *= (1.0 - P_DETECT)
		_normalize()
	queue_redraw()
	belief_changed.emit()

func _normalize() -> void:
	var total: float = 0.0
	for b in belief:
		total += b
	if total <= 0.0:
		return
	for c in range(belief.size()):
		belief[c] /= total

# ------------------------------------------------------------------------------
# Resúmenes de la creencia
# ------------------------------------------------------------------------------
func map_index() -> int:
	var best: int = 0
	for c in range(belief.size()):
		if belief[c] > belief[best]:
			best = c
	return best

# Estimador MAP: posición (px) de la casilla más probable
func map_cell() -> Vector2:
	return cell_pos(map_index())

func max_prob() -> float:
	return belief[map_index()]

# Entropía de Shannon en bits: 0 = certeza total, log2(100) ≈ 6.64 = ignorancia total
func entropy() -> float:
	var h: float = 0.0
	for b in belief:
		if b > 0.0:
			h -= b * log(b) / log(2.0)
	return h

func clear() -> void:
	belief.fill(0.0)
	active = false
	elapsed = 0.0
	_tick_acc = 0.0
	queue_redraw()
	belief_changed.emit()

# ------------------------------------------------------------------------------
# Uso desde el juego: un paso del filtro cada TICK segundos
# ------------------------------------------------------------------------------
# Devuelve la casilla objetivo (MAP) hacia la que debe ir el Bot
func step(bot_pos: Vector2, radius: float, delta: float) -> Vector2:
	elapsed += delta
	_tick_acc += delta
	while _tick_acc >= TICK:
		_tick_acc -= TICK
		predict()
		update(bot_pos, radius, false)
	return map_cell()

# ¿Conviene rendirse? Creencia demasiado difusa o demasiado tiempo buscando
func is_exhausted() -> bool:
	return max_prob() < GIVE_UP_PROB or elapsed >= MAX_SEARCH_TIME

# Mapa de calor: transparencia y color proporcionales a b / b_max (ámbar → rojo)
func _draw() -> void:
	if not active:
		return
	var mx: float = max_prob()
	if mx <= 0.0:
		return
	for c in range(belief.size()):
		if belief[c] <= 0.0:
			continue
		var t: float = belief[c] / mx
		var color: Color = Color(1.0, 0.75, 0.1).lerp(Color(1.0, 0.1, 0.1), t)
		color.a = 0.6 * t
		draw_rect(Rect2(cell_pos(c) - Vector2(30, 30), Vector2(60, 60)), color)
