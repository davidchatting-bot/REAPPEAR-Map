# REAPPEAR: The Map - 10⁷ metres

The Map is one of the five Network Scopes from [The Reappearing Computer](https://davidchatting.com/reappearingcomputer/), a research project about making computational work visible. This scope operates at the largest scale, the Earth itself, 10⁷ metres - it shows how the home creates work across the planet through its use of the Internet. The other scopes measure at different scales.

The Map runs on a Raspberry Pi as a display in your home and illustrates the network activity in real-time. It requires that [Pi-hole](https://pi-hole.net/), a network-wide DNS ad-blocker, is running on the local network.

![Demo: the globe rotating and settling on five example hostnames](demo.gif)

## How work is mapped

1. A device on the network makes a [DNS request](https://en.wikipedia.org/wiki/Domain_Name_System), which is logged by Pi-hole.
2. The Map polls Pi-hole's API is for new hostnames roughly once a second.
3. New hostnames join a queue and are processed in turn.
4. Each hostname is resolved to an IP, then that IP is sent to [ipinfo.io](https://ipinfo.io/) for a rough lat/lon,
   cached to `data/location_cache.json`.
5. The globe animates to that location.

## Structure

- `source/` — the `.pde` sketch source, the only code that's edited by hand
- `tools/pde2java.py` — combines the `.pde` tabs into a single compilable `build/TheMap.java`
  (a stand-in for the Processing IDE's preprocessor, generated on every build, not tracked)
- `build.sh` — builds `lib/TheMap.jar` from `source/`
- `tools/fetch-natives.sh` — downloads the ARM native libraries into `lib/`, see Building below
- `data/` — earth texture (attribution below) and the location cach
- `lib/` — third-party libraries, see Building below
- `TheMap` — launcher script
- `config.properties.example` — config template (copy to `config.properties` and fill in real values)

## Hardware / OS

- **Board:** Raspberry Pi 3 Model B Rev 1.2
- **OS:** Raspbian GNU/Linux 10 (buster), kernel `5.10.103-v7+` (armv7l)
- **Display:** [Pimoroni HyperPixel 2.1" Round](https://shop.pimoroni.com/en-us/products/hyperpixel-round) (`dtoverlay=hyperpixel2r` in `/boot/config.txt`)
- **Java:** OpenJDK 11.0.18 (Raspbian build)

## Building

To build locally, put `core.jar`, `jogl-all.jar`, `gluegen-rt.jar` and `Ani.jar` in `lib/` and run
`./build.sh` (needs a JDK and Python 3). It generates `build/TheMap.java` from `source/*.pde`,
compiles it, and writes `lib/TheMap.jar`.

`.github/workflows/build.yml` runs the same script on every push and uploads two artifacts:

- **TheMap.jar** - just the compiled sketch, for catching compile errors quickly.
- **TheMap-linux-armv6hf** - a complete, ready-to-run bundle for the Pi: `TheMap.jar` plus
  every jar it needs (`core.jar`/`jogl-all.jar`/`gluegen-rt.jar` from Processing 3.5.4,
  `Ani.jar` built from source, and the ARM-specific native jars from Maven Central), the
  launcher script, `config.properties.example`, and the earth texture. To deploy: download,
  extract, copy `config.properties.example` to `config.properties` and fill in real values
  (see Running below), then run `./TheMap`.

The ARM native jars (`jogl-all-natives-linux-armv6hf.jar`, `gluegen-rt-natives-linux-armv6hf.jar`)
are a runtime-only dependency of JOGL's native library loader, so `build.sh` doesn't need them, but
a Pi needs them in `lib/` to run. No official Processing release includes them (Processing dropped
Linux ARM builds before 3.5.4), so `./tools/fetch-natives.sh` downloads JOGL/GlueGen 2.3.2's from
Maven Central and checks them against pinned SHA-256 hashes; CI runs it when assembling the bundle.

## Font

Helvetica, loaded as an installed **system** font at runtime, not a bundled file. Falls back to Java's `SansSerif` if
Helvetica isn't installed.

## Running

Copy `config.properties.example` to `config.properties` (gitignored) and fill in three values,
then run `./TheMap`:

- `pihole.server` — host:port of the Pi-hole instance (e.g. `192.168.1.175:80`)
- `pihole.key` — Pi-hole admin/app password, see:
  [Pi-hole's v6 API](https://docs.pi-hole.net/api/)
- `ipinfo.token` — API token for [ipinfo.io](https://ipinfo.io/)

## License & attribution

MIT licensed — see [LICENSE](LICENSE).

`data/eqcy_600.png` is derived from
[BlankMap-Equirectangular.svg](https://commons.wikimedia.org/wiki/File:BlankMap-Equirectangular.svg)
(Wikimedia Commons, [Natural Earth](https://www.naturalearthdata.com/) data,
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)): rasterized, thresholded to a
binary land mask, then edge-detected down to just the coastline as a white line on black.

The native jars fetched by `tools/fetch-natives.sh` (and bundled in the CI artifact) are
[JOGL](https://jogamp.org/jogl/www/) and [GlueGen](https://jogamp.org/gluegen/www/) native
libraries, Copyright 2009-2024 JogAmp Community, BSD 2-Clause licensed.
