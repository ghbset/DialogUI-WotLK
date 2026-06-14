---@diagnostic disable: undefined-global
BINDING_HEADER_DIALOGUI = "DialogUI";
BINDING_NAME_DIALOGUI_ACCEPT_OR_COMPLETE = "Accept / Complete / Select First";
BINDING_NAME_DIALOGUI_DECLINE_OR_CANCEL = "Decline / Cancel / Close";
BINDING_NAME_DIALOGUI_GOSSIP_OPTION_1 = "Gossip Option 1";
BINDING_NAME_DIALOGUI_GOSSIP_OPTION_2 = "Gossip Option 2";
BINDING_NAME_DIALOGUI_GOSSIP_OPTION_3 = "Gossip Option 3";
BINDING_NAME_DIALOGUI_GOSSIP_OPTION_4 = "Gossip Option 4";
BINDING_NAME_DIALOGUI_GOSSIP_OPTION_5 = "Gossip Option 5";
BINDING_NAME_DIALOGUI_GOSSIP_OPTION_6 = "Gossip Option 6";
BINDING_NAME_DIALOGUI_GOSSIP_OPTION_7 = "Gossip Option 7";
BINDING_NAME_DIALOGUI_GOSSIP_OPTION_8 = "Gossip Option 8";
BINDING_NAME_DIALOGUI_GOSSIP_OPTION_9 = "Gossip Option 9";

DIALOGUI_ACCEPT_BINDING = "DIALOGUI_ACCEPT_OR_COMPLETE";
DIALOGUI_DECLINE_BINDING = "DIALOGUI_DECLINE_OR_CANCEL";

local function DialogUI_NormalizeBindingKey(key)
    if (not key) then
        return nil;
    end

    local normalizedKey = string.upper(key);
    local baseKey = normalizedKey;
    local hasAlt = nil;
    local hasCtrl = nil;
    local hasShift = nil;

    for token in string.gmatch(normalizedKey, "[^-]+") do
        if (token == "ALT") then
            hasAlt = 1;
        elseif (token == "CTRL" or token == "CONTROL") then
            hasCtrl = 1;
        elseif (token == "SHIFT") then
            hasShift = 1;
        else
            baseKey = token;
        end
    end

    local result = "";
    if (hasAlt) then
        result = result .. "ALT-";
    end
    if (hasCtrl) then
        result = result .. "CTRL-";
    end
    if (hasShift) then
        result = result .. "SHIFT-";
    end

    return result .. baseKey;
end

function DialogUI_GetPressedBindingKey(key)
    if (not key) then
        return nil;
    end

    local bindingKey = key;

    if (IsAltKeyDown() and key ~= "LALT" and key ~= "RALT") then
        bindingKey = "ALT-" .. bindingKey;
    end
    if (IsControlKeyDown() and key ~= "LCTRL" and key ~= "RCTRL") then
        bindingKey = "CTRL-" .. bindingKey;
    end
    if (IsShiftKeyDown() and key ~= "LSHIFT" and key ~= "RSHIFT") then
        bindingKey = "SHIFT-" .. bindingKey;
    end

    return DialogUI_NormalizeBindingKey(bindingKey);
end

function DialogUI_IsBindingKey(command, key, defaultKey)
    local pressedKey = DialogUI_GetPressedBindingKey(key);
    local key1, key2 = GetBindingKey(command);

    if (DialogUI_NormalizeBindingKey(key1) == pressedKey or DialogUI_NormalizeBindingKey(key2) == pressedKey) then
        return 1;
    end

    if (not key1 and not key2 and defaultKey) then
        return DialogUI_NormalizeBindingKey(defaultKey) == pressedKey;
    end

    return nil;
end

function DialogUI_GetBindingDisplayText(command, defaultKey)
    local key1 = GetBindingKey(command);
    local key = key1 or defaultKey;

    if (not key) then
        return "";
    end

    if (GetBindingText) then
        return GetBindingText(key, "KEY_");
    end

    key = string.gsub(key, "CTRL%-", "Ctrl-");
    key = string.gsub(key, "ALT%-", "Alt-");
    key = string.gsub(key, "SHIFT%-", "Shift-");
    key = string.gsub(key, "SPACE", "Space");
    key = string.gsub(key, "ESCAPE", "Esc");

    return key;
end

