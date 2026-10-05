"""Stage 2 music: a 90s arcade shooter band, Strikers 1945 style, with a lyrical streak.

A rock kit, FM slap bass in octaves, overdriven rhythm and lead guitar, synth brass, and FM electric piano, bells and
strings for the quiet bridges. Every track has its own key, tempo and form; the boss's phase two is the same song a
whole step up with the drums doubled. Everything is synthesized here and in audio.py.
"""

import numpy as np

import audio
from audio import RATE, Song, chord_notes, crash, env, freq, highpass, lead, lowpass, melody, midi, noise, power_chord, saw_stack, t_axis, tom

NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


def transpose(chord, shift):
    root = chord[:2] if len(chord) > 1 and chord[1] in "#b" else chord[0]
    return NAMES[(midi(root + "4") + shift) % 12] + chord[len(root):]


# --- Instruments ---------------------------------------------------------------------------

def fm(f, seconds, ratio, index, index_decay, decay):
    """Two-operator FM: a sine carrier phase-modulated by a sine at `ratio` whose depth decays."""
    t = t_axis(seconds)
    depth = index * np.exp(-t * index_decay)
    return np.sin(2 * np.pi * f * t + depth * np.sin(2 * np.pi * f * ratio * t)) * np.exp(-t * decay)


def kick():
    n = int(0.3 * RATE)
    t = np.arange(n) / RATE
    body = audio.sweep(130, 46, 0.3, curve=0.2) * np.exp(-t * 9)
    click = highpass(noise(0.3), 3000) * np.exp(-t * 400) * 0.5
    return np.tanh((body + click) * 2.0)


def snare():
    """A tight snare with a short gated room, the 90s arcade crack."""
    n = int(0.32 * RATE)
    t = np.arange(n) / RATE
    body = (np.sin(2 * np.pi * 190 * t) + 0.5 * np.sin(2 * np.pi * 340 * t)) * np.exp(-t * 28) * 0.7
    wires = lowpass(highpass(noise(0.32), 1800), 10000) * np.exp(-t * 16)
    gate = np.where(t < 0.18, 1.0, np.exp(-(t - 0.18) * 60))
    room = lowpass(noise(0.32), 6000) * 0.25 * gate
    return np.tanh((body + wires + room) * 1.4)


def hat(open_hat=False):
    seconds = 0.32 if open_hat else 0.06
    t = t_axis(seconds)
    metal = sum(np.sign(np.sin(2 * np.pi * f * t)) for f in (317.0, 433.0, 547.0, 811.0, 1021.0))
    return highpass(metal * 0.3 + noise(seconds), 7000) * np.exp(-t * (9 if open_hat else 70)) * 0.35


def fm_bass(m, seconds):
    """Slap bass: a bright FM pop that settles into a round note over a sine sub."""
    f = freq(m)
    t = t_axis(seconds)
    sig = fm(f, seconds, 1.0, 3.2, 16, 2.2) + 0.5 * np.sin(2 * np.pi * f * t) * np.exp(-t * 1.5)
    return np.tanh(sig * 1.6) * env(len(sig), 0.002, 0.03)


def epiano(m, seconds):
    """FM electric piano: a mellow 1:1 body and a short bright tine at 14:1."""
    f = freq(m)
    body = fm(f, seconds, 1.0, 1.4, 3.0, 1.6)
    tine = fm(f, seconds, 14.0, 1.2, 28.0, 9.0) * 0.25
    return (body + tine) * env(len(body), 0.002, 0.08)


def bell(m, seconds):
    f = freq(m)
    sig = fm(f, seconds, 3.5, 1.4, 2.0, 1.1) + 0.3 * fm(f * 2, seconds, 1.0, 0.5, 1.0, 2.0)
    return sig * env(len(sig), 0.002, 0.1)


def strings(notes, seconds):
    raw = sum(saw_stack(freq(m), seconds, (-9.0, 0.0, 8.0)) for m in notes) / len(notes)
    return lowpass(lowpass(raw, 2200), 3000) * env(len(raw), 0.35, 0.5)


