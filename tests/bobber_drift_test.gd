extends Node

## Headless check for GDD Line Tangling's bobber drift: a landed bobber
## should wander slowly instead of sitting dead still, AND that wander must
## be deterministic (same landing spot + elapsed time -> same offset) since
## tangle detection reads LureAnimator's own global_position directly, not
## a broadcast one -- every peer computes its own copy, so a host/client
## mismatch would mean what one machine sees crossing isn't what the
## host's own tangle check actually used.

func _ready() -> void:
	print("--- Bobber drift test ---")

	var lure_a := LureAnimator.new()
	var lure_b := LureAnimator.new()
	add_child(lure_a)
	add_child(lure_b)
	await get_tree().process_frame

	# Same landing spot -> same seed (derived from it), same as two peers'
	# independent LureAnimator instances both reacting to the same
	# broadcast cast_landed endpoint.
	var landing_spot := Vector3(5.0, -0.5, 8.0)
	lure_a._anchor_position = landing_spot
	lure_a._drift_seed = float(hash(landing_spot) % 100000) / 100000.0 * TAU
	lure_b._anchor_position = landing_spot
	lure_b._drift_seed = float(hash(landing_spot) % 100000) / 100000.0 * TAU

	var drift_a1: Vector3 = lure_a._compute_drift()
	var drift_b1: Vector3 = lure_b._compute_drift()
	if not drift_a1.is_equal_approx(drift_b1):
		print("FAIL: two instances with the same landing spot computed different drift (%s vs %s) -- would desync tangle detection across peers" %
			[drift_a1, drift_b1])
		get_tree().quit(1)
		return
	print("Two independent instances agree on drift for the same landing spot: ", drift_a1)

	if drift_a1.length() > LureAnimator.DRIFT_RADIUS * 1.5:
		print("FAIL: drift magnitude (%.2f) is way outside DRIFT_RADIUS (%.2f) -- not a SMALL radius" %
			[drift_a1.length(), LureAnimator.DRIFT_RADIUS])
		get_tree().quit(1)
		return
	print("Drift stays within a small radius of the anchor (%.2f <= ~%.2f)." % [drift_a1.length(), LureAnimator.DRIFT_RADIUS])

	# Confirm it actually moves over time (not just a fixed nonzero offset).
	await get_tree().create_timer(1.0).timeout
	var drift_a2: Vector3 = lure_a._compute_drift()
	if drift_a2.is_equal_approx(drift_a1):
		print("FAIL: drift didn't change at all after 1 real second -- bobber would just sit dead still")
		get_tree().quit(1)
		return
	print("Drift changes over time: ", drift_a1, " -> ", drift_a2)

	print("--- Bobber drift test PASSED ---")
	get_tree().quit()
