extends Node

## Headless check for Livewell's pull-based full-state sync (Livewell.
## _apply_full_sync). Added after a real 2-machine playtest showed a round-2
## desync -- the host saw every restored fish, a client only saw some --
## traced to the old restore path pushing _apply_add RPCs at the exact
## moment a client's own fresh Livewell (reloaded for the new round) might
## not exist yet, the same RPC-target-not-ready race already hit once for
## player spawn registration. A single headless process can't reproduce the
## network timing itself (there's only ever one peer, always the server),
## so this instead calls the sync RPC method's body directly to protect its
## actual contract: it fills empty slots from another Livewell's state, and
## never clobbers a slot that's already occupied locally.

func _ready() -> void:
	print("--- Livewell full-sync test ---")

	var host_livewell := preload("res://entities/livewell/livewell.tscn").instantiate() as Livewell
	var peer_livewell := preload("res://entities/livewell/livewell.tscn").instantiate() as Livewell
	add_child(host_livewell)
	add_child(peer_livewell)
	await get_tree().process_frame

	var fish_a := _make_fish(77)
	var fish_b := _make_fish(120)
	var big := _make_fish(500)
	host_livewell.slots[0] = fish_a
	host_livewell.slots[2] = fish_b
	host_livewell.big_fish_slot = big

	# The host ALSO has something in slot 3 -- but the peer already has its
	# own (different) fish there locally (e.g. it caught this one itself
	# after the last sync). That local copy must survive untouched, not get
	# clobbered by the host's version of slot 3.
	host_livewell.slots[3] = _make_fish(111)
	var already_local := _make_fish(999)
	peer_livewell.slots[3] = already_local

	peer_livewell._apply_full_sync(host_livewell.slots, host_livewell.big_fish_slot)

	if peer_livewell.slots[0] != fish_a:
		print("FAIL: empty slot 0 wasn't filled from the host's state")
		get_tree().quit(1)
		return
	if peer_livewell.slots[2] != fish_b:
		print("FAIL: empty slot 2 wasn't filled from the host's state")
		get_tree().quit(1)
		return
	if peer_livewell.slots[3] != already_local:
		print("FAIL: sync clobbered a slot the peer already had locally")
		get_tree().quit(1)
		return
	if peer_livewell.big_fish_slot != big:
		print("FAIL: reserved big-fish slot wasn't synced")
		get_tree().quit(1)
		return
	print("Empty slots filled, occupied slot preserved, big-fish slot synced.")

	var slot0_marker := peer_livewell.fish_display.get_child(0)
	if slot0_marker.get_child_count() == 0:
		print("FAIL: synced fish has no visual under its slot marker")
		get_tree().quit(1)
		return
	print("Synced fish got a visual too.")

	print("--- Livewell full-sync test PASSED ---")
	get_tree().quit()


func _make_fish(value: int) -> CaughtFish:
	var fish := CaughtFish.new()
	fish.species = load("res://data/fish/species/catfish.tres")
	fish.size = 12.0
	fish.final_value = value
	return fish
