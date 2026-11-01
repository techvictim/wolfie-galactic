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


# ---------- weapons ----------

def boom(seconds, low=900, thud_from=110, thud_to=36, crackle=0.5, tail=0.35):
    """An explosion: a noise blast, a falling thud, crackle on top and a rumbling tail."""
    n = int(seconds * SR)
    blast = lowpass(noise(seconds), low, 3) * env(n, 0.002, tail * seconds * 2)
    thud = sweep(thud_from, thud_to, seconds, "sine", 0.4) * env(n, 0.002, seconds * 0.6)
    crack = bandpass(noise(min(seconds, 0.4)), 1500, 7000) * env(int(min(seconds, 0.4) * SR), 0.001, 0.12)
    return mix(blast * 1.2, thud * 1.1, crack * crackle)

def gunshot(seconds, body=1200, snap=0.6, thump=120):
    n = int(seconds * SR)
    crack = bandpass(noise(seconds), 800, 6000) * env(n, 0.0005, seconds * 0.4)
    low = lowpass(noise(seconds), body) * env(n, 0.001, seconds * 0.6)
    punch = sweep(thump, thump * 0.4, seconds, "sine", 0.4) * env(n, 0.001, seconds * 0.5)
    return mix(crack * snap, low, punch * 0.8)

def make_weapons():
    # Hand tools.
    save_sfx("hammer", mix(lowpass(noise(0.18), 1400) * env(int(0.18 * SR), 0.001, 0.07), sweep(180, 70, 0.18) * env(int(0.18 * SR), 0.001, 0.12)), 0.8)
    save_sfx("sledge", mix(lowpass(noise(0.32), 900) * env(int(0.32 * SR), 0.001, 0.14), sweep(120, 40, 0.32) * env(int(0.32 * SR), 0.001, 0.22), bell(220, 0.4, 3) * 0.15), 0.85)
    t = t_of(1.0)
    roar = bandpass(noise(1.0), 250, 3500) * (0.8 + 0.2 * np.sin(2 * np.pi * 9 * t)) + lowpass(noise(1.0), 300) * 0.6
    wavfile.write(os.path.join(OUT, "flame-loop.wav"), SR, (normalize(loop_crossfade(roar, 0.15), 0.55) * 32767).astype(np.int16))

    # Guns.
    save_sfx("gun-mini", gunshot(0.07, 1600, 0.7, 160), 0.6)
    save_sfx("gun-heavy", gunshot(0.16, 900, 0.7, 90), 0.75)
    sniper = mix(gunshot(0.25, 1400, 1.0, 110), delay(lowpass(noise(0.9), 700) * env(int(0.9 * SR), 0.05, 0.6) * 0.35, 0.12))
    save_sfx("gun-sniper", sniper, 0.85)
    save_sfx("gun-rifle", mix(gunshot(0.22, 1200, 0.9, 100), delay(lowpass(noise(0.5), 600) * env(int(0.5 * SR), 0.03, 0.3) * 0.25, 0.1)), 0.8)
    pump = mix(delay(bandpass(noise(0.05), 1500, 5000) * env(int(0.05 * SR), 0.001, 0.02), 0.32), delay(bandpass(noise(0.06), 1000, 4000) * env(int(0.06 * SR), 0.001, 0.03), 0.42))
    save_sfx("shotgun", mix(gunshot(0.3, 800, 0.8, 80), pump * 0.4), 0.85)

    # Launchers and throwing.
    save_sfx("cannon", mix(boom(0.6, 500, 90, 30, 0.2, 0.25), lowpass(noise(0.08), 3000) * env(int(0.08 * SR), 0.001, 0.03)), 0.85)
    whoosh = bandpass(noise(0.7), 600, 6000) * np.sin(np.linspace(0, np.pi, int(0.7 * SR))) ** 0.6 * np.linspace(1, 0.3, int(0.7 * SR))
    save_sfx("rocket", mix(lowpass(noise(0.12), 1500) * env(int(0.12 * SR), 0.001, 0.05), whoosh * 0.9, sweep(300, 900, 0.7, "saw", 0.6) * env(int(0.7 * SR), 0.01, 0.4) * 0.12), 0.75)
    save_sfx("throw", bandpass(noise(0.25), 400, 3000) * np.sin(np.linspace(0, np.pi, int(0.25 * SR))) ** 2, 0.5)
    save_sfx("gl", mix(sweep(260, 120, 0.12) * env(int(0.12 * SR), 0.001, 0.08), lowpass(noise(0.1), 1200) * env(int(0.1 * SR), 0.001, 0.05)), 0.7)
    save_sfx("mortar", mix(sweep(150, 60, 0.3) * env(int(0.3 * SR), 0.001, 0.2), lowpass(noise(0.25), 900) * env(int(0.25 * SR), 0.001, 0.12), delay(bandpass(noise(0.4), 800, 4000) * env(int(0.4 * SR), 0.05, 0.3) * 0.3, 0.1)), 0.8)
    save_sfx("bounce", mix(bell(1900, 0.12, 1.5) * 0.6, bandpass(noise(0.03), 2000, 6000) * env(int(0.03 * SR), 0.0005, 0.015)), 0.4)
    save_sfx("stick", mix(lowpass(noise(0.08), 700) * env(int(0.08 * SR), 0.001, 0.04), sweep(400, 200, 0.08, "tri") * env(int(0.08 * SR), 0.001, 0.05)), 0.55)
    save_sfx("beep", sweep(1760, 1760, 0.07, "square") * env(int(0.07 * SR), 0.002, 0.03), 0.3)

    # Booms, from a pop to the nuke.
    save_sfx("boom-big", boom(1.1, 700, 90, 28, 0.45, 0.4), 0.9)
    huge = mix(boom(2.0, 500, 70, 22, 0.35, 0.45), delay(lowpass(noise(1.6), 250, 3) * env(int(1.6 * SR), 0.1, 1.0) * 0.8, 0.2))
    save_sfx("boom-huge", huge, 0.92)
    n = 6.0
    nuke = mix(boom(1.4, 400, 60, 20, 0.3, 0.5),
               delay(lowpass(noise(n), 160, 3) * env(int(n * SR), 0.3, 3.5) * 1.4, 0.3),
               delay(lowpass(noise(3.0), 600) * env(int(3.0 * SR), 0.6, 1.8) * 0.5, 1.0))
    save_sfx("nuke", nuke, 0.95)
    # A falling bomb: an air-rush shriek that drops in pitch, not a pure tone.
    n = 1.6
    shriek = bandpass(noise(n), 1200, 2600) * 0.6 + sweep(1500, 700, n, "sine", 1.2) * 0.25
    save_sfx("whistle", lowpass(shriek, 4000) * np.linspace(0.2, 1, int(n * SR)) * env(int(n * SR), 0.2, 0.1, hold=1.2), 0.5)

    # Air strikes.
    n = 3.0
    jet = bandpass(noise(n), 300, 5000) * np.sin(np.linspace(0, np.pi, int(n * SR))) ** 2
    jet_tone = sweep(900, 500, n, "saw", 1) * np.sin(np.linspace(0, np.pi, int(n * SR))) ** 3 * 0.12
    save_sfx("jet", mix(jet, lowpass(jet_tone, 2500)), 0.75)
    n = 4.5
    drone_hum = (sweep(70, 62, n, "saw") * 0.5 + sweep(105, 93, n, "saw") * 0.3) * np.sin(np.linspace(0, np.pi, int(n * SR))) ** 1.5
    save_sfx("bomber", mix(lowpass(drone_hum, 600), bandpass(noise(n), 200, 1500) * np.sin(np.linspace(0, np.pi, int(n * SR))) ** 2 * 0.4), 0.75)
    save_sfx("gunship", mix(lowpass(sweep(85, 85, 2.5, "saw"), 500) * env(int(2.5 * SR), 0.4, 0.8, hold=1.2), bandpass(noise(2.5), 300, 2000) * env(int(2.5 * SR), 0.4, 0.8, hold=1.2) * 0.4), 0.6)
    t = t_of(0.8)
    save_sfx("drone", lowpass(sweep(220, 260, 0.8, "saw") * (1 + 0.3 * np.sin(2 * np.pi * 30 * t)), 2500) * env(int(0.8 * SR), 0.05, 0.3), 0.4)
    radio = mix(bandpass(noise(0.12), 1000, 4000) * env(int(0.12 * SR), 0.001, 0.05) * 0.4,
                delay(sweep(1200, 1200, 0.08, "square") * env(int(0.08 * SR), 0.002, 0.03), 0.12),
                delay(sweep(1600, 1600, 0.1, "square") * env(int(0.1 * SR), 0.002, 0.04), 0.24))
    save_sfx("radio", lowpass(radio, 3500), 0.45)

    # Black hole: a sparkle that opens it, a deep wobbling hum with rushing wind, then a falling
    # "vwoomp" and a bright echoing chime when it snaps shut.
    save_sfx("blackhole-open", mix(sweep(200, 1800, 0.5, "sine", 1.5) * env(int(0.5 * SR), 0.01, 0.3),
                                   delay(mix(*[delay(bell(f, 0.4, 2) * 0.3, 0.05 * k) for k, f in enumerate([1319, 1760, 2349])]), 0.2)), 0.6)
    t = t_of(2.0)
    hum = (np.sin(2 * np.pi * 45 * t) * 0.6 + np.sin(2 * np.pi * 67.5 * t) * 0.3) * (1 + 0.4 * np.sin(2 * np.pi * 3 * t))
    wind = bandpass(noise(2.0), 300, 2500) * (0.7 + 0.3 * np.sin(2 * np.pi * 1.5 * t))
    wavfile.write(os.path.join(OUT, "blackhole-loop.wav"), SR, (normalize(loop_crossfade(hum + wind * 0.5, 0.3), 0.6) * 32767).astype(np.int16))
    vwoomp = sweep(900, 50, 0.6, "sine", 0.5) * env(int(0.6 * SR), 0.005, 0.4)
    chime = mix(*[delay(bell(f, 1.2, 2) * (0.5 ** k), 0.18 * k) for k, f in enumerate([2093, 2093, 2093, 2093])])
    save_sfx("blackhole-close", mix(lowpass(vwoomp, 2000), delay(chime * 0.7, 0.4)), 0.8)


