#!/usr/bin/env python3
"""Makes every sound and music loop in Resources/Sounds, from scratch, so there is nothing
to license. Effects are short mono WAV files; music is a seamless AAC loop per planet.

Change a recipe below and run again:  python3 Tools/make_sounds.py
Needs numpy, scipy and ffmpeg (brew install ffmpeg).
"""
import os, subprocess, tempfile
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(7)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "Resources", "Sounds"))


# ---------- building blocks ----------

def t_of(seconds):
    return np.arange(int(seconds * SR)) / SR

def env(n, attack=0.005, release=0.1, hold=None):
    """Attack, optional hold, then exponential-ish release, over n samples."""
    e = np.ones(n)
    a = max(1, int(attack * SR))
    e[:a] = np.linspace(0, 1, a)
    start = a if hold is None else min(n, a + int(hold * SR))
    tail = n - start
    if tail > 0:
        e[start:] = np.exp(-np.linspace(0, 1, tail) * (5 / max(release, 1e-3)) * (tail / SR))
    return e

def sweep(f0, f1, seconds, shape="sine", curve=1.0):
    """An oscillator gliding from f0 to f1."""
    n = int(seconds * SR)
    k = np.linspace(0, 1, n) ** curve
    f = f0 + (f1 - f0) * k
    phase = 2 * np.pi * np.cumsum(f) / SR
    if shape == "sine":
        return np.sin(phase)
    if shape == "square":
        return np.sign(np.sin(phase)) * 0.6
    if shape == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1) - 1
    if shape == "tri":
        return 2 * np.abs(2 * ((phase / (2 * np.pi)) % 1) - 1) - 1
    raise ValueError(shape)

def noise(seconds):
    return rng.uniform(-1, 1, int(seconds * SR))

def lowpass(x, hz, order=2):
    b, a = signal.butter(order, min(hz, SR / 2 - 100) / (SR / 2), "low")
    return signal.lfilter(b, a, x)

def highpass(x, hz, order=2):
    b, a = signal.butter(order, hz / (SR / 2), "high")
    return signal.lfilter(b, a, x)

def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi, SR / 2 - 100) / (SR / 2)], "band")
    return signal.lfilter(b, a, x)

def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out

def delay(x, at):
    return np.concatenate([np.zeros(int(at * SR)), x])

def bell(freq, seconds, bright=2.0):
    """A soft FM bell."""
    t = t_of(seconds)
    mod = np.sin(2 * np.pi * freq * 3.5 * t) * bright * np.exp(-t * 6)
    return np.sin(2 * np.pi * freq * t + mod) * np.exp(-t * 3.2)

def normalize(x, peak=0.85):
    m = np.max(np.abs(x))
    return x if m == 0 else x / m * peak

def fade_edges(x, ms=4):
    n = int(ms / 1000 * SR)
    x = x.copy()
    x[:n] *= np.linspace(0, 1, n)
    x[-n:] *= np.linspace(1, 0, n)
    return x

def save_sfx(name, x, peak=0.85):
    x = fade_edges(normalize(x, peak))
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))


# ---------- effects ----------

