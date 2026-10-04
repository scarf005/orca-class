"""Stage 2 music: lyrical solo piano over chopped breakcore.

The piano is rendered by FluidSynth from the General MIDI soundfont (Acoustic Grand), with sustain pedal,
so the melodies breathe like a real instrument. The drums reuse the Amen-style sampler in audio.py.
Run through `just audio` (needs numpy and pyfluidsynth, libfluidsynth and a GM soundfont).
"""

import os

import numpy as np

import audio
from audio import RATE, Break, Song, chopped, chord_notes, midi, roll, tone, env, lowpass, highpass, noise, root_of

SOUNDFONT = os.environ.get("SOUNDFONT", "/usr/share/soundfonts/FluidR3_GM.sf2")
TAIL = 4.0  # seconds of release that wrap around the loop point


def phrase(text):
    """'E5:3 D5:1 | C5:2' -> [(beat, beats, midi or None)]; `|` marks bars and is ignored."""
    return audio.melody(" ".join(t for t in text.split() if t != "|"))


class Piano:
    """Collects note and pedal events, then renders them through FluidSynth."""

    def __init__(self, song, seed):
        self.song = song
        self.events = []  # (time s, kind, a, b)
        self.rng = np.random.default_rng(seed)

    def note(self, beat, beats, m, vel=80, human=0.006):
        t = beat * self.song.beat + float(self.rng.normal(0.0, human))
        t = max(0.0, t)
        v = int(np.clip(vel + self.rng.integers(-5, 6), 20, 127))
        self.events.append((t, 1, m, v))
        self.events.append((t + max(0.05, beats * self.song.beat * 0.96), 0, m, 0))

    def pedal(self, beat_on, beat_off):
        self.events.append((beat_on * self.song.beat, 2, 127, 0))
        self.events.append((max(beat_on * self.song.beat, beat_off * self.song.beat - 0.04), 2, 0, 0))

    def render(self, gain=1.0, pan=0.0):
        import fluidsynth

        synth = fluidsynth.Synth(samplerate=float(RATE), gain=0.9)
        font = synth.sfload(SOUNDFONT)
        synth.program_select(0, font, 0, 0)
        synth.set_reverb(roomsize=0.62, damping=0.35, width=1.0, level=0.5)
        synth.set_chorus(nr=2, level=0.9, speed=0.25, depth=3.0)
        total = int((self.song.length + TAIL) * RATE)
        order = sorted(range(len(self.events)), key=lambda i: (self.events[i][0], -self.events[i][1]))
        chunks = []
        cursor = 0
        for i in order:
            t, kind, a, b = self.events[i]
            at = min(int(round(t * RATE)), total)
            if at > cursor:
                chunks.append(synth.get_samples(at - cursor))
                cursor = at
            if kind == 1:
                synth.noteon(0, a, b)
            elif kind == 0:
                synth.noteoff(0, a)
            else:
                synth.cc(0, 64, a)
        if total > cursor:
            chunks.append(synth.get_samples(total - cursor))
        synth.delete()
        raw = np.concatenate(chunks).astype(np.float32) / 32768.0
        stereo = raw.reshape(-1, 2)
        n = len(self.song.buses["dry"][0])
        head = stereo[:n].copy()
        tail = stereo[n:]
        head[: len(tail)] += tail  # the last release rings into the first bars of the loop
        left, right = self.song.buses["dry"]
        left += head[:, 0] * gain
        right += head[:, 1] * gain


# --- Left hand, bass, break levels ---------------------------------------------------------

def left_hand(piano, bar, chord, style, vel=58):
    notes = chord_notes(chord, 2)
    r, third, fifth = notes[0], notes[1], notes[2]
    top = notes[3] if len(notes) > 3 else r + 12
    b = bar * 4
    if style == "slow":  # rolling eighths, root up and back down
        seq = [r, fifth, r + 12, third + 12, r + 12, fifth, r + 12, third + 12]
        for i, m in enumerate(seq):
            piano.note(b + i * 0.5, 0.5, m, vel - (6 if i % 2 else 0))
    elif style == "arp16":  # sixteenths; the thumb pushes on every beat
        seq = [r, fifth, r + 12, third + 12, fifth + 12, third + 12, r + 12, fifth]
        for i in range(16):
            m = seq[i % 8]
            piano.note(b + i * 0.25, 0.25, m, vel + (10 if i % 4 == 0 else -4))
    elif style == "pulse":  # root pulses with a syncopated chord answer
        for beat in (0, 1.5, 2, 3.5):
            piano.note(b + beat, 0.5, r, vel + 8)
            piano.note(b + beat, 0.5, r - 12 if r - 12 >= 28 else r, vel)
        for beat in (0.5, 2.5):
            for m in (third + 12, fifth + 12, top + 12):
                piano.note(b + beat, 0.4, m, vel - 12)
    elif style == "whole":  # a held chord under a singing melody
        for m in (r - 12 if r - 12 >= 28 else r, r, fifth, third + 12):
            piano.note(b, 4.0, m, vel - 14)
    elif style == "gallop":  # eighth-triplet drive for fights
        seq = [r, fifth, third + 12]
        for i in range(12):
            piano.note(b + i / 3.0, 0.32, seq[i % 3] + (12 if i % 6 == 5 else 0), vel + (8 if i % 3 == 0 else -6))


