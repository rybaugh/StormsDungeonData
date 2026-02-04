-- Mythic Plus Tracker - UI Utils Module
-- Common UI functions and styling

local MPT = StormsDungeonData
local UIUtils = {}
MPT.UIUtils = UIUtils

-- Colors
UIUtils.COLORS = {
    GOLD = {r = 1, g = 0.84, b = 0},
    WHITE = {r = 1, g = 1, b = 1},
    GREEN = {r = 0.1, g = 1, b = 0.1},
    RED = {r = 1, g = 0.2, b = 0.2},
    BLUE = {r = 0.2, g = 0.6, b = 1},
    ORANGE = {r = 1, g = 0.6, b = 0},
    PURPLE = {r = 0.64, g = 0.2, b = 0.93},
}

-- Create styled button
function UIUtils:CreateButton(parent, text, width, height, onclick)
    local btn = CreateFrame("Button", nil, parent, "GameMenuButtonTemplate")
    btn:SetWidth(width or 100)
    btn:SetHeight(height or 24)
    btn:SetText(text or "Button")
    btn:SetScript("OnClick", onclick)
    return btn
end

-- Create styled label
function UIUtils:CreateLabel(parent, text, width, height)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(text or "")
    if width and height then
        label:SetSize(width, height)
    end
    return label
end

-- Create a simple scrollable frame
function UIUtils:CreateScrollFrame(parent, width, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(width, height)
    
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width - 20, 1)
    scroll:SetScrollChild(content)
    
    return scroll, content
end

-- Create row in list
function UIUtils:CreateListRow(parent, columns, y, rowHeight)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(parent:GetWidth(), rowHeight or 20)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    
    local x = 0
    local columnFrames = {}
    
    for i, colWidth in ipairs(columns) do
        local cell = CreateFrame("Frame", nil, row)
        cell:SetSize(colWidth, rowHeight or 20)
        cell:SetPoint("LEFT", row, "LEFT", x, 0)
        
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", cell, "LEFT", 5, 0)
        text:SetSize(colWidth - 10, rowHeight or 20)
        text:SetJustifyH("LEFT")
        
        table.insert(columnFrames, {frame = cell, text = text})
        x = x + colWidth
    end
    
    return row, columnFrames
end

-- Hex color code to RGB
function UIUtils:HexToRGB(hex)
    hex = hex:gsub("#", "")
    return tonumber("0x" .. hex:sub(1, 2)) / 255,
           tonumber("0x" .. hex:sub(3, 4)) / 255,
           tonumber("0x" .. hex:sub(5, 6)) / 255
end

-- RGB to hex
function UIUtils:RGBToHex(r, g, b)
    return string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Get WoW color strings
function UIUtils:GetRoleIcon(role)
    local icons = {
        TANK = "|TInterface/LFGFrame/UI-LFG-ICON-TANK:16:16|t",
        DAMAGER = "|TInterface/LFGFrame/UI-LFG-ICON-DAMAGER:16:16|t",
        HEALER = "|TInterface/LFGFrame/UI-LFG-ICON-HEALER:16:16|t",
    }
    return icons[role] or ""
end

-- Create minimap button with drag support
function UIUtils:CreateMinimapButton(name, icon, onclick)
    if _G["StormsDungeonDataMinimapButton"] then
        return _G["StormsDungeonDataMinimapButton"]
    end
    if not Minimap then
        return nil
    end

    -- Prefer LibDBIcon (SexyMap friendly) if available
    if LibStub then
        local ldb = LibStub("LibDataBroker-1.1", true)
        local dbIcon = LibStub("LibDBIcon-1.0", true)
        if ldb and dbIcon then
            if not StormsDungeonDataDB then
                StormsDungeonDataDB = {}
            end
            if not StormsDungeonDataDB.settings then
                StormsDungeonDataDB.settings = {}
            end
            if not StormsDungeonDataDB.settings.libdbicon then
                StormsDungeonDataDB.settings.libdbicon = { hide = false, minimapPos = 225 }
            end

            if not self._ldbLauncher then
                self._ldbLauncher = ldb:NewDataObject("StormsDungeonData", {
                    type = "launcher",
                    text = "StormsDungeonData",
                    icon = icon or "Interface/Icons/Inv_misc_rune_10",
                    OnClick = function(_, button)
                        if onclick then
                            onclick(_, button)
                        end
                    end,
                    OnTooltipShow = function(tooltip)
                        if not tooltip then return end
                        tooltip:AddLine("StormsDungeonData")
                        tooltip:AddLine("Left-click: Open history", 0.2, 1, 0.2)
                        tooltip:AddLine("Right-click: Save pending run", 0.2, 1, 0.2)
                    end,
                })
            else
                self._ldbLauncher.icon = icon or self._ldbLauncher.icon
            end

            if not dbIcon:IsRegistered("StormsDungeonData") then
                dbIcon:Register("StormsDungeonData", self._ldbLauncher, StormsDungeonDataDB.settings.libdbicon)
            end

            if StormsDungeonDataDB.settings.libdbicon.hide then
                dbIcon:Hide("StormsDungeonData")
            else
                dbIcon:Show("StormsDungeonData")
            end

            return dbIcon:GetMinimapButton("StormsDungeonData")
        end
    end

    local containerName = name .. "Container"
    local container = _G[containerName]
    if not container then
        container = CreateFrame("Frame", containerName, UIParent)
        container:SetSize(8, 8)
        container:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
        container:SetFrameStrata("LOW")
        if Minimap.HookScript then
            Minimap:HookScript("OnHide", function() container:Hide() end)
            Minimap:HookScript("OnShow", function() container:Show() end)
        end
    else
        container:ClearAllPoints()
        container:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    end

    local existing = _G[name]
    local btn = existing or CreateFrame("Button", name, container)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(8)
    btn:SetHighestButtonLevel()
    
    -- Background
    btn:SetNormalTexture(icon or "Interface/Icons/Inv_misc_rune_10")
    btn:SetPushedTexture(icon or "Interface/Icons/Inv_misc_rune_10", 0.6, 0.6)
    btn:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
    
    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Run History", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Open history", 0.2, 1, 0.2)
        GameTooltip:AddLine("Right-click: Save pending run", 0.2, 1, 0.2)
        GameTooltip:AddLine("Drag to reposition", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Click handler
    if onclick then
        btn:SetScript("OnClick", onclick)
    end
    
    btn:SetClampedToScreen(true)

    local minimapRadius = 72

    local function PositionOnMinimap(angle)
        local x = math.cos(angle) * minimapRadius
        local y = math.sin(angle) * minimapRadius
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

    -- Dragging (locked to minimap ring)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function()
            PositionOnMinimap(GetAngleFromCursor())
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:SetScript("OnUpdate", nil)

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

        PositionOnMinimap(angle)
    end)

    -- Position button on minimap (default or saved)
    local angle = math.rad(225)
    if StormsDungeonDataDB and StormsDungeonDataDB.settings and StormsDungeonDataDB.settings.minimap and StormsDungeonDataDB.settings.minimap.angle then
        angle = StormsDungeonDataDB.settings.minimap.angle
    end
    PositionOnMinimap(angle)
    
    btn:Show()
    return btn
end

print("|cff00ffaa[StormsDungeonData]|r UI Utils module loaded")
