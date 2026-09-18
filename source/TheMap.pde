import java.net.*;
import java.io.*;
import java.util.*;
import de.looksgood.ani.*;
import de.looksgood.ani.easing.*;

PImage earthTexture;
PShape globe;

Ani aniX, aniY;
boolean isAnimating = false;
long animEndMs = 0;

// Marker "pill" stretch, animated from 0 (plain circle) to 1 (fully
// stretched) the moment the globe settles - see drawLocationBlip().
Ani aniBlipStretch;
float blipStretch = 0;

// Guaranteed minimum pause after settling before the next animation is
// allowed to start, so the label always gets visible time even when
// pendingHosts has a backlog - without this, processPendingLocation() would
// start the next animation the instant isAnimating clears, most of the time
// leaving ~0 settled frames.
long settleEndMs = 0;
int settleDurationMs = 1500;

// After settleEndMs, the blip always collapses back to a fully neutral
// state (no fill, no label) - see draw(). collapseGraceMs then holds
// processPendingLocation() off for a bit longer, so that collapsed state
// is actually visible for a moment under busy traffic, rather than the
// next travel starting the same frame and overwriting it instantly.
int collapseGraceMs = 500;

// touchAngle tracks the drag angle relative to screen centre, purely to
// compute the angle DELTA between successive drag events (see
// mouseDragged()). angularSpeed is that delta's rate (degrees/sec,
// signed for direction), fired out via onDragEvent() rather than drawn.
float touchAngle = 0;
float angularSpeed = 0;
float angularSpeedSmoothing = 0.25f; // exponential moving average factor - lower = smoother but laggier
long lastTouchMs = 0;

Easing easing = Easing.CUBIC_IN_OUT;

float angleX = 0;
float angleY = 0;
//float angleZ = 0;
int currentLocation = 0;
float[][] locations = {
  {-0.1278, 51.5074}, // London (lon, lat)
  {116.4074, 39.9042}, // Beijing
  {-122.1430, 37.4419}, // Palo Alto
  {-151.21, -33.867778}, //Sydney
  //{180.0, 0.0},  //date line
  {0.0, 0.0}, //greenwich
  {-12.4964, 41.9028}, //rome
};
//LogLine[] lines = new LogLine[5];

int sphereRadius; // set in setup(), once width is known
int clockFaceRadius;
int markHeight = 15;
int interactionBoundary = 200;

float playHead = 0;

// Loaded from config.properties in setup() - see loadConfig().
String piholeserver;
String piHoleKey;
String ipinfoToken;

int framesPerSecond = 60;

HashMap<String, Location> hostLocations = new HashMap<String, Location>();
LogLines logLines = null;

// Persists hostLocations to disk so a restart doesn't re-spend ipinfo.io
// quota re-resolving hosts it already knows about. Path is relative to the
// working directory run_with_env.sh cd's into before launching, matching
// how earthTexture's bare "eqcy_600.png" filename resolves.
String locationCacheFile = "data/location_cache.json";

// Hosts waiting to be geolocated+animated to, oldest first (index 0) - also
// what's shown in the on-screen list, as an animation to-do list. onLogEvent()
// only enqueues here - the actual blocking getLocation() call happens at most
// once per frame, in processPendingLocation(), so a burst of several new
// hosts in one Pi-hole poll gets worked through in arrival order instead of
// all but the first being silently dropped.
ArrayList<String> pendingHosts = new ArrayList<String>();
int maxPendingHosts = 50; // safety cap on the queue itself
int maxVisiblePending = 12; // how many of it we actually draw on screen

// Hostname the globe is currently settled on, shown next to the blip.
String currentHostLabel = "";

long currentTime;
int seconds[] = new int[60];

PFont consoleFont;

