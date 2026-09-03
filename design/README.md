# Mockups

Static UI mockups for [M4](../docs/ROADMAP.md) (Light) and [M5](../docs/ROADMAP.md) (Map), in the
**Instrument** direction: near-black ground, hairline rules, tabular monospace figures, one amber
accent. The app is read at arm's length, outdoors, often at dusk — the numbers are the interface and
everything else gets out of their way.

| File | Screen |
|---|---|
| `Main.dc.html` | Light, **analog** — the answer, with the lens-barrel distance scale |
| `Digital.dc.html` | Light, **digital** — ISO as a solved value, with a ceiling |
| `NoSolution.dc.html` | Light — *"not on this roll"*, the state a fixed ISO makes possible |
| `SunPanel.dc.html` | Light — 12-hour scrubber, sun panel, live-meter entry |
| `Gear.dc.html` | Body, film stock and push/pull, lens profiles |
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

## The two modes

`Main.dc.html` and `Digital.dc.html` are the **same street, same lens, same moment** — only the body
differs. Put them side by side; the difference is the point.

- **Analog** dims the ISO, because on a loaded M6 the roll speed is a fact, not a decision. The
  alternatives row reads "3 of 3" because at EV 16.05 a shutter topping out at 1/1000 admits exactly
  three settings, and that is the whole set.
- **Digital** renders ISO at full weight and phrases it as a change — *"raise ISO to 1600"* — because
  it is the answer rather than context. 1562 exact, rounded **up** to the body's next real step.
- **`NoSolution.dc.html`** is the state only analog can reach. HP5 400 genuinely cannot expose a
  EV 5.0 street hand-held on an M6, and an empty list would be the wrong way to say so. The shortfall
  is computed, and every lever re-solves.

All three are built on the verified vectors in
[EXPOSURE-MODEL.md §7a–7d](../docs/EXPOSURE-MODEL.md), regenerable with
`python3 docs/reference/film-vectors.py`. Implemented by
[M4a](../PROMPT-COPILOT.md), after M4 lands the base screen.
