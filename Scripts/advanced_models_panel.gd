extends PanelContainer
class_name AdvancedModelsPanel

# ==============================================================================
# DASHBOARD DE MODELOS Y SIMULACIÓN AVANZADA
# ==============================================================================
# Integra en pestañas de interfaz los cuatro modelos matemáticos:
# 1. Cadenas de Markov (Clima Espacial / Fluctuaciones)
# 2. Modelos Ocultos de Markov (HMM - Diagnóstico de Desgaste Latente del Núcleo)
# 3. Teoría de Juegos (Estrategias de Interacción Spark vs Bot)
# 4. Búsqueda Bayesiana (Creencia del Bot sobre la posición de Spark)
# ==============================================================================

# Referencias a los motores matemáticos (asignados por Main o buscados en árbol)
var markov_chain: MarkovChain = null
var hmm: HiddenMarkovModel = null
var game_theory: GameTheoryEngine = null
var bayes: BayesSearch = null

# Referencias a nodos UI
@onready var tab_container: TabContainer = get_node_or_null("Margin/VBox/TabContainer")

# --- UI MARKOV ---
@onready var markov_state_label: Label = get_node_or_null("Margin/VBox/TabContainer/MarkovTab/StateLabel")
@onready var markov_matrix_label: Label = get_node_or_null("Margin/VBox/TabContainer/MarkovTab/MatrixLabel")
@onready var markov_dist_label: Label = get_node_or_null("Margin/VBox/TabContainer/MarkovTab/DistLabel")
@onready var markov_effect_label: Label = get_node_or_null("Margin/VBox/TabContainer/MarkovTab/EffectLabel")
@onready var btn_markov_step: Button = get_node_or_null("Margin/VBox/TabContainer/MarkovTab/HBox/BtnMarkovStep")
@onready var btn_markov_auto: Button = get_node_or_null("Margin/VBox/TabContainer/MarkovTab/HBox/BtnMarkovAuto")

# --- UI HMM ---
@onready var hmm_hidden_label: Label = get_node_or_null("Margin/VBox/TabContainer/HMMTab/HiddenStateLabel")
@onready var hmm_obs_label: Label = get_node_or_null("Margin/VBox/TabContainer/HMMTab/ObsLabel")
@onready var hmm_belief_label: Label = get_node_or_null("Margin/VBox/TabContainer/HMMTab/BeliefLabel")
@onready var hmm_viterbi_label: Label = get_node_or_null("Margin/VBox/TabContainer/HMMTab/ViterbiLabel")
@onready var btn_hmm_pulse: Button = get_node_or_null("Margin/VBox/TabContainer/HMMTab/HBox/BtnHMMPulse")
@onready var btn_hmm_reset: Button = get_node_or_null("Margin/VBox/TabContainer/HMMTab/HBox/BtnHMMReset")

# --- UI TEORÍA DE JUEGOS ---
@onready var gt_preset_btn: Button = get_node_or_null("Margin/VBox/TabContainer/GameTheoryTab/HBoxPreset/BtnPreset")
@onready var gt_matrix_label: Label = get_node_or_null("Margin/VBox/TabContainer/GameTheoryTab/MatrixLabel")
@onready var gt_nash_label: Label = get_node_or_null("Margin/VBox/TabContainer/GameTheoryTab/NashLabel")
@onready var gt_strategy_btn: Button = get_node_or_null("Margin/VBox/TabContainer/GameTheoryTab/HBoxAction/BtnSparkStrategy")
@onready var gt_play_btn: Button = get_node_or_null("Margin/VBox/TabContainer/GameTheoryTab/HBoxAction/BtnPlayRound")
@onready var gt_score_label: Label = get_node_or_null("Margin/VBox/TabContainer/GameTheoryTab/ScoreLabel")

# --- UI BÚSQUEDA BAYESIANA ---
@onready var bayes_state_label: Label = get_node_or_null("Margin/VBox/TabContainer/BayesTab/StateLabel")
@onready var bayes_map_label: Label = get_node_or_null("Margin/VBox/TabContainer/BayesTab/MapLabel")
@onready var bayes_stats_label: Label = get_node_or_null("Margin/VBox/TabContainer/BayesTab/StatsLabel")
@onready var bayes_model_label: Label = get_node_or_null("Margin/VBox/TabContainer/BayesTab/ModelLabel")

