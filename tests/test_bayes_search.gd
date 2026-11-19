extends SceneTree

# ------------------------------------------------------------------------------
# PRUEBA MATEMÁTICA: BÚSQUEDA BAYESIANA (filtro de Bayes en la cuadrícula de Spark)
# Ejecutar: godot --headless --path . -s tests/test_bayes_search.gd
# Código de salida 0 = todo correcto; 1 = alguna aserción falló.
# ------------------------------------------------------------------------------

const BayesScript: Script = preload("res://Scripts/bayes_search.gd")

const EPS: float = 1e-6
const RADIUS: float = 250.0            # radio de visión del Bot (3.9 casillas)
const MAX_STEPS: int = 20              # 10 s de búsqueda a 0.5 s por paso
const TRIALS: int = 500
const HIDDEN_STEPS: int = 6            # 3 s de camuflaje = 6 pasos de 0.5 s
var failures: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("  OK    ", label)
	else:
		print("  FALLA ", label)
		failures += 1

# Muro simulado: columna x = 470 bloqueada salvo el hueco y = 536 (como en Main)
func stub_blocked(pos: Vector2) -> bool:
	return absf(pos.x - 470.0) < 8.0 and absf(pos.y - 536.0) > 8.0

func make_bayes() -> Node2D:
	var b: Node2D = BayesScript.new()
	b.setup(stub_blocked)
	return b

func total_mass(b: Node2D) -> float:
	var s: float = 0.0
	for v in b.belief:
		s += v
	return s

func mass_within(b: Node2D, center: Vector2, inside: bool) -> float:
	var s: float = 0.0
	for c in range(b.belief.size()):
		if (b.cell_pos(c).distance_to(center) <= RADIUS) == inside:
			s += b.belief[c]
	return s

func _init() -> void:
	seed(20261118)   # semilla fija: el Monte Carlo es reproducible

	print("== 1. La masa total suma 1 tras start y tras 20 predict ==")
	var b: Node2D = make_bayes()
	b.start(Vector2(406, 344))
	check(absf(total_mass(b) - 1.0) <= EPS, "Σ b = 1 tras start (%.9f)" % total_mass(b))
	check(absf(b.belief[b.nearest_index(Vector2(406, 344))] - 0.6) <= EPS, "centro = 0.6 tras start")
	for k in range(20):
		b.predict()
	check(absf(total_mass(b) - 1.0) <= EPS, "Σ b = 1 tras 20 predict (%.9f)" % total_mass(b))

	print("== 2. Las casillas bloqueadas valen 0 ==")
	var blocked_max: float = 0.0
	var blocked_cells: int = 0
	for c in range(b.belief.size()):
		if stub_blocked(b.cell_pos(c)):
			blocked_cells += 1
			blocked_max = maxf(blocked_max, b.belief[c])
	check(blocked_cells == 9, "hay 9 casillas bloqueadas en la columna 470 (obtenidas %d)" % blocked_cells)
	check(blocked_max == 0.0, "masa máxima en casillas bloqueadas = %.9f" % blocked_max)

	print("== 3. Observación negativa: dentro del radio la masa cae por (1 - P_d) ==")
	var bot_pos: Vector2 = Vector2(406, 344)
	var in_before: float = mass_within(b, bot_pos, true)
	var out_before: float = mass_within(b, bot_pos, false)
	b.update(bot_pos, RADIUS, false)
	var in_after: float = mass_within(b, bot_pos, true)
	var out_after: float = mass_within(b, bot_pos, false)
	var expected_ratio: float = (1.0 - BayesScript.P_DETECT) * in_before / out_before
	check(absf(in_after / out_after - expected_ratio) <= 1e-6,
		"cociente dentro/fuera = (1-P_d)·antes = %.6f (obtenido %.6f)" % [expected_ratio, in_after / out_after])
	check(absf(total_mass(b) - 1.0) <= EPS, "Σ b = 1 tras normalizar")
	check(b.map_cell().distance_to(bot_pos) > RADIUS, "el MAP salió del radio (en %s)" % str(b.map_cell()))
	b.free()

	print("== 4. Monte Carlo: %d ensayos, radio %.0f px, tope %d pasos ==" % [TRIALS, RADIUS, MAX_STEPS])
	# Escenario A: Spark siempre es visible si entra en el radio.
	# Escenario B: Spark estuvo camuflado los primeros HIDDEN_STEPS pasos (ventana de cobertura de 3 s):
	# el Bot no lo ve aunque esté en el radio (el filtro, en cambio, sigue suponiendo P_d = 0.9).
	var sim: Node2D = make_bayes()
	var ok_a: bool = run_scenario(sim, "A. Spark visible", 0)
	var ok_b: bool = run_scenario(sim, "B. Spark camuflado %d pasos (%.0f s)" % [HIDDEN_STEPS, HIDDEN_STEPS * BayesScript.TICK], HIDDEN_STEPS)
	sim.free()
	check(ok_a, "escenario A: Bayes no es peor que la línea base (halla al menos tantas veces y en pasos medios <=)")
	check(ok_b, "escenario B: Bayes no es peor que la línea base (halla al menos tantas veces y en pasos medios <=)")

	if failures > 0:
		print("RESULTADO: %d aserción(es) fallaron" % failures)
		quit(1)
	else:
		print("RESULTADO: todas las aserciones pasaron")
		quit(0)

