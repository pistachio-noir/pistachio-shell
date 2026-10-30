#!/usr/bin/env python3
"""Writes src/sounds/notification.wav, the shell's notification sound (Notifs plays it with pw-play).

A soft two-note chime, A5 then E6, each a sine with a little of its octave, a 4 ms rise and a quick
fall, about a third of a second, quiet (its peak is -14 dBFS) so it sits under music. No sound theme
was installed on the owner's machine, so the shell brings its own. Run it again after changing it.
"""

import math
import os
import struct
import wave

RATE = 44100
LENGTH = 0.36  # seconds
PEAK = 10 ** (-14 / 20)
NOTES = [(880.0, 0.0), (1318.5, 0.07)]  # frequency (Hz), start (s)


def sample(t):
    total = 0.0
    for freq, start in NOTES:
        u = t - start
        if u < 0:
            continue
        envelope = min(1.0, u / 0.004) * math.exp(-u / 0.09)
        total += envelope * (math.sin(2 * math.pi * freq * u) + 0.25 * math.sin(4 * math.pi * freq * u))
    return total


def main():
    frames = [sample(i / RATE) for i in range(int(RATE * LENGTH))]
    scale = PEAK / max(abs(f) for f in frames)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "sounds", "notification.wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", round(f * scale * 32767)) for f in frames))
    print("wrote", os.path.normpath(path))


if __name__ == "__main__":
    main()