# ---------- the Red Glitch ----------

def robo_meow(seconds, f_start, f_peak, f_end, vowel_from=2600, vowel_to=900, crush=10):
    """A cat's "mee-ow" sung by a little robot: a buzzy tone sliding up then down, through a
    filter that sweeps from "ee" to "ow", then stepped and bit-crushed so it sounds electronic."""
    n = int(seconds * SR)
    t = np.linspace(0, 1, n)
    rise = 0.35
    f = np.where(t < rise, f_start + (f_peak - f_start) * (t / rise),
                 f_peak + (f_end - f_peak) * np.clip((t - rise) / (1 - rise), 0, 1) ** 0.8)
    # Robots step their pitch.
    f = np.round(f / 25) * 25
    phase = np.cumsum(2 * np.pi * f / SR)
    tone = signal.sawtooth(phase) * 0.6 + np.sign(np.sin(phase * 2)) * 0.25
    # Formant: "ee" (bright) to "ow" (dark), done as a moving band.
    out = np.zeros(n)
    chunk = 512
    for i in range(0, n, chunk):
        k = i / n
        centre = vowel_from + (vowel_to - vowel_from) * k
        piece = tone[max(0, i - 256):i + chunk]
        filtered = bandpass(piece, max(200, centre * 0.45), min(9000, centre * 1.6))
        out[i:i + chunk] = filtered[-len(out[i:i + chunk]):]
    out = mix(out, tone * 0.15)
    # A little bit-crush and a ring-mod buzz.
    out = np.round(out * crush) / crush
    out *= 1 + 0.35 * np.sin(2 * np.pi * 62 * t * seconds)
    return lowpass(out, 7000) * env(n, 0.01, seconds * 0.35)

