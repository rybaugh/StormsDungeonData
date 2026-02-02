-- Mythic Plus Tracker - Main Module
-- Initializes UI and slash commands

local MPT = StormsDungeonData

function MPT.UI:Initialize()
    -- Modules are loaded via the .toc file in order; don't overwrite them here.
    -- Just ensure tables exist so later calls don't hard error.
    MPT.Scoreboard = MPT.Scoreboard or {}
    MPT.HistoryViewer = MPT.HistoryViewer or {}
    
    print("|cff00ffaa[StormsDungeonData]|r UI module initialized")
end

function MPT.UI:ShowScoreboard(runRecord)
    if MPT.Scoreboard and MPT.Scoreboard.Show then
        MPT.Scoreboard:Show(runRecord)
    end
end

-- Slash command handler function (defined at load time)
local function HandleSlashCommand(msg, editbox)
    msg = (msg or ""):lower():trim()
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd or ""
    rest = rest or ""

    if cmd == "history" or cmd == "h" then
        MPT.HistoryViewer:Show()
    elseif cmd == "test" then
        MPT.TestMode:SimulateDungeonRun()
    elseif cmd == "testdata" then
        local n = tonumber(rest) or 15
        n = math.floor(n)
        if n < 1 then n = 1 end
        if n > 200 then n = 200 end

        if MPT.TestMode and MPT.TestMode.SeedHistory then
            MPT.TestMode:SeedHistory(n)
        else
            print("|cff00ffaa[StormsDungeonData]|r TestMode seeding not available")
        end
    elseif cmd == "reset" then
        StormsDungeonDataDB = MPT.Database:CreateDefaultDB()
        print("|cff00ffaa[StormsDungeonData]|r Database reset!")
    elseif cmd == "status" then
        print("|cff00ffaa[StormsDungeonData]|r Status:")
        print("  Total runs: " .. #StormsDungeonDataDB.runs)
        print("  Type |cff00ffaa/sdd history|r to view history")
    elseif cmd == "" or cmd == "help" then
        print("|cff00ffaa[StormsDungeonData]|r Commands:")
        print("  |cff00ffaa/sdd history|r - Show run history")
        print("  |cff00ffaa/sdd status|r - Show addon status")
        print("  |cff00ffaa/sdd test|r - Simulate dungeon completion (testing)")
        print("  |cff00ffaa/sdd testdata [n]|r - Generate n fake runs (default 15)")
        print("  |cff00ffaa/sdd reset|r - Reset database")
        print("  |cff00ffaa/sdd help|r - Show this message")
    else
        print("|cff00ffaa[StormsDungeonData]|r Unknown command: " .. msg)
    end
end

-- Register slash commands safely
-- Use pcall to prevent issues if SlashCmdList doesn't exist yet
if SlashCmdList then
    SLASH_STORMSDUNGEONDATA1 = "/sdd"
    SLASH_STORMSDUNGEONDATA2 = "/stormsdungeondata"
    SlashCmdList.STORMSDUNGEONDATA = HandleSlashCommand
end

print("|cff00ffaa[StormsDungeonData]|r Main module loaded")
