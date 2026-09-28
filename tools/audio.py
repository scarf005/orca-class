"""Synthesizes the game's extra sound effects and music.

Run: uv run --with numpy tools/audio.py
Writes WAV effects to assets/audio/synth/ and OGG music to assets/music/ (via ffmpeg).
Everything is generated here from scratch, so no third-party samples are involved.
"""

import os
import subprocess
import wave

import numpy as np

RATE = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "synth")
MUSIC_DIR = os.path.join(ROOT, "assets", "music")
rng = np.random.default_rng(7)


def t_axis(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def env(n, attack=0.005, release=0.1, sustain=1.0, decay=0.0, total=None):
    """Linear attack, exponential-ish decay to sustain, linear release over `n` samples."""
    total = n if total is None else total
    e = np.ones(total) * sustain
    a = max(1, int(attack * RATE))
    e[:a] = np.linspace(0, 1, a)
    if decay > 0:
        d = min(total - a, int(decay * RATE))
        if d > 0:
            e[a:a + d] = sustain + (1 - sustain) * np.exp(-np.linspace(0, 5, d))
    r = min(total, max(1, int(release * RATE)))
    e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x, cutoff):
    """One-pole lowpass, applied as its exponential impulse response truncated at 1e-4."""
    alpha = 1 - np.exp(-2 * np.pi * cutoff / RATE)
    length = int(min(len(x), max(8, np.log(1e-4) / np.log(1 - alpha))))
    kernel = alpha * (1 - alpha) ** np.arange(length)
    return np.convolve(x, kernel)[: len(x)]


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def noise(seconds):
    return rng.uniform(-1, 1, int(seconds * RATE))


def sweep(f0, f1, seconds, shape="sine", curve=1.0):
    t = t_axis(seconds)
    k = (t / seconds) ** curve
    freq = f0 + (f1 - f0) * k
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    if shape == "square":
        return np.sign(np.sin(phase))
    if shape == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1) - 1
    return np.sin(phase)


