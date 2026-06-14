---@diagnostic disable: undefined-global
-- DialogUI auto-advance: optionally skim trivial NPC interactions.
--
-- The modern DialogueUI ships a curated list of retail gossip-option IDs to
-- auto-select; those don't exist on 3.3.5a (and 3.3.5 gossip options are
-- positional, not ID-stable), so we use the portable heuristic instead: when an
-- NPC presents exactly ONE thing, advance it automatically. It also auto-finishes
-- a quest turn-in that has no reward choice to make. Off by default; opt in from
-- the options panel. It never auto-ACCEPTS a new quest.

DialogUI_Auto = DialogUI_Auto or {};

-- Guards against a runaway loop if an option re-presents the same single gossip.
local autoCount = 0;
local AUTO_LIMIT = 25;

local function Enabled()
    return DialogUISettings and DialogUISettings.autoSelect;
end

-- Option count: GetNumGossipOptions exists on 3.3.5a, but derive it from the
-- (text,type) pairs of GetGossipOptions as a guaranteed fallback.
local function CountGossipOptions()
    if (GetNumGossipOptions) then
        return GetNumGossipOptions();
    end
    return select("#", GetGossipOptions()) / 2;
end

-- ===== Per-NPC blocklist (entry-ID keyed) =====

-- Parse a creature/object entry ID from a 3.3.5a GUID. The entry sits in a fixed
-- hex slice; we normalize to a 16-digit string and read it. Only world objects
-- (type nibble "F...": creatures, GOs, pets, vehicles) carry an entry — players
-- return nil so they can never be added.
local function GUIDToEntry(guid)
    if (not guid) then return nil; end
    local hex = guid;
    if (string.sub(hex, 1, 2) == "0x" or string.sub(hex, 1, 2) == "0X") then
        hex = string.sub(hex, 3);
    end
    while (string.len(hex) < 16) do
        hex = "0" .. hex;
    end
    if (string.upper(string.sub(hex, 1, 1)) ~= "F") then
        return nil; -- not a world object (e.g. a player target)
    end
    local entry = tonumber(string.sub(hex, 7, 10), 16);
    if (entry and entry > 0) then
        return entry;
    end
    return nil;
end

local function EnsureBlocklist()
    if (not DialogUISettings) then DialogUISettings = {}; end
    if (not DialogUISettings.autoBlocklist) then DialogUISettings.autoBlocklist = {}; end
    return DialogUISettings.autoBlocklist;
end

local function IsBlocked(guid)
    local entry = GUIDToEntry(guid);
    if (not entry) then return false; end
    local bl = DialogUISettings and DialogUISettings.autoBlocklist;
    return (bl and bl[entry] ~= nil) and true or false;
end
DialogUI_Auto.IsBlocked = IsBlocked;

-- The NPC to act on for a slash command: the open dialog's "npc", else the target.
local function CurrentNPC()
    if (UnitExists("npc")) then
        return UnitGUID("npc"), UnitName("npc");
    elseif (UnitExists("target")) then
        return UnitGUID("target"), UnitName("target");
    end
    return nil, nil;
end

local function Msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff88ccffDialogUI|r: " .. text);
end

function DialogUI_Auto_Block()
    local guid, name = CurrentNPC();
    local entry = GUIDToEntry(guid);
    if (not entry) then
        Msg("no NPC found — target or open the NPC, then /dui block.");
        return;
    end
    EnsureBlocklist()[entry] = name or ("NPC " .. entry);
    Msg("auto-advance will SKIP " .. (name or ("entry " .. entry)) .. "  (" .. entry .. ").");
end

function DialogUI_Auto_Unblock()
    local guid, name = CurrentNPC();
    local entry = GUIDToEntry(guid);
    if (not entry) then
        Msg("no NPC found — target or open the NPC, then /dui unblock.");
        return;
    end
    local bl = EnsureBlocklist();
    if (bl[entry]) then
        local nm = bl[entry];
        bl[entry] = nil;
        Msg("auto-advance restored for " .. nm .. "  (" .. entry .. ").");
    else
        Msg((name or ("entry " .. entry)) .. " (" .. entry .. ") isn't blocked.");
    end
end

function DialogUI_Auto_ListBlocked()
    local bl = EnsureBlocklist();
    Msg("auto-advance blocklist:");
    local any = false;
    for entry, name in pairs(bl) do
        any = true;
        DEFAULT_CHAT_FRAME:AddMessage("   - " .. tostring(name) .. "  (" .. tostring(entry) .. ")");
    end
    if (not any) then
        DEFAULT_CHAT_FRAME:AddMessage("   (empty)");
    end
end

-- Called from the gossip GOSSIP_SHOW handler. Returns true if it advanced (so the
-- caller can skip showing the frame and avoid a flash).
function DialogUI_Auto_HandleGossip()
    if (not Enabled()) then return false; end
    if (IsBlocked(UnitGUID("npc"))) then return false; end
    if (autoCount >= AUTO_LIMIT) then return false; end

    local nOpt = CountGossipOptions() or 0;
    local nAvail = (GetNumGossipAvailableQuests and GetNumGossipAvailableQuests()) or 0;
    local nActive = (GetNumGossipActiveQuests and GetNumGossipActiveQuests()) or 0;

    if (nOpt == 1 and nAvail == 0 and nActive == 0) then
        autoCount = autoCount + 1;
        SelectGossipOption(1);
        return true;
    elseif (nOpt == 0 and nAvail == 1 and nActive == 0) then
        autoCount = autoCount + 1;
        SelectGossipAvailableQuest(1);
        return true;
    elseif (nOpt == 0 and nActive == 1 and nAvail == 0) then
        autoCount = autoCount + 1;
        SelectGossipActiveQuest(1);
        return true;
    end
    return false;
end

-- QUEST_PROGRESS: advance a turn-in that's ready. Returns true if it did.
function DialogUI_Auto_HandleQuestProgress()
    if (not Enabled()) then return false; end
    if (IsBlocked(UnitGUID("npc"))) then return false; end
    if (IsQuestCompletable()) then
        CompleteQuest();
        return true;
    end
    return false;
end

-- QUEST_COMPLETE: claim the reward only when there's no choice to make (so we
-- never pick the wrong item for the player). Returns true if it claimed.
function DialogUI_Auto_HandleQuestComplete()
    if (not Enabled()) then return false; end
    if (IsBlocked(UnitGUID("npc"))) then return false; end
    if (GetNumQuestChoices() == 0) then
        GetQuestReward(0);
        return true;
    end
    return false;
end

-- Reset the loop guard whenever an interaction ends.
local resetter = CreateFrame("Frame");
resetter:RegisterEvent("GOSSIP_CLOSED");
resetter:RegisterEvent("QUEST_FINISHED");
resetter:SetScript("OnEvent", function()
    autoCount = 0;
end);
