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

print("|cff00ffaa[StormsDungeonData]|r UI Utils module loaded")
