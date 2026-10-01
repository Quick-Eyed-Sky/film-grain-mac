# Notice

**Film Grain** — Copyright (C) 2026 Jean-Pascal (Quick-Eyed Sky)

This program is free software: you can redistribute it and/or modify it under
the terms of the **GNU General Public License, version 3** (see
[LICENSE](LICENSE)). It is distributed in the hope that it will be useful, but
**WITHOUT ANY WARRANTY**; without even the implied warranty of merchantability
or fitness for a particular purpose.

## Origin — and what was changed

The effect (grain, warmth, vignette) is derived from the **`FilmGrain` node** of
[ComfyUI-post-processing-nodes](https://github.com/EllangoK/ComfyUI-post-processing-nodes)
by **EllangoK**, file
[`post_processing/film_grain.py`](https://github.com/EllangoK/ComfyUI-post-processing-nodes/blob/master/post_processing/film_grain.py),
which is released under the GNU General Public License v3.0.

**This is a modified adaptation, not the original.** Changes made in 2026:

- rewritten from Python to Swift, as a standalone macOS application (the
  original is a node for ComfyUI);
- the random numbers now come from a seed, so the same seed and settings give
  the same pixels (the original draws a new random grain on every run);
- the grain pattern is computed once and reused while the other settings move;
- the vignette range is limited to 0–1, the range in which it has an effect;
- added: a window with live preview, before/after comparison, picture browsing,
  batch saving, a random-picture key to spot-check a large batch,
  preservation of colour profile and metadata, and remembered settings.

Anyone who redistributes this program must keep this notice and the licence,
state their own changes, and make the corresponding source code available.

## Third-party code

None. The app uses only the frameworks that ship with macOS (SwiftUI,
Core Graphics, Image I/O).
