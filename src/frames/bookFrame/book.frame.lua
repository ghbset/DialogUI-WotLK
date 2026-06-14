---@diagnostic disable: undefined-global
-- DialogUI book mode: an immersive parchment reader that replaces Blizzard's
-- ItemTextFrame for readable books, letters, signs, plaques and gravestones.
--
-- Ported in spirit from the modern DialogueUI "Book" module. The underlying
-- ItemText* API (ITEM_TEXT_BEGIN/READY/CLOSED, ItemTextGetItem/GetText/GetPage/
-- HasNextPage/NextPage/PrevPage, CloseItemText) is unchanged on 3.3.5a, so rather
-- than port the 2000-line retail frame we drive that API directly and render the
-- pages in the addon's own parchment style (theme-aware via DialogUI_Theme).

-- We take over the readable-text system by silencing Blizzard's ItemTextFrame and
-- handling the events on our own frame instead.
function DBookFrame_DisableBlizzard()
    if (ItemTextFrame) then
        ItemTextFrame:UnregisterAllEvents();
        if (ItemTextFrame:IsShown()) then
            HideUIPanel(ItemTextFrame);
        end
    end
end

function DBookFrame_OnLoad()
    this:RegisterEvent("ITEM_TEXT_BEGIN");
    this:RegisterEvent("ITEM_TEXT_READY");
    this:RegisterEvent("ITEM_TEXT_CLOSED");
    this:RegisterEvent("PLAYER_LOGIN");
    -- Blizzard's ItemTextFrame is created (FrameXML) before addons, so it already
    -- exists here; silence it now and again at login (covers /reload too).
    DBookFrame_DisableBlizzard();
    -- ESC closes the reader (and, via OnHide, the item-text session).
    if (UISpecialFrames) then
        table.insert(UISpecialFrames, "DBookFrame");
    end
end

-- Reduce the readable item's (often HTML) markup to clean plain text so it lays
-- out in a normal FontString and the existing scroll machinery can size it.
local function DBookStripHTML(text)
    if (not text or text == "") then
        return "";
    end
    -- <br/> and block-closing tags become line breaks.
    text = string.gsub(text, "<[bB][rR]%s*/?>", "\n");
    text = string.gsub(text, "</[pP]>", "\n\n");
    text = string.gsub(text, "</[hH][123]>", "\n\n");
    -- Drop every remaining tag, keeping the inner text.
    text = string.gsub(text, "<[^>]->", "");
    -- A couple of common entities, just in case.
    text = string.gsub(text, "&[lL][tT];", "<");
    text = string.gsub(text, "&[gG][tT];", ">");
    text = string.gsub(text, "&[aA][mM][pP];", "&");
    text = string.gsub(text, "&[qQ][uU][oO][tT];", "\"");
    -- Collapse runs of blank lines and trim.
    text = string.gsub(text, "\n%s*\n%s*\n+", "\n\n");
    text = string.gsub(text, "^%s+", "");
    text = string.gsub(text, "%s+$", "");
    return text;
end

-- Style a nav button's label directly (explicit font + color) so it never depends
-- on the shared/disabled font objects, which can render blank. The option-button
-- plate is dark in both themes, so ivory text reads on either.
local BOOK_BTN_FONT = "Interface\\AddOns\\DialogUI\\src\\assets\\font\\frizqt___cyr.ttf";
function DBookStyleButton(btn, label)
    btn:SetText(label);
    local fs = btn:GetFontString();
    if (fs) then
        fs:SetFont(BOOK_BTN_FONT, 14, "");
        local c = (DialogUI_Theme and DialogUI_Theme:GetColor("Ivory")) or { 0.87, 0.86, 0.75 };
        fs:SetTextColor(c[1], c[2], c[3]);
    end
end

