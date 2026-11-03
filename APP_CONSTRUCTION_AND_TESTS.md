# InkArcana: construction, successful fixes and verification

**Target:** XTEINK X4 Pro running XTOS Licorice  
**Display:** 480 × 800 monochrome e-paper  
**App declaration:** `"api": "2.0"`; the tested Licorice runtime exposed API 2.9  
**Current version:** v1.5.0  
**Hardware status:** The owner confirmed on **3 November 2026** that the current app works well on a physical X4 Pro. This confirms successful real-device operation, although it is not a claim of exhaustive testing of every individual feature.

InkArcana is an offline tarot companion using the public-domain 1909 Rider-Waite-Smith artwork. Its readings are prompts for reflection rather than predictions.

This document records the **steps and corrections that turned an initially failing app into a working X4 Pro application**. It also provides a reproducible build procedure and a release checklist for future versions.

## 1. How the app became functional

The initial device symptom was **“App error, closed”**. The most important breakthrough was testing against the **Licorice API actually exposed on the reader**, rather than assuming that older sample code or permissive desktop mocks represented it accurately.

The first version confirmed working on a physical device was **v1.1.0**. Later releases refined the interface and introduced Study functionality. **v1.5.0 is also now confirmed to work on the physical device** by the owner.

The effective sequence was:

1. Match the device's callback signatures and input events.
2. Correct context method calls, clock handling and image resource management.
3. Exercise the app with an API 2.9-style Lua test harness, then rebuild and validate the encrypted container.
4. Install the resulting `.xtapp` on the physical X4 Pro and verify that it launches.
5. Improve the interface in small iterations, preserving the working API integration.
6. Publish the **tested package** as a versioned GitHub Release.

## 2. Critical Licorice API 2.9 findings

### Drawing: the canvas comes from the callback

Use `function on_draw(c, gg)` and draw on the **second argument** (`gg`). The device passes a canvas userdata object. The original implementation rejected this object because it incorrectly expected a Lua table. There is no dependable global graphics object.

```lua
function on_draw(c, gg)
    if not gg then return end
    gg:clear(0)
    -- Draw using gg:text, gg:rect, gg:image, etc.
end
```

On the tested firmware, `gg:clear(0)` gives a white screen. Draw the UI using outlines and restrained rules rather than large filled black rectangles. This improves legibility on monochrome e-paper.

Use protected calls around potentially failing host operations and display useful errors during debugging. A completely swallowed error can hide the cause of **“App error, closed.”**

### Touch: activate on completed pointer events

The reliable current touch event is a pointer event with `phase = "up"`. A pointer-down event must not be mistaken for a completed tap.

```lua
if ev.type == "pointer" and ev.phase == "up" then
    local gesture = ev.gesture or "tap"
    if gesture == "tap" or gesture == "double_tap" then
        handle_tap(tonumber(ev.x) or 0, tonumber(ev.y) or 0)
    end
end
```

A compatibility handler may also support the older `touch`/`tap` shape. Update the tap bounds whenever a button's drawn position or size changes.

Physical side buttons can generate repeated events. InkArcana ignores release events and uses a **250 ms debounce** to prevent accidental double advancement.

### Context methods and unavailable libraries

Use **colon method syntax** for device context operations:

```lua
ctx:invalidate()
ctx:save_state()
```

Do not assume the standard Lua `os` library is available. Obtain date/time information from `ctx.clock:now()`, and use `ctx.clock:millis()` where appropriate.

For random card selection, prefer `ctx.random:bytes(4)` when supported. Spread selection should be bounded and must avoid duplicate cards within the same spread.

### Daily-card consistency

Compute the daily card from the **local calendar day**. Once the daily card has been turned over, opening its interpretation or pressing navigation keys must not silently select a different daily card. Persist the daily state via `ctx.state` and `ctx:save_state()`.

### Images and memory

The 78 card illustrations are stored as 1-bit, Atkinson-dithered images encoded in the two artwork banks. Decode images only when needed.

- Maintain the existing **four-image LRU cache**.
- Call `:release()` for evicted decoded images and when leaving/unloading.
- If decoding fails, draw a framed fallback with the card name rather than crashing.
- Rotate a reversed image only when `ctx.capabilities.image_transform` is supported and the drawing operation succeeds.

The card text and reversed interpretation must still be accessible when image rotation is unavailable.

## 3. Project files and package format

| Repository file | Responsibility |
| --- | --- |
| `index.lua` | App state, callbacks, screens and input |
| `manifest.json` | Identity, version, entry point and API |
| `data/cards.txt` | All 78 cards, including upright and reversed wording |
| `data/art_l1.txt` and `data/art_l2.txt` | Encoded card illustrations |
| `icon.png` | Launcher icon, converted to a monochrome device icon |
| `xtpack.py` | Builds the encrypted Licorice container |
| `tools/vendor/xtapp.py` | Vendored container-format support |
| `test_suite.py` | API, card-data and simulated runtime checks |
| `verify_container.py` | Rebuilds the package and checks its sections and limits |
| `.github/workflows/build-and-verify.yml` | Continuous tests and package rebuilding |
| `inkarcana.xtapp` | Distributable package |

