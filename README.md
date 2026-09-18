# REAPPEAR: Map

A Processing sketch that renders a rotating 3D globe on a Pimoroni HyperPixel 2.1" Round
display, driven by live Pi-hole DNS query logs. Originally built to run on this Raspberry Pi
alongside a local Pi-hole install. Part of the REAPPEAR project.

## Hardware / OS

- **Board:** Raspberry Pi 3 Model B Rev 1.2
- **OS:** Raspbian GNU/Linux 10 (buster), kernel `5.10.103-v7+` (armv7l)
- **Display:** Pimoroni HyperPixel 2.1" Round, enabled via `dtoverlay=hyperpixel2r` in
  `/boot/config.txt`, with `display_lcd_rotate=-1` / `display_hdmi_rotate=-1`
- **Java:** OpenJDK 11.0.18 (Raspbian build)
- Known display quirk: this HyperPixel + `vc4-kms-v3d` GPU driver combination has a
  long-standing, unresolved issue where the app runs fine (healthy process, clean logs) but
  paints nothing to the physical screen. A full `sudo reboot` reliably clears it; screenshots
  are unreliable for checking this display, only direct visual confirmation counts.

## Running

Requires three environment variables (previously hardcoded, now redacted for safety):

- `PIHOLE_SERVER` — host:port of the Pi-hole instance to query (e.g. `192.168.1.175:80` for
  the Proxmox-hosted v6 Pi-hole)
- `PIHOLE_KEY` — Pi-hole admin password or app password
- `IPINFO_TOKEN` — ipinfo.io API token, used to geolocate queried hostnames

`LogLines.pde` talks to [Pi-hole v6's API](https://docs.pi-hole.net/api/) (session-based):
it POSTs the password to `/api/auth` to get a session id (`sid`), then passes that as an
`sid` header on `GET /api/queries?length=15` to fetch recent query records. Sessions expire
(Pi-hole's default is 30 minutes) — `updateRecords()` re-authenticates automatically, both
proactively before expiry and reactively on a 401. This replaces the old v5 flow, which
authenticated via a `&auth=<token>` query-string parameter on
`/admin/api.php?getAllQueries=...` — that endpoint doesn't exist any more on v6.

## Font

The label font is Helvetica, loaded as an installed **system** font at runtime
(`createFont("Helvetica Regular", 14)`) rather than a bundled `.ttf` file — the macOS/Adobe
copies used during development aren't ours to redistribute, so no font file ships in this
repo. If Helvetica isn't installed, it falls back to Java's `SansSerif` logical font
(always available, but a different typeface with different metrics).

To get the real Helvetica on a fresh install, copy a licensed `Helvetica.ttf` you're
entitled to use onto the device and register it system-wide:

```sh
sudo cp Helvetica.ttf /usr/local/share/fonts/
sudo fc-cache -f
```

Note: Java's Linux font manager does **not** reliably pick up per-user font directories
(`~/.local/share/fonts`) — it needs a system-wide location like `/usr/local/share/fonts/`.
Also note `PFont.list()` returns the full font name including style (`"Helvetica Regular"`,
not `"Helvetica"`) — match against that, not the bare family name.

## Structure

- `source/` — the `.pde` sketch source
- `data/` — earth texture image (see attribution below)
- `lib/` — third-party Processing libraries (jogl, gluegen, Ani) — not tracked, see `.gitignore`
- `TheMap` — launcher shell script

## Earth texture attribution

`data/eqcy_600.png` is derived from
[File:BlankMap-Equirectangular.svg](https://commons.wikimedia.org/wiki/File:BlankMap-Equirectangular.svg)
on Wikimedia Commons, sourced from [Natural Earth](https://www.naturalearthdata.com/) data and
released under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (public domain -
attribution not legally required, but noted here for provenance).

Processing pipeline: the SVG was rasterized to a filled land/ocean PNG, thresholded to a binary
land mask (absorbing the country-border strokes into solid land), then edge-detected to leave
just the outer coastline as a thin white line on black - no country borders, no filled
continents.
