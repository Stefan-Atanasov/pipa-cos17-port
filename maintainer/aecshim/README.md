# pipa AEC wrapper (BUGS-TODO 27, step 5w)

The pipa DSP echo canceller cancels nothing in the VoIP path. Apps that use the system AEC (PUBG/BGMI voice chat,
OPPO call sharing) send the speaker sound back to the far end. This wrapper adds a software echo canceller in the
audio HAL process.

## How it works

- Step 5w renames the vendor HAL to `vendor/lib/hw/audio.primary.kona_real.so` and installs this wrapper as
  `audio.primary.kona.so`. The HAL service loads the wrapper; the wrapper loads the real HAL and patches the function
  pointers of the real device and its streams in place (no trampolines).
- Every PCM output stream (not offload, not direct PCM) copies what it writes into a reference ring (mono, 48 kHz,
  positions on CLOCK_MONOTONIC). It copies only while an AEC input is open.
- Every `AUDIO_SOURCE_VOICE_COMMUNICATION` input with 16-bit mono at 8, 16 or 48 kHz gets an AOSP WebRTC AEC instance
  (`vendor/lib/soundfx/libaudiopreprocessing.so`, uuid bb392ec0-..., `AEC_PARAM_MOBILE_MODE` = 0, so AEC3 and not
  AECM). Each 10 ms block: the matching reference block goes to `process_reverse`, then the mic block to `process`.
  Reads that are not whole 10 ms blocks go through two FIFOs (10 ms more latency).
- AEC3 finds the delay itself. A writer may run ahead of real time up to 800 ms; the reader follows the clock.
- AGC2 (same library, same session) adds a fixed gain after the AEC, default 24 dB, limiter on
  (`persist.vendor.audio.pipa_aec_gain`, 0-30). The voice-chat mic path is quiet (talker at -32..-40 dBFS in calls).
- The reference is placed at the HAL's played time (`get_presentation_position`), else at the write time.
- A fresh AEC for each input. Reuse of the learned state (`persist.vendor.audio.pipa_aec_keep=1`) gave more start
  echo in tests.
- The DSP keeps its own device choice (`SPEAKER_TMIC_MODE_MULTI_AEC_NS`) and its noise suppression.
- Off switch for tests: `setprop persist.vendor.audio.pipa_aec 0`. The wrapper reads it when an input opens.
- Log tag `pipa_aec`: outputs, AEC creation, and at input close the chunk counts and resyncs.

## Build

`sh build.sh` (NDK 30, armv7a API 30; the vendor audio HAL is 32-bit). `include/` holds the AOSP android-11.0.0_r48
headers (libhardware, system/media, system/core). The output goes to `out/` and `port-rom/pipa_aec/` (step input).

## Live test (no ROM build)

Copy `/vendor/lib/hw` to `/data/local/tmp/hw` with the same labels, add the real HAL as
`audio.primary.kona_real.so` and the wrapper as `audio.primary.kona.so`, bind the folder over `/vendor/lib/hw`
with `su -M`, then `setprop ctl.restart vendor.audio-hal` and `setprop ctl.restart audioserver`. A reboot removes it.

## Results (2026-11-06, pt63, echotest volume 5)

| Case | Echo or level |
|---|---|
| Baseline VOICE_COMMUNICATION, playback | -8.9 dBFS echo |
| Wrapper, playback (3 runs) | -26 / -35 / -39 dBFS mean; most 0.5 s windows at the floor (-75..-85) |
| Near-end source (PC speaker), no playback | wrapper off -31, on -30 dBFS (no change) |
| Double talk (echo 20 dB above the talker) | near-end partly ducked (normal for AEC3) |

Call sharing test with a real call (2026-11-06): echo gone after the start (AEC3 needs 2-3 s, up to ~10 s in a
call); some echo in double talk; the talker was quiet before the AGC (24 dB: better, still a bit quiet).
The plain mic path (no DSP preprocessing) is louder but has 34 dB more room noise: not used.

Ideas not done: a delay hint from the output latency, reference only from speaker outputs, stereo inputs.
