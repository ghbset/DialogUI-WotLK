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

-- Header names (the NPC / quest title over the divider) must not grow back under the
-- portrait ring, so the box is anchored clear of it and anything still too wide is
-- trimmed to one line with an ellipsis rather than wrapping into the divider below.
--
-- Width is measured on a throwaway FontString with NO width set: a width-constrained
-- FontString wraps, and what GetStringWidth reports for a wrapped string is not
-- something to build a layout on. Unconstrained, it is simply the natural pixel width.
local measure;
function DialogUI_Config:SetHeaderText(fs, text)
    if (not fs) then return; end
    text = text or "";
    local maxW = fs:GetWidth() or 0;
    if (maxW <= 0) then
        fs:SetText(text);
        return;
    end
    if (not measure) then
        measure = UIParent:CreateFontString(nil, "ARTWORK");
        measure:Hide();
    end
    -- Match the live font, so the measurement tracks the user's font face/size setting.
    local file, size, flags = fs:GetFont();
    if (file) then measure:SetFont(file, size, flags); end
    measure:SetText(text);
    if ((measure:GetStringWidth() or 0) <= maxW) then
        fs:SetText(text);
        return;
    end
    -- Trim from the end until the name plus an ellipsis fits.
    local trimmed = text;
    while (string.len(trimmed) > 1) do
        trimmed = string.sub(trimmed, 1, string.len(trimmed) - 1);
        measure:SetText(trimmed .. "...");
        if ((measure:GetStringWidth() or 0) <= maxW) then
            break;
        end
    end
    fs:SetText(trimmed .. "...");
end

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

-- Join the stock UI panel system, so opening a dialog PUSHES the character sheet (and
-- friends) aside instead of landing on top of them (issue #2). ShowUIPanel only lays a
-- frame out if it has a UIPanelWindows entry — without one it degrades to frame:Show(),
-- which is why these windows overlapped everything. The entry mirrors what the frames we
-- replace use: stock QuestFrame and GossipFrame are both { area = "left", pushable = 0 },
-- and CharacterFrame is pushable = 3, so it is the one that moves.
--
-- The left/right preference maps straight onto the panel areas. Focus mode is the
-- exception: it centres the window over a dimmer, so there we deregister and go back to
-- placing the frame ourselves.
-- A frame must not sit in UISpecialFrames AND UIPanelWindows at once. ESC reaches both,
-- but CloseSpecialWindows closes with a bare frame:Hide(), which skips the panel system's
-- bookkeeping and leaves UIParent holding a slot it thinks is still occupied. While we are
-- docked, the panel path (CloseWindows -> HideUIPanel) already handles ESC, so drop out of
-- the special list; in focus mode we are not a panel and need it back.
local function SetSpecialFrame(name, wanted)
    if (not UISpecialFrames) then return; end
    for i = table.getn(UISpecialFrames), 1, -1 do
        if (UISpecialFrames[i] == name) then
            table.remove(UISpecialFrames, i);
        end
    end
    if (wanted) then
        table.insert(UISpecialFrames, name);
    end
end

function DialogUI_Config:ApplyPanelDocking()
    if (not UIPanelWindows) then return; end
    local focus = (DialogUI_Focus and DialogUI_Focus.IsOn and DialogUI_Focus:IsOn()) and true or false;
    local area = (S("frameSide") == "RIGHT") and "right" or "left";
    for _, name in ipairs(ORIENT_FRAMES) do
        local want = (not focus) and area or nil;
        local cur = UIPanelWindows[name] and UIPanelWindows[name].area or nil;
        -- Only rewrite on an actual change: swapping the entry out from under a frame the
        -- panel system currently has docked would leave UIParent holding a slot it can no
        -- longer release.
        if (want ~= cur) then
            if (want) then
                UIPanelWindows[name] = { area = want, pushable = 0 };
            else
                UIPanelWindows[name] = nil;
            end
        end
        SetSpecialFrame(name, want == nil);
    end
end

function DialogUI_Config:ApplyOrientation()
    self:ApplyPanelDocking();
    -- Docked to the panel system => UIParent owns the position; anchoring it here would
    -- just fight that. Only place the frame ourselves when we are NOT registered.
    local side = S("frameSide") or "LEFT";
    for _, name in ipairs(ORIENT_FRAMES) do
        local fr = getglobal(name);
        if (fr and not (UIPanelWindows and UIPanelWindows[name])) then
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
