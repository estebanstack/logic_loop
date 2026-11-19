extends SceneTree

# ------------------------------------------------------------------------------
# PRUEBA MATEMÁTICA: HMM DE LA BARRERA + JUEGO DE INSPECCIÓN (STEALTH_COVER)
# Ejecutar: godot --headless --path . -s tests/test_obstacle_models.gd
# Código de salida 0 = todo correcto; 1 = alguna aserción falló.
# ------------------------------------------------------------------------------

const HmmScript: Script = preload("res://Scripts/hidden_markov_model.gd")
const GameScript: Script = preload("res://Scripts/game_theory.gd")
const QueueScript: Script = preload("res://Scripts/queue_simulator.gd")

const EPS: float = 1e-4
var failures: int = 0

func check(cond: bool, label: String) -> void:
	if cond:
		print("  OK    ", label)
	else:
		print("  FALLA ", label)
		failures += 1

func near(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps

# Modelo de la barrera, idéntico al configurado en Main
func make_barrier_hmm() -> Node:
	var hmm: Node = HmmScript.new()
	hmm.configure(
		["FRÁGIL", "BLINDADO"],
		["ECO HUECO", "ECO AMBIGUO", "ECO SÓLIDO"],
		[[1.0, 0.0], [0.0, 1.0]],
		[[0.70, 0.25, 0.05], [0.05, 0.25, 0.70]],
		[0.5, 0.5]
	)
	return hmm

func _init() -> void:
	seed(20261118)   # semilla fija: el Monte Carlo es reproducible

	print("== 1. Filas de B y π0 suman 1 ==")
	var hmm: Node = make_barrier_hmm()
	for i in range(2):
		var row_sum: float = 0.0
		for v in hmm.emission_matrix_B[i]:
			row_sum += float(v)
		check(near(row_sum, 1.0), "fila %d de B suma 1" % i)
	var pi_sum: float = 0.0
	for v in hmm.initial_pi:
		pi_sum += float(v)
	check(near(pi_sum, 1.0), "π0 suma 1")

	print("== 2. Creencia tras un eco ==")
	var hmm_hueco: Node = make_barrier_hmm()
	hmm_hueco.current_belief = hmm_hueco._step_forward_belief(0)   # ECO HUECO
	check(near(hmm_hueco.current_belief[0], 0.9333, 1e-3), "HUECO -> P(Frágil) = 0.9333 (obtenido %.4f)" % hmm_hueco.current_belief[0])
	var hmm_solido: Node = make_barrier_hmm()
	hmm_solido.current_belief = hmm_solido._step_forward_belief(2)  # ECO SÓLIDO
	check(near(hmm_solido.current_belief[0], 0.0667, 1e-3), "SÓLIDO -> P(Frágil) = 0.0667 (obtenido %.4f)" % hmm_solido.current_belief[0])

	print("== 3. Equilibrio de Nash de STEALTH_COVER ==")
	var game: Node = GameScript.new()
	game.load_preset(GameScript.PresetType.STEALTH_COVER)
	check(game.calculate_pure_nash_equilibria().is_empty(), "no hay Nash puro")
	var mixed: Dictionary = game.calculate_mixed_nash_equilibrium()
	check(bool(mixed.has_mixed_equilibrium), "existe Nash mixto")
	check(near(mixed.p_star, 7.0 / 12.0), "p* = 7/12 = 0.5833 (obtenido %.4f)" % mixed.p_star)
	check(near(mixed.q_star, 0.5), "q* = 0.5 (obtenido %.4f)" % mixed.q_star)
	check(near(mixed.expected_u1, 0.0), "E[u1] = 0 (obtenido %.4f)" % mixed.expected_u1)
	check(near(mixed.expected_u2, 1.5), "E[u2] = 1.5 (obtenido %.4f)" % mixed.expected_u2)

	print("== 4. Monte Carlo: 2000 muros, 3 pulsos, θ = 0.65 ==")
	var walls: int = 2000
	var correct: int = 0
	var rams_on_armored: int = 0
	var armored: int = 0
	var detours_on_fragile: int = 0
	var fragile: int = 0
	for n in range(walls):
		var sim: Node = make_barrier_hmm()
		sim.resample_true_state()
		var diag: Dictionary = sim.diagnose_obstacle(3, 0.65)
		sim.free()
		var is_fragile: bool = int(diag.true_state) == 0
		var rams: bool = diag.decision == "FRACTURAR"
		if is_fragile:
			fragile += 1
			if not rams:
				detours_on_fragile += 1
		else:
			armored += 1
			if rams:
				rams_on_armored += 1
		if rams == is_fragile:
			correct += 1
	var accuracy: float = float(correct) / float(walls)
	var ram_armored_rate: float = float(rams_on_armored) / float(maxi(armored, 1))
	var detour_fragile_rate: float = float(detours_on_fragile) / float(maxi(fragile, 1))
	print("  Muros: %d frágiles, %d blindados" % [fragile, armored])
	print("  Precisión de la decisión: %.1f %%" % (accuracy * 100.0))
	print("  Embiste un muro BLINDADO: %.1f %% (%d de %d)" % [ram_armored_rate * 100.0, rams_on_armored, armored])
	print("  Rodea un muro FRÁGIL:     %.1f %% (%d de %d)" % [detour_fragile_rate * 100.0, detours_on_fragile, fragile])
	check(accuracy > 0.85, "precisión > 85 %")
	check(ram_armored_rate < 0.15, "embestidas a blindados < 15 %")

	print("== 5. Viterbi coherente con Forward (defaults de telemetría, 1 observación) ==")
	for k in range(3):
		var tel: Node = HmmScript.new()
		var path: Array[int] = tel.viterbi_decode([k])
		var belief: Array[float] = tel._step_forward_belief(k)
		var best_fwd: int = 0
		for j in range(belief.size()):
			if belief[j] > belief[best_fwd]:
				best_fwd = j
		check(path[0] == best_fwd, "obs %d: argmax Viterbi (%d) = argmax Forward (%d)" % [k, path[0], best_fwd])
		tel.free()

	print("== 6. Muestreador exponencial: media 1.8 s ==")
	var queue: Control = QueueScript.new()
	var total: float = 0.0
	var n_samples: int = 20000
	for i in range(n_samples):
		total += queue._exp_sample(1.0 / 1.8)
	var sample_mean: float = total / float(n_samples)
	check(absf(sample_mean - 1.8) <= 1.8 * 0.05, "media muestral %.3f dentro del 5 %% de 1.8" % sample_mean)
	queue.free()

	hmm.free()
	hmm_hueco.free()
	hmm_solido.free()
	game.free()
	if failures > 0:
		print("RESULTADO: %d aserción(es) fallaron" % failures)
		quit(1)
	else:
		print("RESULTADO: todas las aserciones pasaron")
		quit(0)
