class Location {
  float lon;
  float lat;
  
  Location(float ln, float lt) {
    lon = ln;
    lat = lt;
  }
  
  String toString() {
    return("\t" + lon + "  " + lat);
  }
}
