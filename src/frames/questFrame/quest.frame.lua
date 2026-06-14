---@diagnostic disable: undefined-global
MAX_NUM_QUESTS = 32;
MAX_NUM_ITEMS = 10;
MAX_REQUIRED_ITEMS = 6;
QUEST_DESCRIPTION_GRADIENT_LENGTH = 30;
QUEST_DESCRIPTION_GRADIENT_CPS = 40;
QUESTINFO_FADE_IN = 1;

local COLORS = {
    -- ColorKey = {r, g, b}

    DarkBrown = {0.19, 0.17, 0.13},
    LightBrown = {0.50, 0.36, 0.24},
    Ivory = {0.87, 0.86, 0.75}
};

-- Minimal one-shot timer. 3.3.5a has no C_Timer/After, so we drive a tiny
-- OnUpdate queue ourselves. Used to re-check reward sell prices once the client
-- has cached the item data (GetItemInfo returns nil/0 until then).
local DAfterFrame = CreateFrame("Frame");
local DAfterQueue = {};
DAfterFrame:SetScript("OnUpdate", function()
    local now = GetTime();
    local i = 1;
    while (i <= table.getn(DAfterQueue)) do
        local entry = DAfterQueue[i];
        if (now >= entry.at) then
            table.remove(DAfterQueue, i);
            entry.func();
        else
            i = i + 1;
        end
    end
    if (table.getn(DAfterQueue) == 0) then
        DAfterFrame:Hide();
    end
end);
DAfterFrame:Hide();
function DialogUI_After(delay, func)
    table.insert(DAfterQueue, { at = GetTime() + delay, func = func });
    DAfterFrame:Show();
end

-- "Most valuable to a vendor" marker: pins a gold coin to whichever choosable
-- reward sells for the most, so the player can spot the best vendor-fodder pick
-- at a glance. Ported from the modern DialogueUI (MarkHighestSellPrice). The 11th
-- return of GetItemInfo is sellPrice (present since 3.3.0), so this works on 3.3.5a.
local SELLCOIN_TEXTURE = "Interface\\AddOns\\DialogUI\\src\\assets\\art\\icons\\Coin-Gold";

local function DGetChoiceSellPrice(index)
    local link = GetQuestItemLink("choice", index);
    if (link and string.find(link, "item:")) then
        local sellPrice = select(11, GetItemInfo(link));
        if (sellPrice and sellPrice > 0) then
            return sellPrice;
        end
    end
    return 0;
end

local function DGetSellCoin(button)
    if (not button.dSellCoin) then
        local coin = button:CreateTexture(nil, "OVERLAY");
        coin:SetWidth(15);
        coin:SetHeight(15);
        local icon = getglobal(button:GetName() .. "IconTexture");
        if (icon) then
            coin:SetPoint("CENTER", icon, "TOPLEFT", 3, -3);
        else
            coin:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2);
        end
        coin:SetTexture(SELLCOIN_TEXTURE);
        button.dSellCoin = coin;
    end
    return button.dSellCoin;
end

local function DHideAllSellCoins(questItemName)
    for i = 1, MAX_NUM_ITEMS do
        local b = getglobal(questItemName .. i);
        if (b and b.dSellCoin) then
            b.dSellCoin:Hide();
        end
    end
end

-- Choices are laid out before mandatory rewards, so choice i lives on button i.
local function DMarkHighestSellPrice(questItemName, numQuestChoices, isRetry)
    if (not numQuestChoices or numQuestChoices <= 1) then
        return;
    end
    DHideAllSellCoins(questItemName);
    local maxPrice, maxIndex, anyZero = 0, nil, false;
    for i = 1, numQuestChoices do
        local price = DGetChoiceSellPrice(i);
        if (price == 0) then
            anyZero = true;
        end
        if (price > maxPrice) then
            maxPrice = price;
            maxIndex = i;
        end
    end
    -- If some items aren't cached yet (a winner exists but a sibling reads 0, or
    -- nothing priced at all), wait for the cache and try once more.
    if ((maxIndex and anyZero) or (not maxIndex)) then
        if (not isRetry) then
            DialogUI_After(0.8, function()
                DMarkHighestSellPrice(questItemName, numQuestChoices, true);
            end);
        end
        return;
    end
    local button = getglobal(questItemName .. maxIndex);
    if (button and button:IsShown()) then
        DGetSellCoin(button):Show();
    end
end

local function DQuestButton_IsEnabled(button)
    if (not button) then
        return nil;
    end

    if (not button.IsEnabled) then
        return 1;
    end

    return button:IsEnabled();
end

function SetFontColor(fontObject, key)
    -- Theme system (if loaded) remaps color keys for dark mode; fall back to the
    -- built-in light-mode palette.
    local color = (DialogUI_Theme and DialogUI_Theme:GetColor(key)) or COLORS[key];
    if (not color) then
        return;
    end
    -- FontStrings expose SetTextColor directly; Buttons color their text via
    -- their font string (3.3.5 Buttons have no SetTextColor method).
    if (fontObject.SetTextColor) then
        fontObject:SetTextColor(color[1], color[2], color[3]);
    elseif (fontObject.GetFontString) then
        local fontString = fontObject:GetFontString();
        if (fontString) then
            fontString:SetTextColor(color[1], color[2], color[3]);
        end
    end
end

