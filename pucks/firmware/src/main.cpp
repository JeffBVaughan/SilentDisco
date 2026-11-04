// SilentDisco puck: a wired-headphone Snapcast client with one button and a colour LED.
//
//   core 1 (Arduino loop)  : the Snapcast client, nothing else
//   core 0 (control task)  : Wi-Fi watch, button, LED, channel switching via JSON-RPC
//
// Button: short press = next channel, long press (1.5 s) = volume step.
// LED:    channel colour when playing, dim; blue blink while connecting; red blink = no server.

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <Adafruit_NeoPixel.h>

#include "AudioTools.h"
#include "AudioTools/AudioCodecs/CodecOpus.h"
#include "SnapClient.h"

#if __has_include("config.h")
#include "config.h"
#else
#error "Copy include/config.h.example to include/config.h and fill it in"
#endif

// ------------------------------------------------------------------ audio
I2SStream i2s;
OpusAudioDecoder opus;
WiFiClient tcp;
SnapClient snap(tcp, i2s, opus);

// ------------------------------------------------------------------ state shared with the control task
static char puckName[16];
static IPAddress serverIP;
static volatile bool serverFound = false;
static volatile bool snapStarted = false;
static String myId;                       // Snapcast client id = our MAC, as the library sends it
static String streams[8]; static int nStreams = 0;
static String currentStream;
static String groupId;
static portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;
static Preferences prefs;
static const float VOL_STEPS[] = {1.0f, 0.65f, 0.4f};
static int volStep = 0;

Adafruit_NeoPixel led(LED_COUNT, PIN_LED, NEO_GRB + NEO_KHZ800);

// ------------------------------------------------------------------ led
static uint32_t colourFor(const String& name) {
  String n = name; n.toLowerCase();
  if (n.startsWith("yellow")) return led.Color(255, 150, 0);
  if (n.startsWith("red"))    return led.Color(255, 0, 4);
  if (n.startsWith("green"))  return led.Color(0, 255, 20);
  if (n.startsWith("blue"))   return led.Color(0, 60, 255);
  return led.Color(200, 200, 200);
}
static void ledFill(uint32_t c, float k) {
  uint8_t r = ((c >> 16) & 0xff) * k, g = ((c >> 8) & 0xff) * k, b = (c & 0xff) * k;
  for (int i = 0; i < LED_COUNT; i++) led.setPixelColor(i, r, g, b);
  led.show();
}
enum LedMode { LED_BOOT, LED_WIFI, LED_NOSERVER, LED_PLAY, LED_FLASH };
static volatile LedMode ledMode = LED_BOOT;
static uint32_t flashUntil = 0;

static void ledTick() {
  uint32_t t = millis();
  float breathe = 0.5f + 0.5f * sinf(t / 400.0f);
  switch (ledMode) {
    case LED_BOOT:     ledFill(led.Color(200, 200, 200), 0.05f + 0.1f * breathe); break;
    case LED_WIFI:     ledFill(led.Color(0, 60, 255), (t / 300) % 2 ? 0.25f : 0.02f); break;
    case LED_NOSERVER: ledFill(led.Color(255, 0, 4), (t / 500) % 2 ? 0.3f : 0.02f); break;
    case LED_FLASH:    if (t < flashUntil) { ledFill(colourFor(currentStream), 1.0f); break; } ledMode = LED_PLAY; // fallthrough
    case LED_PLAY:     ledFill(colourFor(currentStream), 0.12f); break;
  }
}

// ------------------------------------------------------------------ wifi
static bool connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(puckName);
  WiFi.setSleep(false);
  for (const auto& net : WIFI_NETS) {
    Serial.printf("wifi: trying %s\n", net.ssid);
    WiFi.begin(net.ssid, net.pass);
    for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) { delay(250); ledTick(); }
    if (WiFi.status() == WL_CONNECTED) {
      Serial.printf("wifi: %s %s\n", net.ssid, WiFi.localIP().toString().c_str());
      return true;
    }
    WiFi.disconnect(true); delay(200);
  }
  return false;
}

static bool findServer() {
  if (MDNS.begin(puckName)) {
    int n = MDNS.queryService("snapcast", "tcp");
    if (n > 0) {
#if ESP_ARDUINO_VERSION >= ESP_ARDUINO_VERSION_VAL(3, 0, 0)
      serverIP = MDNS.address(0);
#else
      serverIP = MDNS.IP(0);
#endif
      MDNS.end();
      Serial.printf("server: %s via mDNS\n", serverIP.toString().c_str());
      return true;
    }
    MDNS.end();
  }
  serverIP.fromString(SERVER_FALLBACK_IP);
  WiFiClient probe;
  bool ok = probe.connect(serverIP, 1704, 1500); probe.stop();
  Serial.printf("server: %s fallback %s\n", serverIP.toString().c_str(), ok ? "ok" : "unreachable");
  return ok;
}

// ------------------------------------------------------------------ snapcast json-rpc (control task only)
static bool rpc(const char* method, JsonDocument& params, JsonDocument& result) {
  HTTPClient http;
  String url = "http://" + serverIP.toString() + ":1780/jsonrpc";
  http.begin(url); http.setTimeout(2500);
  http.addHeader("Content-Type", "application/json");
  JsonDocument req; req["id"] = 1; req["jsonrpc"] = "2.0"; req["method"] = method; req["params"] = params;
  String body; serializeJson(req, body);
  int code = http.POST(body);
  bool ok = false;
  if (code == 200) {
    DeserializationError e = deserializeJson(result, http.getStream());
    ok = !e && !result["error"].is<JsonObject>();
  } else Serial.printf("rpc %s: http %d\n", method, code);
  http.end();
  return ok;
}