def sub_bass(song, bar, chord, gain=0.34, pattern="half"):
    f = root_of(chord, 1)
    hz = audio.freq(f)
    if pattern == "half":
        hits = ((0, 2.3), (2.5, 1.4))
    elif pattern == "drive":
        hits = ((0, 0.9), (1, 0.9), (2, 0.9), (3, 0.9))
    else:
        hits = ((0, 3.8),)
    for beat, dur in hits:
        sig = tone(hz, dur * song.beat)
        song.add(bar * 4 + beat, sig * env(len(sig), 0.012, 0.06), 0, gain)


def drums(br, edits, bar, level, drive):
    """Break level 0 none, 1 sparse and filtered, 2 chopped, 3 chopped with fills."""
    if level <= 0:
        return
    program = chopped(edits, bar % 4, drive if level >= 2 else 0.0)
    cutoff = None
    gain = 0.14 + drive * 0.44
    if level == 1:
        program = [event if i in (0, 4, 10, 12) else None for i, event in enumerate(program)]
        cutoff = 1700
        gain = 0.13
    if level >= 3 and bar % 4 == 3:
        program = roll(program, 8 if bar % 8 == 7 else 12, 9)
    elif level == 2 and bar % 8 == 7:
        program = roll(program, 12, 7)
    br.bar(bar, program, gain, cutoff)


def riser(song, bar, bars=1, gain=0.22):
    """Filtered noise swells into `bar` over the `bars` before it."""
    seconds = bars * 4 * song.beat
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    sig = noise(seconds)
    k = (t / seconds) ** 2
    sig = highpass(sig, 1200) * k + lowpass(noise(seconds), 600) * k * 0.4
    sig *= np.linspace(0, 1, n) ** 1.5
    song.add((bar - bars) * 4, sig, 0.0, gain, "dry")


def impact(song, bar, gain=0.5):
    n = int(1.4 * RATE)
    t = np.arange(n) / RATE
    sig = (audio.sweep(90, 38, 1.4, curve=0.3) * np.exp(-t * 3.0) + highpass(noise(1.4), 4000) * np.exp(-t * 8) * 0.4)
    song.add(bar * 4, np.tanh(sig * 1.4), 0, gain, "dry")


# --- Compositions -------------------------------------------------------------------------