def tone(freq, seconds, shape="sine", harmonics=10):
    t = t_axis(seconds)
    if shape == "sine":
        return np.sin(2 * np.pi * freq * t)
    out = np.zeros_like(t)
    for h in range(1, harmonics + 1):
        if freq * h > RATE / 2.2:
            break
        if shape == "square" and h % 2 == 0:
            continue
        amp = 1 / h
        if shape == "triangle":
            if h % 2 == 0:
                continue
            amp = (1 / h**2) * (-1) ** ((h - 1) // 2)
        out += amp * np.sin(2 * np.pi * freq * h * t)
    return out


def pad(parts, seconds):
    out = np.zeros(int(seconds * RATE))
    for start, sig in parts:
        s = int(start * RATE)
        end = min(len(out), s + len(sig))
        out[s:end] += sig[: end - s]
    return out


def write_wav(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = x / m * peak
    data = (x * 32767).astype(np.int16)
    path = os.path.join(SFX_DIR, name + ".wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())
    print("wrote", path)


# --- Sound effects -------------------------------------------------------------------------

def sfx():
    os.makedirs(SFX_DIR, exist_ok=True)
    # Tail whip: an airy swoosh that brightens, then a crack.
    n = noise(0.28)
    swoosh = highpass(n, 800) * env(len(n), 0.08, 0.1) * np.linspace(0.3, 1.0, len(n))
    crack = pad([(0.2, highpass(noise(0.03), 3000) * env(int(0.03 * RATE), 0.001, 0.02))], 0.28)
    write_wav("whip", swoosh * 0.6 + crack * 1.4)

    # Grab: a heavy clamp and a wet squeeze.
    thud = sweep(120, 45, 0.25) * env(int(0.25 * RATE), 0.002, 0.2, decay=0.1, sustain=0.2)
    squish = lowpass(noise(0.3), 700) * env(int(0.3 * RATE), 0.02, 0.2)
    write_wav("grab", pad([(0, thud), (0.03, squish * 2.0)], 0.35))

    # Stab: sharp transient, a short metallic ring, then a squelch.
    hit = highpass(noise(0.02), 2000) * env(int(0.02 * RATE), 0.001, 0.015)
    ring = sum(np.sin(2 * np.pi * f * t_axis(0.35)) for f in (523, 1307, 2011)) * env(int(0.35 * RATE), 0.001, 0.3, decay=0.05, sustain=0.2)
    wet = lowpass(noise(0.25), 500) * env(int(0.25 * RATE), 0.01, 0.2)
    write_wav("stab", pad([(0, hit * 2), (0, ring * 0.35), (0.02, wet * 2.5)], 0.4))

    # Pickup: a bright rising arpeggio.
    notes = [523.25, 659.25, 783.99, 1046.5]
    parts = [(i * 0.06, tone(f, 0.18, "square", 8) * env(int(0.18 * RATE), 0.002, 0.12)) for i, f in enumerate(notes)]
    write_wav("pickup", pad(parts, 0.45))

    # Hurt: metal clang with a low body hit.
    clang = sum(np.sin(2 * np.pi * f * t_axis(0.5)) * a for f, a in ((180, 1), (433, 0.6), (977, 0.4), (1590, 0.3))) * env(int(0.5 * RATE), 0.001, 0.45, decay=0.05, sustain=0.1)
    body = sweep(90, 40, 0.3) * env(int(0.3 * RATE), 0.001, 0.25)
    grit = lowpass(noise(0.15), 2500) * env(int(0.15 * RATE), 0.001, 0.1)
    write_wav("hurt", clang * 0.5 + pad([(0, body), (0, grit)], 0.5))

    # Pop: laser kill on a small target.
    write_wav("pop", pad([(0, sweep(1400, 200, 0.12) * env(int(0.12 * RATE), 0.001, 0.1)), (0, highpass(noise(0.03), 3000) * 0.6)], 0.15))

    # Airburst: a sharp crack and a spreading fizz.
    crack = highpass(noise(0.05), 1500) * env(int(0.05 * RATE), 0.001, 0.04)
    fizz = lowpass(noise(0.6), 3000) * env(int(0.6 * RATE), 0.01, 0.5, decay=0.1, sustain=0.3)
    boom = sweep(160, 50, 0.3) * env(int(0.3 * RATE), 0.001, 0.25)
    write_wav("airburst", pad([(0, crack * 2), (0.01, fizz), (0, boom)], 0.65))

    # Overheat: two falling alarm tones and a vent hiss.
    beeps = pad([(i * 0.18, tone(f, 0.14, "square", 6) * env(int(0.14 * RATE), 0.005, 0.03)) for i, f in enumerate((1200, 900, 1200, 900))], 0.9)
    hiss = highpass(noise(0.9), 3000) * env(int(0.9 * RATE), 0.3, 0.4) * 0.5
    write_wav("overheat", beeps + hiss)

    # FPV motor whine (loopable: whole number of cycles).
    seconds = 1.0
    t = t_axis(seconds)
    f = 240.0
    whine = sum(np.sin(2 * np.pi * f * h * t + np.sin(2 * np.pi * 7 * t) * 0.3) / h for h in range(1, 7))
    buzz = whine + lowpass(noise(seconds), 4000) * 0.3
    write_wav("buzz", buzz, 0.6)

    # Dive: rising whine.
    write_wav("dive", sweep(300, 900, 0.6, "saw", 0.6) * env(int(0.6 * RATE), 0.02, 0.1) * 0.5 + highpass(noise(0.6), 2000) * 0.15)

    # Rotor loop: blade-pass thumps at 6 Hz over a turbine hum (1.0 s = 6 thumps).
    seconds = 1.0
    t = t_axis(seconds)
    thump = np.zeros_like(t)
    for i in range(6):
        start = int(i / 6 * RATE)
        k = lowpass(noise(0.09), 300) * env(int(0.09 * RATE), 0.005, 0.08)
        thump[start:start + len(k)] += k[: len(thump) - start]
    hum = np.sin(2 * np.pi * 55 * t) * 0.3 + np.sin(2 * np.pi * 1320 * t) * 0.04
    write_wav("rotor", thump * 3.0 + hum, 0.8)

    # Fixed-wing drone prop (loop).
    t = t_axis(1.0)
    prop = sum(np.sin(2 * np.pi * 90 * h * t) / h**1.2 for h in range(1, 9))
    write_wav("jet", prop + lowpass(noise(1.0), 1800) * 0.4, 0.6)

    # Squelch: wet, resonant, bubbly.
    wet = lowpass(noise(0.35), 900) * env(int(0.35 * RATE), 0.01, 0.25)
    bubble = pad([(i * 0.07, sweep(300 + i * 90, 120, 0.06) * env(int(0.06 * RATE), 0.002, 0.04)) for i in range(4)], 0.35)
    write_wav("squelch", wet * 2 + bubble * 0.6)

    # Spore burst.
    puff = lowpass(highpass(noise(0.6), 300), 2500) * env(int(0.6 * RATE), 0.01, 0.5, decay=0.1, sustain=0.4)
    pops = pad([(rng.uniform(0.05, 0.45), sweep(900, 400, 0.03) * 0.4) for _ in range(10)], 0.6)
    write_wav("spore", puff + pops)

    # Warning beeps.
    write_wav("warn", pad([(i * 0.15, tone(880, 0.1, "square", 6) * env(int(0.1 * RATE), 0.003, 0.02)) for i in range(2)], 0.3), 0.7)

    # Lock tone: accelerating beeps rising in pitch.
    parts = []
    at = 0.0
    for i in range(8):
        parts.append((at, tone(1000 + i * 60, 0.05, "square", 6) * env(int(0.05 * RATE), 0.002, 0.01)))
        at += 0.14 * (0.85**i)
    write_wav("lock", pad(parts, 0.8), 0.6)

    write_wav("ui_move", tone(1320, 0.04, "square", 4) * env(int(0.04 * RATE), 0.001, 0.03), 0.5)
    write_wav("ui_select", pad([(0, tone(880, 0.06, "square", 6) * env(int(0.06 * RATE), 0.001, 0.03)), (0.06, tone(1320, 0.1, "square", 6) * env(int(0.1 * RATE), 0.001, 0.08))], 0.18), 0.6)
    write_wav("combo", pad([(i * 0.05, np.sin(2 * np.pi * f * t_axis(0.25)) * env(int(0.25 * RATE), 0.001, 0.22)) for i, f in enumerate((1568, 2093, 2637))], 0.4), 0.6)

    # Arcade shout stab: a fat major chord hit with a noise crack, for big call-outs.
    stab = sum(tone(f, 0.5, "saw", 12) for f in (261.6, 329.6, 392.0, 523.3)) * env(int(0.5 * RATE), 0.002, 0.35, decay=0.08, sustain=0.35)
    crack = highpass(noise(0.08), 1500) * env(int(0.08 * RATE), 0.001, 0.06)
    boom = sweep(120, 45, 0.35) * env(int(0.35 * RATE), 0.001, 0.3)
    write_wav("shout", pad([(0, lowpass(stab, 3000) * 0.5), (0, crack), (0, boom)], 0.55))

    # Combat assist chime: a clean two-tone blip, then a soft data chirp.
    blip = pad([(0, tone(1175, 0.07, "square", 4) * env(int(0.07 * RATE), 0.002, 0.03)), (0.08, tone(1568, 0.09, "square", 4) * env(int(0.09 * RATE), 0.002, 0.05))], 0.35)
    chirp = pad([(0.2, sweep(2400, 3200, 0.08) * env(int(0.08 * RATE), 0.002, 0.05) * 0.3)], 0.35)
    write_wav("ai", blip + chirp, 0.6)

    # Roar: detuned low saws with a growl envelope and a pitch sag.
    t = t_axis(1.0)
    growl = sum(sweep(70 * d, 52 * d, 1.0, "saw") for d in (1.0, 1.013, 0.987, 1.5))
    growl = lowpass(growl, 900) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t)) * env(len(t), 0.08, 0.4)
    write_wav("roar", growl + lowpass(noise(1.0), 600) * env(len(t), 0.05, 0.5) * 0.8)

    # Bullet on armor: a sharp tick, a bright metallic ring and a little grit. Must cut through gunfire.
    t = t_axis(0.16)
    ring = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, d in ((2350, 38), (3710, 52), (5200, 70))) / 3
    tick = highpass(noise(0.16), 2500) * np.exp(-t * 90)
    thud = np.sin(2 * np.pi * 180 * t) * np.exp(-t * 45)
    write_wav("hit_metal", ring * 0.8 + tick * 1.2 + thud * 0.6, 0.85)
    # Kill: a heavy low thump, a crunching mid burst and a bright crack on top.
    t = t_axis(0.5)
    thump = sweep(140, 38, 0.5, curve=0.35) * np.exp(-t * 7)
    crunch = lowpass(noise(0.5), 1800) * np.exp(-t * 14)
    crack = highpass(noise(0.5), 3500) * np.exp(-t * 60)
    write_wav("kill_crunch", np.tanh((thump * 1.4 + crunch * 1.0 + crack * 0.9) * 1.6))


