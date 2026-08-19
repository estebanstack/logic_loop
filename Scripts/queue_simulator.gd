extends Control

# Parametros de la cola
var queue_array : Array = []
var max_capacity : int = 10

@onready var arrival_timer = $ArrivalTimer
@onready var service_timer = $ServiceTimer
@onready var conveyor_belt = $ConveyorBelt
@onready var status_label = $StatusLabel

func _ready():
	arrival_timer.wait_time = 1.5
	service_timer.wait_time = 2.0
	
	update_ui()
	arrival_timer.start()
	service_timer.start()

func _on_arrival_timer_timeout():
	if queue_array.size() < max_capacity:
		var new_box = ColorRect.new()
		new_box.custom_minimum_size = Vector2(50, 50)
		new_box.color = Color(0.8, 0.2, 0.2) 
		
		conveyor_belt.add_child(new_box)
		queue_array.append(new_box)
		update_ui()
	else:
		status_label.text = "Ups parece que ya no caben mas herramientas"
		status_label.modulate = Color(1, 0, 0)
		arrival_timer.stop()
		service_timer.stop()

func _on_service_timer_timeout():
	if queue_array.size() > 0:
		var processed_box = queue_array.pop_front()
		processed_box.queue_free()
		update_ui()

func update_ui():
	if arrival_timer.is_stopped() == false:
		status_label.text = "Herramientas de reparación:  " + str(queue_array.size()) + " / " + str(max_capacity)