void setup() {
  size(480, 480, P3D);
  clockFaceRadius = (width - 10)/2;
  frameRate(framesPerSecond);

  // Fill the full screen, no border - was 180 (leaving a visible margin
  // inside the round display's edge). Not simply width/2: a sphere's
  // silhouette under perspective projection appears LARGER than its
  // radius-at-centre would suggest via flat 1:1-at-z=0 scaling, because
  // its near limb bulges toward the camera - width/2 here overflowed
  // past the screen edge. For a sphere of world radius r centred at the
  // camera distance d = cameraZ (matching computeBlipLayout()'s
  // perspective math), the apparent screen radius is d*r/sqrt(d^2-r^2);
  // solving that for r given the desired screen radius R = width/2
  // gives r = R*d/sqrt(d^2+R^2). Must happen before computeBlipLayout()
  // (and before createShape(SPHERE, ...) below), since both depend on
  // sphereRadius.
  float cameraZ = (height / 2.0f) / tan(PI * 30.0f / 180.0f); // matches P3D's default camera()/perspective()
  float targetScreenRadius = width / 2.0f;
  sphereRadius = (int) (targetScreenRadius * cameraZ / sqrt(cameraZ*cameraZ + targetScreenRadius*targetScreenRadius));

  computeBlipLayout();

  loadConfig();

  //logLines = new LogLines(sketchPath("data/pi-hole.json"));
  logLines = new LogLines();

  // Touch-only kiosk display - no reason to render a pointer, and any
  // perceived lag on it is X11 compositing a cursor on top of a
  // full-screen OpenGL app on this hardware, not anything in the
  // sketch (mouse handlers are fully disabled - see mousePressed() etc).
  noCursor();

  noStroke();
  fill(255);
  sphereDetail(40);
  
  // Helvetica as a system font, not a bundled file - genuinely present
  // on macOS, but this Pi doesn't have it installed (only Nimbus Sans L,
  // a metrically-compatible clone). No .ttf files shipped in the repo,
  // since the macOS/Adobe copies aren't ours to redistribute. Checking
  // PFont.list() first rather than calling createFont("Helvetica", ...)
  // blind - createFont() does fuzzy substitution for an unmatched name
  // rather than failing cleanly. "SansSerif" is Java's built-in logical
  // font name, guaranteed to resolve to some sans-serif font on any
  // system - an explicit, predictable fallback rather than whatever
  // fuzzy match createFont() would otherwise pick.
  // PFont.list() returns the full font name including style (e.g.
  // "Helvetica Regular", "Helvetica Light"), not the bare family name
  // ("Helvetica") that java.awt.GraphicsEnvironment's own font list
  // uses - matching against "Helvetica" alone always missed it.
  boolean helveticaAvailable = false;
  for (String fontName : PFont.list()) {
    if (fontName.equals("Helvetica Regular")) {
      helveticaAvailable = true;
      break;
    }
  }
  consoleFont = createFont(helveticaAvailable ? "Helvetica Regular" : "SansSerif", 14);

  earthTexture = loadImage("eqcy_600.png");  //cylindrical equidistant projection
  // Tried noSmooth() here to stop bilinear filtering blending the thin
  // white lines into grey at the sphere's silhouette, but it's a global
  // renderer setting - also made the server list text and blip edges
  // more jagged, which wasn't wanted. Back to smooth().
  globe = createShape(SPHERE, sphereRadius);
  globe.setTexture(earthTexture);

  // Detail baked into the globe PShape above is already fixed at 40 - this
  // just lowers it for the location blip's own sphere() calls from here on,
  // so its outlined state reads as a clean ring rather than a dense wireframe.
  sphereDetail(8);

  Ani.init(this);

  loadLocationCache();

  splashScreen();
  logLines.setSpeed(1);
  println("First Timestamp: " + logLines.getFirstTimestamp());
  
  logLines.start(logLines.getFirstTimestamp());
  
  //for(int n=0; n < seconds.length; ++n) {
  //  seconds[n] = random(100) > 90 ? 1 : 0;
  //}
}

// Reads config.properties (gitignored, not the repo's config.properties -
// that's just a placeholder template) from the working directory - same
// relative-path convention as earthTexture's "eqcy_600.png" and
// locationCacheFile above. Replaces the old PIHOLE_SERVER/PIHOLE_KEY/
// IPINFO_TOKEN env vars and their run_with_env.sh wrapper: this way the
// jar can be launched directly (see the TheMap launcher script) without a
// shell script existing purely to export secrets into the environment.
void loadConfig() {
  Properties config = new Properties();
  try (FileInputStream configStream = new FileInputStream("config.properties")) {
    config.load(configStream);
  }
  catch (IOException e) {
    println("Could not load config.properties: " + e.getMessage());
  }
  piholeserver = config.getProperty("pihole.server");
  piHoleKey = config.getProperty("pihole.key");
  ipinfoToken = config.getProperty("ipinfo.token");
}

