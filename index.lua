-- ==============================================================================
-- INKARCANA for XTEINK X4 Pro (XTOS Licorice 261024)
-- An independent, unofficial community tribute inspired by pocketoracle.org
--
-- DISCLAIMER & ATTRIBUTION:
-- This app is an independent community project and is in NO WAY officially
-- affiliated with, endorsed by, or connected to Pocket Oracle, Hiroic Ventures,
-- or its creators. All 1909 Pamela Colman Smith tarot artwork is Public Domain.
--
-- Features:
--   1. Daily Oracle Ritual (Waits -> Front -> Full Reading)
--   2. Multi-Card Contemplation Spreads (3-Card Triad & 2-Card Cross)
--   3. Tarot Learning & Flashcard Mode (Visual Quiz & Symbol Anatomy)
--   4. Standby / Desk Altar Mode (Zero-power e-ink display for your desk)
--   5. Shadow Work & Upside-Down Reversals (Rotated art + Shadow keywords)
-- ==============================================================================

local W, H = 480, 800
local CARD_W, CARD_H = 240, 418
local CARD_X, CARD_Y = 120, 70

-- Application State
local state = {
    -- Modes: "daily", "spread", "study", "altar"
    mode = "daily",

    -- Daily View: "waits", "front", "reading"
    daily_view = "waits",
    daily_index = 45,        -- 1..78 (defaults to Nine of Cups)
    daily_reversed = false,
    has_turned_today = false,
    last_day = 0,

    -- Multi-Card Spreads
    spread_type = "triad",   -- "triad" (3 cards: Past/Present/Future) or "cross" (2 cards: Ground/Crossing)
    spread_cards = {},       -- list of { index, reversed, position_label }
    spread_pos = 1,          -- currently focused card in spread
    spread_view = "front",   -- "front" or "reading"

    -- Study / Flashcard Mode
    study_index = 1,         -- 1..78
    study_revealed = false,  -- false = test artwork only, true = reveal title & meanings
    study_suit = "all",      -- "all", "major", "wands", "cups", "swords", "pentacles"

    -- Settings
    reversals_enabled = true,
    menu_open = false
}

local cards = {}             -- { key, name, up_kw, up_read, rev_kw, rev_read, suit, num_str }
local image_cache = {}

-- ------------------------------------------------------------------------------
-- Date & Day Helpers
-- ------------------------------------------------------------------------------
local function get_epoch_day()
    local ok, t = pcall(function() return ctx.clock:now() end)
    if ok and type(t) == "table" and tonumber(t.epoch_sec) then
        local sec = tonumber(t.epoch_sec)
        local hour = tonumber(t.hour) or 0
        local min = tonumber(t.minute) or 0
        local s = tonumber(t.second) or 0
        local off = (hour * 3600 + min * 60 + s) - (sec % 86400)
        if off > 14 * 3600 then off = off - 86400 end
        if off < -12 * 3600 then off = off + 86400 end
        return math.floor((sec + off) / 86400)
    end
    return math.floor(os.time() / 86400)
end

local function get_formatted_date()
    local t = os.time()
    local dt = os.date("*t", t)
    return string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
end

-- ------------------------------------------------------------------------------
-- Card Database & Data Section Loader
-- ------------------------------------------------------------------------------
local function load_cards()
    local P = ctx.package
    if not P then return end

    local ok, r = pcall(function() return P:open_text("cards.txt", { max_line_bytes = 2048 }) end)
    if not ok or not r or type(r) == "string" then return end

    while true do
        local okl, l = pcall(function() return r:read_line() end)
        if not okl or not l then break end

        local key, name, up_kw, up_read, rev_kw, rev_read = l:match("^([%w_]+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)")
        if key and name then
            -- Single clean keywords
            local clean_up_kw = up_kw:match("^([^,]+)") or up_kw
            clean_up_kw = clean_up_kw:gsub("^%s+", ""):gsub("%s+$", "")
            clean_up_kw = clean_up_kw:sub(1,1):upper() .. clean_up_kw:sub(2)

            local clean_rev_kw = rev_kw:match("^([^,]+)") or rev_kw
            clean_rev_kw = clean_rev_kw:gsub("^%s+", ""):gsub("%s+$", "")
            clean_rev_kw = clean_rev_kw:sub(1,1):upper() .. clean_rev_kw:sub(2)

            -- Determine suit
            local s_prefix = key:sub(1,1)
            local suit = "major"
            if s_prefix == "w" then suit = "wands"
            elseif s_prefix == "c" then suit = "cups"
            elseif s_prefix == "s" then suit = "swords"
            elseif s_prefix == "p" then suit = "pentacles"
            end

            table.insert(cards, {
                key = key,
                name = name,
                up_kw = clean_up_kw,
                up_read = up_read,
                rev_kw = clean_rev_kw,
                rev_read = rev_read,
                suit = suit
            })
        end
    end
    pcall(function() r:close() end)
