import re
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