The `.xtapp` contains encrypted code plus **data** and **icon** sections. Card text is accessed through `ctx.package:open_text()` rather than through a desktop filesystem.

The packer uses a device public key derived from the tested Licorice firmware. That remains a **firmware compatibility assumption**: if the firmware changes, revisit `docs/firmware-notes.md` and recheck both the API and the package key.

The manifest currently uses:

```json
{
  "app_id": "inkarcana",
  "display_name": "InkArcana",
  "version": "1.5.0",
  "entry": "index.lua",
  "api": "2.0",
  "permissions": []
}
```

Other descriptive manifest fields are present in the actual file. Preserve them when updating its version.

## 4. Reproducible local build

Start from the repository:

```bash
git clone https://github.com/miquelangelfuentes/ink-arcana.git
cd ink-arcana
```

Use **Python 3.12**, matching the repository's GitHub Actions workflow.

**Windows (PowerShell):**

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe test_suite.py
.\.venv\Scripts\python.exe verify_container.py
```

**Linux / macOS:**

```bash
python3.12 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python test_suite.py
.venv/bin/python verify_container.py
```

`verify_container.py` **already rebuilds** `inkarcana.xtapp` using `xtpack.py`. To run the packer independently, use:

```bash
python xtpack.py . -o inkarcana.xtapp
```

Do not publish the package if either test or verification exits unsuccessfully.

### What the verifier checks

The current `verify_container.py` checks:

- The resulting package fits the Licorice file-size ceiling.
- The manifest identifies InkArcana, uses the expected version and declares API `2.0`.
- The encrypted code, data and icon sections exist; the code section remains within the in-memory limit.
- The embedded icon section has the expected `XTAB` marker.

The version assertion in `verify_container.py` is explicit. **Update it whenever you bump `manifest.json`**; otherwise a legitimate new version fails verification.

## 5. Regression testing that catches the original failures

`test_suite.py` loads the app through **Lupa** in a simulated Lua environment. The crucial decision was to make that environment stricter than the earlier mocks:

- There is **no global graphics object**. Rendering must use the canvas argument passed to `on_draw(c, gg)`.
- Context operations check method-style calls.
- A pointer-down does nothing; a pointer-up activates the relevant control.
- The unavailable desktop modules are removed from the simulated Lua environment.
- Simulated key presses check the side-button debounce and daily-card stability.

The current v1.5 tests also check the 78-card input format and scan for obsolete host APIs. They exercise simulated screen drawing, spread generation and new stateful Study controls, plus history serialization and pagination helpers.

Tests can confirm that the code follows the expected calling conventions. They **cannot reproduce** all ESP32 memory conditions, exact firmware font metrics or real e-paper refresh timing.

## 6. Design corrections made after the first working build

### v1.2: clearer controls and card presentation

- Widened the upper-left **MENU** button and aligned its tap bounds with the visible frame.
- Replaced the confusing **REV** badge over the artwork with a legible **REVERSED** label outside the image.
- Simplified the card back, navigation rows and separators for the e-paper display.
- Reduced avoidable dark fills and preserved the card art as the main visual element.

### v1.2.2: safe spread headings

**THREE-CARD REFLECTION** could collide with MENU because the physical font width differed from expectations. The fix uses a dedicated **two-line heading** inside the area to the right of MENU. **TWO-CARD REFLECTION** uses the same treatment.

Do not reintroduce a globally centered one-line spread title without testing it on the reader.

### v1.3 and v1.4: make Study a genuine learning mode

The artwork was visible even while the caption said **MYSTERY CARD**, which was misleading. Study now identifies the card immediately and opens its meaning on tap.

The first combined upright/reversed meaning layout cut off text. The subsequent redesign displays one orientation at a time and adds an independent **upright/reversed toggle**. This works as a learning feature even when reversed cards are disabled for readings.

### v1.5: learning progress and reading continuity

The current feature layer adds:

- **Study filters** for the complete deck, Major Arcana and individual suits; separate favourites/learned views.
- **LEARN**, **FAV** and **FLIP** controls, with lightweight persisted state; random Study selection respects the current filter.
- **Card metadata** identifying the arcana or minor-card suit/rank.
- **Text pagination** for long meanings, with side-button navigation where multiple pages exist.
- **Spread overview** with a new-spread action, plus up to **six recent spreads** stored as compact indexes and orientation flags.
- A two-page **Help** screen and more explicit date display for the Daily card.

The v1.5 code introduces later overrides of some earlier drawing and lifecycle definitions. When modifying `index.lua`, inspect the **effective definitions near the end of the file** rather than assuming an earlier function body is still the active implementation. Consolidating those definitions would be a useful future maintenance refactor, but it was not necessary for the owner-confirmed working build.

## 7. Install and validate on an X4 Pro

1. Take the package that passed verification. Copy `inkarcana.xtapp` to the **root of a FAT32 microSD card**.
2. On the device, open **All Files**, choose the package and select **Install this package**.
3. Open **Ink App** and launch **InkArcana**. If the Ink App entry is hidden, the documented device route is **Settings → About → tap Model ten times**.
4. Check that the app opens, the icon is displayed and the interface draws normally. Ensure the MENU button is readable and its tap target works.
5. Turn the Daily card, open its interpretation and return to the card. Confirm that the Daily card stays fixed for the same calendar day.
6. Try both spread layouts. Check that long headings do not touch MENU and that reversed status appears outside the illustration.
7. Open Study: inspect the image and card name, switch orientation, navigate the suit filters and try the learned/favourite controls.
8. Open a long meaning, if one spans multiple pages, and test side-button pagination.
9. Create a spread, inspect its overview and reopen it from Recent readings.
10. Leave and reopen the app. Check that saved preferences and the previously selected daily state persist.

**Confirmed outcome:** The owner reported on **3 November 2026** that the app works great on the physical device following the v1.5.0 changes. The steps above remain a **repeatable checklist for future releases**, not a claim that each separate step was explicitly reported as passed.

If a new build fails, compare it with the last confirmed working release before changing multiple areas at once.

## 8. GitHub Actions and publishing Releases

The permanent `.github/workflows/build-and-verify.yml` workflow runs on relevant pushes to `main` and can be started manually. It installs dependencies, runs `test_suite.py`, executes `verify_container.py` and commits a rebuilt `inkarcana.xtapp` when needed.

**Important:** That permanent workflow **does not automatically publish a GitHub Release**. Building a package in the repository and uploading a new release asset are separate steps.

For the next version:

1. Update `manifest.json` and the exact version assertion in `verify_container.py`. Update the README if the behavior changed.
2. Run the test suite and container verifier.
3. Confirm the GitHub Actions build succeeded for the intended source commit.
4. Install and test the exact candidate `.xtapp` on the reader.
5. Create a tag and GitHub Release with the **same tested binary**, using GitHub's release interface or the GitHub CLI.
6. Verify that the release page contains the correct `inkarcana.xtapp` asset and points to the intended commit.

An example GitHub CLI command, after preparing `release-notes.md` and identifying the tested commit:

```bash
gh release create vX.Y.Z inkarcana.xtapp \
  --target VERIFIED_COMMIT_SHA \
  --title "InkArcana vX.Y.Z" \
  --notes-file release-notes.md