def make_effects():
    # Laser: a bright zap when you start firing, a buzzing hum while held, a crackle per blasted block.
    zap = sweep(1800, 380, 0.16, "saw", 0.5) * env(int(0.16 * SR), 0.002, 0.12)
    save_sfx("laser-start", lowpass(zap, 6000) + 0.3 * sweep(3600, 760, 0.16) * env(int(0.16 * SR), 0.002, 0.1), 0.6)

    # A loop has to join up exactly: whole cycles of every partial over 0.5 s.
    t = t_of(0.5)
    hum = (np.sin(2 * np.pi * 220 * t) * 0.5 + np.sin(2 * np.pi * 440 * t) * 0.3
           + np.sign(np.sin(2 * np.pi * 110 * t)) * 0.12 + np.sin(2 * np.pi * 880 * t) * 0.15)
    hum *= 1 + 0.25 * np.sin(2 * np.pi * 16 * t)
    wavfile.write(os.path.join(OUT, "laser-loop.wav"), SR, (normalize(hum, 0.5) * 32767).astype(np.int16))

    crackle = bandpass(noise(0.18), 700, 5000) * env(int(0.18 * SR), 0.001, 0.08)
    pop = sweep(600, 120, 0.12, "sine", 0.4) * env(int(0.12 * SR), 0.001, 0.08)
    save_sfx("blast", mix(crackle * 0.8, pop), 0.75)

    # Blocks.
    crunch = lowpass(noise(0.16), 2400) * env(int(0.16 * SR), 0.001, 0.07)
    thump = sweep(240, 90, 0.14, "sine", 0.5) * env(int(0.14 * SR), 0.001, 0.09)
    save_sfx("break", mix(crunch, thump * 0.9), 0.8)
    knock = sweep(320, 180, 0.1, "tri", 0.7) * env(int(0.1 * SR), 0.001, 0.06)
    tick = bandpass(noise(0.03), 1500, 4000) * env(int(0.03 * SR), 0.001, 0.015)
    save_sfx("place", mix(knock, tick * 0.4), 0.7)

    # Footsteps: three soft scuffs so walking doesn't sound like a machine.
    for i in range(3):
        n = 0.09 + 0.02 * i
        scuff = lowpass(noise(n), 900 + 300 * i) * env(int(n * SR), 0.004, 0.05)
        tap = sweep(140 + 20 * i, 80, n, "sine") * env(int(n * SR), 0.001, 0.04)
        save_sfx(f"step-{i + 1}", mix(scuff, tap * 0.6), 0.5)

    save_sfx("jump", sweep(260, 620, 0.14, "tri", 0.6) * env(int(0.14 * SR), 0.003, 0.09), 0.5)
    land = lowpass(noise(0.12), 600) * env(int(0.12 * SR), 0.001, 0.06)
    save_sfx("land", mix(land, sweep(130, 60, 0.12) * env(int(0.12 * SR), 0.001, 0.08)), 0.6)

    whoosh_up = bandpass(noise(0.6), 300, 2500) * np.sin(np.linspace(0, np.pi, int(0.6 * SR))) ** 2
    save_sfx("fly-on", mix(whoosh_up * 0.7, sweep(300, 900, 0.6, "sine", 0.8) * env(int(0.6 * SR), 0.05, 0.4) * 0.4), 0.6)
    whoosh_down = bandpass(noise(0.5), 200, 1800) * np.sin(np.linspace(0, np.pi, int(0.5 * SR))) ** 2
    save_sfx("fly-off", mix(whoosh_down * 0.7, sweep(700, 250, 0.5, "sine") * env(int(0.5 * SR), 0.05, 0.3) * 0.4), 0.6)

    # Starship: a rumble that rises into a whoosh.
    n = 2.4
    rumble = lowpass(noise(n), 180, 3) * np.linspace(0.3, 1, int(n * SR))
    rise = sweep(70, 520, n, "saw", 1.6) * np.linspace(0.1, 1, int(n * SR))
    swoosh = bandpass(noise(n), 400, 5000) * np.linspace(0, 1, int(n * SR)) ** 3
    launch = mix(rumble * 1.4, lowpass(rise, 1500) * 0.35, swoosh * 0.6) * env(int(n * SR), 0.2, 0.25, hold=1.9)
    save_sfx("launch", launch, 0.85)

    # Menus and hotbar.
    save_sfx("menu-move", sweep(900, 900, 0.05, "tri") * env(int(0.05 * SR), 0.001, 0.03), 0.35)
    save_sfx("menu-select", mix(bell(660, 0.25, 1.0), delay(bell(990, 0.3, 1.0), 0.06)), 0.5)
    save_sfx("hotbar", sweep(1300, 1100, 0.04, "sine") * env(int(0.04 * SR), 0.001, 0.02), 0.3)

    # Critters.
    chirp = mix(*[delay(sweep(2400 + 300 * k, 3400 + 300 * k, 0.07, "sine") * env(int(0.07 * SR), 0.003, 0.04), 0.09 * k) for k in range(3)])
    save_sfx("critter-chirp", chirp, 0.45)
    boop = sweep(300, 180, 0.22, "sine", 0.6) * env(int(0.22 * SR), 0.01, 0.15)
    boop += 0.3 * sweep(600, 360, 0.22, "sine", 0.6) * env(int(0.22 * SR), 0.01, 0.12)
    save_sfx("critter-boop", mix(boop, delay(boop * 0.8, 0.2)), 0.55)
    squeak = sweep(1200, 1900, 0.12, "tri", 0.5) * env(int(0.12 * SR), 0.004, 0.08)
    save_sfx("critter-squeak", mix(squeak, delay(sweep(1500, 2200, 0.1, "tri") * env(int(0.1 * SR), 0.004, 0.06), 0.14)), 0.45)
    click = mix(*[delay(bandpass(noise(0.02), 2500, 7000) * env(int(0.02 * SR), 0.0005, 0.01), 0.06 * k) for k in range(4)])
    save_sfx("critter-click", mix(click, bell(1760, 0.3, 0.5) * 0.3), 0.5)
    happy = mix(*[delay(bell(f, 0.5, 1.2), 0.08 * k) for k, f in enumerate([784, 988, 1175, 1568])])
    save_sfx("befriend", happy, 0.6)

    growl = lowpass(sweep(95, 75, 0.5, "saw") * (1 + 0.6 * np.sin(2 * np.pi * 22 * t_of(0.5))), 900) * env(int(0.5 * SR), 0.03, 0.25)
    save_sfx("grumble", growl, 0.6)
    poof = bandpass(noise(0.35), 500, 6000) * env(int(0.35 * SR), 0.002, 0.18)
    sparkle = mix(*[delay(bell(f, 0.3, 0.6) * 0.4, 0.04 * k) for k, f in enumerate([1568, 2093, 2637])])
    save_sfx("poof", mix(poof, sparkle), 0.7)
    save_sfx("zap-critter", mix(sweep(1500, 300, 0.12, "square", 0.5) * env(int(0.12 * SR), 0.001, 0.08) * 0.5, crackle * 0.5), 0.6)
    save_sfx("startle", sweep(700, 1400, 0.1, "tri", 0.4) * env(int(0.1 * SR), 0.002, 0.07), 0.45)

    # You.
    bonk = mix(sweep(500, 160, 0.18, "tri", 0.5) * env(int(0.18 * SR), 0.001, 0.12), lowpass(noise(0.06), 1200) * env(int(0.06 * SR), 0.001, 0.03))
    save_sfx("hurt", bonk, 0.7)
    save_sfx("heart", mix(bell(1047, 0.35, 0.8), delay(bell(1319, 0.4, 0.8), 0.07)), 0.5)
    wah = mix(*[delay(sweep(f, f * 0.94, 0.32, "tri") * env(int(0.32 * SR), 0.01, 0.2), 0.3 * k) for k, f in enumerate([523, 494, 466, 392])])
    save_sfx("knocked-out", lowpass(wah, 3000), 0.6)
    save_sfx("friend-joined", mix(bell(523, 0.4, 1), delay(bell(784, 0.5, 1), 0.1)), 0.5)


