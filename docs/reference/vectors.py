"""Reference implementation for docs/EXPOSURE-MODEL.md.

Not part of the app; nothing depends on it. This script generated every
numeric test vector in that document. Run it before changing the model.

    python3 docs/reference/vectors.py
"""
import math, datetime as dt

# ---------- NOAA solar position ----------
def julian_day(d):
    y, m = d.year, d.month
    if m <= 2: y -= 1; m += 12
    a = y // 100
    b = 2 - a + a // 4
    day = d.day + (d.hour + d.minute/60 + d.second/3600) / 24
    return math.floor(365.25*(y+4716)) + math.floor(30.6001*(m+1)) + day + b - 1524.5

def solar_position(d_utc, lat, lon):
    jd = julian_day(d_utc)
    T = (jd - 2451545.0) / 36525.0
    L0 = (280.46646 + T*(36000.76983 + T*0.0003032)) % 360
    M  = 357.52911 + T*(35999.05029 - 0.0001537*T)
    Mr = math.radians(M)
    C  = (math.sin(Mr)*(1.914602 - T*(0.004817 + 0.000014*T))
          + math.sin(2*Mr)*(0.019993 - 0.000101*T)
          + math.sin(3*Mr)*0.000289)
    true_long = L0 + C
    omega = 125.04 - 1934.136*T
    lam = true_long - 0.00569 - 0.00478*math.sin(math.radians(omega))
    e0 = 23 + (26 + (21.448 - T*(46.815 + T*(0.00059 - T*0.001813)))/60)/60
    eps = e0 + 0.00256*math.cos(math.radians(omega))
    epsr, lamr = math.radians(eps), math.radians(lam)
    decl = math.degrees(math.asin(math.sin(epsr)*math.sin(lamr)))
    # equation of time
    y = math.tan(epsr/2)**2
    L0r = math.radians(L0)
    ecc = 0.016708634 - T*(0.000042037 + 0.0000001267*T)
    eot = 4*math.degrees(y*math.sin(2*L0r) - 2*ecc*math.sin(Mr)
                         + 4*ecc*y*math.sin(Mr)*math.cos(2*L0r)
                         - 0.5*y*y*math.sin(4*L0r) - 1.25*ecc*ecc*math.sin(2*Mr))
    mins = d_utc.hour*60 + d_utc.minute + d_utc.second/60
    tst = (mins + eot + 4*lon) % 1440
    ha = tst/4 - 180
    if ha < -180: ha += 360
    latr, declr, har = math.radians(lat), math.radians(decl), math.radians(ha)
    cz = math.sin(latr)*math.sin(declr) + math.cos(latr)*math.cos(declr)*math.cos(har)
    cz = max(-1.0, min(1.0, cz))
    zen = math.degrees(math.acos(cz))
    elev = 90 - zen
    # refraction
    if elev > 85: r = 0.0
    elif elev > 5: r = (58.1/math.tan(math.radians(elev)) - 0.07/math.tan(math.radians(elev))**3
                        + 0.000086/math.tan(math.radians(elev))**5)/3600
    elif elev > -0.575: r = (1735 + elev*(-518.2 + elev*(103.4 + elev*(-12.79 + elev*0.711))))/3600
    else: r = (-20.772/math.tan(math.radians(elev)))/3600
    elev_corr = elev + r
    az_den = math.cos(latr)*math.sin(math.radians(zen))
    if abs(az_den) > 1e-9:
        ca = (math.sin(latr)*math.cos(math.radians(zen)) - math.sin(declr)) / az_den
        ca = max(-1.0, min(1.0, ca))
        az = math.degrees(math.acos(ca))
        az = (180 - az) % 360 if ha > 0 else (180 + az) % 360
    else:
        az = 180.0
    return elev_corr, az, decl, eot

# ---------- illuminance -> EV100 ----------
def ambient_lux(h_deg):
    if h_deg > 0.5:
        return 128000.0 * (math.sin(math.radians(h_deg)) ** 1.15)
    # twilight: exponential decay anchored at sunset ~ 700 lux, civil end (-6) ~ 3.4 lux
    return 700.0 * math.exp(0.885 * h_deg)

def ev100(lux):
    return math.log2(lux / 2.5)

def cloud_delta(c):
    return -3.0 * (c ** 1.7)

# ---------- depth of field ----------
def hyperfocal_mm(f_mm, N, coc_mm=0.030):
    return (f_mm*f_mm)/(N*coc_mm) + f_mm

def dof(f_mm, N, s_m, coc_mm=0.030):
    H = hyperfocal_mm(f_mm, N, coc_mm); s = s_m*1000.0
    near = s*(H - f_mm)/(H + s - 2*f_mm)
    far = float('inf') if s >= H else s*(H - f_mm)/(H - s)
    return near/1000.0, (far/1000.0 if far != float('inf') else float('inf')), H/1000.0

print("=== SOLAR POSITION ===")
for label, when, lat, lon in [
    ("NYC 2026-06-21 16:00Z (12:00 EDT)", dt.datetime(2026,6,21,16,0,0), 40.7308, -73.9973),
    ("NYC 2026-12-21 17:00Z (12:00 EST)", dt.datetime(2026,12,21,17,0,0), 40.7308, -73.9973),
    ("NYC 2026-06-21 23:00Z (19:00 EDT)", dt.datetime(2026,6,21,23,0,0), 40.7308, -73.9973),
    ("Tokyo 2026-03-20 03:00Z (12:00 JST)", dt.datetime(2026,3,20,3,0,0), 35.6762, 139.6503),
    ("Berlin 2026-09-02 10:00Z (12:00 CEST)", dt.datetime(2026,9,2,10,0,0), 52.52, 13.405),
]:
    e,a,d,q = solar_position(when, lat, lon)
    print(f"{label}\n    elevation={e:.3f} deg  azimuth={a:.3f} deg  decl={d:.3f}  eot={q:.3f} min")