def make_glitch():
    # When a robo-cat fires: a quick, cross "mrow!".
    save_sfx("robocat-meow", robo_meow(0.32, 520, 900, 420), 0.55)
    # When one gets hit: higher, startled "mip!".
    save_sfx("robocat-hurt", robo_meow(0.18, 900, 1500, 1100, 3200, 1800), 0.55)
    # Knocked out: a long, sad "mee-ooow" that winds down, a power-down whine and a soft clank.
    down = mix(robo_meow(0.7, 700, 1000, 260, 2600, 700),
               delay(sweep(1400, 90, 0.8, "sine", 0.6) * env(int(0.8 * SR), 0.01, 0.5) * 0.35, 0.35),
               delay(mix(bell(320, 0.3, 4) * 0.3, lowpass(noise(0.08), 1500) * env(int(0.08 * SR), 0.001, 0.04) * 0.5), 1.0))
    save_sfx("robocat-down", down, 0.6)
    # Charging the head laser: a rising whine, so there's time to dodge.
    save_sfx("robocat-charge", sweep(500, 2200, 0.9, "sine", 1.4) * np.linspace(0.2, 1, int(0.9 * SR)) * env(int(0.9 * SR), 0.05, 0.05, hold=0.8), 0.3)
    pew = sweep(1600, 300, 0.2, "square", 0.5) * env(int(0.2 * SR), 0.001, 0.12)
    save_sfx("robocat-laser", lowpass(pew, 4500), 0.5)
    # Near a Glitch Nest: a low electric hum with a slow pulse and the odd crackle.
    t = t_of(2.0)
    hum = (np.sin(2 * np.pi * 60 * t) * 0.5 + np.sin(2 * np.pi * 120 * t) * 0.25 + np.sign(np.sin(2 * np.pi * 30 * t)) * 0.08)
    hum *= 0.7 + 0.3 * np.sin(2 * np.pi * 1 * t)
    crackle = bandpass(noise(2.0), 2000, 8000) * (rng.random(int(2.0 * SR)) > 0.9993).astype(float) * 4
    wavfile.write(os.path.join(OUT, "glitch-hum.wav"), SR, (normalize(loop_crossfade(lowpass(hum, 900) + lowpass(crackle, 9000) * 0.3, 0.25), 0.5) * 32767).astype(np.int16))
    # A nest cured: a whoosh of good energy and a bright rising sparkle.
    sparkle = mix(*[delay(bell(f, 0.6, 1.4) * 0.5, 0.07 * k) for k, f in enumerate([784, 988, 1175, 1568, 1976, 2349])])
    save_sfx("cure", mix(bandpass(noise(0.6), 800, 7000) * np.sin(np.linspace(0, np.pi, int(0.6 * SR))) ** 2 * 0.5, sparkle), 0.7)
    # Builder bots putting a block back.
    save_sfx("build-tick", mix(bell(1320, 0.12, 1) * 0.6, bandpass(noise(0.03), 1500, 5000) * env(int(0.03 * SR), 0.001, 0.015) * 0.5), 0.3)
    # The Glitch spreads: a worried two-note alarm.
    save_sfx("glitch-alarm", lowpass(mix(sweep(660, 660, 0.25, "square") * env(int(0.25 * SR), 0.01, 0.05, hold=0.18),
                                         delay(sweep(520, 520, 0.35, "square") * env(int(0.35 * SR), 0.01, 0.1, hold=0.2), 0.3)), 2500), 0.45)


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

