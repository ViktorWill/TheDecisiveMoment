"""Reference vectors for EXPOSURE-MODEL.md sections 7a-7d.

Analog vs digital solving: how many settings a fixed roll actually admits,
when it admits none, and what ISO a digital body needs instead.

    python3 docs/reference/film-vectors.py
"""
import math

def ev_s(ev100, iso): return ev100 + math.log2(iso/100)
def need(ev):        return 2**ev                      # N^2 / t
def shutter_for(N, ev): return N*N / need(ev)
def iso_for(ev100, N, t):
    return 100 * 2**(math.log2(N*N/t) - ev100)

M6_SHUTTERS = [1/1000,1/500,1/250,1/125,1/60,1/30,1/15,1/8,1/4,1/2,1]
M10_SHUTTERS = [1/4000,1/2000,1/1000,1/500,1/250,1/125,1/60,1/30,1/15,1/8,1/4,1/2,1]
STOPS = [2,2.8,4,5.6,8,11,16]

def solve(ev100, isos, shutters, floor, label, tol=0.34):
    out=[]
    for iso in isos:
        E = ev_s(ev100, iso)
        for t in shutters:
            if t > floor: continue
            for N in STOPS:
                err = math.log2(N*N/t) - E
                if abs(err) <= tol: out.append((iso,N,t,err))
    print(f"  {label}: {len(out)} solutions" + ("" if out else "   << NONE"))
    for iso,N,t,err in sorted(out, key=lambda r:(r[0], -r[1]))[:4]:
        print(f"      ISO {iso:<5} f/{N:<4} 1/{round(1/t):<5} err {err:+.2f}")
    return out

print("=== A. Bright sun, front-lit, EV100 15.10 ===")
print("  35mm, handheld floor 1/125 (walking subjects)")
solve(15.10, [400], M6_SHUTTERS, 1/125, "M6 + HP5 400 (fixed)")
solve(15.10, [100], M6_SHUTTERS, 1/125, "M6 + Ektar 100 (fixed)")
solve(15.10, [100,200,400,800,1600,3200,6400], M10_SHUTTERS, 1/125, "M10 (ISO free)")
print("  wide-open f/2 for isolation:")
for iso in (400,100):
    t = shutter_for(2, ev_s(15.10, iso))
    print(f"      ISO {iso}: needs 1/{round(1/t)} s — M6 max 1/1000, M10 max 1/4000 -> "
          f"{'impossible on both' if 1/t>4000 else 'M10 only'}")

print()
print("=== B. Dim side street after sunset, EV100 5.0 ===")
solve(5.0, [400], M6_SHUTTERS, 1/35, "M6 + HP5 400 (fixed)")
solve(5.0, [1600], M6_SHUTTERS, 1/35, "M6 + HP5 pushed to 1600 (+2)")
solve(5.0, [3200], M6_SHUTTERS, 1/35, "M6 + Delta 3200")
print("  M10 at f/2, 1/125 (freeze a walking subject):")
print(f"      needs ISO {round(iso_for(5.0, 2, 1/125))}")
print("  M10 at f/2, 1/60:")
print(f"      needs ISO {round(iso_for(5.0, 2, 1/60))}")

print()
print("=== C. How far off is a fixed roll? (stops of headroom needed) ===")
for name, ev in [("bright sun", 15.10), ("overcast", 12.60), ("blue hour", 8.0), ("lit street", 5.0)]:
    row=[]
    for iso in (100,400,1600):
        # best achievable on M6 within its ladder at f/5.6, 1/125 floor
        best=None
        E=ev_s(ev,iso)
        for t in M6_SHUTTERS:
            if t>1/35: continue
            for N in STOPS:
                e=math.log2(N*N/t)-E
                if best is None or abs(e)<abs(best): best=e
        row.append(f"ISO{iso}: {best:+.2f}")
    print(f"  {name:<12} EV{ev:<6} " + "   ".join(row))