void draw() {
  if (isAnimating && millis() >= animEndMs) {
    isAnimating = false;
    settleEndMs = millis() + settleDurationMs;

    // Size this settle's pill to fit its actual label, rather than
    // always growing to maxPillStretch regardless of content - a short
    // hostname gets a small tight pill, a long one grows further. Capped
    // at maxPillStretch so the pill itself never runs off the screen
    // edge - shortenForDisplay() never truncates text below a domain.tld
    // though, so on the rare registrable domain long enough to exceed
    // that cap, the text can still be wider than the pill it sits in.
    textFont(consoleFont);
    textSize(labelTextSize);
    String upcomingLabel = shortenForDisplay(currentHostLabel, maxLabelWidth());
    // Right margin is a full extra labelPadding (so labelPadding*2 total
    // on the right vs labelPadding on the left) rather than just a couple
    // of px - textWidth() reports the advance width, which for some
    // strings runs enough narrower than the glyphs' actual right edge
    // (overshoot/hinting) that text was sometimes sitting right at, or
    // past, the pill's edge with only a tiny fixed buffer.
    pillStretch = min(maxPillStretch, textWidth(upcomingLabel) + labelPadding*3);

    aniBlipStretch = new Ani(this, 0.3f, "blipStretch", 1, easing);
  }
  // Always collapses back to the unfilled circle exactly settleDurationMs
  // after settling - guaranteed, not conditional on how long it's been
  // since the last visit (the old idle-timeout approach), since under
  // busy traffic there's always something next in pendingHosts and idle
  // time alone would never trigger. processPendingLocation() waits an
  // additional collapseGraceMs before starting the next travel, so this
  // collapsed state is actually visible for a moment rather than being
  // overwritten the very same frame.
  if (!isAnimating && currentHostLabel.length() > 0 && millis() >= settleEndMs) {
    currentHostLabel = "";
    aniBlipStretch = new Ani(this, 0.3f, "blipStretch", 0, easing);
  }
  processPendingLocation();

  background(0);
  strokeWeight(1);
  translate(width/2, height/2);

  //Playhead
  //stroke(255);
  //noFill();
  //int playHeadx = (int)(width/2 * Math.cos(playHead));
  //int playHeady = (int)(width/2 * Math.sin(playHead));
  //circle(playHeadx, playHeady, 50);

  drawGlobe();

  if (frameCount % framesPerSecond == 0) {
    logLines.updateRecords();
  }

  // Hidden - reads like a console log on screen. Queue processing
  // continues in the background regardless; this only affects the
  // visual.
  //drawServerList();

  currentTime = new Date().getTime()/1000;

  //drawClockFace();
  //drawClock(logLines.tick());
}

// The animation to-do list, top-left of the screen: hosts still waiting to
// be visited, oldest/next-up first, same order processPendingLocation()
// works through them in. Entries disappear from here the moment they're
// dequeued (whether or not they resolve to a real animation).
void drawServerList() {
  pushStyle();
  fill(255);
  textFont(consoleFont);
  textSize(14);
  textAlign(LEFT, TOP);
  textLeading(18);

  float x = -width/2 + 16;
  float y = -height/2 + 16;

  int shown = min(pendingHosts.size(), maxVisiblePending);
  for (int i = 0; i < shown; i++) {
    text(pendingHosts.get(i), x, y + i*18);
  }
  popStyle();
}

void drawGlobe() {
  push();
  // Force opaque fill explicitly - don't rely on whatever noFill()/stroke()
  // state earlier drawing in this frame (e.g. the screen-edge circle) left
  // behind, since push()/pop() hasn't reliably scoped that on this device.
  // fill() acts as a tint/multiply on the texture below. Dimmed further so
  // the blip and its label read clearly against it.
  noStroke();
  fill(50); // marker/text are already at full white (255) and can't go brighter, so the only lever for more contrast is dimming the globe further
  rotateX(angleY * -1.0f);
  rotateY(angleX + HALF_PI);
  shape(globe);

  // Was cycling through the fixed demo locations every 3s to test the
  // animation/blip mechanism - stopped for now. Re-enable this (or better,
  // wire animateTo() up to real per-query locations via onLogEvent()) when
  // ready to animate for real.
  //if (frameCount % 180 == 0) {
  //  animateTo(locations[currentLocation][0], locations[currentLocation][1], 2.0f);
  //  currentLocation = (currentLocation + 1) % locations.length;
  //}
  pop();

  drawLocationBlip();
}

