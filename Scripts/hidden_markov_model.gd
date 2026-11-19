extends Node
class_name HiddenMarkovModel

# ==============================================================================
# PARADIGMA 5: MODELO OCULTO DE MARKOV (HMM - HIDDEN MARKOV MODEL)
# ==============================================================================
# Modela el desgaste latente del núcleo de la estación espacial (inobservable)
# y las señales de telemetría emitidas por los sensores de diagnóstico.
#
# Tupla λ = (A, B, π0):
# 1. Estados Ocultos S_H = {ÓPTIMO (0), DEGRADADO (1), CRÍTICO (2)}
# 2. Símbolos Observables V = {VERDE/NOMINAL (0), AMARILLO/VIBRACIÓN (1), ROJO/ALARMA (2)}
# 3. Matriz de Transición Oculta A: P(X_{t+1} = h_j | X_t = h_i)
# 4. Matriz de Emisión B: P(Y_t = o_k | X_t = h_j)
# 5. Distribución Inicial π0
#
# Algoritmos implementados:
# - Algoritmo de Forward (Filtrado de Creencia en Tiempo Real): P(X_t | y_{1:t})
# - Algoritmo de Viterbi (Decodificación de la Secuencia Óptima Más Probable):
#   X̂_{1:T} = argmax P(X_{1:T} | Y_{1:T}) en espacio logarítmico con retro-rastreo.
# ==============================================================================

signal telemetry_emitted(observation: int, obs_name: String, true_hidden: int, belief: Array)
signal viterbi_decoded(decoded_path: Array, obs_sequence: Array)

enum HiddenState { OPTIMAL = 0, DEGRADED = 1, CRITICAL = 2 }
enum Observation { GREEN_NOMINAL = 0, YELLOW_VIBRATION = 1, RED_ALARM = 2 }

@export var hidden_state_names: Array[String] = ["ÓPTIMO", "DEGRADADO", "CRÍTICO"]
@export var observation_names: Array[String] = ["VERDE (Nominal)", "AMARILLO (Vibración)", "ROJO (Alarma)"]

# Si es false, emit_telemetry_pulse no recalcula Viterbi (la barrera no lo usa)
@export var auto_viterbi: bool = true

# Matriz A de transición entre estados ocultos (3x3)
var hidden_transition_A: Array = [
	[0.75, 0.20, 0.05],
	[0.10, 0.70, 0.20],
	[0.05, 0.15, 0.80]
]

# Matriz B de probabilidad de emisión (3x3): P(Observación | Estado Oculto)
# Filas: Estados Ocultos (Óptimo, Degradado, Crítico)
# Columnas: Observaciones (Verde, Amarillo, Rojo)
var emission_matrix_B: Array = [
	[0.70, 0.25, 0.05],  # Óptimo: predominantemente Verde
	[0.20, 0.60, 0.20],  # Degradado: predominantemente Amarillo
	[0.05, 0.25, 0.70]   # Crítico: predominantemente Rojo
]

var initial_pi: Array[float] = [0.70, 0.20, 0.10]

# Estado oculto verdadero actual (simulado por el entorno)
var current_true_hidden_state: int = HiddenState.OPTIMAL

# Estado de creencia probabilística actual α_t (Forward filter)
var current_belief: Array[float] = [0.70, 0.20, 0.10]

# Historial de secuencias registradas
var observation_history: Array[int] = []
var true_hidden_history: Array[int] = []
var viterbi_decoded_history: Array[int] = []

func _ready() -> void:
	reset_hmm()

