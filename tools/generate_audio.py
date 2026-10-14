"""Original sound and music for QALAM, CC0. Pure synthesis (numpy/scipy), no samples.

Design goals after play feedback ("the music is annoying"):
- music is slow, sparse and soft: warm pads, felt piano, a hint of music box,
  long reverb, nothing shrill, long loops (~70 s) so repetition is not noticed;
- effects are short, rounded (no hard clicks), low-passed and quiet.
Music is written as OGG Vorbis (ffmpeg), effects as 22 kHz mono WAV.
"""
import pathlib, subprocess, wave
import numpy as np
from scipy import signal

OUT = pathlib.Path(__file__).resolve().parents[1] / 'assets/audio'
OUT.mkdir(parents=True, exist_ok=True)
SR = 22050
MSR = 32000


def note(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def t_axis(seconds, sr=SR):
    return np.arange(int(seconds * sr)) / sr


def lowpass(x, hz, sr=SR, order=2):
    sos = signal.butter(order, hz, 'low', fs=sr, output='sos')
    return signal.sosfilt(sos, x)


def highpass(x, hz, sr=SR, order=2):
    sos = signal.butter(order, hz, 'high', fs=sr, output='sos')
    return signal.sosfilt(sos, x)


def bandpass(x, lo, hi, sr=SR, order=2):
    sos = signal.butter(order, [lo, hi], 'band', fs=sr, output='sos')
    return signal.sosfilt(sos, x)


def noise(n, seed):
    return np.random.default_rng(abs(hash(seed)) % (2 ** 32)).uniform(-1, 1, n)


def fade(x, a=0.004, r=0.02, sr=SR):
    n = len(x)
    env = np.ones(n)
    na, nr = max(1, int(a * sr)), max(1, int(r * sr))
    env[:na] = np.linspace(0, 1, na) ** 2
    env[-nr:] *= np.linspace(1, 0, nr) ** 2
    return x * env


def reverb(x, seconds=1.6, wet=0.25, sr=SR, seed='rv', loop=False, tone=3500):
    n = int(seconds * sr)
    tt = np.arange(n) / sr
    ir = noise(n, seed) * np.exp(-tt * 6.9 / seconds)
    ir = lowpass(ir, tone, sr)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    y = signal.fftconvolve(x, ir)
    if loop:
        tail = y[len(x):]
        y = y[:len(x)].copy()
        y[:len(tail)] += tail  # wrap the tail so the loop is seamless
    else:
        y = np.pad(y, (0, 1))[:len(x) + n]
        x = np.concatenate([x, np.zeros(n)])
    return x * (1 - wet) + y * wet


def write_wav(name, x, sr=SR, peak=0.7):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) + 1e-9
    x = x / m * peak
    data = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
    with wave.open(str(OUT / (name + '.wav')), 'wb') as w:
        w.setparams((1, 2, sr, 0, 'NONE', 'not compressed'))
        w.writeframes(data)


def write_ogg(name, x, sr=MSR, peak=0.5):
    tmp = OUT / (name + '.tmp.wav')
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    data = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
    with wave.open(str(tmp), 'wb') as w:
        w.setparams((1, 2, sr, 0, 'NONE', 'not compressed'))
        w.writeframes(data)
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', str(tmp), '-c:a', 'libvorbis', '-q:a', '4', str(OUT / (name + '.ogg'))], check=True)
    tmp.unlink()


# --- instruments ----------------------------------------------------------------------

def felt_piano(f, seconds, vel, sr):
    tt = t_axis(seconds, sr)
    out = np.zeros_like(tt)
    for h, (amp, dec) in enumerate([(1.0, 1.6), (0.32, 2.6), (0.12, 4.0), (0.05, 6.0)], start=1):
        detune = 1.0 + (h - 1) * 0.0007
        out += amp * np.sin(2 * np.pi * f * h * detune * tt) * np.exp(-tt * dec * (0.6 + f / 900.0))
    att = np.clip(tt / 0.012, 0, 1)
    out *= att * vel
    # Felt hammer: a soft low thump.
    thump = lowpass(noise(len(tt), f), 400, sr) * np.exp(-tt * 40) * 0.25 * vel
    return lowpass(out + thump, 3200, sr)


def music_box(f, seconds, vel, sr):
    tt = t_axis(seconds, sr)
    tone = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 2.2) + 0.25 * np.sin(2 * np.pi * f * 4.07 * tt) * np.exp(-tt * 7)
    return lowpass(tone * np.clip(tt / 0.004, 0, 1) * vel, 4500, sr)


def pad(freqs, seconds, vel, sr, attack=2.5, release=2.5):
    tt = t_axis(seconds, sr)
    out = np.zeros_like(tt)
    for f in freqs:
        for det in (-0.004, 0.0, 0.0045):
            ff = f * (1 + det)
            for h in range(1, 5):
                out += np.sin(2 * np.pi * ff * h * tt + h * 0.7) / (h * h)
    out *= (1 + 0.15 * np.sin(2 * np.pi * 0.17 * tt))
    env = np.minimum(np.clip(tt / attack, 0, 1), np.clip((seconds - tt) / release, 0, 1))
    return lowpass(out * env * vel / len(freqs), 1400, sr)


