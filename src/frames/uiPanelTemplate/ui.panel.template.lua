-- Smoothly ease the scrollbar toward its target instead of jumping. Driven by an
-- OnUpdate on the scroll frame, enabled only while a wheel scroll is in flight.
local SCROLL_SMOOTH_SPEED = 14;   -- higher = snappier (fraction/sec toward target)

function DScrollFrame_SmoothOnUpdate(self, elapsed)
    self = self or this;
    elapsed = elapsed or arg1 or 0;
    local scrollBar = getglobal(self:GetName() .. "ScrollBar");
    if (not scrollBar or self.smoothTarget == nil) then
        self:SetScript("OnUpdate", nil);
        return;
    end
    local cur = scrollBar:GetValue();
    local diff = self.smoothTarget - cur;
    if (diff < 0.5 and diff > -0.5) then
        scrollBar:SetValue(self.smoothTarget);
        self.smoothTarget = nil;
        self:SetScript("OnUpdate", nil);
        return;
    end
    local frac = SCROLL_SMOOTH_SPEED * elapsed;
    if (frac > 1) then frac = 1; end
    scrollBar:SetValue(cur + diff * frac);
end

function DScrollFrameTemplate_OnMouseWheel(value, scrollBar)
    -- Nothing to scroll (content fits) => ignore the wheel, so there's no scrolling
    -- into empty space when no scrollbar is shown.
    if (this.GetVerticalScrollRange and this:GetVerticalScrollRange() <= 0) then
        return;
    end
    scrollBar = scrollBar or getglobal(this:GetName() .. "ScrollBar");
    local minV, maxV = scrollBar:GetMinMaxValues();
    local step = scrollBar:GetHeight() / 2;
    -- Accumulate onto the in-flight target so rapid ticks add up; then ease there.
    local base = this.smoothTarget or scrollBar:GetValue();
    local target = base + ((value > 0) and -step or step);
    if (target < minV) then target = minV; end
    if (target > maxV) then target = maxV; end
    this.smoothTarget = target;
    this:SetScript("OnUpdate", DScrollFrame_SmoothOnUpdate);
end

-- Scrollframe functions
function DScrollFrame_OnLoad()
    getglobal(this:GetName() .. "ScrollBarScrollDownButton"):Disable();
    getglobal(this:GetName() .. "ScrollBarScrollUpButton"):Disable();

    local scrollbar = getglobal(this:GetName() .. "ScrollBar");
    scrollbar:SetMinMaxValues(0, 0);
    scrollbar:SetValue(0);
    this.offset = 0;

    -- Hide the scrollbar (slider, arrows, thumb) whenever the content fits. The
    -- range-changed handler reveals it again only when the content overflows, so
    -- short quest/gossip/book pages don't show an idle scroll thumb.
    this.scrollBarHideable = 1;
    scrollbar:Hide();
end

function DScrollFrame_OnScrollRangeChanged(scrollrange)
    -- Content/range changed (e.g. panel switch); drop any in-flight smooth-scroll
    -- target so we never animate toward a stale position.
    this.smoothTarget = nil;
    this:SetScript("OnUpdate", nil);
    local scrollbar = getglobal(this:GetName() .. "ScrollBar");
    if (not scrollrange) then
        scrollrange = this:GetVerticalScrollRange();
    end
    local value = scrollbar:GetValue();
    if (value > scrollrange) then
        value = scrollrange;
    end
    scrollbar:SetMinMaxValues(0, scrollrange);
    scrollbar:SetValue(value);
    if (floor(scrollrange) == 0) then
        if (this.scrollBarHideable) then
            getglobal(this:GetName() .. "ScrollBar"):Hide();
            getglobal(scrollbar:GetName() .. "ScrollDownButton"):Hide();
            getglobal(scrollbar:GetName() .. "ScrollUpButton"):Hide();
        else
            getglobal(scrollbar:GetName() .. "ScrollDownButton"):Disable();
            getglobal(scrollbar:GetName() .. "ScrollUpButton"):Disable();
            getglobal(scrollbar:GetName() .. "ScrollDownButton"):Show();
            getglobal(scrollbar:GetName() .. "ScrollUpButton"):Show();
        end
        getglobal(scrollbar:GetName() .. "ThumbTexture"):Hide();
    else
        getglobal(scrollbar:GetName() .. "ScrollDownButton"):Show();
        getglobal(scrollbar:GetName() .. "ScrollUpButton"):Show();
        getglobal(this:GetName() .. "ScrollBar"):Show();
        getglobal(scrollbar:GetName() .. "ScrollDownButton"):Enable();
        getglobal(scrollbar:GetName() .. "ThumbTexture"):Show();
    end

    -- Hide/show scrollframe borders
    local top = getglobal(this:GetName() .. "Top");
    local bottom = getglobal(this:GetName() .. "Bottom");
    local middle = getglobal(this:GetName() .. "Middle");
    if (top and bottom and this.scrollBarHideable) then
        if (this:GetVerticalScrollRange() == 0) then
            top:Hide();
            bottom:Hide();
        else
            top:Show();
            bottom:Show();
        end
    end
    if (middle and this.scrollBarHideable) then
        if (this:GetVerticalScrollRange() == 0) then
            middle:Hide();
        else
            middle:Show();
        end
    end
end

function DScrollingEdit_OnTextChanged(scrollFrame)
    if (not scrollFrame) then
        scrollFrame = this:GetParent();
    end
end

function DScrollingEdit_OnCursorChanged(x, y, w, h)
    this.cursorOffset = y;
    this.cursorHeight = h;
end
