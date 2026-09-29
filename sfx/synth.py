#!/usr/bin/env python3
"""Synthesize the Mogwarts sound effects procedurally, without any API.

    pip install numpy scipy lameenc
    python3 sfx/synth.py                 # every sound that is still missing
    python3 sfx/synth.py fire heal       # only a category and/or a single sound
    python3 sfx/synth.py --force         # overwrite existing files

Every sound in prompts.json has a recipe below that builds it from noise,
oscillators, filters and a convolution reverb. Output goes to the same paths
as generate.py (assets/sfx/<category>/<id>.mp3), so `generate.py --force`
later replaces these with ElevenLabs versions. Rendering is seeded per sound,
so the same recipe always produces the same file.
"""

import argparse
import json
import sys
import zlib
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
MANIFEST = Path(__file__).resolve().parent / "prompts.json"
OUT_DIR = ROOT / "assets" / "sfx"

RECIPES = {}


def sfx(peak=-1.0, loop=None):
    """Register a recipe under its function name. `loop` is the loop length in seconds."""
    def register(fn):
        RECIPES[fn.__name__] = {"fn": fn, "peak": peak, "loop": loop}
        return fn
    return register


# --------------------------------------------------------------------------- basics

def n(d):
    return max(1, int(round(d * SR)))


def tt(d):
    return np.arange(n(d)) / SR


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def snap(f, length):
    """Round a frequency so it completes a whole number of cycles in `length` s (seamless loops)."""
    return max(1, round(f * length)) / length


def lin(d, *pts):
    """Piecewise-linear curve through (time, value) points."""
    xs, ys = zip(*pts)
    return np.interp(tt(d), xs, ys)


def expo(d, *pts):
    """Piecewise-exponential curve through (time, value) points, for frequencies."""
    xs, ys = zip(*pts)
    return np.exp(np.interp(tt(d), xs, np.log(ys)))


def const(d, value):
    return np.full(n(d), float(value))


def decay(d, tau, attack=0.0005):
    t = tt(d)
    env = np.exp(-t / tau)
    if attack:
        env *= np.minimum(1.0, t / attack)
    return env


def nrm(x):
    peak = np.max(np.abs(x))
    return x / peak if peak > 0 else x


def std1(x):
    s = np.std(x)
    return x / s if s > 0 else x


def fit(x, length):
    if len(x) >= length:
        return x[:length]
    return np.concatenate([x, np.zeros(length - len(x))])


def put(buf, x, at, gain=1.0):
    """Mix x into buf starting at time `at` (seconds)."""
    i = int(round(at * SR))
    if i < 0:
        x, i = x[-i:], 0
    if i < len(buf):
        j = min(len(buf), i + len(x))
        buf[i:j] += gain * x[: j - i]
    return buf


def events(r, d, rate):
    """Random event times for a (possibly time-varying) rate in events per second."""
    rate = np.broadcast_to(np.asarray(rate, float), (n(d),))
    return np.nonzero(r.random(n(d)) < rate / SR)[0] / SR


def loguniform(r, lo, hi):
    return float(np.exp(r.uniform(np.log(lo), np.log(hi))))


# --------------------------------------------------------------------------- sources

def noise(r, d, color=0.0):
    """Unit-variance noise; color 0 = white, 1 = pink, 2 = brown."""
    x = r.standard_normal(n(d))
    if color:
        spec = np.fft.rfft(x)
        f = np.maximum(np.fft.rfftfreq(len(x), 1 / SR), 20.0)
        spec *= f ** (-color / 2)
        x = np.fft.irfft(spec, len(x))
    return std1(x)


def osc(f, shape="sine"):
    """Oscillator following the per-sample frequency curve f (band-limited saw)."""
    f = np.asarray(f, float)
    dt = f / SR
    p = np.cumsum(dt) % 1.0
    if shape == "sine":
        return np.sin(2 * np.pi * p)
    if shape == "tri":
        return 2 * np.abs(2 * p - 1) - 1
    y = 2 * p - 1
    m = p < dt
    x = p[m] / dt[m]
    y[m] -= x + x - x * x - 1
    m = p > 1 - dt
    x = (p[m] - 1) / dt[m]
    y[m] -= x * x + x + x + 1
    return y


# (ratio, gain, decay factor) per partial
CHIME = ((1, 1, 1), (2.0, 0.3, 0.6), (3.0, 0.1, 0.4), (4.16, 0.06, 0.3))
GLOCK = ((1, 1, 1), (2.76, 0.35, 0.45), (5.40, 0.15, 0.3), (8.93, 0.06, 0.2))
GLASS = ((1, 1, 1), (2.32, 0.55, 0.7), (4.25, 0.35, 0.5), (6.63, 0.2, 0.35))
METAL = ((1, 1, 1), (2.41, 0.7, 0.8), (3.87, 0.5, 0.6), (5.93, 0.35, 0.5))
SPARK = ((1, 1, 1), (2.0, 0.25, 0.5))


def tone(f, d, tau, partials=((1, 1, 1),), attack=0.003, vibrato=0.0, vib_rate=5.0):
    """Struck/plucked tone: decaying partials (bells, chimes, glass, metal)."""
    t = tt(d)
    wob = 1 + vibrato * np.sin(2 * np.pi * vib_rate * t)
    out = np.zeros(n(d))
    for ratio, gain, factor in partials:
        if f * ratio < 18000:
            out += gain * osc(f * ratio * wob) * np.exp(-t / (tau * factor))
    return out * np.minimum(1.0, t / attack)


# --------------------------------------------------------------------------- filters & effects

def _clamp(f):
    return float(min(max(f, 15.0), SR * 0.45))


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, _clamp(f), "lowpass", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, _clamp(f), "highpass", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [_clamp(lo), _clamp(hi)], "bandpass", fs=SR, output="sos"), x)


def _rbj(kind, f, q):
    w = 2 * np.pi * _clamp(f) / SR
    cw, alpha = np.cos(w), np.sin(w) / (2 * q)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
    else:
        b = [alpha, 0.0, -alpha]
    a0 = 1 + alpha
    return np.array(b) / a0, np.array([1.0, -2 * cw / a0, (1 - alpha) / a0])


def shelf(x, kind, f, gain_db, slope=1.0):
    """RBJ shelving EQ: kind 'low' or 'high', boosting or cutting by gain_db beyond f."""
    amp = 10 ** (gain_db / 40)
    w = 2 * np.pi * _clamp(f) / SR
    cw = np.cos(w)
    alpha = np.sin(w) / 2 * np.sqrt((amp + 1 / amp) * (1 / slope - 1) + 2)
    k = 2 * np.sqrt(amp) * alpha
    sign = 1 if kind == "low" else -1
    b = [amp * ((amp + 1) - sign * (amp - 1) * cw + k),
         sign * 2 * amp * ((amp - 1) - sign * (amp + 1) * cw),
         amp * ((amp + 1) - sign * (amp - 1) * cw - k)]
    a = [(amp + 1) + sign * (amp - 1) * cw + k,
         -sign * 2 * ((amp - 1) + sign * (amp + 1) * cw),
         (amp + 1) + sign * (amp - 1) * cw - k]
    return signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], x)


def master(x):
    """Final tone shaping for every sound: fuller lows, softer highs."""
    x = shelf(x, "low", 140, 6.0)
    x = shelf(x, "high", 4500, -6.0)
    return lp(x, 11000)


def reson(x, f, q):
    b, a = _rbj("bp", f, q)
    return signal.lfilter(b, a, x)


def sweep(x, kind, fc, q=0.707, block=64):
    """Resonant filter ('lp', 'hp' or 'bp') whose cutoff follows the curve fc."""
    fc = np.broadcast_to(np.asarray(fc, float), x.shape)
    y = np.empty_like(x)
    zi = np.zeros(2)
    for i in range(0, len(x), block):
        b, a = _rbj(kind, fc[i], q)
        y[i:i + block], zi = signal.lfilter(b, a, x[i:i + block], zi=zi)
    return y


def formant(src, formants):
    return sum(g * reson(src, f, q) for f, q, g in formants)


def drive(x, amount):
    return np.tanh(amount * x) / np.tanh(amount)


def echo(x, delay, feedback, lpf=3000.0, taps=6):
    y = x.copy()
    tap = x
    step = n(delay)
    for k in range(1, taps + 1):
        tap = lp(tap, lpf) * feedback
        if step * k >= len(x):
            break
        y[step * k:] += tap[: len(x) - step * k]
    return y


def impulse(r, size, damp=5000.0, predelay=0.015):
    """Reverb impulse response: a noise tail whose highs die out faster than its lows. size = RT60 (s)."""
    t = tt(size * 1.2)
    low = lp(noise(r, size * 1.2), 1500) * np.exp(-6.9 * t / size)
    high = hp(lp(noise(r, size * 1.2), damp), 1500) * np.exp(-6.9 * t / (size * 0.45))
    ir = hp(low + 0.8 * high, 100)
    return np.concatenate([np.zeros(n(predelay)), ir / np.sqrt(np.sum(ir ** 2))])


def reverb(r, x, size, wet, damp=5000.0, predelay=0.015):
    return x + wet * signal.fftconvolve(x, impulse(r, size, damp, predelay))[: len(x)]


def creverb(r, x, size, wet, damp=5000.0):
    """Reverb for a loop cycle: the tail wraps around to the start."""
    ir = impulse(r, size, damp)
    folded = np.zeros(len(x))
    for i in range(0, len(ir), len(x)):
        seg = ir[i:i + len(x)]
        folded[: len(seg)] += seg
    return x + wet * np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(folded), len(x))


def circ_put(buf, x, at, gain=1.0):
    """Mix x into a loop cycle starting at `at`, wrapping around the end."""
    i = int(round(at * SR)) % len(buf)
    x = gain * x
    while len(x):
        j = min(len(buf) - i, len(x))
        buf[i:i + j] += x[:j]
        x, i = x[j:], 0
    return buf


ROOMS = {  # RT60, wet, damping
    "castle": (1.9, 0.45, 4500),
    "hall": (1.2, 0.35, 5000),
    "wood": (0.7, 0.25, 5000),
    "small": (0.4, 0.2, 6000),
    "outdoor": (0.25, 0.08, 7000),
}


def room(r, x, kind, wet=None):
    size, default_wet, damp = ROOMS[kind]
    return reverb(r, x, size, default_wet if wet is None else wet, damp)


# --------------------------------------------------------------------------- building blocks

def wobble(r, d, rate, depth):
    """Random amplitude modulation around 1 (flicker, gusts, fabric texture)."""
    m = std1(lp(r.standard_normal(n(d)), rate))
    return np.clip(1 + depth * m, 0.05, None)


def burst(r, d, tau, lo=None, hi=None, color=0.0):
    x = noise(r, d, color) * decay(d, tau)
    if lo and hi:
        return bp(x, lo, hi)
    if lo:
        return hp(x, lo)
    if hi:
        return lp(x, hi)
    return x


def boom(d, f0, f1, tau, amount=1.5):
    """Low sine thump that drops in pitch."""
    t1 = min(tau * 3, d * 0.9)
    return drive(osc(expo(d, (0, f0), (t1, f1), (d, f1))) * decay(d, tau, 0.002), amount)


def whoosh(r, d, fc, env, q=1.5, color=1.0):
    return std1(sweep(noise(r, d, color), "bp", fc, q)) * env


def crackle(r, d, rate, lo=1500, hi=9000, power=2.5):
    """Sparse random clicks: fire crackle, sizzle, gravel, ice."""
    imp = np.zeros(n(d))
    at = (events(r, d, rate) * SR).astype(int)
    imp[at] = r.random(len(at)) ** power * r.choice([-1.0, 1.0], len(at))
    unit = np.zeros(2048)
    unit[0] = 1.0
    return bp(imp, lo, hi) / np.max(np.abs(bp(unit, lo, hi)))


def sparkles(r, d, rate, lo=3000, hi=10000, tau=(0.03, 0.2), rise=0.0, partials=SPARK):
    """Random tiny bell pings; `rise` shifts them up by that many octaves over d."""
    x = np.zeros(n(d))
    for at in events(r, d, rate):
        k = r.uniform(*tau)
        f = loguniform(r, lo, hi) * 0.65 * 2 ** (rise * at / d)
        put(x, tone(f, k * 5, k, partials, attack=0.001), at, r.uniform(0.2, 1.0))
    return x


def bells(r, d, rate, notes, tau=(0.3, 0.8), partials=CHIME):
    """Random pitched bells picked from a list of MIDI notes."""
    x = np.zeros(n(d))
    for at in events(r, d, rate):
        k = r.uniform(*tau)
        put(x, tone(hz(r.choice(notes)), k * 4, k, partials, attack=0.004), at, r.uniform(0.3, 1.0))
    return x


