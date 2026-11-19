extends Node2D

# ENTORNO DE LA ESTACIÓN ESPACIAL (LOGIC LOOP)
# Main actúa como la autoridad central del entorno conectando los 6 paradigmas:
# 1. AGENTES (FSM & Percepción): Bot de Mantenimiento
# 2. EVENTOS DISCRETOS (DES - M/M/1/K): Bahía Logística / Dispensador de herramientas
# 3. SISTEMAS DINÁMICOS (Stock & Flow): Batería solar y consumo de motores de Spark
# 4. CADENAS DE MARKOV: Proceso estocástico del clima y radiación de la estación
# 5. MODELOS OCULTOS DE MARKOV (HMM): Diagnóstico latente de desgaste del núcleo y Viterbi
# 6. TEORÍA DE JUEGOS: Interacción estratégica (Nash, matriz de pagos) entre Spark y Bot
# 7. BÚSQUEDA BAYESIANA: Creencia (filtro de Bayes en cuadrícula) del Bot sobre dónde está Spark

@onready var maintenance_bot: Node2D  = get_node_or_null("MaintenanceBot")
@onready var spark: Node2D            = get_node_or_null("Spark")
@onready var repair_component: Node2D = get_node_or_null("RepairComponent")
@onready var tool_dispenser: Node2D   = get_node_or_null("ToolDispenser")

# UI NODES EXISTENTES
@onready var agent_status_label: Label     = get_node_or_null("UI/TopBar/HBox/BotChip/VBox/StatusText")
@onready var bot_chip: PanelContainer      = get_node_or_null("UI/TopBar/HBox/BotChip")
@onready var bot_state_label: Label        = get_node_or_null("UI/TopBar/HBox/BotChip/VBox/BotStateLabel")
@onready var climate_chip: PanelContainer  = get_node_or_null("UI/TopBar/HBox/ClimateChip")
@onready var climate_label: Label          = get_node_or_null("UI/TopBar/HBox/ClimateChip/VBox/ClimateLabel")
@onready var tool_chip: PanelContainer     = get_node_or_null("UI/TopBar/HBox/ToolChip")
@onready var tool_label: Label             = get_node_or_null("UI/TopBar/HBox/ToolChip/VBox/ToolLabel")
@onready var banner_pill: PanelContainer   = get_node_or_null("UI/BannerPill")
@onready var detection_banner: Label       = get_node_or_null("UI/BannerPill/DetectionBanner")
@onready var modal_backdrop: ColorRect     = get_node_or_null("UI/ModalBackdrop")
@onready var program_list: Label           = get_node_or_null("UI/ProgrammingPanel/Margin/VBox/ScrollList/ProgramList")
@onready var program_scroll: ScrollContainer = get_node_or_null("UI/ProgrammingPanel/Margin/VBox/ScrollList")
@onready var feedback_label: Label         = get_node_or_null("UI/FeedbackPanel/FeedbackText")
@onready var game_over_modal: Control      = get_node_or_null("UI/GameOverModal")
@onready var victory_modal: Control        = get_node_or_null("UI/VictoryModal")
@onready var detection_timer: Timer        = get_node_or_null("UI/DetectionTimer")

# NODES SISTEMAS DINÁMICOS Y EVENTOS DISCRETOS
@onready var dynamics_status_label: Label  = get_node_or_null("UI/TopBar/HBox/EnergyBox/DynamicsText")
@onready var energy_bar: ProgressBar       = get_node_or_null("UI/TopBar/HBox/EnergyBox/EnergyRow/EnergyBar")
@onready var energy_value_label: Label     = get_node_or_null("UI/TopBar/HBox/EnergyBox/EnergyRow/EnergyValue")
@onready var queue_simulator: Control      = get_node_or_null("UI/QueueSimulator")

# NUEVOS MOTORES MATEMÁTICOS Y PANEL AVANZADO
@onready var markov_chain: MarkovChain                      = get_node_or_null("MarkovChain")
@onready var hidden_markov_model: HiddenMarkovModel          = get_node_or_null("HiddenMarkovModel")
@onready var game_theory_engine: GameTheoryEngine            = get_node_or_null("GameTheoryEngine")
@onready var advanced_models_panel: AdvancedModelsPanel      = get_node_or_null("UI/AdvancedModelsPanel")

# BARRERA DAÑADA: HMM de 2 estados (segunda instancia) y juego de inspección (segundo motor)
@onready var obstacle_hmm: HiddenMarkovModel                 = get_node_or_null("ObstacleHMM")
@onready var cover_game_engine: GameTheoryEngine             = get_node_or_null("CoverGameEngine")
@onready var barrier: Node2D                                 = get_node_or_null("DamagedBarrier")

# PARADIGMA 7: filtro de Bayes del Bot (el Bot lo usa solo a través de Main)
@onready var bayes_search: BayesSearch                       = get_node_or_null("BayesSearch")

# Parámetros base para restablecer tras modificaciones ambientales/estratégicas
var base_solar_inflow: float = 1.0
var base_bot_speed: float = 100.0
var base_motor_cost: float = 4.0
const BASE_VISION_RADIUS: float = 250.0

# Rutas de patrulla en la estación espacial para el Bot de Mantenimiento
@export var station_patrol_waypoints: Array[Vector2] = [
	Vector2(200, 200),
	Vector2(760, 200),     # pata derecha acortada (era x = 1080) para no pasar bajo el panel derecho
	Vector2(760, 520),
	Vector2(200, 520)
]