def guitar(m, seconds):
    """Overdriven lead guitar: a slide up into the note, delayed vibrato, a dark cabinet."""
    t = t_axis(seconds)
    bend = -80 * np.clip(1 - t / 0.06, 0, 1)
    vib = np.sin(2 * np.pi * 6.2 * t) * 22 * np.clip((t - 0.25) * 2.5, 0, 1)
    phase = 2 * np.pi * np.cumsum(freq(m) * 2 ** ((bend + vib) / 1200)) / RATE
    raw = sum(np.sin(phase * h) / h for h in range(1, 24) if freq(m) * h < RATE / 2.4)
    sig = lowpass(np.tanh(raw * 4.5), 3600)
    return highpass(sig, 120) * env(len(t), 0.004, 0.06, decay=0.6, sustain=0.75)


def orchestra_hit(notes, song):
    sig = sum(audio.brass(m, 1.0, song, stab=True) for m in notes + [m + 12 for m in notes]) / 3
    n = len(sig)
    sig = sig + highpass(noise(n / RATE), 2500) * np.exp(-np.arange(n) / RATE * 18) * 0.6
    boom = tom(52)
    sig[: len(boom)] += boom[:n] * 0.9
    return sig


# --- Parts ---------------------------------------------------------------------------------

class Kit:
    def __init__(self):
        self.k, self.s, self.h, self.o, self.c = kick(), snare(), hat(), hat(True), crash()
        self.toms = [tom(f) for f in (190, 150, 115, 90)]