def body(f, env, harm=0.4):
    """Warm low tone (fundamental plus octave) under a thin sound; f may be a curve."""
    f = np.broadcast_to(np.asarray(f, float), env.shape)
    return drive(osc(f) + harm * osc(f * 2), 1.3) * env


def bubble(f0, d, rise=0.6):
    """A single bubble: a sine that rises in pitch while it dies away."""
    t = tt(d)
    return osc(f0 * (1 + rise * t / d)) * np.exp(-t / (d / 3.5)) * np.minimum(1.0, t / 0.0015)


def bubbles(r, d, rate, lo, hi, dur=(0.03, 0.1), rise=(0.3, 1.0)):
    x = np.zeros(n(d))
    for at in events(r, d, rate):
        put(x, bubble(loguniform(r, lo, hi), r.uniform(*dur), r.uniform(*rise)), at, r.uniform(0.25, 1.0))
    return x


def creak(r, d, rate, modes, q=12.0, jitter=0.15):
    """Stick-slip friction: a pulse train at `rate` Hz ringing resonances (wood, doors, ice)."""
    rate = np.broadcast_to(np.asarray(rate, float), (n(d),))
    wob = np.clip(1 + jitter * std1(lp(r.standard_normal(n(d)), 30)), 0.3, None)
    phase = np.cumsum(rate * wob) / SR
    imp = np.diff(np.floor(phase), prepend=0.0) * r.uniform(0.6, 1.0, n(d))
    return nrm(sum(g * reson(imp, f, q) for f, g in modes))


def sparks(r, d, rate, lo=900, hi=12000):
    """Electric snaps: clusters of sharp clicks with a short fizz."""
    x = np.zeros(n(d))
    for at in events(r, d, rate):
        span = r.uniform(0.004, 0.03)
        cluster = np.zeros(n(span) + 1)
        k = int(r.integers(3, 14))
        cluster[r.integers(0, len(cluster), k)] = r.uniform(0.3, 1.0, k) * r.choice([-1.0, 1.0], k)
        cluster = fit(cluster, n(span + 0.02)) + noise(r, span + 0.02) * decay(span + 0.02, 0.006) * 0.08
        put(x, cluster, at, r.uniform(0.3, 1.0))
    return nrm(bp(x, lo, hi))


def buzz(r, d, f, lo=200, hi=4000):
    """Electric hum with a nervous flutter."""
    f = np.broadcast_to(np.asarray(f, float), (n(d),)) * (1 + 0.01 * std1(lp(r.standard_normal(n(d)), 20)))
    return std1(bp(drive(osc(f, "saw"), 3.0), lo, hi))


def roar(r, d, cutoff=900.0, rate=7.0, depth=0.45):
    """Flames: brown-noise body plus airy mid band, flickering."""
    body = std1(lp(noise(r, d, 2.0), cutoff))
    air = std1(bp(noise(r, d, 1.0), 300, 3000))
    return (body + 0.35 * air) * wobble(r, d, rate, depth)


def thunder(r, d, cutoff=220.0, tau=0.8):
    return std1(lp(noise(r, d, 2.0), cutoff)) * decay(d, tau, 0.02) * wobble(r, d, 3, 0.6)


def zap(r):
    d = 0.12
    return drive(osc(expo(d, (0, 5000), (d, 250))) * decay(d, 0.03, 0.0005) * 0.7
                 + nrm(burst(r, d, 0.006, lo=600)), 2.0)


def shatter(r, d, shards=40, lo=2000, hi=9000, spread=0.12, partials=GLASS, tau=(0.02, 0.12)):
    """Glass/ice breaking: a crack, many ringing shards and crunchy grains."""
    x = np.zeros(n(d))
    put(x, nrm(burst(r, 0.05, 0.004, lo=1500)), 0)
    times = np.concatenate([r.uniform(0, 0.02, 6), r.exponential(spread, shards)])
    for at in times[times < d]:
        k = r.uniform(*tau)
        put(x, tone(loguniform(r, lo, hi), k * 5, k, partials, attack=0.0005), at,
            r.uniform(0.2, 1.0) * np.exp(-at / (spread * 2)))
    return x + crackle(r, d, shards * 6 / spread * decay(d, spread, 0), 2500, 11000) * 0.6


def wood_body(r, w=1.0, d=0.35):
    """Knock on floorboards: an impulse ringing a few wooden modes."""
    hit = noise(r, d) * decay(d, 0.003)
    modes = [(95, 5, 1.0), (175, 7, 0.7), (320, 9, 0.45), (590, 10, 0.3), (1150, 8, 0.15)]
    return sum(g * nrm(reson(hit, f * r.uniform(0.95, 1.05), q)) for f, q, g in modes) * w


def crack(r, gain=1.0):
    d = 0.2
    x = nrm(burst(r, d, 0.006, lo=500)) + boom(d, 160, 90, 0.03) * 0.6
    return (x + std1(bp(noise(r, d), 1000, 6000)) * decay(d, 0.015) * 0.4) * gain


def brass(freqs, bright, detune=0.003, scoop=0.03):
    """Brass section: detuned saws that scoop up into pitch, through a lowpass following `bright` (Hz)."""
    t = np.arange(len(bright)) / SR
    bend = 1 - scoop * np.exp(-t / 0.06)
    src = sum(osc(const(len(bright) / SR, f * (1 + k * detune)) * bend, "saw") for f in freqs for k in (-1, 0, 1))
    return nrm(sweep(src, "lp", bright, 1.0))


def horn(midis, dur, release=0.3):
    """One brass chord or note with a bright attack and a little vibrato on long notes."""
    ln = dur + release
    t = tt(ln)
    bright = expo(ln, (0, 400), (0.04, 3200), (0.3, 1700), (ln, 1000))
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.2) / 0.3, 0, 1)
    src = sum(osc(hz(m) * (1 + k * 0.003) * vib * (1 - 0.02 * np.exp(-t / 0.05)), "saw")
              for m in midis for k in (-1, 0, 1))
    env = lin(ln, (0, 0), (0.02, 1), (0.08, 0.8), (dur, 0.75), (ln, 0))
    return drive(nrm(sweep(src, "lp", bright, 1.0)), 2.0) * env


def drum(r, f0=110, f1=55, tau=0.35, gain=1.0):
    """Big membrane drum (taiko/timpani): pitched thump, second mode, skin noise and beater."""
    d = tau * 5
    x = osc(expo(d, (0, f0), (0.04, f1 * 1.1), (d, f1))) * decay(d, tau, 0.001)
    x += 0.4 * osc(expo(d, (0, f0 * 1.6), (0.04, f1 * 1.76), (d, f1 * 1.59))) * decay(d, tau * 0.4, 0.001)
    x += std1(lp(noise(r, d), 900)) * decay(d, 0.04, 0.001) * 0.5
    x += std1(hp(noise(r, d), 2000)) * decay(d, 0.003) * 0.2
    return drive(x * gain, 1.5)


def choir(r, midis, d, vowel=((800, 6, 1.0), (1150, 8, 0.5), (2900, 12, 0.2))):
    """Synthetic choir 'aah': detuned saws with vibrato through vocal formants."""
    t = tt(d)
    src = np.zeros(n(d))
    for m in midis:
        for det in (-0.004, 0.0, 0.004):
            vib = 1 + 0.004 * np.sin(2 * np.pi * 5 * t + r.uniform(0, 2 * np.pi))
            src += osc(hz(m) * (1 + det) * vib, "saw")
    return nrm(formant(src, vowel) + 0.3 * lp(src, 1200) + 0.4 * lp(src, 350))


def voice(r, f, formants, breath=0.1, sub=0.0):
    """Creature voice: a glottal saw following the curve f, shaped by formants."""
    jitter = 1 + 0.01 * std1(lp(r.standard_normal(len(f)), 25))
    src = osc(f * jitter, "saw") + (sub * osc(f * 0.5 * jitter, "saw") if sub else 0)
    src = src + breath * std1(r.standard_normal(len(f)))
    return nrm(formant(src, formants))


def heartbeat(r, gain=1.0):
    """One 'lub-dub'."""
    d = 0.6
    x = np.zeros(n(d))
    for at, f, g in ((0.0, 55, 1.0), (0.28, 68, 0.7)):
        beat = body(expo(0.3, (0, f * 1.3), (0.05, f), (0.3, f * 0.9)), decay(0.3, 0.05, 0.008), 0.3)
        beat += std1(lp(noise(r, 0.3, 2.0), 150)) * decay(0.3, 0.04, 0.005) * 0.4
        put(x, beat, at, g)
    return x * gain


def big_hit(r, d=2.5):
    """Dry cinematic impact: sub boom, crack, blast and a metallic clang."""
    x = np.zeros(n(d))
    put(x, boom(d, 95, 28, 0.7, 2.5), 0)
    put(x, nrm(burst(r, 0.05, 0.008, lo=1200)), 0, 0.4)
    put(x, std1(lp(noise(r, 1.0, 2.0), 600)) * decay(1.0, 0.18, 0.002), 0, 0.8)
    clang = tone(155, d, 0.9, METAL) + 0.7 * tone(233, d, 0.7, METAL) + 0.4 * tone(412, d, 0.5, METAL)
    return put(x, drive(nrm(clang), 1.5), 0, 0.4)


def riser(r, d):
    """Tension riser: rising noise, a climbing string chord with faster and faster tremolo, and a sub."""
    k = lin(d, (0, 0), (d, 1))
    x = whoosh(r, d, expo(d, (0, 200), (d, 7000)), k ** 2, q=1.5) * 0.5
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * np.cumsum(4 + 16 * k ** 2) / SR)
    chord = sum(osc(f * 2 ** k, "saw") for f in (110, 164.8, 220))
    x += nrm(sweep(chord, "lp", 300 + 4700 * k ** 2, 1.2)) * k ** 1.5 * trem * 0.5
    x += std1(hp(noise(r, d), 5000)) * k ** 3 * 0.3
    x += body(55 * 2 ** k, k ** 2, 0.5) * 0.4
    return x


def reverse_crash(r, d):
    """A crash with its reverb, played backwards so it swells into a hard stop at d."""
    src = std1(hp(noise(r, 2.5), 3000)) * decay(2.5, 0.5, 0.001) * 0.6
    src += nrm(tone(420, 2.5, 0.8, METAL)) * 0.3 + boom(2.5, 80, 40, 0.5) * 0.6
    tail = reverb(r, src, 2.0, 0.6)[: n(d)][::-1]
    return tail * lin(d, (0, 0), (d, 1)) ** 1.5


def hoot(f, d):
    t = tt(d)
    fr = f * (1 + 0.04 * np.sin(np.pi * t / d))
    return (osc(fr) + 0.15 * osc(fr * 2)) * np.sin(np.pi * np.minimum(t / d, 1)) ** 0.7


def owl_call(r):
    x = np.zeros(n(1.6))
    for at, dur, f in ((0.05, 0.28, 380), (0.5, 0.16, 390), (0.7, 0.16, 390), (0.95, 0.55, 360)):
        put(x, hoot(f, dur), at)
        put(x, std1(lp(noise(r, dur), 1500)) * np.sin(np.pi * tt(dur) / dur), at, 0.04)
    return x


def chirp(f, pulses=3, rate=30.0):
    """Cricket chirp: a few quick pulses of a pure tone."""
    d = pulses / rate
    t = tt(d)
    return osc(const(d, f)) * np.sin(np.pi * ((t * rate) % 1.0)) ** 2


# --------------------------------------------------------------------------- footsteps

def step_stone(r, w=1.0):
    """Leather boot on stone: heel strike, sole roll, a little grit."""
    d = 0.3
    x = std1(bp(noise(r, d), 180, 5000)) * decay(d, 0.006 + 0.004 * w) * 0.5
    x += osc(expo(d, (0, 120), (0.06, 65), (d, 65))) * decay(d, 0.022 + 0.012 * w) * (0.7 + 0.4 * w)
    put(x, std1(bp(noise(r, 0.15), 350, 3500)) * decay(0.15, 0.012) * 0.28, r.uniform(0.055, 0.085))
    put(x, crackle(r, 0.15, 400 * decay(0.15, 0.03, 0), 2500, 9000) * 0.12, 0)
    put(x, std1(bp(noise(r, 0.12), 1200, 6000)) * lin(0.12, (0, 0), (0.03, 1), (0.12, 0)) * 0.06, 0.06)
    if r.random() < 0.35:  # leather creak
        c = creak(r, 0.14, lin(0.14, (0, 140), (0.14, 220)), [(1100, 1), (1900, 0.5)], q=9)
        put(x, c * lin(0.14, (0, 0), (0.03, 1), (0.14, 0)) * 0.06, 0.03)
    return x


