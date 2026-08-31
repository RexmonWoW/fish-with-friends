extends Node

## Headless check for GDD Line Tangling's bobber drift: a landed bobber
## should wander slowly instead of sitting dead still, AND that wander must
## be deterministic (same landing spot + elapsed-since-landing -> same
## offset) since tangle detection reads Bobber's own global_position
## directly, not a broadcast one -- every peer computes its own copy, so a
## host/client mismatch would mean what one machine sees crossing isn't
## what the host's own tangle check actually used. Also checks the
## landing-pop fix: drift must be ~zero right at landing and ramp up, not
## already at some arbitrary offset the instant it lands.

func _ready() -> void:
	print("--- Bobber drift test ---")

	var bobber_a := Bobber.new()
	var bobber_b := Bobber.new()
	add_child(bobber_a)
	add_child(bobber_b)
	await get_tree().process_frame

	# Same landing spot -> same seed (derived from it) and same landing
	# time, same as two peers' independent Bobber instances both reacting
	# to the same broadcast cast_landed endpoint.
	var landing_spot := Vector3(5.0, -0.5, 8.0)
	var landed_at := Time.get_ticks_msec() / 1000.0
	for bobber in [bobber_a, bobber_b]:
		bobber._anchor_position = landing_spot
		bobber._drift_seed = float(hash(landing_spot) % 100000) / 100000.0 * TAU
		bobber._landed_at = landed_at

	var drift_at_landing: Vector3 = bobber_a._compute_drift()
	if drift_at_landing.length() > 0.05:
		print("FAIL: drift should be ~zero the instant it lands (got %.3f) -- this is the reported landing pop" %
			drift_at_landing.length())
		get_tree().quit(1)
		return
	print("Drift is ~zero right at landing (%.3f) -- no pop." % drift_at_landing.length())

	var drift_a1: Vector3 = bobber_a._compute_drift()
	var drift_b1: Vector3 = bobber_b._compute_drift()
	if not drift_a1.is_equal_approx(drift_b1):
		print("FAIL: two instances with the same landing spot computed different drift (%s vs %s) -- would desync tangle detection across peers" %
			[drift_a1, drift_b1])
		get_tree().quit(1)
		return
	print("Two independent instances agree on drift for the same landing spot: ", drift_a1)

	# Wait past the full ramp-in window, then check it's grown and stays
	# within the small radius (ramped up to its full magnitude by now).
	await get_tree().create_timer(Bobber.DRIFT_RAMP_SECONDS + 0.5).timeout
	var drift_a2: Vector3 = bobber_a._compute_drift()
	if drift_a2.is_equal_approx(drift_a1):
		print("FAIL: drift didn't change at all after landing -- bobber would just sit dead still")
		get_tree().quit(1)
		return
	if drift_a2.length() > Bobber.DRIFT_RADIUS * 1.5:
		print("FAIL: drift magnitude (%.2f) is way outside DRIFT_RADIUS (%.2f) -- not a SMALL radius" %
			[drift_a2.length(), Bobber.DRIFT_RADIUS])
		get_tree().quit(1)
		return
	print("Drift ramped up and stays within a small radius: ", drift_a1, " -> ", drift_a2)

	print("--- Bobber drift test PASSED ---")
	get_tree().quit()
