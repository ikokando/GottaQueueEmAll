-------------------------------------------------------------------------------
--  UI/KeyProbe.lua  --  /gotta keyprobe: does the key reader work here?
--
--  Prints the key reader's self-test (UI/KeyRead.lua) and, for the current
--  search results, each title as WoW shows it next to the level read from
--  it, so both can be compared in the chat (for bug reports).
-------------------------------------------------------------------------------
local _, ns = ...
local UI = ns.UI
local T, D, KR = UI.Theme, UI.Data, UI.KeyRead
local P = {}
UI.KeyProbe = P

local SHOWN = 12   -- result lines printed

function P.Run()
    KR.Retest()
    local works = KR.Works()
    local _, why, scale, tries = KR.State()
    ns.Print(("keyprobe: key reader %s%s (scale %s, tries %d)"):format(
        works and "|cff3fb060works|r" or "|cffe05a4eis off|r", why and (": " .. why) or "",
        scale and ("%.3f"):format(scale) or "-", tries or 0))
    for _, line in ipairs(KR.diag or {}) do print("  " .. line) end

    local read, total = 0, 0
    for _, id in ipairs((D.ResultIDs())) do
        local r = D.Read(id)
        if r then
            total = total + 1
            if r.key then read = read + 1 end
            if total <= SHOWN then
                print(("  %d. %s:  %s|r  ->  %s"):format(total, T.Short(r.dungeon), r.title or "?",
                    r.key and ("+" .. r.key) or "|cff8d98a8not read|r"))
            end
        end
    end
    if total == 0 then
        ns.Print("keyprobe: no Mythic+ results to read. Search first, then run it again.")
    else
        ns.Print(("keyprobe: %d results, key read for %d. Compare the left and right side above."):format(total, read))
    end
end
