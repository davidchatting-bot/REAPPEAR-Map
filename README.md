# REAPPEAR: The Map - 10⁷ metres

The Map is one of the Network Scopes from [The Reappearing Computer](https://davidchatting.com/reappearingcomputer/), a research project about making computational work visible. This scope operates at 10⁷ metres - the scale of the Earth itself, showing how the home creates work across the planet. The other scopes measure at different scales.

The Map runs on a Raspberry Pi as a display in your home and illustrates the network activity in real-time. It requires that [Pi-hole](https://pi-hole.net/), a network-wide DNS ad-blocker, is running on the local network.

![Demo: the globe rotating and settling on four example hostnames](demo.gif)

## How work is mapped

1. A device on the network makes a DNS request; Pi-hole, as the resolver, logs it.
2. `LogLines.pde` polls Pi-hole's API for new hostnames roughly once a second, filtering out
   reverse lookups, local names, and ipinfo.io's own hostname (to avoid a lookup-of-a-lookup
   loop).
3. New hostnames join a FIFO queue - also shown on screen as an animation to-do list - and
   are worked through oldest-first.
4. Each hostname is resolved to an IP, then that IP is sent to ipinfo.io for a rough lat/lon,
   cached to `data/location_cache.json` so repeat lookups are free.
5. The globe animates to that location, a marker grows to show the hostname, holds briefly,
   then collapses and moves to the next host in the queue.

## Running

Copy `config.properties.example` to `config.properties` (gitignored) and fill in three values,
then run `./TheMap`:

- `pihole.server` — host:port of the Pi-hole instance (e.g. `192.168.1.175:80`)
- `pihole.key` — Pi-hole admin/app password, used against
  [Pi-hole's v6 API](https://docs.pi-hole.net/api/) (session-based; auto-reauthenticates)
- `ipinfo.token` — API token for [ipinfo.io](https://ipinfo.io/), the IP geolocation service
  used to place each hostname on the globe

## Building

`lib/` (Processing/JOGL/Ani jars) isn't tracked - see `.gitignore`.

1. Get `core.jar`, `jogl-all.jar`, `gluegen-rt.jar` and their `-natives-linux-armv6hf.jar`
   companions from `<processing-install>/core/library/` in a
   [Processing 3.5.4](https://github.com/processing/processing/releases/tag/processing-0270-3.5.4)
   install.
2. Get `Ani.jar` from the [Ani source](https://github.com/b-g/Ani) (archived/unmaintained;
   its old homepage is dead).
3. Put all of the above in `lib/`.
4. `javac -cp lib/core.jar:lib/jogl-all.jar:lib/gluegen-rt.jar:lib/Ani.jar -d build_classes build/TheMap.java`,
   then package into `lib/TheMap.jar` with a manifest declaring `Main-Class: TheMap`.

## Hardware / OS

- **Board:** Raspberry Pi 3 Model B Rev 1.2
- **OS:** Raspbian GNU/Linux 10 (buster), kernel `5.10.103-v7+` (armv7l)
- **Display:** [Pimoroni HyperPixel 2.1" Round](https://shop.pimoroni.com/en-us/products/hyperpixel-round) (`dtoverlay=hyperpixel2r` in `/boot/config.txt`)
- **Java:** OpenJDK 11.0.18 (Raspbian build)
- Known quirk: this HyperPixel + `vc4-kms-v3d` GPU driver combination sometimes runs fine
  but paints nothing to the physical screen. `sudo reboot` reliably clears it.

## Font

Helvetica, loaded as an installed **system** font at runtime, not a bundled file -
commercial font files aren't ours to redistribute. Falls back to Java's `SansSerif` if
Helvetica isn't installed. To install it:

```sh
sudo cp Helvetica.ttf /usr/local/share/fonts/ && sudo fc-cache -f
```

## Structure

- `source/` — the `.pde` sketch source
- `data/` — earth texture (attribution below) and the location cache (gitignored)
- `lib/` — third-party libraries, see Building above (not tracked)
- `TheMap` — self-locating launcher script
- `config.properties.example` — config template (copy to `config.properties` and fill in real
  values - gitignored)

## Earth texture attribution

`data/eqcy_600.png` is derived from
[BlankMap-Equirectangular.svg](https://commons.wikimedia.org/wiki/File:BlankMap-Equirectangular.svg)
(Wikimedia Commons, [Natural Earth](https://www.naturalearthdata.com/) data,
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)): rasterized, thresholded to a
binary land mask, then edge-detected down to just the coastline as a white line on black.