# Estrategia seleccionada actualmente para Spark en Teoría de Juegos (0=Cauto, 1=Audaz)
var spark_chosen_strategy: int = 0

# Títulos legibles de las pestañas (el orden coincide con los hijos del TabContainer)
const TAB_TITLES: Array[String] = ["Markov", "HMM", "Teoría de Juegos", "IA Bayesiana"]

func _ready() -> void:
	if tab_container:
		for i in range(mini(TAB_TITLES.size(), tab_container.get_tab_count())):
			tab_container.set_tab_title(i, TAB_TITLES[i])
	_connect_signals()

func setup_engines(mc: MarkovChain, h: HiddenMarkovModel, gt: GameTheoryEngine, bs: BayesSearch = null) -> void:
	markov_chain = mc
	hmm = h
	game_theory = gt
	bayes = bs
	
	if markov_chain:
		markov_chain.state_changed.connect(_on_markov_state_changed)
		markov_chain.distribution_updated.connect(_on_markov_distribution_updated)
	
	if hmm:
		hmm.telemetry_emitted.connect(_on_hmm_telemetry_emitted)
		hmm.viterbi_decoded.connect(_on_hmm_viterbi_decoded)
		
	if game_theory:
		game_theory.round_resolved.connect(_on_gt_round_resolved)
		game_theory.preset_changed.connect(_on_gt_preset_changed)

	if bayes:
		bayes.belief_changed.connect(update_bayes_ui)
	
	refresh_all_ui()

func _connect_signals() -> void:
	if btn_markov_step:
		btn_markov_step.pressed.connect(_on_btn_markov_step_pressed)
	if btn_markov_auto:
		btn_markov_auto.pressed.connect(_on_btn_markov_auto_pressed)
		
	if btn_hmm_pulse:
		btn_hmm_pulse.pressed.connect(_on_btn_hmm_pulse_pressed)
	if btn_hmm_reset:
		btn_hmm_reset.pressed.connect(_on_btn_hmm_reset_pressed)
		
	if gt_preset_btn:
		gt_preset_btn.pressed.connect(_on_btn_gt_preset_pressed)
	if gt_strategy_btn:
		gt_strategy_btn.pressed.connect(_on_btn_gt_strategy_pressed)
	if gt_play_btn:
		gt_play_btn.pressed.connect(_on_btn_gt_play_pressed)

func refresh_all_ui() -> void:
	update_markov_ui()
	update_hmm_ui()
	update_game_theory_ui()
	update_bayes_ui()

# ==============================================================================
# UI 1: CADENAS DE MARKOV
# ==============================================================================
func update_markov_ui() -> void:
	if not markov_chain:
		return
	
	# 1. Estado Actual
	var s_name: String = markov_chain.get_current_state_name()
	var s_idx: int = markov_chain.current_state
	var state_color: String = "#55ff77" if s_idx == 0 else ("#ffdd55" if s_idx == 1 else "#ff5555")
	if markov_state_label:
		markov_state_label.text = "Estado Estación: %s [S_%d]" % [s_name, s_idx]
	
	# 2. Matriz P
	if markov_matrix_label:
		var P = markov_chain.transition_matrix
		markov_matrix_label.text = "Matriz P (Transición):\n  EST: [%.2f, %.2f, %.2f]\n  FLU: [%.2f, %.2f, %.2f]\n  CRÍ: [%.2f, %.2f, %.2f]" % [
			P[0][0], P[0][1], P[0][2],
			P[1][0], P[1][1], P[1][2],
			P[2][0], P[2][1], P[2][2]
		]
	
	# 3. Distribución Estacionaria vs Empírica
	var pi: Array = markov_chain.calculate_stationary_distribution()
	var emp: Array = markov_chain.get_empirical_distribution()
	if markov_dist_label:
		markov_dist_label.text = "π Teórico: [%.1f%%, %.1f%%, %.1f%%]\nf Empírico: [%.1f%%, %.1f%%, %.1f%%] (N=%d)" % [
			pi[0] * 100.0, pi[1] * 100.0, pi[2] * 100.0,
			emp[0] * 100.0, emp[1] * 100.0, emp[2] * 100.0,
			markov_chain.total_steps
		]
	
	# 4. Modificadores
	if markov_effect_label:
		var solar_mod: float = markov_chain.get_environmental_solar_modifier()
		var bot_mod: float = markov_chain.get_environmental_bot_speed_multiplier()
		markov_effect_label.text = "Efecto: Recarga Solar x%.1f | Alerta Bot x%.2f" % [solar_mod, bot_mod]

