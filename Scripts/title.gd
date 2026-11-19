extends Control

# PANTALLA DE TÍTULO (escena principal). JUGAR abre el nivel; CÓMO JUGAR muestra
# un resumen de controles, objetivo y los 7 paradigmas; SALIR cierra el juego.

const GAME_SCENE: String = "res://Scenes/main.tscn"

@onready var menu_box: VBoxContainer = $Center/MenuBox
@onready var btn_play: Button = $Center/MenuBox/BtnPlay
@onready var help_overlay: Control = $HelpOverlay
@onready var help_panel: PanelContainer = $HelpOverlay/HelpPanel

var _tween: Tween = null

func _ready() -> void:
	help_overlay.visible = false
	btn_play.grab_focus()
	# Entrada suave del menú
	menu_box.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(menu_box, "modulate:a", 1.0, 0.5)

func _on_btn_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_btn_help_pressed() -> void:
	help_overlay.visible = true
	help_panel.pivot_offset = help_panel.size / 2.0
	help_panel.modulate.a = 0.0
	help_panel.scale = Vector2(0.95, 0.95)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(help_panel, "modulate:a", 1.0, 0.2)
	_tween.tween_property(help_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_btn_close_pressed() -> void:
	help_overlay.visible = false
	btn_play.grab_focus()

func _on_btn_quit_pressed() -> void:
	get_tree().quit()