def step_heel(r, w=1.0):
    """Heeled boot on stone: sharp heel click, then the sole taps down."""
    d = 0.3
    x = std1(hp(noise(r, d), 2000)) * decay(d, 0.0015) * 0.45
    x += tone(r.uniform(1900, 2500), d, 0.01, METAL, attack=0.0003) * 0.15
    x += std1(bp(noise(r, d), 250, 2000)) * decay(d, 0.007) * 0.5
    x += osc(expo(d, (0, 130), (0.05, 85), (d, 85))) * decay(d, 0.02) * 0.65 * w
    toe = std1(bp(noise(r, 0.1), 500, 4000)) * decay(0.1, 0.007) * 0.3
    put(x, toe, r.uniform(0.07, 0.1))
    return x


def step_wood(r, w=1.0, heel=False):
    """Boot on old floorboards, often followed by a creak."""
    d = 0.5
    x = fit(wood_body(r, w), n(d)) * 0.6
    x += osc(expo(d, (0, 110), (0.08, 75), (d, 75))) * decay(d, 0.03 + 0.01 * w) * 0.7 * w
    x += std1(bp(noise(r, d), 400, 3500)) * decay(d, 0.003 if heel else 0.008) * (0.6 if heel else 0.35)
    if heel:
        x += std1(hp(noise(r, d), 3000)) * decay(d, 0.0012) * 0.5
    put(x, wood_body(r, 0.25, 0.3), r.uniform(0.07, 0.09))
    if r.random() < 0.6:
        c = creak(r, 0.45, lin(0.45, (0, r.uniform(15, 25)), (0.45, r.uniform(35, 60))),
                  [(r.uniform(380, 480), 1), (r.uniform(700, 850), 0.6), (r.uniform(1200, 1500), 0.3)], q=14)
        put(x, c * lin(0.45, (0, 0), (0.08, 1), (0.3, 0.7), (0.45, 0)) * r.uniform(0.15, 0.3), 0.02)
    return x


def step_grass(r, w=1.0, gravel=0.6, leaves=0.0):
    """Foot pressing into grass, with gravel crunch and/or dry leaves."""
    d = 0.4
    x = std1(bp(noise(r, d, 0.5), 600, 4500)) * lin(d, (0, 0), (0.012, 1), (0.05, 0.45), (0.3, 0)) * 0.35
    x += std1(lp(noise(r, d), 220)) * decay(d, 0.025) * 0.5 * w
    x += crackle(r, d, 40 * gravel / 0.05 * decay(d, 0.05, 0), 1500, 7000) * 0.9
    if leaves:
        x += crackle(r, d, 700 * leaves * lin(d, (0, 0), (0.02, 1), (0.2, 0.3), (0.35, 0)), 2500, 11000) * 0.5
        x += std1(bp(noise(r, d), 2500, 9000)) * lin(d, (0, 0), (0.02, 1), (0.25, 0)) * 0.12
    return x


def cloth(r, d, times, band=(800, 4500), width=0.4, base=0.12, gain=0.2, delay=0.1):
    """Robe/cloak rustle that swells with every step."""
    env = np.full(n(d), base)
    for at in times:
        put(env, np.hanning(n(width)), at + delay)
    return std1(bp(noise(r, d, 0.5), *band)) * env * wobble(r, d, 25, 0.6) * gain


def flaps(r, d, rate, band=(500, 3000), gain=0.25):
    """Cloth flapping in the wind: a train of soft snaps."""
    x = np.zeros(n(d))
    for at in events(r, d, rate):
        snap_ = std1(bp(noise(r, 0.08), *band)) * decay(0.08, r.uniform(0.01, 0.025), 0.004)
        put(x, snap_, at, r.uniform(0.3, 1.0))
    return x * gain


def walk(r, d, interval, step, w=1.0, start=0.12, tail=0.45, jitter=0.03):
    """A sequence of steps (alternating feet) over d seconds; returns (buffer, step times)."""
    x = np.zeros(n(d + 1.0))
    times = []
    at = start
    while at < d - tail:
        times.append(at)
        at += interval * r.uniform(1 - jitter, 1 + jitter)
    for i, at in enumerate(times):
        put(x, step(r, w * (1.0 if i % 2 == 0 else 0.88) * r.uniform(0.92, 1.05)), at)
    return x, times


@sfx(peak=-3)
def wizard_steps_stone(r, d):
    x, times = walk(r, d, 0.74, step_stone, w=1.25)
    x += cloth(r, d + 1, times, (700, 4000), width=0.45, base=0.03, gain=0.05)
    return room(r, x, "castle")


@sfx(peak=-3)
def wizard_steps_wood(r, d):
    x, times = walk(r, d, 0.7, step_wood, w=1.2)
    x += cloth(r, d + 1, times, (700, 4000), width=0.45, base=0.03, gain=0.05)
    return room(r, x, "wood")


@sfx(peak=-3)
def wizard_steps_grass(r, d):
    x, times = walk(r, d, 0.7, lambda r, w: step_grass(r, w, gravel=0.7), w=1.2)
    x += cloth(r, d + 1, times, (600, 3500), width=0.45, base=0.04, gain=0.08)
    return room(r, x, "outdoor")


@sfx(peak=-3)
def wizard_run_stone(r, d):
    x, times = walk(r, d, 0.31, step_stone, w=1.4, start=0.06, tail=0.3)
    env = lin(d + 1, (0, 0), (0.2, 1), (d - 0.15, 1), (d + 0.1, 0))
    x += flaps(r, d + 1, 10, (500, 2800), 0.09) * env
    x += cloth(r, d + 1, times, (700, 4000), width=0.25, base=0.05, gain=0.05)
    return room(r, x, "castle", 0.35)


@sfx(peak=-3)
def wizard_jump_land(r, d):
    x = np.zeros(n(d + 1))
    put(x, step_stone(r, 0.7) * 0.6, 0.03)
    put(x, std1(bp(noise(r, 0.3), 1500, 6000)) * lin(0.3, (0, 0), (0.03, 1), (0.1, 0)) * 0.1, 0.05)
    put(x, std1(bp(noise(r, 0.55), 600, 3500)) * lin(0.55, (0, 0), (0.25, 1), (0.5, 0.3), (0.55, 0)) * 0.07, 0.08)
    land = 0.55
    put(x, step_stone(r, 1.6), land, 1.5)
    put(x, step_stone(r, 1.4), land + 0.022, 1.3)
    put(x, boom(0.3, 90, 45, 0.06), land, 0.8)
    put(x, std1(bp(noise(r, 0.35), 700, 4000)) * lin(0.35, (0, 0), (0.04, 1), (0.35, 0)) * 0.08, land + 0.02)
    return room(r, x, "castle")


@sfx(peak=-3)
def witch_steps_stone(r, d):
    x, times = walk(r, d, 0.47, step_heel, w=0.8)
    x += cloth(r, d + 1, times, (1200, 6000), width=0.3, base=0.04, gain=0.08)
    return room(r, x, "castle")


@sfx(peak=-3)
def witch_steps_wood(r, d):
    x, times = walk(r, d, 0.5, lambda r, w: step_wood(r, w, heel=True), w=0.7)
    x += cloth(r, d + 1, times, (1500, 7000), width=0.3, base=0.04, gain=0.07)
    return room(r, x, "wood")


@sfx(peak=-3)
def witch_steps_grass(r, d):
    x, times = walk(r, d, 0.5, lambda r, w: step_grass(r, w, gravel=0.15, leaves=1.0), w=0.6)
    x += cloth(r, d + 1, times, (900, 5000), width=0.3, base=0.04, gain=0.07)
    return room(r, x, "outdoor")


@sfx(peak=-3)
def witch_run_stone(r, d):
    x, times = walk(r, d, 0.28, step_heel, w=1.0, start=0.06, tail=0.3)
    env = lin(d + 1, (0, 0), (0.2, 1), (d - 0.15, 1), (d + 0.1, 0))
    x += flaps(r, d + 1, 12, (800, 4000), 0.08) * env
    x += cloth(r, d + 1, times, (1200, 6000), width=0.2, base=0.05, gain=0.05)
    return room(r, x, "castle", 0.35)


# --------------------------------------------------------------------------- fire

@sfx()
def fire_cast(r, d):
    x = np.zeros(n(d + 0.8))
    shimmer = sum(osc(expo(0.4, (0, f), (0.4, f * 2))) for f in (620, 930, 1395))
    put(x, shimmer * lin(0.4, (0, 0), (0.3, 1), (0.4, 0.6)) * 0.12, 0)
    put(x, whoosh(r, 0.45, expo(0.45, (0, 300), (0.4, 2500), (0.45, 2500)),
                  lin(0.45, (0, 0), (0.35, 1), (0.45, 0.2)), q=1.2), 0, 0.5)
    ign = 0.3
    fwoomp = std1(sweep(noise(r, 0.5, 1.0), "lp", expo(0.5, (0, 200), (0.06, 4000), (0.5, 800)), 0.9))
    put(x, fwoomp * decay(0.5, 0.12, 0.004), ign, 0.9)
    put(x, boom(0.5, 110, 45, 0.1), ign, 0.8)
    rd = d + 0.5
    flight = std1(sweep(roar(r, rd, 2500), "lp", expo(rd, (0, 2500), (rd, 500)), 0.7))
    put(x, flight * lin(rd, (0, 0), (0.05, 1), (0.4, 0.8), (1.1, 0.1), (rd, 0)), ign, 0.7)
    put(x, crackle(r, rd, lin(rd, (0, 80), (1.2, 10), (rd, 0))), ign, 0.5)
    return room(r, x, "small")


@sfx(peak=-4, loop=3.0)
def fire_projectile_loop(r, d, length):
    t = tt(d)
    lfo = np.sin(2 * np.pi * snap(0.66, length) * t)
    x = roar(r, d, 1400, 6, 0.4) * 0.8
    x += whoosh(r, d, 900 * (1 + 0.5 * lfo), 0.4 + 0.2 * lfo, q=1.0) * 0.4
    x += crackle(r, d, 25) * 0.5
    return room(r, x, "small", 0.08)


@sfx()
def fire_impact(r, d):
    dd = d + 1.0
    x = np.zeros(n(dd))
    put(x, nrm(burst(r, 0.03, 0.003, lo=1000)), 0)
    put(x, boom(1.2, 120, 32, 0.35, 2.0), 0)
    blast = std1(sweep(noise(r, 1.5, 1.0), "lp", expo(1.5, (0, 6000), (0.5, 500), (1.5, 300)), 0.8))
    put(x, blast * decay(1.5, 0.28, 0.002), 0, 0.9)
    put(x, roar(r, 1.8, 1500) * lin(1.8, (0, 0), (0.03, 1), (0.5, 0.5), (1.8, 0)), 0.02, 0.6)
    embers = crackle(r, dd, lin(dd, (0, 20), (0.05, 90), (1.0, 15), (2.0, 3), (dd, 0)), 1800, 10000)
    x += embers * lin(dd, (0, 1), (2, 0.35), (dd, 0.35)) * 0.6
    return room(r, x, "castle", 0.25)


@sfx(peak=-4, loop=4.0)
def fire_stream_loop(r, d, length):
    x = roar(r, d, 2000, 12, 0.3)
    x += std1(hp(noise(r, d), 3500)) * wobble(r, d, 20, 0.3) * 0.25
    x += crackle(r, d, 45) * 0.4
    x += std1(lp(noise(r, d, 2.0), 120)) * 0.5
    return room(r, x, "small", 0.06)


# --------------------------------------------------------------------------- ice

@sfx()
def ice_cast(r, d):
    x = np.zeros(n(d + 0.8))
    put(x, whoosh(r, 1.2, expo(1.2, (0, 700), (1.0, 3200), (1.2, 2000)),
                  lin(1.2, (0, 0), (0.8, 1), (1.2, 0)), q=2.0), 0, 0.45)
    put(x, sparkles(r, 1.3, lin(1.3, (0, 10), (1.0, 60), (1.3, 5)), 2500, 9000, (0.05, 0.3)), 0, 0.35)
    pad = sum(osc(const(1.2, f)) for f in (1568, 2093, 2637)) * (1 + 0.1 * np.sin(2 * np.pi * 6 * tt(1.2)))
    put(x, pad * lin(1.2, (0, 0), (0.9, 1), (1.2, 0)), 0, 0.03)
    put(x, crackle(r, 1.0, lin(1.0, (0, 0), (0.9, 120), (1.0, 0)), 2500, 9000), 0.1, 0.35)
    launch = 0.95
    put(x, whoosh(r, 0.4, expo(0.4, (0, 4000), (0.4, 1500)), lin(0.4, (0, 0), (0.05, 1), (0.4, 0)), q=1.5),
        launch, 0.6)
    put(x, shatter(r, 0.5, shards=10, lo=3000, hi=9000, spread=0.05), launch, 0.35)
    put(x, std1(lp(noise(r, 1.0, 2.0), 200)) * lin(1.0, (0, 0), (0.95, 1), (1.0, 0)), 0, 0.5)
    put(x, boom(0.6, 90, 45, 0.15, 1.5), launch, 0.7)
    return room(r, x, "hall", 0.2)


