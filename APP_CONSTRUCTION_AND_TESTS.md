# InkArcana: construction and verification notes

**Target:** XTEINK X4 Pro running XTOS Licorice  
**App API:** manifest `api: "2.0"`, observed as API 2.9 on current Licorice builds  
**Display:** 480 × 800 monochrome e-paper

## Purpose

InkArcana is an offline tarot companion built around the 1909 Rider-Waite-Smith artwork. The app treats cards as prompts for reflection rather than predictions.

This file records the implementation decisions that matter on the physical X4 Pro and the checks that can be reproduced from the repository. Automated tests reduce regression risk, but they do not replace a run on the reader itself.

## Package layout

The `.xtapp` contains encrypted Lua code plus a data section with the card text and artwork banks. The launcher icon is stored in the package icon section.

The package is built with `xtpack.py`. `verify_container.py` rebuilds it, checks the Licorice size ceiling and validates the main container sections.

## Licorice API assumptions

InkArcana targets the API 2.x host exposed as API 2.9 on the tested Licorice firmware.

The implementation follows these observed behaviours:

- `on_draw(ctx, g)` receives the canvas as its second argument. On API 2.9 that canvas is userdata and there is no dependable global `g`.
- Touches arrive as pointer events. A completed tap is handled on `type="pointer"` with `phase="up"`.
- Context operations such as invalidation are methods, so the app uses `ctx:invalidate()` rather than dot syntax.
- The sandbox does not expose the standard `os` library. Time comes from `ctx.clock`.
- Package data is read through `ctx.package`.
- Decoded images are finite host resources. InkArcana keeps a small LRU cache and calls `:release()` when an image is evicted.
- Side buttons can emit repeated events. A short debounce window prevents one press from advancing twice.

## Runtime safeguards

### Clock and daily card

The app derives the local day from `ctx.clock:now()`. The daily card is deterministic for that local day. No call to `os.time()` or `os.date()` remains.

### Spreads

Spread generation uses the host random source where available. Selection is bounded and cannot spin forever when card data is missing.

If `cards.txt` cannot be loaded, the app stays open and displays an error message instead of entering a failing selection loop.

### Drawing

Every frame starts with `g:clear(0)`. The interface avoids large filled black rectangles because they can ghost on e-paper and can hide black text.

The menu is drawn as its own screen rather than as a dark overlay.

### Input

The primary touch path accepts API 2.9 pointer-up taps. A compatibility path also accepts the older `touch/tap` shape.

Key events ignore release phases and suppress duplicate presses received inside a short interval.

### Persistence

State is stored in `ctx.state` and committed with `ctx:save_state()`. The saved values include the daily card state and the reversal preference.

## Card text

`data/cards.txt` is the single source of card wording. Each card has a name and a short pair of linked ideas for its upright meaning. It also has an upright reflection, with the same structure repeated for the reversed meaning.

The copy avoids three-item keyword lists and obvious three-part rhetorical lists. The tone is reflective and non-predictive.

## Verification

Run:

```bash
python test_suite.py
python verify_container.py
```

`test_suite.py` checks the 78-card data file and scans for obsolete API calls. It also runs the Lua app in a sandbox simulation when Lupa is available.

The simulation intentionally differs from the earlier test harness in important ways. It removes the global graphics object, requires method-style context calls and sends pointer-up events. This is designed to catch the API mismatches that previously passed because the mocks reproduced the app's assumptions.

`verify_container.py` rebuilds `inkarcana.xtapp`, confirms it remains below the Licorice file-size ceiling and checks the manifest plus the code, data and icon sections.

## What automated tests do not prove

A desktop Lua simulation cannot reproduce the ESP32 memory allocator or the exact e-paper refresh behaviour. It also cannot prove that every future Licorice build will expose the same host API.

Before a release, install the freshly built package on an X4 Pro and exercise the daily card and both spread types. Test Study and Desk Altar as well, then leave and reopen the app to confirm persistence.

## Continuous build

The repository workflow runs the test suite and container verification on changes to the app. It then rebuilds `inkarcana.xtapp` so the binary in the repository stays aligned with the source.
