-- ============================================
--  ChatCommands - LocalScript
--  Place inside: StarterPlayerScripts
--  Same script runs on EVERY account, no changes needed per bot
-- ============================================

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

-- ============================================
--  CONFIGURATION
-- ============================================

local CONFIG = {
    -- The controller's username (the one who types commands)
    CONTROLLER = "kilomanskbot25",

    -- Bot accounts in order. Position in table = bot index.
    -- Bot at index 1 = "Bot1Username", index 2 = "Bot2Username", etc.
    -- The controller can also be in here if you want it to execute commands too.
    BOTS = {
        "kilomanskbot23",   -- index 1
        "kilomanskbot24",   -- index 2
        "kilomanskbot26",   -- index 3
    },

    PREFIX = ".",
    COMMAND_COOLDOWN = 3,
}

-- ============================================
--  RESOLVE THIS CLIENT'S BOT INDEX
-- ============================================

local BOT_INDEX = nil
for i, name in ipairs(CONFIG.BOTS) do
    if name:lower() == LocalPlayer.Name:lower() then
        BOT_INDEX = i
        break
    end
end

-- Not in the bot list and not the controller? Do nothing.
local IS_CONTROLLER = LocalPlayer.Name:lower() == CONFIG.CONTROLLER:lower()

if not BOT_INDEX and not IS_CONTROLLER then
    print("[ChatCommands] This account is not in BOTS list and is not the controller. Script inactive.")
    return
end

print(string.format(
    "[ChatCommands] Loaded as %s | Index: %s | Controller: %s",
    LocalPlayer.Name,
    BOT_INDEX and tostring(BOT_INDEX) or "CONTROLLER",
    CONFIG.CONTROLLER
))

-- ============================================
--  UTILITIES
-- ============================================

local cooldowns = {}

local function isOnCooldown(key)
    local last = cooldowns[key]
    if not last then return false end
    return (tick() - last) < CONFIG.COMMAND_COOLDOWN
end

local function setCooldown(key)
    cooldowns[key] = tick()
end

local function sendGlobalMessage(message)
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        local channels = TextChatService:FindFirstChild("TextChannels")
        if channels then
            local general = channels:FindFirstChild("RBXGeneral")
            if general then
                general:SendAsync(message)
                return
            end
        end
    end
    pcall(function()
        game:GetService("ReplicatedStorage")
            :WaitForChild("DefaultChatSystemChatEvents")
            :WaitForChild("SayMessageRequest")
            :FireServer(message, "All")
    end)
end