// A simple marker confirming the current target location. The rotation
// above always brings that location to the front-center of the sphere, so
// the blip just sits there in unrotated space - same white as the server
// list text, sitting just above the globe's surface so it isn't occluded.
// The marker itself is always visible - it never disappears, so the
// screen is never left with no reference point at all. Filled+labelled
// once settled on a location, where it stretches right into a rounded
// "pill" (see blipStretch above) leading toward the label; outlined/
// unfilled and a plain circle both while animating between locations AND
// always again once settleDurationMs after settling, guaranteed - see
// the collapse check in draw(). A flat 2D circle rather than a 3D
// sphere - a wireframe sphere shows both
// its front and back facets when unfilled, which is a mess at this size;
// a flat circle facing the camera gives a clean ring with no such
// artifact.
float blipRadius = 10; // half of the plain marker's diameter, and of the pill's height - the one dial everything below is derived from

// Text size and horizontal padding are derived from blipRadius rather
// than tuned as independent constants, so the whole marker scales as
// one unit if blipRadius ever changes. 1.3x radius sits the text's
// cap-height comfortably inside the pill's height without crowding the
// rounded caps; a floor keeps it legible if blipRadius shrinks a lot.
// 0.4x radius is the horizontal inset from the pill's flat section,
// clear of its curve without reading as dead space. The pill now grows
// to fit the label anyway (see the settle transition in draw()), so
// this mostly just trades off against maxPillStretch - the absolute cap
// near the screen edge, which still limits how much of a long
// domain.tld fallback shortenForDisplay() can fit before it has to
// hard-truncate.
float labelTextSize = max(8, blipRadius * 1.3f);
float labelPadding = blipRadius * 0.4f;
float maxPillStretch; // the absolute furthest the marker may stretch right - computed in setup(), stops it running off the screen edge
float pillStretch = 0; // how far THIS settle's pill actually stretches - sized to fit its label (see the settle transition in draw()), capped at maxPillStretch
float labelEdgeMargin = 8; // breathing room before the round screen's edge
boolean pillFillBlack = true; // trying a black-filled pill with white text instead of white-filled with black text - flip to false to go back

void drawLocationBlip() {
  push();
  translate(0, 0, sphereRadius + 4); // float the marker (and its label) above the globe surface,
                                      // in front of it so depth testing doesn't hide either one

  // Fill state flips instantly with showLabel - the moment a new
  // animation starts (or idle clears the label), it unfills straight
  // away, THEN the shape eases back down to a plain circle as an
  // outline (blipStretch easing 1->0 - see animateTo() and the idle
  // timeout in draw()). Growing is the mirror image: it's already
  // filled by the time blipStretch starts easing 0->1 on settle.
  boolean showLabel = !isAnimating && currentHostLabel.length() > 0;

  if (showLabel) {
    fill(pillFillBlack ? 0 : 255);
    if (pillFillBlack) {
      // Black fill needs a white stroke to stay visible against the
      // black background - a white fill doesn't (it's already visible).
      strokeWeight(2);
      stroke(255);
    } else {
      noStroke();
    }
  } else {
    noFill();
    strokeWeight(2);
    stroke(255);
  }

  // Stadium shape traced as two semicircular caps (each explicitly
  // vertexed, so the curve quality is controlled directly rather than
  // relying on rect()'s corner rounding, which visibly facets at this
  // radius) joined by straight top/bottom edges. The left cap is always
  // centred at local x=0; the right cap slides out to x=pillStretch as
  // blipStretch eases 0->1. When they coincide (blipStretch=0) the two
  // semicircles trace a plain circle - one path covers both states.
  float rightCapX = pillStretch * blipStretch;
  int capSegments = 16;
  beginShape();
  for (int i = 0; i <= capSegments; i++) {
    float a = -HALF_PI + PI * i / capSegments;
    vertex(rightCapX + blipRadius*cos(a), blipRadius*sin(a));
  }
  for (int i = 0; i <= capSegments; i++) {
    float a = HALF_PI + PI * i / capSegments;
    vertex(blipRadius*cos(a), blipRadius*sin(a));
  }
  endShape(CLOSE);

  // Only draw the text once the pill has actually reached full width -
  // showLabel goes true right as the grow animation starts (blipStretch
  // still 0), so without this the label would appear immediately,
  // overlapping the 0.3s grow instead of waiting for it to finish.
  if (showLabel && blipStretch >= 0.999f) {
    fill(pillFillBlack ? 255 : 0); // contrasting text colour against whichever fill the pill above is using
    textFont(consoleFont);
    textSize(labelTextSize);
    textAlign(LEFT, CENTER); // now that text sits inside the pill, centre it in the pill's height

    // Text sits inside the pill's flat middle section - between the two
    // rounded end-caps, each of which consumes blipRadius of the total
    // width. That flat section runs from local x=0 to x=pillStretch,
    // so a small inset from each side keeps the text clear of the curves.
    String label = shortenForDisplay(currentHostLabel, maxLabelWidth());
    text(label, labelPadding, 0);
  }
  pop();
}

