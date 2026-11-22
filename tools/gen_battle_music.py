"""Generate the eight duel tracks: gothic organs, bells and low drones.

Run with plain Python 3 (stdlib only):

    python tools/gen_battle_music.py

Each species gets its own key, mode and tempo, so two duels never sound alike.
The tempo here MUST match SPECIES_STYLE[key]["bpm"] in
scripts/battle/battle.gd - the notes fall on this grid.

The loops are seamless: every voice is summed modulo the buffer length, so
decays that run past the end wrap into the start instead of clicking.
"""

import math
import os
import random
import struct
import wave

SR = 22050
BARS = 8
BEATS_PER_BAR = 4

# semitone offsets from the root
MODES = {
    "minor": [0, 2, 3, 5, 7, 8, 10],
    "harmonic": [0, 2, 3, 5, 7, 8, 11],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
}

# degrees (0-based into the mode) for one chord per bar
PROGRESSIONS = [
    [0, 5, 3, 4],  # i - VI - III - iv
    [0, 3, 5, 4],
    [0, 6, 3, 4],
    [0, 2, 5, 4],
]

TRACKS = {
    #            root  mode        bpm   bell  organ  pluck  choir  thump  step
    "rat":        (220.0, "minor",   152,  0.20, 0.26, 0.55, 0.10, 0.30, 0.10),
    "slime":      (147.0, "phrygian", 84,  0.42, 0.30, 0.18, 0.22, 0.55, 0.00),
    "bat":        (330.0, "harmonic",138,  0.30, 0.16, 0.42, 0.18, 0.18, 0.16),
    "mushroom":   (196.0, "dorian",   92,  0.50, 0.34, 0.14, 0.26, 0.40, 0.00),
    "flying_eye": (233.0, "minor",   126,  0.34, 0.30, 0.34, 0.30, 0.22, 0.08),
    "goblin":     (131.0, "minor",   146,  0.16, 0.24, 0.50, 0.12, 0.42, 0.12),
    "mimic":      (185.0, "harmonic",108,  0.44, 0.28, 0.30, 0.20, 0.30, 0.06),
    "skeleton":   (147.0, "minor",   132,  0.46, 0.44, 0.22, 0.16, 0.36, 0.08),
}


def semis(root, n):
    return root * (2.0 ** (n / 12.0))


def place(buf, start, samples, gain=1.0):
    """Add a rendered voice into the loop, wrapping the tail to the start."""
    n = len(buf)
    for i, v in enumerate(samples):
        buf[(start + i) % n] += v * gain


def env_hit(length, attack=0.005, decay=6.0):
    out = []
    for i in range(length):
        t = i / SR
        a = min(1.0, t / attack) if attack > 0 else 1.0
        out.append(a * math.exp(-decay * t))
    return out


def organ(buf, start, dur, freq, gain, vibrato=0.004):
    """Pipe-organ pad: odd harmonics, slow vibrato, soft edges."""
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        w = 2.0 * math.pi * freq * t * (1.0 + vibrato * math.sin(2.0 * math.pi * 4.6 * t))
        s = (math.sin(w) + 0.42 * math.sin(2.0 * w) + 0.22 * math.sin(3.0 * w)
             + 0.10 * math.sin(4.0 * w))
        edge = min(1.0, i / (0.12 * SR), (n - i) / (0.2 * SR))
        out.append(s * max(0.0, edge))
    place(buf, start, out, gain)


def bell(buf, start, dur, freq, gain):
    """Toll: inharmonic partials, long tail - the signature gothic sound."""
    n = int(dur * SR)
    parts = [(1.0, 1.0, 1.6), (2.76, 0.55, 2.2), (5.40, 0.28, 3.4), (8.93, 0.14, 5.0)]
    out = []
    for i in range(n):
        t = i / SR
        s = 0.0
        for ratio, amp, decay in parts:
            s += amp * math.exp(-decay * t) * math.sin(2.0 * math.pi * freq * ratio * t)
        out.append(s * min(1.0, t / 0.002))
    place(buf, start, out, gain)


def pluck(buf, start, dur, freq, gain, bright=0.45):
    """Harpsichord-ish string: saw edge, fast decay."""
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        s = math.sin(2.0 * math.pi * freq * t)
        s += bright * math.sin(2.0 * math.pi * freq * 2.0 * t)
        s += bright * 0.5 * math.sin(2.0 * math.pi * freq * 3.0 * t)
        out.append(s * math.exp(-5.0 * t) * min(1.0, t / 0.003))
    place(buf, start, out, gain)