def guns():
    """Coaxial gun reports, one per caliber: a sharp muzzle crack, a chest thump and a short
    mechanical clack. Bigger calibers are lower, longer and heavier. Uses its own noise so adding
    it leaves the other effects unchanged."""
    local = np.random.default_rng(805)
    for caliber, pitch, length, weight in ((8, 1.35, 0.14, 0.7), (15, 1.0, 0.2, 1.0), (20, 0.72, 0.28, 1.4)):
        t = t_axis(length)
        crack = highpass(local.uniform(-1, 1, len(t)), 2400 * pitch) * np.exp(-t * 95 / weight)
        blast = lowpass(local.uniform(-1, 1, len(t)), 1500 * pitch) * np.exp(-t * 32 / weight)
        thump = sweep(170 * pitch, 55 * pitch, length, curve=0.4) * np.exp(-t * 26 / weight)
        clack = pad([(0.018 / pitch, highpass(local.uniform(-1, 1, int(0.012 * RATE)), 4000) * np.exp(-t_axis(0.012) * 300))], length)
        write_wav(f"coax{caliber}", np.tanh((crack * 1.3 + blast * 1.1 + thump * 1.5 * weight + clack * 0.5) * 2.2), 0.95)


# --- Music ---------------------------------------------------------------------------------

NOTE_NAMES = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7,
              "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(name):
    pitch, octave = name[:-1], int(name[-1])
    return 12 * (octave + 1) + NOTE_NAMES[pitch]