// Sizes maxPillStretch, the absolute cap on how far the marker may
// stretch. Needs width/height, which size() only sets once setup() is
// under way - can't be a field initializer. The cap reaches out to the
// round screen's edge (minus a small margin); the screen-pixel target is
// divided by the same perspective scale factor maxLabelChars() would
// need if it compared text against raw screen pixels - but it doesn't
// need to any more, since the label now compares directly against
// maxPillStretch, which is already in these same world units.
void computeBlipLayout() {
  float cameraZ = (height / 2.0f) / tan(PI * 30.0f / 180.0f); // matches P3D's default camera()/perspective()
  float labelDepth = sphereRadius + 4; // must match the translate() in drawLocationBlip()
  float perspectiveScale = cameraZ / (cameraZ - labelDepth);

  float reach = ((width / 2.0f) - labelEdgeMargin) / perspectiveScale; // centre to edge, in world units at labelDepth
  maxPillStretch = reach - blipRadius;
}

// The pixel budget a label has to fit in: maxPillStretch, the pill's
// absolute cap (see drawLocationBlip() and the settle transition in
// draw(), which sizes the actual pill to the label rather than always
// growing to this cap), minus the padding on either side. Both the pill
// and the text are drawn at the same Z depth, so this compares directly
// against maxPillStretch with no perspective correction needed.
float maxLabelWidth() {
  return maxPillStretch - labelPadding*2;
}

// Shortens a hostname to fit within maxWidthPixels by dropping leading
// (sub)domain labels first, rather than just chopping characters off the
// end - e.g. "some.long.subdomain.example.com" -> "subdomain.example.com"
// -> "example.com", trying each progressively shorter version in turn.
// Measures each candidate's actual rendered width rather than estimating
// from a character count - consoleFont is proportional (Helvetica), so a
// per-character budget (based on "M", one of the widest letters) was
// truncating text that would have comfortably fit. Never truncates below
// the last two labels (the registrable domain) - if even that doesn't
// fit maxWidthPixels, it's returned as-is rather than character-cut, so
// the pill grows to fit it instead (see the settle transition in
// draw()). Assumes textFont()/textSize() are already set by the caller.
String shortenForDisplay(String hostname, float maxWidthPixels) {
  if (textWidth(hostname) <= maxWidthPixels) return hostname;

  String[] labels = hostname.split("\\.");
  for (int drop = 0; drop <= labels.length - 2; drop++) {
    String candidate = String.join(".", Arrays.copyOfRange(labels, drop, labels.length));
    if (textWidth(candidate) <= maxWidthPixels) return candidate;
  }

  return labels.length >= 2
    ? labels[labels.length - 2] + "." + labels[labels.length - 1]
    : hostname;
}

void drawClockFace() {
  for(int n = 0; n < seconds.length; ++n) {
    float a = (n/60.0f) * TWO_PI;
    float r = clockFaceRadius;
    
    int s = seconds[n] > 0 ? 255 : 60;
    stroke(s);
    strokeWeight(3);
    line(r * cos(a), r * sin(a), (r-markHeight) * cos(a), (r-markHeight) * sin(a));
  }
}

void drawClock(long timeMs) {
  float seconds = ((timeMs % 60000)/1000.0f);

  float a = TWO_PI * ((float)seconds/60) - HALF_PI;
  float r = clockFaceRadius;

  float x0 = (r-markHeight) * cos(a), y0 = (r-markHeight) * sin(a), x1 = r * cos(a), y1 = r * sin(a);

  strokeWeight(1);
  stroke(255);
  line(x0, y0, x1, y1);
  
  String s = "" +  timeMs;
  text(s,0,0);
}