@sfx()
def ice_impact(r, d):
    dd = d + 0.8
    x = np.zeros(n(dd))
    put(x, shatter(r, 1.4, shards=55, lo=1800, hi=9500, spread=0.1), 0, 0.9)
    put(x, crackle(r, 0.4, 3000 * decay(0.4, 0.06, 0), 1200, 6000), 0, 0.8)
    put(x, boom(0.6, 130, 50, 0.12, 1.6), 0, 1.0)
    put(x, std1(lp(noise(r, 0.5, 2.0), 250)) * decay(0.5, 0.1, 0.002), 0, 0.5)
    x += std1(hp(noise(r, dd), 4500)) * decay(dd, 0.45, 0.01) * 0.25
    return room(r, x, "hall", 0.2)


@sfx()
def ice_freeze(r, d):
    x = np.zeros(n(d + 0.8))
    put(x, crackle(r, d, lin(d, (0, 4), (2.3, 90), (d, 8)), 800, 6000) * lin(d, (0, 0.4), (2.3, 1), (d, 0.3)), 0, 0.8)
    put(x, sparkles(r, d, lin(d, (0, 1), (d, 15)), 4000, 10000, (0.01, 0.04)), 0, 0.25)
    for at in np.sort(r.uniform(0.2, d - 0.8, 5)):
        c = creak(r, 0.25, lin(0.25, (0, r.uniform(180, 260)), (0.25, r.uniform(80, 140))),
                  [(r.uniform(1800, 2600), 1), (r.uniform(3500, 4500), 0.5)], q=18)
        put(x, c * lin(0.25, (0, 0), (0.03, 1), (0.25, 0)), at, 0.3 * (0.5 + at / d))
    put(x, std1(hp(noise(r, d), 5000)) * lin(d, (0, 0.05), (2.3, 0.3), (d, 0.05)), 0, 0.12)
    put(x, std1(lp(noise(r, d, 2.0), 150)) * lin(d, (0, 0), (2.3, 0.3), (d, 0)), 0, 0.7)
    groan = creak(r, d, lin(d, (0, 8), (d, 14)), [(160, 1), (310, 0.6)], q=8)
    put(x, groan * lin(d, (0, 0), (1.0, 0.6), (2.3, 1), (d, 0)), 0, 0.35)
    return room(r, x, "small", 0.15)


@sfx()
def ice_break_free(r, d):
    x = np.zeros(n(d + 0.8))
    for at, g in [(0.08, 0.35), (0.3, 0.5), (0.46, 0.6), (0.58, 0.75), (0.66, 0.85)]:
        put(x, crack(r, g), at)
        put(x, boom(0.4, 110, 50, 0.08, 1.5), at, 0.6 * g)
    stress = creak(r, 0.6, lin(0.6, (0, 40), (0.6, 120)), [(900, 1), (1700, 0.6), (3100, 0.3)], q=15)
    put(x, stress * lin(0.6, (0, 0), (0.1, 0.6), (0.6, 1)), 0.1, 0.25)
    brk = 0.72
    put(x, shatter(r, 1.3, shards=70, lo=1200, hi=8000, spread=0.15), brk)
    put(x, boom(0.5, 90, 45, 0.12, 1.8), brk, 0.8)
    for at in brk + 0.03 + r.exponential(0.25, 12):
        chunk = tone(r.uniform(300, 900), 0.2, 0.03, GLASS, attack=0.0005) + burst(r, 0.2, 0.004, lo=800) * 0.3
        put(x, chunk, at, r.uniform(0.2, 0.6))
    put(x, sparkles(r, 1.2, lin(1.2, (0, 40), (1.2, 0)), 3000, 9000, (0.02, 0.08)), brk + 0.08, 0.3)
    return room(r, x, "hall", 0.22)


# --------------------------------------------------------------------------- poison

@sfx()
def poison_cast(r, d):
    x = np.zeros(n(d + 0.6))
    k = 1.4
    put(x, bubbles(r, k, lin(k, (0, 15), (0.9, 45), (k, 10)), 180, 700, (0.04, 0.12), (0.4, 1.2)), 0, 0.5)
    slime = std1(bp(noise(r, k, 1.0), 400, 2500)) * wobble(r, k, 18, 0.9)
    put(x, slime * lin(k, (0, 0), (0.6, 1), (k, 0)), 0, 0.3)
    put(x, crackle(r, k, lin(k, (0, 50), (1.0, 600), (k, 100)), 3500, 11000), 0, 0.35)
    put(x, std1(hp(noise(r, k), 6000)) * lin(k, (0, 0), (1.0, 1), (k, 0)), 0, 0.1)
    put(x, whoosh(r, 0.6, expo(0.6, (0, 350), (0.4, 1400), (0.6, 900)), lin(0.6, (0, 0), (0.3, 1), (0.6, 0)), q=1.3),
        0.55, 0.45)
    eerie = osc(const(k, 110)) + osc(const(k, 116.5))
    put(x, eerie * lin(k, (0, 0), (0.5, 1), (k, 0)), 0, 0.06)
    return room(r, x, "small", 0.15)


@sfx(peak=-4, loop=5.0)
def poison_cloud_loop(r, d, length):
    x = bubbles(r, d, 7, 110, 380, (0.06, 0.16), (0.3, 0.8)) * 0.55
    x += bubbles(r, d, 5, 500, 1100, (0.02, 0.05), (0.5, 1.0)) * 0.2
    x += std1(bp(noise(r, d, 1.0), 400, 2200)) * wobble(r, d, 0.6, 0.4) * 0.3
    x += std1(hp(noise(r, d), 5000)) * wobble(r, d, 1, 0.5) * 0.05
    t = tt(length)
    drone = sum(g * osc(const(length, snap(f, length))) for f, g in [(98, 1), (98.8, 0.8), (138.6, 0.6), (196, 0.3)])
    drone *= 0.7 + 0.3 * np.sin(2 * np.pi * snap(0.4, length) * t)
    return room(r, x, "small", 0.12), drone * 0.05


@sfx()
def poison_impact(r, d):
    x = np.zeros(n(d + 0.6))
    splat = std1(sweep(noise(r, 0.3, 1.0), "lp", expo(0.3, (0, 3500), (0.08, 500), (0.3, 250)), 1.2))
    put(x, splat * decay(0.3, 0.05, 0.002), 0)
    put(x, nrm(reson(noise(r, 0.3) * decay(0.3, 0.02), 260, 4)), 0, 0.5)
    put(x, boom(0.3, 100, 55, 0.05, 1.3), 0, 0.6)
    put(x, bubbles(r, 0.6, 60 * decay(0.6, 0.15, 0), 700, 2500, (0.015, 0.04), (0.5, 1.5)), 0.03, 0.4)
    k = 1.4
    put(x, crackle(r, k, lin(k, (0, 100), (0.1, 900), (k, 30)), 3500, 11000) * lin(k, (0, 1), (k, 0.2)), 0.03, 0.45)
    put(x, std1(hp(noise(r, k), 4000)) * decay(k, 0.45, 0.02), 0, 0.2)
    return room(r, x, "small", 0.12)


@sfx(peak=-4)
def poison_tick(r, d):
    x = np.zeros(n(d + 0.4))
    put(x, bubble(340, 0.09, 0.9), 0.005, 0.9)
    put(x, bubble(362, 0.08, 0.8), 0.012, 0.5)
    put(x, burst(r, 0.02, 0.002, lo=800, hi=5000), 0.07, 0.3)
    put(x, std1(bp(noise(r, 0.4), 3000, 9000)) * lin(0.4, (0, 0), (0.05, 1), (0.4, 0)), 0.05, 0.03)
    return room(r, x, "small", 0.1)


# --------------------------------------------------------------------------- lightning

@sfx()
def lightning_cast(r, d):
    x = np.zeros(n(d + 0.8))
    b = 1.1
    grow = lin(b, (0, 0), (b, 1))
    put(x, sparks(r, b, expo(b, (0, 8), (b, 160))) * (0.3 + 0.7 * grow), 0, 0.6)
    put(x, buzz(r, b, expo(b, (0, 55), (b, 160))) * grow ** 2, 0, 0.35)
    put(x, osc(expo(b, (0, 500), (b, 3500))) * grow ** 2, 0, 0.08)
    put(x, zap(r), b)
    put(x, thunder(r, 0.6, 350, 0.18), b, 0.6)
    return room(r, x, "hall", 0.2)


@sfx()
def lightning_impact(r, d):
    x = np.zeros(n(d + 0.8))
    put(x, drive(nrm(burst(r, 0.06, 0.012, lo=300)), 2.0), 0)
    put(x, zap(r), 0)
    put(x, boom(0.8, 95, 38, 0.25, 2.0), 0, 0.9)
    put(x, sparks(r, 0.9, lin(0.9, (0, 120), (0.9, 5))), 0.02, 0.5)
    put(x, buzz(r, 0.9, 120) * decay(0.9, 0.25), 0.02, 0.35)
    put(x, thunder(r, 1.95, 300, 0.7), 0.04, 1.5)
    return room(r, x, "castle", 0.25)


@sfx(peak=-4, loop=3.0)
def lightning_sparks_loop(r, d, length):
    x = sparks(r, d, 22 * wobble(r, d, 1.5, 0.6)) * 0.8
    x += buzz(r, d, 100) * wobble(r, d, 6, 0.8) * 0.18
    x += std1(hp(noise(r, d), 6000)) * 0.03
    hum = osc(const(length, snap(100, length))) + 0.5 * osc(const(length, snap(200, length)))
    return room(r, x, "small", 0.06), hum * 0.03


# --------------------------------------------------------------------------- dark magic

@sfx()
def dark_cast(r, d):
    x = np.zeros(n(d + 1.2))
    body = std1(sweep(noise(r, d, 1.5), "lp", expo(d, (0, 150), (0.8, 1400), (d, 200)), 1.5))
    put(x, body * lin(d, (0, 0), (0.8, 1), (d, 0)), 0, 0.7)
    put(x, osc(expo(d, (0, 48), (d, 36))) * lin(d, (0, 0), (0.6, 1), (d, 0)), 0, 0.6)
    v = 1.6
    f = expo(v, (0, 190), (v, 120)) * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * tt(v)))
    src = osc(f, "saw") + 0.6 * osc(f * 0.5 * 1.003, "saw")
    voice = nrm(formant(src, [(300, 5, 1.0), (870, 7, 0.4), (2240, 10, 0.15)])) * lin(v, (0, 0), (0.4, 1), (v, 0))
    put(x, echo(fit(voice, n(v + 1.0)), 0.21, 0.5, 2000), 0.15, 0.25)
    whisper = std1(bp(noise(r, v), 1500, 5000)) * wobble(r, v, 6, 0.8) * lin(v, (0, 0), (0.6, 1), (v, 0))
    put(x, whisper, 0.1, 0.08)
    return room(r, drive(nrm(x), 1.3), "castle", 0.4)


@sfx()
def dark_impact(r, d):
    x = np.zeros(n(d + 1.2))
    hit = 0.3
    swell = std1(sweep(noise(r, hit, 1.0), "lp", expo(hit, (0, 200), (hit, 2500)), 0.8))
    put(x, swell * lin(hit, (0, 0), (hit, 1)) ** 3, 0, 0.6)
    put(x, osc(expo(hit, (0, 30), (hit, 70))) * lin(hit, (0, 0), (hit, 1)) ** 2, 0, 0.5)
    put(x, boom(1.5, 75, 28, 0.45, 2.5), hit)
    put(x, std1(lp(noise(r, 1.0, 2.0), 300)) * decay(1.0, 0.2, 0.003), hit, 0.6)
    tl = 1.6
    drone = osc(const(tl, 55), "saw") + osc(const(tl, 57.5), "saw")
    drone = sweep(drone, "lp", expo(tl, (0, 600), (tl, 80)), 1.2) * decay(tl, 0.6, 0.05)
    put(x, nrm(drone), hit + 0.05, 0.3)
    whisper = std1(bp(noise(r, tl), 2000, 6000)) * wobble(r, tl, 5, 0.8) * decay(tl, 0.5, 0.2)
    put(x, whisper, hit, 0.05)
    return reverb(r, x, 2.5, 0.35, 3500)


@sfx()
def dark_charge(r, d):
    k = lin(d, (0, 0), (d, 1))
    f = 55 * (1 + 0.12 * k)
    drone = osc(f, "saw") + osc(f * 1.006, "saw") + 0.6 * osc(f * 1.5, "saw") + 0.5 * osc(f * 2 * 0.997, "saw")
    drone = nrm(sweep(drone, "lp", 120 + 1800 * k ** 1.5, 1.2)) * (0.2 + 0.8 * k)
    trem = 1 + 0.5 * np.sin(2 * np.pi * np.cumsum(3 + 11 * k) / SR)
    rumble = std1(lp(noise(r, d, 2.0), 140)) * (0.3 + 0.7 * k) * trem
    x = drive(nrm(drone * 0.8 + rumble * 0.5), 1 + 3 * k) * lin(d, (0, 0.15), (d, 1))
    return room(r, fit(x, n(d + 0.5)), "hall", 0.2)


