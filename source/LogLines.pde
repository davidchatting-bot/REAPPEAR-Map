class LogLines {
  ArrayList<LogLine> logLines = new ArrayList<LogLine>();
  boolean timeTicking = false;
  float speed = 1.0f;
  long lastTickMs = 0;
  
  long firstTimeLineTimeMs = 0;
  long timeLineTimeMs = 0;
  
  boolean online = true;
  int maxIntervalMs = 60000;

  // Cap on retained records - without this logLines grows forever on a
  // continuously-running kiosk app and eventually exhausts memory.
  int maxLogLines = 2000;

  // Pi-hole v6 session state (v6 auth is session-based via /api/auth,
  // not the old v5 "&auth=<key>" query-string token)
  String piHoleSid = null;
  long sidExpiresAtMs = 0;

  LogLines() {
  }
  
  LogLines(String file) {
    parseFile(file);
  }
  
  long tick() {
    long now = new Date().getTime();
    
    if(timeTicking && lastTickMs > 0) {
      long dt = (long) ((now - lastTickMs) * speed);
      if(abs(dt) < maxIntervalMs) produceRecords(timeLineTimeMs, timeLineTimeMs + dt);
      
      timeLineTimeMs += dt;
    }
    lastTickMs = now;   
    
    return(timeLineTimeMs);
  }
  
  void produceRecords(long t1, long t2) {
    long tmin = t1 < t2 ? t1 : t2;
    long tmax = t1 > t2 ? t1 : t2;
    
    try {
      for (int i = 0; i < logLines.size(); i++) {
        LogLine l = logLines.get(i);
        if(l.timestamp > tmin && l.timestamp < tmax) {
          onLogEvent(l);
        }
      }
    }
    catch(Exception e) {}
  }
  
  void start(long now) {
    setTimeLineTime(now);
    timeTicking = true;
  }
  
  void start() {
    setTimeLineTime(new Date().getTime());
    timeTicking = true;
  }
  
  void stop() {
    timeTicking = false;
  }
  
  void setTimeLineTime(long t) {
    timeLineTimeMs = t;
  }
  
  void setSpeed(float s) {
    speed = s;
  }

  LogLine getFirstLogLine() {
    LogLine firstLogLine = null;
    
    if(logLines.size() > 0){
      firstLogLine = logLines.get(0);
    }
    
    return(firstLogLine);
  }
  
  LogLine getLastLogLine() {
    LogLine lastLogLine = null;
    
    if(logLines.size() > 0){
      lastLogLine = logLines.get(logLines.size()-1);
    }
    
    return(lastLogLine);
  }
  
  long getFirstTimestamp() {
    long timestamp = 0;
    
    LogLine firstLogLine = getFirstLogLine();
    if(firstLogLine != null) timestamp = firstLogLine.timestamp;
    
    return(timestamp);
  }
  
  long getLastTimestamp() {
    long timestamp = new Date().getTime();
    
    LogLine lastLogLine = getLastLogLine();
    if(lastLogLine != null) timestamp = lastLogLine.timestamp;
    
    return(timestamp);
  }
  
  //void list() {
  //  list(logLines.size());
  //}
  
  //void list(int n) {
  //  try {
  //    for (int i = 0; i < logLines.size() && i < n; i++) {
  //      LogLine l = logLines.get(i);
  //      println(l);
  //    }
  //  }
  //  catch(Exception e) {}
  //}
  
  // POST {"password": piHoleKey} to /api/auth and store the returned
  // session id (sid) plus when it expires, per Pi-hole v6's session model.
  void authenticate() {
    HttpURLConnection conn = null;
    try {
      URL url = new URL("http://" + piholeserver + "/api/auth");
      conn = (HttpURLConnection) url.openConnection();
      conn.setConnectTimeout(3000);
      conn.setReadTimeout(3000);
      conn.setRequestMethod("POST");
      conn.setRequestProperty("Content-Type", "application/json");
      conn.setDoOutput(true);

      String body = "{\"password\":\"" + piHoleKey + "\"}";
      try (OutputStream os = conn.getOutputStream()) {
        os.write(body.getBytes("UTF-8"));
      }

      JSONObject json = parseJSONObject(readBody(conn));
      JSONObject session = json.getJSONObject("session");
      String sid = session.getString("sid", null);

      if (session.getBoolean("valid") && sid != null) {
        piHoleSid = sid;
        int validitySec = session.getInt("validity");
        // refresh a little early so we don't get caught out mid-request
        sidExpiresAtMs = new Date().getTime() + (validitySec * 1000L) - 5000L;
      } else {
        piHoleSid = null;
      }
    }
    catch (Exception e) {
      println("Pi-hole authenticate() failed: " + e.getMessage());
      piHoleSid = null;
    }
    finally {
      if (conn != null) conn.disconnect();
    }
  }

  void updateRecords() {
    if (!online) return;

    try {
      boolean freshAuth = false;
      if (piHoleSid == null || new Date().getTime() >= sidExpiresAtMs) {
        authenticate();
        freshAuth = true;
      }
      if (piHoleSid == null) return; // couldn't get a session this cycle, try again next tick

      JSONObject json = fetchQueries(piHoleSid);

      // Only worth re-authenticating and retrying if we used a cached session -
      // if we just freshly authenticated and it still failed, retrying with the
      // same fresh session won't help and just doubles our worst-case blocking time.
      if (json == null && !freshAuth) {
        authenticate();
        if (piHoleSid == null) return;
        json = fetchQueries(piHoleSid);
      }

      if (json != null) parseRecords(json.getJSONArray("queries"));
    }
    catch (Exception e) {
      println("Pi-hole updateRecords() failed: " + e.getMessage());
    }
  }

  // GET /api/queries?length=15 with the session id in the "sid" header.
  // Returns null on a 401 (session expired/invalid) so the caller can re-auth.
  JSONObject fetchQueries(String sid) {
    HttpURLConnection conn = null;
    try {
      URL url = new URL("http://" + piholeserver + "/api/queries?length=15");
      conn = (HttpURLConnection) url.openConnection();
      conn.setConnectTimeout(3000);
      conn.setReadTimeout(3000);
      conn.setRequestMethod("GET");
      conn.setRequestProperty("sid", sid);

      if (conn.getResponseCode() == 401) return null;

      return parseJSONObject(readBody(conn));
    }
    catch (Exception e) {
      println("Pi-hole fetchQueries() failed: " + e.getMessage());
      return null;
    }
    finally {
      if (conn != null) conn.disconnect();
    }
  }

  String readBody(HttpURLConnection conn) throws IOException {
    try (BufferedReader br = new BufferedReader(new InputStreamReader(conn.getInputStream(), "UTF-8"))) {
      StringBuilder sb = new StringBuilder();
      String line;
      while ((line = br.readLine()) != null) sb.append(line);
      return sb.toString();
    }
  }

  // data/pi-hole.json is a legacy sample captured from the old v5 API
  // (rows are positional arrays: [time, type, domain, ...]), kept for
  // reference. This is a different shape to the live v6 records below
  // and isn't wired up to LogLines(String) any more.
  void parseFile(String file) {
    JSONObject json = loadJSONObject(file);
    JSONArray data = json.getJSONArray("data");
    for (int n = 0; n < data.size(); ++n) {
      JSONArray record = data.getJSONArray(n);
      long time = (long) record.getInt(0) * 1000;
      String host = record.getString(2);
      addRecord(time, host);
    }
  }

  // v6's /api/queries returns an array of objects (not positional arrays),
  // e.g. {"time": 1789578898.97, "domain": "example.com", ...}, newest
  // record first - walk it back-to-front so addRecord() sees them in the
  // ascending chronological order it assumes.
  void parseRecords(JSONArray data) {
    for (int n = data.size() - 1; n >= 0; --n) {
      parseRecord(data.getJSONObject(n));
    }
  }

  void parseRecord(JSONObject record) {
    long time = (long) (record.getDouble("time") * 1000);

    String host = record.getString("domain");
    println(host);
    addRecord(time, host);
  }
  
  void addRecord(long time, String host) {
    //Assumes this is called chronlogically
    try{
      LogLine lastLogLine = getLastLogLine();
      LogLine thisLogLine = new LogLine(time, host);
      if(lastLogLine == null || (time >= lastLogLine.timestamp && !thisLogLine.equals(lastLogLine))) {
        logLines.add(thisLogLine);
        while (logLines.size() > maxLogLines) {
          logLines.remove(0);
        }
        onLogEvent(thisLogLine); // live list update - see the sketch's onLogEvent()
      }
    }
    catch(Exception e) {
    }
  }
}
