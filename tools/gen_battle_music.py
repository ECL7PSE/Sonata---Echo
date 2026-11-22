"""Generate the eight duel tracks.

Run with plain Python 3 (stdlib only):

    python tools/gen_battle_music.py

Each species gets its own key, mode, tempo and character. The tempo here MUST
match SPECIES_STYLE[key]["bpm"] in scripts/battle/battle.gd - the notes fall on
this grid.

Arrangement rules, so the tracks stay listenable rather than a pile of voices:
every chord is a diatonic triad of the mode, every melody note is a chord tone
of the bar it lands in, the pad is soft-edged, and only one strike sounds at a
time. The loops are seamless: voices are summed modulo the buffer, so decays
that run past the end wrap into the start instead of clicking.
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

# scale degrees, one chord per bar
PROGRESSIONS = [
    [0, 5, 3, 4],  # i - VI - iv - v
    [0, 3, 4, 0],  # i - iv - v - i
    [0, 5, 2, 4],  # i - VI - III - v
    [0, 2, 5, 4],  # i - III - VI - v
]

# Character per species: how loud each voice sits, and how busy the melody is.
# `step` is the melody grid in beats, `density` the chance a slot is played.
PROFILES = {
    "rat": dict(root=220.0, mode="minor", bpm=152, step=0.5, density=0.55,
                octave=12, pad=0.12, mel=0.20, bell=0.07, thump=0.20),
    "slime": dict(root=147.0, mode="phrygian", bpm=84, step=1.0, density=0.45,
                  octave=0, pad=0.18, mel=0.14, bell=0.16, thump=0.30),
    "bat": dict(root=330.0, mode="harmonic", bpm=138, step=0.5, density=0.50,
                octave=12, pad=0.10, mel=0.16, bell=0.09, thump=0.14),
    "mushroom": dict(root=196.0, mode="dorian", bpm=92, step=1.0, density=0.40,
                     octave=0, pad=0.18, mel=0.12, bell=0.20, thump=0.22),
    "flying_eye": dict(root=233.0, mode="minor", bpm=126, step=0.5, density=0.40,
                       octave=12, pad=0.15, mel=0.14, bell=0.12, thump=0.16),
    "goblin": dict(root=131.0, mode="minor", bpm=146, step=0.5, density=0.60,
                   octave=12, pad=0.10, mel=0.18, bell=0.06, thump=0.26),
    "mimic": dict(root=185.0, mode="harmonic", bpm=108, step=1.0, density=0.45,
                  octave=12, pad=0.15, mel=0.16, bell=0.16, thump=0.20),
    "skeleton": dict(root=147.0, mode="minor", bpm=132, step=2.0, density=0.30,
                     octave=0, pad=0.24, mel=0.10, bell=0.22, thump=0.24),
}


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


def pad(buf, start, dur, freq, gain):
    """Soft organ pipe: sine plus a whisper of second harmonic, gentle edges."""
    n = max(1, int(dur * SR))
    attack = max(1, int(0.18 * SR))
    release = max(1, int(0.22 * SR))
    w = 2.0 * math.pi * freq
    out = []
    for i in range(n):
        t = i / SR
        vibrato = 1.0 + 0.002 * math.sin(2.0 * math.pi * 4.2 * t)
        s = math.sin(w * t * vibrato) + 0.18 * math.sin(2.0 * w * t * vibrato)
        edge = min(1.0, i / attack, (n - i) / release)
        out.append(s * max(0.0, edge))
    place(buf, start, out, gain)


def pluck(buf, start, dur, freq, gain):
    """Harp-ish note: soft triangle with a fast decay."""
    n = max(1, int(dur * SR))
    w = 2.0 * math.pi * freq
    out = []
    for i in range(n):
        t = i / SR
        s = math.sin(w * t) + 0.22 * math.sin(2.0 * w * t) + 0.06 * math.sin(3.0 * w * t)
        out.append(s * math.exp(-2.6 * t) * min(1.0, t / 0.006))
    place(buf, start, out, gain)


def bell(buf, start, dur, freq, gain):
    """Church bell: harmonic partials only, so it rings instead of screeching."""
    n = max(1, int(dur * SR))
    w = 2.0 * math.pi * freq
    out = []
    for i in range(n):
        t = i / SR
        s = (math.exp(-1.1 * t) * math.sin(w * t)
             + 0.42 * math.exp(-1.8 * t) * math.sin(2.0 * w * t)
             + 0.18 * math.exp(-2.6 * t) * math.sin(3.0 * w * t))
        out.append(s * min(1.0, t / 0.004))
    place(buf, start, out, gain)


def thump(buf, start, freq, gain):
    n = max(1, int(0.18 * SR))
    out = []
    for i in range(n):
        t = i / SR
        f = freq * (1.0 - 0.25 * t / 0.18)
        out.append(math.sin(2.0 * math.pi * f * t) * math.exp(-14.0 * t))
    place(buf, start, out, gain)


def build(key, seed):
    p = PROFILES[key]
    mode = MODES[p["mode"]]
    rnd = random.Random(seed)
    beat = 60.0 / p["bpm"]
    bar = BEATS_PER_BAR * beat
    total = int(round(BARS * bar * SR))
    buf = [0.0] * total
    prog = rnd.choice(PROGRESSIONS)
    chords = [triad(mode, prog[b % len(prog)]) for b in range(BARS)]

    # One sustained chord per bar: root, third, fifth and an octave above.
    for b in range(BARS):
        start = int(b * bar * SR)
        for c in chords[b]:
            pad(buf, start, bar * 0.98, semis(p["root"], c), p["pad"] * 0.4)
        pad(buf, start, bar * 0.98, semis(p["root"], chords[b][0] - 12), p["pad"] * 0.7)

    # Melody: chord tones of the bar it lands in, one octave up so it sings.
    slots = int(round(BARS * BEATS_PER_BAR / p["step"]))
    last = -1
    for s in range(slots):
        if rnd.random() > p["density"]:
            continue
        t = s * p["step"] * beat
        b = min(BARS - 1, int(t / bar))
        tone = chords[b][rnd.randrange(3)]
        if b == last and rnd.random() < 0.5:
            continue  # leave a breath instead of repeating the same bar tone
        last = b
        freq = semis(p["root"], tone + p["octave"] + 12)
        dur = p["step"] * beat * rnd.choice([0.9, 1.7])
        pluck(buf, int(t * SR), dur, freq, p["mel"])

    # Bell on the downbeat that opens each half, one quiet answer later.
    bell(buf, 0, 2.4, semis(p["root"], chords[0][0] + 12), p["bell"])
    bell(buf, int(4 * bar * SR), 2.4, semis(p["root"], chords[4][0] + 12), p["bell"])
    if p["bell"] >= 0.12:
        bell(buf, int(6 * bar * SR), 1.8, semis(p["root"], chords[6][2] + 12), p["bell"] * 0.6)

    # Heartbeat: the bar's downbeat, and a softer one on beat three.
    for b in range(BARS):
        thump(buf, int(b * bar * SR), semis(p["root"], -24), p["thump"])
        thump(buf, int((b * bar + 2.0 * beat) * SR), semis(p["root"], -24), p["thump"] * 0.5)

    # Two soft echoes, then normalise. Linear gain only - no clipping, no drive.
    out = list(buf)
    for delay_s, gain in ((0.078, 0.16), (0.151, 0.08)):
        delay = int(delay_s * SR)
        for i in range(total):
            out[i] += gain * out[(i - delay) % total]
    peak = max(1e-9, max(abs(v) for v in out))
    scale = 0.64 / peak
    return [v * scale for v in out]


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