# ---------- vehicles ----------

def loop_crossfade(x, seconds=0.25):
    """Make a clip loop smoothly by blending its end into its start."""
    n = int(seconds * SR)
    head, tail = x[:n].copy(), x[-n:]
    ramp = np.linspace(0, 1, n)
    out = x[:-n].copy()
    out[:n] = head * ramp + tail * (1 - ramp)
    return out

def make_vehicles():
    # Rover engine: a chuggy little motor. Whole cycles over 1 s, so it loops cleanly.
    t = t_of(1.0)
    chug = 0.5 + 0.5 * np.sin(2 * np.pi * 12 * t)
    motor = (sweep(55, 55, 1.0, "saw") * 0.6 + np.sin(2 * np.pi * 110 * t) * 0.3 + np.sin(2 * np.pi * 165 * t) * 0.15) * (0.6 + 0.4 * chug)
    motor = lowpass(motor, 700)
    wavfile.write(os.path.join(OUT, "rover-engine.wav"), SR, (normalize(loop_crossfade(motor, 0.05), 0.6) * 32767).astype(np.int16))

    # Starship engine: a deep hum with rushing air.
    t = t_of(2.0)
    hum = np.sin(2 * np.pi * 80 * t) * 0.5 + np.sin(2 * np.pi * 120 * t) * 0.25 + np.sin(2 * np.pi * 240 * t) * 0.08
    air = bandpass(noise(2.0), 300, 2400) * 0.45
    engine = loop_crossfade(hum + air, 0.3)
    wavfile.write(os.path.join(OUT, "ship-engine.wav"), SR, (normalize(engine, 0.6) * 32767).astype(np.int16))

    # A friendly two-tone horn: honk-honk!
    def honk(seconds):
        n = int(seconds * SR)
        tone = sweep(415, 415, seconds, "square") + sweep(523, 523, seconds, "square") * 0.8
        return lowpass(tone, 1800) * env(n, 0.01, 0.05, hold=seconds - 0.08)
    save_sfx("horn", mix(honk(0.16), delay(honk(0.22), 0.22)), 0.7)

    hop_in = sweep(300, 700, 0.18, "tri", 0.6) * env(int(0.18 * SR), 0.003, 0.1)
    clunk = lowpass(noise(0.08), 900) * env(int(0.08 * SR), 0.001, 0.04)
    save_sfx("vehicle-in", mix(hop_in * 0.6, delay(clunk, 0.15)), 0.6)
    hop_out = sweep(650, 280, 0.18, "tri", 0.6) * env(int(0.18 * SR), 0.003, 0.1)
    save_sfx("vehicle-out", mix(clunk, delay(hop_out * 0.6, 0.05)), 0.6)
    bump = mix(lowpass(noise(0.15), 500) * env(int(0.15 * SR), 0.001, 0.08), sweep(120, 50, 0.15) * env(int(0.15 * SR), 0.001, 0.1))
    save_sfx("bump", bump, 0.7)

    # Laser bolt: a quick bright "pew".
    pew = sweep(2200, 520, 0.14, "square", 0.45) * env(int(0.14 * SR), 0.001, 0.09)
    save_sfx("bolt", mix(lowpass(pew, 5000) * 0.7, sweep(4400, 1000, 0.14) * env(int(0.14 * SR), 0.001, 0.06) * 0.3), 0.55)
    # Block explosion: a punchy boom with crackle and a little rumble tail.
    n = 0.55
    boom = lowpass(noise(n), 900, 3) * env(int(n * SR), 0.002, 0.35)
    thud = sweep(110, 38, n, "sine", 0.4) * env(int(n * SR), 0.002, 0.3)
    crackle = bandpass(noise(0.25), 1500, 7000) * env(int(0.25 * SR), 0.001, 0.12)
    save_sfx("explode", mix(boom * 1.2, thud * 1.1, crackle * 0.5), 0.85)

    # Hyperspace: a rising charge, a bright zap, then a long rushing whoosh that fades.
    n = 3.2
    charge = sweep(180, 1400, 0.7, "saw", 1.8) * np.linspace(0.1, 1, int(0.7 * SR))
    zap = mix(sweep(2600, 300, 0.4, "square", 0.4) * env(int(0.4 * SR), 0.001, 0.3), bell(1568, 0.8, 2) * 0.5)
    rush = bandpass(noise(n), 250, 4000) * np.sin(np.linspace(0, np.pi, int(n * SR))) ** 1.5
    hum = sweep(55, 70, n, "saw") * np.sin(np.linspace(0, np.pi, int(n * SR))) ** 2
    save_sfx("hyperspace", mix(lowpass(charge, 3000) * 0.5, delay(zap, 0.65), delay(rush * 0.9, 0.5), delay(lowpass(hum, 400) * 0.6, 0.5)), 0.85)

    # Atmosphere entry: a roaring, crackling rumble.
    n = 1.9
    roar = lowpass(noise(n), 700, 3) * (0.7 + 0.3 * np.sin(2 * np.pi * 6 * t_of(n)))
    crack = bandpass(noise(n), 2000, 8000) * (rng.random(int(n * SR)) > 0.9985).astype(float) * 6
    save_sfx("entry", mix(roar * 1.3, lowpass(crack, 9000) * 0.5) * env(int(n * SR), 0.15, 0.5, hold=1.1), 0.85)

    # Backpack and machines.
    save_sfx("pickup", mix(sweep(900, 1500, 0.07, "sine", 0.5) * env(int(0.07 * SR), 0.002, 0.04), delay(bell(1800, 0.15, 0.4) * 0.4, 0.03)), 0.45)
    save_sfx("craft", mix(*[delay(bell(f, 0.35, 1.0), 0.07 * k) for k, f in enumerate([523, 659, 784, 1047])], lowpass(noise(0.08), 2000) * env(int(0.08 * SR), 0.001, 0.04) * 0.5), 0.6)
    save_sfx("boing", sweep(180, 720, 0.45, "sine", 0.5) * (1 + 0.35 * np.sin(2 * np.pi * 22 * t_of(0.45))) * env(int(0.45 * SR), 0.004, 0.3), 0.6)
    save_sfx("zoom", mix(bandpass(noise(0.5), 600, 5000) * np.sin(np.linspace(0, np.pi, int(0.5 * SR))) ** 2, sweep(400, 1600, 0.5, "saw", 0.7) * env(int(0.5 * SR), 0.02, 0.3) * 0.25), 0.6)
    save_sfx("teleport", mix(sweep(300, 2400, 0.35, "sine", 1.5) * env(int(0.35 * SR), 0.01, 0.2), delay(mix(*[delay(bell(f, 0.3, 1.5) * 0.4, 0.04 * k) for k, f in enumerate([1568, 2093, 2637, 3136])]), 0.2)), 0.6)