def choir(buf, start, dur, freq, gain):
    """Wordless choir: beating detuned sines with a slow swell."""
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        swell = math.sin(math.pi * min(1.0, i / max(1, n))) ** 0.6
        s = 0.0
        for det in (1.0, 1.005, 0.994):
            s += math.sin(2.0 * math.pi * freq * det * t + 0.4 * math.sin(2.0 * math.pi * 5.2 * t))
        out.append(s / 3.0 * swell)
    place(buf, start, out, gain)


def thump(buf, start, freq, gain):
    n = int(0.22 * SR)
    out = []
    for i in range(n):
        t = i / SR
        f = freq * (1.0 - 0.35 * t / 0.22)
        out.append(math.sin(2.0 * math.pi * f * t) * math.exp(-16.0 * t))
    place(buf, start, out, gain)


def build(key, seed):
    root, mode_name, bpm, bell_g, organ_g, pluck_g, choir_g, thump_g, step_g = TRACKS[key]
    mode = MODES[mode_name]
    rnd = random.Random(seed)
    beat = 60.0 / bpm
    total = int(round(BARS * BEATS_PER_BAR * beat * SR))
    buf = [0.0] * total
    prog = rnd.choice(PROGRESSIONS)
    bar_len = int(round(BEATS_PER_BAR * beat * SR))

    # Low drone: root and fifth, breathing slowly under everything.
    for i in range(total):
        t = i / SR
        g = 0.20 + 0.05 * math.sin(2.0 * math.pi * 0.11 * t)
        buf[i] += g * (math.sin(2.0 * math.pi * semis(root, -12) * t)
                       + 0.5 * math.sin(2.0 * math.pi * semis(root, -5) * t))

    # Organ chords: one per bar, the mode's third gives it the colour.
    for b in range(BARS):
        start = b * bar_len
        degree = prog[b % len(prog)]
        semis_root = mode[degree % len(mode)] + 12 * (degree // len(mode))
        chord = [semis_root, semis_root + (7 if rnd.random() < 0.7 else 8),
                 semis_root + 12]
        for c in chord:
            organ(buf, start, beat * BEATS_PER_BAR * 0.96, semis(root, c), organ_g * 0.55)

    # Bells on the downbeat of the first and fifth bar - the funeral marker.
    for b in (0, 4):
        bell(buf, b * bar_len, 2.6, semis(root, 12), bell_g)
    if rnd.random() < 0.6:
        bell(buf, 6 * bar_len, 2.0, semis(root, 7), bell_g * 0.6)

    # Melody: a minor-key motif, per species. Some rest, some off-beat, so the
    # ear gets a phrase rather than a metronome.
    step = beat * (0.5 if rnd.random() < 0.5 else 1.0)
    pos = 0.0
    while pos < BARS * BEATS_PER_BAR - 0.5:
        if rnd.random() < 0.62:
            deg = rnd.choice([0, 0, 2, 3, 4, 5, 4, 2])
            octave = 12 if rnd.random() < 0.35 else 0
            f = semis(root, mode[deg % len(mode)] + 12 * (deg // len(mode)) + octave)
            dur = step * rnd.choice([1.0, 1.0, 2.0])
            pluck(buf, int(pos * beat * SR), dur, f, pluck_g)
        pos += step

    # Choir pad on the second half of every other bar.
    for b in range(0, BARS, 2):
        f = semis(root, mode[prog[(b + 1) % len(prog)] % len(mode)] + 12)
        choir(buf, int((b + 2) * beat * SR), beat * 2.0, f, choir_g)

    # Heartbeat: downbeats, with an off-beat step tick for the fast movers.
    for b in range(BARS):
        thump(buf, b * bar_len, semis(root, -24), thump_g)
        thump(buf, b * bar_len + int(beat * 2 * SR), semis(root, -24), thump_g * 0.6)
        if step_g > 0.0 and rnd.random() < 0.7:
            thump(buf, b * bar_len + int(beat * 0.5 * SR), semis(root, -12), step_g)

    # Cheap wrap-around reverb, then a wide soft clip.
    delay = int(0.093 * SR)
    out = list(buf)
    for i in range(total):
        out[i] = buf[i] + 0.28 * out[(i - delay) % total]
    peak = max(1e-9, max(abs(v) for v in out))
    scale = 0.74 / peak
    return [math.tanh(v * scale * 1.3) / math.tanh(1.3) * 0.82 for v in out]


def write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-32767, min(32767, v * 32767)))) for v in samples))


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(here, "audio", "battle")
    os.makedirs(out_dir, exist_ok=True)
    for i, key in enumerate(sorted(TRACKS)):
        samples = build(key, 1000 + i)
        path = os.path.join(out_dir, key + ".wav")
        write(path, samples)
        print("%-11s %5.1f s  %d KB" % (key, len(samples) / SR, os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()