def render_track(chords, chord_len, melody_density, seed, bright=False):
    sr = MSR
    total = int(len(chords) * chord_len * sr)
    buf = np.zeros(total)
    rng = np.random.default_rng(seed)

    def add(start, x):
        a = int(start * sr) % total
        end = a + len(x)
        if end <= total:
            buf[a:end] += x
        else:
            k = total - a
            buf[a:] += x[:k]
            buf[:end - total] += x[k:]

    for i, chord in enumerate(chords):
        t0 = i * chord_len
        add(t0 - 1.0, pad([note(n) for n in chord], chord_len + 2.0, 0.55, sr))
        add(t0, felt_piano(note(chord[0] - 12), 5.0, 0.35, sr))
        # Sparse melody from chord tones (and a gentle passing note).
        tones = sorted({n + 12 for n in chord} | {n + 24 for n in chord[:2]})
        tones = [n for n in tones if 62 <= n <= 81]
        t = t0 + rng.uniform(0.3, 1.0)
        while t < t0 + chord_len - 0.6:
            n = int(rng.choice(tones))
            add(t, felt_piano(note(n), 3.5, rng.uniform(0.22, 0.4), sr))
            if bright and rng.random() < 0.5:
                add(t + 0.02, music_box(note(n + 12), 2.0, 0.12, sr))
            t += rng.uniform(1.0, 2.2) / melody_density
    mix = reverb(buf, seconds=3.2, wet=0.38, sr=sr, seed=seed, loop=True, tone=2800)
    return lowpass(mix, 7000, sr)


# --- music ---------------------------------------------------------------------------------
F = [53, 57, 60, 64]; C = [48, 55, 60, 64]; Am = [45, 52, 57, 60]; G = [43, 50, 55, 59]
Dm = [50, 53, 57, 64]; Em = [52, 55, 59, 62]
write_ogg('music_calm', render_track([F, C, Am, G, F, C, Dm, G, Am, Em, F, G], 6.0, 0.8, 11))
write_ogg('music_bright', render_track([C, G, Am, F, C, G, F, C], 4.5, 1.6, 23, bright=True), peak=0.55)


# --- effects ---------------------------------------------------------------------------------

def scribble_loop():
    n = SR * 2
    tt = np.arange(n) / SR
    grain = bandpass(noise(n, 'scr'), 1800, 6000)
    strokes = 0.55 + 0.45 * np.abs(np.sin(2 * np.pi * 2.5 * tt) * np.sin(2 * np.pi * 0.9 * tt + 1.0))
    crackle = (noise(n, 'crk') > 0.985) * noise(n, 'crk2')
    x = grain * strokes + lowpass(crackle, 5000) * 0.6
    return x


def rub_loop():
    n = SR * 2
    tt = np.arange(n) / SR
    x = bandpass(noise(n, 'rub'), 250, 1800) * (0.4 + 0.6 * np.abs(np.sin(2 * np.pi * 1.6 * tt)))
    return x


def tick(f, seconds, dec, vel=1.0):
    tt = t_axis(seconds)
    return np.sin(2 * np.pi * f * tt) * np.exp(-tt * dec) * np.clip(tt / 0.003, 0, 1) * vel


def burst(seconds, seed, lo, hi, dec, attack=0.003):
    tt = t_axis(seconds)
    return bandpass(noise(len(tt), seed), lo, hi) * np.exp(-tt * dec) * np.clip(tt / attack, 0, 1)


def chime(notes, gap, seconds, vel=0.6, box=True):
    out = np.zeros(int(seconds * SR))
    for k, n in enumerate(notes):
        x = (music_box(note(n), seconds, vel, SR) if box else felt_piano(note(n), seconds, vel, SR))
        a = int(k * gap * SR)
        out[a:] += x[:len(out) - a]
    return out


def swell_noise(seconds, seed, lo, hi):
    tt = t_axis(seconds)
    return bandpass(noise(len(tt), seed), lo, hi) * np.sin(np.pi * tt / seconds) ** 1.5


def creak(seconds, seed):
    tt = t_axis(seconds)
    f = 95 + 25 * np.sin(2 * np.pi * 1.3 * tt) + 8 * noise(len(tt), seed + 'j').cumsum() / len(tt) * 40
    phase = 2 * np.pi * np.cumsum(f) / SR
    saw = signal.sawtooth(phase) * (0.5 + 0.5 * (noise(len(tt), seed) > 0.2))
    return lowpass(saw, 1200) * np.sin(np.pi * tt / seconds) * 0.6


def mix(*xs):
    n = max(len(x) for x in xs)
    out = np.zeros(n)
    for x in xs:
        out[:len(x)] += x
    return out