# ---------- music ----------

NOTE = {n: i for i, n in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])}

def hz(note):
    """'A4' -> 440."""
    name, octave = note[:-1], int(note[-1])
    return 440.0 * 2 ** ((NOTE[name] - 9 + 12 * (octave - 4)) / 12)

def pad_voice(freq, seconds, warm=1600):
    """A soft detuned pad note with slow attack and release."""
    t = t_of(seconds)
    x = sum(np.sin(2 * np.pi * freq * d * t + rng.uniform(0, 6)) for d in (0.997, 1.0, 1.004))
    x += 0.35 * sum(np.sin(2 * np.pi * 2 * freq * d * t) for d in (0.998, 1.003))
    x = lowpass(x, warm)
    n = len(t)
    e = np.minimum(1, np.minimum(np.arange(n) / (0.9 * SR), (n - np.arange(n)) / (1.2 * SR)))
    return x * np.clip(e, 0, 1)

def pluck(freq, seconds=1.2):
    t = t_of(seconds)
    x = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * freq * 2 * t) + 0.12 * np.sin(2 * np.pi * freq * 3 * t)
    return x * np.exp(-t * 3.5) * np.minimum(1, t / 0.004)

def add_wrapped(track, part, at):
    """Add part at a time, wrapping anything past the end to the start, so the loop is seamless."""
    start = int(at * SR) % len(track)
    n = len(part)
    first = min(n, len(track) - start)
    track[start:start + first] += part[:first]
    if n > first:
        rest = part[first:]
        while len(rest):
            m = min(len(rest), len(track))
            track[:m] += rest[:m]
            rest = rest[m:]