# ---------- lo-fi 8-bit music ----------
# Chill lo-fi beats played on chiptune sounds: boom-bap drums with a lazy swing, soft pulse-wave
# jazz chords, a triangle-wave bass like an old console, a sparse little melody, then tape wobble,
# vinyl crackle and a gentle bit-crush. Every part wraps around, so each track loops seamlessly.

def chip_wave(freq, seconds, kind="pulse", duty=0.5, wobble=0.0035, vibrato=0.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f = freq * (1 + wobble * np.sin(2 * np.pi * 0.55 * t) + vibrato * np.sin(2 * np.pi * 5.5 * t) * np.clip(t / 0.25, 0, 1))
    phase = np.cumsum(f / SR) % 1.0
    if kind == "tri":
        wave = 4 * np.abs(phase - 0.5) - 1
        return np.round(wave * 7.5) / 7.5          # 16 steps, like the NES triangle
    return np.where(phase < duty, 1.0, -1.0)

def chip_noise(seconds, periodic=False, seed=0):
    """The NES noise channel: random levels held for a few samples (or a short repeating pattern)."""
    n = int(seconds * SR)
    r = np.random.default_rng(seed)
    hold = 3 if not periodic else 23
    vals = r.choice([-1.0, 1.0], size=n // hold + 2)
    if periodic:
        vals = np.tile(vals[:31], n // (31 * hold) + 2)
    return np.repeat(vals, hold)[:n]

def note_env(n, attack, decay, sustain=0.0):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(attack, 1e-4)) * (sustain + (1 - sustain) * np.exp(-t / max(decay, 1e-4)))
    tail = min(n, int(0.02 * SR))
    e[-tail:] *= np.linspace(1, 0, tail)
    return e

def lofi_kick():
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = 48 + 90 * np.exp(-t * 28)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    click = chip_noise(0.01, seed=3)[: int(0.01 * SR)] * 0.25
    body[: len(click)] += click
    return body

def lofi_snare():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    tone = chip_wave(190, 0.25, "tri") * np.exp(-t * 22) * 0.5
    noise = lowpass(chip_noise(0.25, seed=9), 5200) * np.exp(-t * 14)
    return tone + noise * 0.8

def lofi_hat(open_hat=False):
    d = 0.18 if open_hat else 0.05
    n = int(d * SR)
    t = np.arange(n) / SR
    return highpass(chip_noise(d, periodic=True, seed=4), 6000) * np.exp(-t * (14 if open_hat else 70))

def make_lofi(name, bpm, chords, seed, scale, bass_walk=True, lead=0.45, swing=0.6, bright=2600):
    rng = np.random.default_rng(seed)
    beat = 60 / bpm
    bar = beat * 4
    bars_per_chord = 2
    total = bar * bars_per_chord * len(chords) * 2      # the progression twice, the second time with a tune
    n = int(total * SR)
    drums = np.zeros(n)
    keys = np.zeros(n)
    bass = np.zeros(n)
    tune = np.zeros(n)
    kick_times = []

    def swung(step):
        """Eighth-note steps, with the off-beats pushed late."""
        return (step // 2) * beat + (step % 2) * beat * swing

    kick, snare = lofi_kick(), lofi_snare()
    hat, open_hat = lofi_hat(), lofi_hat(True)
    bars = int(round(total / bar))
    for b in range(bars):
        t0 = b * bar
        # Boom-bap: kick on 1 and the "and" of 2 (sometimes 3), snare on 2 and 4.
        for step in ([0, 3] if b % 2 == 0 else [0, 3, 5]):
            add_wrapped(drums, kick * 0.95, t0 + swung(step))
            kick_times.append(t0 + swung(step))
        for step in (2, 6):
            add_wrapped(drums, snare * 0.55, t0 + swung(step) + 0.012)
        for step in range(8):
            if rng.random() < 0.9:
                h = open_hat if (step == 7 and b % 4 == 3) else hat
                add_wrapped(drums, h * (0.15 if step % 2 == 0 else 0.1) * rng.uniform(0.8, 1.1), t0 + swung(step))

    for c in range(len(chords) * 2):
        chord = chords[c % len(chords)]
        start = c * bars_per_chord * bar
        # Soft chords: a hit on 1, another on the "and" of 2, like a lazy keys player.
        for hit, length in ((0, beat * 1.6), (3, beat * 2.4), (8, beat * 1.6), (11, beat * 2.2)):
            when = start + swung(hit) + rng.uniform(0, 0.02)
            for k, note in enumerate(chord):
                f = hz(note)
                wave = chip_wave(f, length, "pulse", duty=0.5 if k % 2 == 0 else 0.25)
                tone = lowpass(wave, bright) * note_env(len(wave), 0.02, length * 0.7, 0.35)
                add_wrapped(keys, tone * 0.06, when + k * 0.012)
        # Triangle bass: the root, then a step toward the next chord.
        root = hz(chord[0]) / 2
        nxt = hz(chords[(c + 1) % len(chords)][0]) / 2
        line = [(0, root, beat * 1.4), (3, root, beat * 0.9), (8, root * 1.5, beat * 1.2)]
        if bass_walk:
            line.append((11, (root + nxt) / 2 if abs(nxt - root) > 1 else root * 2 ** (2 / 12), beat * 1.0))
        for step, f, length in line:
            wave = chip_wave(f, length, "tri", wobble=0.001)
            add_wrapped(bass, wave * note_env(len(wave), 0.005, length * 0.8, 0.5) * 0.32, start + swung(step))
        # A little tune the second time round.
        if c >= len(chords):
            step = 0
            while step < 16:
                if rng.random() < lead:
                    length_steps = int(rng.choice([1, 2, 3, 4]))
                    note = scale[int(rng.integers(len(scale)))]
                    f = hz(note) * 2
                    length = length_steps * beat / 2 * 0.95
                    wave = chip_wave(f, length, "pulse", duty=0.125, vibrato=0.006)
                    add_wrapped(tune, lowpass(wave, 3800) * note_env(len(wave), 0.01, length * 0.6, 0.4) * 0.07, start + swung(step))
                    step += length_steps
                else:
                    step += 1

    # Everything ducks a little under the kick, for that pumping lo-fi feel.
    duck = np.ones(n)
    for k in kick_times:
        i = int(k * SR) % n
        m = int(0.28 * SR)
        shape = 1 - 0.35 * np.exp(-np.arange(m) / (0.08 * SR))
        idx = (i + np.arange(m)) % n
        duck[idx] = np.minimum(duck[idx], shape)
    music = (keys + tune) * duck + bass * (0.6 + 0.4 * duck) + drums

    # Lo-fi: a gentle bit-crush and sample-rate drop, a dull top end, crackle and hiss.
    crushed = np.round(music * 48) / 48
    held = np.repeat(crushed[::2], 2)[:n]
    music = lowpass(0.5 * music + 0.5 * held, 4200)
    crackle = (np.random.default_rng(seed + 1).random(n) > 0.99965).astype(float) * np.random.default_rng(seed + 2).uniform(-1, 1, n)
    music = music + lowpass(crackle, 3000) * 0.18 + lowpass(highpass(noise(total), 1200), 5000)[:n] * 0.006

    stereo = stereo_reverb(music * 0.9)
    stereo = normalize(stereo, 0.7)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        wavfile.write(wav, SR, (stereo * 32767).astype(np.int16))
        out = os.path.join(OUT, name + ".m4a")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "aac", "-b:a", "128k", out], check=True)
    print(f"  {name}: {total:.0f} s loop")

def make_music():
    # Title and space: warm and floaty.
    make_lofi("music-title", 74, [["F3", "A3", "C4", "E4"], ["E3", "G3", "B3", "D4"], ["D3", "F3", "A3", "C4", "E4"], ["C3", "E3", "G3", "B3"]],
              seed=11, scale=["C4", "D4", "E4", "G4", "A4"], lead=0.4)
    # Wolfie World: sunny, a little bouncy.
    make_lofi("music-wolfie-world", 82, [["C3", "E3", "G3", "B3"], ["A2", "C3", "E3", "G3"], ["D3", "F3", "A3", "C4"], ["G2", "B2", "D3", "F3"]],
              seed=21, scale=["C4", "D4", "E4", "G4", "A4"], lead=0.5, bright=3000)
    # Pup Moon: slow and dreamy.
    make_lofi("music-pup-moon", 68, [["D#3", "G3", "A#3", "D4"], ["C3", "D#3", "G3", "A#3", "D4"], ["G#2", "C3", "D#3", "G3"], ["A#2", "D3", "F3", "G3"]],
              seed=31, scale=["D#4", "F4", "G4", "A#4", "C5"], lead=0.35, swing=0.64, bright=2000)
    # Glimmer: a bit mysterious, with a walking bass.
    make_lofi("music-glimmer", 86, [["D3", "F3", "A3", "C4", "E4"], ["G2", "B2", "D3", "F3"], ["E3", "G3", "B3", "D4"], ["A2", "C#3", "E3", "G3"]],
              seed=41, scale=["D4", "E4", "F4", "A4", "C5"], lead=0.45, bright=2800)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    make_effects()
    make_vehicles()
    make_weapons()
    make_glitch()
    print("Effects done.")
    make_music()
    print(f"Wrote everything to {OUT}")
