extends Node2D

# ENTORNO DE LA ESTACIÓN ESPACIAL (LOGIC LOOP)
# Main actúa como la autoridad del entorno conectando:
# - SPARK            → Agente programado por el jugador
# - BOT DE MANTENIMIENTO → Agente autónomo / Obstáculo
# - COMPONENTE DE REPARACIÓN → Objetivo ambiental


@onready var maintenance_bot: Node2D  = get_node_or_null("MaintenanceBot")
@onready var spark: Node2D            = get_node_or_null("Spark")
@onready var repair_component: Node2D = get_node_or_null("RepairComponent")

# UI NODES
@onready var agent_status_label: Label   = get_node_or_null("UI/DebugPanel/Margin/VBox/StatusText")
@onready var detection_banner: Label     = get_node_or_null("UI/DebugPanel/Margin/VBox/DetectionBanner")
@onready var program_list: Label         = get_node_or_null("UI/ProgrammingPanel/Margin/VBox/ScrollList/ProgramList")
@onready var feedback_label: Label       = get_node_or_null("UI/ProgrammingPanel/Margin/VBox/FeedbackText")
@onready var game_over_modal: Control    = get_node_or_null("UI/GameOverModal")
@onready var victory_modal: Control      = get_node_or_null("UI/VictoryModal")
@onready var detection_timer: Timer      = get_node_or_null("UI/DetectionTimer")

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
	if not repair_component or not repair_component.visible or is_level_completed:
		return
	if spark_pos.distance_to(repair_component.global_position) <= 80.0:
		is_level_completed    = true
		repair_component.visible = false
		is_simulation_running = false
		notify_execution_status("¡COMPONENTE DE REPARACIÓN RECOLECTADO!")
		if victory_modal: victory_modal.visible = true
	else:
		notify_execution_status("Demasiado lejos del componente")

# GAME OVER
func reset_spark() -> void:
	is_simulation_running = false
	notify_execution_status("¡SPARK FUE CAPTURADO!")
	if game_over_modal: game_over_modal.visible = true
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

func _cmd_label(cmd: String) -> String:
	match cmd:
		"MOVE":       return "MOVER"
		"TURN_LEFT":  return "GIRAR IZQ"
		"TURN_RIGHT": return "GIRAR DER"
		"INTERACT":   return "INTERACTUAR"
		_:            return cmd