def stereo_reverb(mono):
    """A cheap, soft room: a few feedback delays, a little different left and right."""
    out = []
    for taps in ((0.031, 0.067, 0.113, 0.171), (0.037, 0.073, 0.127, 0.181)):
        wet = np.zeros_like(mono)
        for d in taps:
            k = int(d * SR)
            buf = np.zeros_like(mono)
            buf[k:] = mono[:-k]
            for _ in range(5):          # a few echoes of each tap, fading
                wet += buf * 0.22
                buf = np.roll(buf, k) * 0.55
        out.append(mono + lowpass(wet, 3500))
    return np.stack(out, axis=1)

def make_track(name, bpm, chords, bars_per_chord, scale, arp_pattern, bass=True, bells=0.0, warm=1600, arp_octave=0):
    beat = 60 / bpm
    bar = beat * 4
    total = bar * bars_per_chord * len(chords)
    track = np.zeros(int(total * SR))
    loop_rng = np.random.default_rng(abs(hash(name)) % 2 ** 32)

    for c, chord in enumerate(chords):
        start = c * bars_per_chord * bar
        length = bars_per_chord * bar
        for note in chord:
            add_wrapped(track, pad_voice(hz(note), length + 1.4, warm) * 0.08, start)
        if bass:
            root = hz(chord[0]) / 2
            for b in range(bars_per_chord):
                add_wrapped(track, pad_voice(root, bar * 0.95, 500) * 0.12, start + b * bar)
        # Gentle arpeggio over the chord.
        steps = int(length / (beat / 2))
        tones = [hz(n) * 2 ** arp_octave for n in chord] + [hz(chord[0]) * 2 ** (arp_octave + 1)]
        for s in range(steps):
            idx = arp_pattern[s % len(arp_pattern)]
            if idx is None:
                continue
            f = tones[idx % len(tones)]
            add_wrapped(track, pluck(f) * 0.07 * loop_rng.uniform(0.7, 1.0), start + s * beat / 2)
        # Twinkles from the scale now and then.
        for s in range(int(length / beat)):
            if loop_rng.random() < bells:
                f = hz(scale[loop_rng.integers(len(scale))]) * 2
                add_wrapped(track, bell(f, 1.6, 0.8) * 0.05, start + s * beat + loop_rng.uniform(0, beat / 2))

    stereo = stereo_reverb(track)
    # The reverb tail at the end belongs at the start too.
    stereo = normalize(stereo, 0.7)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        wavfile.write(wav, SR, (stereo * 32767).astype(np.int16))
        out = os.path.join(OUT, name + ".m4a")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "aac", "-b:a", "128k", out], check=True)
    print(f"  {name}: {total:.0f} s loop")