func _on_markov_state_changed(_old: int, _new_state: int, _name: String) -> void:
	update_markov_ui()

func _on_markov_distribution_updated(_stat: Array, _emp: Array) -> void:
	update_markov_ui()

func _on_btn_markov_step_pressed() -> void:
	if markov_chain:
		markov_chain.step()

func _on_btn_markov_auto_pressed() -> void:
	if not markov_chain:
		return
	var new_state: bool = not markov_chain.is_auto_active
	markov_chain.set_auto_transition(new_state)
	if btn_markov_auto:
		btn_markov_auto.text = "AUTO: ON" if new_state else "AUTO: OFF"

# ==============================================================================
# UI 2: MODELOS OCULTOS DE MARKOV (HMM)
# ==============================================================================
func update_hmm_ui() -> void:
	if not hmm:
		return
	
	# 1. Estado Verdadero (para validación del estudiante) y Observación
	if hmm_hidden_label:
		hmm_hidden_label.text = "Estado real (validación docente): %s" % hmm.get_true_state_name()
	if hmm_obs_label:
		hmm_obs_label.text = "Sensor de telemetría: %s" % hmm.get_latest_observation_name()
		
	# 2. Filtrado Forward (Belief state)
	var belief: Array = hmm.current_belief
	if hmm_belief_label and belief.size() >= 3:
		hmm_belief_label.text = "Creencia Forward P(X_t|Y):\n  Óptimo: %.1f%%  |  Degradado: %.1f%%  |  Crítico: %.1f%%" % [
			belief[0] * 100.0, belief[1] * 100.0, belief[2] * 100.0
		]
	
	# 3. Decodificación Viterbi
	if hmm_viterbi_label:
		var n_obs: int = hmm.observation_history.size()
		if n_obs == 0:
			hmm_viterbi_label.text = "Viterbi: Esperando pulsos de telemetría..."
		else:
			var vit_str: String = ""
			var start_idx: int = max(0, n_obs - 5)
			for i in range(start_idx, n_obs):
				var s_idx: int = hmm.viterbi_decoded_history[i]
				var code: String = "ÓPT" if s_idx == 0 else ("DEG" if s_idx == 1 else "CRÍ")
				vit_str += code + " "
			hmm_viterbi_label.text = "Viterbi (últimos): %s(T=%d)" % [vit_str, n_obs]

func _on_hmm_telemetry_emitted(_obs: int, _name: String, _true_h: int, _belief: Array) -> void:
	update_hmm_ui()

func _on_hmm_viterbi_decoded(_path: Array, _obs: Array) -> void:
	update_hmm_ui()

func _on_btn_hmm_pulse_pressed() -> void:
	if hmm:
		hmm.emit_telemetry_pulse()

func _on_btn_hmm_reset_pressed() -> void:
	if hmm:
		hmm.reset_hmm()
		update_hmm_ui()

