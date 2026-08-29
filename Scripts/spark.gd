extends CharacterBody2D

# ------------------------------------------------------------------------------
# DRON SPARK - AGENTE PROGRAMABLE DEL JUGADOR (LOGIC LOOP)
# Spark ejecuta secuencias de comandos programadas por el jugador:
# - MOVER       → Avanza 1 casilla en la cuadrícula
# - GIRAR IZQ   → Gira -90°
# - GIRAR DER   → Gira +90°
# - INTERACTUAR → Intenta recolectar el componente de reparación
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

func _ready() -> void:
	start_position = global_position
	start_direction = facing_direction
	_update_rotation()

func _physics_process(delta: float) -> void:
	if not is_executing:
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

	# Actualiza el indicador visual ANTES de ejecutar el comando
	_notify_sequence_update()

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

func stop_execution() -> void:
	is_executing = false
	current_step_index = 0

func reset_to_start() -> void:
	stop_execution()
	global_position = start_position
	facing_direction = start_direction
	_update_rotation()
	_notify_sequence_update()

func _get_direction_vector() -> Vector2:
	match facing_direction:
		0: return Vector2.RIGHT
		1: return Vector2.DOWN
		2: return Vector2.LEFT
		3: return Vector2.UP
		_: return Vector2.RIGHT

func _update_rotation() -> void:
	rotation = deg_to_rad(facing_direction * 90.0)

# Notifica a Main para reconstruir la visualización del programa con indicadores ✓ ▶ ○
func _notify_sequence_update() -> void:
	var environment = get_parent()
	if environment and environment.has_method("update_program_sequence_ui"):
		environment.update_program_sequence_ui(command_queue, current_step_index, is_executing)