def drum_bar(song, kit, bar, style, fill):
    b = bar * 4

    def put(beat, sig, gain, pan=0.0):
        song.add(b + beat, sig, pan, gain)

    if style == "rock":  # kick on 1 and 3 with a push, snare on 2 and 4, eighth hats
        for beat in (0, 1.5, 2, 3.5 if bar % 2 else 2.75):
            put(beat, kit.k, 0.8)
        for beat in (1, 3):
            put(beat, kit.s, 0.75)
        for i in range(8):
            put(i * 0.5, kit.o if i == 7 and bar % 4 == 3 else kit.h, 0.5 if i % 2 == 0 else 0.32, 0.3)
    elif style == "double":  # driving: kick on every beat, snare on the offbeats, sixteenth hats
        for i in range(8):
            put(i * 0.5, kit.k if i % 2 == 0 else kit.s, 0.75 if i % 2 == 0 else 0.6)
        for i in range(16):
            put(i * 0.25, kit.h, 0.42 if i % 2 == 0 else 0.28, 0.3)
    elif style == "gallop":  # kick gallop under a backbeat
        for beat in (0, 0.75, 1.0, 2.0, 2.75, 3.0):
            put(beat, kit.k, 0.7)
        for beat in (1, 3):
            put(beat, kit.s, 0.75)
        for i in range(8):
            put(i * 0.5, kit.h, 0.4, 0.3)
    elif style == "half":  # half time: snare on 3, open hats on the beat
        put(0, kit.k, 0.8)
        put(2.5, kit.k, 0.55)
        put(2, kit.s, 0.75)
        for i in range(4):
            put(i, kit.o, 0.22, 0.3)
    elif style == "toms":  # tom ostinato for menacing intros
        for i, beat in enumerate((0, 0.75, 1.5, 2, 2.75, 3.5)):
            put(beat, kit.toms[2 + i % 2], 0.7, -0.3 if i % 2 else 0.3)
        put(0, kit.k, 0.7)
    elif style == "light":  # hats and a soft kick under quiet sections
        put(0, kit.k, 0.45)
        for i in range(8):
            put(i * 0.5, kit.h, 0.25, 0.3)
    if fill:
        for i in range(8):  # sixteenth tom run down the kit over beats 3-4, closing on the snare
            put(2 + i * 0.25, kit.toms[i // 2] if i < 7 else kit.s, 0.75, 0.4 - i * 0.1)


def bass_bar(song, chord, bar, style):
    r = chord_notes(chord, 1)[0]
    if r < midi("E1"):
        r += 12
    b = bar * 4
    if style == "oct8":  # octave eighths, the shooter bass signature
        for i in range(8):
            song.add(b + i * 0.5, fm_bass(r + (12 if i % 2 else 0), 0.5 * song.beat + 0.04), 0.0, 0.3)
    elif style == "walk":  # root, fifth, octave and a pickup into the next bar
        for i, m in enumerate((r, r, r + 7, r + 12, r, r + 7, r + 12, r + 10)):
            song.add(b + i * 0.5, fm_bass(m, 0.5 * song.beat + 0.04), 0.0, 0.3)
    elif style == "gallop":
        for i in range(16):
            if i % 4 != 1:
                song.add(b + i * 0.25, fm_bass(r + (12 if i % 4 == 3 else 0), 0.24 * song.beat), 0.0, 0.3)
    elif style == "long":
        song.add(b, fm_bass(r, 3.9 * song.beat), 0.0, 0.32)
        song.add(b + 3.5, fm_bass(r + 12, 0.45 * song.beat), 0.0, 0.22)


def guitar_bar(song, chord, bar, style):
    r = chord_notes(chord, 2)[0]
    if r < midi("E2"):
        r += 12
    b = bar * 4
    if style == "chug":
        for i in range(8):
            accent = i in (0, 3, 6)
            song.add(b + i * 0.5, power_chord(r, 0.45, song, mute=not accent), -0.55 if i % 2 else 0.55, 0.2 if accent else 0.15)
    elif style == "gallop":
        for i in range(16):
            if i % 4 != 1:
                song.add(b + i * 0.25, power_chord(r, 0.22, song), -0.55 if i % 2 else 0.55, 0.16)
    elif style == "ring":
        for pan in (-0.5, 0.5):
            song.add(b, power_chord(r, 3.8, song, mute=False), pan, 0.17)
    elif style == "stab":  # syncopated hits that leave room for the lead
        for beat in (0, 0.75, 1.5, 3.0):
            song.add(b + beat, power_chord(r, 0.6, song, mute=False), 0.0, 0.2)


def keys_bar(song, chord, bar, style):
    notes = chord_notes(chord, 4)
    b = bar * 4
    if style in ("arp", "both"):
        seq = notes[:3] + [notes[0] + 12, notes[2] + 12, notes[0] + 12] + notes[2:0:-1]
        for i in range(8):
            song.add(b + i * 0.5, epiano(seq[i % len(seq)], 0.9 * song.beat), 0.35 if i % 2 else -0.35, 0.16, "wet")
    if style in ("pad", "both"):
        voiced = tuple([chord_notes(chord, 3)[0]] + notes[:3])
        sig = strings(voiced, 4 * song.beat + 0.3)
        song.add(b, sig, -0.4, 0.13)
        song.add(b + 0.01 / song.beat, sig, 0.4, 0.13)


def under(m, chord):
    """The highest chord tone at least a minor third below `m`: a consonant harmony line."""
    return max(n + 12 * o for n in chord_notes(chord, 0) for o in range(10) if n + 12 * o <= m - 3)


def lead_line(song, text, start_bar, chords, voice, shift, harmonize):
    for beat, beats, m in melody(text):
        if m is None:
            continue
        m += shift
        at = start_bar * 4 + beat
        beats += 0.12 / song.beat  # legato: each note releases under the next, and the loop's last note across the seam
        seconds = beats * song.beat
        if voice in ("brass", "both"):
            song.add(at, lead(m, beats, song), 0.15, 0.3, "wet")
        if voice in ("guitar", "both"):
            song.add(at, guitar(m - (12 if voice == "both" else 0), seconds + 0.05), -0.15, 0.24 if voice == "both" else 0.3, "wet")
        if voice == "bell":
            song.add(at, bell(m, seconds + 0.6), 0.1, 0.3, "wet")
        if voice == "epiano":
            song.add(at, epiano(m, seconds + 0.4), 0.1, 0.32, "wet")
        if harmonize:
            song.add(at, lead(under(m, chords[int(beat // 4) % len(chords)]), beats, song), -0.3, 0.17, "wet")


# --- Arrangement ---------------------------------------------------------------------------

def compose(name, bpm, sections, shift=0):
    """sections: dicts with bars and chords, and optionally lead, voice, octave, harmony, drums, fill, bass, gtr,
    keys and hits."""
    song = Song(bpm, sum(s["bars"] for s in sections))
    audio.rng = np.random.default_rng(301)
    kit = Kit()
    bar = 0
    for index, section in enumerate(sections):
        chords = [transpose(c, shift) for c in section["chords"]]
        drums = section.get("drums")
        for i in range(section["bars"]):
            chord = chords[i % len(chords)]
            if drums:
                drum_bar(song, kit, bar, drums, i == section["bars"] - 1 and section.get("fill", True))
            if section.get("bass"):
                bass_bar(song, chord, bar, section["bass"])
            if section.get("gtr"):
                guitar_bar(song, chord, bar, section["gtr"])
            if section.get("keys"):
                keys_bar(song, chord, bar, section["keys"])
            if section.get("hits") and i % 4 == 0:
                song.add(bar * 4, orchestra_hit(chord_notes(chord, 3), song), 0.0, 0.32)
            bar += 1
        start = bar - section["bars"]
        if section.get("lead"):
            text = " ".join(t for t in section["lead"].split() if t != "|")
            span = int(round(sum(d for _, d, _ in melody(text)) / 4))
            for phrase in range(start, bar, span):
                lead_line(song, text, phrase, chords[(phrase - start) % len(chords):] + chords, section.get("voice", "brass"),
                          shift + section.get("octave", 0), section.get("harmony", False))
        if drums and drums not in ("light", "half") and index > 0:
            song.add(start * 4, kit.c, 0.3, 0.4)
    # Bend the last 12 ms onto the first sample, so the loop seam is continuous whatever the waveform's phase.
    ramp = np.linspace(0.0, 1.0, 512)
    for bus in song.buses.values():
        for channel in bus:
            channel[-512:] += (channel[0] - channel[-1]) * ramp
            channel[:96] *= 0.5 + 0.5 * np.linspace(0.0, 1.0, 96)
            channel[-96:] *= 0.5 + 0.5 * np.linspace(1.0, 0.0, 96)
    song.render(name, 0.75, 0.25, 0.22, pump=0.0)


# --- Compositions --------------------------------------------------------------------------
# Boulevard: D minor at dawn. FM piano and bells state the theme quietly, the band takes it up, the chorus turns
# heroic, a bridge in the relative major breathes, then the theme returns, a guitar solo and the chorus close the loop.

D_VERSE = ["Dm", "Bb", "F", "C", "Gm", "Bb", "Asus", "A"]
D_THEME = "D5:1.5 E5:.5 F5:1 A5:1 | G5:2 F5:1 D5:1 | C5:1.5 D5:.5 F5:1 C6:1 | A5:3 G5:1 | Bb5:1.5 A5:.5 G5:1 F5:1 | D5:1 F5:1 Bb5:1 A5:1 | A5:1 G5:1 F5:1 E5:1 | E5:3 -:1"
D_THEME_2 = "D5:1.5 E5:.5 F5:1 A5:1 | G5:2 F5:1 D5:1 | C5:1.5 D5:.5 F5:1 C6:1 | A5:3 G5:1 | Bb5:1.5 A5:.5 G5:1 F5:1 | D5:1 F5:1 Bb5:1 D6:1 | D6:1 E6:1 D6:1 C#6:1 | A5:3 -:1"
D_CHORUS = ["Bb", "C", "Dm", "Dm", "Bb", "C", "F", "A", "Gm", "A", "Dm", "Bb", "Gm", "C", "A", "A"]
D_HOOK = ("F5:1 Bb5:1 D6:2 | C6:1.5 Bb5:.5 C6:1 E6:1 | F6:3 E6:.5 D6:.5 | D6:2 A5:2 | Bb5:1 D6:1 F6:2 | E6:1.5 D6:.5 C6:1 G5:1 | "
          "A5:1.5 C6:.5 F6:2 | E6:3 C#6:1 | D6:1.5 Bb5:.5 G5:2 | C#6:1.5 A5:.5 E6:2 | F6:1 E6:1 D6:1 A5:1 | Bb5:2 D6:1 F6:1 | "
          "G6:2 F6:1 D6:1 | E6:2 C6:1 G5:1 | A5:1 C#6:1 E6:1 G6:1 | A5:4")
D_BRIDGE = ["Bb", "C", "Am", "Dm", "Gm", "C", "F", "A7"]
D_SONG = "D5:3 F5:1 | E5:2 G5:2 | A5:2 E5:2 | F5:3 D5:1 | G5:2 Bb5:1 D6:1 | C6:3 Bb5:1 | A5:2 F5:1 C5:1 | C#5:2 E5:1 G5:1"
D_SOLO = ("D5:.5 F5:.5 A5:.5 D6:.5 C6:.5 A5:.5 F5:.5 A5:.5 | Bb5:.5 D6:.5 F6:.5 D6:.5 Bb5:1 A5:1 | C6:.5 A5:.5 F5:.5 A5:.5 C6:1 F6:1 | "
          "E6:1.5 D6:.5 C6:1 G5:1 | G5:.5 Bb5:.5 D6:.5 G6:.5 F6:.5 D6:.5 Bb5:.5 D6:.5 | F6:2 D6:1 Bb5:1 | "
          "A5:.5 D6:.5 E6:.5 D6:.5 A5:.5 D6:.5 E6:.5 G6:.5 | E6:1 C#6:1 A5:2")

BOULEVARD = [
    {"bars": 8, "chords": D_VERSE, "lead": D_THEME, "voice": "bell", "keys": "pad", "bass": "long"},
    {"bars": 8, "chords": D_VERSE, "lead": D_THEME, "voice": "brass", "drums": "rock", "bass": "oct8", "gtr": "chug"},
    {"bars": 16, "chords": D_CHORUS, "lead": D_HOOK, "voice": "both", "harmony": True, "drums": "double", "bass": "oct8", "gtr": "chug", "keys": "pad"},
    {"bars": 8, "chords": D_BRIDGE, "lead": D_SONG, "voice": "epiano", "keys": "both", "drums": "half", "bass": "long"},
    {"bars": 8, "chords": D_VERSE, "lead": D_THEME_2, "voice": "both", "drums": "rock", "bass": "oct8", "gtr": "chug", "keys": "pad"},
    {"bars": 8, "chords": D_VERSE, "lead": D_SOLO, "voice": "guitar", "octave": 12, "drums": "rock", "bass": "walk", "gtr": "stab", "keys": "pad"},
    {"bars": 8, "chords": D_CHORUS[8:], "lead": "|".join(D_HOOK.split("|")[8:]), "voice": "both", "harmony": True, "drums": "double", "bass": "oct8", "gtr": "chug", "keys": "pad"},
]

# Canyon: E minor, harmonic-minor tension at a gallop; a bell interlude in the middle like light between towers.
E_RIFF = ["Em", "C", "D", "B", "Em", "C", "Am", "B"]
E_THEME = "E5:.5 F#5:.5 G5:1 B5:1.5 A5:.5 | G5:1 E5:1 C6:2 | A5:1.5 F#5:.5 D5:1 F#5:1 | D#5:2 F#5:1 B5:1 | E6:1.5 D6:.5 B5:1 G5:1 | C6:1.5 B5:.5 A5:1 G5:1 | A5:1 C6:1 E6:1 C6:1 | D#6:3 -:1"
E_RISE = ["C", "D", "Em", "Em", "C", "D", "B", "B"]
E_CLIMB = "G5:1 C6:1 E6:2 | F#6:1.5 E6:.5 D6:2 | E6:1 B5:1 G5:1 B5:1 | E6:3 -:1 | G6:2 E6:1 C6:1 | F#6:2 D6:1 A5:1 | B5:1 D#6:1 F#6:1 A6:1 | B6:4"
E_QUIET = ["Em", "C", "G", "D", "Am", "C", "B", "B"]
E_LIGHT = "B4:3 G4:1 | E5:2 C5:2 | D5:3 B4:1 | A4:2 F#4:2 | C5:3 E5:1 | G5:2 E5:2 | F#5:2 D#5:2 | B4:4"

CANYON = [
    {"bars": 4, "chords": ["Em"], "drums": "toms", "bass": "gallop"},
    {"bars": 4, "chords": E_RIFF[:4], "drums": "gallop", "bass": "gallop", "gtr": "gallop"},
    {"bars": 8, "chords": E_RIFF, "lead": E_THEME, "voice": "guitar", "drums": "gallop", "bass": "gallop", "gtr": "chug"},
    {"bars": 8, "chords": E_RIFF, "lead": E_THEME, "voice": "both", "harmony": True, "octave": 12, "drums": "rock", "bass": "oct8", "gtr": "chug", "keys": "pad"},
    {"bars": 16, "chords": E_RISE, "lead": E_CLIMB, "voice": "both", "octave": -12, "harmony": True, "drums": "double", "bass": "oct8", "gtr": "gallop", "hits": True},
    {"bars": 8, "chords": E_QUIET, "lead": E_LIGHT, "voice": "bell", "octave": 12, "keys": "both", "drums": "half", "bass": "long"},
    {"bars": 8, "chords": E_RIFF, "lead": E_THEME, "voice": "brass", "drums": "gallop", "bass": "gallop", "gtr": "gallop", "keys": "pad"},
    {"bars": 8, "chords": E_RISE, "lead": E_CLIMB, "voice": "both", "octave": -12, "harmony": True, "drums": "double", "bass": "oct8", "gtr": "chug", "keys": "pad", "hits": True},
]

# Hovercraft: C minor, the fastest track: orchestra hits and a soaring counter-melody in the relative major.
C_RIFF = ["Cm", "Ab", "Bb", "G", "Cm", "Ab", "Fm", "G"]
C_THEME = "C5:.5 Eb5:.5 G5:.5 C6:.5 Bb5:1 G5:1 | Ab5:1.5 G5:.5 Eb5:2 | F5:.5 G5:.5 Bb5:1 D6:2 | B5:2 G5:1 D5:1 | C6:1.5 D6:.5 Eb6:1 G6:1 | F6:1.5 Eb6:.5 C6:2 | Ab5:1 C6:1 F6:1 Eb6:1 | D6:2 B5:2"
C_SKY = ["Ab", "Bb", "Gm", "Cm", "Ab", "Bb", "G", "G"]
C_SOAR = "C6:2 Eb6:2 | D6:3 Bb5:1 | G5:2 Bb5:1 D6:1 | C6:4 | Ab5:2 C6:1 Eb6:1 | F6:2 D6:2 | B5:2 D6:1 F6:1 | G6:4"

HOVERCRAFT = [
    {"bars": 4, "chords": ["Cm", "Ab", "Bb", "G"], "drums": "toms", "bass": "oct8", "hits": True, "gtr": "ring"},
    {"bars": 8, "chords": C_RIFF, "lead": C_THEME, "voice": "brass", "drums": "double", "bass": "oct8", "gtr": "chug"},
    {"bars": 8, "chords": C_RIFF, "lead": C_THEME, "voice": "both", "harmony": True, "drums": "double", "bass": "oct8", "gtr": "gallop", "hits": True},
    {"bars": 8, "chords": C_SKY, "lead": C_SOAR, "voice": "both", "octave": -12, "drums": "rock", "bass": "walk", "keys": "pad"},
    {"bars": 4, "chords": ["Cm", "Cm", "Ab", "G"], "drums": "gallop", "bass": "gallop", "gtr": "gallop"},
    {"bars": 8, "chords": C_RIFF, "lead": C_THEME, "voice": "guitar", "octave": 12, "harmony": True, "drums": "double", "bass": "oct8", "gtr": "chug", "hits": True},
    {"bars": 8, "chords": C_SKY, "lead": C_SOAR, "voice": "both", "octave": -12, "harmony": True, "drums": "double", "bass": "oct8", "gtr": "chug", "keys": "pad"},
]

# Boss: A minor. A tom-and-riff opening, a dark theme, a heroic answer and a lyrical breakdown; phase two is the same
# song a whole step up with the drums driving throughout.
A_RIFF = ["Am", "F", "G", "E", "Am", "F", "Dm", "E"]
A_THEME = "A4:1.5 C5:.5 E5:1 A5:1 | G5:1.5 F5:.5 C5:2 | D5:1 G5:1 B5:1 D6:1 | B5:2 G#5:2 | A5:1 C6:1 E6:1.5 D6:.5 | C6:1 A5:1 F5:2 | D6:1.5 C6:.5 A5:1 F5:1 | G#5:2 B5:1 E6:1"
A_HERO = ["Dm", "G", "C", "Am", "F", "G", "E", "E"]
A_ANSWER = "F5:1 A5:1 D6:2 | B5:1 D6:1 G6:2 | E6:1.5 D6:.5 C6:1 G5:1 | C6:2 A5:2 | A5:1 C6:1 F6:1.5 E6:.5 | D6:1 B5:1 G5:1 B5:1 | G#5:1 B5:1 E6:2 | D6:2 B5:2"
A_LAMENT = "A4:3 C5:1 | F5:2 E5:2 | D5:3 B4:1 | G#4:4 | A4:2 C5:1 E5:1 | F5:3 A5:1 | F5:2 D5:2 | E5:4"


def boss_sections(phase_two):
    driving = "double" if phase_two else "rock"
    return [
        {"bars": 8, "chords": ["Am", "Am", "F", "E"], "drums": driving if phase_two else "toms", "bass": "long", "gtr": "ring", "hits": True},
        {"bars": 8, "chords": A_RIFF, "drums": driving, "bass": "oct8", "gtr": "gallop" if phase_two else "chug"},
        {"bars": 8, "chords": A_RIFF, "lead": A_THEME, "voice": "both" if phase_two else "guitar", "drums": driving, "bass": "oct8", "gtr": "chug"},
        {"bars": 8, "chords": A_RIFF, "lead": A_THEME, "voice": "both", "harmony": True, "drums": driving, "bass": "oct8", "gtr": "gallop", "keys": "pad"},
        {"bars": 16, "chords": A_HERO, "lead": A_ANSWER, "voice": "both", "harmony": True, "drums": "double", "bass": "oct8", "gtr": "chug", "keys": "pad", "hits": True},
        {"bars": 8, "chords": A_RIFF, "lead": A_LAMENT, "voice": "epiano", "octave": 12, "keys": "both", "drums": "gallop" if phase_two else "light", "bass": "long"},
        {"bars": 8, "chords": A_HERO, "lead": A_ANSWER, "voice": "both", "harmony": True, "drums": "double", "bass": "oct8", "gtr": "gallop", "keys": "pad", "hits": True},
    ]


TRACKS = {
    "stage2_boulevard": (152, BOULEVARD, 0),
    "stage2_canyon": (164, CANYON, 0),
    "stage2_hovercraft": (170, HOVERCRAFT, 0),
    "stage2_boss": (160, boss_sections(False), 0),
    "stage2_boss_phase2": (160, boss_sections(True), 2),
}


def stage2_music(only=None):
    for name, (bpm, sections, shift) in TRACKS.items():
        if only is None or name in only:
            compose(name, bpm, sections, shift)


if __name__ == "__main__":
    import sys
    stage2_music(sys.argv[1:] or None)
