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
| **Apple Developer Program, $99/yr** | **yes** | **from M4 — WeatherKit needs it** |
| iPhone running iOS 18 or later | yes | from M4 |
| TestFlight app | only to hand builds to others | M6 |

The paid account is the one hard gate, and it does not bite until M4. Milestones M0–M3 are pure
Swift and need no Apple account at all.

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

---

## The Apple Developer account

**You need the paid Apple Developer Program membership, $99/yr.** Not optional, for one specific
reason: **WeatherKit requires it.** There is no free tier — membership includes 500,000 API calls
per month, which is far beyond what one person plus a few testers will use.

What each tier gets you:

| | Free Apple ID | Paid membership |
|---|---|---|
| Build and run on your own iPhone | yes, but the build **expires after 7 days** | yes, 1 year |
| Apps installed at once | 3 | unlimited |
| WeatherKit | **no** | yes |
| TestFlight | no | yes |
| App Store | no | yes |

So the practical sequence is: do M0–M3 with no account, sign up before M4, and you will not hit the
limit at an awkward moment.

### Enabling WeatherKit (once, before M4)

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
| **M3** spotforge | network | `swift run spotforge build --city us-nyc --out bundles/v1`, then open the JSON and look at it |
| **M4** Light screen | **paid account**, WeatherKit enabled, iPhone | take it outside and compare against your meter |
| **M5** Map screen | same | airplane mode, relaunch, spots still there |
| **M6** TestFlight | App Store Connect record | someone else installs it |

## A realistic expectation

M1 is the milestone worth your attention. It is pure maths with fixed expected values, it runs in
seconds from Terminal, and it is where a wrong answer is both most likely and most damaging — a
degrees-versus-radians slip produces numbers that look entirely plausible and are wrong.

If Copilot ever "fixes" a failing test by editing the expected value, that is the bug. The vectors in
[EXPOSURE-MODEL.md](EXPOSURE-MODEL.md) were computed independently and cross-checked; they are not
the thing that is wrong.