var is_simulation_running: bool = false
var is_level_completed: bool = false

# ==============================================================================
# GEOMETRÍA DE LA BARRERA (cuadrícula de Spark: x = 150 + 64i, y = 600 - 64j)
# ==============================================================================
# Los muros son un conjunto LÓGICO de casillas bloqueadas (Spark se teletransporta
# por la cuadrícula y no usa colisiones físicas). El Bot NO se bloquea con ellos:
# se mueve en línea recta sin pathfinding, así que la barrera es un obstáculo
# terrestre y el bot "flota" por encima.
const BARRIER_CELL: Vector2 = Vector2(470, 408)   # Barrera dañada, en la fila del dispensador
const WALL_X: float = 470.0                       # Columna de muro (todas las filas salvo barrera y hueco)
const GAP_Y: float = 536.0                        # Único hueco: permite el desvío
const COVER_CELL: Vector2 = Vector2(406, 408)     # Casilla de cobertura (oeste de la barrera)
const EXIT_CELL: Vector2 = Vector2(534, 408)      # Casilla de salida (este de la barrera)
const CELL_TOL: float = 8.0
const WALL_TOP_Y: float = 88.0                    # Primera casilla de muro dibujada (visual): bajo la barra superior
const WALL_BOTTOM_Y: float = 600.0                # Última casilla de muro dibujada (visual): sobre la barra inferior

# Rutas que Spark recorre tras SONDEAR (se recorren paso a paso)
const RAM_PATH: Array[Vector2] = [Vector2(470, 408), Vector2(534, 408)]               # 2 pasos
const DETOUR_PATH: Array[Vector2] = [Vector2(406, 472), Vector2(406, 536), Vector2(470, 536),
		Vector2(534, 536), Vector2(534, 472), Vector2(534, 408)]                      # 6 pasos

# Parámetros del diagnóstico y de los efectos (decisiones nuestras, no del enunciado)
const PROBE_PULSES: int = 3
const FRACTURE_THRESHOLD: float = 0.65            # θ de la regla de decisión
const ARMOR_DAMAGE: float = 15.0                  # % de batería al rebotar contra blindaje
const ARMOR_STUN: float = 1.0                     # s de aturdimiento
const AMBUSH_DAMAGE: float = 15.0                 # % de batería en la emboscada
const EVASION_BONUS: float = 10.0                 # % de batería extra en la evasión limpia (elección propia)
const COVER_WINDOW: float = 3.0                   # s de duración del efecto del encuentro

# Modos del bot (deben coincidir con npc.gd: enum CoverMode { NONE, SWEEP, PATROL })
const COVER_SWEEP: int = 1
const COVER_PATROL: int = 2

const BANNER_DEFAULT_COLOR: Color = Color(1, 0.85, 0.1, 1)

# Paleta única de la interfaz (coincide con Assets/ui/theme.tres)
const COLOR_GREEN: Color = Color(0.24, 0.86, 0.52)
const COLOR_AMBER: Color = Color(1.0, 0.7, 0.28)
const COLOR_RED: Color = Color(1.0, 0.36, 0.36)
const COLOR_BLUE: Color = Color(0.35, 0.63, 1.0)
const COLOR_DIM: Color = Color(0.55, 0.65, 0.76)
const COLOR_PANEL: Color = Color(0.059, 0.09, 0.149)
const COLOR_TEXT: Color = Color(0.96, 0.97, 1.0)

# Marcadores de la lista del programa (✓ ejecutado, ▶ en curso, · pendiente)
const MARK_DONE: String = "✓ "
const MARK_NOW: String = "▶ "
const MARK_TODO: String = "· "

# Programa de demostración (--autodemo): dispensador -> cobertura -> SONDEAR -> reparación.
# Spark parte de (150,600) mirando al este, pasos de 64 px:
#   este 1 y norte 3 hasta (214,408) [38 px del dispensador], girar al este -> INTERACTUAR (4 veces: la cola puede estar vacía al llegar)
#   -> este hasta la cobertura (406,408) -> SONDEAR (termina en la salida (534,408))
#   -> 2 al este y 4 al norte hasta (662,152) [38 px del componente] -> INTERACTUAR
const AUTODEMO_PROGRAM: Array[String] = [
	"MOVE", "TURN_LEFT", "MOVE", "MOVE", "MOVE", "TURN_RIGHT",
	"INTERACT", "INTERACT", "INTERACT", "INTERACT",
	"MOVE", "MOVE", "MOVE", "SONDEAR",
	"MOVE", "MOVE", "TURN_LEFT", "MOVE", "MOVE", "MOVE", "MOVE", "INTERACT"
]
const AUTODEMO_DELAY: float = 1.0

var cover_triggered: bool = false                 # El encuentro se juega una vez por corrida
var spark_hidden: bool = false                    # Spark camuflado: el bot no lo percibe
var spark_hidden_time_left: float = 0.0
var _banner_tween: Tween = null
var event_banner_lock_left: float = 0.0           # Mientras sea > 0, el Bot no pisa el banner de un evento
var barrier_known_armored: bool = false           # Tras un rebote la pared es BLINDADA con certeza

