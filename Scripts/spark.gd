extends CharacterBody2D

# ------------------------------------------------------------------------------
# DRON SPARK - AGENTE PROGRAMABLE DEL JUGADOR (LOGIC LOOP)
# Spark ejecuta secuencias de comandos programadas por el jugador:
# - MOVER       → Avanza 1 casilla en la cuadrícula
# - GIRAR IZQ   → Gira -90°
# - GIRAR DER   → Gira +90°
# - INTERACTUAR → Intenta recolectar el componente de reparación
# - SONDEAR     → Emite pulsos de eco contra la barrera dañada (HMM) y decide
#                 FRACTURAR o RODEAR por su cuenta
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

# Camino programado (casillas) que Spark recorre solo, una por paso, antes de
# retomar el programa (resultado de SONDEAR: ruta de embestida o de desvío)
var auto_path: Array[Vector2] = []

# Aturdimiento por choque contra un muro blindado (pausa el temporizador de pasos)
var stun_time_left: float = 0.0

# Camuflaje térmico (cobertura del juego de inspección)
const CAMO_ALPHA: float = 0.35
var is_camouflaged: bool = false
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var spark_label: Label = get_node_or_null("SparkLabel")
@onready var rush_trail: CPUParticles2D = get_node_or_null("RushTrail")

# Movimiento suave SOLO visual: la lógica mueve global_position al instante y los
# elementos visuales arrancan desplazados -Δ y vuelven a 0 en SLIDE_TIME segundos.
# Ninguna regla del juego lee este desplazamiento.
const SLIDE_TIME: float = 0.18
const TOOL_BASE_POS: Vector2 = Vector2(0, -22)
var _prev_position: Vector2 = Vector2.ZERO
var _visual_offset: Vector2 = Vector2.ZERO
var _slide_tween: Tween = null

func _ready() -> void:
	start_position = global_position
	start_direction = facing_direction
	_prev_position = global_position
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

	# Aturdido: la energía sigue fluyendo, pero no avanza el programa
	if stun_time_left > 0.0:
		stun_time_left -= delta
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
		environment.notify_execution_status("EJECUTANDO PROGRAMA...")

# Ejecuta el siguiente comando en la cola y actualiza el indicador de progreso
func _execute_next_step() -> void:
	# Un camino programado por SONDEAR tiene prioridad sobre el programa
	if auto_path.size() > 0:
		energy_stock = max(0.0, energy_stock - motor_step_cost)
		global_position = auto_path.pop_front()
		_notify_dynamics_update(solar_inflow_rate - base_outflow_rate)
		_notify_position()
		return

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
	if current_cmd in ["MOVE", "TURN_LEFT", "TURN_RIGHT", "SONDEAR"]:
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
		"SONDEAR":
			_cmd_probe()
	_notify_position()

func _cmd_move() -> void:
	var target: Vector2 = global_position + _get_direction_vector() * grid_size
	# Los muros son un conjunto lógico de casillas (Spark se teletransporta por la
	# cuadrícula, no usa move_and_slide): si está bloqueada, choca y se queda
	# en su sitio, pero la energía del paso ya se gastó.
	var environment = get_parent()
	if environment and environment.has_method("is_cell_blocked") and environment.is_cell_blocked(target):
		if environment.has_method("notify_execution_status"):
			environment.notify_execution_status("Spark chocó contra un obstáculo")
		return
	global_position = target

# SONDEAR: pide a Main el diagnóstico de la barrera que tiene al frente
func _cmd_probe() -> void:
	var environment = get_parent()
	if environment and environment.has_method("run_obstacle_probe"):
		environment.run_obstacle_probe(global_position, facing_direction)

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
	auto_path.clear()
	stun_time_left = 0.0
	set_camouflaged(false)
	global_position = start_position
	_prev_position = start_position
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	_set_visual_offset(Vector2.ZERO)
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

# --- EFECTOS DE LA BARRERA Y LA COBERTURA (los ordena Main) ---

# Carga un camino de casillas que se recorre un paso por step_delay
func follow_path(path: Array[Vector2]) -> void:
	auto_path = path.duplicate()

func stun(seconds: float) -> void:
	stun_time_left = seconds

func drain_energy(amount: float) -> void:
	energy_stock = max(0.0, energy_stock - amount)
	_notify_dynamics_update(solar_inflow_rate - base_outflow_rate)

func add_energy(amount: float) -> void:
	energy_stock = min(max_energy, energy_stock + amount)
	_notify_dynamics_update(solar_inflow_rate - base_outflow_rate)

# Camuflaje: sprite casi transparente, contorno cian y etiqueta [CAMUFLADO]
func set_camouflaged(on: bool) -> void:
	is_camouflaged = on
	if sprite:
		sprite.modulate.a = CAMO_ALPHA if on else 1.0
	if spark_label:
		spark_label.text = "Spark [CAMUFLADO]" if on else "Spark (Dron)"
	queue_redraw()

# Estela corta de propulsores al avanzar a toda velocidad (AVANZAR / Rush)
func play_rush_trail() -> void:
	if rush_trail:
		rush_trail.restart()
		rush_trail.emitting = true

func _draw() -> void:
	if is_camouflaged:
		draw_arc(_visual_offset, 26.0, 0.0, TAU, 32, Color(0.2, 0.9, 1.0, 0.9), 2.0)

func _get_direction_vector() -> Vector2:
	match facing_direction:
		0: return Vector2.RIGHT
		1: return Vector2.DOWN
		2: return Vector2.LEFT
		3: return Vector2.UP
		_: return Vector2.RIGHT

# Solo el sprite (y la estela) giran con la dirección: la etiqueta, el icono de
# herramienta y el anillo de camuflaje se quedan siempre derechos.
func _update_rotation() -> void:
	var angle: float = deg_to_rad(facing_direction * 90.0)
	if sprite:
		sprite.rotation = angle
	if rush_trail:
		rush_trail.rotation = angle

# Aplica el desplazamiento visual a sprite, herramienta, etiqueta y anillo
func _set_visual_offset(offset: Vector2) -> void:
	_visual_offset = offset
	if sprite:
		sprite.position = offset
	if tool_indicator:
		tool_indicator.position = TOOL_BASE_POS + offset
	if spark_label:
		spark_label.position = Vector2(-50, 18) + offset
	if is_camouflaged:
		queue_redraw()

# Tras un paso: el cuerpo ya está en la casilla nueva, lo visual se desliza hasta ella
func _slide_from_previous() -> void:
	var delta_pos: Vector2 = _prev_position - global_position
	_prev_position = global_position
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	if delta_pos == Vector2.ZERO:
		return
	_slide_tween = create_tween()
	_slide_tween.tween_method(_set_visual_offset, delta_pos, Vector2.ZERO, SLIDE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# Notifica a Main para reconstruir la visualización del programa
func _notify_sequence_update() -> void:
	var environment = get_parent()
	if environment and environment.has_method("update_program_sequence_ui"):
		environment.update_program_sequence_ui(command_queue, current_step_index, is_executing)

# Notifica a Main la posición tras cada paso (dispara el encuentro en la cobertura)
func _notify_position() -> void:
	_slide_from_previous()
	var environment = get_parent()
	if environment and environment.has_method("on_spark_stepped"):
		environment.on_spark_stepped(global_position)

# Notifica a Main los valores continuos del sistema dinámico de energía
func _notify_dynamics_update(net_rate: float) -> void:
	var environment = get_parent()
	if environment and environment.has_method("update_dynamics_ui"):
		environment.update_dynamics_ui(energy_stock, max_energy, net_rate, solar_inflow_rate, base_outflow_rate)
