extends Node
class_name GameTheoryEngine

# ==============================================================================
# PARADIGMA 6: TEORÍA DE JUEGOS (TOMA DE DECISIONES ESTRATÉGICAS)
# ==============================================================================
# Modela una interacción estratégica en forma normal (bimatriz 2x2) entre:
# - Jugador 1: SPARK (Dron del Jugador)
# - Jugador 2: BOT DE MANTENIMIENTO (Agente de Seguridad)
#
# Capacidades de análisis de teoría de juegos:
# 1. Bimatriz de pagos u_1(a_1, a_2), u_2(a_1, a_2) con presets canónicos.
# 2. Identificación de Estrategias Dominantes (estrictas / débiles).
# 3. Detección de Equilibrios de Nash en Estrategias Puras.
# 4. Cálculo analítico del Equilibrio de Nash en Estrategias Mixtas (p*, q*).
# 5. Detección de Óptimos de Pareto.
# 6. Juego repetido con acumulación de pagos y retroalimentación interactiva.
# ==============================================================================

signal round_resolved(round_data: Dictionary)
signal preset_changed(preset_name: String)

enum PresetType { HAWK_DOVE = 0, PRISONERS_DILEMMA = 1, COORDINATION = 2, STEALTH_COVER = 3 }

@export var p1_name: String = "Spark"
@export var p2_name: String = "Bot"

# Etiquetas de acciones
@export var p1_action_names: Array[String] = ["CAUTO (Stealth)", "AUDAZ (Rush)"]
@export var p2_action_names: Array[String] = ["PATRULLA (Estándar)", "ESCANEO (Estricto)"]

# Matriz de pagos 2x2. Cada celda contiene Vector2(u_Spark, u_Bot)
# Por defecto: Juego del Halcón y la Paloma (Hawk-Dove / Anticoordinación de Recursos)
var payoff_matrix: Array = [
	[Vector2(3.0, 3.0), Vector2(1.0, 4.0)],
	[Vector2(4.0, 1.0), Vector2(0.0, 0.0)]
]

var current_preset: PresetType = PresetType.HAWK_DOVE

# Estadísticas de juego acumulado
var p1_total_score: float = 0.0
var p2_total_score: float = 0.0
var total_rounds: int = 0
var last_round_info: Dictionary = {}

func _ready() -> void:
	load_preset(PresetType.HAWK_DOVE)

# Carga presets canónicos de teoría de juegos
func load_preset(preset: PresetType) -> void:
	current_preset = preset
	match preset:
		PresetType.HAWK_DOVE:
			# Halcón-Paloma: Conflicto por prioridad de paso / recursos
			# (Cauto, Patrulla): (3,3) | (Cauto, Escaneo): (1,4)
			# (Audaz, Patrulla): (4,1) | (Audaz, Escaneo): (0,0) Conflicto
			p1_action_names = ["CAUTO (Stealth)", "AUDAZ (Rush)"]
			p2_action_names = ["PATRULLA (Suave)", "ESCANEO (Estricto)"]
			payoff_matrix = [
				[Vector2(3.0, 3.0), Vector2(1.0, 4.0)],
				[Vector2(4.0, 1.0), Vector2(0.0, 0.0)]
			]
		PresetType.PRISONERS_DILEMMA:
			# Dilema del Prisionero: Cooperar vs Defeccionar
			# (Cooperar, Cooperar): (3,3) | (Cooperar, Defeccionar): (0,5)
			# (Defeccionar, Cooperar): (5,0) | (Defeccionar, Defeccionar): (1,1)
			p1_action_names = ["COOPERAR (Protocolo)", "DEFECCIONAR (Acelerador)"]
			p2_action_names = ["COOPERAR (Ruta libre)", "DEFECCIONAR (Interferencia)"]
			payoff_matrix = [
				[Vector2(3.0, 3.0), Vector2(0.0, 5.0)],
				[Vector2(5.0, 0.0), Vector2(1.0, 1.0)]
			]
		PresetType.COORDINATION:
			# Juego de Coordinación: Puntos de Encuentro
			# (Sincronizar A, A): (4,4) | (A, B): (0,0)
			# (B, A): (0,0)             | (B, B): (2,2)
			p1_action_names = ["CANAL ALFA", "CANAL BETA"]
			p2_action_names = ["CANAL ALFA", "CANAL BETA"]
			payoff_matrix = [
				[Vector2(4.0, 4.0), Vector2(0.0, 0.0)],
				[Vector2(0.0, 0.0), Vector2(2.0, 2.0)]
			]
		PresetType.STEALTH_COVER:
			# Juego de Inspección en la barrera dañada (ventaja asimétrica del Bot)
			# Spark: [OCULTARSE, AVANZAR] | Bot: [BARRIDO INTENSIVO, PATRULLA RÁPIDA]
			# (Ocultarse, Barrido): (-3,4) | (Ocultarse, Patrulla): (3,-1)
			# (Avanzar, Barrido):   (4,-2) | (Avanzar, Patrulla):   (-4,5)
			# Sin Nash puro; mixto: p* = 7/12 = P(Ocultarse), q* = 1/2 = P(Barrido)
			p1_action_names = ["OCULTARSE", "AVANZAR"]
			p2_action_names = ["BARRIDO INTENSIVO", "PATRULLA RÁPIDA"]
			payoff_matrix = [
				[Vector2(-3.0, 4.0), Vector2(3.0, -1.0)],
				[Vector2(4.0, -2.0), Vector2(-4.0, 5.0)]
			]
	
	preset_changed.emit(get_preset_name())

