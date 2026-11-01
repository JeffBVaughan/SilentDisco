# Silent Disco App: Product and Hardware Discovery

Status: draft for decision, 2026-10-31
Repo: `SilentDisco` (empty except for an Android-flavoured `.gitignore` and MIT license)

This document flushes out everything that needs deciding before code is written:
what kind of product this is, who it is for, how audio actually reaches ears,
what hardware is involved, how the software is built, what it will cost, and
what could sink it. Section 12 lists the decisions only you can make.

---

## 1. The one question that shapes everything

"Silent disco app" can mean three very different products. Pick one before
anything else, because the audio path drives the hardware, the architecture,
the licensing exposure and the budget.

| Archetype | Audio path | Hardware | App's job | Who pays |
|---|---|---|---|---|
| **A. Event-ops tool for RF headphone events** | DJ mixer to RF transmitters to rented LED headphones (how 95% of silent discos run today) | Buy off-the-shelf transmitters and headphones | Ticketing, check-in, headphone inventory, channel voting, DJ schedule, live "which channel is winning" screen | Organizers (SaaS or per-event fee) |
| **B. Bring-your-own-device (BYOD) streaming** | DJ to server to each attendee's phone to their own earbuds | None to rent. Needs solid venue Wi-Fi or cellular | Everything in A, plus the actual audio delivery and sync | Attendees (ticket + app) or organizers |
| **C. Hybrid with Bluetooth LE Audio broadcast (Auracast)** | DJ to Auracast transmitter(s) to attendees' LE Audio earbuds or phones | Auracast transmitters (new category) | Channel discovery and switching, plus A's features | Organizers, with BYOD earbuds |

Recommendation: **build A first, design the architecture so B can be added
as a second audio path, and treat C as a 2027 bet.** Reasons:

- A is the business most organizers run today. The problems are inventory loss,
  deposits, check-in queues and knowing which channel the crowd prefers.
  Those are app-shaped problems with no audio-sync risk.
- B is where the technical novelty lives, but it has three hard dependencies:
  music licensing for digital streaming, venue network capacity, and
  Bluetooth earbud latency that you cannot control. It is a great
  differentiator once A pays the bills.
- C has the best fundamentals (tens of ms latency, unlimited receivers,
  free spectrum) but device support is still thin in 2026. See section 5.3.

