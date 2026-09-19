extends CharacterBody2D

# ------------------------------------------------------------------------------
# DRON SPARK - AGENTE PROGRAMABLE DEL JUGADOR (LOGIC LOOP)
# Spark ejecuta secuencias de comandos programadas por el jugador:
# - MOVER       → Avanza 1 casilla en la cuadrícula
# - GIRAR IZQ   → Gira -90°
# - GIRAR DER   → Gira +90°
# - INTERACTUAR → Intenta recolectar el componente de reparación
#
# Integra el paradigma de SISTEMAS DINÁMICOS (Stock & Flow):
# - Stock: Batería / Nivel de Energía acumulada
# - Inflow: Recarga pasiva solar (+%/s)
# - Outflow: Consumo continuo base (-%/s) + gasto por motor (-%/paso)
# ------------------------------------------------------------------------------

@export var grid_size: float = 64.0
@export var step_delay: float = 0.5

# Direcciones: 0=DERECHA, 1=ABAJO, 2=IZQUIERDA, 3=ARRIBA
var facing_direction: int = 0

# Secuencia de programación
var command_queue: Array[String] = []
var is_executing: bool = false
var current_step_index: int = 0  # Índice del comando ACTUALMENTE ejecutándose
var step_timer: float = 0.0

var start_position: Vector2 = Vector2.ZERO
var start_direction: int = 0

# Variables del Sistema Dinámico (Stock & Flow)
var energy_stock: float = 100.0
var max_energy: float = 100.0
var solar_inflow_rate: float = 1.0     # Tasa de recarga solar continua (+1.0 %/s)
var base_outflow_rate: float = 1.5      # Tasa de consumo base continua (-1.5 %/s)
var motor_step_cost: float = 4.0        # Consumo por acción de motor (-4.0 %/paso)

# Herramienta de reparación obtenida de la bahía de eventos discretos
var has_tool: bool = false
@onready var tool_indicator: Node2D = get_node_or_null("ToolSprite")

func _ready() -> void:
	start_position = global_position
	start_direction = facing_direction
	_update_rotation()
	_notify_dynamics_update(0.0)

func _physics_process(delta: float) -> void:
	if not is_executing:
		return

	# Integración continua del sistema dinámico (Euler: dE/dt = Inflow - Outflow)
	var net_rate: float = solar_inflow_rate - base_outflow_rate
	energy_stock += net_rate * delta
	energy_stock = clamp(energy_stock, 0.0, max_energy)
	_notify_dynamics_update(net_rate)

	# Falla por agotamiento energético
	if energy_stock <= 0.0:
		_handle_battery_depleted()
		return

	step_timer += delta
	if step_timer >= step_delay:
		step_timer = 0.0
		_execute_next_step()

# --- SISTEMA DE PROGRAMACIÓN ---

func add_command(command: String) -> void:
	if is_executing:
		return
	command_queue.append(command)
	_notify_sequence_update()

func clear_commands() -> void:
	if is_executing:
		return
	command_queue.clear()
	_notify_sequence_update()

func execute_program() -> void:
	if command_queue.size() == 0 or is_executing:
		return
	is_executing = true
	current_step_index = 0
	step_timer = step_delay  # ejecuta primer paso inmediatamente tras el primer tick
	_notify_sequence_update()
	var environment = get_parent()
	if environment and environment.has_method("notify_execution_status"):
		environment.notify_execution_status("▶  EJECUTANDO PROGRAMA...")

# Ejecuta el siguiente comando en la cola y actualiza el indicador de progreso
func _execute_next_step() -> void:
	if current_step_index >= command_queue.size():
		is_executing = false
		_notify_sequence_update()
		var environment = get_parent()
		if environment and environment.has_method("on_program_complete"):
			environment.on_program_complete()
		return

	var current_cmd: String = command_queue[current_step_index]
	current_step_index += 1

	# Consumo del sistema dinámico por activación de motores
	if current_cmd in ["MOVE", "TURN_LEFT", "TURN_RIGHT"]:
		energy_stock = max(0.0, energy_stock - motor_step_cost)

	# Actualiza el indicador visual ANTES de ejecutar el comando
	_notify_sequence_update()
	_notify_dynamics_update(solar_inflow_rate - base_outflow_rate)

	match current_cmd:
		"MOVE":
			_cmd_move()
		"TURN_LEFT":
			_cmd_turn_left()
		"TURN_RIGHT":
			_cmd_turn_right()
		"INTERACT":
			_cmd_interact()

func _cmd_move() -> void:
	global_position += _get_direction_vector() * grid_size

func _cmd_turn_left() -> void:
	facing_direction = (facing_direction - 1 + 4) % 4
	_update_rotation()

func _cmd_turn_right() -> void:
	facing_direction = (facing_direction + 1) % 4
	_update_rotation()

func _cmd_interact() -> void:
	var environment = get_parent()
	if environment and environment.has_method("check_interact"):
		environment.check_interact(global_position)

func _handle_battery_depleted() -> void:
	is_executing = false
	_notify_sequence_update()
	var environment = get_parent()
	if environment and environment.has_method("on_battery_depleted"):
		environment.on_battery_depleted()

func stop_execution() -> void:
	is_executing = false
	current_step_index = 0

func reset_to_start() -> void:
	stop_execution()
	global_position = start_position
	facing_direction = start_direction
	energy_stock = max_energy
	set_has_tool(false)
	_update_rotation()
	_notify_sequence_update()
	_notify_dynamics_update(0.0)

func set_has_tool(value: bool) -> void:
	has_tool = value
	if tool_indicator:
		tool_indicator.visible = value

func _get_direction_vector() -> Vector2:
	match facing_direction:
		0: return Vector2.RIGHT
		1: return Vector2.DOWN
		2: return Vector2.LEFT
		3: return Vector2.UP
		_: return Vector2.RIGHT

func _update_rotation() -> void:
	rotation = deg_to_rad(facing_direction * 90.0)

# Notifica a Main para reconstruir la visualización del programa
func _notify_sequence_update() -> void:
	var environment = get_parent()
	if environment and environment.has_method("update_program_sequence_ui"):
		environment.update_program_sequence_ui(command_queue, current_step_index, is_executing)

# Notifica a Main los valores continuos del sistema dinámico de energía
func _notify_dynamics_update(net_rate: float) -> void:
	var environment = get_parent()
	if environment and environment.has_method("update_dynamics_ui"):
		environment.update_dynamics_ui(energy_stock, max_energy, net_rate, solar_inflow_rate, base_outflow_rate)