# Estado puramente visual de la interfaz (no interviene en ninguna regla del juego)
var _modal_tween: Tween = null
var _chip_keys: Dictionary = {}                   # chip -> clave de estilo vigente (evita recrearlo cada cuadro)
var _energy_level: int = -1                       # 0 = verde, 1 = ámbar, 2 = rojo
var _tool_shown: bool = false

func _ready() -> void:
	if game_over_modal: game_over_modal.visible = false
	if victory_modal:   victory_modal.visible   = false
	if banner_pill:     banner_pill.visible     = false
	if modal_backdrop:  modal_backdrop.visible  = false

	# El fondo oscuro y la animación de entrada de los modales se manejan en un solo lugar
	for modal in [game_over_modal, victory_modal]:
		if modal:
			modal.visibility_changed.connect(_on_modal_visibility_changed.bind(modal))

	_init_advanced_engines()
	_init_hud()

	if "--autodemo" in OS.get_cmdline_user_args():
		_run_autodemo()

# Estado inicial de los chips de la barra superior
func _init_hud() -> void:
	if markov_chain:
		_set_climate_chip(markov_chain.current_state, markov_chain.get_current_state_name())
	_set_bot_chip("PATRULLA", "Esperando ejecución del programa")
	_set_tool_chip(false)

# Demo para verificación y para grabar la entrega: carga un programa fijo y pulsa EJECUTAR
func _run_autodemo() -> void:
	await get_tree().create_timer(AUTODEMO_DELAY).timeout
	if spark == null or not spark.has_method("add_command"):
		return
	for cmd in AUTODEMO_PROGRAM:
		spark.add_command(cmd)
	_on_btn_execute_pressed()

func _init_advanced_engines() -> void:
	# Respaldo dinámico si no estuvieran presentes en el árbol de escena
	if not markov_chain:
		markov_chain = MarkovChain.new()
		markov_chain.name = "MarkovChain"
		add_child(markov_chain)
		
	if not hidden_markov_model:
		hidden_markov_model = HiddenMarkovModel.new()
		hidden_markov_model.name = "HiddenMarkovModel"
		add_child(hidden_markov_model)
		
	if not game_theory_engine:
		game_theory_engine = GameTheoryEngine.new()
		game_theory_engine.name = "GameTheoryEngine"
		add_child(game_theory_engine)

	if not bayes_search:
		bayes_search = BayesSearch.new()
		bayes_search.name = "BayesSearch"
		add_child(bayes_search)
	# El filtro no conoce a Main: recibe la regla de bloqueo como Callable
	bayes_search.setup(is_cell_blocked)

	# Conexión con el panel UI
	if advanced_models_panel:
		advanced_models_panel.setup_engines(markov_chain, hidden_markov_model, game_theory_engine, bayes_search)
	
	# Escucha de señales para retroalimentar la física y simulación del entorno
	if markov_chain:
		markov_chain.state_changed.connect(_on_markov_climate_changed)
	if game_theory_engine:
		game_theory_engine.round_resolved.connect(_on_strategic_round_resolved)

	# HMM de la barrera: S = {FRÁGIL, BLINDADO}, V = {ECO HUECO, ECO AMBIGUO, ECO SÓLIDO}
	if not obstacle_hmm:
		obstacle_hmm = HiddenMarkovModel.new()
		obstacle_hmm.name = "ObstacleHMM"
		add_child(obstacle_hmm)
	# A = identidad: la pared en reposo no cambia de integridad. Con A = I el filtro
	# Forward se reduce a Bayes secuencial (fácil de defender) y sondear no puede
	# "endurecer" el muro, lo cual no tendría sentido físico.
	obstacle_hmm.configure(
		["FRÁGIL", "BLINDADO"],
		["ECO HUECO", "ECO AMBIGUO", "ECO SÓLIDO"],
		[[1.0, 0.0], [0.0, 1.0]],
		[[0.70, 0.25, 0.05], [0.05, 0.25, 0.70]],
		[0.5, 0.5]
	)
	# La barrera nunca usa Viterbi: se evita recalcularlo en cada pulso
	obstacle_hmm.auto_viterbi = false

	# Juego de inspección en la cobertura (no toca el GameTheoryEngine / Hawk-Dove)
	if not cover_game_engine:
		cover_game_engine = GameTheoryEngine.new()
		cover_game_engine.name = "CoverGameEngine"
		add_child(cover_game_engine)
	cover_game_engine.load_preset(GameTheoryEngine.PresetType.STEALTH_COVER)

	_reset_obstacle_state()

# INTERFAZ DEL ENTORNO
func get_environment_info() -> Dictionary:
	var spark_active: bool    = spark != null and spark.visible
	var spark_pos: Vector2    = spark.global_position if spark_active else Vector2.ZERO
	var comp_active: bool     = repair_component != null and repair_component.visible and not is_level_completed
	var comp_pos: Vector2     = repair_component.global_position if comp_active else Vector2.ZERO

	return {
		"has_spark": spark_active,
		"spark_position": spark_pos,
		"has_repair_component": comp_active,
		"repair_component_position": comp_pos,
		"patrol_waypoints": station_patrol_waypoints,
		"is_simulation_running": is_simulation_running,
		"spark_hidden": spark_hidden,
		"barrier_position": BARRIER_CELL
	}