# Genera una nueva lectura de telemetría:
# 1. El estado oculto verdadero evoluciona mediante la matriz A
# 2. El sensor emite una señal observable según la matriz B
# 3. El filtro Forward actualiza la creencia posterior P(X_t | Y_{1:t})
func emit_telemetry_pulse() -> int:
	# 1. Transición de estado oculto en el núcleo
	current_true_hidden_state = _sample_from_row(hidden_transition_A[current_true_hidden_state])
	true_hidden_history.append(current_true_hidden_state)
	
	# 2. Generación de emisión observada por los sensores
	var obs: int = _sample_from_row(emission_matrix_B[current_true_hidden_state])
	observation_history.append(obs)
	
	# 3. Paso del Algoritmo Forward (Filtrado predictivo)
	current_belief = _step_forward_belief(obs)
	
	# 4. Decodificación Viterbi acumulada (se omite si auto_viterbi = false)
	if auto_viterbi:
		viterbi_decoded_history = viterbi_decode(observation_history)
	
	var obs_name: String = observation_names[obs]
	telemetry_emitted.emit(obs, obs_name, current_true_hidden_state, current_belief)
	if auto_viterbi:
		viterbi_decoded.emit(viterbi_decoded_history, observation_history)
	
	return obs

# Paso del algoritmo Forward para filtrado de creencia continua
# α_t(j) = [ Σ_i α_{t-1}(i) * A_{ij} ] * B_{j, y_t}
func _step_forward_belief(new_obs: int) -> Array[float]:
	var n: int = hidden_state_names.size()
	var unnormalized: Array[float] = []
	var total_prob: float = 0.0
	
	for j in range(n):
		var transition_sum: float = 0.0
		for i in range(n):
			transition_sum += current_belief[i] * float(hidden_transition_A[i][j])
		var val: float = transition_sum * float(emission_matrix_B[j][new_obs])
		unnormalized.append(val)
		total_prob += val
	
	var normalized: Array[float] = []
	if total_prob > 0.0:
		for j in range(n):
			normalized.append(unnormalized[j] / total_prob)
	else:
		# Fallback uniforme si probabilidad es infinitesimal
		for j in range(n):
			normalized.append(1.0 / float(n))
			
	return normalized

# Algoritmo de Viterbi completo:
# Encuentra la secuencia de estados ocultos más probable dada la secuencia de observaciones Y.
# Implementado con suma de logaritmos para garantizar estabilidad numérica.
func viterbi_decode(obs_sequence: Array = []) -> Array[int]:
	if obs_sequence.is_empty():
		return []
	
	var t_len: int = obs_sequence.size()
	var n_states: int = hidden_state_names.size()
	
	# Matrices de programación dinámica:
	# viterbi_table[t][j] almacena el logaritmo de la probabilidad de la trayectoria más probable
	# backpointers[t][j] almacena el estado previo que maximizó dicha probabilidad
	var viterbi_table: Array = []
	var backpointers: Array = []
	
	for t in range(t_len):
		var v_row: Array[float] = []
		var b_row: Array[int] = []
		for j in range(n_states):
			v_row.append(-1e9) # -infinito aproximado
			b_row.append(0)
		viterbi_table.append(v_row)
		backpointers.append(b_row)
	
	# 1. Inicialización en t = 0
	# La primera observación se emite tras UNA transición (igual que en el filtro
	# Forward y en emit_telemetry_pulse), así que se usa el prior predicho
	# prior_j = Σ_i π0(i)·A[i][j] en lugar de π0 directamente.
	var first_obs: int = obs_sequence[0]
	for j in range(n_states):
		var predicted_prior: float = 0.0
		for i in range(n_states):
			predicted_prior += initial_pi[i] * float(hidden_transition_A[i][j])
		var p_prior: float = max(1e-12, predicted_prior)
		var p_emiss: float = max(1e-12, float(emission_matrix_B[j][first_obs]))
		viterbi_table[0][j] = log(p_prior) + log(p_emiss)
		backpointers[0][j] = 0
	
	# 2. Inducción recursiva para t = 1 ... T-1
	for t in range(1, t_len):
		var current_obs: int = obs_sequence[t]
		for j in range(n_states):
			var max_log_prob: float = -1e9
			var best_prev_state: int = 0
			var p_emiss: float = max(1e-12, float(emission_matrix_B[j][current_obs]))
			
			for i in range(n_states):
				var p_trans: float = max(1e-12, float(hidden_transition_A[i][j]))
				var candidate: float = viterbi_table[t - 1][i] + log(p_trans)
				if candidate > max_log_prob:
					max_log_prob = candidate
					best_prev_state = i
			
			viterbi_table[t][j] = max_log_prob + log(p_emiss)
			backpointers[t][j] = best_prev_state
	
	# 3. Terminación: identificar el estado con mayor probabilidad final en T-1
	var best_last_state: int = 0
	var highest_final_prob: float = -1e9
	for j in range(n_states):
		if viterbi_table[t_len - 1][j] > highest_final_prob:
			highest_final_prob = viterbi_table[t_len - 1][j]
			best_last_state = j
	
	# 4. Retro-rastreo (Traceback) para reconstruir la trayectoria de estados óptima
	var optimal_path: Array[int] = []
	for step in range(t_len):
		optimal_path.append(0)
	
	optimal_path[t_len - 1] = best_last_state
	for t in range(t_len - 2, -1, -1):
		optimal_path[t] = backpointers[t + 1][optimal_path[t + 1]]
	
	return optimal_path

