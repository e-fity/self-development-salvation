"""生成占位音效（16-bit 单声道 44.1kHz WAV）。

不是最终音色，只是让每个动作先「有声音」，方便调手感与音量配比。
换正式素材时保持同名覆盖即可，代码不用改。
用法：python tools/assets/make_sfx.py
"""
import math
import os
import wave

import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(HERE, "game", "audio", "sfx")
BGM = os.path.join(HERE, "game", "audio", "bgm")


def t(dur):
    return np.linspace(0.0, dur, int(SR * dur), endpoint=False)


def env_exp(n, attack=0.004, decay=8.0):
    a = max(1, int(SR * attack))
    e = np.ones(n)
    e[:a] = np.linspace(0.0, 1.0, a)
    e[a:] = np.exp(-decay * np.linspace(0.0, 1.0, n - a))
    return e


def sine(freq, dur, phase=0.0):
    return np.sin(2 * math.pi * freq * t(dur) + phase)


def sweep(f0, f1, dur, kind="sine"):
    n = int(SR * dur)
    freqs = np.linspace(f0, f1, n)
    phase = np.cumsum(2 * math.pi * freqs / SR)
    if kind == "saw":
        return 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0
    if kind == "square":
        return np.sign(np.sin(phase))
    return np.sin(phase)


def noise(dur, seed=0):
    rng = np.random.default_rng(seed)
    return rng.uniform(-1.0, 1.0, int(SR * dur))


