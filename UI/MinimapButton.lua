local MPT = StormsDungeonData
local Minimap = Minimap

local MapShapeUtil = {}
MapShapeUtil.cornerRadius = 0
MapShapeUtil.shapes = {
    ["ROUND"] = {true, true, true, true},
    ["SQUARE"] = {false, false, false, false},
    ["CORNER-TOPLEFT"] = {false, false, false, true},
    ["CORNER-TOPRIGHT"] = {false, false, true, false},
    ["CORNER-BOTTOMLEFT"] = {false, true, false, false},
    ["CORNER-BOTTOMRIGHT"] = {true, false, false, false},
    ["SIDE-LEFT"] = {false, true, false, true},
    ["SIDE-RIGHT"] = {true, false, true, false},
    ["SIDE-TOP"] = {false, false, true, true},
    ["SIDE-BOTTOM"] = {true, true, false, false},
    ["TRICORNER-TOPLEFT"] = {false, true, true, true},
    ["TRICORNER-TOPRIGHT"] = {true, false, true, true},
    ["TRICORNER-BOTTOMLEFT"] = {true, true, false, true},
    ["TRICORNER-BOTTOMRIGHT"] = {true, true, true, false},
}

local function GetMinimapShapeSafe()
    if GetMinimapShape then
        return GetMinimapShape()
    end
    return "ROUND"
end

local function SetAngleOnMinimap(btn, angle)
    local x, y, q = math.cos(angle), math.sin(angle), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end

    local minimapShape = GetMinimapShapeSafe()
    if not MapShapeUtil.shapes[minimapShape] then
        minimapShape = "ROUND"
    end

    local quadTable = MapShapeUtil.shapes[minimapShape]
    local w = (Minimap:GetWidth() / 2) + MapShapeUtil.cornerRadius
    local h = (Minimap:GetHeight() / 2) + MapShapeUtil.cornerRadius

    if quadTable[q] then
        x, y = x * w, y * h
    else
        local diagRadiusW = math.sqrt(2 * (w)^2) - MapShapeUtil.cornerRadius
        local diagRadiusH = math.sqrt(2 * (h)^2) - MapShapeUtil.cornerRadius
        x = math.max(-w, math.min(x * diagRadiusW, w))
        y = math.max(-h, math.min(y * diagRadiusH, h))
    end

    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function GetAngleFromCursor()
    local mx, my = Minimap:GetCenter()
    if not mx or not my then
        return math.rad(225)
    end
    local scale = Minimap:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    return math.atan2(cy - my, cx - mx)
end

SDDMinimapButtonMixin = {}

local function OnMinimapClick(_, button)
    if button == "RightButton" then
        -- Close history so only the scoreboard shows after save
        if MPT and MPT.HistoryViewer and MPT.HistoryViewer.Hide then
            MPT.HistoryViewer:Hide()
        end
        if MPT and MPT.PerformManualSave then
            MPT.PerformManualSave("minimap")
        elseif MPT and MPT.Events and MPT.Events.FinalizeRun then
            local saved = MPT.Events:FinalizeRun("manual") or false
            if not saved then
                print("|cff00ffaa[StormsDungeonData]|r No pending run to save")
            end
        end
    else
        -- Close scoreboard so only history shows
        if MPT and MPT.Scoreboard and MPT.Scoreboard.Hide then
            MPT.Scoreboard:Hide()
        end
        if MPT and MPT.HistoryViewer and MPT.HistoryViewer.Show then
            MPT.HistoryViewer:Show()
        end
    end
end

local function EnsureMinimapButton()
    local function EnsureLibDBIcon()
        if not LibStub then
            return nil
        end
        local ldb = LibStub("LibDataBroker-1.1", true)
        local dbIcon = LibStub("LibDBIcon-1.0", true)
        if not ldb or not dbIcon then
            return nil
        end

        StormsDungeonDataDB = StormsDungeonDataDB or {}
        StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
        StormsDungeonDataDB.settings.libdbicon = StormsDungeonDataDB.settings.libdbicon or { hide = false, minimapPos = 225, radius = 12 }
        if StormsDungeonDataDB.settings.libdbicon.radius == nil then
            StormsDungeonDataDB.settings.libdbicon.radius = 12
        end

        if not MPT._ldbLauncher then
            MPT._ldbLauncher = ldb:NewDataObject("StormsDungeonData", {
                type = "launcher",
                text = "StormsDungeonData",
                icon = "Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32",
                OnClick = function(_, button)
                    OnMinimapClick(_, button)
                end,
                OnTooltipShow = function(tooltip)
                    if not tooltip then return end
                    tooltip:AddLine("StormsDungeonData")
                    tooltip:AddLine("Left-click: Open history", 0.2, 1, 0.2)
                    tooltip:AddLine("Right-click: Save pending run", 0.2, 1, 0.2)
                end,
            })
        end

        if not dbIcon:IsRegistered("StormsDungeonData") then
            dbIcon:Register("StormsDungeonData", MPT._ldbLauncher, StormsDungeonDataDB.settings.libdbicon)
        end

        StormsDungeonDataDB.settings.libdbicon.hide = false
        if dbIcon.SetButtonRadius and StormsDungeonDataDB.settings.libdbicon.radius then
            dbIcon:SetButtonRadius(StormsDungeonDataDB.settings.libdbicon.radius)
        end
        dbIcon:Show("StormsDungeonData")
        if dbIcon.Refresh then
            dbIcon:Refresh("StormsDungeonData", StormsDungeonDataDB.settings.libdbicon)
        end

        MPT._useLDBIcon = true
        return dbIcon:GetMinimapButton("StormsDungeonData")
    end

    local ldbBtn = EnsureLibDBIcon()
    if ldbBtn then
        local xmlBtn = _G["StormsDungeonDataMinimapButton"]
        if xmlBtn and xmlBtn ~= ldbBtn then
            xmlBtn:Hide()
        end
        return
    end

    local btn = _G["StormsDungeonDataMinimapButton"]
    if btn and btn.OnLoad and not btn._sddInit then
        btn:OnLoad()
    end

    if not btn and MPT and MPT.UIUtils and MPT.UIUtils.CreateMinimapButton then
        btn = MPT.UIUtils:CreateMinimapButton("StormsDungeonDataMinimapButton", "Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32", OnMinimapClick)
    end

    if btn then
        btn:Show()
        if btn.ResetPosition then
            btn:ResetPosition()
        end
    end