void onLogEvent(LogLine line) {
  println(line);

  if (isLikelyGeolocatable(line.host) && !pendingHosts.contains(line.host)) {
    pendingHosts.add(line.host);
    while (pendingHosts.size() > maxPendingHosts) {
      pendingHosts.remove(0); // drop oldest if it's badly backed up
    }
  }
}

// Works through pendingHosts oldest-first, one attempt per call. Called
// once per frame from draw() - getLocation() is a blocking call, so doing
// at most one per frame (and only when nothing's already animating) bounds
// how much any single frame can stall for, the same reasoning as the
// !isAnimating guard everywhere else in this file. Also respects
// settleEndMs plus collapseGraceMs, so a backlog in pendingHosts can't
// skip either the settled pause or the guaranteed collapsed pause after it.
void processPendingLocation() {
  if (isAnimating || millis() < settleEndMs + collapseGraceMs || pendingHosts.isEmpty()) return;

  String host = pendingHosts.remove(0);
  Location l = getLocation(host);
  if (l != null) {
    currentHostLabel = host;
    animateTo(l, 2.0f);
  }
  // If it failed to resolve, just drop it - the next frame will try the
  // next pending host rather than getting stuck retrying this one.
}

// Hosts to never try to geolocate, regardless of what isLikelyGeolocatable()
// would otherwise say. ipinfo.io itself is the obvious one: looking up any
// host's location makes an outbound DNS+HTTP call to ipinfo.io, which Pi-hole
// then logs as a query like any other - so "ipinfo.io" comes back around
// through the same feed we're reading, and without this we'd animate to our
// own geolocation provider's server on a feedback loop.
String[] excludedHosts = { "ipinfo.io" };

// Cheap pre-filter to skip hosts that are never going to resolve to a real
// public location, before spending a blocking DNS+HTTP round trip on them.
// Most of what actually comes through Pi-hole's query log is PTR reverse
// lookups (*.in-addr.arpa / *.ip6.arpa) or local mDNS names (*.local),
// neither of which are real internet hostnames.
boolean isLikelyGeolocatable(String hostname) {
  String h = hostname.toLowerCase();
  if (h.endsWith(".arpa") || h.endsWith(".local")) return false;
  for (String excluded : excludedHosts) {
    if (h.equals(excluded)) return false;
  }
  return true;
}


void splashScreen() {
  InetAddress ip;
  try {
    ip = InetAddress.getLocalHost();
    System.out.println("Your current IP address : " + ip.getHostAddress());
  } 
  catch (Exception e) {
    e.printStackTrace();
  }
}

void animateTo(Location l, float speedSec) {
  if(l != null) animateTo(l.lon, l.lat, speedSec);
}

void animateTo(float lon, float lat, float speedSec) {
  if(!isAnimating) {
    // Previously registered aniStarted()/aniEnded() as onStart/onEnd
    // callbacks here, and separately tracked isAnimating against known
    // timing (see below) - both wrote to the same flag and raced each
    // other, which is why it never reliably reflected reality. Removed
    // the callback registration; tracking it ourselves is enough.
    // angleX is negated relative to real longitude - the globe's texture
    // wrapping (or the rotateY(angleX + HALF_PI) convention below) runs
    // the opposite way round, confirmed by New York (lon -74, western
    // hemisphere) otherwise landing near +74E (Kazakhstan/China border) -
    // this was presumably wrong for every prior live animation too, just
    // never checked against a specific known city until now.
    float targetAngleX = radians(-lon);
    // Ani tweens linearly from the CURRENT angleX to targetAngleX - with no
    // adjustment, two points on opposite sides of the antimeridian (e.g.
    // lon 170 and lon -170, only 20 degrees apart) spin the long way round
    // (340 degrees) instead of the short way, because -170 and +170 are far
    // apart numerically despite being close on the globe. Shifting the
    // target by a multiple of TWO_PI so the delta from the current angle is
    // within (-PI, PI] makes Ani take the short path instead; angleX is
    // then free to drift outside (-PI, PI] over repeated trips, which is
    // harmless since rotateY() is periodic.
    float deltaX = targetAngleX - angleX;
    while (deltaX > PI) {
      targetAngleX -= TWO_PI;
      deltaX -= TWO_PI;
    }
    while (deltaX < -PI) {
      targetAngleX += TWO_PI;
      deltaX += TWO_PI;
    }
    aniX = new Ani(this, speedSec, "angleX", targetAngleX, easing);
    aniY = new Ani(this, speedSec, "angleY", radians(lat), easing);
    isAnimating = true;
    animEndMs = millis() + (long)(speedSec * 1000);

    aniBlipStretch = new Ani(this, 0.3f, "blipStretch", 0, easing); // ease back to a plain circle, not an instant snap
  }
}