# ==============================================================================
# UI 3: TEORÍA DE JUEGOS
# ==============================================================================
func update_game_theory_ui() -> void:
	if not game_theory:
		return
	
	if gt_preset_btn:
		gt_preset_btn.text = "Preset: " + game_theory.get_preset_name()
		
	# 1. Matriz de Pagos
	if gt_matrix_label:
		var P = game_theory.payoff_matrix
		var p1_0: String = game_theory.p1_action_names[0].substr(0, 5)
		var p1_1: String = game_theory.p1_action_names[1].substr(0, 5)
		var p2_0: String = game_theory.p2_action_names[0].substr(0, 5)
		var p2_1: String = game_theory.p2_action_names[1].substr(0, 5)
		gt_matrix_label.text = "Bimatriz (Spark, Bot):\n  %s: [%s: (%.0f,%.0f) | %s: (%.0f,%.0f)]\n  %s: [%s: (%.0f,%.0f) | %s: (%.0f,%.0f)]" % [
			p1_0, p2_0, P[0][0].x, P[0][0].y, p2_1, P[0][1].x, P[0][1].y,
			p1_1, p2_0, P[1][0].x, P[1][0].y, p2_1, P[1][1].x, P[1][1].y
		]
	
	# 2. Equilibrios de Nash
	if gt_nash_label:
		var pure_nash: Array[Vector2i] = game_theory.calculate_pure_nash_equilibria()
		var mixed_nash: Dictionary = game_theory.calculate_mixed_nash_equilibrium()
		
		var pure_str: String = ""
		if pure_nash.size() == 0:
			pure_str = "Ninguno"
		else:
			for eq in pure_nash:
				pure_str += "(%s, %s) " % [game_theory.p1_action_names[eq.x].substr(0, 5), game_theory.p2_action_names[eq.y].substr(0, 5)]
		
		var mixed_str: String = ""
		if mixed_nash.has_mixed_equilibrium:
			mixed_str = "Mixto: p*=%.0f%%, q*=%.0f%% | E[U]=(%.1f, %.1f)" % [
				mixed_nash.p_star * 100.0, mixed_nash.q_star * 100.0,
				mixed_nash.expected_u1, mixed_nash.expected_u2
			]
		else:
			mixed_str = "Mixto: No hay equilibrio interior"
			
		gt_nash_label.text = "Nash Puro: %s\n%s" % [pure_str, mixed_str]
	
	# 3. Botón de estrategia de Spark
	if gt_strategy_btn:
		gt_strategy_btn.text = "Spark: " + game_theory.p1_action_names[spark_chosen_strategy]
		
	# 4. Marcador y última ronda
	if gt_score_label:
		if game_theory.total_rounds == 0:
			gt_score_label.text = "Sin rondas jugadas | Marcador: Spark 0 - 0 Bot"
		else:
			var info = game_theory.last_round_info
			gt_score_label.text = "Última: (%s, %s) → Pagos: (+%.0f, +%.0f)\nMarcador (R=%d): Spark %.0f pts | Bot %.0f pts" % [
				info.a1_name.substr(0, 5), info.a2_name.substr(0, 5),
				info.payoff_p1, info.payoff_p2,
				game_theory.total_rounds,
				game_theory.p1_total_score, game_theory.p2_total_score
			]

func _on_btn_gt_preset_pressed() -> void:
	if not game_theory:
		return
	var next_preset: int = (game_theory.current_preset + 1) % 3
	game_theory.load_preset(next_preset)
	update_game_theory_ui()

func _on_btn_gt_strategy_pressed() -> void:
	spark_chosen_strategy = 1 - spark_chosen_strategy
	if game_theory and gt_strategy_btn:
		gt_strategy_btn.text = "Spark: " + game_theory.p1_action_names[spark_chosen_strategy]

func _on_btn_gt_play_pressed() -> void:
	if not game_theory:
		return
	var bot_action: int = game_theory.choose_bot_action("NASH")
	game_theory.play_round(spark_chosen_strategy, bot_action)

func _on_gt_round_resolved(_data: Dictionary) -> void:
	update_game_theory_ui()

func _on_gt_preset_changed(_name: String) -> void:
	update_game_theory_ui()

# ==============================================================================
# UI 4: BÚSQUEDA BAYESIANA
# ==============================================================================
func update_bayes_ui() -> void:
	if not bayes:
		return
	if bayes_state_label:
		bayes_state_label.text = "Búsqueda: ACTIVA" if bayes.active else "Búsqueda: INACTIVA (el Bot patrulla o ve a Spark)"
	if bayes_map_label:
		if bayes.active:
			var cell: Vector2 = bayes.map_cell()
			bayes_map_label.text = "Casilla MAP (más probable): (%d, %d) px" % [int(cell.x), int(cell.y)]
		else:
			bayes_map_label.text = "Casilla MAP (más probable): —"
	if bayes_stats_label:
		if bayes.active:
			bayes_stats_label.text = "P máx = %.1f%%  |  Entropía H = %.2f bits (máx. %.2f)" % [
				bayes.max_prob() * 100.0, bayes.entropy(), log(float(bayes.belief.size())) / log(2.0)
			]
		else:
			bayes_stats_label.text = "P máx = —  |  Entropía H = —"
	if bayes_model_label:
		bayes_model_label.text = "Detección P_d = %.2f  |  Predicción: 0.2 se queda, 0.8 a vecinas\nActualización: b(c) ∝ b(c)·(1−P_d) dentro de la visión" % BayesSearch.P_DETECT
