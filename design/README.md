# Mockups

Static UI mockups for [M4](../docs/ROADMAP.md) (Light) and [M5](../docs/ROADMAP.md) (Map), in the
**Instrument** direction: near-black ground, hairline rules, tabular monospace figures, one amber
accent. The app is read at arm's length, outdoors, often at dusk — the numbers are the interface and
everything else gets out of their way.

| File | Screen |
|---|---|
| `Main.dc.html` | Light — the answer, with the lens-barrel distance scale |
| `SunPanel.dc.html` | Light — 12-hour scrubber, sun panel, live-meter entry |
| `Gear.dc.html` | Body and lens profiles |
| `Map.dc.html` | Spot map with filter sheet |
| `SpotDetail.dc.html` | Spot detail |
| `Tokens.dc.html` | **The design system** — palette, type scale, spacing, marker glyphs |

`Tokens.dc.html` is the one to implement against. Everything else is an application of it.

Every number in these mockups is real — taken from the vectors in
[EXPOSURE-MODEL.md](../docs/EXPOSURE-MODEL.md), not invented to fill a box. Two details that look
like styling but are not:

- **The distance scale is positioned linearly in 1/distance**, which is how a Leica barrel is
  actually engraved. That is why 0.7–2 m occupies two thirds of the track and 5, 10, ∞ bunch at the
  end. Reproduce the spacing, not just the marks.
- **"3 of 3" on the alternatives row is literal.** At EV 16.05 the M6's shutter tops out at 1/1000,
  so the ladder yields exactly f/8 · 1/1000, f/11 · 1/500 and f/16 · 1/250. The row is the complete
  solution set, not the first three of many.

## Viewing and editing

The published canvas: <https://claude.ai/code/artifact/b536d281-33e3-45c2-a604-615877da75a4>

These are plain HTML — open one in a browser to see that screen on its own. The canvas is rebuilt
from these files, so edit the source here rather than the generated page (which is gitignored).

## Open question

ISO is rendered dimmer than aperture and shutter on the Light readout. On a loaded M6 the roll speed
is a fact, not a control, so it reads as context. On an M10, where ISO is a third degree of freedom,
that is wrong and it should carry the same weight as the other two. The gear profile's `ISOMode`
already distinguishes the two cases; the UI should follow it.
