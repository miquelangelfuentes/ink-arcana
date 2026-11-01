# InkArcana (E-Ink Tarot Companion for XTEINK X4 Pro)

> [!IMPORTANT]
> **Disclaimer & Attribution:** This application is an independent, open-source community tribute inspired by the contemplative design and e-paper interface of [Pocket Oracle](https://pocketoracle.org/) (by Hiroic Ventures). It is **in no way officially affiliated with, endorsed by, supported by, or connected to Pocket Oracle, Hiroic Ventures, or its creators**.
>
> All 78 tarot illustrations are from the original 1909 deck drawn by Pamela Colman Smith under the direction of Arthur Edward Waite and are in the **public domain**.

A contemplative divination, reflection, and learning companion tailored for the **XTEINK X4 Pro** running **XT Licorice 261024**, featuring all **78 Pamela Colman Smith 1909 Rider–Waite–Smith cards** carefully Atkinson-dithered for e-paper.

---

## What's Included

### 1. Daily Oracle Ritual (Inspired by Pocket Oracle)
- **The Card Waits:** Starts face-down every morning with an authentic geometric talisman back (`+` star matrix and central 8-spoke sacred wheel).
- **One Keyword Upfront:** Turn the card to reveal its Atkinson-dithered 1909 artwork and its single, punchy keyword (e.g. `Nine of Cups` $\rightarrow$ `Contentment`).
- **The Full Contemplation:** Turn the card again to read its full poetic reflection centered cleanly on the e-ink screen.

### 2. Tarot Learning & Flashcard Mode 🎓
- **Visual Recall Quiz:** Displays the 1909 artwork alone with the card title and keyword concealed (`? ? ? MYSTERY CARD ? ? ?`).
- **Tap to Reveal:** Test your intuitive visual recall of Pamela Colman Smith's visual archetypes.
- **Symbol & Meaning Breakdown:** Reveals Card Title, Upright Keyword, Shadow Keyword, and a condensed archetypal meaning.
- **Controls:** Step sequentially (`< PREV` / `NEXT >`) or tap `RANDOM CARD` to study all 78 cards.

### 3. Standby / Desk Altar Mode 🖼️
- **Zero-Power Desk Display:** Takes advantage of E-Ink's bi-stable display to leave your card of the day permanently visible on your desk or nightstand without draining the battery.
- Strips away all interactive button prompts for a serene, uncluttered sacred space aesthetic.
- Tap anywhere on the screen to return to the active app.

### 4. Multi-Card Contemplation Spreads 🃏
- **The Triad (3-Card Spread):**
  - Card 1: *The Root (Past / Origins)*
  - Card 2: *The Axis (Present / The Immediate Moment)*
  - Card 3: *The Horizon (Future / Direction)*
- **The Threshold Cross (2-Card Spread):**
  - Card 1: *The Ground (Where you stand)*
  - Card 2: *The Crossing (The obstacle or ally)*
- **Spread Controls:** Step through cards with `< Card 1 of 3 >` or physical side buttons; tap the card body to read that specific position's contemplation.

### 5. Shadow Work & Upside-Down Reversals 🔄
- Toggle Reversals **ON / OFF** anytime in the menu.
- When drawn reversed (~25% probability):
  - Card artwork is rotated **180° upside-down** on the e-ink screen.
  - Displays the card's **Shadow Keyword** (e.g. `Smugness` instead of `Contentment`).
  - Displays the **Shadow Work Reflection** on the back, inviting reflection on what is hidden, blocked, or overextended.

---

## Navigation & Menu Drawer

- **Tap `[ ≡ ]` (Top-Left):** Opens the master menu to switch between:
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
  - Flips card front and back or triggers actions.

---

## Package Structure

```
pocket-oracle-xtapp/
├── manifest.json       # App configuration (API 2.0 for Licorice 261024)
├── index.lua           # Core engine: Daily ritual, Spreads, Study mode & Desk Altar
├── icon.png            # 96x96 rounded-square 1bpp icon for the Ink App grid
├── xtpack.py           # Community packager script with embedded device public key
├── tools/vendor/       # Cryptographic packaging modules (ECDH P-256 + AES-KW)
└── data/
    ├── cards.txt       # All 78 cards (Title | Upright KW | Upright Read | Rev KW | Rev Read)
    ├── art_l1.txt      # Cards 1 to 39: 1-bit Atkinson-dithered PNGs (240x418)
    └── art_l2.txt      # Cards 40 to 78: 1-bit Atkinson-dithered PNGs (240x418)
```

---

## Build & Sideload to XTEINK X4 Pro

1. **Compile `.xtapp`:**
   ```bash
   py xtpack.py . -o inkarcana.xtapp
   ```
2. **Transfer to SD Card:**
   - Copy `inkarcana.xtapp` to the root directory of your microSD card.
   - Insert into the X4 Pro, open **All Files**, and tap the `.xtapp` file.
   - Access anytime via the **Ink App drawer** (unlocked by tapping **"Model" 10 times** in **Settings $\rightarrow$ About**).

---

## Notice & Credits

- Concept & Aesthetic Inspiration: [Pocket Oracle](https://pocketoracle.org/) by Hiroic Ventures.
- Artwork: Pamela Colman Smith, 1909 Rider–Waite–Smith Tarot deck (Public Domain).
- Firmware Tools & Reverse Engineering: `omer-faruq-xteink` and the XTEINK community.