# ==============================================================================
# BARRERA DAÑADA: BLOQUEO LÓGICO, DIAGNÓSTICO HMM Y ENCUENTRO EN COBERTURA
# ==============================================================================
func _process(delta: float) -> void:
	# Chip de herramienta: refleja si Spark lleva una (solo lectura)
	if spark:
		var carrying: bool = spark.get("has_tool") == true
		if carrying != _tool_shown:
			_set_tool_chip(carrying)
	# Bloqueo de banner de evento: cuenta regresiva
	if event_banner_lock_left > 0.0:
		event_banner_lock_left = maxf(0.0, event_banner_lock_left - delta)
	# Ventana de camuflaje: al terminar, Spark vuelve a ser perceptible
	if spark_hidden:
		spark_hidden_time_left -= delta
		if spark_hidden_time_left <= 0.0:
			_set_spark_hidden(false)

func _same_cell(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) <= CELL_TOL

# ¿La casilla está bloqueada para Spark? Muro en toda la columna salvo el hueco,
# y la barrera mientras no esté destruida.
func is_cell_blocked(pos: Vector2) -> bool:
	if absf(pos.x - WALL_X) > CELL_TOL:
		return false
	if absf(pos.y - GAP_Y) <= CELL_TOL:
		return false
	if absf(pos.y - BARRIER_CELL.y) <= CELL_TOL:
		return barrier == null or not barrier.is_destroyed
	return true

# Casillas de muro visibles (para dibujarlas): la columna sin la barrera ni el hueco
func get_wall_cells() -> Array[Vector2]:
	var cells: Array[Vector2] = []
	var y: float = WALL_TOP_Y
	while y <= WALL_BOTTOM_Y:
		if absf(y - GAP_Y) > CELL_TOL and absf(y - BARRIER_CELL.y) > CELL_TOL:
			cells.append(Vector2(WALL_X, y))
		y += 64.0
	return cells

# Reinicia la barrera, sortea un estado oculto nuevo y limpia los efectos de cobertura
func _reset_obstacle_state() -> void:
	cover_triggered = false
	barrier_known_armored = false
	event_banner_lock_left = 0.0
	_set_spark_hidden(false)
	bayes_stop()   # reinicio / captura / batería agotada: se descarta la creencia del Bot
	if obstacle_hmm:
		obstacle_hmm.reset_hmm()
		obstacle_hmm.resample_true_state()   # π0 = [0.5, 0.5]
	if barrier:
		barrier.restore()
		if obstacle_hmm:
			barrier.is_breakable = (obstacle_hmm.current_true_hidden_state == 0)

func _set_spark_hidden(on: bool) -> void:
	spark_hidden = on
	spark_hidden_time_left = COVER_WINDOW if on else 0.0
	if spark and spark.has_method("set_camouflaged"):
		spark.set_camouflaged(on)

# SONDEAR (lo llama Spark): solo válido en la casilla de cobertura mirando al este
func run_obstacle_probe(spark_pos: Vector2, facing: int) -> String:
	if facing != 0 or not _same_cell(spark_pos, COVER_CELL) or barrier == null or barrier.is_destroyed or obstacle_hmm == null:
		_show_banner("Sin obstáculo al frente", BANNER_DEFAULT_COLOR, 2.0, false, true)
		notify_execution_status("Sin obstáculo al frente")
		return "NINGUNO"

	# Tras un rebote la pared ya es BLINDADA con certeza: no se vuelve a sondear
	if barrier_known_armored:
		spark.follow_path(DETOUR_PATH)
		notify_execution_status("Blindaje confirmado: RODEAR")
		return "RODEAR"

	var diag: Dictionary = obstacle_hmm.diagnose_obstacle(PROBE_PULSES, FRACTURE_THRESHOLD)
	var echo_names: Array[String] = []
	for obs in diag.observations:
		echo_names.append(obstacle_hmm.observation_names[obs])
	barrier.show_echoes(echo_names, diag.belief_fragil)

	var decision: String = diag.decision
	var is_fragile: bool = barrier.is_breakable
	if decision == "FRACTURAR":
		if is_fragile:
			barrier.destroy()
			spark.follow_path(RAM_PATH)
			notify_execution_status("Barrera FRÁGIL fracturada (P(Frágil)=%.2f)" % diag.belief_fragil)
		else:
			# Rebote contra el blindaje: daño, aturdimiento y el estruendo alerta al Bot
			spark.drain_energy(ARMOR_DAMAGE)
			spark.stun(ARMOR_STUN)
			# El rebote es evidencia directa: P(Blindado) = 1 para sondeos posteriores
			barrier_known_armored = true
			obstacle_hmm.current_belief = [0.0, 1.0]
			_show_banner("¡BARRERA BLINDADA! Rebote", Color(1, 0.4, 0.2), 2.0, false, true)
			# El estruendo delata a Spark aunque esté camuflado
			_set_spark_hidden(false)
			if maintenance_bot and maintenance_bot.has_method("force_chase"):
				maintenance_bot.force_chase(spark_pos)
			notify_execution_status("¡Barrera BLINDADA! Rebote (P(Frágil)=%.2f)" % diag.belief_fragil)
	else:
		spark.follow_path(DETOUR_PATH)
		notify_execution_status("Spark RODEA la barrera (P(Frágil)=%.2f)" % diag.belief_fragil)
	return decision

