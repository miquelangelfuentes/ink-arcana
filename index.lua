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
state = {
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

cards = {}                   -- { key, name, up_kw, up_read, rev_kw, rev_read, suit, num_str }
function get_card_count() return #cards end
local image_cache = {}

-- ------------------------------------------------------------------------------
-- Date & Day Helpers (Sandbox-Safe: No os.time)
-- ------------------------------------------------------------------------------
local function get_epoch_day()
    if ctx and ctx.clock and ctx.clock.now then
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
    end
    if ctx and ctx.sys then
        if ctx.sys.epoch_sec then
            local ok, s = pcall(function() return ctx.sys.epoch_sec and (ctx.sys:epoch_sec() or ctx.sys.epoch_sec()) end)
            if ok and tonumber(s) then return math.floor(tonumber(s) / 86400) end
        end
        if ctx.sys.millis then
            local ok, m = pcall(function() return ctx.sys.millis and (ctx.sys:millis() or ctx.sys.millis()) end)
            if ok and tonumber(m) then return math.floor(tonumber(m) / 86400000) end
        end
    end
    return 20760 -- default epoch day
end

local function get_formatted_date()
    if ctx and ctx.clock and ctx.clock.now then
        local ok, t = pcall(function() return ctx.clock:now() end)
        if ok and type(t) == "table" and t.year and t.month and t.day then
            return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
        end
    end
    return "INKARCANA"
end

-- ------------------------------------------------------------------------------
-- Embedded Fallback Cards Database (78 Rider-Waite-Smith Cards)
-- Guarantees offline integrity even if ctx.data is unavailable on firmware.
-- ------------------------------------------------------------------------------
local DEFAULT_CARDS_RAW = [===[
m00|The Fool|beginnings, trust, a leap|A new road opens and you do not need to see all of it yet. Step out with curiosity and an open heart; the first move matters more than the map.|recklessness, hesitation|Either you are leaping without looking, or you are standing at the edge too long. Check the ground, then decide.
m01|The Magician|skill, will, making it real|Everything you need is already on the table. Focus your attention, name what you want and use your tools: this is a day to act, not to wish.|scattered effort, trickery|Talent is there but aimed nowhere, or someone is selling more than they have. Gather your focus before you start.
m02|The High Priestess|intuition, stillness, the unseen|Not everything can be explained yet. Listen to the quiet voice, notice your dreams and wait; the answer is closer to feeling than to argument.|secrets, ignoring your instinct|You may be talking over your own inner voice, or something is hidden from you. Slow down and listen.
m03|The Empress|abundance, care, growth|A time of growth and comfort. Feed what you love, enjoy the senses, be generous with yourself and others; what you tend grows.|neglect, smothering|Care has tipped into too little or too much. Look after yourself as well as you look after others.
m04|The Emperor|structure, authority, order|Bring order to the situation. Clear rules, steady plans and calm leadership will get further than mood; take responsibility and set the frame.|rigidity, control|Structure has turned into control, or there is none at all. Loosen your grip, or build the walls you are missing.
m05|The Hierophant|tradition, teaching, belonging|Learn from those who walked the path before you. A teacher, a custom or a community can hold you now; the proven way is worth trying.|rebellion, empty ritual|A rule no longer fits you, or you follow it without knowing why. It may be time to find your own way.
m06|The Lovers|love, choice, alignment|A meaningful bond or a choice of the heart. Choose what agrees with your values; a true union starts with being honest with yourself.|imbalance, a hard choice|Something is out of tune in a relationship, or you are avoiding a choice. Ask what you really value.
m07|The Chariot|drive, victory, direction|Pull opposing forces in one direction and you will move fast. Determination and self-control carry the day; keep your eyes on the goal.|lack of direction, force|You are pushing without steering, or pulled two ways at once. Decide where you are going before you speed up.
m08|Strength|courage, patience, gentle power|Real strength is calm. Meet the wild thing, in you or around you, with patience and kindness instead of force, and it will follow you.|self-doubt, frustration|Your inner strength feels thin, or anger is doing the talking. Be gentle with yourself and start again.
m09|The Hermit|solitude, reflection, inner light|Step back from the noise. Time alone, a long walk or honest reflection will show you the next step; your own lamp is enough light.|isolation, withdrawal|Solitude has become hiding. Or you never give yourself quiet at all. Find the right measure.
m10|Wheel of Fortune|change, cycles, luck|The wheel turns. Notice what is changing around you and move with it rather than against it; what goes down comes up again.|resistance, a bad turn|Things are not going your way, or you are holding on against the turn. This too will pass; adjust.
m11|Justice|fairness, truth, consequences|Things come into balance. Be honest, weigh the facts and accept what follows from your choices; a fair decision is within reach.|unfairness, avoiding blame|Something is out of balance, or you are dodging your share of the responsibility. Set the record straight.
m12|The Hanged Man|pause, surrender, a new view|Hang in the in-between for a while. Letting go and looking from upside down shows you what pushing never would.|stalling, needless sacrifice|You are waiting without purpose or giving up too much. Decide whether the pause still serves you.
m13|Death|ending, transformation, release|Something is finished, and that clears the way. Let the old form go; the ending makes room for what is next. Rarely about a real death.|clinging, fear of change|You are holding on to what is already over. The change will come anyway; meet it.
m14|Temperance|balance, moderation, blending|Mix things in the right measure. Patience, calm and middle ways work now; take your time and let the parts blend.|excess, impatience|Too much of one thing, too little of another. Find the middle again before you go on.
m15|The Devil|attachment, temptation, shadow|Look at what has a hold on you: a habit, a desire, a fear. The chains are looser than they seem; seeing them is the first step to slipping them.|release, breaking free|You are starting to free yourself from something that held you. Keep going.
m16|The Tower|upheaval, sudden truth, collapse|Is something built on a weak base? Letting it fall is a shock, but it clears out illusions; from the rubble you can build on solid ground.|averting disaster, delayed change|You may be holding up a wall that needs to come down, or you have just escaped. Let the necessary change happen.
m17|The Star|hope, healing, renewal|After the storm, a clear sky. Rest, heal and trust that things can get better; your hope is not naive, it is a compass.|discouragement, lost faith|Hope feels far away. Small things you love can bring it back; look up again.
m18|The Moon|uncertainty, dreams, illusion|Not everything is what it seems. Walk carefully through the half-light, trust your instinct and let fears show you what they are made of.|confusion lifting, facing fears|The fog is thinning and the truth comes out. What frightened you may turn out smaller.
m19|The Sun|joy, success, vitality|Warmth, clarity and good energy. Notice what is going well, enjoy it, share it and let yourself be seen.|dimmed joy, overconfidence|The light is there but clouded, or you are too sure of yourself. Small joys still count.
m20|Judgement|awakening, a calling, reckoning|A call to rise. Look back honestly, forgive what needs forgiving and answer the voice asking you to become more yourself.|self-doubt, ignoring the call|You hear the call but turn away, or you judge yourself too harshly. Listen and give yourself a fair hearing.
m21|The World|completion, wholeness, arrival|A cycle is complete. Celebrate what you have done, gather the lessons and get ready for the next journey.|loose ends, delay|Almost there, but something is unfinished. Close the last chapter before you begin the new one.
w01|Ace of Wands|inspiration, a spark, potential|Look at the idea or burst of energy you have right now. Use it while it is hot: start the project, take the first step.|delay, a spark that fades|The energy is there but blocked or fading. Find what stops it, or wait for a better moment.
w02|Two of Wands|planning, choices, the wider world|You hold the world in your hand and look further. Plan your next move and dare to think bigger than where you stand.|fear of the unknown, poor planning|You hesitate to leave the familiar, or plans stay plans. Take one concrete step.
w03|Three of Wands|expansion, foresight, progress|Think of what you have already set in motion. Keep looking ahead and prepare for it to grow.|setbacks, limited view|Results take longer than you hoped. Adjust the plan rather than giving up on it.
w04|Four of Wands|celebration, home, harmony|A moment to celebrate a milestone with the people you love. Home and community feel solid.|unsettled home, a cancelled party|Harmony at home is shaky, or celebration is postponed. Mend the base.
w05|Five of Wands|competition, conflict, friction|Many voices, many sticks. Friction can be play or strife; use the competition to sharpen your ideas, not to wound.|avoiding conflict, ending a quarrel|Tension winds down, or you are avoiding a fight that needs to happen.
w06|Six of Wands|recognition, success, confidence|You are seen for what you achieved. Accept the praise with grace; your confidence is earned.|ego, lack of recognition|Either pride runs ahead of you or the applause does not come. Your worth does not depend on it.
w07|Seven of Wands|defence, standing firm, perseverance|You are on the high ground and challengers come. Hold your position; you have good reason to stand firm.|giving up, overwhelmed|The pressure is getting to you. Choose which fights are worth it.
w08|Eight of Wands|speed, movement, momentum|Where can you move quickly? Answer the message, make the trip, keep the momentum going.|delays, frustration|Things slow down or scatter. Patience, and check where the energy is going.
w09|Nine of Wands|resilience, last stretch, guard|Tired but still standing. You have been through a lot; one more push and you are through.|exhaustion, defensiveness|You are worn out or guarding against everything. Rest, and let someone help.
w10|Ten of Wands|burden, responsibility, overload|You carry too much. You may be close to the goal, but ask which of these sticks are truly yours to carry.|putting down the load|You are starting to delegate or let go. Keep putting things down.
w11|Page of Wands|enthusiasm, exploration, curiosity|A curious, eager energy. Try something new, follow what excites you and stay open to surprises.|impatience, half-started ideas|Lots of sparks but nothing lit. Pick one idea and stay with it.
w12|Knight of Wands|adventure, passion, action|Charge ahead with fire and charm. A bold move, a trip, a passion; just watch your speed.|haste, scattered energy|Rushing in without a plan, or starting fights. Slow down before you burn out.
w13|Queen of Wands|confidence, warmth, determination|Warm, bold and magnetic. Lead with confidence, shine without apology and keep your focus.|jealousy, insecurity|Your fire turns inward as doubt or envy. Return to what makes you shine.
w14|King of Wands|vision, leadership, boldness|See the big picture and lead others toward it. Take charge with vision and integrity.|impulsiveness, high expectations|Leadership tips into domineering, or your vision runs ahead of the means.
c01|Ace of Cups|new feelings, love, compassion|The heart opens: new love, friendship, or a wave of feeling. Let it flow.|blocked feelings, emptiness|Emotions are held back or drained. Make room for them again.
c02|Two of Cups|partnership, connection, mutual respect|Two people meet as equals. A bond, a reconciliation or a good partnership forms.|imbalance, separation|A relationship is out of balance or drifting. Talk honestly.
c03|Three of Cups|friendship, community, celebration|Raise a glass with friends. Shared joy grows; lean on the people around you.|overindulgence, isolation|Too much partying, or feeling left out. Look for one true friend.
c04|Four of Cups|apathy, contemplation, missed chances|You are bored or withdrawn and do not see the cup being offered. Look up.|new interest, acceptance|You are coming out of the slump and noticing what is on offer.
c05|Five of Cups|loss, grief, regret|You mourn what spilled. It is right to grieve, but two cups are still standing behind you.|acceptance, moving on|You are making peace with a loss and turning toward what remains.
c06|Six of Cups|memories, childhood, kindness|A sweet memory, an old friend, simple kindness. Let the past warm you, not hold you.|stuck in the past|Nostalgia keeps you from the present. Honour the past and walk on.
c07|Seven of Cups|choices, daydreams, illusion|Many dazzling options, not all real. Pick one and test it in the real world.|clarity, decision|The fog clears and you see what truly matters. Choose.
c08|Eight of Cups|walking away, seeking more|You leave something that no longer fulfils you. It is sad and it is right.|fear of leaving, drifting|You know you should go but you stay, or you wander without aim.
c09|Nine of Cups|Contentment|The wish granted, and the satisfaction of it. Contentment, comfort, plenty. Enjoy it without mistaking it for everything.|smugness, unfulfilled wishes|Getting what you wanted did not feel as expected. Look deeper.
c10|Ten of Cups|happiness, family, harmony|Lasting joy, a loving home, a sense of belonging. Everything in its place.|broken harmony, misaligned values|Family or close ties are strained. Mend what matters most.
c11|Page of Cups|sensitivity, a creative start, a message of the heart|A gentle surprise, an intuitive flash, an invitation to feel and create.|emotional immaturity, blocked creativity|Feelings are moody or hidden. Let them out in a healthy way.
c12|Knight of Cups|romance, charm, following the heart|An offer, a romantic gesture, a creative pursuit. Follow your heart with grace.|moodiness, unrealistic dreams|Charm without substance, or dreams that drift. Ground them.
c13|Queen of Cups|empathy, calm, intuition|Deeply caring and emotionally wise. Listen with the heart, hold space for others and for yourself.|over-giving, emotional drain|You take on too much of others' feelings. Protect your own calm.
c14|King of Cups|emotional balance, diplomacy, generosity|Calm in rough water. Lead with compassion and a steady heart.|moodiness, manipulation|Emotions are suppressed or used to control. Find honest calm.
s01|Ace of Swords|clarity, truth, breakthrough|A clear thought cuts through confusion. Speak the truth, make the decision.|confusion, harsh words|Thoughts are clouded or the sword cuts too sharply. Think before you speak.
s02|Two of Swords|stalemate, avoidance, a hard choice|You hold two options blindfolded. Take off the blindfold and look at the facts.|indecision lifting, overload|The deadlock breaks, or the pressure becomes too much. Decide.
s03|Three of Swords|heartbreak, sorrow, painful truth|A painful truth or loss. Let it hurt; naming the pain begins the healing.|recovery, forgiveness|The wound is starting to heal. Let go of the sharp words.
s04|Four of Swords|rest, recovery, retreat|Lay down your swords and rest. Recovery now prepares you for what comes.|restlessness, burnout|You need rest but will not take it. Stop before your body stops you.
s05|Five of Swords|conflict, winning at a cost|A fight won by hurting others is hardly a victory. Choose your battles.|reconciliation, letting go|Ready to end the quarrel or walk away. Make peace.
s06|Six of Swords|transition, moving on, calmer waters|You are leaving troubled waters for calmer ones. The journey is quiet but healing.|unfinished business, resisting change|You cannot quite leave, or the baggage comes along. Lighten the load.
s07|Seven of Swords|strategy, stealth, deception|Is someone cutting corners, perhaps you? Be clever, but be honest about it.|confession, coming clean|Secrets come out, or you decide to stop cutting corners.
s08|Eight of Swords|feeling trapped, self-limiting beliefs|The bindings are mostly in your mind. Look again: there is a way out.|freedom, new perspective|You are seeing past the old beliefs and stepping free.
s09|Nine of Swords|anxiety, worry, sleepless nights|Night thoughts are louder than the facts. Share the worry; it shrinks in daylight.|hope, reaching out|The worst of the anxiety is lifting. Keep talking about it.
s10|Ten of Swords|rock bottom, painful ending|It cannot get worse, which means it starts getting better. The sun is rising behind the scene.|recovery, survival|You are getting up after a fall. Slowly but surely.
s11|Page of Swords|curiosity, new ideas, vigilance|A sharp, curious mind. Ask questions, learn, watch closely.|gossip, all talk|Words without action, or prying where you should not.
s12|Knight of Swords|ambition, haste, determination|Charging ahead with a clear goal. Speak up and act, but do not trample others.|recklessness, rudeness|Rushing with sharp words. Slow down and think about consequences.
s13|Queen of Swords|clarity, independence, honest words|Clear-headed and fair. Set boundaries, say what is true, kindly.|coldness, bitterness|Truth used as a weapon. Soften the edge without losing the point.
s14|King of Swords|intellect, authority, truth|Decide with logic and fairness. Clear thinking and ethics lead.|manipulation, abuse of power|Cleverness used to control. Watch for cold calculation, in yourself too.
p01|Ace of Pentacles|opportunity, prosperity, a new venture|A solid new chance: a job, money, a project with roots. Plant it well.|missed chance, poor planning|An opportunity slips or is built on sand. Check the foundation.
p02|Two of Pentacles|balance, juggling, adaptability|You keep many things in the air. Stay flexible and keep your priorities straight.|overwhelmed, dropping the ball|Too much to juggle. Put something down before everything falls.
p03|Three of Pentacles|teamwork, craft, collaboration|Good work done together. Your skill is noticed; build with others.|disharmony, poor work|The team is not pulling together. Clear up roles and standards.
p04|Four of Pentacles|security, saving, control|You hold tight to what you have. Saving is wise; hoarding is not.|letting go, generosity|Loosening your grip on money or control. Find a healthy balance.
p05|Five of Pentacles|hardship, worry, feeling left out|Times are lean or you feel out in the cold. Ask for help; look for the lit window.|recovery, accepting help|Things are getting easier. Accept the help offered.
p06|Six of Pentacles|generosity, giving and receiving|Give and receive fairly. Share what you can; accept help without shame.|strings attached, imbalance|Generosity with conditions, or a one-sided exchange. Even it out.
p07|Seven of Pentacles|patience, long-term view, assessment|The crop is growing. Pause to see what is working before you invest more.|impatience, poor returns|Effort without results. Change the approach, not only the effort.
p08|Eight of Pentacles|diligence, skill, practice|Head down, steady work. Practice makes mastery; enjoy the craft.|perfectionism, boredom|Working hard at the wrong thing, or stuck in routine. Refresh the goal.
p09|Nine of Pentacles|independence, comfort, self-reliance|You built this. Enjoy the comfort and freedom you have earned.|overwork, dependence|Comfort feels shaky or lonely. Rebuild your own foundation.
p10|Ten of Pentacles|legacy, family wealth, lasting security|Long-term stability and things that last: family, home, inheritance.|instability, family disputes|Money or legacy stirs trouble. Think about what you really want to pass on.
p11|Page of Pentacles|study, a new skill, practical start|A student mind. Learn something useful and take the first practical step.|lack of progress, procrastination|Plans without effort. Start small, but start.
p12|Knight of Pentacles|reliability, routine, hard work|Slow and steady wins. Be methodical, dependable and patient.|stuck, boredom, laziness|Routine has become a rut. Add some movement.
p13|Queen of Pentacles|nurture, practicality, home|Warm and grounded. Care for body, home and finances with practical love.|self-neglect, overwork|Looking after everything except yourself. Restore your own balance.
p14|King of Pentacles|abundance, security, success|Stable success and wise use of resources. Lead with generosity and good sense.|greed, stubbornness|Too focused on wealth or control. Remember what it is for.
]===]

local function parse_card_line(l)
    local key, name, up_kw, up_read, rev_kw, rev_read = l:match("^([%w_]+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)")
    if key and name then
        local clean_up_kw = up_kw:match("^([^,]+)") or up_kw
        clean_up_kw = clean_up_kw:gsub("^%s+", ""):gsub("%s+$", "")
        clean_up_kw = clean_up_kw:sub(1,1):upper() .. clean_up_kw:sub(2)

        local clean_rev_kw = rev_kw:match("^([^,]+)") or rev_kw
        clean_rev_kw = clean_rev_kw:gsub("^%s+", ""):gsub("%s+$", "")
        clean_rev_kw = clean_rev_kw:sub(1,1):upper() .. clean_rev_kw:sub(2)

        local s_prefix = key:sub(1,1)
        local suit = "major"
        if s_prefix == "w" then suit = "wands"
        elseif s_prefix == "c" then suit = "cups"
        elseif s_prefix == "s" then suit = "swords"
        elseif s_prefix == "p" then suit = "pentacles"
        end

        return {
            key = key,
            name = name,
            up_kw = clean_up_kw,
            up_read = up_read,
            rev_kw = clean_rev_kw,
            rev_read = rev_read,
            suit = suit
        }
    end
    return nil
end

local function load_cards()
    cards = {}
    local P = ctx and (ctx.data or ctx.package)
    if P then
        local ok, r = pcall(function() return P:open_text("cards.txt", { max_line_bytes = 2048 }) end)
        if ok and r and type(r) ~= "string" then
            while true do
                local okl, l = pcall(function() return r:read_line() end)
                if not okl or not l then break end
                local card = parse_card_line(l)
                if card then table.insert(cards, card) end
            end
            pcall(function() r:close() end)
        end
    end

    -- Embedded fail-safe: populate all 78 cards if data file was unreadable
    if #cards == 0 then
        for l in DEFAULT_CARDS_RAW:gmatch("[^\r\n]+") do
            local card = parse_card_line(l)
            if card then table.insert(cards, card) end
        end
    end
end

-- ------------------------------------------------------------------------------
-- Image Loader & Caching (Atkinson 1-bit PNGs from art_l1.txt / art_l2.txt)
-- ------------------------------------------------------------------------------
local PER_FILE = 39

local function read_art_line(num)
    local file_idx = math.floor((num - 1) / PER_FILE) + 1
    local file = "art_l" .. file_idx .. ".txt"
    local line_idx = ((num - 1) % PER_FILE) + 1

    local P = ctx and (ctx.data or ctx.package)
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

    if ctx and ctx.capabilities and ctx.capabilities.image_decode and ctx.image and ctx.base64 then
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
    return ctx and ctx.fonts and ctx.fonts[name]
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
    local seed = 1234567
    if ctx and ctx.sys and ctx.sys.millis then
        pcall(function() seed = ctx.sys.millis and (ctx.sys:millis() or ctx.sys.millis()) or seed end)
    end
    math.randomseed(seed)
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

    local total_available = #cards
    if total_available < count then
        count = total_available
    end

    if count <= 0 then
        return result
    end

    local attempts = 0
    while #result < count and attempts < 100 do
        attempts = attempts + 1
        local idx = math.random(1, #cards)
        if not chosen[idx] then
            chosen[idx] = true
            local is_rev = state.reversals_enabled and (math.random(1, 100) <= 25) or false
            table.insert(result, {
                index = idx,
                reversed = is_rev,
                label = labels[#result + 1] or ("Card " .. (#result + 1))
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

function on_load()
    load_cards()

    local today_day = get_epoch_day()
    state.last_day = today_day

    local num_c = #cards > 0 and #cards or 1
    local s = (today_day * 2654435761) % 2147483648
    state.daily_index = (s % num_c) + 1
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

function on_enter()
    if ctx and ctx.invalidate then
        pcall(function() ctx.invalidate() end)
    end
end

function on_draw(a, b)
    local draw_g = (b and type(b) == "table" and b.rect) and b or ((a and type(a) == "table" and a.rect) and a or g)
    local g = draw_g
    if not g then return end

    pcall(function() g:clear(0) end)
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

function on_input(a, b)
    local event = (b and type(b) == "table" and (b.x or b.type)) and b or a
    if not event then return end

    local x = tonumber(event.x) or -1
    local y = tonumber(event.y) or -1
    local is_tap = (event.type == "down")

    -- Key navigation
    local is_prev, is_next, is_trigger = false, false, false
    if event.type == "key" and event.phase ~= "up" then
        local key = event.key
        if key == "ok" or key == "enter" or key == "space" then is_trigger = true
        elseif key == "left" or key == "up" then is_prev = true
        elseif key == "right" or key == "down" then is_next = true
        elseif key == "menu" then
            state.menu_open = not state.menu_open
            if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
            return true
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
        if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
        return true
    end

    -- Menu button tap (top-left)
    if is_tap and x >= 15 and x <= 75 and y >= 15 and y <= 60 then
        state.menu_open = true
        if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
        return true
    end

    -- --------------------------------------------------------------------------
    -- 2. DESK ALTAR MODE (Tap anywhere to return)
    -- --------------------------------------------------------------------------
    if state.mode == "altar" then
        if is_tap or is_trigger then
            state.mode = "daily"
        end
        if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
        return true
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
            if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
            return true
        elseif is_next then
            state.daily_index = (state.daily_index % #cards) + 1
            state.daily_view = "front"
            state.has_turned_today = true
            if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
            return true
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
        if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
        return true
    end

    -- --------------------------------------------------------------------------
    -- 4. MULTI-CARD SPREADS MODE
    -- --------------------------------------------------------------------------
    if state.mode == "spread" then
        local count = #state.spread_cards
        if count > 0 then
            if is_prev or (is_tap and x >= 30 and x <= 140 and y >= 710 and y <= 765) then
                state.spread_pos = ((state.spread_pos - 2 + count) % count) + 1
                state.spread_view = "front"
                if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
                return true
            elseif is_next or (is_tap and x >= 340 and x <= 450 and y >= 710 and y <= 765) then
                state.spread_pos = (state.spread_pos % count) + 1
                state.spread_view = "front"
                if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
                return true
            elseif (is_tap and x >= 170 and x <= 310 and y >= 710 and y <= 765) or is_trigger then
                state.spread_view = (state.spread_view == "front") and "reading" or "front"
                if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
                return true
            end

            -- Tapping card body toggles reading
            if is_tap and x >= CARD_X and x <= CARD_X + CARD_W and y >= 100 and y <= 100 + CARD_H then
                state.spread_view = (state.spread_view == "front") and "reading" or "front"
            end
        end
        if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
        return true
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
        if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
        return true
    end

    if ctx and ctx.invalidate then pcall(function() ctx.invalidate() end) end
    return true
end

function on_leave()
    if ctx then
        ctx.state = {
            last_day = state.last_day,
            daily_index = state.daily_index,
            daily_reversed = state.daily_reversed,
            daily_view = state.daily_view,
            has_turned_today = state.has_turned_today,
            reversals_enabled = state.reversals_enabled
        }
        if ctx.save then pcall(function() ctx.save() end) end
    end
end

function on_unload()
    on_leave()
end

function on_tick()
end