def make_music():
    # Title: hopeful and wide.
    make_track("music-title", 72,
               [["C3", "G3", "E4"], ["A2", "E3", "C4"], ["F2", "C3", "A3"], ["G2", "D3", "B3"]], 4,
               ["C4", "D4", "E4", "G4", "A4"], [0, 1, 2, 3, 2, 1, None, 2], bells=0.25)
    # Wolfie World: bright, bouncy, major pentatonic.
    make_track("music-wolfie-world", 84,
               [["D3", "A3", "F#4"], ["B2", "F#3", "D4"], ["G2", "D3", "B3"], ["A2", "E3", "C#4"]], 4,
               ["D4", "E4", "F#4", "A4", "B4"], [0, 2, 1, 3, 2, None, 1, 2], bells=0.2)
    # Pup Moon: slow and dreamy, Lydian.
    make_track("music-pup-moon", 60,
               [["F2", "C3", "A3", "E4"], ["G2", "D3", "B3", "F#4"], ["F2", "C3", "A3", "E4"], ["E2", "B2", "G3", "D4"]], 4,
               ["F4", "G4", "A4", "B4", "C5", "E5"], [0, None, 2, None, 3, None, 1, None], bells=0.35, warm=1100, arp_octave=1)
    # Glimmer: sparkly and a little mysterious, Dorian.
    make_track("music-glimmer", 92,
               [["E3", "B3", "G4"], ["D3", "A3", "F#4"], ["C3", "G3", "E4"], ["D3", "A3", "F#4"]], 4,
               ["E4", "F#4", "G4", "A4", "B4", "C#5"], [0, 1, 2, 3, 2, 3, 1, 2], bells=0.4, warm=2200, arp_octave=1)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_effects()
    make_vehicles()
    print("Effects done.")
    make_music()
    print(f"Wrote everything to {OUT}")