# ==============================================================================
# PARADIGMA 7: BÚSQUEDA BAYESIANA (el Bot la usa solo a través de Main)
# ==============================================================================
func bayes_start(pos: Vector2) -> void:
	if bayes_search:
		bayes_search.start(pos)

# Avanza el filtro (un paso cada 0.5 s) y devuelve la casilla MAP hacia la que ir
func bayes_step(bot_pos: Vector2, radius: float, delta: float) -> Vector2:
	return bayes_search.step(bot_pos, radius, delta) if bayes_search else bot_pos

func bayes_exhausted() -> bool:
	return bayes_search == null or bayes_search.is_exhausted()

func bayes_stop() -> void:
	if bayes_search and bayes_search.active:
		bayes_search.clear()

# Se llama tras cada paso de Spark: la primera vez por corrida que pisa la
# casilla de cobertura se juega una ronda del juego de inspección.
func on_spark_stepped(pos: Vector2) -> void:
	if is_simulation_running and not cover_triggered and _same_cell(pos, COVER_CELL):
		cover_triggered = true
		_resolve_cover_encounter(pos)

# Ronda del juego STEALTH_COVER: cada jugador sortea su acción con su
# probabilidad de equilibrio mixto (p* = P(Ocultarse), q* = P(Barrido)).
func _resolve_cover_encounter(spark_pos: Vector2) -> void:
	if cover_game_engine == null:
		return
	var mixed: Dictionary = cover_game_engine.calculate_mixed_nash_equilibrium()
	var a1: int = 0 if randf() < float(mixed.p_star) else 1   # 0 = OCULTARSE, 1 = AVANZAR
	var a2: int = 0 if randf() < float(mixed.q_star) else 1   # 0 = BARRIDO, 1 = PATRULLA
	cover_game_engine.play_round(a1, a2)
	var odds: String = " (p*=%.2f, q*=%.2f)" % [mixed.p_star, mixed.q_star]

	match [a1, a2]:
		[0, 0]:
			_show_banner("¡EMBOSCADA EN COBERTURA!" + odds, Color(1, 0.25, 0.2), COVER_WINDOW, false, true)
			spark.drain_energy(AMBUSH_DAMAGE)
			_cover_bot_reaction(COVER_SWEEP, true, spark_pos)
		[0, 1]:
			_show_banner("¡EVASIÓN LIMPIA!" + odds, Color(0.3, 1, 0.4), COVER_WINDOW, false, true)
			spark.add_energy(EVASION_BONUS)
			_set_spark_hidden(true)
			_cover_bot_reaction(COVER_PATROL, false, spark_pos)
		[1, 0]:
			_show_banner("¡CARRERA LIBRE!" + odds, Color(0.35, 0.6, 1), COVER_WINDOW, false, true)
			_set_spark_hidden(true)
			spark.play_rush_trail()
			_cover_bot_reaction(COVER_SWEEP, false, spark_pos)
		_:
			_show_banner("¡INTERCEPTADO EN CAMPO ABIERTO!" + odds, Color(1, 0.2, 0.2), COVER_WINDOW, true, true)
			spark.play_rush_trail()
			_cover_bot_reaction(COVER_PATROL, true, spark_pos)

func _cover_bot_reaction(mode: int, chase: bool, spark_pos: Vector2) -> void:
	if not maintenance_bot:
		return
	maintenance_bot.set_cover_mode(mode, COVER_WINDOW)
	if chase:
		maintenance_bot.force_chase(spark_pos)

# INTERACCIÓN
func check_interact(spark_pos: Vector2) -> void:
	# 1. INTERACCIÓN CON EL DISPENSADOR LOGÍSTICO (RECOGER HERRAMIENTA)
	if tool_dispenser and spark_pos.distance_to(tool_dispenser.global_position) <= 80.0:
		if spark and spark.get("has_tool") == true:
			notify_execution_status("Ya llevas una herramienta equipada")
			return
		if queue_simulator and queue_simulator.has_method("consume_tool"):
			if queue_simulator.consume_tool():
				if spark and spark.has_method("set_has_tool"):
					spark.set_has_tool(true)
				notify_execution_status("¡HERRAMIENTA RECOGIDA! Llévala al componente")
			else:
				notify_execution_status("¡ESPERANDO SUMINISTROS! La cola está vacía")
		return

	# 2. INTERACCIÓN CON EL COMPONENTE DE REPARACIÓN (REPARAR ESTACIÓN)
	if repair_component and repair_component.visible and not is_level_completed:
		if spark_pos.distance_to(repair_component.global_position) <= 80.0:
			if spark and spark.get("has_tool") != true:
				notify_execution_status("¡FALTA HERRAMIENTA! Recógela primero en el dispensador")
				return

			is_level_completed = true
			repair_component.visible = false
			is_simulation_running = false
			if spark and spark.has_method("set_has_tool"):
				spark.set_has_tool(false)
			
			# EVALUACIÓN DE MODELO OCULTO DE MARKOV (HMM) Y VITERBI
			var diag_str: String = "ÓPTIMO"
			if hidden_markov_model:
				hidden_markov_model.emit_telemetry_pulse()
				var viterbi_seq = hidden_markov_model.viterbi_decode(hidden_markov_model.observation_history)
				if viterbi_seq.size() > 0:
					diag_str = hidden_markov_model.hidden_state_names[viterbi_seq.back()]
			
			notify_execution_status("¡ESTACIÓN REPARADA! Diagnóstico Viterbi HMM: [%s]" % diag_str)
			
			if victory_modal:
				var msg = victory_modal.get_node_or_null("Margin/VBox/Msg")
				if msg:
					# Paréntesis: `%` liga más que `+`, así que debe aplicarse a toda la concatenación
					msg.text = (
						"¡Felicidades! Spark reparó la estación con éxito.\n" +
						"Diagnóstico Oculto (Viterbi HMM): Componente en estado [%s].\n" +
						"¡La falla latente ha sido neutralizada!"
					) % diag_str
				victory_modal.visible = true
			return

	notify_execution_status("No hay nada con qué interactuar aquí")