def lowpass(x, cutoff):
    a = math.exp(-2 * math.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def whoosh(dur, lo, hi, seed=1, curve=1.0):
    n = int(SR * dur)
    base = highpass(lowpass(noise(dur, seed), hi), lo)
    shape = np.sin(np.pi * np.linspace(0.0, 1.0, n)) ** curve
    return base * shape


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def place(dest, src):
    out = np.zeros(len(dest))
    out[: min(len(dest), len(src))] += src[: len(dest)]
    return out


def normalize(x, peak=0.85):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def save(name, x, fade_out=0.01):
    x = normalize(np.asarray(x, dtype=np.float64))
    n = len(x)
    f = min(n, int(SR * fade_out))
    if f > 0:
        x[-f:] *= np.linspace(1.0, 0.0, f)
    write_wav(os.path.join(OUT, name + ".wav"), x)
    print("%-14s %5.0f ms" % (name, 1000.0 * n / SR))


def write_wav(path, x):
    data = np.clip(np.asarray(x) * 32767.0, -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def ping(f, dur, decay=14.0):
    return sine(f, dur) * env_exp(len(t(dur)), 0.001, decay)


os.makedirs(OUT, exist_ok=True)
os.makedirs(BGM, exist_ok=True)

# ---- 打击 ----
d = 0.09
save("hit_light",
     mix(sine(220, d) * np.linspace(1, 0.15, len(t(d))) ** 2 * env_exp(len(t(d)), 0.001, 22),
         place(np.zeros(len(t(d))), noise(0.012, 3)) * 0.5))

d = 0.12
save("hit_mid",
     mix(sweep(170, 95, d) * env_exp(len(t(d)), 0.001, 16),
         place(noise(0.02, 4), np.zeros(len(t(d)))) * 0.45))

d = 0.18
save("hit_heavy",
     mix(sweep(120, 55, d, "saw") * env_exp(len(t(d)), 0.001, 11),
         place(noise(0.03, 5), np.zeros(len(t(d)))) * 0.55))

save("hit_player",
     mix(sweep(200, 110, 0.14, "square") * env_exp(len(t(0.14)), 0.001, 14),
         place(noise(0.02, 6), np.zeros(len(t(0.14)))) * 0.4))

# ---- 挥空 ----
save("swing_light", whoosh(0.1, 900, 4200, seed=7))
save("swing_heavy", whoosh(0.15, 500, 2400, seed=8, curve=1.4))

# ---- 位移 ----
save("dash", whoosh(0.22, 300, 5200, seed=9, curve=0.6) * np.linspace(0.3, 1.0, len(t(0.22))))
save("dodge", whoosh(0.14, 400, 3000, seed=10, curve=1.2) * 0.8)

# ---- 跳跃 / 落地 ----
save("jump", sweep(300, 640, 0.1) * env_exp(len(t(0.1)), 0.002, 18) * 0.8)
save("land", mix(sweep(120, 70, 0.11) * env_exp(len(t(0.11)), 0.001, 20),
                 place(noise(0.02, 11), np.zeros(len(t(0.11)))) * 0.35))

# ---- 受伤 / 死亡 ----
save("hurt", mix(sweep(260, 150, 0.16, "square") * env_exp(len(t(0.16)), 0.001, 10) * 0.7,
                 place(noise(0.02, 12), np.zeros(len(t(0.16)))) * 0.3))
save("die", mix(sweep(300, 70, 0.5, "saw") * env_exp(len(t(0.5)), 0.003, 5),
                place(noise(0.08, 13), np.zeros(len(t(0.5)))) * 0.35))
save("enemy_die", sweep(380, 90, 0.3, "square") * env_exp(len(t(0.3)), 0.002, 8) * 0.75)

# ---- Boss ----
d = 0.75
n = len(t(d))
vib = np.sin(2 * math.pi * 5.0 * t(d)) * 12.0
ph = np.cumsum(2 * math.pi * (62.0 + vib) / SR)
roar = 2.0 * ((ph / (2 * math.pi)) % 1.0) - 1.0
save("boss_roar", mix(roar * env_exp(n, 0.05, 3.2),
                      lowpass(noise(d, 14), 900) * env_exp(n, 0.08, 3.0) * 0.5))

save("boss_phase", mix(sweep(180, 820, 0.55) * env_exp(len(t(0.55)), 0.01, 3.0) * 0.7,
                       place(noise(0.4, 15), np.zeros(len(t(0.55)))) * 0.15))
save("summon", mix(sweep(70, 110, 0.6, "saw") * env_exp(len(t(0.6)), 0.05, 3.0) * 0.6,
                   lowpass(noise(0.6, 16), 700) * env_exp(len(t(0.6)), 0.1, 2.5) * 0.4))
save("boss_swing", whoosh(0.12, 400, 2600, seed=17, curve=1.3))

# ---- 反馈 ----
save("gold", mix(ping(1046.5, 0.18, 16) * 0.6,
                 np.concatenate([np.zeros(int(SR * 0.05)), ping(1568.0, 0.16, 14) * 0.5])))

d = 0.7
notes = [523.25, 659.25, 783.99, 1046.5]
step = 0.11
buf = np.zeros(len(t(d)))
for i, f in enumerate(notes):
    s = ping(f, 0.3, 8)
    off = int(SR * step * i)
    buf[off:off + len(s)] += s * 0.55
save("victory", buf)

save("ui_click", ping(1400, 0.035, 40) * 0.6)

# ---- 环境音：雨声循环（8 秒，首尾交叉淡化，接缝听不出来） ----
dur = 8.0
n = int(SR * dur)
rng = np.random.default_rng(21)
raw = rng.uniform(-1.0, 1.0, n)
rain = lowpass(highpass(raw, 300), 5200)
slow = 0.75 + 0.25 * np.sin(2 * math.pi * 0.11 * np.linspace(0, dur, n))
rain = rain * slow
rumble = sine(55, dur) * 0.06 + lowpass(rng.uniform(-1, 1, n), 120) * 0.15
rain = rain + rumble
xf = int(SR * 0.5)
head = rain[:xf].copy()
tail = rain[-xf:].copy()
fade = np.linspace(0.0, 1.0, xf)
rain[:xf] = head * fade + tail * (1.0 - fade)
rain = rain[:-xf]
rain = normalize(rain, 0.55)
write_wav(os.path.join(BGM, "rain_loop.wav"), rain)
print("%-14s %5.0f ms" % ("rain_loop", 1000.0 * len(rain) / SR))
