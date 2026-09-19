extends Control

# BAHÍA LOGÍSTICA DE LA ESTACIÓN (SIMULACIÓN DE EVENTOS DISCRETOS)
# Modela una cola FIFO finita (M/M/1/K) con eventos discretos de llegada y servicio.

var queue_array: Array = []
var max_capacity: int = 8

# Acumuladores de eventos
var total_arrivals: int = 0
var total_served: int = 0

@onready var arrival_timer: Timer = get_node_or_null("ArrivalTimer")
@onready var service_timer: Timer = get_node_or_null("ServiceTimer")
@onready var conveyor_belt: HBoxContainer = _find_conveyor_belt()
@onready var status_label: Label = _find_status_label()

var crate_texture: Texture2D = null

func _find_conveyor_belt() -> HBoxContainer:
	if has_node("Margin/VBox/ConveyorBelt"):
		return get_node("Margin/VBox/ConveyorBelt") as HBoxContainer
	if has_node("ConveyorBelt"):
		return get_node("ConveyorBelt") as HBoxContainer
	return null

func _find_status_label() -> Label:
	if has_node("Margin/VBox/StatusLabel"):
		return get_node("Margin/VBox/StatusLabel") as Label
	if has_node("StatusLabel"):
		return get_node("StatusLabel") as Label
	return null

func _ready() -> void:
	if ResourceLoader.exists("res://Assets/crate.svg"):
		crate_texture = load("res://Assets/crate.svg")

	if not conveyor_belt:
		conveyor_belt = _find_conveyor_belt()
	if not status_label:
		status_label = _find_status_label()
	if not arrival_timer:
		arrival_timer = get_node_or_null("ArrivalTimer")
	if not service_timer:
		service_timer = get_node_or_null("ServiceTimer")

	if arrival_timer:
		arrival_timer.wait_time = 1.8
		arrival_timer.start()
	if service_timer:
		service_timer.wait_time = 2.4
		service_timer.start()
	
	update_ui()

# EVENTO DISCRETO 1: LLEGADA DE HERRAMIENTA A LA CINTA
func _on_arrival_timer_timeout() -> void:
	if queue_array.size() < max_capacity:
		total_arrivals += 1
		var item: Control
		
		if crate_texture:
			var tex_rect = TextureRect.new()
			tex_rect.texture = crate_texture
			tex_rect.custom_minimum_size = Vector2(36, 36)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			item = tex_rect
		else:
			var new_box = ColorRect.new()
			new_box.custom_minimum_size = Vector2(36, 36)
			new_box.color = Color(0.9, 0.5, 0.1)
			item = new_box
		
		if conveyor_belt:
			conveyor_belt.add_child(item)
		queue_array.append(item)
		update_ui()
	else:
		if status_label:
			status_label.text = "Cola llena: buffer saturado (%d/%d)" % [queue_array.size(), max_capacity]
			status_label.modulate = Color(1.0, 0.3, 0.3)

# EVENTO DISCRETO 2: SERVICIO / DESPACHO DE HERRAMIENTA
func _on_service_timer_timeout() -> void:
	if queue_array.size() > 0:
		total_served += 1
		var processed_box = queue_array.pop_front()
		if is_instance_valid(processed_box):
			processed_box.queue_free()
		update_ui()

# Consulta si hay al menos una herramienta disponible en la cinta
func has_available_tool() -> bool:
	return queue_array.size() > 0

# Consume una herramienta de la cola cuando Spark interactúa
func consume_tool() -> bool:
	if queue_array.size() > 0:
		total_served += 1
		var box = queue_array.pop_front()
		if is_instance_valid(box):
			box.queue_free()
		update_ui()
		return true
	return false

func reset_queue() -> void:
	for item in queue_array:
		if is_instance_valid(item):
			item.queue_free()
	queue_array.clear()
	total_arrivals = 0
	total_served = 0
	update_ui()
	if arrival_timer:
		arrival_timer.start()
	if service_timer:
		service_timer.start()

func update_ui() -> void:
	if not status_label:
		return
	status_label.modulate = Color(1, 1, 1)
	status_label.text = "Cola de Herramientas: %d / %d | Llegadas: %d | Servidas: %d" % [
		queue_array.size(), max_capacity, total_arrivals, total_served
	]
