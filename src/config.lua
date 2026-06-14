---@diagnostic disable: undefined-global
-- DialogUI configuration: font size/face, frame scale, frame side, and the text
-- animation toggle. All persisted account-wide in DialogUISettings and applied at
-- login (and live when changed from the options panel). Ports the spirit of the
-- modern DialogueUI settings (FontSizeBase/FontText, FrameSize/FrameOrientation,
-- DisableUIMotion) to 3.3.5a.

DialogUI_Config = DialogUI_Config or {};

local FONT_DIR = "Interface\\AddOns\\DialogUI\\src\\assets\\font\\";

-- Selectable prose fonts (the coin font stays Arial Narrow regardless).
DialogUI_Config.fonts = {
    friz  = { name = "Friz Quadrata", file = FONT_DIR .. "frizqt___cyr.ttf" },
    arial = { name = "Arial Narrow",  file = FONT_DIR .. "ARIALN.ttf" },
};

-- The font objects we restyle, with their base point sizes (from fonts.xml).
-- fixedFile pins a font that should never follow the face choice (the coin font).
DialogUI_Config.fontObjects = {
    { obj = "DQuestTitleFont",         base = 18 },
    { obj = "DQuestFont",              base = 12 },
    { obj = "DQuestButtonTitleGossip", base = 12 },
    { obj = "DGameFontNormal",         base = 12 },
    { obj = "DGameFontBlack",          base = 12 },
    { obj = "DGameFontWhite",          base = 12 },
    { obj = "DQuestFontNormalSmall",   base = 12 },
    { obj = "DGameFontHighlight",      base = 12 },
    { obj = "GameFontDisable",         base = 12 },
    { obj = "DMoneyFont",              base = 16, fixedFile = FONT_DIR .. "ARIALN.ttf" },
};

DialogUI_Config.defaults = {
    darkMode    = false,
    disableAnim = false,
    autoSelect  = false,
    fontScale   = 1.0,
    fontFace    = "friz",
    frameScale  = 1.0,
    frameSide   = "LEFT",
    focusMode   = false,
};

local FRAMES = { "DQuestFrame", "DGossipFrame", "DBookFrame" };
-- The book is a centered modal, so the left/right orientation doesn't apply to it.
local ORIENT_FRAMES = { "DQuestFrame", "DGossipFrame" };

local function S(key)
    if (DialogUISettings and DialogUISettings[key] ~= nil) then
        return DialogUISettings[key];
    end
    return DialogUI_Config.defaults[key];
end
DialogUI_Config.Get = function(_, key) return S(key); end

-- Re-run whichever of our frames is visible so new font/scale metrics lay out.
function DialogUI_Config:RefreshVisible()
    if (DQuestFrame and DQuestFrame:IsVisible()) then
        if (DQuestFrameDetailPanel and DQuestFrameDetailPanel:IsVisible()) then DQuestFrameDetailPanel_OnShow();
        elseif (DQuestFrameRewardPanel and DQuestFrameRewardPanel:IsVisible()) then DQuestFrameRewardPanel_OnShow();
        elseif (DQuestFrameProgressPanel and DQuestFrameProgressPanel:IsVisible()) then DQuestFrameProgressPanel_OnShow();
        elseif (DQuestFrameGreetingPanel and DQuestFrameGreetingPanel:IsVisible()) then DQuestFrameGreetingPanel_OnShow();
        end
    end
    if (DGossipFrame and DGossipFrame:IsVisible() and DGossipFrameUpdate) then DGossipFrameUpdate(); end
    if (DBookFrame and DBookFrame:IsVisible() and DBookFrame_Update) then DBookFrame_Update(); end
end

function DialogUI_Config:ApplyFont()
    local face = self.fonts[S("fontFace")] or self.fonts.friz;
    local scale = S("fontScale") or 1.0;
    for _, e in ipairs(self.fontObjects) do
        local fo = getglobal(e.obj);
        if (fo and fo.SetFont) then
            fo:SetFont(e.fixedFile or face.file, e.base * scale, "");
        end
    end
    self:RefreshVisible();
end

function DialogUI_Config:ApplyScale()
    local s = S("frameScale") or 1.0;
    for _, name in ipairs(FRAMES) do
        local fr = getglobal(name);
        if (fr and fr.SetScale) then fr:SetScale(s); end
    end
end

function DialogUI_Config:ApplyOrientation()
    local side = S("frameSide") or "LEFT";
    for _, name in ipairs(ORIENT_FRAMES) do
        local fr = getglobal(name);
        if (fr) then
            fr:ClearAllPoints();
            if (side == "RIGHT") then
                fr:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, -104);
            else
                fr:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104);
            end
        end
    end
end

function DialogUI_Config:ApplyAnimation()
    -- The frames gate their text fade on this global; nil left it half-on, so we
    -- set it explicitly. "1" disables, "0" enables.
    QUEST_FADING_DISABLE = S("disableAnim") and "1" or "0";
end

function DialogUI_Config:ApplyAll()
    self:ApplyAnimation();
    self:ApplyFont();
    self:ApplyScale();
    self:ApplyOrientation();
end

-- Fill in any missing saved values, then apply once the frames exist.
local loader = CreateFrame("Frame");
loader:RegisterEvent("VARIABLES_LOADED");
loader:RegisterEvent("PLAYER_LOGIN");
loader:SetScript("OnEvent", function()
    if (not DialogUISettings) then DialogUISettings = {}; end
    for k, v in pairs(DialogUI_Config.defaults) do
        if (DialogUISettings[k] == nil) then
            DialogUISettings[k] = v;
        end
    end
    DialogUI_Config:ApplyAll();
end);
