extends Node
class_name MarkovChain

# ==============================================================================
# PARADIGMA 4: CADENA DE MARKOV (PROCESO ESTOCÁSTICO EN TIEMPO DISCRETO)
# ==============================================================================
# Modela las transiciones del clima espacial / ambiente radiológico de la estación.
# Cumple la propiedad markoviana de pérdida de memoria:
# P(X_{t+1} = s_j | X_t = s_i, X_{t-1} = s_{t-1}, ..., X_0 = s_0) = P_{ij}
#
# Elementos matemáticos:
# 1. Espacio de estados discreto S = {ESTABLE (0), FLUCTUANTE (1), CRÍTICO (2)}
# 2. Matriz de transición P estocástica por filas: sum_j P_{ij} = 1.0
# 3. Distribución estacionaria pi tal que pi * P = pi y sum(pi_i) = 1.0
# 4. Estadísticas empíricas: frecuencias observadas f_i = N_i / N_total
# ==============================================================================

signal state_changed(old_state: int, new_state: int, state_name: String)
signal distribution_updated(stationary: Array, empirical: Array)

enum State { STABLE = 0, FLUCTUATING = 1, CRITICAL = 2 }

@export var state_names: Array[String] = ["ESTABLE", "FLUCTUANTE", "CRÍTICO"]
@export var current_state: int = State.STABLE
@export var auto_step_interval: float = 3.5

# Matriz de probabilidad de transición P (3x3):
# Fila 0 (ESTABLE):     70% permanece estable,    25% pasa a fluctuante, 5% a crítico
# Fila 1 (FLUCTUANTE):  30% retorna a estable,    50% sigue fluctuante,  20% a crítico
# Fila 2 (CRÍTICO):     15% se recupera a estable, 35% pasa a fluctuante, 50% sigue crítico
var transition_matrix: Array = [
	[0.70, 0.25, 0.05],
	[0.30, 0.50, 0.20],
	[0.15, 0.35, 0.50]
]

# Variables de seguimiento empírico (Ley de los Grandes Números)
var total_steps: int = 0
var state_visits: Array[int] = [0, 0, 0]
var transition_counts: Array = [
	[0, 0, 0],
	[0, 0, 0],
	[0, 0, 0]
]

var step_timer: Timer = null
var is_auto_active: bool = false

func _ready() -> void:
	# Inicializa contador con el estado base
	state_visits[current_state] = 1
	total_steps = 1
	_setup_timer()

func _setup_timer() -> void:
	step_timer = Timer.new()
	step_timer.wait_time = auto_step_interval
	step_timer.one_shot = false
	step_timer.autostart = false
	step_timer.timeout.connect(_on_timer_timeout)
	add_child(step_timer)

func set_auto_transition(enabled: bool) -> void:
	is_auto_active = enabled
	if not is_instance_valid(step_timer):
		_setup_timer()
	if enabled:
		step_timer.start(auto_step_interval)
	else:
		step_timer.stop()

func _on_timer_timeout() -> void:
	step()

# Realiza una transición probabilística en la cadena de Markov
func step() -> int:
	var old_state: int = current_state
	var next_state: int = _sample_next_state(old_state)
	
	current_state = next_state
	total_steps += 1
	state_visits[next_state] += 1
	transition_counts[old_state][next_state] += 1
	
	var stat_dist: Array = calculate_stationary_distribution()
	var emp_dist: Array = get_empirical_distribution()
	
	state_changed.emit(old_state, next_state, get_current_state_name())
	distribution_updated.emit(stat_dist, emp_dist)
	
	return current_state

# Muestreo estocástico utilizando probabilidades acumuladas de la fila i de P
func _sample_next_state(from_state: int) -> int:
	var row: Array = transition_matrix[from_state]
	var r: float = randf()
	var cumulative: float = 0.0
	
	for j in range(row.size()):
		cumulative += float(row[j])
		if r <= cumulative:
			return j
	
	return row.size() - 1

# Calcula la distribución estacionaria pi mediante el método de potencias (Power Iteration)
# Resuelve pi * P = pi iterativamente con normalización L1.
func calculate_stationary_distribution(max_iterations: int = 50) -> Array:
	var n: int = transition_matrix.size()
	var pi: Array[float] = []
	for i in range(n):
		pi.append(1.0 / float(n))
	
	for iter in range(max_iterations):
		var next_pi: Array[float] = []
		for j in range(n):
			var sum_val: float = 0.0
			for i in range(n):
				sum_val += pi[i] * float(transition_matrix[i][j])
			next_pi.append(sum_val)
		
		# Normaliza para mantener suma = 1.0 (vector de probabilidad estocástico)
		var total_sum: float = 0.0
		for val in next_pi:
			total_sum += val
		if total_sum > 0.0:
			for k in range(n):
				next_pi[k] /= total_sum
		pi = next_pi
	
	return pi

# Retorna la frecuencia empírica acumulada observada: f_i = N_i / N_total
func get_empirical_distribution() -> Array:
	var emp: Array[float] = []
	if total_steps == 0:
		for i in range(state_names.size()):
			emp.append(0.0)
		return emp
	
	for visits in state_visits:
		emp.append(float(visits) / float(total_steps))
	return emp

func get_current_state_name() -> String:
	if current_state >= 0 and current_state < state_names.size():
		return state_names[current_state]
	return "DESCONOCIDO"

# Modificadores de la simulación según el clima espacial (Markov)
func get_environmental_solar_modifier() -> float:
	match current_state:
		State.STABLE:
			return 1.0       # Tasa nominal (+1.0 %/s)
		State.FLUCTUATING:
			return 0.6       # Radiación intermitente (+0.6 %/s)
		State.CRITICAL:
			return 0.2       # Tormenta electromagnética severa (+0.2 %/s)
		_:
			return 1.0

func get_environmental_bot_speed_multiplier() -> float:
	match current_state:
		State.STABLE:
			return 1.0
		State.FLUCTUATING:
			return 1.1       # Bot incrementa sensores ligeramente
		State.CRITICAL:
			return 1.25      # Protocolo de emergencia del bot (+25% velocidad)
		_:
			return 1.0

func reset_chain() -> void:
	current_state = State.STABLE
	total_steps = 1
	for i in range(state_visits.size()):
		state_visits[i] = 0
	state_visits[State.STABLE] = 1
	
	for i in range(transition_counts.size()):
		for j in range(transition_counts[i].size()):
			transition_counts[i][j] = 0
	
	state_changed.emit(State.STABLE, State.STABLE, get_current_state_name())
	distribution_updated.emit(calculate_stationary_distribution(), get_empirical_distribution())
