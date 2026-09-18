class LogLine {
  long timestamp;
  String host;
  
  LogLine(long t, String h) {
    timestamp = t;
    host = h;
  }
  
  boolean equals(Object other) {
    if (!(other instanceof LogLine)) return false;
    LogLine otherLogLine = (LogLine) other;
    return(otherLogLine.timestamp == this.timestamp && otherLogLine.host.equals(this.host));
  }

  int hashCode() {
    return Long.valueOf(timestamp).hashCode() * 31 + host.hashCode();
  }
  
  String toString() {
    return("" + timestamp + "  " + host);
  }
}
