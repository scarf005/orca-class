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


class Song:
    def __init__(self, bpm, bars, beats_per_bar=4):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.length = bars * beats_per_bar * self.beat
        n = int(round(self.length * RATE))
        self.left = np.zeros(n)
        self.right = np.zeros(n)

    def add(self, start_beat, sig, pan=0.0, gain=1.0):
        s = int(round(start_beat * self.beat * RATE))
        if s >= len(self.left):
            return
        end = min(len(self.left), s + len(sig))
        chunk = sig[: end - s] * gain
        self.left[s:end] += chunk * np.sqrt(0.5 * (1 - pan))
        self.right[s:end] += chunk * np.sqrt(0.5 * (1 + pan))
        # Wrap the tail into the start so loops have no gap.
        if s + len(sig) > len(self.left):
            rest = sig[end - s:] * gain
            k = min(len(rest), len(self.left))
            self.left[:k] += rest[:k] * np.sqrt(0.5 * (1 - pan))
            self.right[:k] += rest[:k] * np.sqrt(0.5 * (1 + pan))

    def echo(self, beats=0.75, feedback=0.35, mix=0.3):
        delay = int(beats * self.beat * RATE)
        for ch, other in ((self.left, self.right), (self.right, self.left)):
            wet = np.zeros_like(ch)
            tap = ch * mix
            for i in range(1, 5):
                shift = delay * i
                wet += np.roll(tap, shift) * feedback ** (i - 1)
            ch += wet * 0.5
            other += wet * 0.2

    def render(self, name, loop=True):
        os.makedirs(MUSIC_DIR, exist_ok=True)
        stereo = np.stack([self.left, self.right], axis=1)
        stereo /= np.max(np.abs(stereo)) or 1.0
        stereo = np.tanh(stereo * 1.2) * 0.85
        data = (stereo * 32767).astype(np.int16)
        tmp = os.path.join(MUSIC_DIR, name + ".tmp.wav")
        with wave.open(tmp, "wb") as f:
            f.setnchannels(2)
            f.setsampwidth(2)
            f.setframerate(RATE)
            f.writeframes(data.tobytes())
        out = os.path.join(MUSIC_DIR, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
        os.remove(tmp)
        print("wrote", out, f"{self.length:.1f}s")


def inst_lead(m, beats, song, vibrato=True, shape="square"):
    seconds = beats * song.beat
    t = t_axis(seconds + 0.08)
    f = freq(m)
    vib = np.sin(2 * np.pi * 5.5 * t) * 0.006 * np.clip((t - 0.15) * 4, 0, 1) if vibrato else 0
    phase = 2 * np.pi * f * np.cumsum(1 + vib) / RATE
    wave_sum = np.zeros_like(t)
    for h in range(1, 12):
        if shape == "square" and h % 2 == 0:
            wave_sum += np.sin(phase * h) / h * 0.35  # A 25% pulse keeps some even harmonics.
        else:
            wave_sum += np.sin(phase * h) / h
    return wave_sum * env(len(t), 0.01, 0.08, decay=0.2, sustain=0.7)


def inst_bell(m, beats, song):
    seconds = beats * song.beat + 0.6
    t = t_axis(seconds)
    f = freq(m)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 2.0 * np.exp(-t * 6)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 2.5) * env(len(t), 0.002, 0.3)


def inst_bass(m, beats, song, shape="triangle"):
    seconds = beats * song.beat
    sig = tone(freq(m), seconds, shape, 8)
    sig += np.sin(2 * np.pi * freq(m) / 2 * t_axis(seconds)) * 0.5
    return sig * env(len(sig), 0.005, 0.03, decay=0.15, sustain=0.6)


def inst_pad(notes, beats, song):
    seconds = beats * song.beat
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for m in notes:
        for detune in (0.997, 1.003):
            out += tone(freq(m) * detune, seconds, "saw", 6) * 0.5
    out = lowpass(out, 1400)
    return out * env(len(t), 0.25, 0.4)


def inst_arp(m, beats, song):
    seconds = beats * song.beat
    return tone(freq(m), seconds, "square", 7) * env(int(seconds * RATE), 0.002, 0.05, decay=0.08, sustain=0.3)


def kick():
    return sweep(150, 42, 0.22, curve=0.4) * env(int(0.22 * RATE), 0.001, 0.12)


def snare():
    body = sweep(240, 170, 0.16) * env(int(0.16 * RATE), 0.001, 0.1) * 0.6
    return pad([(0, body), (0, highpass(noise(0.18), 1500) * env(int(0.18 * RATE), 0.001, 0.15))], 0.18)


def hat(open_hat=False):
    seconds = 0.2 if open_hat else 0.05
    return highpass(noise(seconds), 7000) * env(int(seconds * RATE), 0.001, seconds * 0.8)


