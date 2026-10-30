# Multiplayer

## How it works

Ferrum Frontier uses **host-relayed deterministic lockstep**. Every player runs the full simulation. Nobody sends world state; players only send **commands** (walk, place, remove, set recipe, and so on).

- **The host** steps the simulation in real time at 60 ticks per second. Each tick it takes its own commands plus everything clients sent since the last tick and fixes their order. It broadcasts that list (a *bundle*), then steps.
- **Clients** never step on their own clock. A client steps tick N only when bundle N arrives, so everyone applies the same commands in the same order and the worlds stay identical.
- **Bandwidth stays small no matter how big the factory gets.** A bundle is a few bytes per player per tick. Input is sent only when it changes.
- **The host never waits.** A slow client just falls behind and catches up by stepping up to 240 ticks per frame.

### Joining (drop-in)

1. The client connects and sends its name and game version.
2. The host checks the version, then sends a gzip-compressed snapshot: the world settings (seed and all options) plus the full simulation state.
3. The host schedules a `join` command for its very next tick.
4. The client regenerates the map from the settings, loads the snapshot, and replays bundles from that tick on.

### Leaving

When a player disconnects, the host schedules a `leave` command. That player's inventory goes into the HUB, so nothing is lost.

If the host quits, the session ends. Clients go back to the title screen with a message.

### Desync detection

Every 300 ticks (5 s), the host attaches its state checksum to a bundle. A client compares it with its own. On a mismatch, the client asks for a fresh snapshot and reloads it. The player list shows how many times that has happened.

### Your own movement

With lockstep, your input takes effect after a round trip to the host. To hide that, clients **predict** their own engineer: you move instantly on screen, using the same movement and collision rules as the sim.

When the host's authoritative position arrives, the client compares it with where it predicted you were at that moment and nudges the prediction by the difference. Errors are normally zero, because the movement code is identical on both sides.

## Playing

There is no dedicated server and no Steam. One player's PC hosts, and everyone else connects to it by IP address.

1. **PC1:** Title → **Host game**. Pick the world settings and click **Host**, or use **Host my last save**. The default port is 34197 (UDP).
2. **PC2:** Title → **Join game**. Enter the address PC1 shows, then click **Connect**.

The host's player list (bottom right) shows the addresses to hand out, each with a **Copy** button:

- **Same network:** PC1's LAN address, for example `192.168.1.20:34197`.
- **Internet:** PC1's public address. This appears once the port has been opened automatically (see below).

### Automatic port opening (UPnP)

When you host, the game asks your router to forward the game port to your PC, using UPnP. The request runs in the background and takes a couple of seconds. A message tells you how it went:

- **"Port opened automatically":** give friends the Internet address. The rule is removed when you stop hosting or quit.
- **"No router answered" or "router refused":** UPnP is off or unsupported. LAN play still works. For internet play, either:
  - turn on UPnP in your router's settings, or
  - add a port-forward rule by hand: UDP 34197 to your PC's LAN address, or
  - have both PCs install Tailscale and join using PC1's Tailscale address. No router changes are needed.
- **"Private address / CGNAT":** your internet provider shares one public IP between customers, so nothing can reach you directly. Tailscale is the fix.

The first time you host, Windows may ask whether to allow Ferrum Frontier through the firewall. Allow it for **private** networks (and public ones, if you host from a laptop on other networks).

- **Everyone must run the same version.** It is shown on the join screen, and the host refuses mismatches.
- **The world keeps running** when anyone opens the menu. Only the host can save.

### Talking to each other

- **Enter** opens chat. Messages go through the same command stream as everything else, so everyone sees them in order.
- **G** or the **middle mouse button** pings the spot under the cursor. It shows rings on the map, a blinking marker on the minimap, and a sound.
- When a client places a building, it shows as a ghost straight away and turns solid when the host confirms it, usually within one round trip.

### Joining a host that is still loading

If someone connects while the host's world is still generating, the host holds the request and lets them in as soon as it's ready.

## Testing on one machine

Run two copies of the game. In one, click **Host game**. In the other, click **Join game** with address `127.0.0.1`.

There is also a scripted headless test. It runs a host and a client, has both build, walk, craft, pick up and deconstruct, and prints `CS <tick> <checksum>` every 300 ticks. Matching lines mean the two worlds stayed identical.

```
godot --headless --path . -- --nettest=host &
godot --headless --path . -- --nettest=client
```

## Rules for keeping the sim deterministic

Anything inside `Sim` must produce bit-identical results on every machine:

- **No `randf()` / `randi()`, `Time`, or frame `delta` inside `Sim`.** Use `sim.rng` and tick counts.
- **Integers for anything that decides outcomes.** Floats are fine in `WorldView` and `Hud`.
- **Serialise snapshots with `JSON.stringify(data, "", false)`.** The default sorts dictionary keys. That changes iteration order after a reload, and the worlds drift apart. This bug was found and fixed during testing.
- **Every new piece of state goes into `to_dict()` / `from_dict()`.** The self-test checks that a reloaded sim keeps the same checksum.
- **New command types must be added to `NetLink.ALLOWED`.** Otherwise clients can't send them.

## Not done yet

- **Steam networking (GodotSteam):** invites and relays, for the cases UPnP can't solve (CGNAT, locked-down routers). Only `NetLink` needs to change.
- **Mixed Windows/Linux sessions:** map generation uses float maths. If you see desyncs only between different operating systems, have the host send the generated map arrays with the snapshot instead of regenerating them.