# ==============================================================================
# INTEGRACIÓN DEL PARADIGMA 4: CADENA DE MARKOV EN EL JUEGO
# ==============================================================================
func _on_markov_climate_changed(_old: int, new_state: int, state_name: String) -> void:
	if not markov_chain:
		return
	_set_climate_chip(new_state, state_name)
	
	# Modifica la recarga solar de Spark según la radiación climática de Markov
	var solar_mod: float = markov_chain.get_environmental_solar_modifier()
	if spark:
		spark.set("solar_inflow_rate", base_solar_inflow * solar_mod)
	
	# Modifica la velocidad del Bot de Mantenimiento por protocolo de alerta
	var bot_mod: float = markov_chain.get_environmental_bot_speed_multiplier()
	if maintenance_bot:
		maintenance_bot.set("patrol_speed", base_bot_speed * bot_mod)
		
	if new_state == MarkovChain.State.CRITICAL:
		notify_execution_status("¡ALERTA RADIOLÓGICA! Clima espacial: " + state_name)
		_show_banner("CLIMA ESPACIAL: TORMENTA DE RADIACIÓN", BANNER_DEFAULT_COLOR, 2.5, false, true)

# ==============================================================================
# INTEGRACIÓN DEL PARADIGMA 6: TEORÍA DE JUEGOS EN EL JUEGO
# ==============================================================================
func _on_strategic_round_resolved(data: Dictionary) -> void:
	var spark_action: int = data.get("a1", 0)
	var bot_action: int = data.get("a2", 0)
	
	# Solo HAWK_DOVE tiene acciones CAUTO/AUDAZ y PATRULLA/ESCANEO; en otros presets
	# los índices 0/1 significan otra cosa, así que se restauran los valores base.
	var is_hawk_dove: bool = game_theory_engine.current_preset == GameTheoryEngine.PresetType.HAWK_DOVE
	
	# Modificaciones al agente Spark:
	# Cauto (0): Mayor eficiencia de energía (menor consumo motor)
	# Audaz (1): Mayor consumo motor
	if spark:
		if not is_hawk_dove:
			spark.set("motor_step_cost", base_motor_cost)
		elif spark_action == 0:
			spark.set("motor_step_cost", 2.5)
		else:
			spark.set("motor_step_cost", 4.5)
			
	# Modificaciones al Bot:
	# Escaneo Estricto (1): Mayor radio de visión
	# Patrulla Suave (0): Visión normal
	if maintenance_bot:
		if is_hawk_dove and bot_action == 1:
			maintenance_bot.set("vision_radius", 285.0)
		else:
			maintenance_bot.set("vision_radius", BASE_VISION_RADIUS)
		maintenance_bot.queue_redraw()

# GAME OVER POR CAPTURA
func reset_spark() -> void:
	is_simulation_running = false
	_reset_obstacle_state()
	notify_execution_status("¡SPARK FUE CAPTURADO!")
	if game_over_modal:
		var msg = game_over_modal.get_node_or_null("Margin/VBox/Msg")
		if msg:
			msg.text = "Spark fue capturado por el Bot de Mantenimiento.\nModifica tu programa e inténtalo de nuevo."
		game_over_modal.visible = true
	if spark and spark.has_method("reset_to_start"):
		spark.reset_to_start()
	if maintenance_bot and maintenance_bot.has_method("reset_to_start"):
		maintenance_bot.reset_to_start()

# GAME OVER POR SISTEMA DINÁMICO (BATERÍA AGOTADA)
func on_battery_depleted() -> void:
	is_simulation_running = false
	_reset_obstacle_state()
	notify_execution_status("¡BATERÍA AGOTADA!")
	if game_over_modal:
		var msg = game_over_modal.get_node_or_null("Margin/VBox/Msg")
		if msg:
			msg.text = "Spark se quedó sin energía en la batería.\nOptimiza tu programa para consumir menos instrucciones."
		game_over_modal.visible = true
	if spark and spark.has_method("reset_to_start"):
		spark.reset_to_start()
	if maintenance_bot and maintenance_bot.has_method("reset_to_start"):
		maintenance_bot.reset_to_start()

# PROGRAMA COMPLETADO
func on_program_complete() -> void:
	is_simulation_running = false
	notify_execution_status("PROGRAMA FINALIZADO")

# SEÑAL DEL BOT
func notify_spark_detected() -> void:
	if event_banner_lock_left > 0.0:
		return
	_show_banner("¡SPARK DETECTADO!", BANNER_DEFAULT_COLOR, 2.0)

func notify_spark_lost() -> void:
	if event_banner_lock_left > 0.0:
		return
	_show_banner("SPARK PERDIDO · BUSCANDO...", BANNER_DEFAULT_COLOR, 2.0)