local function DialogUI_SetButtonKeyText(buttonName, command, defaultKey)
    local button = getglobal(buttonName);
    if (not button) then
        return;
    end

    local icon = getglobal(buttonName .. "Icon");
    if (icon) then
        icon:Hide();
    end

    local keyBackground = getglobal(buttonName .. "KeyBackground");
    if (not keyBackground) then
        keyBackground = button:CreateTexture(buttonName .. "KeyBackground", "ARTWORK");
        keyBackground:SetPoint("LEFT", button, "LEFT", 8, 0);
        keyBackground:SetHeight(22);
    end
    keyBackground:SetTexture(0, 0, 0);
    keyBackground:SetAlpha(0.90);

    local keyBorder = getglobal(buttonName .. "KeyBorder");
    if (not keyBorder) then
        keyBorder = button:CreateTexture(buttonName .. "KeyBorder", "OVERLAY");
        keyBorder:SetPoint("CENTER", keyBackground, "CENTER", 0, 0);
        keyBorder:SetHeight(24);
    end
    keyBorder:SetTexture(0, 0, 0);
    keyBorder:SetAlpha(1.0);

    local keyText = getglobal(buttonName .. "KeyText");
    if (not keyText) then
        keyText = button:CreateFontString(buttonName .. "KeyText", "OVERLAY", "DGameFontNormal");
        keyText:SetPoint("LEFT", keyBackground, "LEFT", 4, 0);
        keyText:SetPoint("RIGHT", keyBackground, "RIGHT", -4, 0);
        keyText:SetJustifyH("CENTER");
    end
    keyText:SetTextColor(1.0, 1.0, 1.0);

    local bindingText = DialogUI_GetBindingDisplayText(command, defaultKey);
    local keyWidth = string.len(bindingText) * 7 + 14;
    if (keyWidth < 42) then
        keyWidth = 42;
    elseif (keyWidth > 86) then
        keyWidth = 86;
    end

    keyBackground:SetWidth(keyWidth);
    keyBorder:SetWidth(keyWidth + 2);
    keyText:SetText(bindingText);

    local buttonText = getglobal(buttonName .. "Text");
    if (buttonText) then
        buttonText:ClearAllPoints();
        buttonText:SetPoint("LEFT", button, "LEFT", keyWidth + 20, 0);
        buttonText:SetPoint("RIGHT", button, "RIGHT", -10, 0);
        buttonText:SetJustifyH("LEFT");
    end

    keyBackground:Show();
    keyBorder:Show();
    keyText:Show();
end

function DialogUI_UpdateKeyBindingLabels()
    DialogUI_SetButtonKeyText("DQuestFrameAcceptButton", DIALOGUI_ACCEPT_BINDING, "SPACE");
    DialogUI_SetButtonKeyText("DQuestFrameCompleteQuestButton", DIALOGUI_ACCEPT_BINDING, "SPACE");
    DialogUI_SetButtonKeyText("DQuestFrameCompleteButton", DIALOGUI_ACCEPT_BINDING, "SPACE");

    DialogUI_SetButtonKeyText("DQuestFrameDeclineButton", DIALOGUI_DECLINE_BINDING, "ESCAPE");
    DialogUI_SetButtonKeyText("DQuestFrameCancelButton", DIALOGUI_DECLINE_BINDING, "ESCAPE");
    DialogUI_SetButtonKeyText("DQuestFrameGreetingGoodbyeButton", DIALOGUI_DECLINE_BINDING, "ESCAPE");
    DialogUI_SetButtonKeyText("DQuestFrameGoodbyeButton", DIALOGUI_DECLINE_BINDING, "ESCAPE");
    DialogUI_SetButtonKeyText("DGossipFrameGreetingGoodbyeButton", DIALOGUI_DECLINE_BINDING, "ESCAPE");
end

local DialogUIBindingFrame = CreateFrame("Frame");
DialogUIBindingFrame:RegisterEvent("UPDATE_BINDINGS");
DialogUIBindingFrame:SetScript("OnEvent", DialogUI_UpdateKeyBindingLabels);

function DialogUI_AcceptOrComplete()
    -- Only the unmodified key should accept. A base-key override binding ("SPACE")
    -- also fires for Shift/Ctrl/Alt+Space (WoW falls back to the base key when the
    -- modified combo is unbound), so ignore the press when any modifier is held.
    if (IsModifierKeyDown()) then
        return;
    end

    if (DQuestFrame and DQuestFrame:IsVisible() and DQuestFrame_AcceptOrCompleteKeybind) then
        DQuestFrame_AcceptOrCompleteKeybind();
        return;
    end

    if (DGossipFrame and DGossipFrame:IsVisible() and DGossipSelectOption) then
        DGossipSelectOption(1);
    end
end

function DialogUI_DeclineOrCancel()
    if (IsModifierKeyDown()) then
        return;
    end

    if (DQuestFrame and DQuestFrame:IsVisible() and DQuestFrame_DeclineOrCancelKeybind) then
        DQuestFrame_DeclineOrCancelKeybind();
        return;
    end

    if (DGossipFrame and DGossipFrame:IsVisible()) then
        CloseGossip();
    end
end

function DialogUI_GossipOption(n)
    if (DGossipFrame and DGossipFrame:IsVisible()) then
        DGossipSelectOption(n);
    end
end

local savedNumberBindings = {};
local gossipNumberKeysActive = false;

function DialogUI_GossipBindNumberKeys()
    if gossipNumberKeysActive then return; end
    gossipNumberKeysActive = true;
    for i = 1, 9 do
        local key = tostring(i);
        savedNumberBindings[i] = GetBindingAction(key);
        SetBinding(key, "DIALOGUI_GOSSIP_OPTION_" .. i);
    end
end

function DialogUI_GossipRestoreNumberKeys()
    if not gossipNumberKeysActive then return; end
    gossipNumberKeysActive = false;
    for i = 1, 9 do
        local key = tostring(i);
        SetBinding(key, savedNumberBindings[i]);
        savedNumberBindings[i] = nil;
    end
end
