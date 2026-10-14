"""Original deterministic sounds and music for QALAM, CC0. Pure synthesis."""
import math, pathlib, random, struct, wave

OUT = pathlib.Path(__file__).resolve().parents[1] / 'assets/audio'
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050


def write(name, samples):
    peak = max(1e-6, max(abs(x) for x in samples))
    gain = min(1.0, 0.85 / peak)
    with wave.open(str(OUT / (name + '.wav')), 'wb') as w:
        w.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(b''.join(struct.pack('<h', int(32767 * max(-1, min(1, x * gain)))) for x in samples))


def render(seconds, fn):
    n = int(RATE * seconds)
    return [fn(i / RATE, i / n) for i in range(n)]


def lowpass(xs, k):
    out, y = [], 0.0
    for x in xs:
        y += k * (x - y)
        out.append(y)
    return out


def noise(seed, n):
    r = random.Random(seed)
    return [r.uniform(-1, 1) for _ in range(n)]


def note(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def pluck(f, t, decay=6.0):
    return (math.sin(math.tau * f * t) + 0.3 * math.sin(math.tau * 2 * f * t) + 0.1 * math.sin(math.tau * 3 * f * t)) * math.exp(-t * decay)


# --- cues -------------------------------------------------------------------------
# Pencil scribble loop: band-limited noise with stroke-rate wobble (seamless 1 s).
nz = noise('scribble', RATE)
hp = [nz[i] - nz[i - 1] for i in range(len(nz))]
write('scribble', [hp[i] * 0.4 * (0.55 + 0.45 * abs(math.sin(math.tau * 6 * i / RATE))) for i in range(len(hp))])

write('jump', render(0.22, lambda t, u: math.sin(math.tau * (320 + 520 * u) * t) * (1 - u) ** 1.5 * 0.6))
nz = noise('land', int(RATE * 0.12))
write('land', [nz[i] * 0.5 * math.exp(-i / RATE * 40) + math.sin(math.tau * 110 * i / RATE) * 0.5 * math.exp(-i / RATE * 30) for i in range(len(nz))])
nz = noise('step', int(RATE * 0.05))
write('step', [nz[i] * 0.4 * math.exp(-i / RATE * 90) for i in range(len(nz))])
nz = lowpass(noise('poof', int(RATE * 0.5)), 0.25)
write('poof', [nz[i] * math.sin(math.pi * min(1, i / (RATE * 0.03))) * math.exp(-i / RATE * 7) for i in range(len(nz))])
write('pop', render(0.12, lambda t, u: math.sin(math.tau * (700 - 400 * u) * t) * (1 - u) ** 2))
nz = noise('paper', int(RATE * 0.2))
write('paper_pop', [nz[i] * 0.5 * math.exp(-i / RATE * 25) + pluck(520, i / RATE, 18) * 0.4 for i in range(len(nz))])
nz = noise('crumple', int(RATE * 0.3))
r = random.Random('cr')
env = [1.0 if r.random() < 0.08 else 0.0 for _ in nz]
env = lowpass(env, 0.02)
write('crumple', [nz[i] * env[i] * 6.0 * (1 - i / len(nz)) for i in range(len(nz))])
write('bump', render(0.15, lambda t, u: math.sin(math.tau * 140 * t) * math.exp(-t * 30)))
nz = lowpass(noise('book', int(RATE * 0.9)), 0.12)
write('book_open', [nz[i] * math.sin(math.pi * i / len(nz)) ** 2 * 1.4 + math.sin(math.tau * 80 * i / RATE) * 0.3 * math.exp(-max(0, i / RATE - 0.75) * 30) * (i / RATE > 0.75) for i in range(len(nz))])
write('plank', render(0.6, lambda t, u: sum(pluck(f, max(0, t - d), 14) * (t >= d) for f, d in [(392, 0), (494, 0.06), (587, 0.12), (784, 0.18)]) * 0.5))
nz = noise('erase', int(RATE * 0.45))
hp = [nz[i] - nz[i - 1] for i in range(len(nz))]
write('erase', [hp[i] * 0.4 * abs(math.sin(math.tau * 9 * i / RATE)) * (1 - i / len(hp)) for i in range(len(hp))])
write('plate', render(0.5, lambda t, u: math.sin(math.tau * 90 * t) * math.exp(-t * 25) + pluck(1046, t, 5) * 0.5))
nz = lowpass(noise('gate', int(RATE * 1.6)), 0.05)
write('gate', [nz[i] * 2.0 * math.exp(-i / RATE * 3) + sum(pluck(note(n), max(0, i / RATE - d), 3) * (i / RATE >= d) for n, d in [(72, 0.5), (76, 0.65), (79, 0.8), (84, 0.95)]) * 0.4 for i in range(len(nz))])
write('win', render(2.2, lambda t, u: sum(pluck(note(n), max(0, t - d), 2.2) * (t >= d) for n, d in [(67, 0), (72, 0.15), (76, 0.3), (79, 0.45), (84, 0.7), (88, 0.85), (91, 1.0)]) * 0.35))


# --- stage one cues ---------------------------------------------------------------------
nz = lowpass(noise('rumble', int(RATE * 1.4)), 0.03)
write('rumble', [nz[i] * 3.0 * math.sin(math.pi * i / len(nz)) * (0.6 + 0.4 * math.sin(math.tau * 9 * i / RATE)) for i in range(len(nz))])
nz = lowpass(noise('dust', int(RATE * 1.2)), 0.08)
write('dust', [nz[i] * 1.6 * math.sin(math.pi * min(1, i / (RATE * 0.1))) * math.exp(-i / RATE * 2.5) for i in range(len(nz))])
nz = noise('emerge', int(RATE * 1.0))
hp = [nz[i] - nz[i - 1] for i in range(len(nz))]
write('emerge', [hp[i] * 0.3 * abs(math.sin(math.tau * 5 * i / RATE)) * min(1, i / (RATE * 0.2)) + pluck(note(64 + 5 * int(i / RATE * 4)), (i / RATE) % 0.25, 8) * 0.15 for i in range(len(nz))])
nz = noise('scrin', int(RATE * 0.5))
hp = [nz[i] - nz[i - 1] for i in range(len(nz))]
write('scribble_in', [hp[i] * 0.45 * abs(math.sin(math.tau * 14 * i / RATE)) * (i / len(hp)) for i in range(len(hp))])
nz = noise('line', int(RATE * 0.45))
hp = [nz[i] - nz[i - 1] for i in range(len(nz))]
write('pencil_line', [hp[i] * 0.25 * (1 - i / len(hp)) + pluck(note(67), i / RATE, 6) * 0.35 + pluck(note(74), max(0, i / RATE - 0.08), 6) * 0.3 * (i / RATE > 0.08) for i in range(len(hp))])
nz = noise('crumble', int(RATE * 0.5))
r = random.Random('crb')
env = lowpass([1.0 if r.random() < 0.05 else 0.0 for _ in nz], 0.03)
write('crumble', [nz[i] * env[i] * 7.0 * (1 - i / len(nz)) for i in range(len(nz))])
nz = noise('rub', RATE)
hp = lowpass([nz[i] - nz[i - 1] for i in range(len(nz))], 0.5)
write('rub', [hp[i] * 0.8 * (0.5 + 0.5 * abs(math.sin(math.tau * 7 * i / RATE))) for i in range(len(hp))])
write('dry', render(0.25, lambda t, u: math.sin(math.tau * (300 - 120 * u) * t) * (1 - u) * 0.4 + random.Random(int(t * 9000)).uniform(-0.1, 0.1) * (1 - u)))
write('wobble', render(0.5, lambda t, u: math.sin(math.tau * 180 * t + 4 * math.sin(math.tau * 9 * t)) * (1 - u) ** 2 * 0.5))
write('drop', render(0.7, lambda t, u: (pluck(note(84), t, 5) + pluck(note(91), max(0, t - 0.07), 5) * (t > 0.07)) * 0.5))
write('absorb', render(0.6, lambda t, u: math.sin(math.tau * (400 + 600 * u) * t) * math.sin(math.pi * u) * 0.35))
write('bloom', render(1.4, lambda t, u: sum(pluck(note(n), max(0, t - d), 3) * (t >= d) for n, d in [(72, 0), (76, 0.1), (79, 0.2), (83, 0.3), (84, 0.45)]) * 0.4))
nz = noise('click', int(RATE * 0.3))
write('click', [nz[i] * 0.6 * math.exp(-i / RATE * 120) + math.sin(math.tau * 220 * i / RATE) * 0.4 * math.exp(-i / RATE * 20) for i in range(len(nz))])
write('orb', render(2.0, lambda t, u: sum(pluck(note(n), t, 1.2) for n in (67, 71, 74, 79)) * 0.2 * min(1, t * 5)))
write('restore', render(3.0, lambda t, u: sum(math.sin(math.tau * note(n) * t) * math.sin(math.pi * u) for n in (60, 64, 67, 72, 76)) * 0.12 + sum(pluck(note(n), max(0, t - d), 2.5) * (t >= d) for n, d in [(79, 0.4), (84, 0.9), (88, 1.4), (91, 1.9)]) * 0.25))
nz = lowpass(noise('wind', int(RATE * 2.5)), 0.06)
write('wind', [nz[i] * 2.4 * math.sin(math.pi * i / len(nz)) * (0.7 + 0.3 * math.sin(math.tau * 0.8 * i / RATE)) for i in range(len(nz))])
nz = lowpass(noise('flip', int(RATE * 0.8)), 0.2)
write('page_flip', [nz[i] * 1.5 * math.sin(math.pi * i / len(nz)) ** 0.5 * (1.0 + 0.5 * math.sin(math.tau * 3 * i / RATE)) for i in range(len(nz))])


# --- music: soft music-box loops ----------------------------------------------------
def music(name, bpm, chords, melody, seed, warm):
    beat = 60.0 / bpm
    bars = len(chords)
    total = int(RATE * beat * 4 * bars)
    buf = [0.0] * total

    def add(start, length, fn):
        a = int(start * RATE)
        for i in range(int(length * RATE)):
            j = (a + i) % total
            buf[j] += fn(i / RATE)

    for bar, root in enumerate(chords):
        t0 = bar * 4 * beat
        triad = [root, root + (3 if root in (57, 62, 64) else 4), root + 7]
        for k, n in enumerate([triad[0] - 12, triad[1], triad[2], triad[1]] * 2):
            add(t0 + k * beat / 2, beat * 2, lambda t, f=note(n): pluck(f, t, 3.0) * 0.18)
        add(t0, beat * 4, lambda t, f=note(root - 24): math.sin(math.tau * f * t) * 0.12 * min(1, t * 4) * math.exp(-t * 0.6) * warm)
    for k, n in enumerate(melody):
        if n:
            add(k * beat, beat * 2, lambda t, f=note(n): (math.sin(math.tau * f * t) + 0.25 * math.sin(math.tau * 4 * f * t)) * math.exp(-t * 3.5) * 0.22)
    write(name, buf)


music('music_calm', 84, [60, 57, 53, 55], [72, 0, 76, 0, 79, 0, 76, 74, 72, 0, 69, 0, 72, 0, 0, 0, 77, 0, 76, 0, 74, 0, 72, 0, 74, 0, 76, 0, 74, 0, 0, 0], 'calm', 1.0)
music('music_bright', 104, [60, 65, 67, 60], [72, 76, 79, 84, 83, 79, 76, 79, 77, 81, 84, 81, 79, 77, 76, 74, 74, 79, 83, 86, 84, 83, 79, 77, 76, 79, 84, 79, 72, 0, 0, 0], 'bright', 0.6)
print('QALAM audio written to', OUT)