end

-- ------------------------------------------------------------------------------
-- Image Loader & Caching (Atkinson 1-bit PNGs from art_l1.txt / art_l2.txt)
-- ------------------------------------------------------------------------------
local PER_FILE = 39

local function read_art_line(num)
    local file_idx = math.floor((num - 1) / PER_FILE) + 1
    local file = "art_l" .. file_idx .. ".txt"
    local line_idx = ((num - 1) % PER_FILE) + 1

    local P = ctx.data or ctx.package
    if not P then return nil end

    local ok, r = pcall(function() return P:open_text(file, { max_line_bytes = 65536 }) end)
    if not ok or not r or type(r) == "string" then return nil end

    local line = nil
    pcall(function()
        for i = 1, line_idx do
            local l = r:read_line()
            if not l then break end
            line = l
        end
    end)
    pcall(function() r:close() end)
    return line and line:gsub("%s+$", "")
end

local function get_card_image(num)
    if image_cache[num] ~= nil then
        return image_cache[num]
    end

    if ctx.capabilities and ctx.capabilities.image_decode and ctx.image and ctx.base64 then
        local b64 = read_art_line(num)
        if b64 then
            local okb, bytes = pcall(function() return ctx.base64:decode(b64) end)
            if okb and bytes then
                local oki, img = pcall(function() return ctx.image:decode(bytes) end)
                if oki and img then
                    image_cache[num] = img
                    return img
                end
            end
        end
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- Typography & Centering Engine
-- ------------------------------------------------------------------------------
local function get_font(name)
    return ctx.fonts and ctx.fonts[name]
end

local function text_width(f, s)
    if f and f.measure then
        local ok, w = pcall(function() return f:measure(s) end)
        if ok and type(w) == "number" then return w end
    end
    return #s * 11
end

local function line_height(name)
    local f = get_font(name)
    if f and f.line_height then
        local ok, h = pcall(function() return f.line_height end)
        if ok and tonumber(h) then return tonumber(h) end
    end
    return (name == "large" and 30 or (name == "small" and 20 or 24))
end

local function draw_centered_text(g, y, text, font_name)
    local f = get_font(font_name)
    local w = text_width(f, text)
    local x = math.floor((W - w) / 2)
    g:text(x, y, text, { font = f })
end

local function wrap_lines(text, font_name, max_w)
    local f = get_font(font_name)
    local lines = {}
    local current_line = ""

    for word in text:gmatch("%S+") do
        local candidate = (current_line == "") and word or (current_line .. " " .. word)
        if text_width(f, candidate) <= max_w then
            current_line = candidate
        else
            if current_line ~= "" then
                table.insert(lines, current_line)
            end
            current_line = word
        end
    end
    if current_line ~= "" then
        table.insert(lines, current_line)
    end
    return lines
end