def drums(song, bars, style, start_bar=0):
    k, s, h, oh = kick(), snare(), hat(), hat(True)
    for bar in range(start_bar, start_bar + bars):
        b = bar * 4
        if style == "four":
            for i in range(4):
                song.add(b + i, k, 0, 0.9)
            for i in (1, 3):
                song.add(b + i, s, 0.1, 0.6)
            for i in range(8):
                song.add(b + i * 0.5 + (0.5 if i % 2 == 0 else 0), oh if i % 2 == 0 else h, -0.3, 0.13)
        elif style == "break":
            for i in (0, 1.5, 2.5):
                song.add(b + i, k, 0, 0.9)
            for i in (1, 3):
                song.add(b + i, s, 0.1, 0.65)
            for i in range(16):
                song.add(b + i * 0.25, h, -0.3, 0.08 if i % 2 else 0.13)
        elif style == "boss":
            for i in (0, 0.75, 1.5, 2, 2.75, 3.5):
                song.add(b + i, k, 0, 0.95)
            for i in (1, 3):
                song.add(b + i, s, 0.1, 0.7)
            if bar % 2 == 1:
                for i in (3.5, 3.75):
                    song.add(b + i, s, 0.2, 0.4)
            for i in range(16):
                song.add(b + i * 0.25, h, -0.3, 0.07 if i % 2 else 0.12)
        elif style == "soft":
            song.add(b, k, 0, 0.5)
            song.add(b + 2.5, k, 0, 0.35)
            for i in range(4):
                song.add(b + i + 0.5, h, -0.3, 0.12)


