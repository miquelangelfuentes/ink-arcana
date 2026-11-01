-- InkArcana for XTEINK X4 Pro / XTOS Licorice API 2.x
-- Study mode v1.3: card-first learning with upright and reversed meanings.
-- Designed for the API 2.9 host observed on firmware 26102301 / 26102401.
-- The app is fully offline. Tarot is presented as a reflective prompt, not a prediction.

local W, H = 480, 800
local CARD_W, CARD_H = 240, 418
local CARD_X, CARD_Y = 120, 84
local HEADER_MENU_X, HEADER_MENU_Y = 14, 16
local HEADER_MENU_W, HEADER_MENU_H = 78, 36
local HEADER_RULE_Y = 64
local PER_FILE = 39
local MAX_IMAGES = 4
local KEY_GAP_MS = 250

local cards = {}
local image_cache, image_order = {}, {}
local ERR = nil

local state = {
    mode = "daily",          -- daily / spread / study / altar
    daily_view = "waits",    -- waits / front / reading
    daily_index = 1,
    daily_reversed = false,
    daily_day = nil,
    has_turned_today = false,
    reversals_enabled = true,
    spread_type = "triad",
    spread_cards = {},
    spread_pos = 1,
    spread_view = "front",
    study_index = 1,
    study_revealed = false,
    menu_open = false,
}

local last_key, last_key_ms = nil, nil

local function refresh()
    pcall(function() ctx:invalidate() end)
end

local function save_state()
    if not ctx then return end
    ctx.state = {
        daily_day = state.daily_day,
        daily_index = state.daily_index,
        daily_reversed = state.daily_reversed,
        daily_view = state.daily_view,
        has_turned_today = state.has_turned_today,
        reversals_enabled = state.reversals_enabled,
        study_index = state.study_index,
    }
    pcall(function() ctx:save_state() end)
end

local function local_day()
    local ok, t = pcall(function() return ctx.clock:now() end)
    if not ok or type(t) ~= "table" or not tonumber(t.epoch_sec) then
        return 20760
    end
    local epoch = math.floor(tonumber(t.epoch_sec))
    local wall = (tonumber(t.hour) or 0) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
    local off = (wall - (epoch % 86400)) % 86400
    if off > 14 * 3600 then off = off - 86400 end
    return math.floor((epoch + off) / 86400)
end

local function formatted_date()
    local ok, t = pcall(function() return ctx.clock:now() end)
    if ok and type(t) == "table" and t.year and t.month and t.day then
        return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
    end
    return "Today"
end

local function random_int(n)
    if n <= 1 then return 1 end
    if ctx and ctx.random and ctx.random.bytes then
        local ok, b = pcall(function() return ctx.random:bytes(4) end)
        if ok and type(b) == "string" and #b >= 4 then
            local v = ((b:byte(1) * 256 + b:byte(2)) * 256 + b:byte(3)) * 256 + b:byte(4)
            return (v % n) + 1
        end
    end
    return math.random(n)
end

local function random_reversed()
    return state.reversals_enabled and random_int(100) <= 25
end

