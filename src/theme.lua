---@diagnostic disable: undefined-global
-- DialogUI theme system: a Lua-only light/dark mode for WotLK 3.3.5a.
--
-- The modern DialogueUI ships two full texture sets (Theme_Brown / Theme_Dark).
-- We don't have those assets here, so instead of swapping textures we recreate
-- the EFFECT: darken the existing parchment backgrounds with a vertex-color
-- multiply and flip the (normally dark-brown) text to a light ivory so it stays
-- legible. State is persisted account-wide in DialogUISettings and toggled with
-- /dialogui dark (aliases: /dui, plain /dialogui = toggle).

DialogUI_Theme = DialogUI_Theme or {};

-- Color-key remap consumed by SetFontColor in the quest & gossip frames.
-- "DarkBrown" is the primary prose / plain-gossip color, so in dark mode it has
-- to become light. "Ivory" is already light (used for the option-button text on
-- the darker OptionBackground texture) and stays light in both modes.
DialogUI_Theme.colorKeys = {
    light = {
        DarkBrown  = {0.19, 0.17, 0.13},
        LightBrown = {0.50, 0.36, 0.24},
        Ivory      = {0.87, 0.86, 0.75},
    },
    dark = {
        DarkBrown  = {0.85, 0.81, 0.69},
        LightBrown = {0.74, 0.62, 0.45},
        Ivory      = {0.92, 0.90, 0.82},
    },
};

-- Dark mode swaps the actual texture FILES (not just a tint). The modern
-- DialogueUI ships a distinct dark parchment, so we mirror that with dark art
-- generated from this addon's own textures (same size/layout/alpha). Keyed by a
-- lowercased path fragment so it matches whatever case the XML/Lua used.
local PARCH = "Interface\\AddOns\\DialogUI\\src\\assets\\art\\parchment\\";
DialogUI_Theme.textureSwap = {
    { key = "parchment\\parchment",    light = PARCH .. "Parchment",               dark = PARCH .. "Parchment-Dark" },
    { key = "bookpage",                light = PARCH .. "BookPage",                 dark = PARCH .. "BookPage-Dark" },
    { key = "optionbackground-common", light = PARCH .. "OptionBackground-Common", dark = PARCH .. "OptionBackground-Common-Dark" },
    { key = "optionbackground-grey",   light = PARCH .. "OptionBackground-Grey",   dark = PARCH .. "OptionBackground-Grey-Dark" },
    { key = "rewardchoice-pending",    light = PARCH .. "RewardChoice-Pending",    dark = PARCH .. "RewardChoice-Pending-Dark" },
    { key = "divider-h",               light = PARCH .. "Divider-H",                dark = PARCH .. "Divider-H-Dark" },
    { key = "portraitring",            light = PARCH .. "PortraitRing",             dark = PARCH .. "PortraitRing-Dark" },
};

-- Positive-action buttons get a red plate in dark mode (the dark-theme accent).
local ACCENT_BUTTONS = {
    "DQuestFrameAcceptButton",        -- detail: Accept
    "DQuestFrameCompleteQuestButton", -- reward: Complete Quest
    "DQuestFrameCompleteButton",      -- progress: Complete
};

function DialogUI_Theme:GetMode()
    if (DialogUISettings and DialogUISettings.darkMode) then
        return "dark";
    end
    return "light";
end

-- Returns {r,g,b} for a color key under the active theme (nil if unknown).
function DialogUI_Theme:GetColor(key)
    local set = self.colorKeys[self:GetMode()] or self.colorKeys.light;
    return set[key];
end

-- Returns the themed path for a texture, or nil if it isn't a themed texture.
function DialogUI_Theme:ResolveTexture(currentPath, dark)
    if (not currentPath) then
        return nil;
    end
    local low = string.lower(currentPath);
    for _, entry in ipairs(self.textureSwap) do
        if (string.find(low, entry.key, 1, true)) then
            return (dark and entry.dark) or entry.light;
        end
    end
    return nil;
end

-- Path code can set directly (e.g. gossip buttons recolor their normal texture).
function DialogUI_Theme:OptionBackground()
    if (self:GetMode() == "dark") then
        return PARCH .. "OptionBackground-Common-Dark";
    end
    return PARCH .. "OptionBackground-Common";
end

local function SwapButtonFace(tex, dark)
    if (tex and tex.GetTexture) then
        local np = DialogUI_Theme:ResolveTexture(tex:GetTexture(), dark);
        if (np) then
            tex:SetTexture(np);
        end
    end
end

-- Walk a frame tree, swapping themed textures to their light/dark file. Matches
-- on the texture path so icons, portraits and unrelated art are left untouched.
local function ApplyThemeToFrame(frame, dark)
    if (not frame) then
        return;
    end
    -- Plain regions: background parchment, item-plate backgrounds, etc.
    if (frame.GetRegions) then
        for _, region in ipairs({ frame:GetRegions() }) do
            if (region and region.GetObjectType and region:GetObjectType() == "Texture") then
                local np = DialogUI_Theme:ResolveTexture(region:GetTexture(), dark);
                if (np) then
                    region:SetTexture(np);
                    region:SetVertexColor(1, 1, 1);
                end
            end
        end
    end
    -- Button face textures aren't returned by GetRegions; swap them explicitly.
    if (frame.GetObjectType and frame:GetObjectType() == "Button") then
        if (frame.GetNormalTexture) then SwapButtonFace(frame:GetNormalTexture(), dark); end
        if (frame.GetPushedTexture) then SwapButtonFace(frame:GetPushedTexture(), dark); end
        if (frame.GetDisabledTexture) then SwapButtonFace(frame:GetDisabledTexture(), dark); end
    end
    if (frame.GetChildren) then
        for _, child in ipairs({ frame:GetChildren() }) do
            ApplyThemeToFrame(child, dark);
        end
    end
