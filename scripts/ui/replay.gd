class_name Replay
extends RefCounted
## Replay di fine partita. Dal registro dei movimenti (state.replay) ricava per ogni nave e ordigno
## le posizioni a fine turno e le collega con curve morbide (Catmull-Rom): tutti si muovono insieme,
## turno dopo turno, senza le pause fra i segmenti dei giocatori.

static func build(state: Dictionary) -> Dictionary:
	var tracks := {}
	var info := {}
	for s in state.ships:
		if s.get("dummy", false): continue
		info[s.id] = {"owner": s.owner, "type": s.type, "kind": "ship"}
	var ord: Dictionary = state.get("replay_ord", {})
	for frame in state.get("replay", []):
		var t := float(frame.t)
		for m in frame.m:
			var id: String = m[0]
			if not info.has(id):
				if ord.has(id): info[id] = {"owner": ord[id][1], "type": "", "kind": ord[id][0]}
				else: continue
			if not tracks.has(id):
				tracks[id] = {"times": [t - 1.0], "pts": [Board.world(Vector2i(int(m[1]), int(m[2])))], "burns": [Vector2i.ZERO]}
			var tr: Dictionary = tracks[id]
			var to := Board.world(Vector2i(int(m[3]), int(m[4])))
			var burn := Vector2i(int(m[5]), int(m[6]))
			if is_equal_approx(float(tr.times[-1]), t):
				tr.pts[-1] = to; tr.burns[-1] = burn
			else:
				# turni senza movimento (a terra, in attesa): la nave resta ferma
				var last_t: float = tr.times[-1]
				while t - last_t > 1.0:
					last_t += 1.0
					tr.times.append(last_t); tr.pts.append(tr.pts[-1]); tr.burns.append(Vector2i.ZERO)
				tr.times.append(t); tr.pts.append(to); tr.burns.append(burn)
	var tmin := INF
	var tmax := 0.0
	for id in tracks:
		tmin = minf(tmin, float(tracks[id].times[0]))
		tmax = maxf(tmax, float(tracks[id].times[-1]))
	if tmin == INF: tmin = 0.0
	tmax = maxf(tmax, float(state.turn))
	# navi mai mosse (rimaste a terra): ferme dall'inizio alla fine
	for s in state.ships:
		if tracks.has(s.id) or s.get("dummy", false) or s.destroyed: continue
		tracks[s.id] = {"times": [tmin], "pts": [Board.world(s.pos)], "burns": [Vector2i.ZERO]}
	var lost := {}
	for s in state.ships:
		if s.destroyed and tracks.has(s.id): lost[s.id] = float(s.get("lost_turn", tracks[s.id].times[-1])) + 0.6
	for id in tracks:
		if info.has(id) and info[id].kind != "ship":
			lost[id] = float(tracks[id].times[-1]) + 0.25
	return {"tracks": tracks, "info": info, "lost": lost, "tmin": tmin, "tmax": tmax}

## Posizione di un tracciato al tempo u (in turni); null se non è ancora (o non è più) in gioco.
static func pos_at(tr: Dictionary, u: float):
	var times: Array = tr.times
	var pts: Array = tr.pts
	if u < float(times[0]): return null
	var n := times.size()
	if n == 1 or u >= float(times[-1]): return pts[-1]
	var i := 0
	while i < n - 2 and u >= float(times[i + 1]): i += 1
	var t0: float = times[i]; var t1: float = times[i + 1]
	var s := clampf((u - t0) / maxf(0.001, t1 - t0), 0.0, 1.0)
	var p0: Vector2 = pts[maxi(i - 1, 0)]
	var p1: Vector2 = pts[i]
	var p2: Vector2 = pts[i + 1]
	var p3: Vector2 = pts[mini(i + 2, n - 1)]
	# Catmull-Rom con tensione ridotta: curva morbida che passa per le posizioni di fine turno
	var s2 := s * s; var s3 := s2 * s
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * s + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * s2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * s3)

## Spinta del movimento in corso al tempo u (per lo sbuffo dei motori).
static func burn_at(tr: Dictionary, u: float) -> Vector2i:
	var times: Array = tr.times
	for i in range(1, times.size()):
		if u < float(times[i]):
			return tr.burns[i] if u >= float(times[i - 1]) else Vector2i.ZERO
	return Vector2i.ZERO
