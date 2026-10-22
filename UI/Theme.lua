-- Storm's Dungeon Data - Theme
-- Shared palette, fonts, rounded panels, controls and a small tween engine
-- used by the scoreboard, history viewer and live tracker ("Party Cards" look).

local MPT = StormsDungeonData
local Theme = {}
MPT.Theme = Theme

local MEDIA = "Interface\\AddOns\\StormsDungeonData\\Media\\"
Theme.TEX_ROUNDED = MEDIA .. "Rounded"
Theme.TEX_BORDER = MEDIA .. "RoundedBorder"
Theme.TEX_GLOW = MEDIA .. "Glow"
Theme.TEX_STAR = MEDIA .. "Star"
Theme.TEX_WHITE = "Interface\\Buttons\\WHITE8X8"

local SLICE_MARGIN = 12
local GLOW_MARGIN = 24

Theme.FONT_HEAD = "Fonts\\FRIZQT__.TTF"
Theme.FONT_BODY = "Fonts\\ARIALN.TTF"

-- Palette (r, g, b, a)
Theme.C = {
    bg       = {0.078, 0.071, 0.102, 0.97},   -- window
    surface  = {0.110, 0.098, 0.141, 1},      -- cards
    raised   = {0.149, 0.133, 0.184, 1},      -- chips, buttons, bar tracks
    line     = {0.200, 0.180, 0.243, 1},      -- borders
    text     = {0.937, 0.929, 0.957, 1},
    muted    = {0.604, 0.580, 0.659, 1},
    gold     = {1.000, 0.749, 0.278, 1},      -- MVP only
    good     = {0.373, 0.827, 0.553, 1},
    bad      = {1.000, 0.420, 0.420, 1},
    pb       = {1.000, 0.502, 0.000, 1},      -- personal best orange (kept from v2)
}

Theme.HEX = {
    muted = "9a94a8",
    gold = "ffbf47",
    good = "5fd38d",
    bad = "ff6b6b",
    pb = "ff8000",
}

function Theme:Unpack(name, alphaOverride)
    local c = self.C[name] or self.C.text
    return c[1], c[2], c[3], alphaOverride or c[4] or 1
end

function Theme:Colorize(text, name)
    return "|cff" .. (self.HEX[name] or "ffffff") .. tostring(text) .. "|r"
end

function Theme:ClassColor(classToken)
    if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
        local c = RAID_CLASS_COLORS[classToken]
        return c.r, c.g, c.b
    end
    return 0.8, 0.8, 0.8
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local function Settings()
    if not StormsDungeonDataDB then
        return nil
    end
    StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
    return StormsDungeonDataDB.settings
end

function Theme:GetSetting(key, default)
    local s = Settings()
    if not s or s[key] == nil then
        return default
    end
    return s[key]
end

function Theme:SetSetting(key, value)
    local s = Settings()
    if s then
        s[key] = value
    end
end

function Theme:AnimationsEnabled()
    return self:GetSetting("uiAnimations", true) ~= false
end

-- ---------------------------------------------------------------------------
-- Fonts and text
-- ---------------------------------------------------------------------------

function Theme:SetFont(fs, size, role, flags)
    local path = (role == "head") and self.FONT_HEAD or self.FONT_BODY
    if not fs:SetFont(path, size or 12, flags or "") then
        fs:SetFontObject("GameFontHighlightSmall")
    end
end