def freq(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def melody(text):
    """'A4:1 D5:.5 -:1' -> [(beat, beats, midi or None)]"""
    out = []
    beat = 0.0
    for token in text.split():
        name, dur = token.split(":")
        d = float(dur)
        out.append((beat, d, None if name == "-" else midi(name)))
        beat += d
    return out


def chord_notes(name, octave=3):
    """Chord symbol -> midi notes, root in the given octave."""
    root = name[:2] if len(name) > 1 and name[1] in "#b" else name[0]
    quality = name[len(root):]
    r = midi(root + str(octave))
    intervals = {"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11],
                 "sus": [0, 5, 7], "add9": [0, 4, 7, 14]}[quality]
    return [r + i for i in intervals]




# --- Music ---------------------------------------------------------------------------------
# Arcade military funk-rock in the Metal Slug vein: brass stabs and a brass lead over slap bass,
# palm-muted power chords, a marching snare with rolls, toms and crashes. Every part is placed on
# the beat grid of a `Song`; the lead and brass get their own echo bus so the rhythm stays dry.


class Song:
    def __init__(self, bpm, bars, beats_per_bar=4):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bars = bars
        self.length = bars * beats_per_bar * self.beat
        n = int(round(self.length * RATE))
        self.buses = {name: (np.zeros(n), np.zeros(n)) for name in ("dry", "wet")}

    def add(self, start_beat, sig, pan=0.0, gain=1.0, bus="dry"):
        left, right = self.buses[bus]
        s = int(round(start_beat * self.beat * RATE))
        if s >= len(left) or s < 0:
            return
        end = min(len(left), s + len(sig))
        gl, gr = np.sqrt(0.5 * (1 - pan)) * gain, np.sqrt(0.5 * (1 + pan)) * gain
        left[s:end] += sig[: end - s] * gl
        right[s:end] += sig[: end - s] * gr
        # Wrap the tail into the start so loops have no gap.
        rest = sig[end - s:]
        if len(rest):
            k = min(len(rest), len(left))
            left[:k] += rest[:k] * gl
            right[:k] += rest[:k] * gr

    def render(self, name, echo_beats=0.75, feedback=0.3, wet_mix=0.28):
        os.makedirs(MUSIC_DIR, exist_ok=True)
        dl, dr = self.buses["dry"]
        wl, wr = self.buses["wet"]
        # Ping-pong echo on the wet bus only; np.roll keeps it seamless across the loop point.
        delay = int(echo_beats * self.beat * RATE)
        el, er = np.zeros_like(wl), np.zeros_like(wr)
        for i in range(1, 5):
            g = wet_mix * feedback ** (i - 1)
            src_l, src_r = (wr, wl) if i % 2 else (wl, wr)
            el += np.roll(lowpass(src_l, 3500), delay * i) * g
            er += np.roll(lowpass(src_r, 3500), delay * i) * g
        left, right = dl + wl + el, dr + wr + er
        stereo = np.stack([left, right], axis=1)
        stereo = highpass(stereo[:, 0], 30), highpass(stereo[:, 1], 30)
        stereo = np.stack(stereo, axis=1)
        # Normalize, a soft-knee saturator as the bus compressor, then settle at about -15 dBFS RMS
        # so the music sits under the effects instead of fighting them.
        stereo /= np.percentile(np.abs(stereo), 99.9) or 1.0
        stereo = np.tanh(stereo * 1.1) / np.tanh(1.1)
        stereo *= min(0.89 / np.max(np.abs(stereo)), 10 ** (-15 / 20) / np.sqrt(np.mean(stereo ** 2)))
        data = (np.clip(stereo, -1, 1) * 32767).astype(np.int16)
        tmp = os.path.join(MUSIC_DIR, name + ".tmp.wav")
        with wave.open(tmp, "wb") as f:
            f.setnchannels(2)
            f.setsampwidth(2)
            f.setframerate(RATE)
            f.writeframes(data.tobytes())
        out = os.path.join(MUSIC_DIR, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "6", out], check=True)
        os.remove(tmp)
        rms = np.sqrt(np.mean(stereo ** 2))
        print("wrote", out, f"{self.length:.1f}s rms {20 * np.log10(rms):.1f} dBFS")


def saw_stack(f, seconds, voices=(0.0,), bend=0.0, bend_time=0.04):
    """Band-limited saws detuned by `voices` (cents), each starting `bend` cents flat and sliding up."""
    t = t_axis(seconds)
    out = np.zeros_like(t)
    glide = bend * np.clip(1 - t / bend_time, 0, 1)
    for cents in voices:
        inst = f * 2 ** ((cents + glide) / 1200)
        phase = 2 * np.pi * np.cumsum(inst) / RATE
        for h in range(1, 40):
            if f * h > RATE / 2.4:
                break
            out += np.sin(phase * h) / h
    return out / len(voices)