-- Vanilla had a global QuestFrame_SetAsLastShown; it was removed in 3.3.5, so we
-- provide our own. It re-anchors the scroll-child spacer beneath the most recently
-- shown element (preserving the spacer's original point/offset) so the scrollframe
-- computes the correct content height.
function DQuestFrame_SetAsLastShown(frame, spacerFrame)
    if (not frame or not spacerFrame) then
        return;
    end
    local point, relativePoint, x, y = "TOP", "BOTTOM", 0, 0;
    if (spacerFrame:GetNumPoints() > 0) then
        local p, _, rp, ox, oy = spacerFrame:GetPoint(1);
        point = p or point;
        relativePoint = rp or relativePoint;
        x = ox or 0;
        y = oy or 0;
    end
    spacerFrame:ClearAllPoints();
    spacerFrame:SetPoint(point, frame, relativePoint, x, y);
end

-- Keyboard handling via frame-scoped override bindings instead of
-- EnableKeyboard()+OnKeyDown: capturing the keyboard would swallow movement keys
-- (WASD), and 3.3.5 has no SetPropagateKeyboardInput to let them through. Override
-- bindings intercept ONLY the keys we name while the quest frame is shown, leaving
-- movement and everything else untouched, and auto-clear via ClearOverrideBindings.
--
-- We bind the plain keys SPACE (accept/complete) and ESCAPE (decline/cancel) plus the
-- panel's number keys. Binding plain "SPACE"/"ESCAPE" matches only the unmodified key,
-- so Shift/Ctrl/Alt+Space (and any other combo) pass through normally.
function DQuestFrame_SetKeys(buttonPrefix, count)
    if (not DQuestFrame) then
        return;
    end
    ClearOverrideBindings(DQuestFrame);
    SetOverrideBinding(DQuestFrame, true, "SPACE", DIALOGUI_ACCEPT_BINDING);
    SetOverrideBinding(DQuestFrame, true, "ESCAPE", DIALOGUI_DECLINE_BINDING);
    if (buttonPrefix and count and count >= 1) then
        if (count > 9) then
            count = 9;
        end
        for i = 1, count do
            if (getglobal(buttonPrefix .. i)) then
                SetOverrideBindingClick(DQuestFrame, true, tostring(i), buttonPrefix .. i);
            end
        end
    end
end

function DQuestFrame_ClearKeys()
    if (DQuestFrame) then
        ClearOverrideBindings(DQuestFrame);
    end
end

function DQuestFrame_OnLoad()
    this:RegisterEvent("QUEST_GREETING");
    this:RegisterEvent("QUEST_DETAIL");
    this:RegisterEvent("QUEST_PROGRESS");
    this:RegisterEvent("QUEST_COMPLETE");
    this:RegisterEvent("QUEST_FINISHED");
    this:RegisterEvent("QUEST_ITEM_UPDATE");
    -- Silence Blizzard's default QuestFrame so it never flashes its panels for a
    -- frame before ours takes over (e.g. when handing in a quest). We drive the
    -- quest API directly, so the default frame isn't needed.
    if (QuestFrame) then
        QuestFrame:UnregisterAllEvents();
    end
    -- ESC used to close via the (now silenced) Blizzard frame; register ours so
    -- ESC still closes it (OnHide calls CloseQuest).
    if (UISpecialFrames) then
        table.insert(UISpecialFrames, "DQuestFrame");
    end
end

function HideDefaultFrames()
    QuestFrameGreetingPanel:Hide()
    QuestFrameDetailPanel:Hide()
    QuestFrameProgressPanel:Hide()
    QuestFrameRewardPanel:Hide()
    QuestNpcNameFrame:Hide()
    QuestFramePortrait:SetTexture()
end

function DQuestFrame_OnEvent(event)
    if (event == "QUEST_FINISHED") then
        HideUIPanel(DQuestFrame);
        return;
    end
    if ((event == "QUEST_ITEM_UPDATE") and not DQuestFrame:IsVisible()) then
        return;
    end

    -- Optional auto-advance of turn-ins (never auto-accepts a new quest).
    if (event == "QUEST_PROGRESS" and DialogUI_Auto_HandleQuestProgress and DialogUI_Auto_HandleQuestProgress()) then
        return;
    end
    if (event == "QUEST_COMPLETE" and DialogUI_Auto_HandleQuestComplete and DialogUI_Auto_HandleQuestComplete()) then
        return;
    end

    HideDefaultFrames();
    DQuestFrame_SetPortrait();
    ShowUIPanel(DQuestFrame);
    if (not DQuestFrame:IsVisible()) then
        CloseQuest();
        return;
    end
    if (event == "QUEST_GREETING") then
        DQuestFrameGreetingPanel:Hide();
        DQuestFrameGreetingPanel:Show();
    elseif (event == "QUEST_DETAIL") then
        DQuestFrameDetailPanel:Hide();
        DQuestFrameDetailPanel:Show();
    elseif (event == "QUEST_PROGRESS") then
        DQuestFrameProgressPanel:Hide();
        DQuestFrameProgressPanel:Show();
    elseif (event == "QUEST_COMPLETE") then
        DQuestFrameRewardPanel:Hide();
        DQuestFrameRewardPanel:Show();
    elseif (event == "QUEST_ITEM_UPDATE") then
        if (DQuestFrameDetailPanel:IsVisible()) then
            DQuestFrameItems_Update("DQuestDetail");
            DQuestDetailScrollFrame:UpdateScrollChildRect();
            DQuestDetailScrollFrameScrollBar:SetValue(0);
        elseif (DQuestFrameProgressPanel:IsVisible()) then
            DQuestFrameProgressItems_Update()
            DQuestProgressScrollFrame:UpdateScrollChildRect();
            DQuestProgressScrollFrameScrollBar:SetValue(0);
        elseif (DQuestFrameRewardPanel:IsVisible()) then
            DQuestFrameItems_Update("DQuestReward");
            DQuestRewardScrollFrame:UpdateScrollChildRect();
            DQuestRewardScrollFrameScrollBar:SetValue(0);
        end
    end
end

function DQuestFrame_SetPortrait()
    DQuestFrameNpcNameText:SetText(UnitName("npc"));
    if (UnitExists("npc")) then
        -- Plain SetPortraitTexture renders a CIRCULAR portrait on 3.3.5a (head on a
        -- circular field with transparent corners). No mask/texcoord needed.
        SetPortraitTexture(DQuestFramePortrait, "npc");
    else
        DQuestFramePortrait:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookIcon");
    end
end

function DQuestFrameRewardPanel_OnShow()
    DQuestFrameDetailPanel:Hide();
    DQuestFrameGreetingPanel:Hide();
    DQuestFrameProgressPanel:Hide();
    HideDefaultFrames();
    DQuestFrameNpcNameText:SetText(GetTitleText());
    DQuestRewardText:SetText(GetRewardText());
    SetFontColor(DQuestFrameNpcNameText, "DarkBrown");
    SetFontColor(DQuestRewardTitleText, "DarkBrown");
    SetFontColor(DQuestRewardText, "DarkBrown");
    DQuestFrameItems_Update("DQuestReward");
    DQuestRewardScrollFrame:UpdateScrollChildRect();
    DQuestRewardScrollFrameScrollBar:SetValue(0);
    if (QUEST_FADING_DISABLE == "0") then
        DQuestRewardScrollChildFrame:SetAlpha(0);
        UIFrameFadeIn(DQuestRewardScrollChildFrame, QUESTINFO_FADE_IN, 0, 1);
    end
    -- Accept/decline + number keys 1-9 for the choosable reward items on this panel.
    DQuestFrame_SetKeys("DQuestRewardItem", GetNumQuestChoices());
end

function DQuestRewardCancelButton_OnClick()
    DeclineQuest();
    PlaySound("igQuestCancel");
end

function DQuestRewardCompleteButton_OnClick()
    if (not DQuestFrameRewardPanel:IsVisible() or not DQuestButton_IsEnabled(DQuestFrameCompleteQuestButton)) then
        return;
    end

    if (DQuestFrameRewardPanel.itemChoice == 0 and GetNumQuestChoices() > 0) then
        QuestChooseRewardError();
    else
        GetQuestReward(DQuestFrameRewardPanel.itemChoice);
        PlaySound("igQuestListComplete");
    end
end

function DQuestProgressCompleteButton_OnClick()
    if (not DQuestFrameProgressPanel:IsVisible() or not DQuestButton_IsEnabled(DQuestFrameCompleteButton) or not IsQuestCompletable()) then
        return;
    end

    CompleteQuest();
    PlaySound("igQuestListComplete");
end

function DQuestGoodbyeButton_OnClick()
    DeclineQuest();
    PlaySound("igQuestCancel");
end

function DQuestItem_OnClick()
    if (IsControlKeyDown()) then
        if (this.rewardType ~= "spell") then
            DressUpItemLink(GetQuestItemLink(this.type, this:GetID()));
        end
    elseif (IsShiftKeyDown()) then
        if (this.rewardType ~= "spell") then
            local link = GetQuestItemLink(this.type, this:GetID());
            if (link) then ChatEdit_InsertLink(link); end
        end
    end
end

function DQuestReward_SelectChoice(choiceIndex)
    if (not DQuestFrameRewardPanel:IsVisible()) then
        return nil;
    end
    if (choiceIndex < 1 or choiceIndex > GetNumQuestChoices()) then
        return nil;
    end

    local rewardItem = getglobal("DQuestRewardItem" .. choiceIndex);
    if (not rewardItem or not rewardItem:IsVisible() or rewardItem.type ~= "choice") then
        return nil;
    end

    DQuestRewardItemHighlight:ClearAllPoints();
    DQuestRewardItemHighlight:SetPoint("TOPLEFT", rewardItem, "TOPLEFT", -2, 5);
    DQuestRewardItemHighlight:Show();
    DQuestFrameRewardPanel.itemChoice = rewardItem:GetID();

    GameTooltip:SetOwner(rewardItem, "ANCHOR_RIGHT");
    GameTooltip:SetQuestItem(rewardItem.type, rewardItem:GetID());

    return 1;
end

function DQuestRewardItem_OnClick()
    if (IsControlKeyDown()) then
        if (this.rewardType ~= "spell") then
            DressUpItemLink(GetQuestItemLink(this.type, this:GetID()));
        end
    elseif (IsShiftKeyDown()) then
        local link = GetQuestItemLink(this.type, this:GetID());
        if (link) then ChatEdit_InsertLink(link); end
    elseif (this.type == "choice") then
        DQuestReward_SelectChoice(this:GetID());
    end
end

function DQuestFrameProgressPanel_OnShow()
    DQuestFrameRewardPanel:Hide();
    DQuestFrameDetailPanel:Hide();
    DQuestFrameGreetingPanel:Hide();
    HideDefaultFrames();
    DQuestFrameNpcNameText:SetText(GetTitleText());
    DQuestProgressText:SetText(GetProgressText());
    SetFontColor(DQuestFrameNpcNameText, "DarkBrown");
    SetFontColor(DQuestProgressText, "DarkBrown");
    if (IsQuestCompletable()) then
        DQuestFrameCompleteButton:Enable();
    else
        DQuestFrameCompleteButton:Disable();
    end
    DQuestFrameProgressItems_Update();
    if (QUEST_FADING_DISABLE == "0") then
        DQuestProgressScrollChildFrame:SetAlpha(0);
        UIFrameFadeIn(DQuestProgressScrollChildFrame, QUESTINFO_FADE_IN, 0, 1);
    end
    -- Accept/decline only; no numbered selection on this panel.
    DQuestFrame_SetKeys(nil, 0);
end

function DQuestFrameProgressItems_Update()
    local numRequiredItems = GetNumQuestItems();
    local questItemName = "DQuestProgressItem";
    if (numRequiredItems > 0 or GetQuestMoneyToGet() > 0) then
        DQuestProgressRequiredItemsText:Show();

        -- If there's money required then anchor and display it
        if (GetQuestMoneyToGet() > 0) then
            DMoneyFrame_Update("DQuestProgressRequiredMoneyFrame", GetQuestMoneyToGet());

            if (GetQuestMoneyToGet() > GetMoney()) then
                -- Not enough money
                DQuestProgressRequiredMoneyText:SetTextColor(0, 0, 0);
                DSetMoneyFrameColor("DQuestProgressRequiredMoneyFrame", 1.0, 0.1, 0.1);
            else
                local pc = (DialogUI_Theme and DialogUI_Theme:GetColor("DarkBrown")) or {0.2, 0.2, 0.2};
                DQuestProgressRequiredMoneyText:SetTextColor(pc[1], pc[2], pc[3]);
                DSetMoneyFrameColor("DQuestProgressRequiredMoneyFrame", 1.0, 1.0, 1.0);
            end
            DQuestProgressRequiredMoneyText:Show();
            DQuestProgressRequiredMoneyFrame:Show();

            -- Reanchor required item
            getglobal(questItemName .. 1):ClearAllPoints();
            getglobal(questItemName .. 1):SetPoint("TOPLEFT", "DQuestProgressRequiredMoneyText", "BOTTOMLEFT", 0, -12);
        else
            DQuestProgressRequiredMoneyText:Hide();
            DQuestProgressRequiredMoneyFrame:Hide();

            getglobal(questItemName .. 1):ClearAllPoints();
            getglobal(questItemName .. 1):SetPoint("TOPLEFT", "DQuestProgressRequiredItemsText", "BOTTOMLEFT", -3, -12);
        end

        for i = 1, numRequiredItems, 1 do
            local requiredItem = getglobal(questItemName .. i);
            requiredItem.type = "required";
            local name, texture, numItems = GetQuestItemInfo(requiredItem.type, i);
            SetItemButtonCount(requiredItem, numItems);
            SetItemButtonTexture(requiredItem, texture);
            requiredItem:Show();
            getglobal(questItemName .. i .. "Name"):SetText(name);

            if (i > 1) then
                requiredItem:ClearAllPoints();
                if (mod(i, 2) == 1) then
                    requiredItem:SetPoint("TOPLEFT", questItemName .. (i - 2), "BOTTOMLEFT", 0, -20);
                else
                    requiredItem:SetPoint("TOPLEFT", questItemName .. (i - 1), "TOPRIGHT", 50, 0);
                end
            end
        end
    else
        DQuestProgressRequiredMoneyText:Hide();
        DQuestProgressRequiredMoneyFrame:Hide();
        DQuestProgressRequiredItemsText:Hide();
    end
    for i = numRequiredItems + 1, MAX_REQUIRED_ITEMS, 1 do
        getglobal(questItemName .. i):Hide();
    end
    DQuestProgressScrollFrame:UpdateScrollChildRect();
    DQuestProgressScrollFrameScrollBar:SetValue(0);
end

function DQuestFrameGreetingPanel_OnShow()
    DQuestFrameRewardPanel:Hide();
    DQuestFrameProgressPanel:Hide();
    DQuestFrameDetailPanel:Hide();

    if (QUEST_FADING_DISABLE == "0") then
        DQuestGreetingScrollChildFrame:SetAlpha(0);
        UIFrameFadeIn(DQuestGreetingScrollChildFrame, QUESTINFO_FADE_IN, 0, 1);
    end

    DGreetingText:SetText(GetGreetingText());
    SetFontColor(DGreetingText, "DarkBrown");
    SetFontColor(DCurrentQuestsText, "DarkBrown");
    SetFontColor(DAvailableQuestsText, "DarkBrown");
    
    local numActiveQuests = GetNumActiveQuests();
    local numAvailableQuests = GetNumAvailableQuests();
    local buttonIndex = 1; -- Counter for numbering buttons 1-9
    
    if (numActiveQuests == 0) then
        DCurrentQuestsText:Hide();
    else
        DCurrentQuestsText:SetPoint("TOPLEFT", "DGreetingText", "BOTTOMLEFT", 0, -10);
        DCurrentQuestsText:Show();
        DQuestTitleButton1:SetPoint("TOPLEFT", "DCurrentQuestsText", "BOTTOMLEFT", -10, -5);
        for i = 1, numActiveQuests, 1 do
            local questTitleButton = getglobal("DQuestTitleButton" .. i);
            -- Add number prefix (1-9) to the quest title
            local questTitle = GetActiveTitle(i);
            if (buttonIndex <= 9) then
                questTitleButton:SetText(buttonIndex .. ". " .. questTitle);
            else
                questTitleButton:SetText(questTitle);
            end
            questTitleButton:SetHeight(questTitleButton:GetTextHeight() + 20);
            SetFontColor(questTitleButton, "DarkBrown");
            questTitleButton:SetID(i);
            questTitleButton.isActive = 1;
            questTitleButton:Show();
            if (i > 1) then
                questTitleButton:SetPoint("TOPLEFT", "DQuestTitleButton" .. (i - 1), "BOTTOMLEFT", 0, 0)
            end
            buttonIndex = buttonIndex + 1;
        end
    end
    
    if (numAvailableQuests == 0) then
        DAvailableQuestsText:Hide();
    else
        if (numActiveQuests > 0) then
            DQuestGreetingFrameHorizontalBreak:SetPoint("TOPLEFT", "DQuestTitleButton" .. numActiveQuests, "BOTTOMLEFT",
                22, -10);
            DQuestGreetingFrameHorizontalBreak:Show();
            DAvailableQuestsText:SetPoint("TOPLEFT", "DQuestGreetingFrameHorizontalBreak", "BOTTOMLEFT", -12, -10);
        else
            DAvailableQuestsText:SetPoint("TOPLEFT", "DGreetingText", "BOTTOMLEFT", 0, -10);
        end
        DAvailableQuestsText:Show();
        getglobal("DQuestTitleButton" .. (numActiveQuests + 1)):SetPoint("TOPLEFT", "DAvailableQuestsText", "BOTTOMLEFT",
            -10, -5);
        for i = (numActiveQuests + 1), (numActiveQuests + numAvailableQuests), 1 do
            local questTitleButton = getglobal("DQuestTitleButton" .. i);
            -- Add number prefix (1-9) to the quest title
            local questTitle = GetAvailableTitle(i - numActiveQuests);
            if (buttonIndex <= 9) then
                questTitleButton:SetText(buttonIndex .. ". " .. questTitle);
            else
                questTitleButton:SetText(questTitle);
            end
            questTitleButton:SetHeight(questTitleButton:GetTextHeight() + 20);
            SetFontColor(questTitleButton, "DarkBrown");
            questTitleButton:SetID(i - numActiveQuests);
            questTitleButton.isActive = 0;
            questTitleButton:Show();
            if (i > numActiveQuests + 1) then
                questTitleButton:SetPoint("TOPLEFT", "DQuestTitleButton" .. (i - 1), "BOTTOMLEFT", 0, 0)
            end
            buttonIndex = buttonIndex + 1;
        end
    end
    
    for i = (numActiveQuests + numAvailableQuests + 1), MAX_NUM_QUESTS, 1 do
        getglobal("DQuestTitleButton" .. i):Hide();
    end
    
    -- Accept/decline + number keys 1-9 for the listed quest title buttons.
    DQuestFrame_SetKeys("DQuestTitleButton", numActiveQuests + numAvailableQuests);
end

function DQuestFrame_OnKeyDown()
    local key = arg1;
    
    if DialogUI_IsBindingKey(DIALOGUI_DECLINE_BINDING, key, "ESCAPE") then
        DQuestFrame_DeclineOrCancelKeybind();
        return
    end

    if DialogUI_IsBindingKey(DIALOGUI_ACCEPT_BINDING, key, "SPACE") then
        DQuestFrame_AcceptOrCompleteKeybind();
        return;
    end
    
    -- Handle number keys 1-9 for direct quest selection
    if (key >= "1" and key <= "9") then
        local buttonNum = tonumber(key);

        if (DQuestFrameRewardPanel:IsVisible()) then
            DQuestReward_SelectChoice(buttonNum);
            return;
        end

        local numActiveQuests = GetNumActiveQuests();
        local numAvailableQuests = GetNumAvailableQuests();
        local totalQuests = numActiveQuests + numAvailableQuests;
        
        if (buttonNum <= totalQuests) then
            local questButton = getglobal("DQuestTitleButton" .. buttonNum);
            if (questButton and questButton:IsVisible()) then
                questButton:Click();
            end
        end
    end
end

function DQuestFrame_AcceptOrCompleteKeybind()
    if (DQuestFrameDetailPanel:IsVisible()) then
        DQuestDetailAcceptButton_OnClick();
        return;
    elseif (DQuestFrameRewardPanel:IsVisible()) then
        DQuestRewardCompleteButton_OnClick();
        return;
    elseif (DQuestFrameProgressPanel:IsVisible()) then
        DQuestProgressCompleteButton_OnClick();
        return;
    else
        local numActiveQuests = GetNumActiveQuests();
        local numAvailableQuests = GetNumAvailableQuests();
        
        if (numActiveQuests > 0 or numAvailableQuests > 0) then
            local firstButton = getglobal("DQuestTitleButton1");
            if (firstButton and firstButton:IsVisible()) then
                firstButton:Click();
            end
        end
    end
end

function DQuestFrame_DeclineOrCancelKeybind()
    if (DQuestFrameDetailPanel:IsVisible()) then
        DQuestDetailDeclineButton_OnClick();
    elseif (DQuestFrameRewardPanel:IsVisible()) then
        DQuestRewardCancelButton_OnClick();
    elseif (DQuestFrameProgressPanel:IsVisible()) then
        DQuestGoodbyeButton_OnClick();
    elseif (DQuestFrameGreetingPanel:IsVisible()) then
        HideUIPanel(DQuestFrame);
    else
        HideUIPanel(DQuestFrame);
    end
end


function DQuestFrame_OnShow()
    PlaySound("igQuestListOpen");
    DialogUI_UpdateKeyBindingLabels();
    if (DialogUI_Focus) then DialogUI_Focus:OnShow(DQuestFrame); end
end

function DQuestFrame_OnHide()
    DQuestFrame_ClearKeys();
    DQuestFrameGreetingPanel:Hide();
    DQuestFrameDetailPanel:Hide();
    DQuestFrameRewardPanel:Hide();
    DQuestFrameProgressPanel:Hide();
    CloseQuest();
    PlaySound("igQuestListClose");
    if (DialogUI_Focus) then DialogUI_Focus:OnHide(); end
end

function DQuestTitleButton_OnClick()
    if (this.isActive == 1) then
        SelectActiveQuest(this:GetID());
    else
        SelectAvailableQuest(this:GetID());
    end
    PlaySound("igQuestListSelect");
end

function DQuestMoneyFrame_OnLoad()
    DMoneyFrame_OnLoad();
    DMoneyFrame_SetType("STATIC");
end

function DQuestFrameItems_Update(questState)


    if (DQuestFrameRewardPanel) then
        DQuestFrameRewardPanel.itemChoice = 0;
    end
    if (DQuestRewardItemHighlight) then
        DQuestRewardItemHighlight:Hide();
    end

    local isQuestLog = 0;
    local numQuestRewards;
    local numQuestChoices;
    local numQuestSpellRewards = 0;
    local money;
    local spacerFrame;
    if (isQuestLog == 0) then
        numQuestRewards = GetNumQuestRewards();
        numQuestChoices = GetNumQuestChoices();
        if (GetRewardSpell()) then
            numQuestSpellRewards = 1;
        end
        money = GetRewardMoney();
        spacerFrame = DQuestSpacerFrame;
    end

    local totalRewards = numQuestRewards + numQuestChoices + numQuestSpellRewards;
    local questItemName = questState .. "Item";
    local questItemReceiveText = getglobal(questState .. "ItemReceiveText");
    -- Clear any stale "best vendor value" coins before relaying out the rewards.
    DHideAllSellCoins(questItemName);
    if (totalRewards == 0 and money == 0) then
        getglobal(questState .. "RewardTitleText"):Hide();
    else
        getglobal(questState .. "RewardTitleText"):Show();
        SetFontColor(getglobal(questState .. "RewardTitleText"), "DarkBrown");
        DQuestFrame_SetAsLastShown(getglobal(questState .. "RewardTitleText"), spacerFrame);
    end
    if (money == 0) then
        getglobal(questState .. "MoneyFrame"):Hide();
    else
        getglobal(questState .. "MoneyFrame"):Show();
        DQuestFrame_SetAsLastShown(getglobal(questState .. "MoneyFrame"), spacerFrame);
        DMoneyFrame_Update(questState .. "MoneyFrame", money);
        -- Default coin numbers are white (invisible on light parchment); recolor to
        -- the theme's primary text color so they read in both light and dark modes.
        local mc = (DialogUI_Theme and DialogUI_Theme:GetColor("DarkBrown")) or {0.19, 0.17, 0.13};
        DSetMoneyFrameColor(questState .. "MoneyFrame", mc[1], mc[2], mc[3]);
    end

    -- Hide unused rewards
    for i = totalRewards + 1, MAX_NUM_ITEMS, 1 do
        getglobal(questItemName .. i):Hide();
    end

    local questItem, name, texture, isTradeskillSpell, quality, isUsable, numItems = 1;
    local rewardsCount = 0;

    -- Setup choosable rewards
    if (numQuestChoices > 0) then
        local itemChooseText = getglobal(questState .. "ItemChooseText");
        itemChooseText:Show();
        SetFontColor(itemChooseText, "DarkBrown");
        DQuestFrame_SetAsLastShown(itemChooseText, spacerFrame);

        local index;
        local baseIndex = rewardsCount;
        for i = 1, numQuestChoices, 1 do
            index = i + baseIndex;
            questItem = getglobal(questItemName .. index);
            questItem.type = "choice";
            numItems = 1;
            if (isQuestLog == 0) then
                name, texture, numItems, quality, isUsable = GetQuestItemInfo(questItem.type, i);
            end
            questItem:SetID(i)
            questItem:Show();
            -- For the tooltip
            questItem.rewardType = "item"
            DQuestFrame_SetAsLastShown(questItem, spacerFrame);
            getglobal(questItemName .. index .. "Name"):SetText(name);
            SetItemButtonCount(questItem, numItems);
            SetItemButtonTexture(questItem, texture);
            if (isUsable) then
                SetItemButtonTextureVertexColor(questItem, 1.0, 1.0, 1.0);
                SetItemButtonNameFrameVertexColor(questItem, 1.0, 1.0, 1.0);
            else
                SetItemButtonTextureVertexColor(questItem, 0.9, 0, 0);
                SetItemButtonNameFrameVertexColor(questItem, 0.9, 0, 0);
            end
            -- Changes how the reward columns are positioned
            if (i > 1) then
                questItem:ClearAllPoints();
                if (mod(i, 2) == 1) then
                    questItem:SetPoint("TOPLEFT", questItemName .. (index - 2), "BOTTOMLEFT", 0,-20);
                else
                    questItem:SetPoint("TOPLEFT", questItemName .. (index - 1), "TOPRIGHT", 50, 0);
                end
            else
                questItem:ClearAllPoints();
                questItem:SetPoint("TOPLEFT", itemChooseText, "BOTTOMLEFT", -3, -12);
            end
            rewardsCount = rewardsCount + 1;
        end
        -- Flag the choosable reward worth the most to a vendor (>1 choice only).
        DMarkHighestSellPrice(questItemName, numQuestChoices);
    else
        getglobal(questState .. "ItemChooseText"):Hide();
    end

    -- Setup spell rewards
    if (numQuestSpellRewards > 0) then
        local learnSpellText = getglobal(questState .. "SpellLearnText");
        learnSpellText:Show();
        SetFontColor(learnSpellText, "DarkBrown");
        DQuestFrame_SetAsLastShown(learnSpellText, spacerFrame);

        -- Anchor learnSpellText if there were choosable rewards
        learnSpellText:ClearAllPoints();
        if (rewardsCount > 0) then
            learnSpellText:SetPoint("TOPLEFT", questItemName .. rewardsCount, "BOTTOMLEFT", 3, -5);
        else
            learnSpellText:SetPoint("TOPLEFT", questState .. "RewardTitleText", "BOTTOMLEFT", 0, -5);
        end

        if (isQuestLog == 1) then
            texture, name, isTradeskillSpell = GetQuestLogRewardSpell();
        else
            texture, name, isTradeskillSpell = GetRewardSpell();
        end

        if (isTradeskillSpell) then
            learnSpellText:SetText(REWARD_TRADESKILL_SPELL);
        else
            learnSpellText:SetText(REWARD_SPELL);
        end

        rewardsCount = rewardsCount + 1;
        questItem = getglobal(questItemName .. rewardsCount);
        questItem:Show();
        -- For the tooltip
        questItem.rewardType = "spell";
        SetItemButtonCount(questItem, 0);
        SetItemButtonTexture(questItem, texture);
        getglobal(questItemName .. rewardsCount .. "Name"):SetText(name);
        questItem:ClearAllPoints();
        questItem:SetPoint("TOPLEFT", learnSpellText, "BOTTOMLEFT", -3, -12);
    else
        getglobal(questState .. "SpellLearnText"):Hide();
    end

    -- Setup mandatory rewards
    if (numQuestRewards > 0 or money > 0) then
            SetFontColor(questItemReceiveText, "DarkBrown");
        -- Anchor the reward text differently if there are choosable rewards
        if (numQuestSpellRewards > 0) then
            questItemReceiveText:SetText(REWARD_ITEMS);
            questItemReceiveText:ClearAllPoints();
            questItemReceiveText:SetPoint("TOPLEFT", questItemName .. rewardsCount, "BOTTOMLEFT", 3, -12);
        elseif (numQuestChoices > 0) then
            questItemReceiveText:SetText(REWARD_ITEMS);
            local index = numQuestChoices;
            if (mod(index, 2) == 0) then
                index = index - 1;
            end
            questItemReceiveText:ClearAllPoints();
            questItemReceiveText:SetPoint("TOPLEFT", questItemName .. index, "BOTTOMLEFT", 3, -12);
        else
            questItemReceiveText:SetText(REWARD_ITEMS_ONLY);
            questItemReceiveText:ClearAllPoints();
            questItemReceiveText:SetPoint("TOPLEFT", questState .. "RewardTitleText", "BOTTOMLEFT", 3, -12);
        end
        questItemReceiveText:Show();
        DQuestFrame_SetAsLastShown(questItemReceiveText, spacerFrame);
        -- Setup mandatory rewards
        local index;
        local baseIndex = rewardsCount;
        for i = 1, numQuestRewards, 1 do
            index = i + baseIndex;
            questItem = getglobal(questItemName .. index);
            questItem.type = "reward";
            numItems = 1;
            if (isQuestLog == 1) then
                name, texture, numItems, quality, isUsable = GetQuestLogRewardInfo(i);
            else
                name, texture, numItems, quality, isUsable = GetQuestItemInfo(questItem.type, i);
            end
            questItem:SetID(i)
            questItem:Show();
            -- For the tooltip
            questItem.rewardType = "item";
            DQuestFrame_SetAsLastShown(questItem, spacerFrame);
            getglobal(questItemName .. index .. "Name"):SetText(name);
            SetItemButtonCount(questItem, numItems);
            SetItemButtonTexture(questItem, texture);
            if (isUsable) then
                -- SetItemButtonTextureVertexColor(questItem, 1.0, 1.0, 1.0);
                -- SetItemButtonNameFrameVertexColor(questItem, 1.0, 1.0, 1.0);
            else
                -- SetItemButtonTextureVertexColor(questItem, 0.5, 0, 0);
                -- SetItemButtonNameFrameVertexColor(questItem, 1.0, 0, 0);
            end

            if (i > 1) then
                questItem:ClearAllPoints();
                if (mod(i, 2) == 1) then
                    questItem:SetPoint("TOPLEFT", questItemName .. (index - 2), "BOTTOMLEFT", 0, -20);
                else
                    questItem:SetPoint("TOPLEFT", questItemName .. (index - 1), "TOPRIGHT", 50, 0);
                end
            else
                questItem:ClearAllPoints();
                questItem:SetPoint("TOPLEFT", questState .. "ItemReceiveText", "BOTTOMLEFT", -3, -12);
            end
            rewardsCount = rewardsCount + 1;
        end
    else
        questItemReceiveText:Hide();
    end
    if (questState == "QuestReward") then
        DQuestFrameCompleteQuestButton:Enable();
        DQuestFrameRewardPanel.itemChoice = 0;
        DQuestRewardItemHighlight:Hide();
    end
end

function DQuestFrameDetailPanel_OnShow()
    DQuestFrameRewardPanel:Hide();
    DQuestFrameProgressPanel:Hide();
    DQuestFrameGreetingPanel:Hide();
    HideDefaultFrames();
    DQuestFrameNpcNameText:SetText(GetTitleText());
    DQuestDescription:SetText(GetQuestText());
    DQuestObjectiveText:SetText(GetObjectiveText());
    SetFontColor(DQuestFrameNpcNameText, "DarkBrown");
    SetFontColor(DQuestDescription, "DarkBrown");
    SetFontColor(DQuestObjectiveText, "DarkBrown");
    DQuestFrame_SetAsLastShown(DQuestObjectiveText, DQuestSpacerFrame);
    DQuestFrameItems_Update("DQuestDetail");
    DQuestDetailScrollFrame:UpdateScrollChildRect();
    DQuestDetailScrollFrameScrollBar:SetValue(0);

    -- Hide Objectives and rewards until the text is completely displayed
    DTextAlphaDependentFrame:SetAlpha(0);
    DQuestFrameAcceptButton:Disable();

    -- Accept/decline only; single-quest detail has no numbered selection.
    DQuestFrame_SetKeys(nil, 0);

    DQuestFrameDetailPanel.fading = 1;
    DQuestFrameDetailPanel.fadingProgress = 0;
    DQuestDescription:SetAlphaGradient(0, QUEST_DESCRIPTION_GRADIENT_LENGTH);
    if (QUEST_FADING_DISABLE == "1") then
        DQuestFrameDetailPanel.fadingProgress = 1024;
    end
end

function DQuestFrameDetailPanel_OnUpdate(elapsed)
    if (this.fading) then
        this.fadingProgress = this.fadingProgress + (elapsed * QUEST_DESCRIPTION_GRADIENT_CPS);
        PlaySound("WriteQuest");
        if (not DQuestDescription:SetAlphaGradient(this.fadingProgress, QUEST_DESCRIPTION_GRADIENT_LENGTH)) then
            this.fading = nil;
            -- Show Quest Objectives and Rewards
            if (QUEST_FADING_DISABLE == "0") then
                UIFrameFadeIn(DTextAlphaDependentFrame, QUESTINFO_FADE_IN, 0, 1);
            else
                DTextAlphaDependentFrame:SetAlpha(1);
            end
            DQuestFrameAcceptButton:Enable();
        end
    end
end

function DQuestDetailAcceptButton_OnClick()
    if (not DQuestFrameDetailPanel:IsVisible() or not DQuestButton_IsEnabled(DQuestFrameAcceptButton)) then
        return;
    end

    AcceptQuest();
end

function DQuestDetailDeclineButton_OnClick()
    DeclineQuest();
    PlaySound("igQuestCancel");
end


-- The greeting panel doesn't report per-quest completion, so match the active quest
-- title against the quest log (GetQuestLogTitle's 7th return is isComplete).
local function DQuestFrame_IsActiveQuestComplete(title)
    if (not title) then
        return false;
    end
    for i = 1, GetNumQuestLogEntries() do
        local logTitle, _, _, _, isHeader, _, isComplete = GetQuestLogTitle(i);
        if (not isHeader and logTitle == title) then
            return isComplete == 1;
        end
    end
    return false;
end

local function UpdateQuestIcons()
    local numActiveQuests = GetNumActiveQuests();
    local numAvailableQuests = GetNumAvailableQuests();

    -- Update active quest icons
    for i = 1, numActiveQuests do
        local button = getglobal("DQuestTitleButton" .. i);
        if button and button:IsVisible() then
            local iconTexture = button:GetRegions(); -- Gets the first region (your texture)
            if iconTexture and iconTexture.SetTexture then
                iconTexture:SetTexture("Interface\\AddOns\\DialogUI\\src\\assets\\art\\icons\\activeQuestIcon");
                -- Gold "?" only when the quest is actually complete; otherwise show it
                -- desaturated (black & white) to mean "in progress".
                if iconTexture.SetDesaturated then
                    iconTexture:SetDesaturated(not DQuestFrame_IsActiveQuestComplete(GetActiveTitle(i)));
                end
            end
        end
    end

    -- Update available quest icons
    for i = (numActiveQuests + 1), (numActiveQuests + numAvailableQuests) do
        local button = getglobal("DQuestTitleButton" .. i);
        if button and button:IsVisible() then
            local iconTexture = button:GetRegions(); -- Gets the first region (your texture)
            if iconTexture and iconTexture.SetTexture then
                iconTexture:SetTexture("Interface\\AddOns\\DialogUI\\src\\assets\\art\\icons\\availableQuestIcon");
                -- Available "!" is always full colour.
                if iconTexture.SetDesaturated then
                    iconTexture:SetDesaturated(false);
                end
            end
        end
    end
end

local originalOnShow = DQuestFrameGreetingPanel_OnShow;
DQuestFrameGreetingPanel_OnShow = function()
    originalOnShow();
    UpdateQuestIcons();
    -- Size the scroll child to its actual content so the panel only scrolls when
    -- content genuinely overflows (no scrolling into empty space, no idle bar).
    local child = DQuestGreetingScrollChildFrame;
    local scroll = DQuestGreetingScrollFrame;
    if (child and scroll) then
        local total = GetNumActiveQuests() + GetNumAvailableQuests();
        local lastBtn = (total > 0) and getglobal("DQuestTitleButton" .. total) or nil;
        local top = child:GetTop();
        if (lastBtn and lastBtn:IsShown() and lastBtn:GetBottom() and top) then
            local h = top - lastBtn:GetBottom() + 24;
            if (h < 10) then h = 10; end
            child:SetHeight(h);
        end
        scroll:UpdateScrollChildRect();
        local needScroll = (child:GetHeight() or 0) > (scroll:GetHeight() or 0) + 1;
        for _, suffix in ipairs({ "", "ThumbTexture", "ScrollUpButton", "ScrollDownButton" }) do
            local part = getglobal("DQuestGreetingScrollFrameScrollBar" .. suffix);
            if (part) then
                if (needScroll) then part:Show(); else part:Hide(); end
            end
        end
    end
end