// Disabled - leftover from an earlier design (playHead, its only output,
// isn't read by anything currently active) and actively broken against
// the current animation system: aniX.pause()/resume() freezes the Ani
// tween, but isAnimating/animEndMs is our own separate millis()-based
// timer that keeps counting down regardless of the pause. Touching the
// screen mid-animation froze the globe while draw() still concluded the
// animation had finished on schedule, settling on a label for a
// location the globe hadn't actually reached - then mouseReleased()
// resumed the stale tween in the background, out of sync with the UI.
/*
void mousePressed() {
  if(aniX != null) aniX.pause();
  if(aniY != null) aniY.pause();
  wheelUpdated(mouseX - width/2, mouseY - height/2);
}

void mouseDragged() {
  wheelUpdated(mouseX - width/2, mouseY - height/2);
}

void mouseReleased() {
  if(aniX != null) aniX.resume();
  if(aniY != null) aniY.resume();
  wheelUpdated(mouseX - width/2, mouseY - height/2);
}

void wheelUpdated(int dx, int dy) {
  float a = atan2(dx, dy);
  float d = (float) Math.sqrt(dx*dx + dy*dy);

  if (d >= interactionBoundary/2 && d <= height/2) {
    playHead = HALF_PI-a;
  }
}
*/

// Tracks the angular speed and direction of the drag itself - degrees
// per second, signed (positive = clockwise/forward, negative =
// counterclockwise/backward) - and fires onDragEvent() with it. Only the
// ANGLE DELTA since the last drag event matters, not the absolute angle,
// so mousePressed() just records a starting angle and zeroes the speed
// rather than computing a rate against a stale previous touch.
void mousePressed() {
  touchAngle = atan2(mouseX - width/2, mouseY - height/2);
  lastTouchMs = millis();
  angularSpeed = 0;
}

void mouseDragged() {
  float angle = atan2(mouseX - width/2, mouseY - height/2);

  // Raw angle - angle is in (-TWO_PI, TWO_PI), and wraps at the 0/360
  // boundary (e.g. 359deg -> 1deg is really a +2deg turn, not -358deg) -
  // normalize into (-PI, PI] so a drag across that boundary doesn't
  // register as a huge jump the wrong way.
  float delta = angle - touchAngle;
  while (delta > PI) delta -= TWO_PI;
  while (delta < -PI) delta += TWO_PI;

  long now = millis();
  float dtSec = (now - lastTouchMs) / 1000.0f;
  if (dtSec > 0.001f) { // guard against a near-zero interval between events
    // Raw event-to-event rate is jittery - drag events don't arrive at
    // even intervals, so a tiny dtSec spikes the instantaneous reading.
    // Smooth it with an exponential moving average instead of firing
    // the raw value straight out.
    float rawSpeed = degrees(delta) / dtSec;
    angularSpeed = lerp(angularSpeed, rawSpeed, angularSpeedSmoothing);
  }

  touchAngle = angle;
  lastTouchMs = now;

  onDragEvent(angularSpeed);
}

void mouseReleased() {
  angularSpeed = 0;
  onDragEvent(angularSpeed); // signals the drag ended, to anything listening
}

// Fired on every drag update (and once more, at 0, on release) with the
// current smoothed angular speed - degrees/sec, signed for direction.
// Not wired to anything yet; hook in here when there's something to
// drive with it.
void onDragEvent(float speedDegPerSec) {
}

// Floor between outbound ipinfo.io calls - deliberately below the ~3.5s an
// animation+settle cycle normally takes on the success path, so it never
// slows down ordinary operation. It only bites during a run of cache
// misses that fail fast (e.g. a burst of NXDOMAINs), which would otherwise
// hammer ipinfo.io with no gap at all. Cache hits never reach this check.
long lastIpinfoRequestMs = 0;
int ipinfoMinIntervalMs = 2000;