# --------------------------------------------------------------------------- light & healing

@sfx()
def heal(r, d):
    x = np.zeros(n(d + 1.2))
    for i, m in enumerate([72, 74, 76, 79, 81, 84, 88]):
        put(x, tone(hz(m), 1.6, 0.6, CHIME, attack=0.012), 0.02 + i * 0.16, 0.5 + i * 0.05)
    t = tt(d)
    hum = osc(const(d, 261.6)) + 0.6 * osc(const(d, 392.0)) + 0.4 * osc(const(d, 523.25 * 1.003))
    hum += 0.8 * osc(const(d, 130.8)) + 0.5 * osc(const(d, 65.4))
    put(x, hum * (1 + 0.15 * np.sin(2 * np.pi * 4 * t)) * lin(d, (0, 0), (0.35, 1), (1.5, 0.8), (d, 0)), 0, 0.18)
    put(x, sparkles(r, 1.6, 12, 4000, 9000, (0.05, 0.2), rise=0.5), 0.1, 0.15)
    return room(r, x, "castle", 0.35)


@sfx()
def light_cast(r, d):
    x = np.zeros(n(d + 1.0))
    put(x, osc(expo(0.12, (0, 1500), (0.12, 5000))) * lin(0.12, (0, 0), (0.12, 1)), 0, 0.3)
    burst_at = 0.1
    put(x, std1(hp(noise(r, 0.3), 3000)) * decay(0.3, 0.04, 0.002), burst_at, 0.5)
    put(x, sparkles(r, 0.6, 200 * decay(0.6, 0.12, 0), 3500, 11000, (0.03, 0.15)), burst_at, 0.5)
    put(x, tone(1318.5, 1.4, 0.45, CHIME), burst_at, 0.6)
    put(x, tone(1975.5, 1.4, 0.35, CHIME), burst_at, 0.35)
    put(x, body(130.8, decay(1.4, 0.5, 0.02)), burst_at, 0.35)
    put(x, boom(0.4, 100, 60, 0.1), burst_at, 0.4)
    return room(r, x, "hall", 0.3)


@sfx()
def revive(r, d):
    x = np.zeros(n(d + 1.5))
    t = tt(d)
    src = np.zeros(n(d))
    for m in (60, 64, 67, 72, 76):
        for det in (-0.004, 0.0, 0.004):
            vib = 1 + 0.004 * np.sin(2 * np.pi * 5 * t + r.uniform(0, 2 * np.pi))
            src += osc(hz(m) * (1 + det) * vib, "saw")
    choir = formant(src, [(800, 6, 1.0), (1150, 8, 0.5), (2900, 12, 0.2)]) + 0.3 * lp(src, 1200) + 0.4 * lp(src, 350)
    choir = nrm(sweep(choir, "lp", expo(d, (0, 400), (1.9, 5000), (d, 1500)), 0.7))
    put(x, choir * lin(d, (0, 0), (1.9, 1), (d, 0)) ** 1.2, 0, 0.5)
    put(x, body(65.4, lin(d, (0, 0), (1.9, 1), (d, 0)) ** 1.5), 0, 0.3)
    put(x, bells(r, d, lin(d, (0, 2), (1.9, 25), (d, 0)), [84, 86, 88, 91, 93, 96, 98, 100], (0.2, 0.6)), 0, 0.3)
    put(x, tone(hz(96), 1.4, 0.4, CHIME), 1.9, 0.4)
    put(x, tone(hz(100), 1.4, 0.35, CHIME), 1.9, 0.3)
    return room(r, x, "castle", 0.4)


# --------------------------------------------------------------------------- shield, wind & earth

@sfx()
def shield_activate(r, d):
    x = np.zeros(n(d + 0.8))
    f = expo(d, (0, 60), (0.45, 98), (d, 98))
    hum = osc(f) + 0.5 * osc(f * 2) + 0.3 * osc(f * 3.01) + 0.2 * osc(f * 4.02)
    hum = sweep(hum, "lp", expo(d, (0, 200), (0.5, 2500), (d, 1200)), 0.9)
    hum *= (1 + 0.25 * np.sin(2 * np.pi * 7 * tt(d))) * lin(d, (0, 0), (0.4, 1), (1.1, 0.7), (d, 0))
    put(x, nrm(hum), 0, 0.7)
    put(x, whoosh(r, 0.6, expo(0.6, (0, 250), (0.5, 3000), (0.6, 3000)), lin(0.6, (0, 0), (0.45, 1), (0.6, 0)), q=4.0),
        0, 0.35)
    chime = 0.45
    for m, g in [(88, 0.3), (95, 0.22), (100, 0.15)]:
        put(x, tone(hz(m), 1.0, 0.4, GLASS), chime, g)
    put(x, sparkles(r, 0.5, 60 * decay(0.5, 0.12, 0), 4000, 10000), chime, 0.2)
    return room(r, x, "hall", 0.22)


@sfx()
def shield_hit(r, d):
    x = np.zeros(n(d + 0.8))
    put(x, boom(0.4, 90, 50, 0.07, 1.8), 0)
    put(x, nrm(burst(r, 0.1, 0.01, hi=1500)), 0, 0.5)
    k = 0.9
    t = tt(k)
    ring = sum(g * osc(const(k, f)) for f, g in [(110, 1), (111.7, 0.8), (166, 0.5), (221, 0.4), (331, 0.25)])
    ripple = 1 + 0.6 * decay(k, 0.3) * np.sin(2 * np.pi * 13 * t)
    put(x, nrm(ring) * decay(k, 0.35, 0.005) * ripple, 0, 0.6)
    put(x, std1(sweep(noise(r, k, 1.0), "bp", 800 * (1 + 0.5 * np.sin(2 * np.pi * 13 * t)), 3)) * decay(k, 0.2), 0, 0.2)
    put(x, tone(2100, 0.8, 0.2, GLASS), 0, 0.12)
    return room(r, x, "hall", 0.15)


@sfx()
def shield_break(r, d):
    x = np.zeros(n(d + 0.8))
    put(x, nrm(burst(r, 0.05, 0.004, lo=1000)), 0, 0.8)
    put(x, shatter(r, 1.0, shards=45, lo=1500, hi=7000, spread=0.08), 0, 0.8)
    for at in r.exponential(0.1, 8):
        put(x, tone(hz(r.choice([84, 86, 88, 91, 93, 96])), 0.6, 0.15, CHIME), at, r.uniform(0.1, 0.3))
    k = 1.4
    f = expo(k, (0, 98), (k, 45))
    hum = osc(f) + 0.5 * osc(f * 2) + 0.3 * osc(f * 3)
    flutter = 1 + 0.5 * np.sign(np.sin(2 * np.pi * np.cumsum(lin(k, (0, 20), (k, 5))) / SR))
    put(x, nrm(hum) * flutter * lin(k, (0, 1), (k, 0)) ** 1.5, 0, 0.7)
    put(x, whoosh(r, 1.0, expo(1.0, (0, 4000), (1.0, 300)), decay(1.0, 0.3), q=2.0), 0, 0.3)
    put(x, boom(0.8, 80, 35, 0.2, 1.8), 0, 0.8)
    return room(r, x, "hall", 0.25)


@sfx()
def wind_cast(r, d):
    x = np.zeros(n(d + 0.6))
    t = tt(d)
    env = lin(d, (0, 0), (0.35, 1), (0.7, 0.7), (d, 0))
    put(x, whoosh(r, d, expo(d, (0, 300), (0.45, 1500), (d, 500)), env, q=1.0), 0, 0.8)
    whistle_fc = 1400 * (1 + 0.35 * np.sin(2 * np.pi * 3.5 * t)) * expo(d, (0, 0.7), (0.4, 1.2), (d, 0.8))
    put(x, std1(sweep(noise(r, d), "bp", whistle_fc, 9)) * env, 0, 0.25)
    put(x, std1(lp(noise(r, d, 2.0), 180)) * env, 0, 0.5)
    swirl = osc(expo(d, (0, 880), (d, 1760)) * (1 + 0.02 * np.sin(2 * np.pi * 6 * t)))
    put(x, swirl * env, 0, 0.06)
    put(x, sparkles(r, d, 15, 3000, 8000), 0, 0.12)
    return room(r, x, "hall", 0.12)


@sfx()
def earth_cast(r, d):
    x = np.zeros(n(d + 0.8))
    put(x, std1(lp(noise(r, d, 2.0), 110)) * lin(d, (0, 0), (0.25, 1), (1.2, 0.7), (d, 0)), 0, 0.9)
    burst_at = 0.25
    put(x, boom(1.0, 70, 32, 0.35, 2.2), burst_at, 0.9)
    for at, g in [(0.25, 1.0), (0.33, 0.7), (0.42, 0.8)]:
        put(x, nrm(burst(r, 0.2, 0.012, lo=300, hi=6000)) * g + boom(0.2, 180, 100, 0.03) * 0.4 * g, at)
    grind = std1(bp(noise(r, 1.3), 250, 1600)) * wobble(r, 1.3, 25, 0.9) * lin(1.3, (0, 0), (0.1, 1), (1.3, 0))
    put(x, grind, burst_at, 0.35)
    for at in burst_at + 0.05 + r.exponential(0.35, 45):
        size = r.random()
        f = 220 + 900 * (1 - size)
        hit = noise(r, 0.12) * decay(0.12, 0.003)
        rock = nrm(sum(reson(hit, f * k, 6) for k in (1, 1.7, 2.9))) * decay(0.12, 0.02 + 0.03 * size)
        rock += nrm(burst(r, 0.12, 0.003, lo=1500)) * 0.4
        put(x, rock, at, (0.3 + 0.7 * size) * np.exp(-(at - burst_at) / 0.8))
    return room(r, x, "hall", 0.18)


# --------------------------------------------------------------------------- special effects

@sfx()
def teleport(r, d):
    x = np.zeros(n(d + 0.8))
    pop = 0.68
    rise = lin(pop, (0, 0), (pop, 1)) ** 2
    swirl_rate = np.cumsum(lin(pop, (0, 3), (pop, 25))) / SR
    fc = expo(pop, (0, 200), (pop, 6000)) * (1 + 0.3 * np.sin(2 * np.pi * swirl_rate))
    put(x, whoosh(r, pop, fc, rise, q=2.5), 0, 0.7)
    vib_rate = np.cumsum(lin(pop, (0, 4), (pop, 22))) / SR
    put(x, osc(expo(pop, (0, 250), (pop, 1600)) * (1 + 0.03 * np.sin(2 * np.pi * vib_rate))) * rise, 0, 0.15)
    put(x, osc(expo(0.06, (0, 1400), (0.06, 220))) * decay(0.06, 0.018, 0.0005), pop, 0.9)
    put(x, nrm(burst(r, 0.02, 0.0015, lo=2000)), pop, 0.6)
    put(x, boom(0.4, 120, 50, 0.08, 1.6), pop, 0.9)
    put(x, body(expo(pop, (0, 40), (pop, 90)), rise), 0, 0.5)
    put(x, sparkles(r, 0.3, 90 * decay(0.3, 0.08, 0), 3500, 10000), pop, 0.35)
    return room(r, x, "hall", 0.2)


@sfx()
def spell_fail(r, d):
    x = np.zeros(n(d + 0.5))
    k = 0.6
    gate_src = std1(lp(r.standard_normal(n(k)), 25))
    gate = lp((gate_src > lin(k, (0, -0.2), (k, 0.8))).astype(float), 150)
    put(x, std1(bp(noise(r, k), 700, 4000)) * gate * lin(k, (0, 1), (k, 0.3)), 0, 0.45)
    w = 0.55
    wah = osc(expo(w, (0, 650), (w, 170)) * (1 + 0.04 * np.sin(2 * np.pi * 7 * tt(w))), "tri")
    put(x, lp(wah, 2500) * lin(w, (0, 0), (0.05, 1), (w, 0)), 0, 0.18)
    put(x, crackle(r, k, 40, 800, 5000), 0, 0.3)
    p = 0.35
    puff = std1(sweep(noise(r, p, 1.0), "lp", expo(p, (0, 1400), (p, 300)), 0.7))
    put(x, puff * lin(p, (0, 0), (0.03, 1), (p, 0)) ** 1.5, 0.62, 0.5)
    return room(r, x, "small", 0.12)