```

Use a concrete version in place of `X.Y.Z`. Do not rebuild after the hardware test and then quietly upload different bytes. A SHA-256 hash can help establish that the uploaded asset and tested package are identical.

The published **v1.5.0** release is at:
https://github.com/miquelangelfuentes/ink-arcana/releases/tag/v1.5.0

Its release asset is named `inkarcana.xtapp`. The published asset at that milestone was **876,432 bytes**, with SHA-256:
`041f40192b49556e943c9da68607d2b3cc50b67f651e5dc6a42107a9717df6ac`.

## 9. Troubleshooting by symptom

| Symptom | First checks |
| --- | --- |
| **App error, closed** | Inspect the actual `on_draw` callback arguments, host-method syntax and API compatibility. Check the drawn error text if available. |
| Screen blank or drawing seems missing | Ensure the second argument to `on_draw(c, gg)` is used; verify `gg:clear(0)` and the API 2.9-style canvas mock. |
| Taps do nothing or activate twice | Use pointer **up**, verify touch coordinates and check key debounce. |
| MENU text or header overlaps | Inspect physical font widths. Keep the fixed MENU bounds and two-line spread headings. |
| Reversed status is difficult to read | Render the label outside the card artwork on a white background. |
| Study meaning seems cut short | Inspect pagination calculations, page indicators and side-button navigation. |
| Artwork missing or app becomes unstable after browsing | Check package data reads, image decoding, the bounded cache and `:release()`. |
| Different Daily card appears the same day | Verify local-day calculation, restoration from `ctx.state` and the daily-mode key handlers. |
| The package cannot be installed | Validate the manifest, container sections and size; recheck compatibility with the target firmware. |
| Release does not match the source | Compare the release version/commit, the repository binary and the actual asset hash. |

## 10. What “tested successfully” means

There are **two distinct kinds of evidence**:

- **Automated verification:** The app loads in the Lua simulation, exercises the tested behaviors and produces a container that passes structural checks.
- **Real-device confirmation:** The owner has installed and run the app on the X4 Pro, confirming that it works on actual hardware.

Both are now available for the v1.5.0 milestone, with the scope of device testing described above. Future firmware updates and future app releases should repeat this process before claiming compatibility.
