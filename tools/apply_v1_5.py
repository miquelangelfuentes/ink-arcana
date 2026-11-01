from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
index = ROOT / "index.lua"
s = index.read_text(encoding="utf-8")

if "-- Feature layer v1.5" in s:
    raise SystemExit("v1.5 feature layer already applied")

s = s.replace(
    "-- Study mode v1.4: complete meanings with an upright/reversed orientation toggle.",
    "-- Feature release v1.5: richer study tools, spread history, help and paginated readings.",
    1,
)

feature_block = r'''
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
'''

marker = "local function key_accepted(ev)"
if marker not in s:
    raise SystemExit("key_accepted marker missing")
s = s.replace(marker, feature_block + "\n" + marker, 1)

handler_block = r'''
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
'''

marker = "function on_load(c)"
if marker not in s:
    raise SystemExit("on_load marker missing")
s = s.replace(marker, handler_block + "\n" + marker, 1)

new_on_load = r'''
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
'''
marker = "function on_enter()"
if marker not in s:
    raise SystemExit("on_enter marker missing")
s = s.replace(marker, new_on_load + "\n" + marker, 1)

new_on_draw = r'''
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
'''
# Insert after the original on_draw, so this later definition wins.
marker = "function on_input(c, ev)"
if marker not in s:
    raise SystemExit("on_input marker missing")
s = s.replace(marker, new_on_draw + "\n" + marker, 1)

# Extend test hooks.
hook = "        key_accepted = key_accepted,\n"
if hook not in s:
    raise SystemExit("test-hook marker missing")
s = s.replace(hook, hook + "        study_indices = study_indices,\n        cycle_study_filter = cycle_study_filter,\n        toggle_learned = toggle_learned,\n        toggle_favorite = toggle_favorite,\n        encode_history = encode_history,\n        decode_history = decode_history,\n        text_page_count = text_page_count,\n", 1)

index.write_text(s, encoding="utf-8")

manifest = ROOT / "manifest.json"
data = json.loads(manifest.read_text(encoding="utf-8"))
data["version"] = "1.5.0"
manifest.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

verify = ROOT / "verify_container.py"
v = verify.read_text(encoding="utf-8")
v = re.sub(r'manifest\["version"\] == "[^"]+"', 'manifest["version"] == "1.5.0"', v, count=1)
verify.write_text(v, encoding="utf-8")

readme = ROOT / "README.md"
r = readme.read_text(encoding="utf-8")
r = re.sub(
    r"### Study mode\n\n.*?\n\n### Desk altar",
    """### Study mode\n\nStudy mode now works as a deck-learning workspace. Each card is identified immediately and includes suit or arcana metadata. You can filter the deck by suit, favourites or learned cards; random selection respects the active filter. Cards can be marked as learned or favourite, and the FLIP control makes upright and reversed meanings available independently of the reading setting. Longer meanings are paginated rather than silently cut off.\n\n### Recent readings\n\nInkArcana keeps a lightweight history of the six most recent spreads. The history stores card indexes and orientations rather than artwork, and a saved spread can be reopened from the menu. Each new spread also includes an overview with a direct option to generate another spread of the same type.\n\n### Help and controls\n\nA two-page Help screen explains the app modes and the physical controls. Long readings use the side buttons for page changes while the reading is open.\n\n### Desk altar""",
    r,
    count=1,
    flags=re.S,
)
r = r.replace("Version 1.1 follows the API 2.9 behavior", "Version 1.5 follows the API 2.9 behavior")
readme.write_text(r, encoding="utf-8")

