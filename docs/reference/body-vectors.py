"""Reference vectors for the M body roster.

Format and circle of confusion per body, the M8's 1.333x hyperfocal penalty,
which M can shoot f/2 in bright sun, and where a digital ISO ceiling runs out.

    python3 docs/reference/body-vectors.py
"""
import math

FF_DIAG   = math.hypot(36, 24)      # 43.267
APSH_DIAG = math.hypot(27, 18)      # 32.450
COC_FF    = 0.030
COC_APSH  = COC_FF * APSH_DIAG / FF_DIAG

print(f"full frame  diagonal {FF_DIAG:.3f} mm   CoC {COC_FF:.4f} mm")
print(f"APS-H (M8)  diagonal {APSH_DIAG:.3f} mm   CoC {COC_APSH:.4f} mm   crop {FF_DIAG/APSH_DIAG:.3f}x")

def hyper(f, N, c): return (f*f)/(N*c) + f
def dof(f, N, s_m, c):
    H = hyper(f,N,c); s = s_m*1000
    near = s*(H-f)/(H+s-2*f)
    far  = float('inf') if s >= H else s*(H-f)/(H-s)
    return near/1000, far/1000, H/1000

print("\n=== HYPERFOCAL: M8 vs full frame ===")
print(f"{'lens':>6} {'f/':>5} {'full frame':>12} {'M8 APS-H':>11}  {'difference':>10}")
for f in (28, 35, 50):
    for N in (5.6, 8, 11):
        a = hyper(f,N,COC_FF)/1000; b = hyper(f,N,COC_APSH)/1000
        print(f"{f:>4}mm {N:>5} {a:>10.2f} m {b:>9.2f} m  {(b/a-1)*100:>+9.0f}%")

print("\n  35mm f/8 set to 3 m:")
for name, c in (("full frame", COC_FF), ("M8 APS-H", COC_APSH)):
    n, fr, H = dof(35, 8, 3.0, c)
    print(f"    {name:<11} sharp {n:.2f} m to {fr:.2f} m   (H {H:.2f} m)")

print("\n=== f/2 IN BRIGHT SUN, EV100 15.10 — which M can actually do it? ===")
EV = 15.10
BODIES = [
    ("M6 / MP / M-A", 100, 1/1000,  "film at ISO 100"),
    ("M7 (AE)",       100, 1/1000,  "film at ISO 100"),
    ("M8",            160, 1/8000,  "base ISO 160"),
    ("M9",             80, 1/4000,  "pulled to ISO 80"),
    ("M10",           100, 1/4000,  "base ISO 100"),
    ("M11 mechanical", 64, 1/4000,  "base ISO 64"),
    ("M11 electronic", 64, 1/16000, "base ISO 64"),
]
for name, iso, tmin, note in BODIES:
    evs = EV + math.log2(iso/100)
    t   = 4.0 / (2**evs)                      # f/2 -> N^2 = 4
    ok  = t >= tmin
    print(f"  {name:<16} needs 1/{round(1/t):<6} max 1/{round(1/tmin):<6} {'YES' if ok else 'no':<4} ({note})")

print("\n=== DIGITAL CAN RUN OUT OF ISO TOO ===")
def iso_needed(ev100, N, t): return 100 * 2**(math.log2(N*N/t) - ev100)
CEIL = [("M8", 2500), ("M9", 2500), ("M10", 50000), ("M11", 50000)]
for scene, ev in (("lit street", 5.0), ("dim side street", 3.0), ("near dark", 1.0)):
    need = iso_needed(ev, 2, 1/125)
    verdict = "  ".join(f"{n}:{'ok' if need <= c else 'SHORT'}" for n, c in CEIL)
    print(f"  {scene:<16} EV {ev:<5} f/2 @ 1/125 needs ISO {round(need):<6} {verdict}")
