extends SceneTree
## Prova del gioco online con il finto Firebase (tests/firebase_mock.py).
## Due istanze: TP_ROLE=host crea la stanza e scrive il codice in TP_CODE_FILE, TP_ROLE=guest entra.
## L'IA gioca per tutti (anche per i posti umani). Ogni istanza stampa le impronte dello stato per ogni
## voce del registro: devono coincidere. Con TP_DROP=1 l'ospite esce a metà e rientra con il codice.
## TP_SCENARIO sceglie lo scenario (predefinito: nova, con un posto IA giocato dall'host).

func _init() -> void:
	var role := OS.get_environment("TP_ROLE")
	var code_file := OS.get_environment("TP_CODE_FILE")
	var scen := OS.get_environment("TP_SCENARIO")
	if scen == "": scen = "nova"
	var target := int(OS.get_environment("TP_ACTS")) if OS.get_environment("TP_ACTS") != "" else 30
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 10: await process_frame
	scene.autoplay = true
	scene.anim_speed = 60.0
	if role == "host":
		scene.menu_scenario = scen
		if OS.get_environment("TP_MAP") != "": scene.menu_options.map = OS.get_environment("TP_MAP")
		scene.menu_seats = [{"name": "", "type": "human"}, {"name": "", "type": "human"}, {"name": "", "type": "ai"},
			{"name": "", "type": "none"}, {"name": "", "type": "none"}, {"name": "", "type": "none"}]
		var err: String = await scene._online_create("Ospite di casa")
		if err != "":
			print("ERRORE ", err); quit(1); return
		FileAccess.open(code_file, FileAccess.WRITE).store_string(scene.lobby.code)
		# aspetta l'amico
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 60000:
			var room: Dictionary = await scene.net.room(scene.lobby.code)
			if Net._as_dict(room.get("seats", {})).has("1"): break
			await create_timer(0.3).timeout
		await scene._online_start()
	else:
		var code := ""
		var t1 := Time.get_ticks_msec()
		while code == "" and Time.get_ticks_msec() - t1 < 60000:
			if FileAccess.file_exists(code_file): code = FileAccess.get_file_as_string(code_file).strip_edges()
			await create_timer(0.2).timeout
		var err2: String = await scene._online_join(code, "Amico")
		if err2 != "":
			print("ERRORE ", err2); quit(1); return
		var t2 := Time.get_ticks_msec()
		while scene.online == null and Time.get_ticks_msec() - t2 < 60000:
			await create_timer(0.2).timeout
	if scene.online == null:
		print("ERRORE nessuna partita online"); quit(1); return
	scene.online.poll = 0.05
	scene.online.away_after = 2500
	scene.online.wait_min = 3000
	var dropped := false
	var t3 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t3 < 240000:
		await create_timer(0.2).timeout
		if scene.online == null: break
		scene.online.poll = 0.05
		scene.online.away_after = 2500
		scene.online.wait_min = 3000
		if scene.state.over or scene.online.n >= target: break
		if role == "guest" and OS.get_environment("TP_DROP") == "1" and not dropped and scene.online.n >= target / 2:
			dropped = true
			var c: String = scene.online.code
			scene._show_menu()
			await create_timer(12.0 if OS.get_environment("TP_DROP_LONG") == "1" else 1.0).timeout
			var err3: String = await scene._online_join(c, "Amico")
			print("RIENTRO ", c, " ", err3)
	await create_timer(2.0).timeout
	var o = scene.online
	var hist: Dictionary = o.history if o != null else {}
	var keys := hist.keys()
	keys.sort()
	var out := []
	for k in keys: out.append("%d:%d" % [k, hist[k]])
	print("RUOLO ", role, " pid ", o.pid if o != null else "", " voci ", keys.size(), " turno ", scene.state.turn, " fase ", scene.state.phase)
	print("IMPRONTE ", " ".join(out))
	quit()