print("\n=== AMBIENT LUX -> EV100 (clear sky, open) ===")
for h in [90,60,45,40,30,20,10,5,2,0,-3,-6]:
    lx = ambient_lux(h)
    print(f"    sun {h:>3} deg -> {lx:>10.1f} lux -> EV100 {ev100(lx):6.2f}")

print("\n=== CLOUD ATTENUATION (stops) ===")
for c in [0.0,0.25,0.5,0.75,1.0]:
    print(f"    cover {c:.2f} -> {cloud_delta(c):+.2f} EV   (from EV15 clear -> EV{15+cloud_delta(c):.1f})")

print("\n=== HYPERFOCAL (full frame, CoC 0.030mm) ===")
for f in [28,35,50]:
    for N in [4,5.6,8,11,16]:
        print(f"    {f}mm f/{N}: H = {hyperfocal_mm(f,N)/1000:.2f} m")

print("\n=== ZONE FOCUS EXAMPLES ===")
for f,N,s in [(35,8,3),(35,8,5),(50,8,3),(28,8,2),(35,11,2),(50,5.6,5)]:
    n,fa,H = dof(f,N,s)
    fs = "inf" if fa==float('inf') else f"{fa:.2f} m"
    print(f"    {f}mm f/{N} at {s} m -> sharp {n:.2f} m to {fs}   (H={H:.2f} m)")

print("\n=== EXPOSURE SOLVE SANITY ===")
def ev_of(N,t): return math.log2(N*N/t)
for N,t,S in [(16,1/100,100),(8,1/250,200),(5.6,1/125,400),(2,1/60,1600)]:
    print(f"    f/{N} @ 1/{round(1/t)} ISO{S} -> EV100 = {ev_of(N,t) - math.log2(S/100):.2f}")


# ------------------------------------------------------------------
# Part 2: subject geometry (EXPOSURE-MODEL section 4a) and the
# end-to-end solve (section 7).
# ------------------------------------------------------------------

def vertical_delta(h):
    """Extra light on a vertical, front-lit subject vs the horizontal plane."""
    if h <= 0.5: return 0.0
    return max(-1.0, min(3.0, math.log2(1.0/math.tan(math.radians(h)))))

print("=== AMBIENT vs FRONT-LIT VERTICAL SUBJECT (clear sky) ===")
print(f"{'sun h':>6} {'lux':>10} {'EV100 horiz':>12} {'vert delta':>11} {'EV100 subject':>14}")
for h in [90,60,45,40,30,20,15,10,5,2,0]:
    lx=ambient_lux(h); e=ev100(lx); d=vertical_delta(h)
    print(f"{h:>6} {lx:>10.0f} {e:>12.2f} {d:>+11.2f} {e+d:>14.2f}")

print("\n=== SCENE MODIFIERS (stops, applied after cloud + vertical) ===")
for n,v in [("open sky / sunlit side",0.0),("shaded side of street",-2.5),
            ("narrow canyon between towers",-3.5),("under arcade / deep shade",-4.5),
            ("subway platform / interior",-6.0)]:
    print(f"    {n:<32} {v:+.1f}")

print("\n=== WORKED END-TO-END: NYC, 21 Jun 2026, 19:00 EDT, sun 14.73 deg, 20% cloud ===")
h=14.727; lx=ambient_lux(h); base=ev100(lx); cl=-3.0*(0.20**1.7); vd=vertical_delta(h)
for scene,mod in [("sunlit side",0.0),("shaded side",-2.5)]:
    ev=base+cl+vd+mod
    print(f"    {scene:<14} EV100 = {base:.2f} {cl:+.2f} (cloud) {vd:+.2f} (vertical) {mod:+.1f} (scene) = {ev:.2f}")

print("\n=== SOLVE: EV100 14.05, ISO 400 film, 35mm, zone-focus strategy ===")
EV=14.05; ISO=400
EVs = EV + math.log2(ISO/100)
print(f"    EV at ISO{ISO} = {EVs:.2f}  (need N^2/t = 2^{EVs:.2f} = {2**EVs:.0f})")
shutters=[1/1000,1/500,1/250,1/125,1/60]
apertures=[2,2.8,4,5.6,8,11,16]
best=[]
for t in shutters:
    for N in apertures:
        e=math.log2(N*N/t); err=e-EVs
        if abs(err)<=0.34 and t<=1/125:   # within 1/3 stop, handheld floor for 35mm
            best.append((abs(err),N,t,err))
best.sort()
def hyper(f,N,c=0.030): return (f*f)/(N*c)+f
def dof(f,N,s,c=0.030):
    H=hyper(f,N,c); s*=1000
    return s*(H-f)/(H+s-2*f)/1000, (float('inf') if s>=H else s*(H-f)/(H-s)/1000)
for err,N,t,signed in best:
    n,fa=dof(35,N,3.0); fs="inf" if fa==float('inf') else f"{fa:.1f}m"
    print(f"    f/{N:<4} 1/{round(1/t):<5} err {signed:+.2f} EV | scale 3m -> {n:.1f}m..{fs}")