Location getLocation(String hostname) {
  Location thisLocation = hostLocations.get(hostname);
  if (thisLocation == null) {
    if (millis() - lastIpinfoRequestMs < ipinfoMinIntervalMs) {
      return null; // rate-limited - drop this attempt, next pending host gets a turn next frame
    }
    lastIpinfoRequestMs = millis();

    HttpURLConnection conn = null;
    try {
      // DNS resolution has no built-in timeout in Java - bound it
      // ourselves the same way we now bound the HTTP call below, since an
      // unbounded blocking call here is exactly the bug we already found
      // and fixed once tonight for Pi-hole.
      InetAddress address = resolveWithTimeout(hostname, 3000);

      URL url = new URL("https://ipinfo.io/" + address.getHostAddress() + "?token=" + ipinfoToken);
      conn = (HttpURLConnection) url.openConnection();
      conn.setConnectTimeout(3000);
      conn.setReadTimeout(3000);

      JSONObject json = parseJSONObject(logLines.readBody(conn));
      String loc = json.getString("loc", null);
      if (loc != null) {
        String lnlat[] = loc.split(",");
        thisLocation = new Location(float(lnlat[1]), float(lnlat[0]));
        hostLocations.put(hostname, thisLocation);
        saveLocationCache(); // write-through so the cache survives an unclean restart
      }
    }
    catch(Exception e) {
      println("getLocation() failed for " + hostname + ": " + e.getMessage());
    }
    finally {
      if (conn != null) conn.disconnect();
    }
  }
  //else println("location from cache");

  return(thisLocation);
}

// Loads hostLocations from disk on startup, if a cache file exists yet.
// loadJSONObject() returns null (after printing its own error) rather than
// throwing when the file is missing, which is expected on first-ever run.
void loadLocationCache() {
  JSONObject json = null;
  try {
    json = loadJSONObject(locationCacheFile);
  }
  catch (Exception e) {
    // no cache file yet - fine, start empty
  }
  if (json == null) return;

  for (Object keyObj : json.keys()) {
    String host = (String) keyObj;
    JSONObject entry = json.getJSONObject(host);
    hostLocations.put(host, new Location(entry.getFloat("lon"), entry.getFloat("lat")));
  }
  println("Loaded " + hostLocations.size() + " cached location(s) from " + locationCacheFile);
}

// Rewrites the whole cache file with the current in-memory hostLocations.
// Called write-through (right after each new entry is added, in
// getLocation()) rather than only at shutdown, since this process gets
// killed abruptly during deploys - and could lose power in the field -
// often enough that a clean-exit-only save would lose most of a session's
// results. hostLocations only grows a new key every couple of seconds at
// most (gated by ipinfoMinIntervalMs and one lookup per animation cycle),
// so rewriting the full file each time is cheap enough not to matter.
void saveLocationCache() {
  JSONObject json = new JSONObject();
  for (String host : hostLocations.keySet()) {
    Location l = hostLocations.get(host);
    JSONObject entry = new JSONObject();
    entry.setFloat("lon", l.lon);
    entry.setFloat("lat", l.lat);
    json.setJSONObject(host, entry);
  }
  saveJSONObject(json, locationCacheFile);
}

// InetAddress.getByName() has no timeout parameter and can hang
// indefinitely on a slow/broken resolver - run it on a daemon thread and
// give up after timeoutMs rather than blocking the render loop forever.
InetAddress resolveWithTimeout(String hostname, int timeoutMs) throws Exception {
  final InetAddress[] result = new InetAddress[1];
  final Exception[] error = new Exception[1];

  Thread t = new Thread(new Runnable() {
    public void run() {
      try {
        result[0] = InetAddress.getByName(hostname);
      }
      catch (Exception e) {
        error[0] = e;
      }
    }
  });
  t.setDaemon(true);
  t.start();
  t.join(timeoutMs);

  if (t.isAlive()) throw new Exception("DNS resolution timed out for " + hostname);
  if (error[0] != null) throw error[0];
  return result[0];
}

void keyPressed() {
  if (key == '<') logLines.setSpeed(-1);
  if (key == '>') logLines.setSpeed(1);
  if (key == ' ') logLines.setSpeed(0.5f);
}