# ------------------------------------------------------------------------------
# Monte Carlo
# ------------------------------------------------------------------------------
# Ejecuta TRIALS ensayos con ambos buscadores sobre las mismas trayectorias.
# Devuelve true si Bayes no es peor (halla al menos tantas veces y pasos medios <=).
func run_scenario(sim: Node2D, title: String, hidden_steps: int) -> bool:
	var bayes_found: int = 0
	var base_found: int = 0
	var bayes_steps_sum: int = 0     # pasos totales; los fallos cuentan MAX_STEPS
	var base_steps_sum: int = 0
	for t in range(TRIALS):
		var trial: Dictionary = make_trial(sim)
		var rb: int = run_bayes(sim, trial, hidden_steps)
		var rl: int = run_last_known(trial, hidden_steps)
		bayes_found += 1 if rb > 0 else 0
		base_found += 1 if rl > 0 else 0
		bayes_steps_sum += rb if rb > 0 else MAX_STEPS
		base_steps_sum += rl if rl > 0 else MAX_STEPS
	var bayes_mean: float = float(bayes_steps_sum) / float(TRIALS)
	var base_mean: float = float(base_steps_sum) / float(TRIALS)
	print("  [%s]" % title)
	print("    Última posición conocida: lo halla en %5.1f %% | pasos medios (fallo = %d): %.2f" % [100.0 * base_found / TRIALS, MAX_STEPS, base_mean])
	print("    Búsqueda bayesiana (MAP): lo halla en %5.1f %% | pasos medios (fallo = %d): %.2f" % [100.0 * bayes_found / TRIALS, MAX_STEPS, bayes_mean])
	return bayes_found >= base_found and bayes_mean <= base_mean

# Un ensayo: Bot en una casilla libre S; Spark acaba de salir de su visión en T0
# (a entre 250 y 346 px). Spark camina al azar con el mismo modelo de movimiento
# del filtro; la trayectoria se guarda para que ambos buscadores enfrenten lo mismo.
func make_trial(sim: Node2D) -> Dictionary:
	var free_cells: Array[int] = []
	for c in range(sim.belief.size()):
		if not stub_blocked(sim.cell_pos(c)):
			free_cells.append(c)
	var bot_start: Vector2 = Vector2.ZERO
	var spark_cell: int = 0
	while true:
		bot_start = sim.cell_pos(free_cells[randi() % free_cells.size()])
		spark_cell = free_cells[randi() % free_cells.size()]
		var d: float = bot_start.distance_to(sim.cell_pos(spark_cell))
		if d > RADIUS and d <= RADIUS + 96.0:
			break
	var path: Array[Vector2] = [sim.cell_pos(spark_cell)]
	for k in range(MAX_STEPS):
		if randf() >= BayesScript.STAY_PROB:
			var neighbours: Array[int] = sim.free_neighbours(spark_cell)
			if not neighbours.is_empty():
				spark_cell = neighbours[randi() % neighbours.size()]
		path.append(sim.cell_pos(spark_cell))
	return {"bot": bot_start, "path": path}

func move_toward_goal(pos: Vector2, goal: Vector2) -> Vector2:
	return pos.move_toward(goal, BayesScript.CELL)   # 1 casilla por paso

# Devuelve el paso en que lo encuentra, o 0 si falla (se rinde o agota el tiempo)
func run_bayes(sim: Node2D, trial: Dictionary, hidden_steps: int) -> int:
	var path: Array[Vector2] = trial.path
	var bot: Vector2 = trial.bot
	sim.start(path[0])
	for step in range(1, MAX_STEPS + 1):
		bot = move_toward_goal(bot, sim.map_cell())
		if step > hidden_steps and bot.distance_to(path[step]) <= RADIUS:
			return step
		sim.predict()
		sim.update(bot, RADIUS, false)
		if sim.max_prob() < BayesScript.GIVE_UP_PROB:
			return 0
	return 0

# Línea base: ir a la última posición conocida y rendirse al llegar
func run_last_known(trial: Dictionary, hidden_steps: int) -> int:
	var path: Array[Vector2] = trial.path
	var bot: Vector2 = trial.bot
	for step in range(1, MAX_STEPS + 1):
		bot = move_toward_goal(bot, path[0])
		if step > hidden_steps and bot.distance_to(path[step]) <= RADIUS:
			return step
		if bot.distance_to(path[0]) < 1.0:
			return 0
	return 0