local function parse_card_line(line)
    local key, name, up_kw, up_read, rev_kw, rev_read =
        line:match("^([%w_]+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
    if not key then return nil end
    local suit = "major"
    local prefix = key:sub(1, 1)
    if prefix == "w" then suit = "wands"
    elseif prefix == "c" then suit = "cups"
    elseif prefix == "s" then suit = "swords"
    elseif prefix == "p" then suit = "pentacles" end
    return {
        key = key, name = name, up_kw = up_kw, up_read = up_read,
        rev_kw = rev_kw, rev_read = rev_read, suit = suit
    }
end

local function load_cards()
    cards = {}
    local P = ctx and ctx.package
    if not P or not P.open_text then return end
    local ok, r = pcall(function() return P:open_text("cards.txt", { max_line_bytes = 4096 }) end)
    if not ok or not r or type(r) == "string" then return end
    while true do
        local okl, line = pcall(function() return r:read_line() end)
        if not okl or not line then break end
        local card = parse_card_line(line)
        if card then cards[#cards + 1] = card end
    end
    pcall(function() r:close() end)
end

local function release_image(img)
    if img then pcall(function() img:release() end) end
end

local function release_cache()
    for _, id in ipairs(image_order) do release_image(image_cache[id]) end
    image_cache, image_order = {}, {}
end

local function touch_cache(id)
    for i, v in ipairs(image_order) do
        if v == id then table.remove(image_order, i); break end
    end
    image_order[#image_order + 1] = id
end

local function cache_put(id, img)
    while #image_order >= MAX_IMAGES do
        local old = table.remove(image_order, 1)
        release_image(image_cache[old])
        image_cache[old] = nil
    end
    image_cache[id] = img or false
    touch_cache(id)
end

local function read_art_line(num)
    local file_idx = math.floor((num - 1) / PER_FILE) + 1
    local line_idx = ((num - 1) % PER_FILE) + 1
    local P = ctx and ctx.package
    if not P or not P.open_text then return nil end
    local filename = "art_l" .. file_idx .. ".txt"
    local ok, r = pcall(function() return P:open_text(filename, { max_line_bytes = 65536 }) end)
    if not ok or not r or type(r) == "string" then return nil end
    local line = nil
    pcall(function()
        for _ = 1, line_idx do
            line = r:read_line()
            if not line then break end
        end
    end)
    pcall(function() r:close() end)
    return line and line:gsub("%s+$", "") or nil
end

local function get_card_image(num)
    if image_cache[num] ~= nil then
        touch_cache(num)
        return image_cache[num] or nil
    end
    if not (ctx and ctx.capabilities and ctx.capabilities.image_decode and ctx.image and ctx.base64) then
        cache_put(num, false)
        return nil
    end
    local b64 = read_art_line(num)
    if not b64 then
        cache_put(num, false)
        return nil
    end
    local okb, bytes = pcall(function() return ctx.base64:decode(b64) end)
    if not okb or not bytes then
        cache_put(num, false)
        return nil
    end
    local oki, img = pcall(function()
        return ctx.image:decode(bytes, { max_w = CARD_W, max_h = CARD_H })
    end)
    if not oki or not img then
        cache_put(num, false)
        return nil
    end
    cache_put(num, img)
    return img
end

local function font(name)
    return ctx and ctx.fonts and ctx.fonts[name]
end

local function text_width(f, s)
    if f then
        local ok, w = pcall(function() return f:measure(s) end)
        if ok and tonumber(w) then return tonumber(w) end
    end
    return #tostring(s) * 11
end

local function line_height(name)
    local f = font(name)
    if f then
        local ok, h = pcall(function() return f.line_height end)
        if ok and tonumber(h) then return tonumber(h) end
    end
    return name == "large" and 30 or name == "small" and 20 or 24
end

local function centered(gg, y, s, fname)
    local f = font(fname)
    local x = math.floor((W - text_width(f, s)) / 2)
    gg:text(x, y, s, { font = f })
end

local function wrap(s, fname, max_w)
    local f = font(fname)
    local out, line = {}, ""
    for word in tostring(s):gmatch("[^ \t]+") do
        local cand = line == "" and word or (line .. " " .. word)
        if line ~= "" and text_width(f, cand) > max_w then
            out[#out + 1] = line
            line = word
        else
            line = cand
        end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
end

local function paragraph(gg, y, s, fname, max_w, bottom)
    local lh = line_height(fname) + 5
    for _, line in ipairs(wrap(s, fname, max_w)) do
        if y + lh > bottom then break end
        centered(gg, y, line, fname)
        y = y + lh
    end
    return y
end

local function button(gg, x, y, w, h, label, fname)
    gg:rect(x, y, w, h, { line_width = 1 })
    local chosen = fname or "small"
    local f = font(chosen)
    local tw = text_width(f, label)
    if tw > w - 12 and chosen ~= "small" then
        chosen = "small"
        f = font(chosen)
        tw = text_width(f, label)
    end
    local tx = x + math.floor((w - tw) / 2)
    if tx < x + 4 then tx = x + 4 end
    local ty = y + math.max(1, math.floor((h - line_height(chosen)) / 2))
    gg:text(tx, ty, label, { font = f })
end

local function draw_card_back(gg, x, y, w, h)
    gg:rect(x, y, w, h, { line_width = 2 })
    gg:rect(x + 8, y + 8, w - 16, h - 16, { line_width = 1 })
    gg:rect(x + 14, y + 14, w - 28, h - 28, { line_width = 1 })
    local cx, cy = x + math.floor(w / 2), y + math.floor(h / 2)
    local r = 42
    gg:line(cx, cy - r, cx + r, cy, { width = 1 })
    gg:line(cx + r, cy, cx, cy + r, { width = 1 })
    gg:line(cx, cy + r, cx - r, cy, { width = 1 })
    gg:line(cx - r, cy, cx, cy - r, { width = 1 })
    gg:circle(cx, cy, 27, { line_width = 1 })
    gg:circle(cx, cy, 6, { line_width = 1 })
end

local function draw_card_art(gg, idx, reversed, x, y, w, h)
    local img = get_card_image(idx)
    local drawn = false
    if img then
        if reversed and ctx.capabilities and ctx.capabilities.image_transform then
            drawn = pcall(function() gg:image(img, x, y, { rotate = 180 }) end)
        end
        if not drawn then drawn = pcall(function() gg:image(img, x, y) end) end
    end
    if not drawn then
        gg:rect(x, y, w, h, { line_width = 2 })
        local c = cards[idx]
        if c then centered(gg, y + math.floor(h / 2) - 12, c.name, "medium") end
    else
        gg:rect(x, y, w, h, { line_width = 1 })
    end
end

local function title_bar(gg, title)
    button(gg, HEADER_MENU_X, HEADER_MENU_Y, HEADER_MENU_W, HEADER_MENU_H, "MENU", "small")
    local left = HEADER_MENU_X + HEADER_MENU_W + 12
    local right = W - 14
    local available = right - left

    local function region_text(y, text, fname)
        local f = font(fname)
        local tw = text_width(f, text)
        local tx = left + math.max(0, math.floor((available - tw) / 2))
        gg:text(tx, y, text, { font = f })
    end

    -- Spread headings are deliberately split instead of relying on font metrics.
    -- This keeps them clear of MENU on the physical X4 Pro display.
    if title:find("CARD REFLECTION", 1, true) then
        local first = title:gsub(" REFLECTION$", "")
        region_text(11, first, "small")
        region_text(35, "REFLECTION", "small")
    else
        local title_font = "medium"
        if text_width(font(title_font), title) > available then
            title_font = "small"
        end
        region_text(22, title, title_font)
    end

    gg:line(14, HEADER_RULE_Y, W - 14, HEADER_RULE_Y, { width = 1 })
end

local function draw_reading(gg, c, reversed, title)
    centered(gg, 92, title, "small")
    local card_font = text_width(font("large"), c.name) > 420 and "medium" or "large"
    centered(gg, 126, c.name, card_font)
    local kw_y = 188
    if reversed then
        centered(gg, 168, "REVERSED", "small")
        kw_y = 202
    end
    local kw = reversed and c.rev_kw or c.up_kw
    centered(gg, kw_y, kw, "medium")
    gg:line(100, 238, 380, 238, { width = 1 })
    local body = reversed and c.rev_read or c.up_read
    paragraph(gg, 274, body, "medium", 400, 650)
    gg:line(150, 686, 330, 686, { width = 1 })
    centered(gg, 708, "Tap to return to the card", "small")
end

local function draw_daily(gg)
    title_bar(gg, "INKARCANA")
    if #cards == 0 then
        centered(gg, 180, "Card data is missing from the package.", "medium")
        return
    end
    local c = cards[state.daily_index]
    if state.daily_view == "waits" then
        draw_card_back(gg, CARD_X, CARD_Y, CARD_W, CARD_H)
        centered(gg, 542, "The card waits", "large")
        centered(gg, 594, "Tap to turn today's card", "medium")
    elseif state.daily_view == "front" then
        draw_card_art(gg, state.daily_index, state.daily_reversed, CARD_X, CARD_Y, CARD_W, CARD_H)
        centered(gg, 538, c.name, "large")
        local kw_y = 590
        if state.daily_reversed then
            centered(gg, 576, "REVERSED", "small")
            kw_y = 610
        end
        centered(gg, kw_y, state.daily_reversed and c.rev_kw or c.up_kw, "medium")
        gg:line(145, 650, 335, 650, { width = 1 })
        centered(gg, 700, "Tap the card to reflect", "small")
    else
        draw_reading(gg, c, state.daily_reversed, "TODAY'S CARD")
    end
end

local function spread_label(entry)
    return entry and entry.label or "Spread"
end

local function draw_spread(gg)
    title_bar(gg, state.spread_type == "triad" and "THREE-CARD REFLECTION" or "TWO-CARD REFLECTION")
    local entry = state.spread_cards[state.spread_pos]
    if not entry then
        centered(gg, 200, "Choose a new spread from the menu.", "medium")
        return
    end
    local c = cards[entry.index]
    if state.spread_view == "reading" then
        draw_reading(gg, c, entry.reversed, spread_label(entry))
        return
    end
    local position = string.format("%d / %d   %s", state.spread_pos, #state.spread_cards, spread_label(entry))
    centered(gg, 76, position, "small")
    draw_card_art(gg, entry.index, entry.reversed, CARD_X, 105, CARD_W, CARD_H)
    centered(gg, 548, c.name, "large")
    local kw_y = 592
    if entry.reversed then
        centered(gg, 580, "REVERSED", "small")
        kw_y = 612
    end
    centered(gg, kw_y, entry.reversed and c.rev_kw or c.up_kw, "medium")
    gg:line(145, 650, 335, 650, { width = 1 })
    button(gg, 24, 718, 118, 48, "PREV", "small")
    button(gg, 168, 718, 144, 48, "REFLECT", "small")
    button(gg, 338, 718, 118, 48, "NEXT", "small")
end

local function draw_study(gg)
    title_bar(gg, "STUDY")
    if #cards == 0 then return end
    local c = cards[state.study_index]
    centered(gg, 72, string.format("%d / %d", state.study_index, #cards), "small")

    if not state.study_revealed then
        draw_card_art(gg, state.study_index, false, CARD_X, 96, CARD_W, CARD_H)
        local card_font = text_width(font("large"), c.name) > 420 and "medium" or "large"
        centered(gg, 530, c.name, card_font)
        centered(gg, 575, c.up_kw, "medium")
        gg:line(145, 620, 335, 620, { width = 1 })
        centered(gg, 650, "Tap for meaning", "small")
    else
        local card_font = text_width(font("large"), c.name) > 420 and "medium" or "large"
        centered(gg, 104, c.name, card_font)

        centered(gg, 150, "UPRIGHT", "small")
        centered(gg, 178, c.up_kw, "medium")
        gg:line(100, 214, 380, 214, { width = 1 })
        paragraph(gg, 235, c.up_read, "small", 390, 365)

        gg:line(100, 390, 380, 390, { width = 1 })
        centered(gg, 410, "REVERSED", "small")
        centered(gg, 438, c.rev_kw, "medium")
        gg:line(100, 475, 380, 475, { width = 1 })
        paragraph(gg, 495, c.rev_read, "small", 390, 670)
        centered(gg, 684, "Tap to return to card", "small")
    end

    button(gg, 24, 718, 118, 48, "PREV", "small")
    button(gg, 168, 718, 144, 48, "RANDOM", "small")
    button(gg, 338, 718, 118, 48, "NEXT", "small")
end

local function draw_altar(gg)
    if #cards == 0 then return end
    local c = cards[state.daily_index]
    centered(gg, 22, "INKARCANA", "medium")
    centered(gg, 52, formatted_date(), "small")
    gg:line(155, 79, 325, 79, { width = 1 })
    draw_card_art(gg, state.daily_index, state.daily_reversed, CARD_X, 100, CARD_W, CARD_H)
    centered(gg, 555, c.name, "large")
    local kw_y = 605
    if state.daily_reversed then
        centered(gg, 590, "REVERSED", "small")
        kw_y = 625
    end
    centered(gg, kw_y, state.daily_reversed and c.rev_kw or c.up_kw, "medium")
    gg:line(155, 665, 325, 665, { width = 1 })
    centered(gg, 742, "Tap anywhere to leave altar mode", "small")
end

local MENU_ITEMS = {
    { "Daily card", "daily" },
    { "Three-card reflection", "triad" },
    { "Two-card reflection", "cross" },
    { "Study the deck", "study" },
    { "Desk altar", "altar" },
}

local function menu_row(gg, y, label)
    local x, w, h = 45, 390, 58
    gg:text(x + 14, y + 17, label, { font = font("medium") })
    local ax, ay = x + w - 18, y + math.floor(h / 2)
    gg:line(ax - 5, ay - 5, ax, ay, { width = 1 })
    gg:line(ax, ay, ax - 5, ay + 5, { width = 1 })
    gg:line(x, y + h - 1, x + w, y + h - 1, { width = 1 })
end

local function draw_menu(gg)
    centered(gg, 30, "INKARCANA", "large")
    centered(gg, 76, "A quiet space for reflection", "small")
    gg:line(45, 111, 435, 111, { width = 1 })
    local y = 125
    for _, item in ipairs(MENU_ITEMS) do
        menu_row(gg, y, item[1])
        y = y + 75
    end
    gg:text(59, y + 17, "Reversed cards", { font = font("medium") })
    button(gg, 349, y + 14, 72, 30, state.reversals_enabled and "ON" or "OFF", "small")
    gg:line(45, y + 57, 435, y + 57, { width = 1 })
    y = y + 75
    button(gg, 140, y, 200, 52, "CLOSE", "medium")
end

local function generate_spread(kind)
    local labels = kind == "cross"
        and { "Where you stand", "What meets you" }
        or { "What shaped this", "Where you are", "What may emerge" }
    local count = math.min(#labels, #cards)
    local chosen, out = {}, {}
    local attempts = 0
    while #out < count and attempts < 200 do
        attempts = attempts + 1
        local idx = random_int(#cards)
        if not chosen[idx] then
            chosen[idx] = true
            out[#out + 1] = { index = idx, reversed = random_reversed(), label = labels[#out + 1] }
        end
    end
    return out
end

local function begin_spread(kind)
    state.mode = "spread"
    state.spread_type = kind
    state.spread_cards = generate_spread(kind)
    state.spread_pos = 1
    state.spread_view = "front"
    state.menu_open = false
end

local function key_accepted(ev)
    local phase = ev.phase or ev.state
    if phase == "up" or phase == "release" or ev.pressed == false or ev.down == false then return false end
    local t = tonumber(ev.time_ms)
    if not t and ctx and ctx.clock and ctx.clock.millis then
        local ok, ms = pcall(function() return ctx.clock:millis() end)
        if ok then t = tonumber(ms) end
    end
    if t and last_key == ev.key and last_key_ms and t - last_key_ms >= 0 and t - last_key_ms < KEY_GAP_MS then
        return false
    end
    last_key, last_key_ms = ev.key, t
    return true
end

local function handle_menu_tap(x, y)
    local top, row = 125, 75
    for i, item in ipairs(MENU_ITEMS) do
        local yy = top + (i - 1) * row
        if x >= 45 and x <= 435 and y >= yy and y <= yy + 58 then
            local id = item[2]
            if id == "daily" then
                state.mode = "daily"; state.menu_open = false
            elseif id == "triad" or id == "cross" then
                begin_spread(id)
            elseif id == "study" then
                state.mode = "study"; state.study_revealed = false; state.menu_open = false
            elseif id == "altar" then
                state.mode = "altar"; state.menu_open = false
            end
            return
        end
    end
    local rev_y = top + #MENU_ITEMS * row
    if x >= 45 and x <= 435 and y >= rev_y and y <= rev_y + 58 then
        state.reversals_enabled = not state.reversals_enabled
        save_state()
        return
    end
    local close_y = rev_y + row
    if x >= 140 and x <= 340 and y >= close_y and y <= close_y + 52 then
        state.menu_open = false
    end
end

local function handle_tap(x, y)
    if state.menu_open then
        handle_menu_tap(x, y)
        refresh()
        return
    end
    if x >= HEADER_MENU_X and x <= HEADER_MENU_X + HEADER_MENU_W and y >= HEADER_MENU_Y and y <= HEADER_MENU_Y + HEADER_MENU_H and state.mode ~= "altar" then
        state.menu_open = true
        refresh()
        return
    end
    if state.mode == "altar" then
        state.mode = "daily"
        refresh()
        return
    end
    if state.mode == "daily" then
        if state.daily_view == "waits" then
            state.daily_view = "front"
            state.has_turned_today = true
            save_state()
        elseif state.daily_view == "front" and x >= CARD_X and x <= CARD_X + CARD_W and y >= CARD_Y and y <= CARD_Y + CARD_H then
            state.daily_view = "reading"
            save_state()
        elseif state.daily_view == "reading" then
            state.daily_view = "front"
            save_state()
        end
        refresh()
        return
    end
    if state.mode == "spread" then
        local count = #state.spread_cards
        if count == 0 then return end
        if y >= 718 and y <= 766 and x >= 24 and x <= 142 then
            state.spread_pos = ((state.spread_pos - 2 + count) % count) + 1
            state.spread_view = "front"
        elseif y >= 718 and y <= 766 and x >= 338 and x <= 456 then
            state.spread_pos = (state.spread_pos % count) + 1
            state.spread_view = "front"
        elseif y >= 718 and y <= 766 and x >= 168 and x <= 312 then
            state.spread_view = state.spread_view == "front" and "reading" or "front"
        elseif state.spread_view == "reading" then
            state.spread_view = "front"
        elseif x >= CARD_X and x <= CARD_X + CARD_W and y >= 105 and y <= 105 + CARD_H then
            state.spread_view = "reading"
        end
        refresh()
        return
    end
    if state.mode == "study" then
        if y >= 718 and y <= 766 and x >= 24 and x <= 142 then
            state.study_index = ((state.study_index - 2 + #cards) % #cards) + 1
            state.study_revealed = false
        elseif y >= 718 and y <= 766 and x >= 338 and x <= 456 then
            state.study_index = (state.study_index % #cards) + 1
            state.study_revealed = false
        elseif y >= 718 and y <= 766 and x >= 168 and x <= 312 then
            state.study_index = random_int(#cards)
            state.study_revealed = false
        elseif state.study_revealed then
            state.study_revealed = false
        elseif x >= CARD_X and x <= CARD_X + CARD_W and y >= 96 and y <= 96 + CARD_H then
            state.study_revealed = true
        end
        refresh()
    end
end

local function handle_key(ev)
    if not key_accepted(ev) then return end
    local key = ev.key
    if key == "back" then
        if state.menu_open then state.menu_open = false
        elseif state.mode ~= "daily" then state.mode = "daily"
        elseif state.daily_view == "reading" then state.daily_view = "front"
        end
        refresh()
        return
    end
    if key == "ok" or key == "enter" then
        if state.mode == "daily" then
            if state.daily_view == "waits" then
                state.daily_view = "front"; state.has_turned_today = true
            elseif state.daily_view == "front" then state.daily_view = "reading"
            else state.daily_view = "front" end
            save_state()
        elseif state.mode == "spread" and #state.spread_cards > 0 then
            state.spread_view = state.spread_view == "front" and "reading" or "front"
        elseif state.mode == "study" then
            state.study_revealed = not state.study_revealed
        end
        refresh()
        return
    end
    local d = (key == "right" or key == "down") and 1 or ((key == "left" or key == "up") and -1 or 0)
    if d == 0 then return end
    if state.mode == "spread" and #state.spread_cards > 0 then
        local n = #state.spread_cards
        state.spread_pos = ((state.spread_pos - 1 + d) % n) + 1
        state.spread_view = "front"
    elseif state.mode == "study" and #cards > 0 then
        state.study_index = ((state.study_index - 1 + d) % #cards) + 1
        state.study_revealed = false
    elseif state.mode == "daily" and #cards > 0 then
        if state.daily_view == "waits" then
            state.daily_view = "front"
            state.has_turned_today = true
        elseif state.daily_view == "front" then
            state.daily_view = "reading"
        else
            state.daily_view = "front"
        end
        save_state()
    end
    refresh()
end

function on_load(c)
    ERR = nil
    local ok, e = pcall(function()
        load_cards()
        local saved = c and c.state or (ctx and ctx.state)
        if type(saved) == "table" and saved.reversals_enabled ~= nil then
            state.reversals_enabled = saved.reversals_enabled
        end
        local today = local_day()
        state.daily_day = today
        if #cards > 0 then
            local hash = (today * 2654435761) % 2147483648
            state.daily_index = (hash % #cards) + 1
            state.daily_reversed = state.reversals_enabled and (((math.floor(hash / 78)) % 100) < 25) or false
        end
        if type(saved) == "table" then
            if saved.study_index and #cards > 0 then
                state.study_index = math.max(1, math.min(#cards, tonumber(saved.study_index) or 1))
            end
            if saved.daily_day == today then
                if saved.daily_index and #cards > 0 then
                    state.daily_index = math.max(1, math.min(#cards, tonumber(saved.daily_index) or state.daily_index))
                end
                if saved.daily_reversed ~= nil then state.daily_reversed = saved.daily_reversed end
                state.has_turned_today = saved.has_turned_today == true
                state.daily_view = saved.daily_view or (state.has_turned_today and "front" or "waits")
            end
        end
        if not state.has_turned_today then state.daily_view = "waits" end
        if ctx and ctx.clock and ctx.clock.millis then
            local okm, ms = pcall(function() return ctx.clock:millis() end)
            if okm and tonumber(ms) then math.randomseed(tonumber(ms)) end
        end
    end)
    if not ok then ERR = tostring(e) end
end

function on_enter()
    refresh()
end

function on_draw(c, gg)
    if not gg then return end
    local ok, e = pcall(function()
        gg:clear(0)
        if state.menu_open then
            draw_menu(gg)
        elseif state.mode == "daily" then
            draw_daily(gg)
        elseif state.mode == "spread" then
            draw_spread(gg)
        elseif state.mode == "study" then
            draw_study(gg)
        elseif state.mode == "altar" then
            draw_altar(gg)
        end
        if ERR then
            gg:text(8, H - 26, "ERR " .. tostring(ERR):sub(1, 52), { font = font("small") })
        end
    end)
    if not ok then
        ERR = tostring(e)
        pcall(function()
            gg:clear(0)
            gg:text(8, 100, "Draw error", { font = font("medium") })
            gg:text(8, 135, tostring(e):sub(1, 52), { font = font("small") })
        end)
    end
end

function on_input(c, ev)
    ERR = nil
    local ok, e = pcall(function()
        if type(ev) ~= "table" then return end
        if ev.type == "pointer" and ev.phase == "up" then
            local gesture = ev.gesture or "tap"
            if gesture == "tap" or gesture == "double_tap" then
                handle_tap(tonumber(ev.x) or 0, tonumber(ev.y) or 0)
            end
        elseif ev.type == "touch" and ev.gesture == "tap" then
            handle_tap(tonumber(ev.x) or 0, tonumber(ev.y) or 0)
        elseif ev.type == "key" then
            handle_key(ev)
        end
    end)
    if not ok then ERR = tostring(e); refresh() end
    return true
end

function on_leave()
    save_state()
    release_cache()
end

function on_unload()
    release_cache()
end

if rawget(_G, "__TEST") then
    __TEST.api = {
        cards = function() return cards end,
        state = function() return state end,
        generate_spread = generate_spread,
        random_int = random_int,
        cache_size = function() return #image_order end,
        key_accepted = key_accepted,
    }
end
