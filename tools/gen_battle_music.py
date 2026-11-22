"""Generate the eight duel tracks.

Run with plain Python 3 (stdlib only):

    python tools/gen_battle_music.py

Each species gets its own key, tempo and groove. The tempo here MUST match
SPECIES_STYLE[key]["bpm"] in scripts/battle/battle.gd - the notes fall on this
grid.

The arrangement is a duel groove, not an organ drone: a kick and a snare that
push the bar, hats that tick the sixteenths, a syncopated bass, chord stabs on
the offbeats and a bright lead that answers itself. The busier the species, the
more sixteenth-note hats, the more bass movement and the harder the lead hits,
so the music itself says how much trouble you are in.

The loops are seamless: voices are summed modulo the buffer, so decays that run
past the end wrap into the start instead of clicking.
"""

import math
import os
import random
import struct
import wave

SR = 22050
BARS = 8
BEATS_PER_BAR = 4
STEPS_PER_BAR = 16  # sixteenth notes

# semitone offsets from the root
MODES = {
    "minor": [0, 2, 3, 5, 7, 8, 10],
    "harmonic": [0, 2, 3, 5, 7, 8, 11],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
}

# One chord per bar, in scale degrees.
PROGRESSIONS = [
    [0, 5, 3, 4],  # i - VI - iv - v
    [0, 3, 4, 0],  # i - iv - v - i
    [0, 5, 2, 4],  # i - VI - III - v
    [0, 2, 5, 4],  # i - III - VI - v
]

# Groove per species. `drive` is how hard the drums push: 1 is a plain backbeat,
# 3 is a wall of sixteenths. `lead` is the top hook's busyness, 0..1.
PROFILES = {
    "rat": dict(root=220.0, mode="minor", bpm=124, drive=1, lead=0.45,
                bass_groove=0.55, stab=0.35),
    "mushroom": dict(root=196.0, mode="dorian", bpm=112, drive=1, lead=0.30,
                     bass_groove=0.40, stab=0.25),
    "slime": dict(root=155.56, mode="phrygian", bpm=128, drive=2, lead=0.40,
                  bass_groove=0.60, stab=0.30),
    "flying_eye": dict(root=233.08, mode="minor", bpm=134, drive=2, lead=0.55,
                       bass_groove=0.55, stab=0.35),
    "goblin": dict(root=130.81, mode="minor", bpm=140, drive=2, lead=0.60,
                   bass_groove=0.70, stab=0.40),
    "bat": dict(root=164.81, mode="harmonic", bpm=144, drive=3, lead=0.65,
                bass_groove=0.75, stab=0.45),
    "skeleton": dict(root=146.83, mode="minor", bpm=150, drive=3, lead=0.50,
                     bass_groove=0.70, stab=0.55),
    "mimic": dict(root=185.0, mode="harmonic", bpm=156, drive=3, lead=0.75,
                  bass_groove=0.85, stab=0.60),
}

# Kick, snare and hat patterns, in sixteenths inside a bar.
KICK_PATTERNS = {
    1: [0, 8],
    2: [0, 6, 8, 14],
    3: [0, 3, 6, 8, 11, 14],
}
SNARE_STEPS = [4, 12]
# Bass: root, fifth, octave and the pushes in between.
BASS_STEPS = [0, 3, 6, 8, 10, 14]
BASS_SHAPE = [0, 0, 7, 12, 0, 7]
# Chord stabs land on the offbeats, the way a funk rhythm section leans.
STAB_STEPS = [2, 6, 10, 14]


def semis(root, n):
    return root * (2.0 ** (n / 12.0))


def place(buf, start, samples, gain=1.0):
    """Add a rendered voice into the loop, wrapping the tail to the start."""
    n = len(buf)
    for i, v in enumerate(samples):
        buf[(start + i) % n] += v * gain


