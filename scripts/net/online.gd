class_name Online
extends Node
## Partita online di Triplanetary.
##
## Il registro della stanza (acts/0, acts/1, …) è una sequenza di istantanee dello stato, compresse.
## In ogni momento un solo dispositivo "ha la mano": quello che decide per il giocatore di turno
## (la persona davanti allo schermo per il suo colore, chi ha creato la stanza per i colori IA).
## Quando la mano passa a un altro dispositivo, chi la lascia pubblica lo stato aggiornato; gli altri
## aspettano leggendo la voce successiva del registro. Così si sincronizzano anche le scelte più varie
## (negozio, schieramento, ordigni, contrattacchi…) senza tradurre ogni comando in una mossa.
## Se un giocatore tace per un minuto, chi ha creato la stanza lo fa giocare all'IA finché non rientra.

signal status_changed(text: String)
## Mentre si aspetta il proprio input, qualcun altro (l'IA dell'host) ha già giocato al nostro posto.
signal forced(packet: Dictionary)

var net: Net
var code := ""
var seat := -1                 # posto di questo dispositivo nella stanza (indice del menu)
var pid := ""                  # giocatore controllato da questo dispositivo
var role := "guest"            # "host" o "guest"
var n := 0                     # prossima voce del registro da leggere o scrivere
var last_json := ""            # stato all'ultima sincronizzazione (per non ripubblicare doppioni)
var moves_out: Array = []      # spostamenti animati da allegare alla prossima istantanea
var away := {}                 # pid → true: giocatori assenti che per ora gioca l'IA dell'host
var alive := true
var watching := false
var _watch_n := -1
var _heartbeat_on := false
var away_after := 45000       # ms senza segnale di presenza prima di far giocare l'IA…
var wait_min := 60000         # …e comunque non prima di questo tempo d'attesa
var poll := 1.2                # secondi fra una lettura e l'altra del registro
var history := {}              # n → impronta dello stato (per le prove automatiche)

func setup(p_net: Net, p_code: String, p_seat: int, p_role: String) -> void:
	net = p_net
	code = p_code
	seat = p_seat
	role = p_role

func _exit_tree() -> void:
	alive = false

## Vero se questo dispositivo decide per il giocatore pid.
func controls(state: Dictionary, who: String) -> bool:
	if who == pid: return true
	if role != "host": return false
	var p := Rules.player(state, who)
	return p.get("type", "human") != "human" or away.has(who)

static func seat_of(state: Dictionary, who: String) -> int:
	return int(Rules.player(state, who).get("seat", -1))

static func pid_of_seat(state: Dictionary, s: int) -> String:
	for p in state.players:
		if int(p.get("seat", -1)) == s: return p.id
	return ""

# ---------------------------------------------------------------- impacchettamento

static func pack(state: Dictionary, moves: Array) -> String:
	var js := Persistence.to_json(state)
	var body := JSON.stringify({"st": js, "mv": Persistence._encode(moves)})
	return Marshalls.raw_to_base64(body.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))

static func unpack(z: String) -> Dictionary:
	var raw := Marshalls.base64_to_raw(z)
	if raw.is_empty(): return {}
	var txt := raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	var d = JSON.parse_string(txt)
	if not d is Dictionary: return {}
	var st := Persistence.from_json(str(d.get("st", "")))
	if st.is_empty(): return {}
	var mv = Persistence._decode(d.get("mv", []))
	if mv is Array:
		for batch in mv:
			for m in batch: Persistence._fix_numbers(m)
	return {"state": st, "moves": mv if mv is Array else [], "n": -1}

# ---------------------------------------------------------------- pubblicazione e attesa

## Pubblica lo stato se è cambiato dall'ultima sincronizzazione.
## Restituisce {} se tutto bene, oppure il pacchetto che un altro dispositivo ha scritto prima di noi.
func publish(state: Dictionary) -> Dictionary:
	var js := Persistence.to_json(state)
	if js == last_json: return {}
	var a := {"s": seat, "k": "st", "z": pack(state, moves_out)}
	var tries := 0
	while alive:
		if await net.post_act(code, n, a):
			history[n] = Persistence.to_json(Persistence.from_json(js)).hash()
			n += 1
			last_json = js
			moves_out = []
			status_changed.emit("")
			return {}
		var ex := await net.get_act(code, n)
		if not ex.is_empty() and not ex.has("_err"):
			var pk := _accept(ex)
			if not pk.is_empty():
				moves_out = []
				return pk
		tries += 1
		status_changed.emit("Rete non raggiungibile, riprovo… (%s)" % net.last_error)
		await get_tree().create_timer(minf(2.0 + tries, 8.0)).timeout
	return {}