@sfx()
def wand_draw(r, d):
    x = np.zeros(n(d + 0.6))
    k = 0.4
    rustle = std1(bp(noise(r, k, 0.5), 1200, 6000)) * wobble(r, k, 30, 0.8)
    put(x, rustle * lin(k, (0, 0), (0.08, 1), (0.3, 0.6), (k, 0)), 0, 0.35)
    s = 0.3
    slide = std1(bp(noise(r, s), 600, 2000)) * lin(s, (0, 0), (0.05, 1), (0.25, 1), (s, 0))
    put(x, slide, 0.22, 0.25)
    put(x, creak(r, s, lin(s, (0, 60), (s, 90)), [(900, 1), (1600, 0.5)], q=6) * lin(s, (0, 0), (0.1, 1), (s, 0)),
        0.22, 0.06)
    w = 0.18
    put(x, whoosh(r, w, expo(w, (0, 1200), (w, 3500)), lin(w, (0, 0), (0.08, 1), (w, 0)), q=1.2), 0.48, 0.3)
    put(x, std1(lp(noise(r, 0.3, 2.0), 300)) * lin(0.3, (0, 0), (0.12, 1), (0.3, 0)), 0.42, 0.4)
    put(x, body(130.8, decay(0.5, 0.2, 0.01)), 0.55, 0.25)
    put(x, sparkles(r, 0.4, 50 * decay(0.4, 0.12, 0), 4000, 10000), 0.55, 0.35)
    put(x, tone(hz(100), 0.6, 0.25, CHIME), 0.56, 0.2)
    return room(r, x, "small", 0.12)


@sfx()
def spell_charge(r, d):
    x = np.zeros(n(d + 0.4))
    k = lin(d, (0, 0), (d, 1))
    f = expo(d, (0, 110), (d, 330)) * (1 + (0.003 + 0.02 * k) * np.sin(2 * np.pi * np.cumsum(5 + 4 * k) / SR))
    hum = osc(f, "saw") * 0.5 + osc(f) * 0.8 + osc(f * 1.5) * 0.3 + osc(f / 2) * 0.7
    put(x, nrm(sweep(hum, "lp", 300 + 3500 * k ** 1.3, 1.5)) * (0.15 + 0.85 * k), 0, 0.6)
    fc = expo(d, (0, 500), (d, 3000)) * (1 + 0.3 * np.sin(2 * np.pi * np.cumsum(2 + 8 * k) / SR))
    put(x, std1(sweep(noise(r, d, 1.0), "bp", fc, 4)) * k, 0, 0.2)
    put(x, sparkles(r, d, 5 + 70 * k, 2500, 9000, rise=1.0), 0, 0.3)
    return room(r, x, "hall", 0.15)


@sfx(peak=-4, loop=5.0)
def broom_flight_loop(r, d, length):
    gust = wobble(r, d, 0.5, 0.35)
    x = std1(sweep(noise(r, d, 1.0), "bp", 900 * gust ** 1.2, 0.8)) * gust * 0.8
    x += std1(hp(noise(r, d), 2500)) * gust * 0.15
    x += std1(sweep(noise(r, d), "bp", 2300 * wobble(r, d, 0.3, 0.15), 12)) * 0.08
    x += flaps(r, d, 16 * gust, (500, 3000), 0.35)
    x += std1(lp(noise(r, d, 2.0), 90)) * gust * 0.35
    return x


@sfx(peak=-4, loop=6.0)
def cauldron_loop(r, d, length):
    x = bubbles(r, d, 4, 90, 260, (0.07, 0.18), (0.2, 0.6)) * 0.7
    x += bubbles(r, d, 9, 350, 900, (0.02, 0.06), (0.4, 1.0)) * 0.25
    x += std1(lp(noise(r, d, 1.0), 500)) * wobble(r, d, 3, 0.4) * 0.2
    x += bells(r, d, 1.2, [84, 86, 88, 91, 93, 96], (0.5, 1.0)) * 0.12
    t = tt(length)
    pad = sum(g * osc(const(length, snap(f, length))) for f, g in [(523.25, 1.0), (783.99, 0.7), (1048.6, 0.4)])
    pad *= 0.6 + 0.4 * np.sin(2 * np.pi * snap(0.5, length) * t)
    return room(r, x, "small", 0.15), pad * 0.03


@sfx()
def potion_drink(r, d):
    x = np.zeros(n(d + 0.6))
    put(x, tone(1850, 0.4, 0.09, GLASS), 0.04, 0.4)
    put(x, nrm(burst(r, 0.01, 0.001, lo=3000)), 0.04, 0.3)
    s = 0.3
    slosh = std1(bp(noise(r, s, 1.0), 300, 1500)) * wobble(r, s, 12, 0.8) * lin(s, (0, 0), (0.1, 1), (s, 0))
    put(x, slosh, 0.15, 0.25)
    put(x, bubbles(r, s, 30, 400, 1100), 0.15, 0.2)
    for at in (0.42, 0.72, 1.02):
        g = 0.14
        gulp = nrm(sweep(noise(r, g) * lin(g, (0, 0), (0.02, 1), (0.1, 0.3), (g, 0)), "bp",
                         expo(g, (0, 240), (g, 520)), 5))
        put(x, lp(gulp, 1000, 4), at, 1.4)
        put(x, boom(0.12, 95, 70, 0.03, 1.0), at, 0.7)
        put(x, bubble(r.uniform(250, 420), 0.07, 1.0), at + 0.06, 0.4)
        put(x, bubbles(r, 0.2, 40, 500, 1200, (0.015, 0.04)), at + 0.1, 0.2)
    magic = 1.25
    put(x, sparkles(r, 0.6, lin(0.6, (0, 80), (0.6, 0)), 3000, 10000, rise=0.6), magic, 0.25)
    for i, m in enumerate((84, 88, 91)):
        put(x, tone(hz(m), 0.8, 0.35, CHIME), magic + i * 0.06, 0.3)
    return room(r, x, "small", 0.12)


@sfx()
def door_open(r, d):
    x = np.zeros(n(d + 1.5))
    put(x, tone(900, 0.3, 0.05, METAL), 0.05, 0.35)
    put(x, nrm(burst(r, 0.03, 0.002, lo=1500)), 0.05, 0.4)
    put(x, boom(0.15, 110, 70, 0.03), 0.05, 0.4)
    put(x, fit(wood_body(r), n(0.4)), 0.12, 0.4)
    c = 2.2
    rate = lin(c, (0, 18), (0.5, 35), (1.0, 28), (1.5, 45), (c, 22))
    creaking = creak(r, c, rate, [(310, 1), (560, 0.7), (930, 0.45), (1480, 0.25)], q=11)
    put(x, creaking * lin(c, (0, 0), (0.15, 0.8), (0.8, 1), (1.6, 0.9), (c, 0)), 0.3, 0.55)
    put(x, std1(lp(noise(r, c, 2.0), 200)) * lin(c, (0, 0), (0.4, 1), (c, 0)), 0.3, 0.2)
    g = 1.7
    pad = osc(const(g, 329.6)) + 0.7 * osc(const(g, 493.9)) + 0.5 * osc(const(g, 659.3 * 1.003)) \
        + 0.3 * osc(const(g, 830.6))
    put(x, lp(pad, 3000) * lin(g, (0, 0), (0.9, 1), (g, 0)), 1.3, 0.12)
    put(x, sparkles(r, g, lin(g, (0, 0), (0.9, 30), (g, 0)), 3000, 9000), 1.3, 0.18)
    return room(r, x, "castle", 0.3)


@sfx(peak=-3)
def book_pages(r, d):
    x = np.zeros(n(d + 0.4))
    for at in (0.08, 0.68 + r.uniform(-0.03, 0.03), 1.25 + r.uniform(-0.03, 0.03)):
        p = 0.4
        env = lin(p, (0, 0), (0.05, 0.4), (0.25, 1), (0.3, 0.3), (p, 0))
        put(x, crackle(r, p, 900 * env, 1500, 7000), at, 0.6)
        put(x, std1(lp(noise(r, 0.15, 2.0), 250)) * decay(0.15, 0.03, 0.01), at + 0.25, 0.6)
        put(x, std1(bp(noise(r, p, 0.5), 1500, 8000)) * env, at, 0.25)
        put(x, std1(bp(noise(r, 0.06), 600, 4000)) * decay(0.06, 0.01), at + 0.27, 0.5)
    x += std1(hp(noise(r, d + 0.4), 6000)) * 0.015
    return room(r, x, "small", 0.08)


@sfx()
def spell_learn(r, d):
    x = np.zeros(n(d + 1.4))
    for i, m in enumerate((72, 76, 79, 84)):
        put(x, tone(hz(m), 1.2, 0.5, CHIME), i * 0.08, 0.5)
    chord = 0.36
    for m in (72, 76, 79, 84, 88):
        put(x, tone(hz(m), 2.5, 1.2, CHIME, attack=0.006), chord, 0.3)
    k = 1.6
    brass = sum(osc(const(k, hz(m)), "saw") for m in (48, 52, 55, 60))
    put(x, lp(brass, 2000) * lin(k, (0, 0), (0.05, 1), (k, 0)) ** 1.5, chord, 0.15)
    put(x, body(65.4, lin(k, (0, 0), (0.05, 1), (k, 0)) ** 1.5), chord, 0.3)
    put(x, boom(0.8, 90, 55, 0.25, 1.4), chord, 0.6)
    put(x, sparkles(r, 1.4, lin(1.4, (0, 20), (0.6, 70), (1.4, 5)), 3000, 9000, rise=1.0), 0, 0.3)
    return room(r, x, "castle", 0.35)


@sfx(peak=-3)
def item_pickup(r, d):
    x = np.zeros(n(d + 0.6))
    put(x, tone(hz(88), 0.5, 0.18, CHIME), 0, 0.5)
    put(x, tone(hz(95), 0.5, 0.22, CHIME), 0.06, 0.5)
    put(x, body(261.6, decay(0.5, 0.15, 0.005)) + body(130.8, decay(0.5, 0.12, 0.005)), 0, 0.3)
    put(x, sparkles(r, 0.25, 120 * decay(0.25, 0.07, 0), 5000, 11000, (0.02, 0.08)), 0, 0.35)
    return room(r, x, "hall", 0.15)


# --------------------------------------------------------------------------- cinematic

@sfx()
def cine_braam(r, d):
    x = np.zeros(n(d + 1.5))
    t = tt(d)
    env = lin(d, (0, 0), (0.03, 1), (1.0, 0.85), (d, 0))
    bright = expo(d, (0, 150), (0.08, 2600), (1.2, 900), (d, 250))
    blast = drive(brass([hz(m) for m in (24, 36, 43, 48, 51)], bright), 3.5) * env
    put(x, blast * (1 + 0.15 * np.sin(2 * np.pi * 31 * t)), 0, 0.8)
    put(x, body(32.7, env ** 1.3, 0.5), 0, 0.6)
    put(x, std1(lp(noise(r, 0.6, 2.0), 400)) * decay(0.6, 0.12, 0.005), 0, 0.5)
    put(x, boom(1.5, 70, 30, 0.4, 2.0), 0, 0.6)
    return room(r, x, "castle", 0.35)


@sfx()
def cine_hit(r, d):
    x = fit(big_hit(r, d), n(d + 2.0))
    return reverb(r, x, 3.5, 0.5, 3500)


@sfx()
def cine_sub_drop(r, d):
    x = np.zeros(n(d + 0.5))
    env = lin(d, (0, 0), (0.01, 1), (1.8, 0.7), (d, 0))
    put(x, body(expo(d, (0, 110), (1.8, 30), (d, 26)), env, 0.5), 0)
    put(x, std1(lp(noise(r, d, 2.0), 90)) * env * wobble(r, d, 4, 0.4), 0, 0.5)
    put(x, boom(0.4, 150, 70, 0.05), 0, 0.5)
    put(x, nrm(burst(r, 0.03, 0.004, lo=800)), 0, 0.2)
    return room(r, x, "hall", 0.12)


@sfx()
def cine_riser(r, d):
    return room(r, fit(riser(r, d), n(d + 0.5)), "hall", 0.2)


@sfx()
def cine_build_hit(r, d):
    x = np.zeros(n(d + 2.0))
    hit = 3.2
    put(x, room(r, riser(r, hit), "hall", 0.2), 0)
    put(x, reverb(r, big_hit(r, 3.0), 3.5, 0.5, 3500), hit + 0.04)
    return x


@sfx()
def cine_reverse_swell(r, d):
    x = np.zeros(n(d + 0.3))
    stop = 1.85
    put(x, reverse_crash(r, stop), 0)
    put(x, nrm(burst(r, 0.01, 0.001, hi=3000)), stop, 0.3)
    return x


