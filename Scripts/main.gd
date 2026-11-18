extends Node2D

# ENTORNO DE LA ESTACIÓN ESPACIAL (LOGIC LOOP)
# Main actúa como la autoridad central del entorno conectando los 6 paradigmas:
# 1. AGENTES (FSM & Percepción): Bot de Mantenimiento
# 2. EVENTOS DISCRETOS (DES - M/M/1/K): Bahía Logística / Dispensador de herramientas
# 3. SISTEMAS DINÁMICOS (Stock & Flow): Batería solar y consumo de motores de Spark
# 4. CADENAS DE MARKOV: Proceso estocástico del clima y radiación de la estación
# 5. MODELOS OCULTOS DE MARKOV (HMM): Diagnóstico latente de desgaste del núcleo y Viterbi
# 6. TEORÍA DE JUEGOS: Interacción estratégica (Nash, matriz de pagos) entre Spark y Bot

@onready var maintenance_bot: Node2D  = get_node_or_null("MaintenanceBot")
@onready var spark: Node2D            = get_node_or_null("Spark")
@onready var repair_component: Node2D = get_node_or_null("RepairComponent")
@onready var tool_dispenser: Node2D   = get_node_or_null("ToolDispenser")

# UI NODES EXISTENTES
@onready var agent_status_label: Label     = get_node_or_null("UI/DebugPanel/Margin/VBox/StatusText")
@onready var detection_banner: Label       = get_node_or_null("UI/DebugPanel/Margin/VBox/DetectionBanner")
@onready var program_list: Label           = get_node_or_null("UI/ProgrammingPanel/Margin/VBox/ScrollList/ProgramList")
@onready var feedback_label: Label         = get_node_or_null("UI/ProgrammingPanel/Margin/VBox/FeedbackText")
@onready var game_over_modal: Control      = get_node_or_null("UI/GameOverModal")
@onready var victory_modal: Control        = get_node_or_null("UI/VictoryModal")
@onready var detection_timer: Timer        = get_node_or_null("UI/DetectionTimer")

# NODES SISTEMAS DINÁMICOS Y EVENTOS DISCRETOS
@onready var dynamics_status_label: Label  = get_node_or_null("UI/DynamicsPanel/Margin/VBox/DynamicsText")
@onready var energy_bar: ProgressBar       = get_node_or_null("UI/DynamicsPanel/Margin/VBox/EnergyBar")
@onready var queue_simulator: Control      = get_node_or_null("UI/QueueSimulator")

# NUEVOS MOTORES MATEMÁTICOS Y PANEL AVANZADO
@onready var markov_chain: MarkovChain                      = get_node_or_null("MarkovChain")
@onready var hidden_markov_model: HiddenMarkovModel          = get_node_or_null("HiddenMarkovModel")
@onready var game_theory_engine: GameTheoryEngine            = get_node_or_null("GameTheoryEngine")
@onready var advanced_models_panel: AdvancedModelsPanel      = get_node_or_null("UI/AdvancedModelsPanel")

# Parámetros base para restablecer tras modificaciones ambientales/estratégicas
var base_solar_inflow: float = 1.0
var base_bot_speed: float = 100.0
var base_motor_cost: float = 4.0

# Rutas de patrulla en la estación espacial para el Bot de Mantenimiento
@export var station_patrol_waypoints: Array[Vector2] = [
	Vector2(200, 200),
	Vector2(1080, 200),
	Vector2(1080, 520),
	Vector2(200, 520)
]

var is_simulation_running: bool = false
var is_level_completed: bool = false

func _ready() -> void:
	if game_over_modal: game_over_modal.visible = false
	if victory_modal:   victory_modal.visible   = false
	if detection_banner: detection_banner.visible = false

	_init_advanced_engines()

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

	# Conexión con el panel UI
	if advanced_models_panel:
		advanced_models_panel.setup_engines(markov_chain, hidden_markov_model, game_theory_engine)
	
	# Escucha de señales para retroalimentar la física y simulación del entorno
	if markov_chain:
		markov_chain.state_changed.connect(_on_markov_climate_changed)
	if game_theory_engine:
		game_theory_engine.round_resolved.connect(_on_strategic_round_resolved)

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
		"is_simulation_running": is_simulation_running
	}

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
					msg.text = (
						"¡Felicidades! Spark reparó la estación con éxito.\n" +
						"Diagnóstico Oculto (Viterbi HMM): Componente en estado [%s].\n" +
						"¡La falla latente ha sido neutralizada!" % diag_str
					)
				victory_modal.visible = true
			return

	notify_execution_status("No hay nada con qué interactuar aquí")

