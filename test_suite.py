import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = (ROOT / "index.lua").read_text(encoding="utf-8")
CARDS_TEXT = (ROOT / "data" / "cards.txt").read_text(encoding="utf-8")
CARDS = [line for line in CARDS_TEXT.splitlines() if line.strip()]

print("=== InkArcana API 2.9 verification ===")

for forbidden in ("os.time", "os.date", "ctx.sys", "ctx.invalidate(", "ctx.save("):
    assert forbidden not in SOURCE, f"forbidden or obsolete API usage: {forbidden}"

assert "function on_draw(c, gg)" in SOURCE, "on_draw must accept the API 2.x canvas argument"
assert 'ev.type == "pointer"' in SOURCE and 'ev.phase == "up"' in SOURCE, "pointer-up input handling is required"
assert "ctx:invalidate()" in SOURCE, "API 2.x ctx methods must use colon syntax"
assert "ctx:save_state()" in SOURCE, "state persistence must use save_state"
assert ":release()" in SOURCE, "decoded images need an explicit release path"

assert len(CARDS) == 78, f"expected 78 cards, got {len(CARDS)}"
keys = set()
for n, line in enumerate(CARDS, 1):
    fields = line.split("|")
    assert len(fields) == 6, f"line {n}: expected six fields"
    key, name, up_kw, up_read, rev_kw, rev_read = fields
    assert key not in keys, f"duplicate card key: {key}"
    keys.add(key)
    assert name and up_kw and up_read and rev_kw and rev_read, f"line {n}: empty card field"
    assert "," not in up_kw and "," not in rev_kw, f"{name}: comma-list keyword found"
    assert up_kw.count("/") <= 1 and rev_kw.count("/") <= 1, f"{name}: too many keyword items"
    for text in (up_read, rev_read):
        for sentence in re.split(r"[.!?;]", text):
            assert sentence.count(",") < 2, f"{name}: possible three-part list: {sentence.strip()}"

try:
    from lupa import LuaRuntime
except ImportError as exc:
    raise SystemExit("Lupa is required for runtime simulation: pip install lupa") from exc

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
    now = function(self)
        assert(self == ctx.clock)
        return { epoch_sec = 1793563200, year = 2026, month = 11, day = 1, hour = 21, minute = 0, second = 0 }
    end,
    millis = function(self)
        assert(self == ctx.clock)
        return 123456 + random_counter
    end,
}
ctx.random = {
    bytes = function(self, n)
        assert(self == ctx.random and n == 4)
        random_counter = random_counter + 1
        local v = random_counter % 250
        return string.char(0, 0, 0, v)
    end,
}
ctx.fonts = {
    small = { measure = function(self, s) return #s * 7 end, line_height = 20 },
    medium = { measure = function(self, s) return #s * 9 end, line_height = 24 },
    large = { measure = function(self, s) return #s * 12 end, line_height = 30 },
}
ctx.invalidate = function(self, mode)
    assert(self == ctx, "invalidate called with dot syntax")
    invalidates = invalidates + 1
end
ctx.save_state = function(self)
    assert(self == ctx, "save_state called with dot syntax")
    saves = saves + 1
end
ctx.package = {
    open_text = function(self, name, opts)
        assert(self == ctx.package)
        if name ~= "cards.txt" then return nil end
        local lines = {}
        for line in (cards_data .. "\n"):gmatch("([^\n]*)\n") do
            if line ~= "" then lines[#lines + 1] = line end
        end
        local i = 0
        return {
            read_line = function(r)
                i = i + 1
                return lines[i]
            end,
            close = function(r) end,
        }
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

os = nil
io = nil
debug = nil
package = nil
__TEST = {}

local loader = assert(load(app_code, "index.lua"))
loader()

assert(on_load and on_draw and on_input and on_leave)
local ok, err = pcall(on_load, ctx)
assert(ok, "on_load failed: " .. tostring(err))
assert(#__TEST.api.cards() == 78)

draw_calls = 0
ok, err = pcall(on_draw, ctx, canvas)
assert(ok, "on_draw failed: " .. tostring(err))
assert(draw_calls > 5, "on_draw returned without using the API 2.x canvas")

local S = __TEST.api.state()
assert(S.daily_view == "waits")

on_input(ctx, { type = "pointer", phase = "down", gesture = "tap", x = 240, y = 300, time_ms = 1000 })
assert(S.daily_view == "waits")

on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 240, y = 300, time_ms = 1100 })
assert(S.daily_view == "front")

on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 40, y = 30, time_ms = 1400 })
assert(S.menu_open == true)

on_input(ctx, { type = "pointer", phase = "up", gesture = "tap", x = 200, y = 215, time_ms = 1700 })
assert(S.mode == "spread" and #S.spread_cards == 3 and S.menu_open == false)
local seen = {}
for _, entry in ipairs(S.spread_cards) do
    assert(not seen[entry.index], "spread contains a duplicate card")
    seen[entry.index] = true
end

local before = S.spread_pos
on_input(ctx, { type = "key", key = "right", phase = "down", time_ms = 2000 })
local after_one = S.spread_pos
on_input(ctx, { type = "key", key = "right", phase = "down", time_ms = 2100 })
assert(after_one ~= before)
assert(S.spread_pos == after_one, "duplicate key event was not debounced")

for _, mode in ipairs({ "daily", "spread", "study", "altar" }) do
    S.mode = mode
    if mode == "spread" and #S.spread_cards == 0 then S.spread_cards = __TEST.api.generate_spread("triad") end
    local before_draw = draw_calls
    ok, err = pcall(on_draw, ctx, canvas)
    assert(ok, "draw failed in mode " .. mode .. ": " .. tostring(err))
    assert(draw_calls > before_draw, "mode did not draw: " .. mode)
end

ok, err = pcall(on_leave)
assert(ok, "on_leave failed: " .. tostring(err))
assert(saves > 0, "save_state was not called")
assert(invalidates > 0, "invalidate was not called")

return true
'''

lua.execute(runtime_test)
print("Runtime simulation: PASS")
print("Card wording checks: PASS")
print("API 2.9 static checks: PASS")
print("=== Verification completed ===")