function DBookFrame_Update()
    local title = ItemTextGetItem();
    DBookTitle:SetText(string.upper(title or ""));

    local page = ItemTextGetPage() or 1;
    local hasNext = ItemTextHasNextPage();

    local raw = ItemTextGetText();
    local creator = ItemTextGetCreator and ItemTextGetCreator() or nil;
    local body = DBookStripHTML(raw);
    -- Letters expose a creator/sender on their first page; show it like the game.
    if (creator and creator ~= "" and page <= 1) then
        body = body .. "\n\n" .. (ITEM_TEXT_FROM or "From:") .. "\n" .. creator;
    end
    DBookPageText:SetText(body);

    -- Color via the theme-aware SetFontColor so dark mode flips text to light.
    SetFontColor(DBookTitle, "DarkBrown");
    SetFontColor(DBookPageText, "DarkBrown");
    SetFontColor(DBookPageNumber, "LightBrown");

    -- Size the scroll child to the laid-out text and reset to the top.
    local h = DBookPageText:GetStringHeight() or DBookPageText:GetHeight() or 0;
    DBookScrollChildFrame:SetHeight(h + 24);
    DBookScrollFrame:UpdateScrollChildRect();
    if (DBookScrollFrameScrollBar) then
        DBookScrollFrameScrollBar:SetValue(0);
        -- Only show the scrollbar (and its thumb/arrows) when the page overflows.
        if (DBookScrollFrame:GetVerticalScrollRange() > 0) then
            DBookScrollFrameScrollBar:Show();
        else
            DBookScrollFrameScrollBar:Hide();
        end
    end

    -- Navigation. Page 1 HIDES Previous (nothing to go back to) rather than
    -- disabling it, so we never depend on the button template's disabled font.
    -- Labels are styled explicitly so they stay legible (esp. on the dark plate).
    if (page > 1) then
        DBookPrevButton:Show();
        DBookStyleButton(DBookPrevButton, "Previous");
    else
        DBookPrevButton:Hide();
    end

    if (hasNext) then
        DBookStyleButton(DBookNextButton, "Next Page");
        DBookNextButton.isClose = nil;
    else
        DBookStyleButton(DBookNextButton, "Close");
        DBookNextButton.isClose = 1;
    end

    -- A single-page book needs no page counter.
    if (page <= 1 and not hasNext) then
        DBookPageNumber:Hide();
    else
        DBookPageNumber:SetText("Page " .. page);
        DBookPageNumber:Show();
    end
end

function DBookFrame_OnEvent(event)
    if (event == "PLAYER_LOGIN") then
        DBookFrame_DisableBlizzard();
        return;
    end

    if (event == "ITEM_TEXT_BEGIN") then
        -- Belt and braces: make sure the default frame stays down.
        if (ItemTextFrame and ItemTextFrame:IsShown()) then
            HideUIPanel(ItemTextFrame);
        end
        return;
    end

    if (event == "ITEM_TEXT_READY") then
        DBookFrame_Update();
        -- Centered modal reader: plain Show (not a UIPanel) so it stays centered.
        DBookFrame:Show();
        if (DBookFrame:IsVisible()) then
            -- Re-run now that it's shown (anchors/heights resolve cleanly).
            DBookFrame_Update();
        end
        return;
    end

    if (event == "ITEM_TEXT_CLOSED") then
        if (DBookFrame:IsVisible()) then
            DBookFrame:Hide();
        end
        return;
    end
end

function DBookFrame_SetKeys()
    if (not DBookFrame) then
        return;
    end
    ClearOverrideBindings(DBookFrame);
    -- SPACE advances (and closes on the last page, since Next becomes Close).
    if (getglobal("DBookNextButton")) then
        SetOverrideBindingClick(DBookFrame, true, "SPACE", "DBookNextButton");
    end
end

function DBookFrame_ClearKeys()
    if (DBookFrame) then
        ClearOverrideBindings(DBookFrame);
    end
end

local BACKDROP_FADE = 0.5;

function DBookFrame_OnShow()
    PlaySound("igQuestListOpen");
    if (DBookBackdrop) then
        -- Fade the dimmer in to draw the eye to the page.
        UIFrameFadeRemoveFrame(DBookBackdrop); -- cancel any pending fade-out
        DBookBackdrop:Show();
        DBookBackdrop:SetAlpha(0);
        UIFrameFadeIn(DBookBackdrop, BACKDROP_FADE, 0, 1);
    end
    DBookFrame_SetKeys();
end

function DBookFrame_OnHide()
    DBookFrame_ClearKeys();
    if (DBookBackdrop) then
        -- Fade the dimmer back out, then hide it once the fade completes.
        UIFrameFadeRemoveFrame(DBookBackdrop);
        UIFrameFade(DBookBackdrop, {
            mode = "OUT",
            timeToFade = BACKDROP_FADE,
            startAlpha = DBookBackdrop:GetAlpha(),
            endAlpha = 0,
            finishedFunc = function() DBookBackdrop:Hide(); end,
        });
    end
    -- Closing the reader by any means (ESC, Close, walking away) ends the session.
    -- CloseItemText is idempotent, so the ITEM_TEXT_CLOSED it may raise is harmless.
    CloseItemText();
    PlaySound("igQuestListClose");
end

function DBookPrevButton_OnClick()
    if (ItemTextPrevPage) then
        ItemTextPrevPage();
        PlaySound("igQuestListSelect");
    end
end

function DBookNextButton_OnClick()
    if (this and this.isClose) then
        DBookFrame:Hide();
        return;
    end
    if (ItemTextHasNextPage()) then
        ItemTextNextPage();
        PlaySound("igQuestListSelect");
    else
        DBookFrame:Hide();
    end
end
