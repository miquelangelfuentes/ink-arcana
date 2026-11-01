-- InkArcana for XTEINK X4 Pro / XTOS Licorice API 2.x
-- Feature release v1.5: richer study tools, spread history, help and paginated readings.
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
    study_reversed = false,
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
        study_reversed = state.study_reversed,
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

    local orientation = state.study_reversed and "REVERSED" or "UPRIGHT"
    local keywords = state.study_reversed and c.rev_kw or c.up_kw
    local meaning = state.study_reversed and c.rev_read or c.up_read
    local toggle_label = state.study_reversed and "SHOW UPRIGHT" or "SHOW REVERSED"

    if not state.study_revealed then
        draw_card_art(gg, state.study_index, state.study_reversed, CARD_X, 96, CARD_W, CARD_H)
        local card_font = text_width(font("large"), c.name) > 420 and "medium" or "large"
        centered(gg, 530, c.name, card_font)
        centered(gg, 575, keywords, "medium")
        centered(gg, 610, orientation, "small")
        button(gg, 150, 638, 180, 44, toggle_label, "small")
        centered(gg, 690, "Tap the card for meaning", "small")
    else
        local card_font = text_width(font("large"), c.name) > 420 and "medium" or "large"
        centered(gg, 102, c.name, card_font)
        centered(gg, 148, orientation, "small")
        centered(gg, 178, keywords, "medium")
        gg:line(90, 216, 390, 216, { width = 1 })
        paragraph(gg, 242, meaning, "small", 410, 610)
        button(gg, 150, 638, 180, 44, toggle_label, "small")
        centered(gg, 690, "Tap elsewhere to return to card", "small")
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


-- Feature layer v1.5 ---------------------------------------------------------
state.study_filter = state.study_filter or "all"
state.learned = state.learned or {}
state.favorites = state.favorites or {}
state.history = state.history or {}
state.help_page = state.help_page or 1
state.text_page = state.text_page or 1

local STUDY_FILTERS = { "all", "major", "wands", "cups", "swords", "pentacles", "favorites", "learned" }
local FILTER_NAMES = {
    all = "ALL", major = "MAJOR", wands = "WANDS", cups = "CUPS",
    swords = "SWORDS", pentacles = "PENTACLES", favorites = "FAVORITES", learned = "LEARNED"
}