def triad(mode, degree):
    """Diatonic triad on a scale degree, as semitone offsets from the root."""
    def at(d):
        return mode[d % 7] + 12 * (d // 7)
    return [at(degree), at(degree + 2), at(degree + 4)]


def kick(buf, start, gain):
    """Thump: pitch drops fast, body dies quickly."""
    n = int(0.22 * SR)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 48.0 + 130.0 * math.exp(-32.0 * t)
        phase += 2.0 * math.pi * f / SR
        out.append(math.sin(phase) * math.exp(-13.0 * t))
    place(buf, start, out, gain)


def snare(buf, start, gain, rnd):
    """Backbeat: a body tone plus a short hiss of noise."""
    n = int(0.17 * SR)
    out = []
    for i in range(n):
        t = i / SR
        hiss = rnd.uniform(-1.0, 1.0) * math.exp(-26.0 * t)
        body = math.sin(2.0 * math.pi * 190.0 * t) * math.exp(-30.0 * t) * 0.6
        out.append((hiss * 0.8 + body) * min(1.0, t / 0.002))
    place(buf, start, out, gain)


def hat(buf, start, gain, rnd, open_hat=False):
    """Tick: high noise, no body, gone in a blink."""
    dur = 0.11 if open_hat else 0.035
    n = int(dur * SR)
    out = []
    prev = 0.0
    for i in range(n):
        t = i / SR
        noise = rnd.uniform(-1.0, 1.0)
        bright = noise - prev  # crude high-pass, keeps it sibilant
        prev = noise
        out.append(bright * math.exp(-55.0 * t) * (0.55 if open_hat else 0.4))
    place(buf, start, out, gain)


def bass(buf, start, dur, freq, gain):
    """Funk bass: round body, quick decay, a touch of grit."""
    n = max(1, int(dur * SR))
    w = 2.0 * math.pi * freq
    out = []
    for i in range(n):
        t = i / SR
        s = (math.sin(w * t) + 0.28 * math.sin(2.0 * w * t)
             + 0.10 * math.sin(3.0 * w * t))
        out.append(s * math.exp(-4.2 * t) * min(1.0, t / 0.004))
    place(buf, start, out, gain)


def stab(buf, start, dur, freqs, gain):
    """Chord stab: bright, short, with the bite of a filtered keyboard."""
    n = max(1, int(dur * SR))
    out = []
    for i in range(n):
        t = i / SR
        s = 0.0
        for f in freqs:
            w = 2.0 * math.pi * f
            s += math.sin(w * t) + 0.22 * math.sin(2.0 * w * t) + 0.08 * math.sin(3.0 * w * t)
        out.append(s / len(freqs) * math.exp(-9.0 * t) * min(1.0, t / 0.003))
    place(buf, start, out, gain)


def lead(buf, start, dur, freq, gain):
    """Top hook: square-ish and bright, the part you hum."""
    n = max(1, int(dur * SR))
    w = 2.0 * math.pi * freq
    out = []
    for i in range(n):
        t = i / SR
        vib = 1.0 + 0.004 * math.sin(2.0 * math.pi * 5.5 * t)
        s = (math.sin(w * t * vib) + 0.35 * math.sin(3.0 * w * t * vib)
             + 0.12 * math.sin(5.0 * w * t * vib))
        out.append(s * math.exp(-3.4 * t) * min(1.0, t / 0.005))
    place(buf, start, out, gain)


def build(key, seed):
    p = PROFILES[key]
    mode = MODES[p["mode"]]
    rnd = random.Random(seed)
    beat = 60.0 / p["bpm"]
    step = beat / 4.0
    bar = BEATS_PER_BAR * beat
    total = int(round(BARS * bar * SR))
    buf = [0.0] * total
    prog = rnd.choice(PROGRESSIONS)
    chords = [triad(mode, prog[b % len(prog)]) for b in range(BARS)]

    kick_steps = KICK_PATTERNS[p["drive"]]
    hat_steps = list(range(0, STEPS_PER_BAR, 2 if p["drive"] < 3 else 1))

    for b in range(BARS):
        bar_start = int(b * bar * SR)
        chord = chords[b]
        root_tone = chord[0]

        # --- drums: the push
        for s in kick_steps:
            kick(buf, bar_start + int(s * step * SR), 0.55)
        for s in SNARE_STEPS:
            snare(buf, bar_start + int(s * step * SR), 0.30, rnd)
        for s in hat_steps:
            if rnd.random() < 0.86:
                hat(buf, bar_start + int(s * step * SR), 0.16, rnd)
        if p["drive"] >= 2 and b % 4 == 3:
            hat(buf, bar_start + int(14 * step * SR), 0.14, rnd, open_hat=True)

        # --- bass: root, fifth, octave, pushed around the beat
        for i, s in enumerate(BASS_STEPS):
            if rnd.random() > p["bass_groove"] + 0.25:
                continue
            tone = root_tone + BASS_SHAPE[i % len(BASS_SHAPE)]
            bass(buf, bar_start + int(s * step * SR), step * 1.6,
                 semis(p["root"], tone - 24), 0.42)

        # --- stabs: the chords lean on the offbeats
        for s in STAB_STEPS:
            if rnd.random() > p["stab"] + 0.35:
                continue
            freqs = [semis(p["root"], c + 12) for c in chord]
            stab(buf, bar_start + int(s * step * SR), step * 1.2, freqs, 0.20)

        # --- lead: a hook that answers itself, one bar of question and answer
        for half in range(2):
            if rnd.random() > p["lead"]:
                continue
            for s in range(8):
                if rnd.random() < 0.45:
                    continue
                beat_in_bar = half * 2.0 + s * 0.5
                b2 = min(BARS - 1, b + (1 if half == 1 else 0))
                tone = chords[b2][rnd.randrange(3)]
                if half == 1:
                    tone += 12  # the answer climbs
                lead(buf, bar_start + int(beat_in_bar * beat * SR), beat * 0.45,
                     semis(p["root"], tone + 12), 0.24)

    # Normalise. Linear gain only - no clipping, no drive.
    peak = max(1e-9, max(abs(v) for v in buf))
    scale = 0.72 / peak
    return [v * scale for v in buf]


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
    for i, key in enumerate(sorted(PROFILES)):
        samples = build(key, 1000 + i)
        path = os.path.join(out_dir, key + ".wav")
        write(path, samples)
        rms = math.sqrt(sum(v * v for v in samples) / len(samples))
        print("%-11s %5.1f s  rms %.3f  %d KB"
              % (key, len(samples) / SR, rms, os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()
