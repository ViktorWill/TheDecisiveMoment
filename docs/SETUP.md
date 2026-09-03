# What you need to build and run this

Nothing in this repository has been compiled yet — the specs were written in a Linux container with
no Swift toolchain and no Xcode. Your Mac is where the first real build happens, so expect some
friction on the first `⌘B` regardless of how clean the generated code looks.

## Short version

| | Needed | When |
|---|---|---|
| Mac with Apple silicon, ~60 GB free | yes | from M0 |
| Xcode 26 (or 16+) | yes | from M0 |
| Homebrew + XcodeGen | yes | from M0 |
| **An Apple ID** | **yes** | **from M4 — a free one is enough** |
| Apple Developer Program, $99/yr | only for WeatherKit, TestFlight and the App Store | M4 onwards |
| iPhone running iOS 18 or later | yes | from M4 |
| TestFlight app | only to hand builds to others | M6 |

There are two ways to get this onto a phone, and neither of them is blocked by the other:

- **Free Apple ID** — build the **`The Decisive Moment (Free)`** scheme. It carries no WeatherKit
  entitlement, so automatic signing accepts it, and the sky comes from a five-segment control on the
  Light screen instead of a forecast. Everything else — map, spots, exposure model, sun position,
  live meter, offline bundles — is unchanged.
- **Paid membership, $99/yr** — build the default **`TheDecisiveMoment`** scheme. WeatherKit leads,
  and the sky control is still there as an override off the cloud figure.

Milestones M0–M3 are pure Swift and need no Apple account at all.

---

## On the Mac

### Xcode

Xcode 26 is current. Its minimum macOS is **Sequoia 15.6**, and point releases have moved that
target — Xcode 26.4 requires macOS Tahoe 26.2. Check the App Store page against your macOS version
before downloading 15 GB.

Xcode 16 also works: the project targets iOS 18 and Swift 6, both of which Xcode 16 supports. Use
whatever you already have if it is 16 or newer, and only upgrade if something needs it.

Budget **~60 GB free disk**. Xcode is roughly 15 GB installed and each simulator runtime is several
more.

Apple silicon is strongly preferred. An Intel Mac will build this but slowly, and Xcode 26 is the
last stop for several Intel configurations.

### Command line tools

```sh
xcode-select --install          # if not already present
sudo xcodebuild -license accept
```

### XcodeGen

The `.xcodeproj` is generated, never committed. You need XcodeGen to produce it:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"  # Homebrew, if needed
brew install xcodegen
```

### First run

```sh
git clone https://github.com/ViktorWill/TheDecisiveMoment.git
cd TheDecisiveMoment
git checkout claude/photography-app-architecture-whok1z

