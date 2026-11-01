# Vendored libraries

- `opus-decoder.min.js`: opus-decoder 0.7.12 from wasm-audio-decoders,
  Copyright 2021-2026 Ethan Halsall, MIT licence.
  https://github.com/eshaz/wasm-audio-decoders
  libopus itself is BSD-licensed (Xiph.Org Foundation).
  Used because the browser's built-in WebCodecs decoder is only available on
  HTTPS pages, and the join page is served over plain HTTP on the LAN.