-- Theme:Text(parent, size, role, colorName, justify, layer)
function Theme:Text(parent, size, role, colorName, justify, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    self:SetFont(fs, size, role)
    fs:SetTextColor(self:Unpack(colorName or "text"))
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- ---------------------------------------------------------------------------
-- Rounded panels
-- ---------------------------------------------------------------------------

local function ApplySlice(tex, margin)
    if tex.SetTextureSliceMargins then
        tex:SetTextureSliceMargins(margin, margin, margin, margin)
        if tex.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
            tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
        return true
    end
    return false
end

-- Rounded texture tinted with a palette color. Falls back to a flat rectangle
-- when the client has no texture slicing.
function Theme:RoundedTexture(parent, layer, texPath, colorName, alpha, sublevel)
    local tex = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    tex:SetTexture(texPath or self.TEX_ROUNDED)
    if not ApplySlice(tex, SLICE_MARGIN) then
        tex:SetTexture(self.TEX_WHITE)
    end
    tex:SetVertexColor(self:Unpack(colorName or "surface", alpha))
    return tex
end

-- Gives a frame a rounded fill and 1px rounded border. Stores them on the frame
-- as frame.SDDFill / frame.SDDBorder so callers can recolor later.
function Theme:Panel(frame, fillName, borderName, fillAlpha)
    if not frame.SDDFill then
        frame.SDDFill = self:RoundedTexture(frame, "BACKGROUND", self.TEX_ROUNDED, fillName or "surface", fillAlpha, -7)
        frame.SDDFill:SetAllPoints(frame)
        frame.SDDBorder = self:RoundedTexture(frame, "BORDER", self.TEX_BORDER, borderName or "line", nil, -7)
        frame.SDDBorder:SetAllPoints(frame)
    else
        self:SetPanelColors(frame, fillName, borderName, fillAlpha)
    end
    return frame.SDDFill, frame.SDDBorder
end

function Theme:SetPanelColors(frame, fillName, borderName, fillAlpha)
    if frame.SDDFill and fillName then
        frame.SDDFill:SetVertexColor(self:Unpack(fillName, fillAlpha))
    end
    if frame.SDDBorder and borderName then
        frame.SDDBorder:SetVertexColor(self:Unpack(borderName))
    end
end

-- Soft glow drawn behind a frame. Starts hidden (alpha 0).
function Theme:Glow(frame, colorName, spread)
    spread = spread or 18
    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    glow:SetTexture(self.TEX_GLOW)
    ApplySlice(glow, GLOW_MARGIN)
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -spread, spread)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", spread, -spread)
    glow:SetVertexColor(self:Unpack(colorName or "gold"))
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0)
    return glow
end

function Theme:Divider(parent, colorName, alpha)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(self:Unpack(colorName or "line", alpha))
    line:SetHeight(1)
    return line
end

-- ---------------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------------

local BUTTON_STYLES = {
    default = {fill = "raised", border = "line", text = "text"},
    primary = {fill = "gold", border = "gold", text = "bg"},
    ghost   = {fill = "surface", border = "line", text = "muted"},
}