# Banner genérico (texto, color, duración); `flash` lo hace parpadear;
# `priority` bloquea los avisos del Bot mientras dure el banner del evento
func _show_banner(text: String, color: Color, duration: float, flash: bool = false, priority: bool = false) -> void:
	if priority:
		event_banner_lock_left = duration
	if not detection_banner or not banner_pill:
		return
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	banner_pill.modulate.a = 1.0
	detection_banner.text = text
	# Texto claro siempre; el color del evento va en el borde y el relleno de la pastilla
	detection_banner.add_theme_color_override("font_color", COLOR_TEXT)
	_style_chip(banner_pill, color, 0.35, 14.0)
	banner_pill.visible = true
	banner_pill.reset_size.call_deferred()   # se ajusta a 1 o 2 líneas según el texto
	if flash:
		_banner_tween = create_tween().set_loops(int(duration / 0.5))
		_banner_tween.tween_property(banner_pill, "modulate:a", 0.25, 0.25)
		_banner_tween.tween_property(banner_pill, "modulate:a", 1.0, 0.25)
	if detection_timer: detection_timer.start(duration)

func _on_detection_timer_timeout() -> void:
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	if banner_pill:
		banner_pill.modulate.a = 1.0
		banner_pill.visible = false

# CONTROL DE SIMULACIÓN
func start_simulation() -> void:
	is_simulation_running = true
	
	# Activa un pulso en el modelo estocástico HMM
	if hidden_markov_model:
		hidden_markov_model.emit_telemetry_pulse()
		
	# Resuelve un encuentro estratégico de Teoría de Juegos si el panel está presente
	if game_theory_engine and advanced_models_panel:
		var bot_strat: int = game_theory_engine.choose_bot_action("NASH")
		game_theory_engine.play_round(advanced_models_panel.spark_chosen_strategy, bot_strat)

func reset_simulation() -> void:
	is_simulation_running = false
	_reset_obstacle_state()
	# Deshace los efectos de la última ronda estratégica
	if spark:
		spark.set("motor_step_cost", base_motor_cost)
	if maintenance_bot:
		maintenance_bot.set("vision_radius", BASE_VISION_RADIUS)
		maintenance_bot.queue_redraw()
	if spark and spark.has_method("reset_to_start"):
		spark.reset_to_start()
	if maintenance_bot and maintenance_bot.has_method("reset_to_start"):
		maintenance_bot.reset_to_start()

# BOTONES DE PROGRAMACIÓN
func _on_btn_move_pressed() -> void:
	if spark and spark.has_method("add_command"): spark.add_command("MOVE")

func _on_btn_turn_left_pressed() -> void:
	if spark and spark.has_method("add_command"): spark.add_command("TURN_LEFT")

func _on_btn_turn_right_pressed() -> void:
	if spark and spark.has_method("add_command"): spark.add_command("TURN_RIGHT")

func _on_btn_interact_pressed() -> void:
	if spark and spark.has_method("add_command"): spark.add_command("INTERACT")

func _on_btn_sondear_pressed() -> void:
	if spark and spark.has_method("add_command"): spark.add_command("SONDEAR")

func _on_btn_clear_pressed() -> void:
	reset_simulation()
	if spark and spark.has_method("clear_commands"): spark.clear_commands()
	notify_execution_status("Listo para programar")

func _on_btn_execute_pressed() -> void:
	if game_over_modal: game_over_modal.visible = false
	if victory_modal:   victory_modal.visible   = false
	if spark and spark.has_method("execute_program"):
		reset_simulation()
		start_simulation()
		spark.execute_program()

func _on_btn_retry_pressed() -> void:
	if game_over_modal: game_over_modal.visible = false
	reset_simulation()
	notify_execution_status("Listo para programar")

func _on_btn_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/title.tscn")

func _on_btn_replay_pressed() -> void:
	if victory_modal: victory_modal.visible = false
	is_level_completed = false
	if repair_component: repair_component.visible = true
	if queue_simulator and queue_simulator.has_method("reset_queue"):
		queue_simulator.reset_queue()
	reset_simulation()
	notify_execution_status("Listo para programar")

# ACTUALIZACIÓN DE LA UI
func update_program_sequence_ui(commands: Array, current_idx: int, executing: bool) -> void:
	if not program_list:
		return
	if commands.size() == 0:
		program_list.text = "Programa vacío: añade comandos"
		return

	var lines: String = ""
	for i in range(commands.size()):
		var label: String = _cmd_label(commands[i])
		var prefix: String
		if executing:
			if i < current_idx - 1:
				prefix = MARK_DONE   # ejecutado
			elif i == current_idx - 1:
				prefix = MARK_NOW    # ejecutándose
			else:
				prefix = MARK_TODO   # pendiente
		else:
			prefix = MARK_TODO
		lines += prefix + label + "\n"
	program_list.text = lines.strip_edges()
	# Mantiene a la vista la línea en curso mientras se ejecuta (solo visual)
	if executing and program_scroll:
		var line_h: float = program_list.get_line_height() + program_list.get_theme_constant("line_spacing")
		program_scroll.scroll_vertical = int(maxf(0.0, float(current_idx - 3)) * line_h)

func notify_execution_status(msg: String) -> void:
	if feedback_label:
		feedback_label.text = msg

