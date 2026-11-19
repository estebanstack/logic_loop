extends CharacterBody2D


# BOT DE MANTENIMIENTO AUTÓNOMO (OBSTÁCULO DE LOGIC LOOP)
# Agente autónomo con máquina de estados (PATRULLA -> PERSEGUIR -> BÚSQUEDA -> PATRULLA)
# Opera bajo el ciclo: PERCIBIR → DECIDIR → ACTUAR cuando la simulación está activa.

# Estados de la Máquina de Estados Finita del Bot
enum State { PATROL, CHASE, SEARCH }

# Modo táctico durante el encuentro en la cobertura (juego de inspección):
# NONE = normal | SWEEP = Barrido Intensivo | PATROL = Patrulla Rápida
enum CoverMode { NONE, SWEEP, PATROL }

# Radio de visión
@export var vision_radius: float = 250.0

@export var chase_speed: float = 180.0
@export var patrol_speed: float = 100.0
@export var stopping_distance: float = 20.0

# Estado actual del robot autónomo
var current_state: State = State.PATROL
var prev_state: State = State.PATROL   # Para detectar transiciones de estado

# Variables de Percepción
var perceived_environment: Dictionary = {}
var spark_in_vision: bool = false
var spark_position: Vector2 = Vector2.ZERO
var distance_to_spark: float = 0.0

# Memoria sensorial: Última posición conocida de Spark
var last_known_spark_position: Vector2 = Vector2.ZERO

# Puntos de patrulla en la estación espacial
var patrol_waypoints: Array = []
var current_waypoint_index: int = 0

# Posición y estado inicial para reinicios
var start_position: Vector2 = Vector2.ZERO

# Variables de Decisión y Acción
var calculated_velocity: Vector2 = Vector2.ZERO
var current_action_description: String = "ESPERANDO EJECUCIÓN"
var current_target_string: String = "NO DETECTADO"

# Estado del modo de cobertura (ventana temporal ordenada por Main)
var cover_mode: CoverMode = CoverMode.NONE
var cover_time_left: float = 0.0
var cover_clock: float = 0.0
const COVER_PATROL_SPEED_MULT: float = 1.3
var barrier_position: Vector2 = Vector2(470, 408)

@onready var state_label: Label = get_node_or_null("StateLabel")

func _ready() -> void:
	start_position = global_position
	queue_redraw()

# Dibuja la zona de visión circular alrededor del bot
func _draw() -> void:
	draw_circle(Vector2.ZERO, vision_radius, Color(0.2, 0.6, 1.0, 0.12))
	draw_arc(Vector2.ZERO, vision_radius, 0, TAU, 64, Color(0.2, 0.6, 1.0, 0.4), 2.0)

	# Conos tácticos de la ventana de cobertura
	match cover_mode:
		CoverMode.SWEEP:
			# Cono naranja-rojo de 45° que oscila apuntando hacia la barrera
			var aim: float = (barrier_position - global_position).angle() + sin(cover_clock * 3.0) * 0.35
			_draw_cone(aim, deg_to_rad(45.0), Color(1.0, 0.35, 0.1, 0.35))
		CoverMode.PATROL:
			# Cono azul ancho (120°) hacia donde se desplaza
			var heading: float = calculated_velocity.angle() if calculated_velocity != Vector2.ZERO else 0.0
			_draw_cone(heading, deg_to_rad(120.0), Color(0.2, 0.5, 1.0, 0.30))

