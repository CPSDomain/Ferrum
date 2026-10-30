class_name NetLink
extends Node
## Multiplayer transport: host-relayed deterministic lockstep over ENet.
##
## * The host runs the simulation in real time. Every tick it gathers its own commands
##   plus whatever clients have sent since the last tick, fixes their order, broadcasts
##   that bundle, then steps.
## * Clients never step on their own clock. They step tick N only when bundle N arrives,
##   so every peer applies exactly the same commands in exactly the same order.
## * Joining: the host sends a compressed snapshot (world settings + full sim state) and
##   schedules a "join" command for the very next tick.
## * Every CHECK_EVERY ticks the host attaches its state checksum. A client that
##   disagrees asks for a fresh snapshot.
## Offline play never touches this node except through `mode == "offline"`.

signal status(msg: String)
signal dropped(msg: String)
signal upnp_done
signal connected

const CHECK_EVERY := 300
const ALLOWED := {"input": 1, "place": 1, "set_dir": 1, "remove": 1, "rotate": 1, "recipe": 1, "clock": 1,
	"shard_add": 1, "shard_rem": 1, "take_out": 1, "fill_in": 1, "fuel": 1, "crate_take": 1, "hub_take": 1,
	"hub_dep": 1, "submit_ms": 1, "research": 1, "pick_alt": 1, "elev_dep": 1, "elev_launch": 1, "craft": 1, "cancel_craft": 1, "chat": 1, "ping": 1}

var main
var mode := "offline"           # offline | host | client
var peer: ENetMultiplayerPeer
var remote: Array = []          # host: client commands waiting for the next tick
var bundles := {}               # client: tick -> commands
var pending_cs: Array = []      # host: [tick, checksum] riding on the next bundle
var my_cs := {}                 # client: tick -> local checksum
var host_cs := {}               # client: tick -> host checksum
var desyncs := 0
var resyncing := false
var my_name := "Engineer"
# UPnP: ask the host's router to forward the game port automatically
var upnp: UPNP
var upnp_thread: Thread
var upnp_state := "off"         # off | working | open | failed
var upnp_msg := ""
var public_ip := ""
var host_port := 0
var accepting := true           # host: false while its own world is still loading
var pending_hellos: Array = []

# ------------------------------------------------------------------ session control
func host(port: int, pname: String) -> String:
	shutdown()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 8)
	if err != OK:
		peer = null
		return "Could not open port %d. Something else may be using it." % port
	multiplayer.multiplayer_peer = peer
	mode = "host"
	my_name = pname
	host_port = port
	multiplayer.peer_disconnected.connect(_on_peer_left)
	_start_upnp(port)
	return ""

# ------------------------------------------------------------------ UPnP
## Router discovery takes a couple of seconds, so it runs on a thread; the game keeps going.
func _start_upnp(port: int) -> void:
	if upnp_thread != null:
		return
	upnp_state = "working"
	upnp_msg = "Asking your router to open UDP port %d..." % port
	public_ip = ""
	upnp_thread = Thread.new()
	upnp_thread.start(_upnp_work.bind(port))

func _upnp_work(port: int) -> void:
	var u := UPNP.new()
	var r := {"ok": false, "ip": "", "msg": "", "upnp": u, "port": port}
	var err := u.discover(2000, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null:
		r.msg = "No router answered the automatic port request (UPnP may be switched off)."
	elif not u.get_gateway().is_valid_gateway():
		r.msg = "Your router doesn't support automatic port opening."
	else:
		var m := u.add_port_mapping(port, port, "Ferrum Frontier", "UDP", 0)
		if m != UPNP.UPNP_RESULT_SUCCESS:
			r.msg = "Your router refused to open the port (UPnP error %d)." % m
		else:
			r.ok = true
			r.ip = u.query_external_address()
	call_deferred("_upnp_finished", r)

func _upnp_finished(r: Dictionary) -> void:
	if upnp_thread:
		upnp_thread.wait_to_finish()
		upnp_thread = null
	if mode != "host" or r.port != host_port:
		if r.ok:
			r.upnp.delete_port_mapping(r.port, "UDP")
		return
	if r.ok:
		upnp = r.upnp
		upnp_state = "open"
		public_ip = r.ip
		if _is_private(public_ip) or public_ip == "":
			upnp_msg = "The port is open on your router, but your router's internet address is private (%s). Your internet provider is probably sharing one public address between customers (CGNAT), so friends outside your network can't reach you directly. Use Tailscale instead." % public_ip
			upnp_state = "failed"
		else:
			upnp_msg = "Port %d opened on your router automatically." % host_port
	else:
		upnp_state = "failed"
		upnp_msg = r.msg + " Friends on your network can still join. For internet play, forward UDP %d to this PC on your router, or use Tailscale." % host_port
	upnp_done.emit()

static func _is_private(ip: String) -> bool:
	var p := ip.split(".")
	if p.size() != 4:
		return true
	var a := p[0].to_int()
	var b := p[1].to_int()
	return a == 10 or a == 127 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31) or (a == 100 and b >= 64 and b <= 127) or (a == 169 and b == 254)

func _close_upnp() -> void:
	if upnp != null:
		upnp.delete_port_mapping(host_port, "UDP")
		upnp = null
	upnp_state = "off"
	upnp_msg = ""
	public_ip = ""

func _exit_tree() -> void:
	if upnp_thread:
		upnp_thread.wait_to_finish()
		upnp_thread = null
	_close_upnp()

func lan_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and _is_private(a) and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out

func join(addr: String, port: int, pname: String) -> String:
	shutdown()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, port)
	if err != OK:
		peer = null
		return "Could not start a connection to %s:%d." % [addr, port]
	multiplayer.multiplayer_peer = peer
	mode = "client"
	my_name = pname
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)
	status.emit("Connecting to %s:%d..." % [addr, port])
	return ""