@sfx()
def cine_whoosh_by(r, d):
    t = tt(d)
    c = 1.0
    prox = 1 / (1 + ((t - c) / 0.22) ** 2)
    fc = 250 + 1600 * prox * np.where(t < c, 1.0, 0.7)
    x = std1(sweep(noise(r, d, 1.0), "bp", fc, 0.9)) * prox
    x += std1(lp(noise(r, d, 2.0), 150)) * prox * 0.8
    x += body(140 * (1 + 0.12 * np.tanh(-(t - c) / 0.1)), prox ** 1.5, 0.5) * 0.5
    return room(r, fit(x, n(d + 0.5)), "hall", 0.15)


@sfx()
def cine_slowmo(r, d):
    src_d = 2.0
    src = crackle(r, src_d, 30) * 0.4
    src += whoosh(r, src_d, 800 * (1 + 0.5 * np.sin(2 * np.pi * 1.5 * tt(src_d))), 0.6, q=1.0) * 0.5
    put(src, tone(880, 1.5, 0.5, METAL), 0.1, 0.3)
    for at in (0.05, 0.6, 1.1):
        put(src, drum(r, 120, 60, 0.3), at, 0.6)
    rate = lin(d, (0, 1.0), (1.0, 0.3), (d, 0.25))
    y = np.interp(np.cumsum(rate), np.arange(len(src)), src, right=0.0)
    x = sweep(y, "lp", expo(d, (0, 8000), (1.0, 900), (d, 500)), 0.8)
    x += whoosh(r, d, expo(d, (0, 600), (d, 120)), lin(d, (0, 0), (0.3, 1), (d, 0.3)), q=0.8) * 0.5
    x += body(expo(d, (0, 90), (1.2, 38), (d, 36)), lin(d, (0, 0), (0.2, 1), (d, 0.2)), 0.5) * 0.6
    x *= lin(d, (0, 1), (1.4, 1), (d, 0.35))
    return room(r, fit(x, n(d + 1.0)), "castle", 0.4)


@sfx()
def cine_shellshock(r, d):
    x = np.zeros(n(d + 0.8))
    blast = boom(1.5, 90, 30, 0.4, 2.5) + std1(lp(noise(r, 1.5, 2.0), 350)) * decay(1.5, 0.35, 0.002) * 0.8
    put(x, lp(blast, 400), 0)
    put(x, osc(const(d, 3700)) * lin(d, (0, 0), (0.15, 1), (2.5, 0.7), (d, 0)), 0, 0.1)
    put(x, std1(lp(noise(r, d, 1.0), 300)) * wobble(r, d, 1, 0.5) * lin(d, (0, 0), (0.5, 1), (d, 0.6)), 0, 0.25)
    for at in (1.3, 2.4, 3.4):
        put(x, heartbeat(r), at, 0.7)
    return room(r, x, "small", 0.2)


@sfx()
def cine_war_drums(r, d):
    x = np.zeros(n(d + 2.0))
    pattern = [(0.0, 1), (0.5, 0.7), (1.0, 1), (1.25, 0), (1.5, 0.9), (2.0, 1), (2.5, 0.7),
               (2.75, 0), (2.875, 0), (3.0, 1)]
    for at, accent in pattern:
        if accent:
            put(x, drum(r, r.uniform(100, 110), 50, 0.4), at, accent)
        else:
            put(x, drum(r, 190, 110, 0.18), at, 0.55)
    return reverb(r, x, 2.5, 0.45, 4000)


@sfx()
def cine_horror_stinger(r, d):
    x = np.zeros(n(d + 1.0))
    hit = 0.02
    put(x, boom(1.5, 80, 35, 0.35, 2.2), hit, 0.9)
    put(x, nrm(burst(r, 0.05, 0.006, lo=600)), hit, 0.4)
    k = 1.6
    t = tt(k)
    bend = 1 + 0.06 * lin(k, (0, 0), (k, 1))
    cluster = sum(osc(const(k, f) * bend * (1 + 0.006 * np.sin(2 * np.pi * 11 * t + i)), "saw")
                  for i, f in enumerate((440, 466.2, 493.9, 523.3)))
    screech = nrm(sweep(cluster, "bp", 1800, 0.9) + 0.4 * lp(cluster, 1200))
    screech += std1(bp(noise(r, k), 1500, 5000)) * 0.15
    env = lin(k, (0, 0), (0.02, 1), (0.3, 0.7), (k, 0))
    put(x, screech * env * (1 + 0.3 * np.sin(2 * np.pi * 12 * t)), hit, 0.6)
    low = lp(osc(const(k, 55), "saw") + osc(const(k, 58.3), "saw"), 400)
    put(x, nrm(low) * env, hit, 0.5)
    return room(r, x, "castle", 0.45)


@sfx(peak=-3, loop=4.0)
def cine_heartbeat_loop(r, d, length):
    x = std1(lp(noise(r, d, 2.0), 120)) * wobble(r, d, 0.3, 0.3) * 0.1
    cycle = np.zeros(n(length))
    for k in range(4):
        circ_put(cycle, heartbeat(r), k * length / 4, 2.5)
    t = tt(length)
    drone = sum(g * osc(const(length, snap(f, length))) for f, g in ((55, 1), (55.5, 0.7), (82.4, 0.35)))
    drone *= 0.75 + 0.25 * np.sin(2 * np.pi * snap(0.25, length) * t)
    return room(r, x, "small", 0.1), creverb(r, cycle, 0.6, 0.2) + drone * 0.18


def clock_tick(r, high):
    d = 0.15
    x = tone(2100 if high else 1600, d, 0.012, METAL, attack=0.0003) * 0.4
    x += nrm(burst(r, d, 0.0015, lo=1500, hi=6000)) * 0.5
    x += nrm(reson(noise(r, d) * decay(d, 0.002), 900 if high else 700, 8)) * 0.5
    return x + osc(const(d, 180)) * decay(d, 0.015, 0.001) * 0.3


@sfx(peak=-3, loop=4.0)
def cine_clock_loop(r, d, length):
    cycle = np.zeros(n(length))
    for k in range(8):
        circ_put(cycle, clock_tick(r, k % 2 == 0), k * length / 8)
    t = tt(length)
    pad = sum(osc(const(length, snap(f, length)), "saw") for f in (65.4, 65.8, 77.8, 98.0, 98.5))
    pad = lp(np.tile(pad, 3), 500)[len(pad): 2 * len(pad)]
    pad = nrm(pad) * (0.6 + 0.4 * np.sin(2 * np.pi * snap(0.25, length) * t))
    bed = std1(lp(noise(r, d, 1.0), 400)) * 0.05
    return bed, creverb(r, cycle, 0.5, 0.15) + pad * 0.35


# --------------------------------------------------------------------------- ambience

@sfx(peak=-5, loop=8.0)
def amb_castle_hall(r, d, length):
    x = std1(sweep(noise(r, d, 1.0), "bp", 450 * wobble(r, d, 0.15, 0.35), 2.0)) * wobble(r, d, 0.2, 0.5) * 0.35
    x += std1(sweep(noise(r, d), "bp", 900 * wobble(r, d, 0.1, 0.1), 14)) * wobble(r, d, 0.25, 0.8) * 0.06
    x += std1(lp(noise(r, d, 2.0), 200)) * 0.35
    far = np.zeros(n(d))
    for at in events(r, d, 0.35):
        kind = r.integers(3)
        if kind == 0:
            ev = fit(wood_body(r), n(0.4)) + boom(0.4, 90, 50, 0.08) * 0.8
        elif kind == 1:
            ev = step_stone(r, 1.0)
        else:
            ev = bubble(r.uniform(900, 1600), 0.03, 1.5)
        put(far, lp(fit(ev, n(0.5)), 1500), at, r.uniform(0.1, 0.3))
    return room(r, x, "castle", 0.25) + reverb(r, far, 3.0, 1.5, 3000) * 0.5


@sfx(peak=-5, loop=8.0)
def amb_storm(r, d, length):
    x = crackle(r, d, 2500, 600, 7000, power=3) * 0.4
    x += std1(bp(noise(r, d, 1.0), 400, 6000)) * 0.25
    x += crackle(r, d, 40, 300, 3000, power=1.5) * 0.3
    x += std1(lp(noise(r, d, 2.0), 100)) * 0.3
    for at, g in ((1.2, 1.8), (5.3, 2.6)):
        put(x, thunder(r, 3.5, 160, 1.6), at + 1.0, g)
    return room(r, x, "hall", 0.1)


@sfx(peak=-5, loop=8.0)
def amb_forest_night(r, d, length):
    gust = wobble(r, d, 0.15, 0.6)
    x = std1(sweep(noise(r, d, 1.0), "bp", 700 * wobble(r, d, 0.12, 0.3), 0.8)) * gust * 0.3
    x += crackle(r, d, 300 * gust, 1500, 6000, power=3) * 0.15
    x += std1(lp(noise(r, d, 2.0), 150)) * 0.2
    put(x, lp(reverb(r, fit(owl_call(r), n(3.0)), 1.4, 0.5), 2500), 3.5, 0.25)
    cycle = np.zeros(n(length))
    for f, period, pulses, offset in ((3800, 0.5, 3, 0.0), (4300, 0.8, 4, 0.23)):
        period = length / round(length / period)
        for k in range(int(round(length / period))):
            circ_put(cycle, chirp(f, pulses), offset + k * period)
    return room(r, x, "outdoor", 0.1), creverb(r, cycle, 0.8, 0.3) * 0.06


@sfx(peak=-5, loop=8.0)
def amb_dungeon(r, d, length):
    x = std1(sweep(noise(r, d, 1.0), "bp", 260 * wobble(r, d, 0.1, 0.25), 6)) * wobble(r, d, 0.2, 0.5) * 0.25
    x += std1(lp(noise(r, d, 2.0), 100)) * 0.3
    wet = np.zeros(n(d))
    for at in events(r, d, 0.9):
        put(wet, bubble(r.uniform(900, 1800), 0.03, 1.5) + nrm(burst(r, 0.03, 0.001, lo=2000)) * 0.2, at,
            r.uniform(0.2, 0.6))
    for at in events(r, d, 0.12):
        for k in range(int(r.integers(4, 9))):
            link = tone(r.uniform(1200, 3500), 0.3, r.uniform(0.02, 0.06), METAL, attack=0.0005)
            put(wet, lp(link, 3000), at + r.uniform(0, 0.4), r.uniform(0.05, 0.15))
    x += reverb(r, wet, 2.8, 1.2, 3500)
    t = tt(length)
    drone = sum(g * osc(const(length, snap(f, length))) for f, g in ((55, 1), (55.4, 0.8), (110, 0.3)))
    drone *= 0.7 + 0.3 * np.sin(2 * np.pi * snap(0.125, length) * t)
    return x, drone * 0.15


@sfx(peak=-5, loop=8.0)
def amb_fireplace(r, d, length):
    x = roar(r, d, 500, 3, 0.35) * 0.45
    x += crackle(r, d, 14, 800, 6000, power=2) * 0.6
    x += crackle(r, d, 3, 300, 2500, power=1.2) * 0.4
    for at in events(r, d, 0.12):
        put(x, fit(wood_body(r, 0.6), n(0.5)) + crackle(r, 0.5, 200 * decay(0.5, 0.1, 0), 800, 5000), at, 0.3)
    x += std1(bp(noise(r, d), 2000, 6000)) * wobble(r, d, 4, 0.4) * 0.04
    return room(r, x, "wood", 0.15)


@sfx(peak=-5, loop=8.0)
def amb_magic(r, d, length):
    x = bells(r, d, 0.7, [74, 78, 81, 85, 86, 90], (0.6, 1.2)) * 0.15
    x += sparkles(r, d, 2.5, 2500, 7000, (0.1, 0.3)) * 0.1
    x += std1(bp(noise(r, d), 2000, 6000)) * wobble(r, d, 0.2, 0.6) * 0.03
    three = 3 * length
    t3 = tt(three)
    pad = sum(g * (osc(const(three, snap(f, length)), "saw") + osc(const(three, snap(f * 1.003, length)), "saw"))
              for f, g in ((73.4, 0.8), (146.8, 1.0), (220, 0.8), (329.6, 0.6), (415.3, 0.4)))
    cutoff = 700 + 450 * np.sin(2 * np.pi * snap(0.125, length) * t3)
    pad = sweep(pad, "lp", cutoff, 1.3)[n(length): 2 * n(length)]
    return room(r, x, "castle", 0.5), nrm(pad) * 0.25


# --------------------------------------------------------------------------- creatures