-- ------------------------------------------------------------------------------
-- Spread Generator
-- ------------------------------------------------------------------------------
local function generate_spread(spread_type)
    math.randomseed(os.time())
    local result = {}
    local chosen = {}

    local labels = {}
    local count = 3
    if spread_type == "cross" then
        count = 2
        labels = { "1. The Ground (Where You Stand)", "2. The Crossing (Challenge / Ally)" }
    else
        count = 3
        labels = { "1. The Root (Past)", "2. The Axis (Present)", "3. The Horizon (Future)" }
    end

    while #result < count do
        local idx = math.random(1, #cards)
        if not chosen[idx] then
            chosen[idx] = true
            local is_rev = state.reversals_enabled and (math.random(1, 100) <= 25) or false
            table.insert(result, {
                index = idx,
                reversed = is_rev,
                label = labels[#result + 1]
            })
        end
    end
    return result
end

-- ------------------------------------------------------------------------------
-- Drawing Components
-- ------------------------------------------------------------------------------

-- 1. Card Back: Double border, plus matrix & 8-spoke wheel
local function draw_card_back(g, x, y, w, h)
    g:rect(x, y, w, h, { line_width = 2, radius = 6 })
    g:rect(x + 6, y + 6, w - 12, h - 12, { line_width = 1 })

    local cx = x + math.floor(w / 2)
    local cy = y + math.floor(h / 2)
    local r_clear = 50

    local start_x = x + 22
    local end_x = x + w - 22
    local start_y = y + 24
    local end_y = y + h - 24

    for px = start_x, end_x, 24 do
        for py = start_y, end_y, 24 do
            local dx = px - cx
            local dy = py - cy
            if (dx * dx + dy * dy) > (r_clear * r_clear) then
                g:line(px - 3, py, px + 3, py, { width = 1 })
                g:line(px, py - 3, px, py + 3, { width = 1 })
            end
        end
    end

    -- 8-spoke sacred wheel
    g:circle(cx, cy, 44, { width = 2 })
    for angle = 0, 7 do
        local rad = angle * (math.pi / 4)
        local sx = cx + math.floor(44 * math.cos(rad) + 0.5)
        local sy = cy + math.floor(44 * math.sin(rad) + 0.5)
        g:line(cx, cy, sx, sy, { width = 2 })
    end
end

-- 2. Draw Card Artwork with Upside-Down Reversal Support
local function draw_card_artwork(g, card_idx, is_rev, x, y, w, h)
    local img = get_card_image(card_idx)
    local drawn = false

    if img then
        if is_rev then
            -- Attempt hardware rotation (API 2.0 image_transform)
            drawn = pcall(function() g:image(img, x, y, { rotate = 180 }) end)
        end
        if not drawn then
            drawn = pcall(function() g:image(img, x, y) end)
        end
    end

    if drawn then
        g:rect(x, y, w, h, { line_width = 1 })
        if is_rev then
            -- Display subtle badge if drawn upright on non-rotating hosts
            g:rect(x + w - 54, y + 6, 48, 20, { fill = 0 })
            g:text(x + w - 48, y + 8, "REV", { font = get_font("small"), color = 1 })
        end
    else
        -- Fallback framed label
        g:rect(x, y, w, h, { line_width = 2, radius = 6 })
        local c = cards[card_idx]
        if c then
            draw_centered_text(g, y + math.floor(h / 2) - 10, c.name, "medium")
        end
    end
end

-- 3. Top Status & Menu Bar
local function draw_top_bar(g, title_str)
    -- Menu Pill Button [ ≡ ]
    g:rect(20, 20, 48, 34, { line_width = 1, radius = 4 })
    g:text(34, 26, "≡", { font = get_font("large") })

    -- Mode Title
    draw_centered_text(g, 26, title_str, "medium")

    -- Subtle horizontal divider
    g:line(20, 62, 460, 62, { width = 1 })
end

-- ------------------------------------------------------------------------------
-- Screen Renders by Mode
-- ------------------------------------------------------------------------------

-- MODE 1: DAILY ORACLE
local function draw_daily_mode(g)
    draw_top_bar(g, "INKARCANA")

    local c = cards[state.daily_index]
    if not c then return end

    if state.daily_view == "waits" then
        draw_card_back(g, CARD_X, CARD_Y, CARD_W, CARD_H)
        draw_centered_text(g, 545, "THE CARD WAITS", "large")
        g:line(180, 585, 300, 585, { width = 2 })
        draw_centered_text(g, 615, "PRESS TO TURN", "large")
        g:text(125, 750, "[ Tap or side buttons to turn ]", { font = get_font("small") })

    elseif state.daily_view == "front" then
        draw_card_artwork(g, state.daily_index, state.daily_reversed, CARD_X, CARD_Y, CARD_W, CARD_H)

        local title_text = c.name .. (state.daily_reversed and " (Reversed)" or "")
        draw_centered_text(g, 545, title_text, "large")
        g:line(180, 585, 300, 585, { width = 2 })

        local kw = state.daily_reversed and c.rev_kw or c.up_kw
        draw_centered_text(g, 615, kw, "large")
        g:text(130, 750, "[ Tap card to unveil reading ]", { font = get_font("small") })

    elseif state.daily_view == "reading" then
        local title_text = c.name .. (state.daily_reversed and " (Reversed)" or "")
        draw_centered_text(g, 100, title_text, "large")
        g:line(180, 140, 300, 140, { width = 2 })

        local read_body = state.daily_reversed and c.rev_read or c.up_read
        local lines = wrap_lines(read_body, "medium", 360)
        local lh = line_height("medium") + 6
        local total_h = #lines * lh
        local start_y = math.floor(390 - (total_h / 2))

        for i, line in ipairs(lines) do
            local y = start_y + (i - 1) * lh
            draw_centered_text(g, y, line, "medium")
        end

        draw_centered_text(g, 700, "PRESS TO RETURN", "large")
    end
end

-- MODE 2: MULTI-CARD SPREADS
local function draw_spread_mode(g)
    local cur_entry = state.spread_cards[state.spread_pos]
    if not cur_entry then return end

    local c = cards[cur_entry.index]
    local is_rev = cur_entry.reversed

    draw_top_bar(g, cur_entry.label)

    -- Step Indicator (< 2/3 >)
    local count = #state.spread_cards
    local nav_text = string.format("< Card %d of %d >", state.spread_pos, count)
    draw_centered_text(g, 68, nav_text, "small")

    if state.spread_view == "front" then
        draw_card_artwork(g, cur_entry.index, is_rev, CARD_X, 100, CARD_W, CARD_H)

        local title_text = c.name .. (is_rev and " (Reversed)" or "")
        draw_centered_text(g, 555, title_text, "large")
        g:line(180, 595, 300, 595, { width = 2 })

        local kw = is_rev and c.rev_kw or c.up_kw
        draw_centered_text(g, 620, kw, "large")

        -- Bottom controls: [PREV] [FLIP] [NEXT]
        g:rect(30, 715, 110, 44, { line_width = 1, radius = 4 })
        g:text(55, 727, "< PREV", { font = get_font("small") })

        g:rect(170, 715, 140, 44, { line_width = 1, radius = 4 })
        g:text(195, 727, "READING", { font = get_font("small") })

        g:rect(340, 715, 110, 44, { line_width = 1, radius = 4 })
        g:text(370, 727, "NEXT >", { font = get_font("small") })

    else
        -- Spread Reading View
        local title_text = c.name .. (is_rev and " (Reversed)" or "")
        draw_centered_text(g, 120, title_text, "large")
        g:line(180, 155, 300, 155, { width = 2 })

        local read_body = is_rev and c.rev_read or c.up_read
        local lines = wrap_lines(read_body, "medium", 360)
        local lh = line_height("medium") + 6
        local total_h = #lines * lh
        local start_y = math.floor(380 - (total_h / 2))

        for i, line in ipairs(lines) do
            local y = start_y + (i - 1) * lh
            draw_centered_text(g, y, line, "medium")
        end

        g:rect(170, 715, 140, 44, { line_width = 1, radius = 4 })
        g:text(188, 727, "< CARD ART", { font = get_font("small") })
    end
end

-- MODE 3: TAROT LEARNING & FLASHCARD MODE
local function draw_study_mode(g)
    draw_top_bar(g, "TAROT STUDY & FLASHCARDS")

    local c = cards[state.study_index]
    if not c then return end

    -- Artwork always prominently visible
    draw_card_artwork(g, state.study_index, false, CARD_X, 85, CARD_W, CARD_H)

    if not state.study_revealed then
        -- Concealed Quiz state
        draw_centered_text(g, 545, "? ? ?  MYSTERY CARD  ? ? ?", "medium")
        g:line(180, 580, 300, 580, { width = 2 })

        g:rect(120, 615, 240, 50, { line_width = 2, radius = 6 })
        draw_centered_text(g, 630, "TAP TO REVEAL", "large")

        g:text(95, 750, "[ Test your visual recall of RWS archetypes ]", { font = get_font("small") })

    else
        -- Answer & Symbol Breakdown Revealed
        draw_centered_text(g, 530, c.name, "large")
        g:line(160, 560, 320, 560, { width = 1 })

        local info_line = "Upright: " .. c.up_kw .. "  |  Shadow: " .. c.rev_kw
        draw_centered_text(g, 575, info_line, "small")

        -- 2-line condensed meaning
        local lines = wrap_lines(c.up_read, "small", 380)
        local y = 605
        for i = 1, math.min(2, #lines) do
            draw_centered_text(g, y, lines[i], "small")
            y = y + 22
        end

        -- Bottom controls: [ < PREV ] [ SHUFFLE ] [ NEXT > ]
        g:rect(30, 715, 110, 44, { line_width = 1, radius = 4 })
        g:text(55, 727, "< PREV", { font = get_font("small") })

        g:rect(160, 715, 160, 44, { line_width = 1, radius = 4 })
        g:text(180, 727, "RANDOM CARD", { font = get_font("small") })

        g:rect(340, 715, 110, 44, { line_width = 1, radius = 4 })
        g:text(370, 727, "NEXT >", { font = get_font("small") })
    end
end

-- MODE 4: STANDBY / DESK ALTAR MODE (ZERO POWER DISPLAY)
local function draw_altar_mode(g)
    local c = cards[state.daily_index]
    if not c then return end

    -- Clean Top Altar Header
    local date_str = get_formatted_date()
    g:line(40, 35, 440, 35, { width = 1 })
    draw_centered_text(g, 45, "* INKARCANA ALTAR *", "medium")
    draw_centered_text(g, 72, date_str, "small")
    g:line(40, 95, 440, 95, { width = 1 })

    -- Center Artwork
    draw_card_artwork(g, state.daily_index, state.daily_reversed, CARD_X, 125, CARD_W, CARD_H)

    -- Card Name & Single Keyword
    local title_text = c.name .. (state.daily_reversed and " (Reversed)" or "")
    draw_centered_text(g, 580, title_text, "large")
    g:line(180, 620, 300, 620, { width = 2 })

    local kw = state.daily_reversed and c.rev_kw or c.up_kw
    draw_centered_text(g, 645, kw, "large")

    -- Subtle Desk Altar notice
    g:line(60, 725, 420, 725, { width = 1 })
    draw_centered_text(g, 745, "[ Desk Altar Active - Zero E-Ink Drain - Tap to Exit ]", "small")
end

-- 5. OVERLAY MENU DRAWER
local function draw_menu(g)
    -- Darkened / framed modal box
    g:rect(30, 60, 420, 680, { fill = 1, line_width = 3, radius = 12 })
    g:rect(36, 66, 408, 668, { line_width = 1, radius = 8 })

    draw_centered_text(g, 90, "ORACLE COMPANION", "large")
    g:line(60, 130, 420, 130, { width = 2 })

    local menu_items = {
        { id = "daily", label = "1. Daily Oracle Ritual" },
        { id = "spread_triad", label = "2. Three-Card Triad Spread" },
        { id = "spread_cross", label = "3. Two-Card Cross Spread" },
        { id = "study", label = "4. Tarot Study & Flashcards" },
        { id = "altar", label = "5. Desk Altar (Standby Mode)" },
        { id = "toggle_rev", label = "6. Shadow Reversals: " .. (state.reversals_enabled and "[ ON ]" or "[ OFF ]") }
    }

    local y = 160
    for _, item in ipairs(menu_items) do
        g:rect(55, y, 370, 54, { line_width = 1, radius = 6 })
        g:text(75, y + 17, item.label, { font = get_font("medium") })
        y = y + 70
    end

    -- Disclaimer & Attribution
    draw_centered_text(g, 582, "Unofficial tribute inspired by pocketoracle.org", "small")
    draw_centered_text(g, 604, "Not affiliated with Pocket Oracle or Hiroic Ventures", "small")

    -- Close Menu Button
    g:rect(140, 640, 200, 50, { line_width = 2, radius = 8 })
    draw_centered_text(g, 655, "CLOSE MENU", "medium")
end

-- ------------------------------------------------------------------------------
-- Lifecycle Callbacks
-- ------------------------------------------------------------------------------

function on_load(ctx)
    load_cards()

    local today_day = get_epoch_day()
    state.last_day = today_day

    -- Deterministic card of the day
    local s = (today_day * 2654435761) % 2147483648
    state.daily_index = (s % #cards) + 1
    state.daily_reversed = state.reversals_enabled and (((s // 78) % 100) <= 25) or false

    -- Initialize spreads
    state.spread_cards = generate_spread("triad")

    -- Restore saved state
    if ctx and ctx.state then
        if ctx.state.last_day == today_day then
            state.has_turned_today = ctx.state.has_turned_today or false
            state.daily_view = ctx.state.daily_view or (state.has_turned_today and "front" or "waits")
            if ctx.state.daily_index then state.daily_index = ctx.state.daily_index end
            if ctx.state.daily_reversed ~= nil then state.daily_reversed = ctx.state.daily_reversed end
        end
        if ctx.state.reversals_enabled ~= nil then
            state.reversals_enabled = ctx.state.reversals_enabled
        end
    end

    if not state.has_turned_today then
        state.daily_view = "waits"
    end
end

function on_draw(ctx, g)
    g:rect(0, 0, W, H, { fill = 1 })

    if state.mode == "daily" then
        draw_daily_mode(g)
    elseif state.mode == "spread" then
        draw_spread_mode(g)
    elseif state.mode == "study" then
        draw_study_mode(g)
    elseif state.mode == "altar" then
        draw_altar_mode(g)
    end

    if state.menu_open then
        draw_menu(g)
    end
end

function on_input(ctx, event)
    if not event then return end

    local x, y = event.x, event.y
    local is_tap = (event.type == "down")

    -- Key navigation
    local is_prev, is_next, is_trigger = false, false, false
    if event.type == "key" and event.phase ~= "up" then
        local key = event.key
        if key == "ok" or key == "enter" or key == "space" then is_trigger = true
        elseif key == "left" or key == "up" then is_prev = true
        elseif key == "right" or key == "down" then is_next = true
        elseif key == "menu" then state.menu_open = not state.menu_open; return
        end
    end

    -- --------------------------------------------------------------------------
    -- 1. MENU OVERLAY INTERACTION
    -- --------------------------------------------------------------------------
    if state.menu_open then
        if is_tap then
            -- Item 1: Daily
            if y >= 160 and y <= 214 then
                state.mode = "daily"
                state.menu_open = false
            -- Item 2: Triad Spread
            elseif y >= 230 and y <= 284 then
                state.mode = "spread"
                state.spread_type = "triad"
                state.spread_cards = generate_spread("triad")
                state.spread_pos = 1
                state.spread_view = "front"
                state.menu_open = false
            -- Item 3: Cross Spread
            elseif y >= 300 and y <= 354 then
                state.mode = "spread"
                state.spread_type = "cross"
                state.spread_cards = generate_spread("cross")
                state.spread_pos = 1
                state.spread_view = "front"
                state.menu_open = false
            -- Item 4: Study
            elseif y >= 370 and y <= 424 then
                state.mode = "study"
                state.study_revealed = false
                state.menu_open = false
            -- Item 5: Desk Altar
            elseif y >= 440 and y <= 494 then
                state.mode = "altar"
                state.menu_open = false
            -- Item 6: Toggle Reversals
            elseif y >= 510 and y <= 564 then
                state.reversals_enabled = not state.reversals_enabled
            -- Close Button or outside tap
            elseif (y >= 640 and y <= 690) or (x < 30 or x > 450 or y < 60 or y > 740) then
                state.menu_open = false
            end
        end
        return
    end

    -- Menu button tap (top-left)
    if is_tap and x >= 15 and x <= 75 and y >= 15 and y <= 60 then
        state.menu_open = true
        return
    end

    -- --------------------------------------------------------------------------
    -- 2. DESK ALTAR MODE (Tap anywhere to return)
    -- --------------------------------------------------------------------------
    if state.mode == "altar" then
        if is_tap or is_trigger then
            state.mode = "daily"
        end
        return
    end

    -- --------------------------------------------------------------------------
    -- 3. DAILY ORACLE MODE
    -- --------------------------------------------------------------------------
    if state.mode == "daily" then
        -- Side keys browse cards
        if is_prev then
            state.daily_index = ((state.daily_index - 2 + #cards) % #cards) + 1
            state.daily_view = "front"
            state.has_turned_today = true
            return
        elseif is_next then
            state.daily_index = (state.daily_index % #cards) + 1
            state.daily_view = "front"
            state.has_turned_today = true
            return
        end

        if is_tap or is_trigger then
            if state.daily_view == "waits" then
                state.daily_view = "front"
                state.has_turned_today = true
            elseif state.daily_view == "front" then
                state.daily_view = "reading"
            elseif state.daily_view == "reading" then
                state.daily_view = "front"
            end
        end
        return
    end

    -- --------------------------------------------------------------------------
    -- 4. MULTI-CARD SPREADS MODE
    -- --------------------------------------------------------------------------
    if state.mode == "spread" then
        local count = #state.spread_cards
        if is_prev or (is_tap and x >= 30 and x <= 140 and y >= 710 and y <= 765) then
            state.spread_pos = ((state.spread_pos - 2 + count) % count) + 1
            state.spread_view = "front"
            return
        elseif is_next or (is_tap and x >= 340 and x <= 450 and y >= 710 and y <= 765) then
            state.spread_pos = (state.spread_pos % count) + 1
            state.spread_view = "front"
            return
        elseif (is_tap and x >= 170 and x <= 310 and y >= 710 and y <= 765) or is_trigger then
            state.spread_view = (state.spread_view == "front") and "reading" or "front"
            return
        end

        -- Tapping card body toggles reading
        if is_tap and x >= CARD_X and x <= CARD_X + CARD_W and y >= 100 and y <= 100 + CARD_H then
            state.spread_view = (state.spread_view == "front") and "reading" or "front"
        end
        return
    end

    -- --------------------------------------------------------------------------
    -- 5. TAROT LEARNING & FLASHCARD MODE
    -- --------------------------------------------------------------------------
    if state.mode == "study" then
        if not state.study_revealed then
            -- Tap anywhere on center to reveal
            if is_tap or is_trigger then
                state.study_revealed = true
            end
        else
            -- Bottom buttons: Prev, Shuffle, Next
            if is_prev or (is_tap and x >= 30 and x <= 140 and y >= 710 and y <= 765) then
                state.study_index = ((state.study_index - 2 + #cards) % #cards) + 1
                state.study_revealed = false
            elseif is_next or (is_tap and x >= 340 and x <= 450 and y >= 710 and y <= 765) then
                state.study_index = (state.study_index % #cards) + 1
                state.study_revealed = false
            elseif is_tap and x >= 160 and x <= 320 and y >= 710 and y <= 765 then
                state.study_index = math.random(1, #cards)
                state.study_revealed = false
            end
        end
    end
end

function on_leave(ctx)
    if ctx then
        ctx.state = {
            last_day = state.last_day,
            daily_index = state.daily_index,
            daily_reversed = state.daily_reversed,
            daily_view = state.daily_view,
            has_turned_today = state.has_turned_today,
            reversals_enabled = state.reversals_enabled
        }
    end
end