# ==============================================================================
# INTEGRACIÓN DEL PARADIGMA 4: CADENA DE MARKOV EN EL JUEGO
# ==============================================================================
func _on_markov_climate_changed(_old: int, new_state: int, state_name: String) -> void:
	if not markov_chain:
		return
	
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
		if detection_banner:
			detection_banner.text = "[!] CLIMA ESPACIAL: TORMENTA DE RADIACIÓN"
			detection_banner.visible = true
			if detection_timer: detection_timer.start(2.5)

# ==============================================================================
# INTEGRACIÓN DEL PARADIGMA 6: TEORÍA DE JUEGOS EN EL JUEGO
# ==============================================================================
func _on_strategic_round_resolved(data: Dictionary) -> void:
	var spark_action: int = data.get("a1", 0)
	var bot_action: int = data.get("a2", 0)
	
	# Modificaciones al agente Spark:
	# Cauto (0): Mayor eficiencia de energía (menor consumo motor)
	# Audaz (1): Mayor consumo motor
	if spark:
		if spark_action == 0:
			spark.set("motor_step_cost", 2.5)
		else:
			spark.set("motor_step_cost", 4.5)
			
	# Modificaciones al Bot:
	# Escaneo Estricto (1): Mayor radio de visión
	# Patrulla Suave (0): Visión normal
	if maintenance_bot:
		if bot_action == 1:
			maintenance_bot.set("vision_radius", 285.0)
		else:
			maintenance_bot.set("vision_radius", 250.0)
		maintenance_bot.queue_redraw()

# GAME OVER POR CAPTURA
func reset_spark() -> void:
	is_simulation_running = false
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
	if detection_banner:
		detection_banner.text    = "[!] ¡SPARK DETECTADO!"
		detection_banner.visible = true
	if detection_timer: detection_timer.start(2.0)

func notify_spark_lost() -> void:
	if detection_banner:
		detection_banner.text    = "[?] SPARK PERDIDO — BUSCANDO..."
		detection_banner.visible = true
	if detection_timer: detection_timer.start(2.0)

func _on_detection_timer_timeout() -> void:
	if detection_banner: detection_banner.visible = false

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
		program_list.text = "[ Vacío — añade comandos ]"
		return

	var lines: String = ""
	for i in range(commands.size()):
		var label: String = _cmd_label(commands[i])
		var prefix: String
		if executing:
			if i < current_step_index_val(current_idx) - 1:
				prefix = "[X] "      # ejecutado
			elif i == current_step_index_val(current_idx) - 1:
				prefix = "[>] "      # ejecutándose
			else:
				prefix = "[ ] "      # pendiente
		else:
			prefix = "[ ] "
		lines += prefix + label + "\n"
	program_list.text = lines.strip_edges()

func current_step_index_val(idx: int) -> int:
	return idx

func notify_execution_status(msg: String) -> void:
	if feedback_label:
		feedback_label.text = "ESTADO: " + msg

func update_debug_ui(state_str: String, target_str: String, distance_str: String, action_str: String, vision_radius: float) -> void:
	if agent_status_label:
		agent_status_label.text = (
			"Estado:    %s\nObjetivo:  %s\nDistancia: %s\nAcción:    %s\nVisión:    %d px"
			% [state_str, target_str, distance_str, action_str, int(vision_radius)]
		)

func update_dynamics_ui(energy: float, max_energy: float, net_rate: float, inflow: float, outflow: float) -> void:
	if energy_bar:
		energy_bar.value = (energy / max_energy) * 100.0
	if dynamics_status_label:
		dynamics_status_label.text = (
			"Stock (Energía): %.1f %%\nInflow (Solar):   +%.1f %%/s\nOutflow (Base):   -%.1f %%/s\nTasa Neta dE/dt:  %+.1f %%/s\nBucle: Balance continuo"
			% [energy, inflow, outflow, net_rate]
		)

func _cmd_label(cmd: String) -> String:
	match cmd:
		"MOVE":       return "MOVER"
		"TURN_LEFT":  return "GIRAR IZQ"
		"TURN_RIGHT": return "GIRAR DER"
		"INTERACT":   return "INTERACTUAR"
		_:            return cmd