TRACKS = {
    # name: (bpm, bars, key progression sets, melody phrases, plan)
    "stage2_boulevard": {
        "bpm": 174,
        "chords": {
            "A": ("Am", "Fmaj7", "Cmaj7", "G", "Am", "Fmaj7", "Dm7", "E7"),
            "B": ("Fmaj7", "G", "Am7", "Em7", "Fmaj7", "G", "Cmaj7", "E7"),
            "C": ("Am", "Fmaj7", "Cmaj7", "G", "Dm7", "Am", "E7", "E7"),
        },
        "melody": {
            "A": "E5:3 D5:1 | C5:2 A4:1 C5:1 | E5:2 G5:1 E5:1 | D5:3 B4:1 | A4:1.5 C5:.5 E5:2 | F5:3 E5:1 | D5:2 F5:1 A5:1 | G#5:3 -:1",
            "B": "A5:3 G5:1 | B5:2 D6:1 B5:1 | C6:3 B5:1 | G5:2 E5:2 | A5:2 C6:1 A5:1 | G5:2 B5:2 | E6:2 D6:1 C6:1 | B5:3 G#5:1",
            "C": "E5:4 | A5:2 G5:2 | E5:3 C5:1 | D5:4 | F5:3 A5:1 | C6:2 B5:2 | G#5:2 B5:2 | E5:4",
        },
        # (section, bars, melody, chords, left hand, drum level, drive, bass)
        "plan": [
            ("intro", 8, "A", "A", "slow", 0, 0.0, None),
            ("verse", 8, "A", "A", "slow", 1, 0.25, "half"),
            ("rise", 16, "B", "B", "arp16", 2, 0.45, "half"),
            ("breakdown", 8, "C", "C", "whole", 0, 0.0, None),
            ("climax", 16, "A", "A", "arp16", 3, 0.75, "drive"),
            ("outro", 8, "C", "C", "slow", 1, 0.3, "half"),
        ],
    },
    "stage2_canyon": {
        "bpm": 176,
        "chords": {
            "A": ("Dm", "Bbmaj7", "Fmaj7", "C", "Dm", "Bbmaj7", "Gm7", "A7"),
            "B": ("Gm7", "Dm", "Bbmaj7", "Fmaj7", "Gm7", "Dm", "A7", "A7"),
            "C": ("Dm", "Bbmaj7", "Gm7", "A7", "Dm", "Bbmaj7", "Gm7", "A7"),
        },
        "melody": {
            "A": "A5:1.5 F5:.5 D5:2 | F5:1 G5:1 A5:2 | C6:3 A5:1 | G5:2 E5:2 | D5:2 F5:1 A5:1 | Bb5:3 A5:1 | G5:2 F5:1 E5:1 | C#5:3 E5:1",
            "B": "D6:2 C6:1 Bb5:1 | A5:3 F5:1 | D6:3 C6:1 | A5:4 | Bb5:2 D6:1 C6:1 | A5:2 F5:2 | E5:2 A5:2 | C#6:3 -:1",
            "C": "D5:2 F5:2 | A5:3 G5:1 | F5:2 D5:2 | E5:4 | D5:2 Bb4:2 | F5:3 E5:1 | D5:2 F5:2 | C#5:4",
        },
        "plan": [
            ("intro", 4, "A", "A", "pulse", 2, 0.35, "half"),
            ("verse", 12, "A", "A", "pulse", 2, 0.5, "half"),
            ("rise", 16, "B", "B", "gallop", 3, 0.65, "drive"),
            ("breakdown", 8, "C", "C", "whole", 0, 0.0, None),
            ("climax", 16, "B", "B", "arp16", 3, 0.85, "drive"),
            ("outro", 8, "A", "A", "slow", 2, 0.4, "half"),
        ],
    },
    "stage2_hovercraft": {
        "bpm": 178,
        "chords": {
            "A": ("Em7", "Cmaj7", "G", "Dm", "Em7", "Cmaj7", "Am7", "B7"),
            "B": ("Am7", "Em7", "Cmaj7", "G", "Am7", "Em7", "B7", "B7"),
        },
        "melody": {
            "A": "B4:1 E5:1 G5:2 | F#5:1 E5:1 D5:2 | B4:1 D5:1 G5:2 | A5:3 -:1 | G5:1 B5:1 E6:2 | D6:1 B5:1 G5:2 | A5:1 C6:1 B5:2 | D#6:3 -:1",
            "B": "C6:1 B5:1 A5:2 | G5:1 E5:1 B5:2 | C6:1 E6:1 G6:2 | F#6:2 D6:2 | E6:1 C6:1 A5:2 | G5:1 B5:1 E6:2 | D#6:2 F#6:2 | B5:3 -:1",
        },
        "plan": [
            ("intro", 4, "A", "A", "gallop", 2, 0.5, "drive"),
            ("verse", 12, "A", "A", "gallop", 3, 0.7, "drive"),
            ("rise", 16, "B", "B", "arp16", 3, 0.85, "drive"),
            ("outro", 16, "A", "A", "pulse", 3, 0.75, "drive"),
        ],
    },
    "stage2_boss": {
        "bpm": 180,
        "chords": {
            "A": ("Bm", "Gmaj7", "D", "A", "Bm", "Gmaj7", "Em7", "F#7"),
            "B": ("Gmaj7", "A", "Bm", "F#m7", "Gmaj7", "A", "D", "F#7"),
            "C": ("Bm", "Gmaj7", "D", "A", "Em7", "Bm", "F#7", "F#7"),
        },
        "melody": {
            "A": "F#5:2 B5:1 D6:1 | C#6:3 B5:1 | A5:2 D6:1 F#6:1 | E6:3 C#6:1 | D6:1.5 B5:.5 F#5:2 | G5:2 B5:2 | E6:2 D6:1 C#6:1 | A#5:3 -:1",
            "B": "D6:2 E6:1 F#6:1 | E6:2 C#6:2 | D6:3 B5:1 | A5:2 C#6:2 | B5:2 D6:1 G6:1 | F#6:3 E6:1 | D6:2 B5:2 | A#5:3 C#6:1",
            "C": "B4:4 | D5:2 G5:2 | F#5:3 A5:1 | E5:4 | G5:2 B5:2 | D6:3 C#6:1 | A#5:2 C#6:2 | F#5:4",
        },
        "plan": [
            ("intro", 4, "A", "A", "gallop", 2, 0.45, "drive"),
            ("verse", 12, "A", "A", "gallop", 3, 0.6, "drive"),
            ("rise", 16, "B", "B", "arp16", 3, 0.75, "drive"),
            ("breakdown", 8, "C", "C", "whole", 0, 0.0, None),
            ("climax", 16, "A", "A", "arp16", 3, 0.9, "drive"),
            ("outro", 8, "C", "C", "pulse", 3, 0.6, "drive"),
        ],
    },
    "stage2_boss_phase2": {
        "bpm": 180,
        "chords": {
            "A": ("Bm", "Gmaj7", "D", "A", "Bm", "Gmaj7", "Em7", "F#7"),
            "B": ("Gmaj7", "A", "Bm", "F#m7", "Gmaj7", "A", "D", "F#7"),
        },
        "melody": {
            "A": "F#6:1 D6:1 B5:2 | E6:1 C#6:1 A5:2 | D6:1 F#6:1 A6:2 | G6:2 E6:2 | F#6:1 D6:1 B5:2 | G6:1 E6:1 B5:2 | E6:1 G6:1 B6:2 | A#6:3 -:1",
            "B": "D6:1 F#6:1 B6:2 | A6:2 C#7:2 | B6:1 A6:1 F#6:2 | E6:2 C#6:2 | D6:1 G6:1 B6:2 | A6:1 F#6:1 C#6:2 | D6:1 F#6:1 A6:2 | A#6:2 C#7:2",
        },
        "plan": [
            ("intro", 4, "A", "A", "arp16", 3, 0.7, "drive"),
            ("verse", 12, "A", "A", "arp16", 3, 0.85, "drive"),
            ("rise", 16, "B", "B", "arp16", 3, 0.95, "drive"),
            ("climax", 16, "A", "A", "arp16", 3, 1.0, "drive"),
            ("outro", 16, "B", "B", "gallop", 3, 0.9, "drive"),
        ],
    },
}


