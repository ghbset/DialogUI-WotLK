---@diagnostic disable: undefined-global
-- DialogUI focus mode: an optional book-style screen dimmer for the quest and
-- gossip frames, and (when on) centers those windows like the book reader.
-- Toggled from the options panel; persisted in DialogUISettings.focusMode.

DialogUI_Focus = DialogUI_Focus or {};

local FADE = 0.5;

-- Shared full-screen dimmer behind the quest/gossip frame while focus mode is on.
local backdrop = CreateFrame("Frame", "DDialogFocusBackdrop", UIParent);
backdrop:SetFrameStrata("FULLSCREEN");
backdrop:SetAllPoints(UIParent);
backdrop:EnableMouse(true);
backdrop:Hide();
local dim = backdrop:CreateTexture(nil, "BACKGROUND");
dim:SetAllPoints(true);
dim:SetTexture(0, 0, 0);
dim:SetAlpha(0.5);
-- Clicking the dimmed area closes the open dialog (matches the book reader).
backdrop:SetScript("OnMouseUp", function()
    if (DQuestFrame and DQuestFrame:IsVisible()) then HideUIPanel(DQuestFrame); end
    if (DGossipFrame and DGossipFrame:IsVisible()) then CloseGossip(); end
end);

function DialogUI_Focus:IsOn()
    return (DialogUISettings and DialogUISettings.focusMode) and true or false;
end

local function AnyDialogVisible()
    return (DQuestFrame and DQuestFrame:IsVisible())
        or (DGossipFrame and DGossipFrame:IsVisible());
end

-- Position a frame: centered (focus mode) or docked to its configured side.
function DialogUI_Focus:PlaceFrame(frame)
    if (not frame) then return; end
    frame:ClearAllPoints();
    if (self:IsOn()) then
        frame:SetFrameStrata("FULLSCREEN_DIALOG");   -- above the dimmer
        -- The parchment overhangs the 384-wide frame by 128 on the right, so nudge
        -- left 64 to center the visible page.
        frame:SetPoint("CENTER", UIParent, "CENTER", -64, 20);
    else
        frame:SetFrameStrata("DIALOG");
        local side = (DialogUISettings and DialogUISettings.frameSide) or "LEFT";
        if (side == "RIGHT") then
            frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, -104);
        else
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -104);
        end
    end
end

-- Called from a dialog's OnShow.
function DialogUI_Focus:OnShow(frame)
    self:PlaceFrame(frame);
    if (self:IsOn()) then
        UIFrameFadeRemoveFrame(backdrop);
        backdrop:Show();
        backdrop:SetAlpha(0);
        UIFrameFadeIn(backdrop, FADE, 0, 1);
    end
end

-- Called from a dialog's OnHide. Fades the dimmer out only when no dialog remains.
function DialogUI_Focus:OnHide()
    if (AnyDialogVisible()) then return; end
    if (not backdrop:IsShown()) then return; end
    UIFrameFadeRemoveFrame(backdrop);
    UIFrameFade(backdrop, {
        mode = "OUT",
        timeToFade = FADE,
        startAlpha = backdrop:GetAlpha(),
        endAlpha = 0,
        finishedFunc = function() backdrop:Hide(); end,
    });
end

-- Re-apply when the setting is toggled from the options panel: reposition any open
-- dialog and show/hide the dimmer to match.
function DialogUI_Focus:Apply()
    if (DQuestFrame and DQuestFrame:IsVisible()) then self:PlaceFrame(DQuestFrame); end
    if (DGossipFrame and DGossipFrame:IsVisible()) then self:PlaceFrame(DGossipFrame); end
    if (self:IsOn()) then
        if (AnyDialogVisible()) then
            UIFrameFadeRemoveFrame(backdrop);
            backdrop:Show();
            UIFrameFadeIn(backdrop, FADE, backdrop:GetAlpha(), 1);
        end
    else
        UIFrameFadeRemoveFrame(backdrop);
        backdrop:Hide();
    end
end