@sfx()
def dragon_roar(r, d):
    x = np.zeros(n(d + 1.2))
    k = 2.8
    f = expo(k, (0, 55), (0.25, 95), (1.2, 85), (2.2, 70), (k, 50))
    rate = 28 + 10 * std1(lp(r.standard_normal(n(k)), 3))
    growl = 1 + 0.6 * np.sin(2 * np.pi * np.cumsum(rate) / SR)
    env = lin(k, (0, 0), (0.25, 1), (1.8, 0.85), (k, 0))
    v = voice(r, f, [(550, 3, 1.0), (900, 4, 0.6), (2300, 6, 0.2)], breath=0.6, sub=0.8)
    put(x, drive(nrm(v * growl), 3.0) * env, 0, 0.8)
    put(x, std1(bp(noise(r, k, 1.0), 200, 2500)) * env * wobble(r, k, 20, 0.6), 0, 0.3)
    put(x, body(f * 0.5, env, 0.3), 0, 0.5)
    return room(r, x, "castle", 0.35)


@sfx()
def dragon_wings(r, d):
    x = np.zeros(n(d + 0.6))
    for at in (0.1, 0.75, 1.4):
        k = 0.45
        shape = lin(k, (0, 0), (0.12, 1), (k, 0))
        air = std1(sweep(noise(r, k, 1.5), "lp", expo(k, (0, 150), (0.12, 900), (k, 200)), 1.0)) * shape
        put(x, air, at)
        put(x, std1(bp(noise(r, 0.1), 250, 1800)) * decay(0.1, 0.02, 0.002), at + 0.1, 0.7)
        put(x, body(45, shape), at, 0.4)
    return room(r, x, "hall", 0.15)


@sfx()
def ghost_wail(r, d):
    k = 2.8
    t = tt(k)
    f = expo(k, (0, 480), (0.6, 640), (1.6, 560), (2.2, 700), (k, 380)) * (1 + 0.035 * np.sin(2 * np.pi * 4.2 * t))
    v = osc(f) + 0.3 * osc(f * 2) + 0.15 * osc(f * 3) + 0.4 * osc(f * 1.012)
    v = nrm(v) + 0.5 * nrm(formant(osc(f, "saw"), [(350, 5, 1.0), (800, 7, 0.4)]))
    env = lin(k, (0, 0), (0.5, 1), (2.2, 0.8), (k, 0))
    x = nrm(v) * env + std1(bp(noise(r, k), 600, 2500)) * wobble(r, k, 5, 0.7) * env * 0.15
    x += body(f / 4, env * 0.6, 0.3) * 0.25
    return room(r, echo(fit(x, n(d + 1.5)), 0.33, 0.45, 2000), "castle", 0.6)


@sfx()
def owl_hoot(r, d):
    x = fit(owl_call(r), n(d + 1.2))
    return reverb(r, x, 1.4, 0.35, 4000)


@sfx()
def wolf_howl(r, d):
    k = 3.6
    t = tt(k)
    f = expo(k, (0, 300), (0.5, 540), (2.4, 560), (3.1, 470), (k, 380)) * (1 + 0.012 * np.sin(2 * np.pi * 5 * t))
    v = osc(f) + 0.35 * osc(f * 2) + 0.12 * osc(f * 3)
    v = nrm(v) + 0.4 * nrm(formant(osc(f, "saw"), [(700, 4, 1.0), (1200, 6, 0.4)]))
    env = lin(k, (0, 0), (0.3, 1), (2.8, 0.9), (k, 0))
    x = nrm(v) * env + std1(bp(noise(r, k), 800, 3000)) * env * 0.08 + body(f / 2, env * 0.5, 0.3) * 0.2
    return reverb(r, echo(fit(x, n(d + 2.0)), 0.45, 0.3, 2500), 2.8, 0.45, 4000)


@sfx()
def bats_swarm(r, d):
    x = np.zeros(n(d + 0.5))
    for _ in range(14):
        c, w = r.uniform(0.4, 2.4), r.uniform(0.3, 0.6)
        bd = 2 * w
        tb = tt(bd)
        prox = np.sin(np.pi * tb / bd) ** 2
        flutter = (0.5 + 0.5 * np.sin(2 * np.pi * r.uniform(11, 17) * tb)) ** 4
        put(x, std1(bp(noise(r, bd), 700, 3500)) * flutter * prox, c - w, r.uniform(0.2, 0.5))
        for at in events(r, bd, 3 * prox):
            squeak = osc(expo(0.02, (0, 7500), (0.02, 5200))) * np.sin(np.pi * tt(0.02) / 0.02)
            put(x, squeak, c - w + at, 0.08 * r.uniform(0.5, 1.0))
    x += fit(std1(lp(noise(r, d, 1.0), 600)) * lin(d, (0, 0), (1.2, 1), (d, 0)), len(x)) * 0.15
    return room(r, x, "hall", 0.15)


# --------------------------------------------------------------------------- game moments

@sfx()
def boss_appears(r, d):
    x = np.zeros(n(d + 1.5))
    put(x, big_hit(r), 0, 0.9)
    env = lin(d, (0, 0), (0.02, 1), (1.5, 0.8), (d, 0))
    put(x, drive(brass([hz(m) for m in (36, 43, 48, 51)], expo(d, (0, 200), (0.1, 1800), (d, 300))), 3.0) * env, 0,
        0.55)
    put(x, choir(r, [48, 51, 55, 60], d) * lin(d, (0, 0), (0.4, 0.6), (1.6, 1), (d, 0)), 0, 0.35)
    for at in (0, 1.0, 1.5, 2.0, 2.5, 3.0):
        put(x, drum(r, 100, 48, 0.4), at, 0.8)
    t = tt(d)
    low = nrm(lp(osc(const(d, 65.4), "saw") + osc(const(d, 69.3), "saw"), 500))
    put(x, low * (0.6 + 0.4 * np.sin(2 * np.pi * 12 * t)) * env, 0, 0.2)
    return room(r, x, "castle", 0.4)


@sfx()
def victory_fanfare(r, d):
    x = np.zeros(n(d + 1.5))
    for at, midis, dur in ((0.0, [67], 0.11), (0.13, [67], 0.11), (0.26, [67], 0.11), (0.40, [72], 0.34),
                           (0.78, [76], 0.24), (1.05, [79], 0.24), (1.32, [60, 64, 67, 72, 76], 2.2)):
        put(x, horn(midis, dur), at, 0.5)
    for at in (0.40, 1.32):
        put(x, drum(r, 95, 70, 0.5), at, 0.8)
    crash = std1(hp(noise(r, 2.5), 3000)) * decay(2.5, 0.5, 0.003) * 0.22 + tone(420, 2.5, 0.8, METAL) * 0.1
    put(x, crash, 1.32)
    put(x, body(65.4, lin(2.5, (0, 0), (0.03, 1), (2.2, 0.7), (2.5, 0))), 1.32, 0.4)
    put(x, sparkles(r, 1.6, lin(1.6, (0, 40), (1.6, 0)), 3000, 9000), 1.35, 0.2)
    return room(r, x, "hall", 0.35)


@sfx()
def game_over(r, d):
    x = np.zeros(n(d + 1.5))
    for at, m, dur in ((0.0, 67, 0.4), (0.45, 63, 0.4), (0.9, 60, 0.4), (1.35, 55, 1.4)):
        put(x, horn([m, m - 12], dur, 0.4), at, 0.5)
    put(x, boom(1.2, 70, 35, 0.3, 1.8), 1.35, 0.7)
    put(x, body(49, lin(1.6, (0, 0), (0.1, 1), (1.6, 0))), 1.35, 0.4)
    put(x, std1(lp(noise(r, 1.6, 2.0), 120)) * lin(1.6, (0, 0), (0.2, 1), (1.6, 0)), 1.35, 0.4)
    x = sweep(x, "lp", expo(len(x) / SR, (0, 4000), (1.5, 2500), (d, 300), (len(x) / SR, 300)), 0.7)
    return room(r, x, "castle", 0.35)


@sfx()
def secret_found(r, d):
    x = np.zeros(n(d + 1.2))
    for i, m in enumerate((79, 83, 86, 90, 91, 95)):
        put(x, tone(hz(m), 1.2, 0.5, GLOCK), i * 0.09, 0.5)
    for m in (79, 86, 91):
        put(x, tone(hz(m), 1.8, 1.0, CHIME, attack=0.01), 0.6, 0.3)
    put(x, sparkles(r, 1.2, lin(1.2, (0, 10), (0.6, 60), (1.2, 0)), 3000, 9000, rise=0.5), 0.2, 0.25)
    put(x, body(98, lin(1.8, (0, 0), (0.1, 1), (1.8, 0))), 0.6, 0.25)
    return room(r, x, "hall", 0.3)


@sfx()
def level_up(r, d):
    x = np.zeros(n(d + 1.2))
    k = 0.6
    put(x, whoosh(r, k, expo(k, (0, 300), (k, 3000)), lin(k, (0, 0), (k, 1)), q=1.5), 0, 0.4)
    put(x, osc(expo(k, (0, 220), (k, 880))) * lin(k, (0, 0), (k, 1)), 0, 0.12)
    for i, m in enumerate((60, 64, 67, 72)):
        put(x, tone(hz(m + 12), 0.8, 0.3, CHIME), 0.1 + i * 0.1, 0.35)
    put(x, horn([48, 60, 64, 67, 72], 0.9), 0.62, 0.55)
    put(x, drum(r, 95, 70, 0.4), 0.62, 0.7)
    put(x, body(65.4, lin(1.2, (0, 0), (0.03, 1), (1.2, 0))), 0.62, 0.35)
    put(x, sparkles(r, 1.4, lin(1.4, (0, 60), (1.4, 0)), 3000, 9000, rise=0.5), 0.6, 0.25)
    return room(r, x, "hall", 0.3)


@sfx()
def chapter_title(r, d):
    x = np.zeros(n(d + 1.5))
    hit = 0.8
    put(x, reverse_crash(r, hit), 0, 0.7)
    put(x, big_hit(r), hit, 0.8)
    for m in (62, 69, 74, 78):
        put(x, tone(hz(m), 2.5, 1.2, CHIME, attack=0.005), hit, 0.25)
    k = d - hit
    put(x, choir(r, [50, 57, 62, 66], k) * lin(k, (0, 0), (0.3, 1), (k, 0)), hit, 0.25)
    put(x, sparkles(r, k, lin(k, (0, 50), (k, 0)), 3000, 9000), hit, 0.2)
    return room(r, x, "castle", 0.45)


# --------------------------------------------------------------------------- rendering

def render(sid, duration=None):
    """Render one sound to a float array at SR, peak-normalized."""
    recipe = RECIPES[sid]
    r = np.random.default_rng(zlib.crc32(sid.encode()))
    loop = recipe["loop"]
    if loop:
        pre, xfade = 1.0, min(1.0, loop / 4)
        out = recipe["fn"](r, pre + loop + xfade, loop)
        x, periodic = out if isinstance(out, tuple) else (out, None)
        x = master(hp(x, 25))[n(pre):]
        body, fold = x[: n(loop)].copy(), x[n(loop): n(loop) + n(xfade)]
        w = np.linspace(0, np.pi / 2, len(fold))
        body[: len(fold)] = body[: len(fold)] * np.sin(w) + fold * np.cos(w)
        if periodic is not None:
            cycle = fit(periodic, len(body))
            body_ = master(np.tile(cycle, 3))[len(cycle): 2 * len(cycle)]
            body += body_
        x = body
    else:
        x = master(hp(fit(recipe["fn"](r, duration), n(duration)), 25))
        x[: n(0.001)] *= np.linspace(0, 1, n(0.001))
        fade = n(min(0.06, duration * 0.1))
        x[-fade:] *= np.linspace(1, 0, fade) ** 2
    return nrm(x) * 10 ** (recipe["peak"] / 20)


def write_mp3(path, x, bitrate=128):
    import lameenc

    enc = lameenc.Encoder()
    enc.set_bit_rate(bitrate)
    enc.set_in_sample_rate(SR)
    enc.set_channels(1)
    enc.set_quality(2)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(enc.encode(pcm) + enc.flush())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("only", nargs="*", help="category ids and/or sound ids to render (default: all)")
    parser.add_argument("--force", action="store_true", help="overwrite files that already exist")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    sounds = [(c["id"], s) for c in manifest["categories"] for s in c["sounds"]]
    known = {c for c, _ in sounds} | {s["id"] for _, s in sounds}
    unknown = [name for name in args.only if name not in known]
    if unknown:
        parser.error(f"unknown id(s): {', '.join(unknown)}")
    if args.only:
        sounds = [(c, s) for c, s in sounds if c in args.only or s["id"] in args.only]

    done = skipped = missing = 0
    for category, sound in sounds:
        target = OUT_DIR / category / f"{sound['id']}.mp3"
        if sound["id"] not in RECIPES:
            print(f"!! no recipe for {sound['id']} yet, skipped")
            missing += 1
            continue
        if target.exists() and not args.force:
            skipped += 1
            continue
        write_mp3(target, render(sound["id"], sound.get("duration")))
        print(f"-> {target.relative_to(ROOT)}")
        done += 1
    print(f"\n{done} rendered, {skipped} already present, {missing} without recipe")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