end

function DialogUI_Theme:ApplyParchment()
    local dark = (self:GetMode() == "dark");
    if (DQuestFrame) then ApplyThemeToFrame(DQuestFrame, dark); end
    if (DGossipFrame) then ApplyThemeToFrame(DGossipFrame, dark); end
    if (DBookFrame) then ApplyThemeToFrame(DBookFrame, dark); end
end

-- Red plate on positive-action buttons in dark mode; normal plate in light mode.
-- Runs after ApplyParchment (which would otherwise set them to the dark plate).
function DialogUI_Theme:ApplyAccents()
    local dark = (self:GetMode() == "dark");
    local normal = dark and (PARCH .. "OptionBackground-Common-Red")
                         or (PARCH .. "OptionBackground-Common");
    for _, name in ipairs(ACCENT_BUTTONS) do
        local b = getglobal(name);
        if (b and b.GetNormalTexture) then
            local t = b:GetNormalTexture();
            if (t) then t:SetTexture(normal); end
        end
    end
end

-- Apply the whole theme: tint parchment now, and re-run the visible panel so any
-- already-displayed text picks up the new color immediately.
function DialogUI_Theme:Apply()
    self:ApplyParchment();
    self:ApplyAccents();

    if (DQuestFrame and DQuestFrame:IsVisible()) then
        if (DQuestFrameDetailPanel and DQuestFrameDetailPanel:IsVisible()) then
            DQuestFrameDetailPanel_OnShow();
        elseif (DQuestFrameRewardPanel and DQuestFrameRewardPanel:IsVisible()) then
            DQuestFrameRewardPanel_OnShow();
        elseif (DQuestFrameProgressPanel and DQuestFrameProgressPanel:IsVisible()) then
            DQuestFrameProgressPanel_OnShow();
        elseif (DQuestFrameGreetingPanel and DQuestFrameGreetingPanel:IsVisible()) then
            DQuestFrameGreetingPanel_OnShow();
        end
    end
    if (DGossipFrame and DGossipFrame:IsVisible() and DGossipFrameUpdate) then
        DGossipFrameUpdate();
    end
    if (DBookFrame and DBookFrame:IsVisible() and DBookFrame_Update) then
        DBookFrame_Update();
    end
end

function DialogUI_Theme:SetMode(mode)
    if (not DialogUISettings) then
        DialogUISettings = {};
    end
    DialogUISettings.darkMode = (mode == "dark");
    self:Apply();
    -- Keep the options checkbox in sync when toggled by slash command.
    if (DialogUIDarkModeCheck) then
        DialogUIDarkModeCheck:SetChecked(DialogUISettings.darkMode);
    end
end

function DialogUI_Theme:Toggle()
    self:SetMode(self:GetMode() == "dark" and "light" or "dark");
end

-- Initialize saved state and apply once frames exist (PLAYER_LOGIN is after the
-- XML frames are created; VARIABLES_LOADED guarantees DialogUISettings is ready).
local loader = CreateFrame("Frame");
loader:RegisterEvent("VARIABLES_LOADED");
loader:RegisterEvent("PLAYER_LOGIN");
loader:SetScript("OnEvent", function()
    if (not DialogUISettings) then
        DialogUISettings = {};
    end
    if (DialogUISettings.darkMode == nil) then
        DialogUISettings.darkMode = false;
    end
    DialogUI_Theme:Apply();
end);

SLASH_DIALOGUI1 = "/dialogui";
SLASH_DIALOGUI2 = "/dui";
SlashCmdList["DIALOGUI"] = function(msg)
    msg = string.lower(msg or "");
    msg = string.gsub(msg, "^%s*(.-)%s*$", "%1");
    -- Auto-advance blocklist management (captured from the open/target NPC).
    if (msg == "block") then
        if (DialogUI_Auto_Block) then DialogUI_Auto_Block(); end
        return;
    elseif (msg == "unblock") then
        if (DialogUI_Auto_Unblock) then DialogUI_Auto_Unblock(); end
        return;
    elseif (msg == "blocklist" or msg == "list") then
        if (DialogUI_Auto_ListBlocked) then DialogUI_Auto_ListBlocked(); end
        return;
    end
    if (msg == "dark") then
        DialogUI_Theme:SetMode("dark");
    elseif (msg == "light") then
        DialogUI_Theme:SetMode("light");
    elseif (msg == "" or msg == "toggle") then
        DialogUI_Theme:Toggle();
    else
        DEFAULT_CHAT_FRAME:AddMessage("DialogUI: /dialogui dark | light | toggle | block | unblock | blocklist");
        return;
    end
    DEFAULT_CHAT_FRAME:AddMessage("DialogUI: " .. DialogUI_Theme:GetMode() .. " mode");
end

-- The in-game options panel (incl. the Dark mode checkbox) lives in settings.lua.