# Replace the test suite with a v1.5-focused regression suite while preserving the API checks.
test = ROOT / "test_suite.py"
test.write_text(r'''import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = (ROOT / "index.lua").read_text(encoding="utf-8")
CARDS_TEXT = (ROOT / "data" / "cards.txt").read_text(encoding="utf-8")
CARDS = [line for line in CARDS_TEXT.splitlines() if line.strip()]

print("=== InkArcana API 2.9 / v1.5 verification ===")

for forbidden in ("os.time", "os.date", "ctx.sys", "ctx.invalidate(", "ctx.save("):
    assert forbidden not in SOURCE, f"forbidden or obsolete API usage: {forbidden}"

assert "function on_draw(c, gg)" in SOURCE
assert 'ev.type == "pointer"' in SOURCE and 'ev.phase == "up"' in SOURCE
assert "ctx:invalidate()" in SOURCE and "ctx:save_state()" in SOURCE
assert ":release()" in SOURCE
assert 'title:find("CARD REFLECTION", 1, true)' in SOURCE
assert '"MYSTERY CARD"' not in SOURCE

for required in (
    'STUDY_FILTERS', 'favorites', 'learned', 'RECENT READINGS', 'SPREAD OVERVIEW',
    'NEW SPREAD', 'draw_help', 'text_page_count', 'SHOW REVERSED', 'SHOW UPRIGHT'
):
    assert required in SOURCE, f"missing v1.5 feature: {required}"

assert len(CARDS) == 78
keys = set()
for n, line in enumerate(CARDS, 1):
    fields = line.split("|")
    assert len(fields) == 6, f"line {n}: expected six fields"
    key, name, up_kw, up_read, rev_kw, rev_read = fields
    assert key not in keys
    keys.add(key)
    assert name and up_kw and up_read and rev_kw and rev_read
    assert "," not in up_kw and "," not in rev_kw
    assert up_kw.count("/") <= 1 and rev_kw.count("/") <= 1
    for text in (up_read, rev_read):
        for sentence in re.split(r"[.!?;]", text):
            assert sentence.count(",") < 2, f"{name}: possible three-part list: {sentence.strip()}"

try:
    from lupa import LuaRuntime
except ImportError as exc:
    raise SystemExit("Lupa is required: pip install lupa") from exc

lua = LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.app_code = SOURCE
g.cards_data = CARDS_TEXT

runtime_test = r'''
local invalidates, saves, draw_calls = 0, 0, 0
local random_counter = 0
ctx = {}
ctx.state = {}
ctx.capabilities = { image_decode = false, image_transform = true }
ctx.clock = {
    now = function(self) assert(self == ctx.clock); return { epoch_sec = 1793563200, year = 2026, month = 11, day = 1, hour = 21, minute = 0, second = 0 } end,
    millis = function(self) assert(self == ctx.clock); return 123456 + random_counter end,
}
ctx.random = {
    bytes = function(self, n) assert(self == ctx.random and n == 4); random_counter = random_counter + 1; local v = random_counter % 250; return string.char(0, 0, 0, v) end,
}
ctx.fonts = {
    small = { measure = function(self, s) return #s * 7 end, line_height = 20 },
    medium = { measure = function(self, s) return #s * 9 end, line_height = 24 },
    large = { measure = function(self, s) return #s * 12 end, line_height = 30 },
}
ctx.invalidate = function(self, mode) assert(self == ctx); invalidates = invalidates + 1 end
ctx.save_state = function(self) assert(self == ctx); saves = saves + 1 end
ctx.package = {
    open_text = function(self, name, opts)
        assert(self == ctx.package)
        if name ~= "cards.txt" then return nil end
        local lines = {}
        for line in (cards_data .. "\n"):gmatch("([^\n]*)\n") do if line ~= "" then lines[#lines + 1] = line end end
        local i = 0
        return { read_line = function(r) i = i + 1; return lines[i] end, close = function(r) end }
    end,
}

g = nil
canvas = {
    clear = function(self, c) draw_calls = draw_calls + 1; assert(c == 0) end,
    rect = function(self, ...) draw_calls = draw_calls + 1 end,
    circle = function(self, ...) draw_calls = draw_calls + 1 end,
    line = function(self, ...) draw_calls = draw_calls + 1 end,
    text = function(self, ...) draw_calls = draw_calls + 1 end,
    image = function(self, ...) draw_calls = draw_calls + 1 end,
}
os = nil; io = nil; debug = nil; package = nil; __TEST = {}
local loader = assert(load(app_code, "index.lua")); loader()
assert(on_load and on_draw and on_input and on_leave)
local ok, err = pcall(on_load, ctx); assert(ok, "on_load failed: " .. tostring(err))
assert(#__TEST.api.cards() == 78)
local S = __TEST.api.state()
assert(S.daily_view == "waits")

-- Daily card stays fixed.
local daily_index = S.daily_index
on_input(ctx, { type = "key", key = "right", phase = "down", time_ms = 500 })
assert(S.daily_index == daily_index and S.daily_view == "front")
S.daily_view = "waits"; S.has_turned_today = false
on_input(ctx, { type = "pointer", phase = "down", gesture = "tap", x = 240, y = 300, time_ms = 1000 })
assert(S.daily_view == "waits")
on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 240, y = 300, time_ms = 1100 })
assert(S.daily_view == "front" and S.daily_index == daily_index)

-- Create a three-card spread through the compact menu.
on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 40, y = 30, time_ms = 1400 })
assert(S.menu_open == true)
on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 200, y = 185, time_ms = 1700 })
assert(S.mode == "spread" and #S.spread_cards == 3 and #S.history == 1)
local seen = {}; for _, entry in ipairs(S.spread_cards) do assert(not seen[entry.index]); seen[entry.index] = true end

-- Overview is available and can generate a fresh spread.
on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 240, y = 740, time_ms = 1900 })
assert(S.spread_view == "overview")
on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 240, y = 640, time_ms = 2100 })
assert(S.spread_view == "front" and #S.history == 2)

-- Study supports progress flags and filtered browsing.
S.mode = "study"; S.study_filter = "all"; S.study_revealed = false; S.study_reversed = false
local study_index = S.study_index
on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 240, y = 300, time_ms = 2400 })
assert(S.study_revealed == true and S.study_index == study_index)
on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 180, y = 650, time_ms = 2600 })
assert(S.study_reversed == true and S.study_revealed == true)
on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 280, y = 650, time_ms = 2800 })
assert(S.learned[study_index] == true)
on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 390, y = 650, time_ms = 3000 })
assert(S.favorites[study_index] == true)
local all_count = #__TEST.api.study_indices(); assert(all_count == 78)
__TEST.api.cycle_study_filter(); assert(S.study_filter == "major" and #__TEST.api.study_indices() == 22)

-- Pagination helper must create more than one page for long text.
local long_text = string.rep("word ", 220)
assert(__TEST.api.text_page_count(long_text, "small", 410, 250, 555) > 1)

-- History codec round-trips at least the saved records.
local encoded = __TEST.api.encode_history(S.history)
local decoded = __TEST.api.decode_history(encoded)
assert(#decoded == #S.history)

-- All visible modes draw without an exception.
for _, mode in ipairs({ "daily", "spread", "study", "history", "help", "altar" }) do
    S.mode = mode
    if mode == "spread" and #S.spread_cards == 0 then S.spread_cards = __TEST.api.generate_spread("triad") end
    local before_draw = draw_calls
    ok, err = pcall(on_draw, ctx, canvas)
    assert(ok, "draw failed in mode " .. mode .. ": " .. tostring(err))
    assert(draw_calls > before_draw, "mode did not draw: " .. mode)
end

ok, err = pcall(on_leave); assert(ok)
assert(saves > 0 and invalidates > 0)
return true
'''

lua.execute(runtime_test)
print("Runtime simulation: PASS")
print("Feature regression checks: PASS")
print("Card wording checks: PASS")
print("=== Verification completed ===")
''', encoding="utf-8")

print("Applied InkArcana v1.5.0 feature layer")