end

function SDDMinimapButtonMixin:OnLoad()
    if self._sddInit then
        return
    end
    self._sddInit = true

    self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    self:RegisterForDrag("LeftButton")
    self:SetMovable(true)
    self:SetClampedToScreen(true)
    self:SetFrameStrata("LOW")
    self:SetFrameLevel(62)

    if self.Icon and self.Icon.SetTexture then
        self.Icon:SetTexture("Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32")
    else
        self:SetNormalTexture("Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32")
    end
    self:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

    self:SetScript("OnEnter", function()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("StormsDungeonData", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Open history", 0.2, 1, 0.2)
        GameTooltip:AddLine("Right-click: Save pending run", 0.2, 1, 0.2)
        GameTooltip:AddLine("Drag to reposition", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    self:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self:SetScript("OnDragStart", function(btn)
        btn.isDragging = true
        btn:SetScript("OnUpdate", function()
            SetAngleOnMinimap(btn, GetAngleFromCursor())
        end)
    end)

    self:SetScript("OnDragStop", function(btn)
        btn.isDragging = false
        btn:SetScript("OnUpdate", nil)

        local angle = GetAngleFromCursor()
        if not StormsDungeonDataDB then
            StormsDungeonDataDB = {}
        end
        if not StormsDungeonDataDB.settings then
            StormsDungeonDataDB.settings = {}
        end
        if not StormsDungeonDataDB.settings.minimap then
            StormsDungeonDataDB.settings.minimap = {}
        end
        StormsDungeonDataDB.settings.minimap.angle = angle

        SetAngleOnMinimap(btn, angle)
    end)

    self:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if MPT and MPT.HistoryViewer and MPT.HistoryViewer.Hide then
                MPT.HistoryViewer:Hide()
            end
            if MPT and MPT.PerformManualSave then
                MPT.PerformManualSave("minimap")
            elseif MPT and MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
                if MPT.Events and MPT.Events.FinalizeRun then
                    MPT.Events:FinalizeRun("manual")
                end
            else
                print("|cff00ffaa[StormsDungeonData]|r No pending run to save")
            end
        else
            if MPT and MPT.Scoreboard and MPT.Scoreboard.Hide then
                MPT.Scoreboard:Hide()
            end
            if MPT and MPT.HistoryViewer and MPT.HistoryViewer.Show then
                MPT.HistoryViewer:Show()
            end
        end
    end)

    self:ResetPosition()
    self:SetAlpha(1)
    self:Show()

    if C_Timer and C_Timer.After then
        C_Timer.After(1, function()
            if self and self.ResetPosition then
                self:ResetPosition()
                self:SetAlpha(1)
                self:Show()
            end
        end)
    end
end

function SDDMinimapButtonMixin:SetClickHandler(handler)
    self._clickHandler = handler
end

function SDDMinimapButtonMixin:ResetPosition()
    if not Minimap then
        return
    end
    local angle = math.rad(225)
    if StormsDungeonDataDB and StormsDungeonDataDB.settings and StormsDungeonDataDB.settings.minimap and StormsDungeonDataDB.settings.minimap.angle then
        angle = StormsDungeonDataDB.settings.minimap.angle
    end
    SetAngleOnMinimap(self, angle)
end

print("|cff00ffaa[StormsDungeonData]|r Minimap button module loaded")

-- Bootstrap in case XML doesn't initialize the button
if CreateFrame then
    local bootstrap = CreateFrame("Frame")
    bootstrap:RegisterEvent("PLAYER_LOGIN")
    bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
    bootstrap:RegisterEvent("ADDON_LOADED")
    bootstrap:SetScript("OnEvent", function()
        EnsureMinimapButton()
        if C_Timer and C_Timer.After then
            C_Timer.After(2, EnsureMinimapButton)
        end
    end)
end

EnsureMinimapButton()