func get_preset_name() -> String:
	match current_preset:
		PresetType.HAWK_DOVE:
			return "Halcón y Paloma (Hawk-Dove)"
		PresetType.PRISONERS_DILEMMA:
			return "Dilema del Prisionero"
		PresetType.COORDINATION:
			return "Juego de Coordinación"
		PresetType.STEALTH_COVER:
			return "Sigilo en Cobertura / Juego de Inspección"
		_:
			return "Personalizado"

# 1. EQUILIBRIOS DE NASH EN ESTRATEGIAS PURAS
# Un perfil (a1*, a2*) es equilibrio si:
# u1(a1*, a2*) >= u1(a1, a2*) para todo a1
# u2(a1*, a2*) >= u2(a1*, a2) para todo a2
func calculate_pure_nash_equilibria() -> Array[Vector2i]:
	var equilibria: Array[Vector2i] = []
	
	for i in range(2):
		for j in range(2):
			var u1_current: float = payoff_matrix[i][j].x
			var u1_alternative: float = payoff_matrix[1 - i][j].x
			var is_p1_best_response: bool = u1_current >= u1_alternative
			
			var u2_current: float = payoff_matrix[i][j].y
			var u2_alternative: float = payoff_matrix[i][1 - j].y
			var is_p2_best_response: bool = u2_current >= u2_alternative
			
			if is_p1_best_response and is_p2_best_response:
				equilibria.append(Vector2i(i, j))
				
	return equilibria

# 2. EQUILIBRIO DE NASH EN ESTRATEGIAS MIXTAS
# Sea p = P(Spark juega Acción 0). Bot debe ser indiferente entre Acción 0 y Acción 1:
# E[U2 | Bot=0] = p*U2(0,0) + (1-p)*U2(1,0)
# E[U2 | Bot=1] = p*U2(0,1) + (1-p)*U2(1,1)
# Igualmente, sea q = P(Bot juega Acción 0). Spark debe ser indiferente.
func calculate_mixed_nash_equilibrium() -> Dictionary:
	var u2_00: float = payoff_matrix[0][0].y
	var u2_01: float = payoff_matrix[0][1].y
	var u2_10: float = payoff_matrix[1][0].y
	var u2_11: float = payoff_matrix[1][1].y
	
	var denom_p: float = (u2_00 - u2_01) + (u2_11 - u2_10)
	var num_p: float = u2_11 - u2_10
	
	var u1_00: float = payoff_matrix[0][0].x
	var u1_01: float = payoff_matrix[0][1].x
	var u1_10: float = payoff_matrix[1][0].x
	var u1_11: float = payoff_matrix[1][1].x
	
	var denom_q: float = (u1_00 - u1_10) + (u1_11 - u1_01)
	var num_q: float = u1_11 - u1_01
	
	var has_interior: bool = false
	var p_star: float = -1.0
	var q_star: float = -1.0
	var exp_u1: float = 0.0
	var exp_u2: float = 0.0
	
	if abs(denom_p) > 1e-6 and abs(denom_q) > 1e-6:
		var candidate_p: float = num_p / denom_p
		var candidate_q: float = num_q / denom_q
		
		if candidate_p >= 0.0 and candidate_p <= 1.0 and candidate_q >= 0.0 and candidate_q <= 1.0:
			has_interior = true
			p_star = candidate_p
			q_star = candidate_q
			
			# Utilidad esperada bajo estrategias mixtas:
			exp_u1 = p_star * (q_star * u1_00 + (1.0 - q_star) * u1_01) + (1.0 - p_star) * (q_star * u1_10 + (1.0 - q_star) * u1_11)
			exp_u2 = q_star * (p_star * u2_00 + (1.0 - p_star) * u2_10) + (1.0 - q_star) * (p_star * u2_01 + (1.0 - p_star) * u2_11)
	
	return {
		"has_mixed_equilibrium": has_interior,
		"p_star": p_star, # Probabilidad de Spark de elegir Acción 0
		"q_star": q_star, # Probabilidad del Bot de elegir Acción 0
		"expected_u1": exp_u1,
		"expected_u2": exp_u2
	}