-- Flat rounded button. style = "default" | "primary" | "ghost".
function Theme:Button(parent, text, width, height, style, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 90, height or 24)
    local s = BUTTON_STYLES[style or "default"] or BUTTON_STYLES.default
    btn.SDDStyle = s
    self:Panel(btn, s.fill, s.border)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(self.TEX_ROUNDED)
    if not ApplySlice(hl, SLICE_MARGIN) then
        hl:SetTexture(self.TEX_WHITE)
    end
    hl:SetAllPoints(btn)
    hl:SetVertexColor(1, 1, 1, 0.08)

    local label = self:Text(btn, 12, "body", s.text, "CENTER")
    label:SetPoint("LEFT", btn, "LEFT", 6, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    label:SetText(text or "")
    btn:SetFontString(label)
    btn.Label = label

    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    btn:HookScript("OnEnable", function(b)
        b:SetAlpha(1)
    end)
    btn:HookScript("OnDisable", function(b)
        b:SetAlpha(0.4)
    end)
    return btn
end

-- Marks a button as the selected item in a group (nav tabs, metric tabs).
function Theme:SetButtonSelected(btn, selected)
    if selected then
        self:SetPanelColors(btn, "raised", "gold")
        btn.Label:SetTextColor(self:Unpack("text"))
    else
        self:SetPanelColors(btn, btn.SDDStyle.fill, btn.SDDStyle.border)
        btn.Label:SetTextColor(self:Unpack(btn.SDDStyle.text))
    end
end

function Theme:CloseButton(parent, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(22, 22)
    local x = self:Text(btn, 16, "body", "muted", "CENTER")
    x:SetPoint("CENTER", btn, "CENTER", 0, 1)
    x:SetText("x")
    btn:SetScript("OnEnter", function() x:SetTextColor(Theme:Unpack("text")) end)
    btn:SetScript("OnLeave", function() x:SetTextColor(Theme:Unpack("muted")) end)
    btn:SetScript("OnClick", onClick or function() parent:Hide() end)
    return btn
end

-- On/off switch with a label to its right. getter() -> bool, setter(bool).
function Theme:Toggle(parent, labelText, getter, setter, tooltip)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(220, 20)

    local track = CreateFrame("Frame", nil, btn)
    track:SetSize(30, 16)
    track:SetPoint("LEFT", btn, "LEFT", 0, 0)
    self:Panel(track, "raised", "line")

    local knob = self:RoundedTexture(track, "ARTWORK", self.TEX_ROUNDED, "muted")
    knob:SetSize(12, 12)

    local label = self:Text(btn, 12, "body", "text")
    label:SetPoint("LEFT", track, "RIGHT", 8, 0)
    label:SetText(labelText or "")

    function btn:Refresh()
        local on = getter() and true or false
        knob:ClearAllPoints()
        if on then
            knob:SetPoint("RIGHT", track, "RIGHT", -2, 0)
            knob:SetVertexColor(Theme:Unpack("bg"))
            Theme:SetPanelColors(track, "gold", "gold")
        else
            knob:SetPoint("LEFT", track, "LEFT", 2, 0)
            knob:SetVertexColor(Theme:Unpack("muted"))
            Theme:SetPanelColors(track, "raised", "line")
        end
    end

    btn:SetScript("OnClick", function(b)
        setter(not getter())
        b:Refresh()
    end)
    if tooltip then
        btn:SetScript("OnEnter", function(b)
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    btn.Label = label
    btn:Refresh()
    return btn
end

-- Thin horizontal bar: track + fill. bar:SetFraction(f, animate, delay).
function Theme:Bar(parent, height, colorR, colorG, colorB)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(height or 3)
    local track = bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints(bar)
    track:SetColorTexture(self:Unpack("raised"))
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    fill:SetColorTexture(colorR or 1, colorG or 1, colorB or 1, 1)
    fill:SetWidth(0.001)
    bar.Fill = fill
    bar.fraction = 0

    function bar:SetColor(r, g, b)
        fill:SetColorTexture(r, g, b, 1)
    end

    function bar:ApplyFraction(f)
        local w = (self:GetWidth() or 0) * f
        fill:SetWidth(math.max(0.001, w))
        if f <= 0 then fill:Hide() else fill:Show() end
    end

    function bar:SetFraction(f, animate, delay)
        f = math.max(0, math.min(1, tonumber(f) or 0))
        self.fraction = f
        if animate and Theme:AnimationsEnabled() then
            self:ApplyFraction(0)
            Theme:Tween(self, 0.5, delay or 0, function(p)
                self:ApplyFraction(f * p)
            end)
        else
            Theme:CancelTween(self)
            self:ApplyFraction(f)
        end
    end

    bar:SetScript("OnSizeChanged", function(self)
        if not Theme:IsTweening(self) then
            self:ApplyFraction(self.fraction or 0)
        end
    end)
    return bar
end

-- Turns a named UIDropDownMenuTemplate frame into a rounded filter chip.
-- The whole chip opens the menu; the template's own art is hidden.
function Theme:StyleDropdownChip(dropdown, labelText, width)
    local name = dropdown:GetName()
    if not name then return end
    for _, part in ipairs({"Left", "Middle", "Right"}) do
        local tex = _G[name .. part]
        if tex then tex:SetAlpha(0) end
    end
    if dropdown.Left then dropdown.Left:SetAlpha(0) end
    if dropdown.Middle then dropdown.Middle:SetAlpha(0) end
    if dropdown.Right then dropdown.Right:SetAlpha(0) end

    local chip = CreateFrame("Frame", nil, dropdown)
    chip:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 16, -2)
    chip:SetPoint("BOTTOMRIGHT", dropdown, "BOTTOMRIGHT", -14, 4)
    chip:SetFrameLevel(math.max(0, dropdown:GetFrameLevel() - 1))
    self:Panel(chip, "raised", "line")
    dropdown.SDDChip = chip

    local prefix = self:Text(chip, 11, "body", "muted")
    prefix:SetPoint("LEFT", chip, "LEFT", 10, 0)
    prefix:SetText(labelText or "")
    dropdown.SDDChipLabel = prefix

    local text = _G[name .. "Text"]
    if text then
        self:SetFont(text, 12, "body")
        text:SetTextColor(self:Unpack("text"))
        text:ClearAllPoints()
        text:SetPoint("LEFT", prefix, "RIGHT", 6, 0)
        text:SetPoint("RIGHT", chip, "RIGHT", -18, 0)
        text:SetJustifyH("LEFT")
    end

    local arrow = self:Text(chip, 10, "body", "muted", "RIGHT")
    arrow:SetPoint("RIGHT", chip, "RIGHT", -8, 0)
    arrow:SetText("v")

    local button = _G[name .. "Button"]
    if button then
        button:ClearAllPoints()
        button:SetAllPoints(chip)
        for _, getter in ipairs({"GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture"}) do
            local t = button[getter] and button[getter](button)
            if type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
        end
        button:HookScript("OnEnter", function() Theme:SetPanelColors(chip, "raised", "muted") end)
        button:HookScript("OnLeave", function() Theme:SetPanelColors(chip, "raised", "line") end)
    end
    if width then
        UIDropDownMenu_SetWidth(dropdown, width)
    end
end

-- ---------------------------------------------------------------------------
-- Windows
-- ---------------------------------------------------------------------------

function Theme:RegisterEscape(frame)
    local frameName = frame:GetName()
    if not frameName or not UISpecialFrames then return end
    for _, n in ipairs(UISpecialFrames) do
        if n == frameName then return end
    end
    table.insert(UISpecialFrames, frameName)
end

-- Movable rounded window with a title and close button.
function Theme:Window(name, width, height, titleText, strata)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata(strata or "DIALOG")
    self:Panel(frame, "bg", "line")

    local title = self:Text(frame, 18, "head", "text")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -16)
    title:SetText(titleText or "")
    frame.Title = title

    local close = self:CloseButton(frame)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    frame.CloseButton = close

    self:RegisterEscape(frame)
    return frame
end

-- ---------------------------------------------------------------------------
-- Game data helpers
-- ---------------------------------------------------------------------------

function Theme:DungeonInfo(mapID)
    mapID = tonumber(mapID)
    if not mapID or mapID == 0 or not C_ChallengeMode or not C_ChallengeMode.GetMapUIInfo then
        return nil
    end
    local ok, name, _, timeLimit, texture, backgroundTexture = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    if not ok or not name then
        return nil
    end
    return {name = name, timeLimit = tonumber(timeLimit), texture = texture, background = backgroundTexture}
end

-- Keystone upgrade from duration vs limit: 3, 2, 1, or 0 (over time).
function Theme:ChestCount(duration, timeLimit)
    duration, timeLimit = tonumber(duration), tonumber(timeLimit)
    if not duration or not timeLimit or timeLimit <= 0 then
        return nil
    end
    if duration <= timeLimit * 0.6 then return 3 end
    if duration <= timeLimit * 0.8 then return 2 end
    if duration <= timeLimit then return 1 end
    return 0
end

function Theme:SpecInfo(specID)
    specID = tonumber(specID)
    if not specID or specID == 0 or not GetSpecializationInfoByID then
        return nil
    end
    local ok, _, name, _, icon, role, classFile, className = pcall(GetSpecializationInfoByID, specID)
    if not ok or not name then
        return nil
    end
    return {name = name, icon = icon, role = role, classFile = classFile, className = className}
end

local CLASS_ICONS = {
    DEATHKNIGHT = "Interface/Icons/ClassIcon_DeathKnight",
    DEMONHUNTER = "Interface/Icons/ClassIcon_DemonHunter",
    DRUID       = "Interface/Icons/ClassIcon_Druid",
    EVOKER      = "Interface/Icons/ClassIcon_Evoker",
    HUNTER      = "Interface/Icons/ClassIcon_Hunter",
    MAGE        = "Interface/Icons/ClassIcon_Mage",
    MONK        = "Interface/Icons/ClassIcon_Monk",
    PALADIN     = "Interface/Icons/ClassIcon_Paladin",
    PRIEST      = "Interface/Icons/ClassIcon_Priest",
    ROGUE       = "Interface/Icons/ClassIcon_Rogue",
    SHAMAN      = "Interface/Icons/ClassIcon_Shaman",
    WARLOCK     = "Interface/Icons/ClassIcon_Warlock",
    WARRIOR     = "Interface/Icons/ClassIcon_Warrior",
}

function Theme:ClassIcon(classToken)
    return CLASS_ICONS[classToken or ""] or "Interface/Icons/INV_Misc_QuestionMark"
end

-- ---------------------------------------------------------------------------
-- Tween engine
-- One driver frame steps every active tween; keyed by owner so a new tween on
-- the same owner replaces the old one.
-- ---------------------------------------------------------------------------

local tweens = {}
local driver = CreateFrame("Frame")
driver:Hide()

function Theme.EaseOutCubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

function Theme.EaseOutBack(t)
    local c1, c3 = 1.4, 2.4
    local u = t - 1
    return 1 + c3 * u * u * u + c1 * u * u
end

driver:SetScript("OnUpdate", function(self, elapsed)
    local any = false
    for owner, tw in pairs(tweens) do
        any = true
        tw.t = tw.t + elapsed
        if tw.t >= tw.delay then
            local raw = math.min(1, (tw.t - tw.delay) / tw.duration)
            local ok, err = pcall(tw.step, tw.ease(raw), raw)
            if not ok then
                tweens[owner] = nil
                if MPT.Log and MPT.Log.Error then MPT.Log:Error("Tween step failed: " .. tostring(err)) end
            elseif raw >= 1 then
                tweens[owner] = nil
                if tw.done then pcall(tw.done) end
            end
        end
    end
    if not any then
        self:Hide()
    end
end)

-- step(easedProgress, rawProgress) runs every frame; done() runs once at the end.
function Theme:Tween(owner, duration, delay, step, done, ease)
    if not owner or not step then return end
    if not self:AnimationsEnabled() then
        pcall(step, 1, 1)
        if done then pcall(done) end
        return
    end
    tweens[owner] = {
        t = 0,
        delay = delay or 0,
        duration = math.max(0.01, duration or 0.3),
        step = step,
        done = done,
        ease = ease or Theme.EaseOutCubic,
    }
    driver:Show()
end

function Theme:CancelTween(owner)
    tweens[owner] = nil
end

function Theme:IsTweening(owner)
    return tweens[owner] ~= nil
end

-- Fade + slide a frame into its anchor. dx/dy is the starting offset.
-- anchor = {point, relativeTo, relativePoint, x, y}
function Theme:SlideIn(frame, anchor, dx, dy, duration, delay, ease, done)
    local point, rel, relPoint, x, y = anchor[1], anchor[2], anchor[3], anchor[4] or 0, anchor[5] or 0
    if not self:AnimationsEnabled() then
        frame:ClearAllPoints()
        frame:SetPoint(point, rel, relPoint, x, y)
        frame:SetAlpha(1)
        if done then done() end
        return
    end
    frame:SetAlpha(0)
    frame:ClearAllPoints()
    frame:SetPoint(point, rel, relPoint, x + (dx or 0), y + (dy or 0))
    self:Tween(frame, duration or 0.4, delay or 0, function(p, raw)
        frame:ClearAllPoints()
        frame:SetPoint(point, rel, relPoint, x + (dx or 0) * (1 - p), y + (dy or 0) * (1 - p))
        frame:SetAlpha(math.min(1, raw * 1.6))
    end, done, ease)
end

-- One pulse of a texture's alpha: 0 -> peak -> settle.
function Theme:Pulse(tex, peak, settle, duration, delay)
    if not self:AnimationsEnabled() then
        tex:SetAlpha(settle or 0)
        return
    end
    tex:SetAlpha(0)
    self:Tween(tex, duration or 1.2, delay or 0, function(_, raw)
        local a
        if raw < 0.4 then
            a = (raw / 0.4) * peak
        else
            a = peak + ((settle or 0) - peak) * ((raw - 0.4) / 0.6)
        end
        tex:SetAlpha(a)
    end, nil, function(t) return t end)
end

-- Counts a FontString up to a number. format = function(n) -> string.
function Theme:CountUp(fs, target, duration, delay, format)
    format = format or function(n) return tostring(math.floor(n + 0.5)) end
    target = tonumber(target) or 0
    if not self:AnimationsEnabled() then
        fs:SetText(format(target))
        return
    end
    fs:SetText(format(0))
    self:Tween(fs, duration or 0.8, delay or 0, function(p)
        fs:SetText(format(target * p))
    end)
end
