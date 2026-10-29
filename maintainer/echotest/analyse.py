#!/usr/bin/env python3
"""Measure the echo in echotest recordings (BUGS-TODO 27).

play.raw is the played signal (16 kHz mono s16le: 1 s silence, 6 s speech-like bursts, 1 s silence). Each <tag>.raw
is the mic recording of one run; it starts about 0.5 s before the playback.

For each recording:
  delay    the lag with the highest correlation to the played signal (echo path + start offset)
  floor    RMS of the recording after the playback (noise floor, dBFS)
  active   RMS of the recording while the signal plays (dBFS)
  ENR      active - floor in dB: about 0 dB = no audible echo; 20 dB or more = loud echo
  corr     normalised correlation peak (0..1): how much of the played signal is in the recording

usage: analyse.py <dir with play.raw and *.raw>
"""
import glob
import os
import sys

import numpy as np

RATE = 16000


def load(p):
    return np.fromfile(p, dtype="<i2").astype(np.float64) / 32768.0


def db(x):
    return 20 * np.log10(max(x, 1e-9))


def rms(x):
    return float(np.sqrt(np.mean(x * x))) if len(x) else 0.0


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    play = load(os.path.join(d, "play.raw"))
    act = play[RATE:RATE * 7]
    print(f"{'tag':12} {'delay ms':>8} {'floor dB':>9} {'active dB':>9} {'ENR dB':>7} {'corr':>5}")
    for p in sorted(glob.glob(os.path.join(d, "*.raw"))):
        tag = os.path.basename(p)[:-4]
        if tag == "play":
            continue
        rec = load(p)
        if len(rec) < RATE * 9:
            print(f"{tag:12} too short ({len(rec)} samples)")
            continue
        # correlation of the active part of the signal against the recording, lags 0..2 s
        n = 1 << int(np.ceil(np.log2(len(rec) + len(act))))
        c = np.fft.irfft(np.fft.rfft(rec, n) * np.conj(np.fft.rfft(act, n)), n)[: RATE * 3]
        lag = int(np.argmax(np.abs(c)))            # recording index where the active part starts
        seg = rec[lag:lag + len(act)]
        corr = abs(c[lag]) / (np.linalg.norm(act) * max(np.linalg.norm(seg), 1e-12))
        start = max(lag - RATE, 0)                  # recording index where play.raw starts
        floor = rms(rec[start + RATE * 7 + RATE // 2:])   # after the playback: the noise suppressor has settled
        active = rms(seg)
        print(f"{tag:12} {(lag - RATE) * 1000 / RATE:8.0f} {db(floor):9.1f} {db(active):9.1f} "
              f"{db(active) - db(floor):7.1f} {corr:5.2f}")


if __name__ == "__main__":
    main()