# 3. ESTRATEGIAS DOMINANTES
func check_dominant_strategies() -> Dictionary:
	# P1
	var p1_dominant: int = -1 # -1 = ninguna, 0 = accion 0, 1 = accion 1
	if payoff_matrix[0][0].x > payoff_matrix[1][0].x and payoff_matrix[0][1].x > payoff_matrix[1][1].x:
		p1_dominant = 0
	elif payoff_matrix[1][0].x > payoff_matrix[0][0].x and payoff_matrix[1][1].x > payoff_matrix[0][1].x:
		p1_dominant = 1
		
	# P2
	var p2_dominant: int = -1
	if payoff_matrix[0][0].y > payoff_matrix[0][1].y and payoff_matrix[1][0].y > payoff_matrix[1][1].y:
		p2_dominant = 0
	elif payoff_matrix[0][1].y > payoff_matrix[0][0].y and payoff_matrix[1][1].y > payoff_matrix[1][0].y:
		p2_dominant = 1
		
	return {
		"p1_dominant": p1_dominant,
		"p2_dominant": p2_dominant
	}

# 4. EFICIENCIA EN EL SENTIDO DE PARETO
# Un resultado no es dominado por ningún otro que mejore a uno sin empeorar al otro
func calculate_pareto_optimal_outcomes() -> Array[Vector2i]:
	var pareto: Array[Vector2i] = []
	for i in range(2):
		for j in range(2):
			var is_dominated: bool = false
			var u1: float = payoff_matrix[i][j].x
			var u2: float = payoff_matrix[i][j].y
			
			for x in range(2):
				for y in range(2):
					if x == i and y == j:
						continue
					var alt_u1: float = payoff_matrix[x][y].x
					var alt_u2: float = payoff_matrix[x][y].y
					if alt_u1 >= u1 and alt_u2 >= u2 and (alt_u1 > u1 or alt_u2 > u2):
						is_dominated = true
						break
				if is_dominated:
					break
			if not is_dominated:
				pareto.append(Vector2i(i, j))
	return pareto

# Ejecuta una ronda del juego estratégico
func play_round(a1: int, a2: int) -> Dictionary:
	a1 = clamp(a1, 0, 1)
	a2 = clamp(a2, 0, 1)
	
	var payoffs: Vector2 = payoff_matrix[a1][a2]
	p1_total_score += payoffs.x
	p2_total_score += payoffs.y
	total_rounds += 1
	
	last_round_info = {
		"round": total_rounds,
		"a1": a1,
		"a1_name": p1_action_names[a1],
		"a2": a2,
		"a2_name": p2_action_names[a2],
		"payoff_p1": payoffs.x,
		"payoff_p2": payoffs.y,
		"total_p1": p1_total_score,
		"total_p2": p2_total_score
	}
	
	round_resolved.emit(last_round_info)
	return last_round_info

# Decisión autónoma del Bot según política
func choose_bot_action(policy: String = "NASH") -> int:
	match policy:
		"NASH":
			var mixed = calculate_mixed_nash_equilibrium()
			if mixed.has_mixed_equilibrium:
				var q_star: float = mixed.q_star
				return 0 if randf() <= q_star else 1
			var pure = calculate_pure_nash_equilibria()
			if pure.size() > 0:
				return pure[0].y
			return 0
		"RANDOM":
			return 0 if randf() < 0.5 else 1
		"DEFENSIVE":
			return 0
		"AGGRESSIVE":
			return 1
		"TIT_FOR_TAT":
			if last_round_info.has("a1"):
				return last_round_info.a1
			return 0
		_:
			return 0

func reset_scores() -> void:
	p1_total_score = 0.0
	p2_total_score = 0.0
	total_rounds = 0
	last_round_info.clear()
