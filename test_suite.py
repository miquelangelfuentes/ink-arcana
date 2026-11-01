import os
import sys
import lupa
from lupa import LuaRuntime

print("=== STARTING EXHAUSTIVE TEST SUITE FOR INKARCANA ===")

# Test 1: Lupa Sandbox Simulation
lua = LuaRuntime(unpack_returned_tuples=True)

test_sandbox = '''
local logs = {}
ctx = {
    clock = {
        now = function() return { epoch_sec = 1730494800, year = 2026, month = 11, day = 1, hour = 21, minute = 0, second = 0 } end
    },
    sys = {
        millis = function() return 1234567 end,
        epoch_sec = function() return 1730494800 end
    },
    invalidate = function() table.insert(logs, "invalidate") end,
    state = {},
    save = function() table.insert(logs, "save") end,
    fonts = {
        small = { measure = function(self, s) return #s * 7 end, line_height = 20 },
        medium = { measure = function(self, s) return #s * 9 end, line_height = 24 },
        large = { measure = function(self, s) return #s * 12 end, line_height = 30 }
    }
}

g = {
    clear = function(self, c) table.insert(logs, "g:clear(" .. tostring(c) .. ")") end,
    rect = function(self, x, y, w, h, opt) end,
    circle = function(self, x, y, r, opt) end,
    line = function(self, x1, y1, x2, y2, opt) end,
    text = function(self, x, y, str, opt) end,
    text_width = function(self, str, opt) return #str * 8 end,
    size = function(self) return 480, 800 end,
    image = function(self, img, x, y, opt) end,
}

-- Strip forbidden standard libraries (firmware sandbox condition)
os = nil
io = nil
debug = nil
package = nil

-- Load app index.lua
local loader = assert(load(app_code, "index.lua"))
loader()

-- 1. Test on_load (Fallback when ctx.data is nil)
assert(on_load ~= nil, "on_load must be defined")
local ok_load, err_load = pcall(on_load)
assert(ok_load, "on_load failed: " .. tostring(err_load))
assert(#cards == 78, "Embedded cards count must be 78, got " .. tostring(#cards))
assert(state.daily_index >= 1 and state.daily_index <= 78, "Invalid daily_index: " .. tostring(state.daily_index))
assert(#state.spread_cards == 3, "Triad spread must have 3 cards, got " .. tostring(#state.spread_cards))

-- 2. Test on_enter
assert(on_enter ~= nil, "on_enter must be defined")
local ok_enter, err_enter = pcall(on_enter)
assert(ok_enter, "on_enter failed: " .. tostring(err_enter))

-- 3. Test on_draw with different invocation signatures
assert(on_draw ~= nil, "on_draw must be defined")
-- Zero-args signature (Licorice standard)
local ok_draw0, err_draw0 = pcall(on_draw)
assert(ok_draw0, "on_draw() failed: " .. tostring(err_draw0))

-- One-arg signature
local ok_draw1, err_draw1 = pcall(on_draw, g)
assert(ok_draw1, "on_draw(g) failed: " .. tostring(err_draw1))

-- Two-args signature
local ok_draw2, err_draw2 = pcall(on_draw, ctx, g)
assert(ok_draw2, "on_draw(ctx, g) failed: " .. tostring(err_draw2))

-- 4. Test all modes on_draw
local modes = { "daily", "spread", "study", "altar" }
for _, m in ipairs(modes) do
    state.mode = m
    local ok, err = pcall(on_draw)
    assert(ok, "on_draw in mode " .. m .. " failed: " .. tostring(err))
end

-- Test views within Daily mode
state.mode = "daily"
for _, v in ipairs({ "waits", "front", "reading" }) do
    state.daily_view = v
    local ok, err = pcall(on_draw)
    assert(ok, "on_draw in daily_view " .. v .. " failed: " .. tostring(err))
end

-- Test views within Spread mode
state.mode = "spread"
for _, v in ipairs({ "front", "reading" }) do
    state.spread_view = v
    local ok, err = pcall(on_draw)
    assert(ok, "on_draw in spread_view " .. v .. " failed: " .. tostring(err))
end

-- Test views within Study mode
state.mode = "study"
for _, rev in ipairs({ false, true }) do
    state.study_revealed = rev
    local ok, err = pcall(on_draw)
    assert(ok, "on_draw in study mode (revealed=" .. tostring(rev) .. ") failed: " .. tostring(err))
end

-- Test Menu overlay on_draw
state.menu_open = true
local ok_menu, err_menu = pcall(on_draw)
assert(ok_menu, "on_draw with menu_open=true failed: " .. tostring(err_menu))
state.menu_open = false

-- 5. Test on_input with touch events
local ok_inp1, err_inp1 = pcall(on_input, { type = "down", x = 240, y = 400 })
assert(ok_inp1, "on_input touch failed: " .. tostring(err_inp1))

-- Test on_input with MISSING coordinates (e.g. key event or nil coordinates)
local ok_inp2, err_inp2 = pcall(on_input, { type = "key", key = "right", phase = "down" })
assert(ok_inp2, "on_input key right failed: " .. tostring(err_inp2))

local ok_inp3, err_inp3 = pcall(on_input, { type = "key", key = "left", phase = "down" })
assert(ok_inp3, "on_input key left failed: " .. tostring(err_inp3))

local ok_inp4, err_inp4 = pcall(on_input, { type = "key", key = "ok", phase = "down" })
assert(ok_inp4, "on_input key ok failed: " .. tostring(err_inp4))

local ok_inp5, err_inp5 = pcall(on_input, { type = "key", key = "menu", phase = "down" })
assert(ok_inp5, "on_input key menu failed: " .. tostring(err_inp5))
assert(state.menu_open == true, "menu should have opened on menu key")

-- Test menu selection touch
local ok_inp6, err_inp6 = pcall(on_input, { type = "down", x = 200, y = 250 }) -- Triad Spread
assert(ok_inp6, "on_input menu select failed: " .. tostring(err_inp6))
assert(state.mode == "spread", "mode should have changed to spread")
assert(state.menu_open == false, "menu should have closed")

-- 6. Test on_leave and on_unload
local ok_leave, err_leave = pcall(on_leave)
assert(ok_leave, "on_leave failed: " .. tostring(err_leave))
assert(ctx.state.daily_index ~= nil, "state must be saved to ctx.state")

local ok_unload, err_unload = pcall(on_unload)
assert(ok_unload, "on_unload failed: " .. tostring(err_unload))

return true
'''

with open('index.lua', 'r', encoding='utf-8') as f:
    app_code = f.read()

lua.execute(f'app_code = {repr(app_code)}')
result = lua.execute(test_sandbox)
print("Lua Sandbox Simulation Result: SUCCESS (100% PASS)")
