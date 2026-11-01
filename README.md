# InkArcana 🎴
### A reflective 1909 Rider-Waite-Smith tarot companion for XTEINK X4 Pro

> [!IMPORTANT]
> **InkArcana** is an independent open-source project inspired by the contemplative e-paper approach of [Pocket Oracle](https://pocketoracle.org/) by Hiroic Ventures. It is not affiliated with Pocket Oracle or Hiroic Ventures.
>
> The 78 illustrations come from the original 1909 Rider-Waite-Smith deck drawn by **Pamela Colman Smith** under the direction of Arthur Edward Waite. The artwork is in the public domain.

InkArcana treats tarot cards as prompts for reflection rather than predictions.

---

## Quick start

A rebuilt `inkarcana.xtapp` is included in the repository.

1. Download [`inkarcana.xtapp`](./inkarcana.xtapp).
2. Copy it to the root of a FAT32 microSD card.
3. On the XTEINK X4 Pro, open **All Files**, select the package and choose **Install this package**.
4. Open **Ink App** and launch **InkArcana**. If the Ink App entry is hidden, open **Settings → About** and tap **Model** ten times.

The package targets XTOS Licorice with manifest API `2.0`, which is exposed as API 2.9 on the tested current firmware.

---

## What the app does

### Daily card

The card begins face-down. Turn it to see the illustration and its short reflective theme. Tap the card again to read the full reflection. The same daily card is kept for the local calendar day.

### Reflective spreads

InkArcana includes a three-card reflection with the positions **What shaped this**, **Where you are** and **What may emerge**. A shorter two-card reflection uses **Where you stand** and **What meets you**.

Cards in a spread are selected without duplicates. Reversed cards can be enabled from the menu.

### Study mode

Study mode now works as a deck-learning workspace. Each card is identified immediately and includes suit or arcana metadata. You can filter the deck by suit, favourites or learned cards; random selection respects the active filter. Cards can be marked as learned or favourite, and the FLIP control makes upright and reversed meanings available independently of the reading setting. Longer meanings are paginated rather than silently cut off.

### Recent readings

InkArcana keeps a lightweight history of the six most recent spreads. The history stores card indexes and orientations rather than artwork, and a saved spread can be reopened from the menu. Each new spread also includes an overview with a direct option to generate another spread of the same type.

### Help and controls

A two-page Help screen explains the app modes and the physical controls. Long readings use the side buttons for page changes while the reading is open.

### Desk altar

Desk Altar keeps the daily card on a minimal screen with its date and reflective theme. Because e-paper is bistable, the displayed image itself does not require continuous screen power. Tap anywhere to return to the app.

---

## Artwork on the X4 Pro

The Pamela Colman Smith images are prepared as 1-bit Atkinson-dithered PNGs for the 480 × 800 e-paper display. Their base64 data is divided between `data/art_l1.txt` and `data/art_l2.txt`.

Images are decoded only when needed. The app keeps a small runtime cache and explicitly releases older decoded images so it stays within the host's limited image resources.

If an image cannot be decoded, InkArcana keeps running and shows a framed card name instead.

---

## XTOS Licorice compatibility

Version 1.5 follows the API 2.9 behavior observed on current Licorice builds. In particular, it uses the canvas passed to `on_draw(ctx, g)`, handles completed pointer taps on `phase="up"` and calls context methods with method syntax such as `ctx:invalidate()`.

The app also avoids the unavailable standard `os` library. Time comes from `ctx.clock`, while random selections use the host random source where available.

Side-button events are debounced because the firmware can emit more than one event for a physical press. Decoded images use a bounded cache with explicit release.

---

## Repository structure

```text
ink-arcana/
├── inkarcana.xtapp
├── manifest.json
├── index.lua
├── icon.png
├── test_suite.py
├── verify_container.py
├── xtpack.py
├── APP_CONSTRUCTION_AND_TESTS.md
└── data/
    ├── cards.txt
    ├── art_l1.txt
    └── art_l2.txt
```

`data/cards.txt` is the source for all card wording. Each upright or reversed keyword field uses one idea or a linked pair rather than a three-item list.

---

## Build and verify

Create a virtual environment and install the dependencies:

```bash
py -m venv .venv
.venv\Scripts\pip install -r requirements.txt
```

Run the API regression suite and package verifier:

```bash
.venv\Scripts\python.exe test_suite.py
.venv\Scripts\python.exe verify_container.py
```

`verify_container.py` rebuilds `inkarcana.xtapp`, checks the Licorice package-size ceiling and validates the package sections.

GitHub Actions runs the same checks whenever app source or package data changes. If the package differs, the workflow commits the rebuilt `.xtapp` back to the repository.

For implementation details and the limits of automated testing, see [APP_CONSTRUCTION_AND_TESTS.md](./APP_CONSTRUCTION_AND_TESTS.md).

---

## Credits and licence

- **Inspiration:** [Pocket Oracle](https://pocketoracle.org/) by Hiroic Ventures.
- **Artwork:** Pamela Colman Smith's 1909 Rider-Waite-Smith illustrations, public domain.
- **Firmware research:** XTEINK community reverse engineering, including `kycube/x4pro-emu` and `omer-faruq-xteink/touch-licorice-apps`.
- **Licence:** MIT.