def progression(song, chords, bars, start_bar=0, pad_gain=0.18, bass_pattern="eighths", bass_gain=0.5, arp_gain=0.0, arp_octave=5):
    for i in range(bars):
        chord = chords[i % len(chords)]
        b = (start_bar + i) * 4
        notes = chord_notes(chord, 4)
        song.add(b, inst_pad(notes, 4, song), 0.0, pad_gain)
        root = chord_notes(chord, 2)[0]
        if bass_pattern == "eighths":
            for j in range(8):
                song.add(b + j * 0.5, inst_bass(root + (12 if j % 2 else 0), 0.45, song), 0, bass_gain)
        elif bass_pattern == "gallop":
            for j in range(16):
                if j % 4 != 3:
                    song.add(b + j * 0.25, inst_bass(root + (1 if j in (6, 14) else 0), 0.22, song, "saw"), 0, bass_gain)
        elif bass_pattern == "whole":
            song.add(b, inst_bass(root, 3.8, song), 0, bass_gain)
        elif bass_pattern == "syncopated":
            for j in (0, 0.75, 1.5, 2, 2.75, 3.5):
                song.add(b + j, inst_bass(root + (12 if j in (1.5, 3.5) else 0), 0.4, song), 0, bass_gain)
        if arp_gain > 0:
            arp = chord_notes(chord, arp_octave)
            for j in range(16):
                song.add(b + j * 0.25, inst_arp(arp[j % len(arp)] + (12 if (j // 4) % 2 else 0), 0.24, song), 0.4 if j % 2 else -0.4, arp_gain)


def place_melody(song, text, start_bar, instrument="lead", gain=0.35, octave_shift=0, pan=0.1):
    for beat, beats, m in melody(text):
        if m is None:
            continue
        m += 12 * octave_shift
        sig = inst_bell(m, beats, song) if instrument == "bell" else inst_lead(m, beats, song)
        song.add(start_bar * 4 + beat, sig, pan, gain)


def music():
    # Stage A: farm road and village. D minor, driving and bright.
    song = Song(140, 32)
    chords = ["Dm", "Bb", "F", "C"]
    m1 = ("A4:1 D5:.5 E5:.5 F5:1 E5:.5 D5:.5 D5:1.5 C5:.5 Bb4:1 F4:1 A4:1 C5:.5 F5:.5 A5:1 G5:.5 F5:.5 E5:2 G5:1 E5:1 "
          "A5:1 G5:.5 F5:.5 E5:1 D5:1 F5:1.5 E5:.5 D5:1 Bb4:1 C5:1 D5:.5 E5:.5 F5:1 A5:1 G5:3 -:1")
    m2 = ("D6:.5 C6:.5 A5:.5 F5:.5 A5:1 D6:1 F6:1.5 D6:.5 Bb5:2 C6:.5 A5:.5 F5:.5 A5:.5 C6:1 F6:1 E6:1 D6:.5 C6:.5 G5:2 "
          "D6:.5 E6:.5 F6:1 E6:.5 D6:.5 A5:1 Bb5:1 D6:1 F6:1 D6:1 C6:1 A5:1 F6:1 E6:1 E6:2 D6:1 C6:1")
    progression(song, chords, 8, 0, bass_pattern="eighths", arp_gain=0.05)
    progression(song, chords, 24, 8, bass_pattern="eighths", arp_gain=0.07)
    drums(song, 4, "soft", 0)
    drums(song, 4, "break", 4)
    drums(song, 24, "four", 8)
    place_melody(song, m1, 8)
    place_melody(song, m2, 16)
    place_melody(song, m1, 24, gain=0.3)
    place_melody(song, m1, 24, "bell", 0.2, 1, -0.3)
    song.echo(0.75, 0.35, 0.25)
    song.render("stage_a")

    # Stage B: school, reservoir and overpass. E minor, tense and quicker.
    song = Song(150, 32)
    chords = ["Em", "C", "Am", "B7"]
    m3 = ("E5:.75 G5:.75 B5:.5 A5:1 G5:1 E5:1.5 G5:.5 C6:1 B5:1 A5:.75 C6:.75 E6:.5 D6:1 C6:1 B5:2 D#6:1 F#6:1 "
          "G6:1 F#6:.5 E6:.5 D6:1 B5:1 C6:1 E6:1 G6:1 E6:1 A5:.5 B5:.5 C6:1 E6:1 D#6:1 B5:4")
    progression(song, chords, 8, 0, bass_pattern="syncopated", arp_gain=0.06)
    progression(song, chords, 24, 8, bass_pattern="syncopated", arp_gain=0.08)
    drums(song, 8, "break", 0)
    drums(song, 24, "four", 8)
    place_melody(song, m3, 8)
    place_melody(song, m3, 16, octave_shift=0, gain=0.3)
    place_melody(song, m3, 16, "bell", 0.18, 1, -0.3)
    place_melody(song, m3, 24, gain=0.34)
    song.echo(0.5, 0.3, 0.22)
    song.render("stage_b")

    # Boss: E phrygian riffing at 164 bpm.
    song = Song(164, 32)
    chords = ["Em", "F", "Em", "D", "C", "D", "Em", "Em"]
    m4 = ("E5:.5 F5:.5 G5:.5 B5:.5 E6:1 D6:.5 B5:.5 C6:1 A5:.5 F5:.5 A5:1 C6:1 B5:.5 G5:.5 E5:.5 G5:.5 B5:1 E6:1 "
          "F#6:1.5 E6:.5 D6:2 E6:1 G6:1 E6:.5 C6:.5 G5:1 F#6:1 A6:1 F#6:.5 D6:.5 A5:1 G6:.5 F#6:.5 E6:.5 D6:.5 B5:1 G5:1 E6:3 -:1")
    progression(song, chords, 32, 0, pad_gain=0.14, bass_pattern="gallop", bass_gain=0.45, arp_gain=0.07)
    drums(song, 4, "break", 0)
    drums(song, 28, "boss", 4)
    place_melody(song, m4, 8)
    place_melody(song, m4, 16, gain=0.3)
    place_melody(song, m4, 16, "bell", 0.18, 1, -0.3)
    place_melody(song, m4, 24, gain=0.35, octave_shift=0)
    song.echo(0.5, 0.25, 0.2)
    song.render("boss")

    # Title: dreamy F lydian, slow.
    song = Song(84, 16)
    chords = ["Fmaj7", "Fmaj7", "Em7", "Em7", "Dm7", "Dm7", "Cmaj7", "Cmaj7"]
    m5 = "A5:2 G5:1 E5:1 C5:4 B4:2 D5:1 G5:1 E5:4 F5:2 E5:1 D5:1 A5:3 C6:1 B5:2 G5:1 E5:1 G5:4"
    progression(song, chords, 16, 0, pad_gain=0.3, bass_pattern="whole", bass_gain=0.4, arp_gain=0.04, arp_octave=5)
    drums(song, 8, "soft", 8)
    place_melody(song, m5, 0, "bell", 0.35)
    place_melody(song, m5, 8, "bell", 0.3, 1, -0.2)
    place_melody(song, m5, 8, "lead", 0.12, 0, 0.3)
    song.echo(1.0, 0.45, 0.35)
    song.render("title")

    # Clear fanfare (not looped).
    song = Song(120, 6)
    fan = "C5:.5 E5:.5 G5:.5 C6:1.5 -:1 A5:.5 C6:.5 F6:1 E6:.5 D6:.5 E6:1 D6:.5 B5:.5 G5:1 C6:6"
    progression(song, ["C", "F", "G", "C", "C", "C"], 6, 0, pad_gain=0.25, bass_pattern="whole", bass_gain=0.4)
    place_melody(song, fan, 0, "lead", 0.4)
    place_melody(song, fan, 0, "bell", 0.25, 1, -0.3)
    song.add(0, kick(), 0, 0.8)
    song.add(4, kick(), 0, 0.8)
    song.add(8, kick(), 0, 0.8)
    song.add(12, kick(), 0, 1.0)
    song.echo(0.5, 0.3, 0.2)
    song.render("clear")


if __name__ == "__main__":
    sfx()
    music()