local function encode_set(t)
    local out = {}
    for i = 1, #cards do
        if t and t[i] then out[#out + 1] = tostring(i) end
    end
    return table.concat(out, ",")
end

local function decode_set(s)
    local out = {}
    for n in tostring(s or ""):gmatch("%d+") do
        local i = tonumber(n)
        if i and i >= 1 and i <= #cards then out[i] = true end
    end
    return out
end

local function count_set(t)
    local n = 0
    for i = 1, #cards do if t and t[i] then n = n + 1 end end
    return n
end

local function spread_labels(kind)
    if kind == "cross" then return { "Where you stand", "What meets you" } end
    return { "What shaped this", "Where you are", "What may emerge" }
end

local function clone_spread(entries, kind)
    local labels = spread_labels(kind)
    local out = {}
    for i, e in ipairs(entries or {}) do
        out[#out + 1] = {
            index = tonumber(e.index) or 1,
            reversed = e.reversed == true,
            label = e.label or labels[i] or "Spread",
        }
    end
    return out
end

local function encode_history(history)
    local rows = {}
    for _, rec in ipairs(history or {}) do
        local bits = {}
        for _, e in ipairs(rec.cards or {}) do
            bits[#bits + 1] = tostring(e.index) .. (e.reversed and "r" or "u")
        end
        rows[#rows + 1] = tostring(rec.date or "Today") .. "|" .. tostring(rec.kind or "triad") .. "|" .. table.concat(bits, ",")
    end
    return table.concat(rows, ";")
end

local function decode_history(serialized)
    local out = {}
    for row in tostring(serialized or ""):gmatch("[^;]+") do
        local date, kind, body = row:match("^([^|]+)|([^|]+)|(.+)$")
        if date and (kind == "triad" or kind == "cross") then
            local cards_out = {}
            local labels = spread_labels(kind)
            local pos = 1
            for token in body:gmatch("[^,]+") do
                local idx, orient = token:match("^(%d+)([ru])$")
                idx = tonumber(idx)
                if idx and idx >= 1 and idx <= #cards then
                    cards_out[#cards_out + 1] = { index = idx, reversed = orient == "r", label = labels[pos] }
                    pos = pos + 1
                end
            end
            if #cards_out > 0 then out[#out + 1] = { date = date, kind = kind, cards = cards_out } end
        end
    end
    return out
end

local function add_history(kind, entries)
    table.insert(state.history, 1, { date = formatted_date(), kind = kind, cards = clone_spread(entries, kind) })
    while #state.history > 6 do table.remove(state.history) end
end

local function valid_filter(name)
    for _, v in ipairs(STUDY_FILTERS) do if v == name then return true end end
    return false
end

local function study_matches(idx, filter_name)
    local c = cards[idx]
    if not c then return false end
    if filter_name == "all" then return true end
    if filter_name == "favorites" then return state.favorites[idx] == true end
    if filter_name == "learned" then return state.learned[idx] == true end
    return c.suit == filter_name
end

local function study_indices()
    local out = {}
    for i = 1, #cards do if study_matches(i, state.study_filter) then out[#out + 1] = i end end
    return out
end

local function study_position()
    local list = study_indices()
    if #list == 0 then return list, 0 end
    for pos, idx in ipairs(list) do
        if idx == state.study_index then return list, pos end
    end
    state.study_index = list[1]
    return list, 1
end

local function cycle_study_filter()
    local current = 1
    for i, v in ipairs(STUDY_FILTERS) do if v == state.study_filter then current = i; break end end
    state.study_filter = STUDY_FILTERS[(current % #STUDY_FILTERS) + 1]
    local list = study_indices()
    if #list > 0 then state.study_index = list[1] end
    state.study_revealed = false
    state.text_page = 1
    save_state()
end

local function study_move(delta)
    local list, pos = study_position()
    if #list == 0 then return end
    pos = ((pos - 1 + delta) % #list) + 1
    state.study_index = list[pos]
    state.study_revealed = false
    state.text_page = 1
end

local function study_random()
    local list = study_indices()
    if #list == 0 then return end
    state.study_index = list[random_int(#list)]
    state.study_revealed = false
    state.text_page = 1
end

local function toggle_learned()
    local i = state.study_index
    state.learned[i] = not state.learned[i] or nil
    if state.study_filter == "learned" and not state.learned[i] then
        local list = study_indices(); if #list > 0 then state.study_index = list[1] end
    end
    save_state()
end

local function toggle_favorite()
    local i = state.study_index
    state.favorites[i] = not state.favorites[i] or nil
    if state.study_filter == "favorites" and not state.favorites[i] then
        local list = study_indices(); if #list > 0 then state.study_index = list[1] end
    end
    save_state()
end

local function roman(n)
    if n == 0 then return "0" end
    local vals = { 10, 9, 5, 4, 1 }
    local syms = { "X", "IX", "V", "IV", "I" }
    local out = ""
    for i, v in ipairs(vals) do
        while n >= v do out = out .. syms[i]; n = n - v end
    end
    return out
end

local function card_meta(c)
    if not c then return "" end
    local n = tonumber(c.key:sub(2)) or 0
    if c.suit == "major" then return "MAJOR ARCANA  " .. roman(n) end
    local rank = tostring(n)
    if n == 1 then rank = "ACE"
    elseif n == 11 then rank = "PAGE"
    elseif n == 12 then rank = "KNIGHT"
    elseif n == 13 then rank = "QUEEN"
    elseif n == 14 then rank = "KING" end
    return string.upper(c.suit) .. "  " .. rank
end

local function text_page_info(text, fname, max_w, y, bottom)
    local lines = wrap(text, fname, max_w)
    local lh = line_height(fname) + 5
    local per_page = math.max(1, math.floor((bottom - y) / lh))
    local pages = math.max(1, math.ceil(#lines / per_page))
    return lines, lh, per_page, pages
end

local function draw_text_page(gg, y, text, fname, max_w, bottom, page)
    local lines, lh, per_page, pages = text_page_info(text, fname, max_w, y, bottom)
    page = math.max(1, math.min(pages, tonumber(page) or 1))
    local first = (page - 1) * per_page + 1
    local last = math.min(#lines, first + per_page - 1)
    for i = first, last do
        centered(gg, y, lines[i], fname)
        y = y + lh
    end
    return pages, page
end

local function text_page_count(text, fname, max_w, y, bottom)
    local _, _, _, pages = text_page_info(text, fname, max_w, y, bottom)
    return pages
end

local function short_text(s, max_chars)
    s = tostring(s or "")
    if #s <= max_chars then return s end
    return s:sub(1, math.max(1, max_chars - 3)) .. "..."
end

save_state = function()
    if not ctx then return end
    ctx.state = {
        daily_day = state.daily_day,
        daily_index = state.daily_index,
        daily_reversed = state.daily_reversed,
        daily_view = state.daily_view,
        has_turned_today = state.has_turned_today,
        reversals_enabled = state.reversals_enabled,
        study_index = state.study_index,
        study_reversed = state.study_reversed,
        study_filter = state.study_filter,
        learned = encode_set(state.learned),
        favorites = encode_set(state.favorites),
        history = encode_history(state.history),
    }
    pcall(function() ctx:save_state() end)
end

begin_spread = function(kind)
    state.mode = "spread"
    state.spread_type = kind
    state.spread_cards = generate_spread(kind)
    state.spread_pos = 1
    state.spread_view = "front"
    state.text_page = 1
    state.menu_open = false
    add_history(kind, state.spread_cards)
    save_state()
end

local function load_history_spread(rec)
    if not rec then return end
    state.mode = "spread"
    state.spread_type = rec.kind
    state.spread_cards = clone_spread(rec.cards, rec.kind)
    state.spread_pos = 1
    state.spread_view = "overview"
    state.text_page = 1
    state.menu_open = false
end

local function reading_page_count(c, reversed)
    if not c then return 1 end
    return text_page_count(reversed and c.rev_read or c.up_read, "medium", 400, 274, 620)
end

local function study_page_count()
    local c = cards[state.study_index]
    if not c then return 1 end
    local text = state.study_reversed and c.rev_read or c.up_read
    return text_page_count(text, "small", 410, 250, 555)
end

draw_reading = function(gg, c, reversed, title)
    centered(gg, 92, title, "small")
    local card_font = text_width(font("large"), c.name) > 420 and "medium" or "large"
    centered(gg, 126, c.name, card_font)
    local kw_y = 188
    if reversed then centered(gg, 168, "REVERSED", "small"); kw_y = 202 end
    centered(gg, kw_y, reversed and c.rev_kw or c.up_kw, "medium")
    gg:line(100, 238, 380, 238, { width = 1 })
    local body = reversed and c.rev_read or c.up_read
    local pages, page = draw_text_page(gg, 274, body, "medium", 400, 620, state.text_page)
    state.text_page = page
    if pages > 1 then centered(gg, 642, string.format("Page %d / %d   Side buttons change page", page, pages), "small") end
    gg:line(150, 676, 330, 676, { width = 1 })
    centered(gg, 700, "Tap to return to the card", "small")
end

draw_daily = function(gg)
    title_bar(gg, "INKARCANA")
    if #cards == 0 then centered(gg, 180, "Card data is missing from the package.", "medium"); return end
    centered(gg, 72, "TODAY  " .. formatted_date(), "small")
    local c = cards[state.daily_index]
    if state.daily_view == "waits" then
        draw_card_back(gg, CARD_X, 100, CARD_W, CARD_H)
        centered(gg, 544, "The card waits", "large")
        centered(gg, 594, "Tap to turn today's card", "medium")
    elseif state.daily_view == "front" then
        draw_card_art(gg, state.daily_index, state.daily_reversed, CARD_X, 100, CARD_W, CARD_H)
        centered(gg, 540, c.name, "large")
        local kw_y = 590
        if state.daily_reversed then centered(gg, 576, "REVERSED", "small"); kw_y = 610 end
        centered(gg, kw_y, state.daily_reversed and c.rev_kw or c.up_kw, "medium")
        gg:line(145, 650, 335, 650, { width = 1 })
        centered(gg, 700, "Tap the card to reflect", "small")
    else
        draw_reading(gg, c, state.daily_reversed, "TODAY'S CARD")
    end
end

local function draw_spread_overview(gg)
    centered(gg, 82, "SPREAD OVERVIEW", "medium")
    local row_y = 120
    for i, entry in ipairs(state.spread_cards) do
        local c = cards[entry.index]
        gg:line(45, row_y - 8, 435, row_y - 8, { width = 1 })
        centered(gg, row_y, spread_label(entry), "small")
        centered(gg, row_y + 30, c and c.name or "Card", "medium")
        if entry.reversed then centered(gg, row_y + 60, "REVERSED", "small") end
        row_y = row_y + 130
    end
    gg:line(45, row_y - 8, 435, row_y - 8, { width = 1 })
    button(gg, 90, 620, 300, 44, "NEW SPREAD", "small")
    button(gg, 90, 678, 300, 44, "VIEW CARDS", "small")
end

draw_spread = function(gg)
    title_bar(gg, state.spread_type == "triad" and "THREE-CARD REFLECTION" or "TWO-CARD REFLECTION")
    if state.spread_view == "overview" then draw_spread_overview(gg); return end
    local entry = state.spread_cards[state.spread_pos]
    if not entry then centered(gg, 200, "Choose a new spread from the menu.", "medium"); return end
    local c = cards[entry.index]
    if state.spread_view == "reading" then draw_reading(gg, c, entry.reversed, spread_label(entry)); return end
    local position = string.format("%d / %d   %s", state.spread_pos, #state.spread_cards, spread_label(entry))
    centered(gg, 76, position, "small")
    draw_card_art(gg, entry.index, entry.reversed, CARD_X, 105, CARD_W, CARD_H)
    centered(gg, 548, c.name, "large")
    local kw_y = 592
    if entry.reversed then centered(gg, 580, "REVERSED", "small"); kw_y = 612 end
    centered(gg, kw_y, entry.reversed and c.rev_kw or c.up_kw, "medium")
    gg:line(145, 650, 335, 650, { width = 1 })
    centered(gg, 680, "Tap the card for meaning", "small")
    button(gg, 24, 718, 118, 48, "PREV", "small")
    button(gg, 168, 718, 144, 48, "OVERVIEW", "small")
    button(gg, 338, 718, 118, 48, "NEXT", "small")
end

draw_study = function(gg)
    title_bar(gg, "STUDY")
    if #cards == 0 then return end
    local list, pos = study_position()
    local filter_name = FILTER_NAMES[state.study_filter] or "ALL"
    if #list == 0 then
        centered(gg, 92, filter_name, "small")
        centered(gg, 250, "No cards in this view yet.", "medium")
        button(gg, 140, 340, 200, 48, "NEXT FILTER", "small")
        return
    end
    local c = cards[state.study_index]
    centered(gg, 72, string.format("%d / %d   %s", pos, #list, filter_name), "small")
    local orientation = state.study_reversed and "REVERSED" or "UPRIGHT"
    local keywords = state.study_reversed and c.rev_kw or c.up_kw
    local meaning = state.study_reversed and c.rev_read or c.up_read
    local learn_label = state.learned[state.study_index] and "UNLEARN" or "LEARN"
    local fav_label = state.favorites[state.study_index] and "UNFAV" or "FAV"

    if not state.study_revealed then
        draw_card_art(gg, state.study_index, state.study_reversed, CARD_X, 92, CARD_W, CARD_H)
        local card_font = text_width(font("large"), c.name) > 420 and "medium" or "large"
        centered(gg, 518, c.name, card_font)
        centered(gg, 552, card_meta(c), "small")
        centered(gg, 582, keywords, "medium")
        centered(gg, 612, orientation, "small")
    else
        local card_font = text_width(font("large"), c.name) > 420 and "medium" or "large"
        centered(gg, 102, c.name, card_font)
        centered(gg, 138, card_meta(c), "small")
        centered(gg, 168, orientation, "small")
        centered(gg, 198, keywords, "medium")
        gg:line(90, 230, 390, 230, { width = 1 })
        local pages, page = draw_text_page(gg, 250, meaning, "small", 410, 555, state.text_page)
        state.text_page = page
        if pages > 1 then centered(gg, 570, string.format("Page %d / %d   Side buttons change page", page, pages), "small") end
    end

    button(gg, 18, 635, 102, 40, "FILTER", "small")
    button(gg, 126, 635, 102, 40, "FLIP", "small")
    button(gg, 234, 635, 102, 40, learn_label, "small")
    button(gg, 342, 635, 102, 40, fav_label, "small")
    centered(gg, 684, state.study_revealed and "Tap the meaning to return" or "Tap the card for meaning", "small")
    button(gg, 24, 718, 118, 48, "PREV", "small")
    button(gg, 168, 718, 144, 48, "RANDOM", "small")
    button(gg, 338, 718, 118, 48, "NEXT", "small")
end

local function draw_history(gg)
    title_bar(gg, "RECENT READINGS")
    if #state.history == 0 then centered(gg, 250, "No saved spreads yet.", "medium"); return end
    local y = 92
    for i = 1, math.min(6, #state.history) do
        local rec = state.history[i]
        local kind_name = rec.kind == "triad" and "Three-card reflection" or "Two-card reflection"
        local first = rec.cards[1] and cards[rec.cards[1].index]
        gg:line(40, y - 8, 440, y - 8, { width = 1 })
        gg:text(52, y, tostring(rec.date), { font = font("small") })
        gg:text(52, y + 25, kind_name, { font = font("medium") })
        gg:text(52, y + 54, short_text(first and first.name or "Reading", 34), { font = font("small") })
        y = y + 88
    end
    gg:line(40, y - 8, 440, y - 8, { width = 1 })
    centered(gg, 680, "Tap a reading to reopen it", "small")
end

local function draw_help(gg)
    title_bar(gg, "HELP")
    centered(gg, 78, string.format("%d / 2", state.help_page), "small")
    if state.help_page == 1 then
        centered(gg, 120, "DAILY CARD", "medium")
        paragraph(gg, 155, "A fixed card for the local day. Turn it, then tap the artwork to read the reflection.", "small", 400, 255)
        centered(gg, 285, "REFLECTIONS", "medium")
        paragraph(gg, 320, "Two-card and three-card spreads include an overview. Recent readings can be reopened from the menu.", "small", 400, 420)
        centered(gg, 455, "STUDY", "medium")
        paragraph(gg, 490, "Filter the deck by suit or progress. Mark learned cards or favourites, and flip between upright and reversed meanings.", "small", 400, 600)
    else
        centered(gg, 120, "CONTROLS", "medium")
        paragraph(gg, 155, "Tap cards to open meanings. The side buttons move through cards; when a long meaning has more than one page, they change pages instead.", "small", 400, 280)
        centered(gg, 330, "READING OPTIONS", "medium")
        paragraph(gg, 365, "Reversed cards can be enabled for readings from the menu. Study has its own FLIP control so both orientations are always available there.", "small", 400, 485)
        centered(gg, 535, "E-PAPER", "medium")
        paragraph(gg, 570, "InkArcana keeps movement minimal and releases decoded card images as you browse to respect the device limits.", "small", 400, 650)
    end
    button(gg, 60, 704, 150, 48, "PREV PAGE", "small")
    button(gg, 270, 704, 150, 48, "NEXT PAGE", "small")
end

MENU_ITEMS = {
    { "Daily card", "daily" },
    { "Three-card reflection", "triad" },
    { "Two-card reflection", "cross" },
    { "Study the deck", "study" },
    { "Recent readings", "history" },
    { "Desk altar", "altar" },
    { "Help", "help" },
}

draw_menu = function(gg)
    centered(gg, 24, "INKARCANA", "large")
    centered(gg, 66, "A quiet space for reflection", "small")
    gg:line(45, 100, 435, 100, { width = 1 })
    local y = 112
    for _, item in ipairs(MENU_ITEMS) do
        local x, w, h = 45, 390, 46
        gg:text(x + 14, y + 12, item[1], { font = font("medium") })
        local ax, ay = x + w - 18, y + math.floor(h / 2)
        gg:line(ax - 5, ay - 5, ax, ay, { width = 1 })
        gg:line(ax, ay, ax - 5, ay + 5, { width = 1 })
        gg:line(x, y + h, x + w, y + h, { width = 1 })
        y = y + 58
    end
    gg:text(59, y + 12, "Reversed cards", { font = font("medium") })
    button(gg, 349, y + 9, 72, 30, state.reversals_enabled and "ON" or "OFF", "small")
    gg:line(45, y + 46, 435, y + 46, { width = 1 })
    button(gg, 140, y + 68, 200, 48, "CLOSE", "medium")
end
-- End feature drawing layer --------------------------------------------------

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
        elseif x >= 150 and x <= 330 and y >= 638 and y <= 682 then
            state.study_reversed = not state.study_reversed
            save_state()
        elseif state.study_revealed then
            state.study_revealed = false
        elseif y >= 90 and y <= 620 then
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


-- v1.5 interaction layer ----------------------------------------------------
handle_menu_tap = function(x, y)
    local top, row, h = 112, 58, 46
    for i, item in ipairs(MENU_ITEMS) do
        local yy = top + (i - 1) * row
        if x >= 45 and x <= 435 and y >= yy and y <= yy + h then
            local id = item[2]
            if id == "daily" then state.mode = "daily"; state.menu_open = false
            elseif id == "triad" or id == "cross" then begin_spread(id)
            elseif id == "study" then state.mode = "study"; state.study_revealed = false; state.text_page = 1; state.menu_open = false
            elseif id == "history" then state.mode = "history"; state.menu_open = false
            elseif id == "altar" then state.mode = "altar"; state.menu_open = false
            elseif id == "help" then state.mode = "help"; state.help_page = 1; state.menu_open = false end
            return
        end
    end
    local rev_y = top + #MENU_ITEMS * row
    if x >= 45 and x <= 435 and y >= rev_y and y <= rev_y + h then
        state.reversals_enabled = not state.reversals_enabled
        save_state(); return
    end
    if x >= 140 and x <= 340 and y >= rev_y + 68 and y <= rev_y + 116 then state.menu_open = false end
end

handle_tap = function(x, y)
    if state.menu_open then handle_menu_tap(x, y); refresh(); return end
    if x >= HEADER_MENU_X and x <= HEADER_MENU_X + HEADER_MENU_W and y >= HEADER_MENU_Y and y <= HEADER_MENU_Y + HEADER_MENU_H and state.mode ~= "altar" then
        state.menu_open = true; refresh(); return
    end
    if state.mode == "altar" then state.mode = "daily"; refresh(); return end

    if state.mode == "daily" then
        if state.daily_view == "waits" then
            state.daily_view = "front"; state.has_turned_today = true; state.text_page = 1; save_state()
        elseif state.daily_view == "front" and x >= CARD_X and x <= CARD_X + CARD_W and y >= 100 and y <= 100 + CARD_H then
            state.daily_view = "reading"; state.text_page = 1; save_state()
        elseif state.daily_view == "reading" then
            state.daily_view = "front"; state.text_page = 1; save_state()
        end
        refresh(); return
    end

    if state.mode == "spread" then
        local count = #state.spread_cards
        if count == 0 then return end
        if state.spread_view == "overview" then
            for i = 1, count do
                local yy = 120 + (i - 1) * 130
                if y >= yy - 8 and y <= yy + 90 then state.spread_pos = i; state.spread_view = "front"; refresh(); return end
            end
            if x >= 90 and x <= 390 and y >= 620 and y <= 664 then begin_spread(state.spread_type); refresh(); return end
            if x >= 90 and x <= 390 and y >= 678 and y <= 722 then state.spread_pos = 1; state.spread_view = "front"; refresh(); return end
        elseif y >= 718 and y <= 766 and x >= 24 and x <= 142 then
            state.spread_pos = ((state.spread_pos - 2 + count) % count) + 1; state.spread_view = "front"; state.text_page = 1
        elseif y >= 718 and y <= 766 and x >= 338 and x <= 456 then
            state.spread_pos = (state.spread_pos % count) + 1; state.spread_view = "front"; state.text_page = 1
        elseif y >= 718 and y <= 766 and x >= 168 and x <= 312 then
            state.spread_view = "overview"; state.text_page = 1
        elseif state.spread_view == "reading" then
            state.spread_view = "front"; state.text_page = 1
        elseif x >= CARD_X and x <= CARD_X + CARD_W and y >= 105 and y <= 105 + CARD_H then
            state.spread_view = "reading"; state.text_page = 1
        end
        refresh(); return
    end

    if state.mode == "study" then
        local list = study_indices()
        if #list == 0 then
            if x >= 140 and x <= 340 and y >= 340 and y <= 388 then cycle_study_filter() end
            refresh(); return
        end
        if y >= 718 and y <= 766 and x >= 24 and x <= 142 then study_move(-1)
        elseif y >= 718 and y <= 766 and x >= 338 and x <= 456 then study_move(1)
        elseif y >= 718 and y <= 766 and x >= 168 and x <= 312 then study_random()
        elseif y >= 635 and y <= 675 and x >= 18 and x <= 120 then cycle_study_filter()
        elseif y >= 635 and y <= 675 and x >= 126 and x <= 228 then state.study_reversed = not state.study_reversed; state.text_page = 1; save_state()
        elseif y >= 635 and y <= 675 and x >= 234 and x <= 336 then toggle_learned()
        elseif y >= 635 and y <= 675 and x >= 342 and x <= 444 then toggle_favorite()
        elseif state.study_revealed and y >= 90 and y <= 620 then state.study_revealed = false; state.text_page = 1
        elseif not state.study_revealed and x >= CARD_X and x <= CARD_X + CARD_W and y >= 92 and y <= 92 + CARD_H then state.study_revealed = true; state.text_page = 1 end
        refresh(); return
    end

    if state.mode == "history" then
        for i = 1, math.min(6, #state.history) do
            local yy = 92 + (i - 1) * 88
            if y >= yy - 8 and y <= yy + 72 then load_history_spread(state.history[i]); refresh(); return end
        end
        return
    end

    if state.mode == "help" then
        if y >= 704 and y <= 752 and x >= 60 and x <= 210 then state.help_page = state.help_page == 1 and 2 or 1
        elseif y >= 704 and y <= 752 and x >= 270 and x <= 420 then state.help_page = state.help_page == 2 and 1 or 2 end
        refresh(); return
    end
end

handle_key = function(ev)
    if not key_accepted(ev) then return end
    local key = ev.key
    if key == "back" then
        if state.menu_open then state.menu_open = false
        elseif state.mode ~= "daily" then state.mode = "daily"
        elseif state.daily_view == "reading" then state.daily_view = "front"; state.text_page = 1 end
        refresh(); return
    end
    if key == "ok" or key == "enter" then
        if state.mode == "daily" then
            if state.daily_view == "waits" then state.daily_view = "front"; state.has_turned_today = true
            elseif state.daily_view == "front" then state.daily_view = "reading"; state.text_page = 1
            else state.daily_view = "front"; state.text_page = 1 end
            save_state()
        elseif state.mode == "spread" and #state.spread_cards > 0 then
            if state.spread_view == "overview" then state.spread_view = "front"
            elseif state.spread_view == "front" then state.spread_view = "reading"; state.text_page = 1
            else state.spread_view = "front"; state.text_page = 1 end
        elseif state.mode == "study" then state.study_revealed = not state.study_revealed; state.text_page = 1
        end
        refresh(); return
    end
    local d = (key == "right" or key == "down") and 1 or ((key == "left" or key == "up") and -1 or 0)
    if d == 0 then return end
    if state.mode == "daily" and state.daily_view == "reading" then
        local pages = reading_page_count(cards[state.daily_index], state.daily_reversed)
        if pages > 1 then state.text_page = ((state.text_page - 1 + d) % pages) + 1
        else state.daily_view = "front"; state.text_page = 1 end
    elseif state.mode == "spread" and #state.spread_cards > 0 then
        if state.spread_view == "reading" then
            local e = state.spread_cards[state.spread_pos]
            local pages = reading_page_count(cards[e.index], e.reversed)
            if pages > 1 then state.text_page = ((state.text_page - 1 + d) % pages) + 1
            else state.spread_pos = ((state.spread_pos - 1 + d) % #state.spread_cards) + 1; state.spread_view = "front" end
        elseif state.spread_view ~= "overview" then
            state.spread_pos = ((state.spread_pos - 1 + d) % #state.spread_cards) + 1; state.spread_view = "front"; state.text_page = 1
        end
    elseif state.mode == "study" and #cards > 0 then
        if state.study_revealed and study_page_count() > 1 then
            local pages = study_page_count(); state.text_page = ((state.text_page - 1 + d) % pages) + 1
        else study_move(d) end
    elseif state.mode == "daily" and #cards > 0 then
        if state.daily_view == "waits" then state.daily_view = "front"; state.has_turned_today = true
        elseif state.daily_view == "front" then state.daily_view = "reading"; state.text_page = 1
        else state.daily_view = "front"; state.text_page = 1 end
        save_state()
    elseif state.mode == "help" then state.help_page = d > 0 and 2 or 1 end
    refresh()
end
-- End v1.5 interaction layer -----------------------------------------------

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
            if saved.study_reversed ~= nil then
                state.study_reversed = saved.study_reversed == true
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


-- v1.5 persisted-state loader replaces the earlier on_load definition.
function on_load(c)
    ERR = nil
    local ok, e = pcall(function()
        load_cards()
        local saved = c and c.state or (ctx and ctx.state)
        state.learned, state.favorites, state.history = {}, {}, {}
        state.study_filter, state.text_page, state.help_page = "all", 1, 1
        if type(saved) == "table" then
            if saved.reversals_enabled ~= nil then state.reversals_enabled = saved.reversals_enabled end
            if saved.learned then state.learned = decode_set(saved.learned) end
            if saved.favorites then state.favorites = decode_set(saved.favorites) end
            if saved.history then state.history = decode_history(saved.history) end
            if valid_filter(saved.study_filter) then state.study_filter = saved.study_filter end
            if saved.study_index and #cards > 0 then state.study_index = math.max(1, math.min(#cards, tonumber(saved.study_index) or 1)) end
            if saved.study_reversed ~= nil then state.study_reversed = saved.study_reversed == true end
        end
        local today = local_day()
        state.daily_day = today
        if #cards > 0 then
            local hash = (today * 2654435761) % 2147483648
            state.daily_index = (hash % #cards) + 1
            state.daily_reversed = state.reversals_enabled and (((math.floor(hash / 78)) % 100) < 25) or false
        end
        if type(saved) == "table" and saved.daily_day == today then
            if saved.daily_index and #cards > 0 then state.daily_index = math.max(1, math.min(#cards, tonumber(saved.daily_index) or state.daily_index)) end
            if saved.daily_reversed ~= nil then state.daily_reversed = saved.daily_reversed end
            state.has_turned_today = saved.has_turned_today == true
            state.daily_view = saved.daily_view or (state.has_turned_today and "front" or "waits")
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


-- v1.5 renderer adds history and help modes.
function on_draw(c, gg)
    if not gg then return end
    local ok, e = pcall(function()
        gg:clear(0)
        if state.menu_open then draw_menu(gg)
        elseif state.mode == "daily" then draw_daily(gg)
        elseif state.mode == "spread" then draw_spread(gg)
        elseif state.mode == "study" then draw_study(gg)
        elseif state.mode == "history" then draw_history(gg)
        elseif state.mode == "help" then draw_help(gg)
        elseif state.mode == "altar" then draw_altar(gg) end
        if ERR then gg:text(8, H - 26, "ERR " .. tostring(ERR):sub(1, 52), { font = font("small") }) end
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
        study_indices = study_indices,
        cycle_study_filter = cycle_study_filter,
        toggle_learned = toggle_learned,
        toggle_favorite = toggle_favorite,
        encode_history = encode_history,
        decode_history = decode_history,
        text_page_count = text_page_count,
    }
end