# Muestreo categórico aleatorio a partir de una fila de probabilidades
func _sample_from_row(probabilities: Array) -> int:
	var r: float = randf()
	var cumulative: float = 0.0
	for idx in range(probabilities.size()):
		cumulative += float(probabilities[idx])
		if r <= cumulative:
			return idx
	return probabilities.size() - 1

func get_true_state_name() -> String:
	return hidden_state_names[current_true_hidden_state]

func get_latest_observation_name() -> String:
	if observation_history.is_empty():
		return "SIN OBSERVACIONES"
	return observation_names[observation_history.back()]

func get_latest_viterbi_state_name() -> String:
	if viterbi_decoded_history.is_empty():
		return "DESCONOCIDO"
	return hidden_state_names[viterbi_decoded_history.back()]

func reset_hmm() -> void:
	current_true_hidden_state = HiddenState.OPTIMAL
	current_belief.clear()
	for val in initial_pi:
		current_belief.append(val)
	observation_history.clear()
	true_hidden_history.clear()
	viterbi_decoded_history.clear()

# ==============================================================================
# EXTENSIÓN: HMM DE LA BARRERA DAÑADA (SEGUNDA INSTANCIA, N = 2 ESTADOS)
# ==============================================================================
# El mismo motor sirve para otro modelo λ = (A, B, π0). Los métodos Forward,
# Viterbi y de emisión ya son genéricos en N, así que solo se reemplazan las
# matrices. Los valores por defecto de telemetría (3 estados) NO se modifican.

# Reemplaza λ = (A, B, π0) y los nombres de estados/observaciones, y reinicia.
func configure(state_names: Array, obs_names: Array, a_matrix: Array, b_matrix: Array, pi: Array) -> void:
	hidden_state_names.clear()
	for s in state_names:
		hidden_state_names.append(str(s))
	observation_names.clear()
	for o in obs_names:
		observation_names.append(str(o))
	hidden_transition_A = a_matrix.duplicate(true)
	emission_matrix_B = b_matrix.duplicate(true)
	initial_pi.clear()
	for p in pi:
		initial_pi.append(float(p))
	reset_hmm()

# Sortea el estado oculto verdadero desde π0 (p. ej. al iniciar cada corrida)
func resample_true_state() -> void:
	current_true_hidden_state = _sample_from_row(initial_pi)

# Diagnóstico de la barrera: emite `pulses` ecos, filtra con Forward y aplica
# la regla de decisión P(estado 0 | Y_{1:t}) >= umbral  →  FRACTURAR, si no RODEAR.
# Convención del modelo de la barrera: estado 0 = FRÁGIL, estado 1 = BLINDADO.
func diagnose_obstacle(pulses: int = 3, threshold: float = 0.65) -> Dictionary:
	var echoes: Array[int] = []
	for i in range(pulses):
		echoes.append(emit_telemetry_pulse())
	var belief_fragil: float = current_belief[0]
	return {
		"observations": echoes,
		"belief_fragil": belief_fragil,
		"decision": "FRACTURAR" if belief_fragil >= threshold else "RODEAR",
		"true_state": current_true_hidden_state
	}
