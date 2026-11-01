# InkArcana 🎴
### A Contemplative 1909 Rider–Waite–Smith Tarot Companion for XTEINK X4 Pro (XTOS Licorice)

> [!IMPORTANT]
> **Disclaimer & Community Attribution:**  
> **InkArcana** is an independent, open-source community tribute inspired by the contemplative e-paper interface and design philosophy of [Pocket Oracle](https://pocketoracle.org/) (by Hiroic Ventures).  
> It is **in no way officially affiliated with, endorsed by, maintained by, or connected to Pocket Oracle, Hiroic Ventures, or its creators**.
> 
> All 78 tarot illustrations are from the original 1909 deck drawn by **Pamela Colman Smith** under the direction of Arthur Edward Waite and are in the **public domain**.

---

## ⚡ Quick Start: Ready-to-Install App

You do not need to build from source unless you want to customize the code! A pre-packaged, signed binary is included directly in this repository:

1. **Download:** Grab [`inkarcana.xtapp`](./inkarcana.xtapp) from the root of this repository or from the [**GitHub Releases**](https://github.com/miquelangelfuentes/ink-arcana/releases/latest).
2. **Transfer to SD Card:** Copy `inkarcana.xtapp` directly to the **root directory** of your FAT32 microSD card (not inside any folder).
3. **Install on Device:**
   - Insert the microSD card into your **XTEINK X4 Pro**.
   - Open **All Files** from the main launcher menu.
   - Tap `inkarcana.xtapp` and select **Install this package**.
4. **Launch:** Access **InkArcana** from the **Mini Apps / Ink App** drawer (if locked, tap **"Model" 10 times** in **Settings → About**).

> [!TIP]
> **Alternative Direct Folder Install (Bypass On-Device Installer):**  
> You can also bypass the on-device "Install" dialog entirely by copying the file directly on your computer:  
> Create the folder `/XTApps/inkarcana/` on your SD card and place `inkarcana.xtapp` inside it renamed as `app.xtapp` (path: `/XTApps/inkarcana/app.xtapp`).  
> Insert the SD card, and the app will appear immediately in the **Mini Apps** drawer!

---

## 🌟 Key Features

### 1. Daily Oracle Ritual (Inspired by Pocket Oracle)
- **The Card Waits:** Starts face-down every morning featuring an authentic geometric talisman card back (`+` star matrix and central 8-spoke sacred wheel).
- **One Keyword Upfront:** Tap or press OK to turn the card and reveal its Atkinson-dithered 1909 artwork and its single, punchy keyword (e.g. `Nine of Cups` $\rightarrow$ `Contentment`).
- **The Full Contemplation:** Turn the card again to read its full poetic reflection, cleanly formatted and centered for distraction-free reading on the e-ink screen.
- **Press to Return:** Completes the contemplative cycle, returning smoothly to the waiting state.

### 2. Carefully Dithered for E-Paper (Pamela Colman Smith 1909)
- All 78 cards have been scanned and processed using custom **Atkinson dithering** (preserving 75% diffusion error while leaving clear, luminous white spaces).
- Unlike standard Floyd-Steinberg dithering which produces a hazy gray speckle on e-ink, Atkinson dithering produces high-contrast, razor-sharp line work and rich black inks tuned specifically for the X4 Pro's portrait screen.
- Cards are packed into fixed-stride base64 streams (`data/art_l1.txt` & `data/art_l2.txt`) allowing instantaneous $O(1)$ on-demand decoding without eating device RAM.

### 3. Tarot Learning & Flashcard Quiz Mode 🎓
- **Visual Intuition Practice:** Displays the 1909 artwork with all titles and keywords concealed (`? ? ? MYSTERY CARD ? ? ?`).
- **Tap to Reveal:** Test your intuitive visual recall of Pamela Colman Smith's classical symbols and archetypes before revealing the card's identity.
- **Archetype Breakdown:** Reveals Card Title, Upright Keyword, Shadow Keyword, and an archetypal synthesis.
- **Study Navigation:** Step sequentially through the entire 78-card deck using `< PREV` / `NEXT >` (or the physical side buttons), or tap `RANDOM CARD` for quick flashcard sessions.

### 4. Standby / Desk Altar Mode 🖼️
- **Zero-Power Sacred Space:** Leverages the zero-power bistable nature of E-Ink screens. Place your X4 Pro on your desk, workstation, or nightstand with your daily card permanently visible without draining the battery.
- Strips away all interactive UI chrome, buttons, and navigation for a pure, serene art print aesthetic.
- Displays the card artwork, card title, upright keyword, and sacred emblem. Tap anywhere on the screen to return to the active app.

### 5. Multi-Card Contemplation Spreads 🃏
- **The Triad (3-Card Spread):**
  - Card 1: *The Root* (Past foundations / origins)
  - Card 2: *The Axis* (Present moment / current focus)
  - Card 3: *The Horizon* (Emerging trajectory / future lessons)
- **The Threshold Cross (2-Card Spread):**
  - Card 1: *The Ground* (Where you currently stand)
  - Card 2: *The Crossing* (The immediate obstacle, tension, or ally)
- **Spread Carousel:** Step between cards using the on-screen arrows (`< Card 1 of 3 >`) or physical side buttons; tap any card to view its specific contextual position and contemplation.

### 6. Shadow Work & Upside-Down Reversals 🔄
- Toggle Reversals **ON / OFF** anytime via the menu.
- When drawn reversed (~25% organic probability):
  - Card artwork is rotated **180° upside-down** on the e-ink screen.
  - Displays the card's **Shadow Keyword** (e.g. `Smugness` instead of `Contentment`).
  - Displays the **Shadow Work Reflection** on the back, inviting reflection on what is hidden, repressed, overextended, or blocked.

---

## 🧭 In-App Controls & Navigation

- **Tap `[ ≡ ]` (Top-Left):** Opens the master menu overlay to switch between:
  1. *Daily Oracle Ritual*
  2. *Three-Card Triad Spread*
  3. *Two-Card Cross Spread*
  4. *Tarot Study & Flashcards*
  5. *Desk Altar (Standby Mode)*
  6. *Shadow Reversals: [ ON / OFF ]*
- **Physical Side Buttons:**
  - In Daily/Study mode: Browse sequentially through the 78 cards.
  - In Spreads mode: Step between Card 1, Card 2, and Card 3.
- **Screen Tap or OK Button:**
  - Flips card front and back or confirms options.

---

## 📦 Repository Structure

```
ink-arcana/
├── inkarcana.xtapp     # Pre-compiled, install-ready package for XTEINK X4 Pro
├── manifest.json       # XTOS Licorice API 2.0 app metadata
├── index.lua           # Complete Lua engine (Ritual, Spreads, Quiz, Altar, Menus)
├── icon.png            # 96x96 1bpp rounded squircle icon for Licorice launcher
├── icon_cards_alt.png  # Alternate 96x96 fan-style icon
├── xtpack.py           # Packaging compiler for XTOS Licorice
├── requirements.txt    # Python dependencies for packager (cryptography, Pillow)
├── tools/vendor/       # Cryptographic packaging tools (P-256 ECDH + AES-KW)
└── data/
    ├── cards.txt       # All 78 cards (Title | Upright KW | Upright Read | Shadow KW | Shadow Read)
    ├── art_l1.txt      # Cards 1 to 39: 1-bit Atkinson-dithered PNGs (240x418)
    └── art_l2.txt      # Cards 40 to 78: 1-bit Atkinson-dithered PNGs (240x418)
```

---

## 🛠️ Building from Source

If you want to modify the Lua scripts or add new card data:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/miquelangelfuentes/ink-arcana.git
   cd ink-arcana
   ```

2. **Set up a Python virtual environment:**
   ```bash
   py -m venv .venv
   .venv\Scripts\pip install -r requirements.txt
   ```

3. **Run the Test Suite:**
   ```bash
   .venv\Scripts\python.exe test_suite.py
   .venv\Scripts\python.exe verify_container.py
   ```

4. **Pack the `.xtapp`:**
   ```bash
   .venv\Scripts\python.exe xtpack.py . -o inkarcana.xtapp
   ```

---

## 🔬 Architecture, Firmware Verification & Test Report

For an in-depth technical analysis of the XTOS Licorice firmware reverse engineering, root-cause analyses of previous crash logs, memory limits, and the complete 12-stage test matrix, see:
👉 [**App Construction & Verification Report (APP_CONSTRUCTION_AND_TESTS.md)**](./APP_CONSTRUCTION_AND_TESTS.md)

---

## 📜 Credits & License

- **Inspiration:** Inspired by [Pocket Oracle](https://pocketoracle.org/) by Hiroic Ventures.
- **Tarot Art:** Original 1909 line illustrations by **Pamela Colman Smith**, under the direction of **Arthur Edward Waite** (Public Domain).
- **Firmware & Packaging Architecture:** Based on reverse engineering and container research by `kycube/x4pro-emu` and the open-source XTEINK community.
- **License:** MIT License. Free and open source for the e-ink and tarot communities.