-- ".command arg1 arg2 3" → command="command", args={"arg1","arg2"}, rawArgs="arg1 arg2", targetIndex=3
local function parseCommand(message)
    local parts = {}
    for word in message:gmatch("%S+") do
        table.insert(parts, word)
    end

    local command = (parts[1] or ""):lower():sub(2)
    table.remove(parts, 1)

    local targetIndex = nil
    if #parts > 0 then
        local n = tonumber(parts[#parts])
        if n then
            targetIndex = n
            table.remove(parts, #parts)
        end
    end

    local rawArgs = table.concat(parts, " ")
    return command, parts, rawArgs, targetIndex
end

local function getLocalRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function getPlayerCFrame(playerName)
    local player = Players:FindFirstChild(playerName)
    if not player or not player.Character then return nil end
    local root = player.Character:FindFirstChild("HumanoidRootPart")
    return root and root.CFrame or nil
end

-- ============================================
--  COMMAND REGISTRY
-- ============================================

local Commands = {}

-- .chat [message] [index?]
Commands["chat"] = function(args, rawArgs)
    if rawArgs == "" then print("[Commands] Usage: .chat <message> <index?>") return end
    task.wait(0.3)
    sendGlobalMessage(rawArgs)
end

-- .rj [index?]
Commands["rj"] = function(args, rawArgs)
    print(string.format("[Bot %s] Rejoining...", BOT_INDEX or "CTRL"))
    task.wait(0.5)
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end

-- .re [index?]  — reset then teleport to controller
Commands["re"] = function(args, rawArgs)
    print(string.format("[Bot %s] Resetting...", BOT_INDEX or "CTRL"))
    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.Health = 0 end

    LocalPlayer.CharacterAdded:Wait()
    task.wait(1)

    local root = getLocalRoot()
    local targetCFrame = getPlayerCFrame(CONFIG.CONTROLLER)
    if root and targetCFrame then
        local offset = BOT_INDEX and (BOT_INDEX * 2) or 0
        root.CFrame = targetCFrame * CFrame.new(offset, 0, 0)
    end
end

-- .bring [index?]  — teleport to controller
Commands["bring"] = function(args, rawArgs)
    local root = getLocalRoot()
    local targetCFrame = getPlayerCFrame(CONFIG.CONTROLLER)
    if not root then print("[Commands] .bring — no character") return end
    if not targetCFrame then print("[Commands] .bring — controller not found") return end
    local offset = BOT_INDEX and (BOT_INDEX * 2) or 0
    root.CFrame = targetCFrame * CFrame.new(offset, 0, 0)
    print(string.format("[Bot %s] Brought to controller", BOT_INDEX or "CTRL"))
end

-- .surround [player] [index?]
-- Bots continuously teleport relative to the TARGET's facing direction.
-- Position is locked relative to the target's CFrame so it rotates with them.
-- 1 = in front, 2 = right, 3 = behind, 4 = left (wraps for 5+ bots)
-- .unsurround [index?] to stop

local surroundLoops = {} -- [BOT_INDEX] = true/false, used to cancel loop

Commands["surround"] = function(args, rawArgs)
    local targetName = rawArgs ~= "" and rawArgs or CONFIG.CONTROLLER

    -- Cancel any existing surround loop for this bot
    surroundLoops[BOT_INDEX] = false
    task.wait(0.05)
    surroundLoops[BOT_INDEX] = true

    local DISTANCE = 4  -- studs away from target
    local INTERVAL  = 0.05 -- seconds between each teleport tick

    -- Relative offsets in target's LOCAL CFrame space
    -- In Roblox local space: -Z = in front, +Z = behind, +X = left, -X = right
    local slots = {
        Vector3.new( DISTANCE, 0,  0),        -- 1: right
        Vector3.new( 0,        0,  DISTANCE), -- 2: behind
        Vector3.new(-DISTANCE, 0,  0),        -- 3: left
        Vector3.new( 0,        0, -DISTANCE), -- 4: in front
    }

    local slotIndex = ((BOT_INDEX - 1) % #slots) + 1
    local localOffset = slots[slotIndex]

    print(string.format("[Bot %s] .surround started — tracking '%s' at slot %d", BOT_INDEX, targetName, slotIndex))

    task.spawn(function()
        while surroundLoops[BOT_INDEX] do
            local targetPlayer = Players:FindFirstChild(targetName)
            if not targetPlayer or not targetPlayer.Character then
                task.wait(INTERVAL)
                continue
            end

            local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
            local root = getLocalRoot()

            if targetRoot and root then
                -- Transform local offset into world space using target's CFrame
                -- This makes the position rotate with the target
                local worldPos = targetRoot.CFrame * CFrame.new(localOffset)

                -- Always face the target's position
                root.CFrame = CFrame.lookAt(worldPos.Position, targetRoot.Position)
            end

            task.wait(INTERVAL)
        end

        print(string.format("[Bot %s] .surround stopped", BOT_INDEX))
    end)
end

-- .unsurround [index?]  — stop the surround loop
Commands["unsurround"] = function(args, rawArgs)
    surroundLoops[BOT_INDEX] = false
    print(string.format("[Bot %s] .unsurround — loop cancelled", BOT_INDEX))
end

-- ============================================
--  ATTACK SYSTEM
-- ============================================

local attackLoops = {}

local function fireClick(character)
    local communicate = character:FindFirstChild("Communicate")
    if not communicate then return end
    communicate:FireServer({ Goal = "LeftClick" })
    task.wait(0.1)
    communicate:FireServer({ Goal = "LeftClickRelease" })
end

-- .attack [target] [index?]
-- Bots surround target at 5 studs and take turns clicking alternately
Commands["attack"] = function(args, rawArgs)
    local targetName = rawArgs ~= "" and rawArgs or CONFIG.CONTROLLER

    attackLoops[BOT_INDEX] = false
    task.wait(0.05)
    attackLoops[BOT_INDEX] = true

    local DISTANCE      = 7
    local MOVE_INTERVAL = 0.05
    local CLICK_INTERVAL = 0.6  -- each bot clicks every (totalBots * CLICK_INTERVAL) seconds

    local totalBots = #CONFIG.BOTS

    -- Dynamically space bots evenly around a circle based on total bot count
    -- 2 bots = opposite sides, 3 = triangle, 4 = square, 5 = pentagon, etc.
    local slotIndex  = ((BOT_INDEX - 1) % totalBots) + 1
    local angle      = (2 * math.pi / totalBots) * (slotIndex - 1)  -- evenly spaced radians
    local worldOffset = Vector3.new(
        math.sin(angle) * DISTANCE,   -- X
        0,                            -- Y (stay on same level)
        -math.cos(angle) * DISTANCE   -- Z (negative cos so index 1 starts at north)
    )

    print(string.format("[Bot %s] .attack started — targeting '%s' slot %d", BOT_INDEX, targetName, slotIndex))

    -- Position loop: predicts target's next position using velocity
    task.spawn(function()
        local lastPos     = nil  -- target position last tick
        local lastTick    = nil  -- time of last tick

        -- How far ahead to predict (in seconds). Higher = more aggressive prediction.
        -- Tune this up if the target still escapes at high ping.
        local PREDICTION_TIME = 0.15

        while attackLoops[BOT_INDEX] do
            local tp = Players:FindFirstChild(targetName)
            if tp and tp.Character then
                local tr = tp.Character:FindFirstChild("HumanoidRootPart")
                local lr = getLocalRoot()
                if tr and lr then
                    local now     = tick()
                    local currPos = tr.Position

                    -- Read ping from target's player attributes (in ms), convert to seconds
                    -- Falls back to PREDICTION_TIME constant if attribute not found
                    local pingMs = tp:GetAttribute("Ping")
                    local predictionTime = pingMs and (pingMs / 1000) or PREDICTION_TIME

                    -- Calculate velocity from position delta between ticks
                    local predictedPos = currPos
                    if lastPos and lastTick then
                        local dt = now - lastTick
                        if dt > 0 then
                            local velocity = (currPos - lastPos) / dt
                            -- Project forward by target's actual ping
                            predictedPos = currPos + velocity * predictionTime
                        end
                    end

                    lastPos  = currPos
                    lastTick = now

                    -- Place bot at its world-space slot around the PREDICTED position
                    local botPos = predictedPos + worldOffset
                    lr.CFrame = CFrame.lookAt(botPos, predictedPos)
                end
            end
            task.wait(MOVE_INTERVAL)
        end
    end)

    -- Click loop: staggered so each bot takes turns
    task.spawn(function()
        task.wait((BOT_INDEX - 1) * CLICK_INTERVAL)  -- stagger start
        while attackLoops[BOT_INDEX] do
            local char = LocalPlayer.Character
            if char then
                fireClick(char)
            end
            task.wait(CLICK_INTERVAL * totalBots)
        end
        print(string.format("[Bot %s] .attack stopped", BOT_INDEX))
    end)
end

-- .unattack [index?]
Commands["unattack"] = function(args, rawArgs)
    attackLoops[BOT_INDEX] = false
    print(string.format("[Bot %s] .unattack — stopped", BOT_INDEX))
end

-- .leave [index?]
Commands["leave"] = function(args, rawArgs)
    print(string.format("[Bot %s] .leave — disconnecting...", BOT_INDEX))
    task.wait(0.2)
    game:GetService("Players").LocalPlayer:Kick()
end

-- ============================================
--  ADD MORE COMMANDS BELOW
-- ============================================

-- Commands["yourcommand"] = function(args, rawArgs)
-- end

-- ============================================
--  COMMAND HANDLER
-- ============================================

local function handleMessage(speakerName, messageText)
    if speakerName:lower() ~= CONFIG.CONTROLLER:lower() then return end
    if messageText:sub(1, 1) ~= CONFIG.PREFIX then return end

    local command, args, rawArgs, targetIndex = parseCommand(messageText)
    if command == "" then return end

    -- Controller only listens, never executes commands
    if IS_CONTROLLER and not BOT_INDEX then return end

    -- Index routing:
    -- No index = all bots execute
    -- Index given = only that bot index executes
    if targetIndex ~= nil then
        if BOT_INDEX ~= targetIndex then return end
    end

    local key = command .. "_" .. (BOT_INDEX or "ctrl")
    if isOnCooldown(key) then return end

    local fn = Commands[command]
    if fn then
        setCooldown(key)
        local ok, err = pcall(fn, args, rawArgs)
        if not ok then
            print(string.format("[Bot %s] Error in .%s: %s", BOT_INDEX or "CTRL", command, err))
        end
    else
        print(string.format("[Bot %s] Unknown command: .%s", BOT_INDEX or "CTRL", command))
    end
end

-- ============================================
--  CHAT LISTENERS
-- ============================================

if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
    TextChatService.MessageReceived:Connect(function(msg)
        if not msg.TextSource then return end
        local player = Players:GetPlayerByUserId(msg.TextSource.UserId)
        if player then handleMessage(player.Name, msg.Text) end
    end)
else
    local function listenToPlayer(player)
        player.Chatted:Connect(function(msg) handleMessage(player.Name, msg) end)
    end
    for _, p in ipairs(Players:GetPlayers()) do listenToPlayer(p) end
    Players.PlayerAdded:Connect(listenToPlayer)
end