fx = {
    'scribble': (scribble_loop(), 0.35, False),
    'rub': (rub_loop(), 0.35, False),
    'step': (burst(0.06, 'step', 300, 2500, 90), 0.25, False),
    'jump': (mix(tick(330, 0.18, 14), 0.5 * tick(495, 0.18, 16)), 0.35, True),
    'land': (mix(burst(0.12, 'land', 120, 1500, 35), tick(110, 0.12, 30, 0.6)), 0.4, False),
    'poof': (lowpass(burst(0.5, 'poof', 200, 3000, 7, 0.02), 2500), 0.45, True),
    'pop': (mix(tick(620, 0.12, 30), tick(930, 0.1, 40, 0.4)), 0.35, False),
    'paper_pop': (mix(burst(0.15, 'pp', 600, 4000, 30) * 0.6, tick(520, 0.15, 25, 0.5)), 0.3, False),
    'crumple': (mix(*[np.pad(burst(0.05, 'c%d' % k, 800, 5000, 80), (int(k * 0.035 * SR), 0)) for k in range(8)]), 0.35, False),
    'bump': (mix(tick(140, 0.15, 30), burst(0.08, 'bump', 100, 900, 40) * 0.5), 0.4, False),
    'book_open': (mix(swell_noise(1.2, 'book', 150, 2200), np.pad(creak(0.6, 'bk'), (int(0.2 * SR), 0)) * 0.5), 0.55, True),
    'pencil_line': (mix(scribble_loop()[:int(0.25 * SR)] * np.linspace(1, 0, int(0.25 * SR)) * 0.5, chime([67, 74], 0.09, 0.8, 0.5)), 0.45, True),
    'erase': (mix(rub_loop()[:int(0.4 * SR)] * np.linspace(1, 0, int(0.4 * SR)), chime([72], 0, 0.4, 0.2)), 0.4, True),
    'crumble': (mix(*[np.pad(burst(0.06, 'cb%d' % k, 1500, 6000, 70), (int(k * 0.05 * SR), 0)) for k in range(10)]), 0.3, False),
    'dry': (bandpass(noise(int(0.25 * SR), 'dry'), 2000, 5000) * np.linspace(1, 0, int(0.25 * SR)) ** 2 * 0.6, 0.25, False),
    'wobble': (np.sin(2 * np.pi * 160 * t_axis(0.5) + 3 * np.sin(2 * np.pi * 7 * t_axis(0.5))) * np.exp(-t_axis(0.5) * 6), 0.3, False),
    'drop': (chime([84, 91], 0.07, 1.2, 0.6), 0.45, True),
    'absorb': (chime([76, 79, 83, 88], 0.06, 1.0, 0.4), 0.4, True),
    'bloom': (chime([72, 76, 79, 83, 84], 0.11, 1.8, 0.45, box=False), 0.5, True),
    'click': (mix(tick(900, 0.05, 120), tick(180, 0.2, 25, 0.6)), 0.4, False),
    'gate': (mix(creak(1.4, 'gate'), np.pad(chime([60, 67, 72, 76], 0.15, 1.2, 0.35, box=False), (int(0.5 * SR), 0))), 0.55, True),
    'orb': (chime([67, 71, 74, 79, 83], 0.12, 2.2, 0.4, box=False), 0.5, True),
    'restore': (chime([60, 64, 67, 72, 76, 79, 84], 0.28, 3.0, 0.4, box=False), 0.55, True),
    'wind': (swell_noise(3.0, 'wind', 150, 1200) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.7 * t_axis(3.0))), 0.45, True),
    'page_flip': (swell_noise(0.7, 'flip', 400, 4000) * (1 + 0.6 * np.sin(2 * np.pi * 9 * t_axis(0.7))), 0.45, True),
    'rumble': (lowpass(noise(int(1.4 * SR), 'rumble'), 160) * np.sin(np.pi * t_axis(1.4) / 1.4) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t_axis(1.4))), 0.5, False),
    'dust': (swell_noise(1.2, 'dust', 300, 3000) * np.exp(-t_axis(1.2) * 1.5), 0.4, True),
    'emerge': (mix(swell_noise(1.0, 'em', 600, 4000) * 0.6, chime([64, 69, 71], 0.25, 1.0, 0.25)), 0.4, True),
    'scribble_in': (mix(scribble_loop()[:int(0.5 * SR)] * np.linspace(0.2, 1, int(0.5 * SR)), np.pad(chime([72], 0, 0.3, 0.3), (int(0.45 * SR), 0))), 0.35, False),
}
for name, (x, peak, wet) in fx.items():
    x = np.asarray(x, dtype=np.float64)
    if name not in ('scribble', 'rub'):  # loops must not fade at their ends
        x = fade(x)
    if wet:
        x = reverb(x, seconds=1.2, wet=0.22, seed=name, tone=4000)
    write_wav(name, lowpass(x, 7500), peak=peak)
print('QALAM audio written:', len(fx), 'effects + 2 music loops')
