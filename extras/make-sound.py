#!/usr/bin/env python3
"""Writes the shell's sounds to src/sounds/ (pw-play plays them). Run it again after changing one.

- notification.wav (Notifs, with a toast): a soft two-note chime, A5 then E6, each a sine with a little
  of its octave, a 4 ms rise and a quick fall, about a third of a second, quiet (its peak is -14 dBFS)
  so it sits under music. No sound theme was installed on the owner's machine, so the shell brings its own.
- tick.wav (Audio, as the volume changes; owner's pick, 31 October 2026): a 40 ms click, a high sine
  falling away in a few milliseconds, played at the new volume so the level can be heard.
  tick-wake.wav is the same after 150 ms of silence, for when the output has been quiet: the owner's
  AudioBox sleeps after a few seconds of silence and mutes for a moment as it wakes, which swallowed
  the bare click (the owner heard it after 150 and 300 ms of silence, not without, 1 November).
- shutter.wav (Screenshots, as a picture is taken; same day): a soft pop, a sine falling from 1100 to
  550 Hz in a few tens of milliseconds, after 150 ms of silence for the same reason (the owner picked
  it from three, 1 November; the first, a burst of noise, sounded harsh).
"""

import math
import os
import struct
import wave

RATE = 44100
NOTES = [(880.0, 0.0), (1318.5, 0.07)]  # frequency (Hz), start (s)


def chime(t):
    total = 0.0
    for freq, start in NOTES:
        u = t - start
        if u < 0:
            continue
        envelope = min(1.0, u / 0.004) * math.exp(-u / 0.09)
        total += envelope * (math.sin(2 * math.pi * freq * u) + 0.25 * math.sin(4 * math.pi * freq * u))
    return total


def tick(t):
    return min(1.0, t / 0.0005) * math.exp(-t / 0.006) * math.sin(2 * math.pi * 1900 * t)


def pop_frames(length):
    frames, phase = [], 0.0
    for i in range(int(RATE * length)):
        t = i / RATE
        phase += 2 * math.pi * (550 + 550 * math.exp(-t / 0.02)) / RATE
        frames.append(min(1.0, t / 0.002) * math.exp(-t / 0.03) * math.sin(phase))
    return frames


def write(name, frames, peak_db, lead=0.0):
    scale = 10 ** (peak_db / 20) / max(abs(f) for f in frames)
    frames = [0.0] * int(RATE * lead) + frames
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "sounds", name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", round(f * scale * 32767)) for f in frames))
    print("wrote", os.path.normpath(path))


def main():
    write("notification.wav", [chime(i / RATE) for i in range(int(RATE * 0.36))], -14)
    ticks = [tick(i / RATE) for i in range(int(RATE * 0.04))]
    write("tick.wav", ticks, -16)
    write("tick-wake.wav", ticks, -16, 0.15)
    write("shutter.wav", pop_frames(0.16), -18, 0.15)


if __name__ == "__main__":
    main()
