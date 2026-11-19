extends Node2D

# ------------------------------------------------------------------------------
# BARRERA DAÑADA (OBSTÁCULO FÍSICO DEL CORREDOR PRINCIPAL)
# Su integridad real (FRÁGIL / BLINDADO) es un estado OCULTO: el aspecto es
# idéntico en ambos casos. Solo el HMM puede inferirla a partir de los ecos.
# Patrón mediador: la barrera NO conoce a Spark ni al Bot; Main le ordena
# destruirse, restaurarse o mostrar el resultado del sondeo.
# ------------------------------------------------------------------------------

@export var is_breakable: bool = true   # Estado oculto verdadero (se sincroniza desde Main)
@export var is_destroyed: bool = false

const HALF_SIZE: float = 28.0

@onready var echo_label: Label = get_node_or_null("EchoLabel")
@onready var debris: CPUParticles2D = get_node_or_null("Debris")

# Bloque agrietado dibujado por código (sin assets nuevos)
func _draw() -> void:
	if is_destroyed:
		return
	var rect: Rect2 = Rect2(-HALF_SIZE, -HALF_SIZE, HALF_SIZE * 2.0, HALF_SIZE * 2.0)
	draw_rect(rect, Color(0.42, 0.36, 0.30))
	draw_rect(rect, Color(0.85, 0.65, 0.30), false, 2.0)
	# Grietas
	var crack_color: Color = Color(0.12, 0.10, 0.08)
	draw_polyline(PackedVector2Array([Vector2(-6, -HALF_SIZE), Vector2(2, -10), Vector2(-8, 4), Vector2(4, HALF_SIZE)]), crack_color, 2.0)
	draw_polyline(PackedVector2Array([Vector2(2, -10), Vector2(18, -16)]), crack_color, 2.0)
	draw_polyline(PackedVector2Array([Vector2(-8, 4), Vector2(-20, 10)]), crack_color, 2.0)

# Rotura: oculta el bloque y lanza una ráfaga única de escombros
func destroy() -> void:
	is_destroyed = true
	queue_redraw()
	if debris:
		debris.restart()
		debris.emitting = true

# Deshace destroy() y borra el último diagnóstico mostrado
func restore() -> void:
	is_destroyed = false
	queue_redraw()
	if debris:
		debris.emitting = false
	if echo_label:
		echo_label.text = ""
		echo_label.visible = false

# Muestra los ecos recibidos y la creencia posterior P(Frágil | ecos)
func show_echoes(echo_names: Array[String], belief_fragil: float) -> void:
	if echo_label:
		echo_label.text = "%s\nP(Frágil) = %.2f" % [" · ".join(echo_names), belief_fragil]
		echo_label.visible = true