func update_debug_ui(state_str: String, _target_str: String, distance_str: String, action_str: String, _vision_radius: float) -> void:
	var detail: String = _sentence_case(action_str)
	if distance_str != "N/A":
		detail += " · " + distance_str
	var chip_text: String = state_str + " · IA bayesiana" if state_str == "BUSCAR" else state_str
	_set_bot_chip(chip_text, detail, state_str)

func update_dynamics_ui(energy: float, max_energy: float, net_rate: float, inflow: float, outflow: float) -> void:
	var percent: float = (energy / max_energy) * 100.0
	if energy_bar:
		energy_bar.value = percent
		_set_energy_level(0 if percent > 50.0 else (1 if percent > 25.0 else 2))
	if energy_value_label:
		energy_value_label.text = "ENERGÍA %d%%" % int(round(percent))
	if dynamics_status_label:
		dynamics_status_label.text = "Solar +%.1f/s · Consumo −%.1f/s · Neto %+.1f/s" % [inflow, outflow, net_rate]

# ==============================================================================
# AYUDAS VISUALES DE LA INTERFAZ (no tocan la lógica del juego)
# ==============================================================================
# Estilo de chip/pastilla: fondo tintado, borde del color indicado
func _style_chip(panel: PanelContainer, color: Color, fill_alpha: float = 0.16, margin_x: float = 8.0) -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = COLOR_PANEL.lerp(color, fill_alpha)   # opaco: legible sobre cualquier fondo
	box.border_color = color
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = 3.0
	box.content_margin_bottom = 3.0
	panel.add_theme_stylebox_override("panel", box)

# Aplica el estilo solo cuando cambia el color (update_debug_ui se llama cada cuadro)
func _style_chip_once(panel: PanelContainer, color: Color) -> void:
	if _chip_keys.get(panel) == color:
		return
	_chip_keys[panel] = color
	_style_chip(panel, color)

func _set_climate_chip(state_idx: int, state_name: String) -> void:
	if not climate_chip or not climate_label:
		return
	var color: Color = COLOR_GREEN if state_idx == MarkovChain.State.STABLE else (COLOR_AMBER if state_idx == MarkovChain.State.FLUCTUATING else COLOR_RED)
	climate_label.text = state_name
	climate_label.add_theme_color_override("font_color", color)
	_style_chip_once(climate_chip, color)

func _set_bot_chip(text: String, detail: String, state_key: String = "PATRULLA") -> void:
	if not bot_chip or not bot_state_label:
		return
	var color: Color = COLOR_BLUE
	if state_key == "PERSEGUIR":
		color = COLOR_RED
	elif state_key == "BUSCAR":
		color = COLOR_AMBER
	bot_state_label.text = text
	bot_state_label.add_theme_color_override("font_color", color)
	if agent_status_label:
		agent_status_label.text = detail
	_style_chip_once(bot_chip, color)

func _set_tool_chip(carrying: bool) -> void:
	_tool_shown = carrying
	if not tool_chip or not tool_label:
		return
	tool_label.text = "EN MANO" if carrying else "NINGUNA"
	var color: Color = COLOR_AMBER if carrying else COLOR_DIM
	tool_label.add_theme_color_override("font_color", color)
	_style_chip_once(tool_chip, color)

# Relleno de la barra de energía según el nivel (verde / ámbar / rojo)
func _set_energy_level(level: int) -> void:
	if level == _energy_level or not energy_bar:
		return
	_energy_level = level
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = [COLOR_GREEN, COLOR_AMBER, COLOR_RED][level]
	box.set_corner_radius_all(4)
	energy_bar.add_theme_stylebox_override("fill", box)

# "ESPERANDO EJECUCIÓN" -> "Esperando ejecución" (los textos con ¡ se dejan como están)
func _sentence_case(text: String) -> String:
	if text.begins_with("¡") or text.length() < 2:
		return text
	return (text.substr(0, 1) + text.substr(1).to_lower()).replace("spark", "Spark").replace("(ia ", "(IA ")

# Fondo oscuro + entrada suave (fundido y escala, 0.2 s) de los modales
func _on_modal_visibility_changed(modal: Control) -> void:
	var any_visible: bool = (game_over_modal != null and game_over_modal.visible) or (victory_modal != null and victory_modal.visible)
	if modal_backdrop:
		modal_backdrop.visible = any_visible
	if not modal.visible:
		return
	if _modal_tween and _modal_tween.is_valid():
		_modal_tween.kill()
	modal.pivot_offset = modal.size / 2.0
	modal.modulate.a = 0.0
	modal.scale = Vector2(0.9, 0.9)
	if modal_backdrop:
		modal_backdrop.modulate.a = 0.0
	_modal_tween = create_tween().set_parallel(true)
	_modal_tween.tween_property(modal, "modulate:a", 1.0, 0.2)
	_modal_tween.tween_property(modal, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if modal_backdrop:
		_modal_tween.tween_property(modal_backdrop, "modulate:a", 1.0, 0.2)

func _cmd_label(cmd: String) -> String:
	match cmd:
		"MOVE":       return "MOVER"
		"TURN_LEFT":  return "GIRAR IZQ"
		"TURN_RIGHT": return "GIRAR DER"
		"INTERACT":   return "INTERACTUAR"
		"SONDEAR":    return "SONDEAR"
		_:            return cmd
