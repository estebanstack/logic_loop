# Logic Loop

Juego de programación en Godot 4.7: Spark (un dron) debe recoger una herramienta en el dispensador y repararla en el componente de la estación sin que el Bot de Mantenimiento lo capture.

## Cómo ejecutar
1. Abrir la carpeta con Godot 4.7 y pulsar F5 (la escena principal es `Scenes/title.tscn`), o desde consola: `godot --path .`
2. Demo automática (programa fijo): `godot --path . res://Scenes/main.tscn -- --autodemo`

## Controles y objetivo
Añade comandos con los botones (MOVER, GIRAR IZQ/DER, INTERACTUAR, SONDEAR) y pulsa EJECUTAR. BORRAR TODO reinicia. Cada paso mueve a Spark 64 px.

## Los 7 paradigmas
| # | Paradigma | Archivo |
|---|-----------|---------|
| 1 | Agentes (FSM, visión) | `Scripts/npc.gd` |
| 2 | Eventos discretos (M/M/1/K) | `Scripts/queue_simulator.gd` |
| 3 | Sistemas dinámicos (stock y flujos) | `Scripts/spark.gd` |
| 4 | Cadenas de Markov | `Scripts/markov_chain.gd` |
| 5 | HMM (Forward, Viterbi, barrera) | `Scripts/hidden_markov_model.gd`, `Scripts/damaged_barrier.gd` |
| 6 | Teoría de juegos | `Scripts/game_theory.gd` |
| 7 | Búsqueda bayesiana | `Scripts/bayes_search.gd` |

`Scripts/main.gd` es el mediador entre ellos. La interfaz usa `Assets/ui/theme.tres`.

## Pruebas
```
godot --headless --path . -s tests/test_obstacle_models.gd
godot --headless --path . -s tests/test_bayes_search.gd
```

## Cambios de diseño por la interfaz
- La pata derecha de la patrulla del Bot pasó de x = 1080 a x = 760 para no cruzar el panel derecho.
- Los muros se dibujan solo entre y = 88 y y = 600; el bloqueo lógico no cambió.