xcodegen generate
open TheDecisiveMoment.xcodeproj
```

Re-run `xcodegen generate` any time `project.yml` changes or a package is added. It is fast and safe
to run repeatedly.

### Testing the logic without opening Xcode

The three pure packages have no Apple dependencies, so they run straight from Terminal using the
toolchain Xcode already installed:

```sh
swift test --package-path Packages/TDMLight
swift test --package-path Packages/TDMCore
swift test --package-path Packages/TDMSpots
```

This is how you check M1 and M2. No simulator, no signing, no account — and it is the fastest way to
find out whether the agents got the exposure maths right.

There is no `Package.swift` at the repo root — each package under `Packages/` and `Tools/` has its
own, which is why every command above names `--package-path` explicitly rather than assuming you are
sitting inside the package's own directory.

---

## The Apple Developer account

Either tier gets the app onto your own phone. The difference is WeatherKit, how long the build
lasts, and whether anyone else can have it.

| | Free Apple ID | Paid membership, $99/yr |
|---|---|---|
| Build and run on your own iPhone | yes, but the build **expires after 7 days** | yes, 1 year |
| Apps installed at once | 3 | unlimited |
| WeatherKit | **no** | yes, 500,000 calls/month |
| TestFlight | no | yes |
| App Store | no | yes |

### The free path

```sh
xcodegen generate
open TheDecisiveMoment.xcodeproj
# scheme: The Decisive Moment (Free) → your iPhone → Run
```

Xcode → Signing & Capabilities → Team → *Add an Account…* and sign in with any Apple ID. The `Free`
configuration points `CODE_SIGN_ENTITLEMENTS` at `App/TheDecisiveMoment-Free.entitlements`, which
asks for nothing, and defines `TDM_NO_WEATHERKIT`, which compiles `WeatherKitProvider` out
altogether. Do not add the WeatherKit capability to that configuration: automatic signing refuses an
entitlement a free Apple ID cannot be granted, and it refuses the *whole* build, not just the
feature.

You will also need a bundle identifier nobody else has registered. `com.viktorwill.thedecisivemoment`
is taken; change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to something of your own and re-run
`xcodegen generate`.

Three things to know before you rely on it, because none of them are worked around and all of them
will bite:

1. **The build expires after 7 days.** On the eighth day it refuses to launch — *"…could not be
   verified"* — and the only fix is to plug into the Mac and hit Run again. Nothing on the phone can
   renew it, and there is no warning beforehand.
2. **Three sideloaded apps at a time.** A free Apple ID can have three of its own builds installed
   across all devices. A fourth requires deleting one.
3. **No TestFlight, and no App Store.** Handing the app to someone else needs the paid membership.
   There is no free route to another person's phone.

And the app's own difference, from `docs/SPEC-light.md`: there is no forecast, so the sky is a
five-segment control — Clear, Light haze, Hazy sun, Cloudy bright, Overcast — sitting where the
weather readout goes. Those map to exactly the cloud-cover rows the model already uses
(EXPOSURE-MODEL §4b), so the answer is as good as the sky you report. The 12-hour scrubber still
works: sun position is computed on device, the reported cover is held across the window, and the
uncertainty widens for the hours ahead rather than the feature disappearing.

### The paid path, and enabling WeatherKit (once, before M4)

1. [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles →
   Identifiers → register the App ID `com.viktorwill.thedecisivemoment`.
2. In the **App Services** tab, tick **WeatherKit**. This is what grants the
   `com.apple.developer.weatherkit` entitlement.
3. In Xcode, Signing & Capabilities → add the WeatherKit capability.
4. Create the app record in App Store Connect with the same bundle ID (needed for TestFlight at M6).

Entitlement propagation is not instant — allow up to a few hours before the first WeatherKit call
succeeds. If it fails immediately after enabling, wait rather than debugging.

---

## On the iPhone

### The phone itself

Anything running **iOS 18 or later** — iPhone XR / XS and newer. The deployment target is iOS 18, so
this is not restrictive.

### Developer Mode

Required since iOS 16 for any build you install yourself:

**Settings → Privacy & Security → Developer Mode → on**, then restart the phone.

The toggle only appears *after* the Mac has tried to install a build once, so plug in and hit Run
first, then go looking for it.

### Cable, then wireless

Pair over USB-C or Lightning the first time. After that, Xcode → Window → Devices and Simulators →
tick *Connect via network*, and you can run untethered — which you want, because the interesting
testing happens outside.

### Permissions the app will ask for

- **Location, While Using** — spots near you, and the sun position.
- **Camera** — only for the live meter on the Light screen. It reads exposure values and captures
  nothing. The Info.plist string says so, and that has to stay true.

### TestFlight

Only needed at M6, when you want other people to have it. Install the **TestFlight** app from the
App Store on each tester's phone; they get an invite by email or link. Builds last 90 days.

---

## What can be tested where

This matters more than it looks — several parts of the Light feature simply cannot be checked in the
simulator.

| Thing | Simulator | Real device |
|---|---|---|
| Exposure maths, solar position, DoF | yes — and via `swift test`, no simulator needed | yes |
| Bundle download, decode, map rendering | yes | yes |
| Location | yes, simulated | yes |
| WeatherKit | yes, with entitlement + network | yes |
| The manual sky control (Free build) | yes | yes |
| **Live meter (camera exposure readout)** | **no — no camera** | yes |
| **Compass heading** (street bearing on new pins) | **no** | yes |
| Offline behaviour in airplane mode | approximately | yes — this is the real test |

The last row is the one to take seriously. The whole design rests on the app being fully useful with
no connection, and the only honest test of that is a phone in airplane mode on a street.

---

## Milestone by milestone

| Milestone | What you need | How you check it |
|---|---|---|
| **M0** scaffold | Xcode, XcodeGen | `xcodegen generate`, app launches to three empty tabs |
| **M1** light maths | nothing else | `swift test --package-path Packages/TDMLight` — the four vectors in EXPOSURE-MODEL.md pass |
| **M2** models, bundles | nothing else | `swift test` on TDMCore and TDMSpots |
| **M3** spotforge | network | `swift run --package-path Tools/spotforge spotforge build --city us-nyc --out bundles/v1`, then open the JSON and look at it |
| **M4** Light screen | an Apple ID and an iPhone; a paid account only if you want WeatherKit | take it outside and compare against your meter |
| **M5** Map screen | same | airplane mode, relaunch, spots still there |
| **M6** TestFlight | App Store Connect record | someone else installs it |

## A realistic expectation

M1 is the milestone worth your attention. It is pure maths with fixed expected values, it runs in
seconds from Terminal, and it is where a wrong answer is both most likely and most damaging — a
degrees-versus-radians slip produces numbers that look entirely plausible and are wrong.

If Copilot ever "fixes" a failing test by editing the expected value, that is the bug. The vectors in
[EXPOSURE-MODEL.md](EXPOSURE-MODEL.md) were computed independently and cross-checked; they are not
the thing that is wrong.