If you already know you want B (for example, a consumer "silent disco
anywhere" product), skip to sections 5.2 and 8, which are written for it.

---

## 2. Users and jobs to be done

**Organizer / promoter.** Runs 1 to 20 events a month, 50 to 2,000 heads.
Wants: fewer lost headphones, faster check-in, proof of which DJ drew the crowd,
no surprise licensing letters.

**DJ.** Wants: to see the live channel share, a countdown to their slot, and
to know the transmitter is actually broadcasting. Does not want to touch the app
mid-set.

**Attendee.** Wants: pick up a headphone or join from a phone in under 30
seconds, switch channels instantly, see what song is playing, find friends by
colour, and get their deposit back without a queue.

**Venue / crew.** Wants: a headcount per channel, a battery-low list, a
"return all headphones" sweep at close, and a kill switch per channel.

Jobs that are not in scope for v1: DJ mixing software, music discovery,
general-purpose ticketing competing with Eventbrite.

---

## 3. Feature map

### MVP (archetype A)

- Event creation: name, venue, date, channels (name + colour), DJ lineup.
- Attendee check-in by QR ticket or walk-up; headphone assigned by scanning its
  tag (QR or NFC sticker on each unit).
- Headphone inventory: status per unit (out, returned, charging, lost), battery
  reported by crew, deposit held or released.
- Live channel voting: attendees tap the channel they are on (they switch on the
  headphone anyway, this is self-reported). Shows share per channel on a big
  screen and on DJ phones. Counts as "crowd applause" and is marketing content.
- Now-playing per channel: DJ or crew types it, or pulls from a Serato / rekordbox
  / Mixxx broadcast feed (phase 2).
- End-of-night sweep: list of unreturned units with attendee contact.

### Phase 2

- BYOD audio path (archetype B) as an additional "channel type".
- DJ metadata ingest (Icecast metadata, rekordbox Link, Serato Now-Playing files).
- Setlist export and licensing report (PRS / ASCAP / BMI set lists are often a
  condition of the venue licence).
- Multi-event accounts, team roles, Stripe deposits.

### Later

- Auracast channel type (archetype C).
- Crowd games tied to channel share (the channel that wins at midnight gets
  the main room lights).
- Rental marketplace (organizers renting kit to each other).

---

## 4. Hardware

### 4.1 Off-the-shelf RF kit (archetype A)

This is the proven path. Headphones have a 3-channel selector with an LED that
shows the chosen channel's colour; transmitters take a line-level feed from
each DJ.

| Item | Typical 2026 retail | Notes |
|---|---|---|
| 3-channel transmitter | about $150 (US) or about £150 (UK) each | One per channel. Quiet Events "Pulse", W Audio SDPROTX, VocoPro, Talent are common brands |
| LED headphone | $35 to $50 each new, included in bundles | 50 headphones + 3 transmitters bundle listed at about $2,450 |
| Charging cases | bundled | 20 to 25 units per case, matters for turnaround |
| Rental benchmark | $5 to $7 per headphone per night | Vendor-published figure, useful for pricing the app |

Frequency bands differ by market and are **not** interchangeable:

- EU / UK: 863 to 865 MHz (licence-free "CH70").
- US: around 915 to 926 MHz ISM band.

Buy kit for the country of operation. A mixed fleet is a support nightmare.

Hardware the app needs from this kit: nothing electrical. The integration is
a sticker. Put a QR or NFC tag on every headphone and charging case, and the
app tracks them. NFC (NTAG213 stickers, a few cents each) is faster than QR at
a dark door; Android and iPhone both read them natively.

### 4.2 Do we build our own receiver? (Short answer: no, not yet)

A custom receiver (ESP32-S3 plus a codec plus an RF or Wi-Fi front end) is
feasible as a prototype in weeks, but a sellable, certified product is a
different scale of effort:

- FCC / CE radio certification, battery safety (UN38.3), and drop testing.
- Injection-moulded enclosure tooling runs into five figures before the first
  unit ships.
- You would be competing on price with manufacturers who already ship
  headphones at $35.

The only reason to build hardware is if the app needs something the market
kit cannot do, such as per-unit telemetry (which channel each headphone is
on, battery level, location in the room). That telemetry is valuable: it
replaces self-reported channel voting with ground truth. The cheap way to get
most of it is a tiny BLE beacon tag inside the headphone cup reporting
channel and battery, which is a hardware project of a few hundred dollars
and one firmware engineer, not a product. Park this as a phase 3 experiment.

### 4.3 Auracast transmitters (archetype C)

An Auracast transmitter takes a line input and broadcasts an LC3 stream that
any LE Audio receiver in range can join, with no pairing and no receiver
limit. Google added Auracast to Android starting with Samsung One UI 7 and
Pixel 9 on Android 16, with Sony, Xiaomi and others following, and Bose began
adding it to existing headphones via firmware in 2026. Public venue trials
(Frankfurt Airport, January 2026) are only now starting.

What that means for us in 2026:

- Attendee side is a coin flip: many phones can act as "assistant" to pick a
  broadcast, but the earbuds themselves must support LE Audio and the Public
  Broadcast Profile. A large share of the crowd will have older AirPods and
  cannot join.
- Range is Bluetooth range, roughly 30 m indoors per transmitter. A big room
  needs several transmitters per channel, each broadcasting the same stream.
- Latency is tens of milliseconds and all receivers are inherently in sync,
  which is the property that BYOD over Wi-Fi struggles to get.

Treat C as the eventual replacement for RF headphones. Keep the channel model
in the app abstract enough that an Auracast channel is just another delivery
type.

### 4.4 Venue network hardware (only for archetype B)

If phones stream audio, the venue network becomes your hardware:

- Consumer routers fall over at 30 to 50 active streaming clients. Budget for
  an enterprise access point per 60 to 80 attendees (Ubiquiti U6/U7 Pro or
  Ruckus class), on 5 GHz, with band steering, and a wired uplink.
- Have a cellular fallback story. At 128 kbps per listener, 300 listeners is
  about 40 Mbps sustained upstream from your server, which is fine, but
  venue cellular coverage indoors is often not.
- A local edge server (a mini PC on the venue LAN) that receives the DJ feed
  once and serves all phones locally removes the internet from the critical
  path. This is the recommended B topology.

---

## 5. Audio delivery options in detail

### 5.1 RF (archetype A)

Nothing for the app to do. Latency is effectively zero and everyone is in
sync by physics. The app layers data on top.

### 5.2 Phone streaming (archetype B)

The hard problem is not getting audio to a phone, it is getting it to several
hundred phones so that nobody is noticeably ahead of or behind the person
next to them. Two observations make it tractable:

1. Listeners are isolated by headphones, so sync tolerance is looser than
   for speakers. Roughly 50 ms feels tight, 150 ms is noticeable when people
   sing along, 500 ms is a mess.
2. The DJ's end-to-end latency can be a couple of seconds as long as it is
   the same couple of seconds for everyone. Nobody at a silent disco is
   watching the DJ's hands closely enough to notice two seconds.

So the design is **deliberately delayed, precisely scheduled playback**, not
a race for the lowest latency:

- The DJ feed is encoded once (Opus 96 to 128 kbps) into fixed-length
  segments (for example 200 ms) with a wall-clock timestamp.
- Every phone syncs its clock against the server (NTP-style, four-way
  handshake, median of several samples, repeated every 30 s). Phones reach
  about 5 to 20 ms accuracy on a LAN.
- Every phone plays segment N at exactly `T_dj + fixed_delay`, where
  `fixed_delay` is 1.5 to 3 s. Phones buffer ahead; nobody starts a segment
  early or late.
- Drift correction is by sample-rate micro-adjustment (resample by 0.1 to
  0.5%) not by jumping, because jumps click. One open-source silent disco
  project reported that amortising a 500 ms offset takes about a minute, so
  the first join should hard-seek and then switch to micro-adjustment.
- Transport: WebSocket or WebRTC data channel for segments over LAN; LL-HLS
  as a fallback over the internet. Plain HLS and Icecast are too loose
  (seconds of uncontrolled buffering per client).

The uncontrollable part is the attendee's Bluetooth earbuds. Bluetooth
Classic (A2DP) adds 100 to 250 ms that varies by earbud model, and a phone
cannot reliably measure it. Mitigations:

- Android reports an estimated output latency via `AudioTrack.getTimestamp()`
  and `AudioManager` properties; use them, and let the attendee nudge with a
  "sync slider" if their earbuds are odd.
- Wired earbuds get a near-perfect result. Offer cheap wired earbuds at the
  door for $2 as the "pro" option, which also solves the "I forgot my
  earbuds" problem.
- Phone screen-lock must not stop playback: foreground media service on
  Android, background audio mode on iOS, wake lock plus Wi-Fi lock on
  Android.

Expect to spend most of the v1 engineering budget here if you choose B.
Budget a two-week spike (section 13) before committing.

### 5.3 Auracast (archetype C)

See 4.3. Sync and latency are solved by the transmitter. The app's role is
to list the broadcasts, show which is which (name, colour, now playing), and
hand the phone's assistant API the chosen broadcast. Android exposes this
through `BluetoothLeBroadcastAssistant`; iOS has no public API for Auracast
as of 2026, so iPhone attendees would use their earbuds' own app or the
system UI.

### 5.4 Comparison

| Criterion | RF (A) | Phone streaming (B) | Auracast (C) |
|---|---|---|---|
| Sync between listeners | perfect | 20 to 150 ms with care | near perfect |
| Latency from DJ | about 0 | 1.5 to 3 s by design | tens of ms |
| Receiver cost | $35 to $50 per unit owned, or rented | $0 (attendee's own) | $0 if earbuds are LE Audio, else cannot join |
| Scale limit | transmitter range, about 100 to 300 m | network capacity | about 30 m per transmitter, unlimited receivers |
| Licensing exposure | venue's public performance licence | adds digital transmission rights | likely treated like RF, but untested |
| App engineering risk | low | high | medium, device support risk |
| Attendee friction | none | app install, join code, battery | earbud compatibility |

---

## 6. Software architecture

Designed so the same backend and app serve A today and B or C later.

```
+-------------------+        +-------------------+        +-------------------+
| Organizer web app |        | Attendee mobile   |        | DJ / crew mobile  |
| (Next.js)         |        | app (Android 1st) |        | (same app, role)  |
+---------+---------+        +---------+---------+        +---------+---------+
          |                            |                            |
          v                            v                            v
+---------------------------------------------------------------------------+
| API + realtime (Kotlin/Ktor or Node/NestJS, WebSocket fan-out, Postgres,   |
| Redis pub/sub). Entities: Event, Channel, Slot, Unit (headphone), Checkin, |
| Vote, NowPlaying.                                                         |
+---------------------------------------------------------------------------+
          |
          v   (archetype B only)
+---------------------------------------------------------------------------+
| Audio edge: DJ line-in -> encoder (ffmpeg/Opus) -> segmenter -> LAN fan-out |
| Runs on a mini PC at the venue; mirrors to cloud for remote listeners.     |
+---------------------------------------------------------------------------+
```

Key design rules:

- **Channel is an abstraction.** A channel has a colour, a name, a DJ slot and
  a `delivery` of `rf | stream | auracast`. The attendee UI is identical.
- **Offline-first at the door.** Check-in and headphone assignment must work
  with no internet (venue basements). Local SQLite queue, sync when online.
  This alone decides against a pure web app for crew.
- **Realtime fan-out is one-way.** Vote counts and now-playing go server to
  phones over WebSocket. Phones send tiny events. Keeps the backend cheap.
- **Roles, not apps.** One mobile app with attendee, DJ and crew modes avoids
  shipping three binaries.

### 6.1 Platform choice

The repo's `.gitignore` is the Android Studio template, which suggests
Android native is the intent. Options:

| Option | Pros | Cons |
|---|---|---|
| **Kotlin + Jetpack Compose (Android first)** | Best audio control (`AudioTrack`, Media3, foreground services, LE Audio APIs are Android-only). Matches the repo | iOS is a second codebase |
| Kotlin Multiplatform + Compose Multiplatform | Shared logic and most UI, native audio per platform via `expect/actual` | Still maturing; audio layer must be written twice anyway |
| Flutter | One UI codebase, good tooling | Low-level audio and Bluetooth need platform channels; fighting the framework for B |
| React Native / Expo | Fast iteration for A-style CRUD screens | Same audio caveat as Flutter |

Recommendation: **Kotlin and Compose for the Android app, Kotlin Multiplatform
for the shared domain and networking layer so iOS can follow**, and a web app
for organizers. If the chosen archetype is A only, Flutter becomes attractive
because there is no low-level audio work.

Android specifics worth noting early:

- Media playback runs in a `MediaSessionService` foreground service with the
  `mediaPlayback` type, otherwise Android 14+ kills it.
- NFC tag reading is `NfcAdapter` reader mode; QR is CameraX plus ML Kit.
- Battery optimisation exemption prompts are rejected by Play review unless
  justified. Design for playback inside the media-session rules instead.
- Target the latest SDK; Play requires it anyway for new apps.

---

## 7. Attendee flow (archetype A, with B additions in brackets)

1. Buys ticket (external link or in-app Stripe). Receives QR.
2. At the door, crew scans QR, taps a headphone's NFC tag. Unit is bound to
   the attendee. Deposit hold is placed if configured.
3. Attendee opens the app (optional for A, required for B). Sees three
   channels with colour, DJ name, now playing. Taps the one they are on.
   [B: tapping starts the stream; a "sync check" plays a click track and lets
   them nudge the slider if their earbuds are late.]
4. During the night: vote changes update the big-screen share chart.
   Push notification when the lineup changes.
5. At exit: crew taps the headphone tag, unit returns, deposit released.
   Unreturned units show on the sweep list with the attendee's contact.

Time budget per attendee at the door: under 15 s, or the queue wraps the
block. This is the main UX constraint in archetype A.

---

## 8. Sync protocol (archetype B only)

Written out so it can be prototyped independently of the app.

```
Server clock S, phone clock P.

Clock sync (every 30 s, 8 samples, keep lowest round-trip):
  t0 = P.now()      -> request
  t1 = S.now()      (server receives)
  t2 = S.now()      (server sends)
  t3 = P.now()      <- response
  offset = ((t1 - t0) + (t2 - t3)) / 2
  rtt    = (t3 - t0) - (t2 - t1)

Segments: {seq, pts_server_ms, opus_bytes}, 200 ms each.
Playback target for seq N: pts_server_ms(N) + FIXED_DELAY_MS - offset,
  minus the phone's measured output latency.

Correction:
  |error| > 80 ms  -> hard seek (drop or insert silence)
  |error| <= 80 ms -> adjust resample ratio by clamp(error / 10 s, ±0.5%)
```

Acceptance tests for the spike: two phones with wired earbuds on one AP must
stay within 20 ms for an hour; twenty phones on one AP must not stutter;
Bluetooth earbud offset must be reported to within 50 ms after the user's
one-time sync tap.

---

## 9. Music licensing and legal

This is the part most silent disco apps get wrong, and it differs by archetype.

- **A (RF):** The venue's public performance licence (PRS/PPL in the UK,
  ASCAP/BMI/SESAC in the US) normally covers headphones as it would speakers.
  Many licensing bodies ask for set lists, so the setlist export in phase 2 is
  a real feature, not a nicety.
- **B (streaming):** Sending audio over the internet to a phone is a digital
  transmission. In the US that can bring in SoundExchange (sound recording
  performance) on top of the PRO licences; in the UK, PRS has specific online
  tariffs. If the edge server keeps everything on the venue LAN and never
  touches the internet, you have a stronger argument that this is a local
  performance, but get a music lawyer's view before launch. Budget for it.
- **C (Auracast):** Untested. It is a local radio broadcast, which argues for
  A-style treatment, but nobody has litigated it.
- **Data:** attendee contact details for deposits mean GDPR / CCPA basics:
  privacy policy, deletion, and not keeping card data (Stripe holds it).
- **Deposits:** holding a card authorisation for a $30 headphone is normal;
  charging it after 7 days for a lost unit needs clear terms at check-in.

---

## 10. Business model options

| Model | Fits | Notes |
|---|---|---|
| Per-event fee ($50 to $200) to organizers | A | Simple, matches how they already buy rentals |
| Per-headphone-night fee ($0.25 to $0.50) | A | Scales with the event; hides inside their $5 to $7 rental margin |
| Attendee ticket add-on or app purchase | B | Only works if the app is the only way to hear the music |
| Kit rental marketplace take rate | A, later | Needs scale |

Don't build an attendee subscription. People attend a silent disco twice a
year.

---

## 10a. Second product direction: multi-language audio for tours, churches and venues

Added 2026-11-01, after the home-party stack was running. What we built is
really "stations on a box": one server, N channels, every phone a tuner,
everything in sync. Swap colours for languages and it is a tour-guide and
interpretation system, which is an existing market with awkward products.

**Who buys this today, and what they put up with**

| Buyer | Current answer | Pain |
|---|---|---|
| Churches with a second-language service | Radio receiver kits (Williams Sound, Listen Technologies), $1,500 to $5,000 per 20 receivers | Handing out and collecting receivers, batteries, one channel per kit |
| Museums and fixed exhibits | Rented audio guides, or app plus cloud | Device logistics, per-visitor licence fees |
| Walking and factory tours | Sennheiser Tourguide-style RF packs | Same logistics, guide carries the transmitter, one language per transmitter |
| Conferences, breakout rooms | Interpretation booths with IR receivers | Expensive, installed by a contractor |
| App-based rivals (LiveVoice, Listen Everywhere, AudioFetch) | Phone app, cloud or dedicated Wi-Fi hardware | Needs internet or $1,000+ hardware, often priced per listener |

**Why our stack fits with few changes**

- Channel per language is a rename. The join page already takes any names.
- Runs with no internet. The box is the whole system.
- Nothing to install on the listener's phone, nothing to collect afterwards.
- Snapcast's one-second buffer does not matter: an interpreter is already a
  sentence behind the speaker.
- Opus at about 100 kbit/s per listener means a Pi-class box on its own
  hotspot serves a room; a Pi 4 or 5 serves a hall.

**What is missing, in build order**

1. *Live inputs.* Every channel is a playlist today. Interpretation needs a
   microphone per channel. Two routes, both wanted:
   - Snapcast can read an ALSA capture device directly (`alsa://` source),
     so a USB mic or a small USB interface per interpreter works with a
     config change. Good for churches, where the interpreter sits still.
   - A "broadcast from my phone" page: the interpreter opens a page, taps
     a language, and their phone's microphone becomes that channel. Browser
     to server audio over a WebSocket, server writes it into the channel's
     FIFO. This is the walking-tour version and also gives a party host an
     announcement microphone, so it is worth building regardless.
2. *Hotspot mode.* The Pi as its own access point, a QR that carries the
   Wi-Fi credentials so guests join without typing, DHCP and a captive
   landing on the join page. Already on the roadmap for the party box.
3. *Battery and range.* A USB power bank runs a Pi 3B all day. Outdoor Wi-Fi
   range from a Pi is 30 to 50 m, so for walking tours the box travels in the
   guide's bag; for fixed venues it sits by the speaker.
4. *Listener-side niceties.* Larger text, a language flag per tile, and a
   "raise hand" button are cheap and make demos land.

**What changes versus the party product**

- Sync between listeners stops mattering; latency from speaker to ear
  matters a little (keep it under about two seconds including the
  interpreter).
- Loudness and intelligibility matter more than fidelity: a speech preset
  (mono, 32 kbit/s Opus, a compressor) halves the bandwidth again and sounds
  better on a phone speaker in a pocket.
- Licensing drops out entirely for speech, which removes the party
  product's biggest legal question.

**Go-to-market, cheapest first**

1. One church with a Spanish or English second service. Fixed setup, weekly
   use, tolerant of rough edges, talks to other churches.
2. A local museum or brewery tour as the walking-tour pilot with the
   hotspot and battery.
3. Conference and event AV contractors, who already own the customer
   relationships and would rent the box as a line item.

Price anchor: a single rental RF headset kit for one event costs more than
the whole box. A box plus a year of updates at a few hundred dollars, or a
monthly fee for venues, undercuts every rival above while being simpler to
operate than any of them.

**Risks specific to this direction**

- Phone Wi-Fi power saving: a listener's phone with the screen off may drop
  the stream after a few minutes on some Android builds. The media-session
  trick in the join page helps; needs field testing per device.
- Hotspot capacity on a Pi 3B is the limiting factor; a Pi 5 or a small
  dedicated access point is the fix for rooms over about 15 listeners.
- Interpreters need a reliable mic path. The phone-mic page is convenient
  but a $30 USB mic into the box is bulletproof; offer both.

## 11. Risks, ranked

1. **Picking B first and sinking months into sync** before learning whether
   organizers want it. Mitigation: ship A, run the B spike in parallel.
2. **Bluetooth earbud latency variance** making B feel broken for a third of
   users. Mitigation: wired earbuds at the door, sync slider, honest
   expectations in onboarding.
3. **Venue network capacity** for B. Mitigation: edge server on the LAN,
   organizer-supplied APs as a documented requirement.
4. **Licensing surprise** for B. Mitigation: legal review before launch, LAN-only
   topology by default.
5. **Door throughput** for A. If check-in takes 40 s, the product fails on
   night one. Mitigation: NFC over QR, offline-first, test with a stopwatch.
6. **Auracast device support** for C. Mitigation: do not depend on it before
   2027; survey real crowds with a one-screen "does your earbud support LE
   Audio" check in the attendee app.
7. **iOS gap.** If the first customers' attendees are 60% iPhone, an Android-only
   B product is dead on arrival. A is fine Android-first because attendees don't
   need the app.

---

## 12. Decisions needed from you

Each of these changes what gets built. My default is in bold.

1. **Archetype:** **A first, B as phase 2**, or B first, or C.
2. **Market:** **US** or UK/EU (sets the RF band and the licensing body).
3. **First customer:** do you run events yourself (then the app is an internal
   tool and can be rough) or are you selling to other organizers (then
   onboarding and billing come first)? **Assumed: you run events yourself.**
4. **Platform:** **Android native first**, or cross-platform from day one.
5. **Hardware budget:** are you buying a 50 to 100 headphone kit (about
   $2,500 to $5,000) for a pilot, or renting per event?
6. **Deposits:** hold cards via Stripe, or cash and ID at the door?
7. **Scale target for the pilot:** **100 heads, 3 channels, one venue.**
8. **Name and brand:** needed before the Play Store listing and the NFC
   stickers are printed.

---

## 13. Roadmap

**Week 0 to 1: validation.**
Talk to five organizers. Ask what they lose money on (it is usually
headphones and door time). Confirm archetype.

**Week 1 to 3: B spike (parallel, only if B is in scope).**
Two Android phones, one laptop running the encoder and segmenter, the sync
protocol from section 8. Pass or fail against the acceptance tests. This is
the single biggest de-risking step in the whole plan.

**Week 2 to 6: MVP A.**
Backend (events, channels, units, check-ins, votes), Android app with
attendee and crew modes, NFC check-in, big-screen vote page (plain web).
Buy or rent a 50-unit kit and 150 NFC stickers.

**Week 7: pilot event.**
One venue, 100 heads. Measure door time per attendee, unreturned units,
vote participation. Fix what breaks.

**Week 8 to 12: phase 2.**
Deposits via Stripe, DJ now-playing ingest, setlist export, organizer web
app with billing. Second and third pilot events with an outside organizer.

**Q1 2027: B or C** depending on the spike result and what the earbud market
looks like by then.

**In parallel, once the party stack is stable:** the live-input page and
hotspot mode from section 10a, since both serve the party product too and
unlock the tour and church direction.

---

## 14. Proposed repo layout

```
SilentDisco/
  docs/                 this document, ADRs, pilot reports
  backend/              API + realtime (Kotlin/Ktor or Node), Postgres migrations
  android/              Kotlin + Compose app (attendee, DJ, crew modes)
  shared/               Kotlin Multiplatform domain + networking (added when iOS starts)
  web/                  organizer dashboard + big-screen vote page
  edge/                 (archetype B) encoder, segmenter, LAN fan-out
  hardware/             NFC tag spec, label templates, kit BOM, later any firmware
```

---

## 15. Sources used for the market and platform facts

- Android Auracast rollout: [TechCrunch, March 2025](https://techcrunch.com/2025/03/13/android-is-adding-auracast-support-which-allows-hearing-aids-to-connect-to-public-audio-broadcasts/), [Google Android blog](https://blog.google/products-and-platforms/platforms/android/le-audio-auracast-support/), [Analytics Insight on Auracast device support and venue trials](https://www.analyticsinsight.net/technology/what-is-auracast-how-bluetooth-broadcast-audio-could-change-wireless-listening)
- Phone-based sync difficulty and the amortised drift-correction figure: [digitalillusion/silentdisco on GitHub](https://github.com/digitalillusion/silentdisco), [Hacker News thread on Beatsync](https://hn-git-rm-svelte-dev-svelte.vercel.app/item/43835584), [Tildes thread on small silent disco setups](https://tildes.net/~tech/18g2/any_idea_on_running_a_very_small_silent_disco_system)
- RF kit pricing and bands: [Quiet Events 2026 pricing guide](https://www.quietevents.com/blogs/quiet-events-blog/silent-disco-rental-pricing-guide-2026), [Quiet Events Pulse 3-channel transmitter](https://www.quietevents.com/products/silent-disco-transmitter-3ch-pulse), [Quiet Events 50-headphone bundle](https://www.quietevents.com/products/party-bundle-50-headphones-3-transmitters-silent-disco-bundle-3ch-party.oembed), [W Audio SDPROTX at Showtec UK](https://shop.showtec.co.uk/products/sdprotx-3-channel-silent-disco-transmitter), [Talent 100-pack at Parts Express](https://www.parts-express.com/Talent-Silent-Disco-Prism-Color-Changing-Headphone-100-Pack-with-3-Transmitters-233-3533)