# Sector circular de ángulo `width` centrado en `aim` (coordenadas locales del bot)
func _draw_cone(aim: float, width: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	var steps: int = 16
	for i in range(steps + 1):
		var a: float = aim - width / 2.0 + width * float(i) / float(steps)
		points.append(Vector2.from_angle(a) * vision_radius)
	draw_colored_polygon(points, color)

func _physics_process(delta: float) -> void:
	# Cuenta atrás de la ventana de cobertura
	if cover_mode != CoverMode.NONE:
		cover_clock += delta
		cover_time_left -= delta
		if cover_time_left <= 0.0:
			cover_mode = CoverMode.NONE
		queue_redraw()

	# 1. PERCIBIR (PERCEIVE)
	# Consulta a Main para obtener datos de Spark y el estado de simulación.
	perceive()

	# Si la simulación no se está ejecutando (fase de programación), el bot espera en reposo.
	var is_sim_running: bool = perceived_environment.get("is_simulation_running", false)
	if not is_sim_running:
		velocity = Vector2.ZERO
		move_and_slide()
		if state_label:
			state_label.text = "EN ESPERA"
		var environment = get_parent()
		if environment and environment.has_method("bayes_stop"):
			environment.bayes_stop()   # programa terminado / victoria: se limpia el mapa de calor
		if environment and environment.has_method("update_debug_ui"):
			environment.update_debug_ui("PATRULLA", "NO DETECTADO", "N/A", "ESPERANDO EJECUCIÓN DEL PROGRAMA", vision_radius)
		return

	# 2. DECIDIR (DECIDE) Y TRANSICIONES DE ESTADO
	# PATRULLA -> PERSEGUIR -> BÚSQUEDA -> PATRULLA
	decide()

	# 3. ACTUAR (ACT)
	# Aplica el movimiento físico y actualiza las pantallas de estado.
	act()

# 1. PERCEPCIÓN
func perceive() -> void:
	var environment = get_parent()
	if environment and environment.has_method("get_environment_info"):
		perceived_environment = environment.get_environment_info()
	else:
		perceived_environment = {}

	if perceived_environment.get("has_spark", false):
		spark_position = perceived_environment.get("spark_position", global_position)
		distance_to_spark = global_position.distance_to(spark_position)
		
		# Verificación de percepción dentro de la zona de visión circular
		spark_in_vision = distance_to_spark <= vision_radius
		if spark_in_vision:
			# Memoria del agente: guarda la última posición conocida de Spark al estar en visión
			last_known_spark_position = spark_position
	else:
		spark_in_vision = false
		distance_to_spark = 0.0

	patrol_waypoints = perceived_environment.get("patrol_waypoints", [])
	barrier_position = perceived_environment.get("barrier_position", barrier_position)

	# Spark camuflado en la cobertura: el bot no lo percibe aunque esté a rango
	if perceived_environment.get("spark_hidden", false):
		spark_in_vision = false

# 2. TOMA DE DECISIONES Y TRANSICIONES DE ESTADO
func decide() -> void:
	prev_state = current_state

	# CASO A: SPARK ENTRÓ EN EL ÁREA DE VISIÓN
	if spark_in_vision:
		current_state = State.CHASE
		current_target_string = "SPARK DETECTADO"
		# Notifica a Main cuando el Bot detecta a Spark por primera vez
		if prev_state != State.CHASE:
			var env = get_parent()
			if env and env.has_method("notify_spark_detected"): env.notify_spark_detected()
			if env and env.has_method("bayes_stop"): env.bayes_stop()   # lo ve: ya no hace falta la creencia
		
		if distance_to_spark <= stopping_distance:
			_handle_catch_spark()
		else:
			var direction: Vector2 = global_position.direction_to(spark_position)
			calculated_velocity = direction * chase_speed
			current_action_description = "PERSIGUIENDO A SPARK"

	# CASO B: SPARK SALIÓ DEL ÁREA DE VISIÓN (BÚSQUEDA BAYESIANA)
	# En vez de ir solo a la última posición conocida, el Bot va a la casilla más
	# probable de su creencia (estimador MAP) hasta rendirse (ver BayesSearch).
	elif current_state == State.CHASE or current_state == State.SEARCH:
		var env = get_parent()
		# Notifica a Main cuando el Bot pierde a Spark y arranca la creencia en su última posición
		if prev_state == State.CHASE:
			if env and env.has_method("notify_spark_lost"): env.notify_spark_lost()
			if env and env.has_method("bayes_start"): env.bayes_start(last_known_spark_position)

		if env and env.has_method("bayes_step") and not env.bayes_exhausted():
			current_state = State.SEARCH
			current_target_string = "PERDIDO"
			var target: Vector2 = env.bayes_step(global_position, vision_radius, get_physics_process_delta_time())
			calculated_velocity = global_position.direction_to(target) * chase_speed
			current_action_description = "BUSCANDO (IA BAYESIANA)"
		else:
			# Se rinde: creencia demasiado difusa o más de 10 s buscando
			if env and env.has_method("bayes_stop"): env.bayes_stop()
			current_state = State.PATROL
			current_target_string = "NO DETECTADO"
			_decide_patrol()

	# CASO C: SIN CONTACTO PREVIO O PATRULLA NORMAL
	else:
		current_state = State.PATROL
		current_target_string = "NO DETECTADO"
		_decide_patrol()

# Decisión en estado PATRULLA: Navega por los puntos de control de la estación espacial
func _decide_patrol() -> void:
	if patrol_waypoints.size() > 0:
		var target_waypoint: Vector2 = patrol_waypoints[current_waypoint_index]
		var dist_to_waypoint: float = global_position.distance_to(target_waypoint)
		
		if dist_to_waypoint < 20.0:
			current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
			target_waypoint = patrol_waypoints[current_waypoint_index]
			
		var direction: Vector2 = global_position.direction_to(target_waypoint)
		var speed_mult: float = COVER_PATROL_SPEED_MULT if cover_mode == CoverMode.PATROL else 1.0
		calculated_velocity = direction * patrol_speed * speed_mult
		current_action_description = "PATRULLANDO ESTACIÓN (PUNTO %d)" % (current_waypoint_index + 1)
	else:
		calculated_velocity = Vector2.ZERO
		current_action_description = "PATRULLANDO (EN ESPERA)"

# Orden de Main (resultado del juego en cobertura): ir a la posición dada.
# Usa BÚSQUEDA (misma velocidad de persecución) y no PERSEGUIR: si no ve a Spark,
# PERSEGUIR dispararía de inmediato "SPARK PERDIDO" y taparía el banner del evento.
# Como se salta la transición PERSEGUIR -> perdido, aquí arranca la creencia bayesiana.
func force_chase(pos: Vector2) -> void:
	last_known_spark_position = pos
	current_state = State.SEARCH
	prev_state = State.SEARCH
	var env = get_parent()
	if env and env.has_method("bayes_start"): env.bayes_start(pos)

# Activa un modo táctico (CoverMode) durante `duration` segundos
func set_cover_mode(mode: int, duration: float) -> void:
	cover_mode = mode as CoverMode
	cover_time_left = duration
	cover_clock = 0.0
	queue_redraw()

# Evento de juego: Spark es capturado por el Bot (GAME OVER)
func _handle_catch_spark() -> void:
	calculated_velocity = Vector2.ZERO
	current_action_description = "¡GAME OVER - SPARK CAPTURADO!"
	var environment = get_parent()
	if environment and environment.has_method("reset_spark"):
		environment.reset_spark()

# 3. ACCIÓN 
func act() -> void:
	velocity = calculated_velocity
	move_and_slide()

	if state_label:
		state_label.text = _get_state_string()

	var environment = get_parent()
	if environment and environment.has_method("update_debug_ui"):
		var state_str: String = _get_state_string()
		var distance_val: float = distance_to_spark if spark_in_vision else (global_position.distance_to(last_known_spark_position) if current_state == State.SEARCH else 0.0)
		var distance_str: String = "%d px" % int(distance_val) if (spark_in_vision or current_state == State.SEARCH) else "N/A"
		environment.update_debug_ui(state_str, current_target_string, distance_str, current_action_description, vision_radius)

# Reinicia la posición y estado inicial del bot
func reset_to_start() -> void:
	global_position = start_position
	current_state = State.PATROL
	current_waypoint_index = 0
	last_known_spark_position = Vector2.ZERO
	cover_mode = CoverMode.NONE
	cover_time_left = 0.0
	queue_redraw()
	calculated_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	if state_label:
		state_label.text = "EN ESPERA"

func _get_state_string() -> String:
	match current_state:
		State.PATROL:
			return "PATRULLA"
		State.CHASE:
			return "PERSEGUIR"
		State.SEARCH:
			return "BUSCAR"
		_:
			return "DESCONOCIDO"