def filter_env(raw, n, dark_cutoff, attack, decay, floor):
    """Crossfades a dark (lowpassed) copy into the raw signal: a cheap filter envelope."""
    dark = lowpass(raw, dark_cutoff)
    t = np.arange(n) / RATE
    k = np.clip(t / max(attack, 1e-4), 0, 1) * (floor + (1 - floor) * np.exp(-np.maximum(t - attack, 0) / decay))
    return dark * (1 - k) + raw * k


def brass(m, beats, song, stab=False):
    """Synth brass: detuned saws that blat up into pitch with the filter opening on the attack."""
    seconds = beats * song.beat * (0.55 if stab else 1.0) + 0.05
    raw = saw_stack(freq(m), seconds, (-8.0, 0.0, 7.0), bend=-45.0)
    n = len(raw)
    sig = filter_env(raw, n, 700, 0.02, 0.09 if stab else 0.25, 0.25 if stab else 0.55)
    return sig * env(n, 0.012, 0.06 if stab else 0.1, decay=0.12, sustain=0.5 if stab else 0.8)


def brass_chord(notes, beats, song, stab=True):
    return sum(brass(m, beats, song, stab) for m in notes) / np.sqrt(len(notes))


def lead(m, beats, song):
    """Lead brass line: brighter, with delayed vibrato."""
    seconds = beats * song.beat + 0.04
    t = t_axis(seconds)
    vib = np.sin(2 * np.pi * 5.8 * t) * 14 * np.clip((t - 0.18) * 3, 0, 1)
    f = freq(m)
    out = np.zeros_like(t)
    for cents in (-6.0, 5.0):
        inst = f * 2 ** ((cents + vib - 30 * np.clip(1 - t / 0.035, 0, 1)) / 1200)
        phase = 2 * np.pi * np.cumsum(inst) / RATE
        for h in range(1, 30):
            if f * h > RATE / 2.4:
                break
            out += np.sin(phase * h) / h * (0.6 if h % 2 == 0 else 1.0)
    sig = filter_env(out / 2, len(t), 2200, 0.015, 0.3, 0.8)
    return sig * env(len(t), 0.01, 0.07, decay=0.15, sustain=0.75)


def slap(m, beats, song, pop=False):
    """Slap bass: plucked saw with a snapping filter; pops are an octave up with a click."""
    seconds = min(beats * song.beat, 0.5) + 0.02
    f = freq(m + (12 if pop else 0))
    raw = saw_stack(f, seconds, (0.0,)) + np.sin(2 * np.pi * f * t_axis(seconds)) * 0.8
    n = len(raw)
    sig = filter_env(raw, n, 380, 0.002, 0.05 if pop else 0.08, 0.1)
    if pop:
        sig[: int(0.004 * RATE)] += highpass(noise(0.004), 2000) * 0.6
    return np.tanh(sig * 1.6) * env(n, 0.002, 0.04, decay=0.18, sustain=0.35)


def power_chord(m, beats, song, mute=True):
    """Overdriven root-fifth-octave; palm-muted chugs are short and dark."""
    seconds = beats * song.beat * (0.8 if mute else 1.0) + 0.02
    raw = sum(saw_stack(freq(n), seconds, (-4.0, 4.0)) for n in (m, m + 7, m + 12))
    sig = np.tanh(raw * 5.0)
    sig = lowpass(sig, 900 if mute else 2600)
    sig = highpass(sig, 90)
    return sig * env(len(sig), 0.003, 0.03, decay=0.08 if mute else 0.4, sustain=0.3 if mute else 0.8)


def kick():
    n = int(0.3 * RATE)
    body = sweep(190, 44, 0.3, curve=0.3) * np.exp(-np.arange(n) / RATE * 9)
    click = np.zeros(n)
    click[: int(0.003 * RATE)] = highpass(noise(0.003), 1500) * 0.5
    return np.tanh((body + click) * 1.8) * 0.75


def snare(accent=1.0):
    n = int(0.22 * RATE)
    body = sweep(260, 180, 0.22) * np.exp(-np.arange(n) / RATE * 28) * 0.8
    wires = highpass(noise(0.22), 1800) * np.exp(-np.arange(n) / RATE * (16 + 6 * (1 - accent)))
    return (body + wires) * accent


def tom(f):
    n = int(0.35 * RATE)
    return sweep(f * 1.4, f, 0.35, curve=0.4) * np.exp(-np.arange(n) / RATE * 9)


def hat(open_hat=False):
    seconds = 0.25 if open_hat else 0.045
    n = int(seconds * RATE)
    return highpass(noise(seconds), 8000) * np.exp(-np.arange(n) / RATE * (10 if open_hat else 90))


def crash():
    n = int(1.8 * RATE)
    return highpass(noise(1.8), 5000) * np.exp(-np.arange(n) / RATE * 2.2) * 0.8