def compose(name, spec):
    bars = sum(p[1] for p in spec["plan"])
    song = Song(spec["bpm"], bars)
    audio.rng = np.random.default_rng(202)
    br = Break(song)
    edits = np.random.default_rng(204)
    piano = Piano(song, seed=hash(name) & 0xFFFF)
    bar = 0
    for section, length, mel, chords_key, hand, level, drive, bass in spec["plan"]:
        chords = spec["chords"][chords_key]
        lead = phrase(spec["melody"][mel])
        for i in range(length):
            chord = chords[i % 8]
            left_hand(piano, bar, chord, hand)
            drums(br, edits, bar, level, drive)
            if bass:
                sub_bass(song, bar, chord, 0.24, bass)
            bar += 1
        # The melody runs in eight-bar phrases through the section, the last bar leaning into the next.
        start = bar - length
        for phrase_start in range(0, length, 8):
            for beat, beats, m in lead:
                if m is None:
                    continue
                at = (start + phrase_start) * 4 + beat
                octave_double = section == "climax"
                piano.note(at, beats, m, 96 if section != "breakdown" else 84, human=0.01)
                if octave_double:
                    piano.note(at, beats, m - 12, 70)
        if section in ("verse", "rise", "climax", "breakdown"):
            riser(song, start + length if start + length < bars else bars, 1, 0.4 if start + length >= bars else 0.22)
        if section == "climax" or (section == "rise" and level >= 3):
            impact(song, start, 0.5)
        for b in range(start, start + length):
            piano.pedal(b * 4, b * 4 + 3.9)
    piano.render(gain=3.2)
    # Bend the last 12 ms onto the first sample, so the loop seam is continuous whatever the waveform's phase.
    ramp = np.linspace(0.0, 1.0, 512)
    for bus in song.buses.values():
        for channel in bus:
            channel[-512:] += (channel[0] - channel[-1]) * ramp
            channel[:96] *= 0.5 + 0.5 * np.linspace(0.0, 1.0, 96)
            channel[-96:] *= 0.5 + 0.5 * np.linspace(1.0, 0.0, 96)
    song.render(name, 0.75, 0.2, 0.0, pump=0, pedal=False)


def stage2_music(only=None):
    for name, spec in TRACKS.items():
        if only is None or name in only:
            compose(name, spec)