## Decodifica una voce del registro e avanza il contatore.
func _accept(a: Dictionary) -> Dictionary:
	var pk := unpack(str(a.get("z", "")))
	if pk.is_empty():
		push_warning("Online: voce %d illeggibile" % n)
		n += 1
		return {}
	pk.n = n
	n += 1
	last_json = Persistence.to_json(pk.state)
	history[pk.n] = last_json.hash()
	return pk

## Pubblica (se serve) e aspetta la prossima istantanea scritta da un altro dispositivo.
## Restituisce il pacchetto {state, moves}, oppure {"takeover": true} se l'host ha deciso di far
## giocare l'IA al posto di un giocatore assente, oppure {} se la sessione è chiusa.
func handoff(state: Dictionary, who: String) -> Dictionary:
	var pk := await publish(state)
	if not pk.is_empty(): return pk
	var t0 := Time.get_ticks_msec()
	var seen_t := t0
	var last_seen = null
	var polls := 0
	var human: bool = Rules.player(state, who).get("type", "human") == "human"
	var s := seat_of(state, who)
	while alive:
		var a := await net.get_act(code, n)
		if not alive: break
		if not a.is_empty() and not a.has("_err"):
			var got := _accept(a)
			if not got.is_empty():
				status_changed.emit("")
				return got
			continue
		var now := Time.get_ticks_msec()
		if role == "host" and human and s >= 0 and polls % 4 == 0:
			var st := await net.seat(code, s)
			if not alive: break
			if not st.is_empty():
				var seen = st.get("seen", null)
				if seen != last_seen:
					last_seen = seen
					seen_t = now
				if st.get("away", false) or (now - seen_t > away_after and now - t0 > wait_min):
					await net.set_away(code, s, true)
					away[who] = true
					status_changed.emit("%s non risponde: per ora gioca l'IA al suo posto." % Rules.player(state, who).name)
					return {"takeover": true}
		if now - t0 > wait_min and polls % 10 == 0:
			status_changed.emit("%s ci sta pensando da più di un minuto…" % Rules.player(state, who).name)
		polls += 1
		await get_tree().create_timer(poll).timeout
	return {}

## L'host gioca per un assente: controlla se nel frattempo è tornato.
func check_back(state: Dictionary, who: String) -> bool:
	var s := seat_of(state, who)
	if s < 0: return false
	var st := await net.seat(code, s)
	if not st.is_empty() and not st.get("away", false):
		away.erase(who)
		status_changed.emit("%s è tornato." % Rules.player(state, who).name)
		return true
	return false

## Mentre il giocatore locale pensa, controlla che l'host non abbia già giocato al suo posto
## (succede se la scheda del browser resta in secondo piano a lungo).
func watch() -> void:
	watching = true
	if _watch_n == n: return
	_watch_n = n
	var my_n := n
	while alive and watching and n == my_n:
		await get_tree().create_timer(3.0).timeout
		if not alive or not watching or n != my_n: break
		var a := await net.get_act(code, my_n)
		if not alive or not watching or n != my_n: break
		if not a.is_empty() and not a.has("_err"):
			var pk := _accept(a)
			if not pk.is_empty():
				watching = false
				_watch_n = -1
				forced.emit(pk)
			break
	if _watch_n == my_n: _watch_n = -1

## Tutto il registro fino all'ultima voce: per entrare o rientrare in una partita in corso.
func catch_up() -> Dictionary:
	var last := await net.last_act(code)
	if last < 0: return {}
	var a := await net.get_act(code, last)
	if a.is_empty() or a.has("_err"): return {}
	n = last
	return _accept(a)

func heartbeat_loop() -> void:
	if _heartbeat_on: return
	_heartbeat_on = true
	while alive:
		net.heartbeat(code, seat)
		await get_tree().create_timer(5.0).timeout

func finish() -> void:
	alive = false
	if role == "host":
		net.set_status(code, "over")
	net.remember_room("")