def orchestra_hit(notes, song):
    """Brass chord, a wash of noise and a low boom: the arcade 'stab'."""
    sig = brass_chord([m + 12 for m in notes] + notes, 1.0, song)
    n = len(sig)
    sig = sig + highpass(noise(n / RATE), 3000) * np.exp(-np.arange(n) / RATE * 20) * 0.5
    boom = tom(55)
    sig[: len(boom)] += boom[: n] * 0.8
    return sig


class Drums:
    def __init__(self, song):
        self.song = song
        self.k, self.h, self.oh, self.c = kick(), hat(), hat(True), crash()
        self.s = [snare(a) for a in (1.0, 0.55, 0.3)]
        self.toms = [tom(f) for f in (180, 140, 105)]

    def bar(self, bar, style):
        s, b = self.song, bar * 4
        if style == "march":
            # Snare-led march groove: kick on 1 and 3, backbeat plus ghost notes, 8th hats.
            for i in (0, 2, 2.75):
                s.add(b + i, self.k, 0, 0.95)
            for i in (1, 3):
                s.add(b + i, self.s[0], 0.08, 0.7)
            for i in (0.25, 1.75, 2.5, 3.75):
                s.add(b + i, self.s[2], 0.08, 0.7)
            for i in range(8):
                s.add(b + i * 0.5, self.oh if i == 7 else self.h, -0.35, 0.16 if i % 2 == 0 else 0.1)
        elif style == "drive":
            for i in (0, 1, 2, 3, 3.5):
                s.add(b + i, self.k, 0, 0.9)
            for i in (1, 3):
                s.add(b + i, self.s[0], 0.08, 0.75)
            for i in range(16):
                s.add(b + i * 0.25, self.h, -0.35, 0.12 if i % 2 == 0 else 0.07)
        elif style == "gallop":
            for i in (0, 0.75, 1, 1.75, 2, 2.75, 3, 3.75):
                s.add(b + i, self.k, 0, 0.85)
            for i in (1, 3):
                s.add(b + i, self.s[0], 0.08, 0.8)
            for i in range(8):
                s.add(b + i * 0.5, self.h, -0.35, 0.14)
        elif style == "half":
            s.add(b, self.k, 0, 0.9)
            s.add(b + 2, self.s[0], 0.08, 0.7)
            for i in range(4):
                s.add(b + i + 0.5, self.h, -0.35, 0.1)

    def roll(self, bar, beats=4):
        """Marching snare roll swelling into the next bar."""
        s, b = self.song, bar * 4 + (4 - beats)
        steps = int(beats * 8)
        for i in range(steps):
            k = (i + 1) / steps
            s.add(b + i / 8, self.s[1], 0.08 * (1 if i % 2 else -1), 0.25 + 0.6 * k * k)

    def fill(self, bar):
        """Last two beats of a bar down the toms."""
        s, b = self.song, bar * 4 + 2
        for i in range(8):
            s.add(b + i * 0.25, self.toms[min(i // 3, 2)], -0.3 + i * 0.08, 0.7)

    def crash(self, bar, beat=0.0):
        self.song.add(bar * 4 + beat, self.c, 0.3, 0.45)
        self.song.add(bar * 4 + beat, self.k, 0, 1.0)


def slap_bar(song, root, bar, pattern="funk"):
    """One bar of slap bass on `root` (MIDI): thumbed roots and octave pops."""
    b = bar * 4
    if pattern == "funk":
        hits = [(0, 0, False), (0.75, 0, False), (1.0, 12, True), (1.5, 0, False), (2.0, 0, False), (2.5, 10, False),
                (2.75, 12, True), (3.25, 7, False), (3.5, 12, True)]
    elif pattern == "drive":
        hits = [(i * 0.5, 12 if i % 4 == 3 else 0, i % 4 == 3) for i in range(8)]
    else:  # gallop
        hits = [(i * 0.25, 0, False) for i in range(16) if i % 4 != 1]
    for beat, offset, pop in hits:
        song.add(b + beat, slap(root + offset, 0.4, song, pop), 0.0, 0.45 if pop else 0.42)


def chug_bar(song, root, bar, pattern="eighths", gain=0.22):
    b = bar * 4
    if pattern == "eighths":
        for i in range(8):
            song.add(b + i * 0.5, power_chord(root, 0.45, song), -0.5 if i % 2 else 0.5, gain)
    elif pattern == "gallop":
        for i in range(16):
            if i % 4 != 1:
                song.add(b + i * 0.25, power_chord(root, 0.22, song), -0.5 if i % 2 else 0.5, gain)
    elif pattern == "ring":
        song.add(b, power_chord(root, 3.6, song, mute=False), -0.4, gain)
        song.add(b, power_chord(root, 3.6, song, mute=False), 0.4, gain)


def stab_bar(song, chord, bar, beats=(0.5, 1.5, 2.5, 3.5), gain=0.2):
    notes = chord_notes(chord, 4)
    for beat in beats:
        song.add(bar * 4 + beat, brass_chord(notes, 0.5, song), 0.2, gain, "wet")


def place_lead(song, text, start_bar, gain=0.34, shift=0, pan=0.12):
    for beat, beats, m in melody(text):
        if m is not None:
            song.add(start_bar * 4 + beat, lead(m + shift, beats, song), pan, gain, "wet")


def root_of(chord, octave=1):
    return chord_notes(chord, octave)[0]


def arrange(song, drums, chords, bars, start, style, bass="funk", chug="eighths", stabs=True):
    for i in range(bars):
        chord = chords[i % len(chords)]
        bar = start + i
        drums.bar(bar, style)
        slap_bar(song, root_of(chord, 1), bar, bass)
        chug_bar(song, root_of(chord, 2), bar, chug)
        if stabs:
            stab_bar(song, chord, bar)


def music():
    # Stage A: farm road and village. G minor military funk, 150 bpm.
    song = Song(150, 36)
    d = Drums(song)
    verse = ["Gm", "Gm", "Eb", "F", "Gm", "Gm", "Cm", "D"]
    chorus = ["Eb", "F", "Gm", "Gm", "Eb", "F", "D", "D"]
    # Intro: brass hits over a swelling roll.
    for bar, chord in enumerate(["Gm", "Eb", "F", "D"]):
        song.add(bar * 4, orchestra_hit(chord_notes(chord, 3), song), 0, 0.5)
        song.add(bar * 4 + 1.5, orchestra_hit(chord_notes(chord, 3), song), 0, 0.35)
    d.roll(2, 8)
    d.crash(4)
    arrange(song, d, verse, 8, 4, "march")
    arrange(song, d, verse, 8, 12, "march")
    d.fill(19)
    d.crash(20)
    arrange(song, d, chorus, 8, 20, "drive")
    d.fill(27)
    d.crash(28)
    # Breakdown: bass and drums, stabs answering.
    for i, chord in enumerate(verse):
        d.bar(28 + i, "half" if i < 4 else "march")
        slap_bar(song, root_of(chord, 1), 28 + i, "funk")
        if i % 2 == 1:
            stab_bar(song, chord, 28 + i, beats=(2.5, 3.0, 3.5), gain=0.24)
    d.roll(35, 4)
    theme = ("G4:.5 A#4:.5 D5:1 C5:.5 A#4:.5 C5:1 D5:1.5 F5:.5 D5:1 -:1 "
             "D#5:.5 D5:.5 C5:1 A#4:.5 C5:.5 D5:1 C5:1.5 A#4:.5 A4:1 -:1 "
             "G4:.5 A#4:.5 D5:1 C5:.5 A#4:.5 C5:1 D5:.5 F5:.5 G5:1 A#5:1 G5:1 "
             "G5:.5 F5:.5 D#5:1 D5:.5 C5:.5 D#5:1 D5:2 F#5:1 A5:1")
    hook = ("A#5:1.5 G5:.5 D#5:1 G5:1 A5:1.5 F5:.5 C5:1 F5:1 G5:1 A#5:1 D6:1 C6:.5 A#5:.5 A5:.5 A#5:.5 A5:.5 G5:.5 D5:2 "
            "A#5:1.5 G5:.5 D#5:1 G5:1 C6:1.5 A5:.5 F5:1 A5:1 A#5:1 A5:1 G5:1 F#5:1 A5:4")
    place_lead(song, theme, 4)
    place_lead(song, theme, 12, shift=12, gain=0.28)
    place_lead(song, theme, 12, gain=0.2, pan=-0.3)
    place_lead(song, hook, 20)
    place_lead(song, hook, 20, shift=-12, gain=0.18, pan=-0.3)
    song.render("stage_a", 0.75)

    # Stage B: school, reservoir and overpass. D minor, harder drive, 160 bpm.
    song = Song(160, 36)
    d = Drums(song)
    verse = ["Dm", "Dm", "Bb", "C", "Dm", "Dm", "Gm", "A"]
    chorus = ["Bb", "C", "Am", "Dm", "Bb", "C", "A", "A"]
    for bar in range(4):
        chug_bar(song, root_of("Dm", 2), bar, "gallop", 0.2)
        d.bar(bar, "half")
    d.roll(3, 4)
    d.crash(4)
    arrange(song, d, verse, 8, 4, "drive", bass="drive")
    arrange(song, d, verse, 8, 12, "drive", bass="funk")
    d.fill(19)
    d.crash(20)
    arrange(song, d, chorus, 8, 20, "drive", bass="drive", chug="ring")
    d.fill(27)
    d.crash(28)
    arrange(song, d, verse, 8, 28, "march", bass="funk", stabs=False)
    d.roll(35, 2)
    theme = ("D5:.75 D5:.25 F5:.5 A5:.5 G5:.5 F5:.5 E5:.5 F5:.5 D5:1 A4:1 D5:1 -:1 "
             "F5:.75 F5:.25 A#5:.5 A5:.5 G5:1 F5:1 E5:.5 F5:.5 G5:1 C5:2 "
             "D5:.75 D5:.25 F5:.5 A5:.5 G5:.5 F5:.5 E5:.5 F5:.5 D5:1 A5:1 D6:1 C6:1 "
             "A#5:1 A5:.5 G5:.5 A#5:1 D6:1 C#6:2 E6:2")
    hook = ("F6:1.5 E6:.5 D6:1 C6:1 E6:1.5 D6:.5 C6:1 G5:1 A5:1 C6:1 E6:1 D6:.5 C6:.5 D6:2 A5:2 "
            "F6:1.5 E6:.5 D6:1 C6:1 E6:1.5 D6:.5 C6:1 E6:1 C#6:1 D6:1 E6:1 G6:1 E6:4")
    place_lead(song, theme, 4)
    place_lead(song, theme, 12, gain=0.3)
    place_lead(song, theme, 12, shift=-12, gain=0.2, pan=-0.3)
    place_lead(song, hook, 20)
    place_lead(song, theme, 28, shift=12, gain=0.22)
    song.render("stage_b", 0.5)

    # Boss: E minor with a phrygian F, galloping, 172 bpm.
    song = Song(172, 36)
    d = Drums(song)
    prog = ["Em", "Em", "C", "D", "Em", "Em", "F", "B7"]
    for bar in range(4):
        song.add(bar * 4, orchestra_hit(chord_notes("Em" if bar < 3 else "B7", 3), song), 0, 0.55)
        song.add(bar * 4 + 0.75, orchestra_hit(chord_notes("Em" if bar < 3 else "B7", 3), song), 0, 0.4)
    d.roll(2, 8)
    d.crash(4)
    arrange(song, d, prog, 16, 4, "gallop", bass="gallop", chug="gallop")
    d.fill(19)
    d.crash(20)
    arrange(song, d, prog, 8, 20, "drive", bass="drive", chug="ring")
    d.crash(28)
    arrange(song, d, prog, 8, 28, "gallop", bass="gallop", chug="gallop", stabs=False)
    d.roll(35, 4)
    theme = ("B5:.5 E6:.5 B5:.5 A5:.5 G5:1 F#5:1 E5:.5 G5:.5 B5:1 E6:2 C6:.5 B5:.5 A5:.5 G5:.5 A5:1 C6:1 B5:1 A5:1 F#5:2 "
             "E6:.5 F#6:.5 G6:1 F#6:.5 E6:.5 D6:1 B5:.5 D6:.5 E6:1 G6:2 F6:1 E6:1 D6:1 C6:1 B5:2 D#6:2")
    place_lead(song, theme, 4)
    place_lead(song, theme, 12, gain=0.3)
    place_lead(song, theme, 12, shift=-12, gain=0.22, pan=-0.3)
    place_lead(song, theme, 20, shift=12, gain=0.26)
    song.render("boss", 0.5)

    # Title: a slow brass anthem over a ringing guitar and soft march.
    song = Song(96, 16)
    d = Drums(song)
    prog = ["Gm", "Eb", "Bb", "F", "Gm", "Eb", "Cm", "D"]
    for i in range(16):
        chord = prog[i % 8]
        chug_bar(song, root_of(chord, 2), i, "ring", 0.14)
        song.add(i * 4, brass_chord(chord_notes(chord, 3), 4.0, song, stab=False), 0, 0.2, "wet")
        if i >= 8:
            d.bar(i, "half")
    d.roll(7, 4)
    d.crash(8)
    anthem = "D5:2 G5:1 A5:1 A#5:3 A5:1 G5:2 F5:1 D#5:1 D5:4 D5:2 G5:1 A5:1 A#5:2 C6:2 A5:3 F#5:1 G5:4"
    place_lead(song, anthem, 0, gain=0.3)
    place_lead(song, anthem, 8, gain=0.3)
    place_lead(song, anthem, 8, shift=-12, gain=0.2, pan=-0.3)
    song.render("title", 1.0, 0.4, 0.35)

    # Clear fanfare (not looped).
    song = Song(132, 6)
    d = Drums(song)
    fan = "G4:.33 G4:.33 G4:.34 C5:1 G4:.5 C5:.5 E5:1.5 -:.5 D5:.33 D5:.33 D5:.34 E5:.5 F5:.5 G5:1 A5:.5 B5:.5 C6:6"
    for bar, chord in enumerate(["C", "C", "G", "G", "C", "C"]):
        song.add(bar * 4, orchestra_hit(chord_notes(chord, 3), song), 0, 0.45)
    d.roll(3, 2)
    d.crash(4)
    place_lead(song, fan, 0, gain=0.4)
    place_lead(song, fan, 0, shift=-12, gain=0.22, pan=-0.3)
    song.render("clear", 0.5)


if __name__ == "__main__":
    import sys
    parts = sys.argv[1:] or ["sfx", "music"]
    if "sfx" in parts:
        sfx()
        guns()
    elif "guns" in parts:
        guns()
    if "music" in parts:
        music()
