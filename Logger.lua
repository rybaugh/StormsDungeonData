-- StormsDungeonData - Action logger for debugging (why run did/didn't save)
-- Logs to StormsDungeonDataLog (SavedVariable). Use /sdd log to view, /sdd log clear to reset.

StormsDungeonDataLog = StormsDungeonDataLog or { lines = {}, maxLines = 1000 }

local MPT = StormsDungeonData
local Log = {}
MPT.Log = Log

local LOG = StormsDungeonDataLog
if not LOG.lines then LOG.lines = {} end
if not LOG.maxLines or LOG.maxLines < 100 then LOG.maxLines = 1000 end

local function timestamp()
    local t = date("*t")
    return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

function Log:Log(level, message)
    if not message then message = tostring(level) level = "INFO" end
    if type(level) == "string" and level:match("^%u") then
        -- level, message
        level = level:upper()
    else
        message = tostring(level)
        level = "INFO"
    end
    local line = string.format("[%s] [%s] %s", timestamp(), level, tostring(message))
    table.insert(LOG.lines, line)
    while #LOG.lines > LOG.maxLines do
        table.remove(LOG.lines, 1)
    end
    return line
end

function Log:Info(msg)   return self:Log("INFO", msg) end
function Log:Warn(msg)    return self:Log("WARN", msg) end
function Log:Error(msg)  return self:Log("ERROR", msg) end

function Log:GetLines(lastN)
    local n = lastN or #LOG.lines
    local start = math.max(1, #LOG.lines - n + 1)
    local out = {}
    for i = start, #LOG.lines do
        table.insert(out, LOG.lines[i])
    end
    return out
end

function Log:Clear()
    LOG.lines = {}
    return self:Info("Log cleared.")
end

function Log:DumpToChat(lastN)
    lastN = lastN or 100
    local lines = self:GetLines(lastN)
    print("|cff00ffaa[StormsDungeonData]|r --- Log (last " .. #lines .. " lines) ---")
    for _, line in ipairs(lines) do
        print("|cffaaaaaa" .. line .. "|r")
    end
    print("|cff00ffaa[StormsDungeonData]|r --- End log. Use /sdd log 500 for more, /sdd log clear to reset. ---")
end

-- Try to write log to a file (WoW may block; fallback is SavedVariable only)
function Log:WriteToFile()
    local path = "StormsDungeonData_log.txt"
    local ok, err = pcall(function()
        local f = io.open(path, "w")
        if not f then
            self:Warn("Could not open file for writing (io may be restricted). Log is in SavedVariable; use /sdd log.")
            return
        end
        for _, line in ipairs(LOG.lines) do
            f:write(line .. "\n")
        end
        f:close()
    end)
    if ok then
        print("|cff00ffaa[StormsDungeonData]|r Log written to " .. path)
    else
        print("|cffff4444[StormsDungeonData]|r Log file write failed (WoW may restrict file I/O). Use /sdd log to view.")
    end
end