func shutdown() -> void:
	for pair in [[multiplayer.peer_disconnected, _on_peer_left], [multiplayer.connected_to_server, _on_connected],
			[multiplayer.connection_failed, _on_failed], [multiplayer.server_disconnected, _on_server_gone]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
	if peer:
		peer.close()
	peer = null
	_close_upnp()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = "offline"
	remote.clear()
	bundles.clear()
	pending_hellos.clear()
	accepting = true
	pending_cs.clear()
	my_cs.clear()
	host_cs.clear()
	resyncing = false
	desyncs = 0

func _on_connected() -> void:
	status.emit("Connected. Downloading the world...")
	connected.emit()
	hello.rpc_id(1, my_name, Data.VERSION)

func _on_failed() -> void:
	dropped.emit("Could not reach the host. Check the address, the port, and the host's firewall.")

func _on_server_gone() -> void:
	dropped.emit("The host closed the game.")

func _on_peer_left(id: int) -> void:
	if mode == "host":
		remote.append({"t": "leave", "pid": id, "seq": -1})

func ping_ms(id := 1) -> int:
	if peer == null:
		return 0
	var p := peer.get_peer(id)
	if p == null:
		return 0
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))

# ------------------------------------------------------------------ snapshots
func snapshot_bytes() -> PackedByteArray:
	return JSON.stringify(main.sim.to_dict(), "", false).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)

static func decode_snapshot(b: PackedByteArray):
	var raw := b.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	return JSON.parse_string(raw.get_string_from_utf8())

# ------------------------------------------------------------------ host side
## All commands for this tick, in their final order. Clients replay this list verbatim.
func host_bundle(local: Array) -> Array:
	var all := local + remote
	remote = []
	all.sort_custom(func(a, b): return a.pid < b.pid or (a.pid == b.pid and a.get("seq", 0) < b.get("seq", 0)))
	return all

func broadcast(tick: int, all: Array) -> void:
	var cs := pending_cs
	pending_cs = []
	bundle.rpc(tick, all, cs)

func host_after_step(sim: Sim) -> void:
	if sim.tick % CHECK_EVERY == 0:
		pending_cs = [sim.tick, sim.checksum()]

@rpc("any_peer", "call_remote", "reliable")
func hello(pname: String, ver: String) -> void:
	if mode != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	if not accepting:
		pending_hellos.append([id, pname, ver])
		return
	_accept(id, pname, ver)

func _accept(id: int, pname: String, ver: String) -> void:
	if ver != Data.VERSION:
		main.log_line("Refused %s: version %s (host %s)" % [pname, ver, Data.VERSION])
		kicked.rpc_id(id, "Version mismatch: the host runs %s, you run %s." % [Data.VERSION, ver])
		return
	welcome.rpc_id(id, id, snapshot_bytes())
	remote.append({"t": "join", "pid": id, "name": pname.substr(0, 20), "seq": -1})
	main.log_line("%s joined (peer %d)" % [pname, id])

## Host: the world finished loading; let in anyone who knocked meanwhile.
func flush_pending() -> void:
	accepting = true
	for h in pending_hellos:
		_accept(h[0], h[1], h[2])
	pending_hellos.clear()

@rpc("any_peer", "call_remote", "reliable")
func cmds(list: Array) -> void:
	if mode != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	for c in list:
		if typeof(c) == TYPE_DICTIONARY and ALLOWED.has(c.get("t", "")):
			c["pid"] = id
			remote.append(c)

@rpc("any_peer", "call_remote", "reliable")
func request_resync() -> void:
	if mode != "host":
		return
	resync.rpc_id(multiplayer.get_remote_sender_id(), snapshot_bytes())

# ------------------------------------------------------------------ client side
func send_cmds(list: Array) -> void:
	if mode == "client" and list.size():
		cmds.rpc_id(1, list)

func client_after_step(sim: Sim) -> void:
	if sim.tick % CHECK_EVERY == 0:
		my_cs[sim.tick] = sim.checksum()
		_compare(sim.tick)

func _compare(t: int) -> void:
	if not (my_cs.has(t) and host_cs.has(t)):
		return
	if my_cs[t] != host_cs[t] and not resyncing:
		desyncs += 1
		main.log_line("Desync at tick %d: local %d, host %d. Requesting resync." % [t, my_cs[t], host_cs[t]])
		resyncing = true
		main.hud.toast("Out of sync with the host. Resyncing...", "bad")
		request_resync.rpc_id(1)
	my_cs.erase(t)
	host_cs.erase(t)

@rpc("authority", "call_remote", "reliable")
func welcome(pid: int, snap: PackedByteArray) -> void:
	var d = decode_snapshot(snap)
	if typeof(d) != TYPE_DICTIONARY:
		dropped.emit("The world download was damaged. Try joining again.")
		return
	main.client_start(pid, d)

@rpc("authority", "call_remote", "reliable")
func bundle(tick: int, list: Array, cs: Array) -> void:
	if mode != "client":
		return
	bundles[tick] = list
	if cs.size() == 2:
		host_cs[cs[0]] = cs[1]
		_compare(cs[0])

@rpc("authority", "call_remote", "reliable")
func resync(snap: PackedByteArray) -> void:
	var d = decode_snapshot(snap)
	if typeof(d) == TYPE_DICTIONARY:
		main.client_resync(d)
		main.hud.toast("Resynced with the host.", "good")
	resyncing = false
	my_cs.clear()
	host_cs.clear()

@rpc("authority", "call_remote", "reliable")
func kicked(msg: String) -> void:
	dropped.emit(msg)