// Refresh stream list and our group/stream from Server.GetStatus
static bool refreshStatus() {
  JsonDocument params, res;
  if (!rpc("Server.GetStatus", params, res)) return false;
  JsonObject server = res["result"]["server"];
  int n = 0;
  for (JsonObject s : server["streams"].as<JsonArray>()) if (n < 8) streams[n++] = s["id"].as<String>();
  String gid, sid;
  for (JsonObject g : server["groups"].as<JsonArray>())
    for (JsonObject c : g["clients"].as<JsonArray>()) {
      String cid = c["id"].as<String>();
      if (cid.equalsIgnoreCase(myId)) { gid = g["id"].as<String>(); sid = g["stream_id"].as<String>(); }
    }
  portENTER_CRITICAL(&mux);
  nStreams = n; groupId = gid; if (sid.length()) currentStream = sid;
  portEXIT_CRITICAL(&mux);
  return gid.length() > 0;
}

static bool setStream(const String& id) {
  if (!groupId.length()) return false;
  JsonDocument params, res;
  params["id"] = groupId; params["stream_id"] = id;
  if (!rpc("Group.SetStream", params, res)) return false;
  currentStream = id;
  prefs.putString("stream", id);
  flashUntil = millis() + 400; ledMode = LED_FLASH;
  Serial.printf("stream: %s\n", id.c_str());
  return true;
}

static void nextStream() {
  if (nStreams == 0) return;
  int cur = -1;
  for (int i = 0; i < nStreams; i++) if (streams[i] == currentStream) cur = i;
  setStream(streams[(cur + 1) % nStreams]);
}

static void nextVolume() {
  volStep = (volStep + 1) % 3;
  snap.setVolumeFactor(VOL_STEPS[volStep]);
  prefs.putInt("vol", volStep);
  flashUntil = millis() + 150; ledMode = LED_FLASH;
  Serial.printf("volume factor %.2f\n", VOL_STEPS[volStep]);
}

// ------------------------------------------------------------------ buttons
struct Button { int pin; bool down = false; uint32_t since = 0; bool longFired = false; };
static Button btnCh{PIN_BTN_CH}, btnVol{PIN_BTN_VOL};

static void pollButton(Button& b, void (*shortPress)(), void (*longPress)()) {
  bool pressed = digitalRead(b.pin) == LOW;
  uint32_t t = millis();
  if (pressed && !b.down) { b.down = true; b.since = t; b.longFired = false; }
  else if (pressed && b.down && !b.longFired && t - b.since > 1500) { b.longFired = true; if (longPress) longPress(); }
  else if (!pressed && b.down) { b.down = false; if (!b.longFired && t - b.since > 40 && shortPress) shortPress(); }
}

// ------------------------------------------------------------------ control task (core 0)
static void controlTask(void*) {
  uint32_t lastStatus = 0; bool applied = false;
  for (;;) {
    ledTick();
    if (WiFi.status() != WL_CONNECTED) { ledMode = LED_WIFI; delay(50); continue; }
    if (!serverFound) { delay(50); continue; }
    pollButton(btnCh, nextStream, nextVolume);
    pollButton(btnVol, nextVolume, nullptr);
    uint32_t t = millis();
    if (t - lastStatus > 3000) {
      lastStatus = t;
      if (refreshStatus()) {
        if (ledMode == LED_NOSERVER || ledMode == LED_WIFI || ledMode == LED_BOOT) ledMode = LED_PLAY;
        if (!applied) {                      // first contact: go back to the channel we were on
          applied = true;
          String want = prefs.getString("stream", "");
          if (want.length() && want != currentStream) {
            for (int i = 0; i < nStreams; i++) if (streams[i] == want) setStream(want);
          }
        }
      }
    }
    delay(20);
  }
}

// ------------------------------------------------------------------ arduino
void setup() {
  Serial.begin(115200);
  delay(300);
  snprintf(puckName, sizeof puckName, "puck-%02d", PUCK_NUMBER);
  Serial.printf("\n%s starting\n", puckName);

  pinMode(PIN_BTN_CH, INPUT_PULLUP);
  pinMode(PIN_BTN_VOL, INPUT_PULLUP);
  led.begin(); led.setBrightness(LED_BRIGHT); ledFill(led.Color(200, 200, 200), 0.1f);

  prefs.begin("puck", false);
  volStep = prefs.getInt("vol", 0);

  while (!connectWifi()) { ledMode = LED_WIFI; Serial.println("wifi: no network, retrying"); }
  myId = WiFi.macAddress();

  // I2S to the PCM5102A
  auto cfg = i2s.defaultConfig(TX_MODE);
  cfg.pin_bck = PIN_I2S_BCK; cfg.pin_ws = PIN_I2S_WS; cfg.pin_data = PIN_I2S_DATA;
  cfg.sample_rate = 48000; cfg.channels = 2; cfg.bits_per_sample = 16;
  cfg.buffer_size = 1024; cfg.buffer_count = 8;
  i2s.begin(cfg);

  xTaskCreatePinnedToCore(controlTask, "control", 8192, nullptr, 1, nullptr, 0);

  while (!findServer()) { ledMode = LED_NOSERVER; delay(2000); }
  serverFound = true;

  snap.snapProcessor().setHostName(puckName);
  snap.setServerIP(serverIP);
  snap.setVolumeFactor(VOL_STEPS[volStep]);
  if (!snap.begin()) { Serial.println("snap: begin failed"); ledMode = LED_NOSERVER; }
  else { snapStarted = true; Serial.println("snap: running"); }
}

void loop() {
  if (snapStarted) snap.doLoop();
  else delay(100);
}
