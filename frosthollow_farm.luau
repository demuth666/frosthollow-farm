--[[
    FrostHollow [ Floor 1 ] — Auto Farm Hub
    UI      : WindUI (Footagesus)
    Fitur   : Auto Farm, Auto Loot, Auto Revive, Auto Mine (pickaxe),
              Kill Aura, ESP, Teleport waypoint/quest, Speed/Jump/Fly/Noclip,
              Infinite Jump, Anti-AFK, Auto Allocate Stat.

    Catatan: script ini client-side. Posisi karakter & tool activation itu
    client-authoritative di game ini (sudah dites), jadi farm jalan lewat
    teleport + Tool:Activate(). Pakai speed wajar biar tidak mencurigakan.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local VirtualUser = game:GetService("VirtualUser")

local LP = Players.LocalPlayer
local Router = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("NetworkRouter")

-- single-instance guard: reload lama otomatis berhenti
local genv = getgenv()
local CoreGui = game:GetService("CoreGui")
local genObj = CoreGui:FindFirstChild("FrostHollowFarmGen")
if not genObj then
    genObj = Instance.new("NumberValue")
    genObj.Name = "FrostHollowFarmGen"
    genObj.Value = 0
    genObj.Parent = CoreGui
end
genObj.Value = genObj.Value + 1
local MY_GEN = genObj.Value

-- bersihkan window dari instance script sebelumnya (kalau re-run tanpa rejoin)
do
    local rg = CoreGui:FindFirstChild("RobloxGui")
    local oldWin = rg and rg:FindFirstChild("WindUI")
    if oldWin then
        pcall(function() oldWin:Destroy() end)
    end
end

-- ============================================================
-- WindUI (jsDelivr + cache sumber, biar reload nggak nunggu GitHub)
-- ============================================================
local WindUI
do
    local URL = "https://cdn.jsdelivr.net/gh/Footagesus/WindUI@main/dist/main.lua"
    local src = genv.__fh_windui_src
    if not src then
        local ok, res = pcall(function() return game:HttpGet(URL) end)
        if ok and type(res) == "string" and #res > 1000 then
            src = res
            genv.__fh_windui_src = src
        end
    end
    local ok, err
    if src then
        ok, err = pcall(function()
            WindUI = loadstring(src)()
        end)
    else
        ok, err = pcall(function()
            WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
        end)
    end
    if not ok or not WindUI then
        error("Gagal load WindUI: " .. tostring(err))
    end
end

-- ============================================================
-- Config default
-- ============================================================
local C = {
    -- farm
    Farm = false,
    Aura = false,
    AutoLoot = true,
    AutoRevive = true,
    AutoMine = false,
    AutoStat = false,
    IncludeBosses = false,
    Priority = "Nearest",      -- Nearest / Lowest HP / Highest Level
    MinLevel = 1,
    MaxLevel = 0,              -- 0 = otomatis (Lv pemain + 2)
    SwingInterval = 0.18,
    MaxChase = 900,
    RetreatHP = 20,
    ResumeHP = 65,
    LootRange = 120,
    MobFilter = {},
    -- movement
    SpeedHack = false,
    Speed = 30,
    JumpBoost = false,
    Jump = 80,
    Fly = false,
    FlySpeed = 70,
    Noclip = false,
    InfJump = false,
    AntiAFK = true,
    -- visuals
    EspMobs = false,
    EspDrops = false,
    EspCrystals = false,
    EspPlayers = false,
    EspDistance = 400,
    -- parry
    AutoParry = true,
    ParryLead = 0,          -- offset manual; 0 = auto pakai latency terukur
    ParryHold = 0.3,
    ParryRange = 16,
    AutoDash = true,
    DashHP = 45,
    DashBoss = true,
    BossSafe = true,
    BossRetreatHP = 50,
}

local StatChoice = "Damage"

-- State auto parry (server-authoritative: RequestBlockStart / RequestBlockEnd)
local PARRY_ATTACK_ACTIONS_EXCLUDED = {
    Idle = true, Hop = true, Walk = true, Run = true,
    Notice = true, Spawn = true, Dead = true,
}
local parry = {
    nextImpact = nil,     -- detik menuju impact serangan terdekat
    attacker = nil,       -- mob yang serangannya paling dekat
    impact = {},          -- [mob|action] = waktu impact yang dipelajari
    latency = nil,        -- latency terukur dari ParryWindowEnd
    lastTry = -999,
    blocking = false,
    busyUntil = 0,
    scanAt = 0,
    lastHP = nil,
    attempts = 0,
    successes = 0,
    lastSelfParryAt = nil,
    lastAttempt = nil,
    seenParryAt = {},
}

-- Dipakai auto farm & defense (dideklarasikan di awal supaya bisa diakses farmStep)
local VIM = game:GetService("VirtualInputManager")
local dashReadyAt = 0
local dashHoldUntil = 0

-- ============================================================
-- Helper umum
-- ============================================================
local function notify(title, content, icon)
    if WindUI then
        pcall(function()
            WindUI:Notify({ Title = title, Content = content, Icon = icon or "snowflake", Duration = 4 })
        end)
    end
end

local function getChar()
    local char = LP.Character
    if not char then return nil end
    return char, char:FindFirstChild("HumanoidRootPart"), char:FindFirstChildOfClass("Humanoid"), char:FindFirstChildOfClass("Tool")
end

local function getHRP()
    local char, hrp, hum = getChar()
    if char and hrp and hum and hum.Health > 0 then return hrp, hum, char end
    return nil
end

local function playerLevel()
    local ls = LP:FindFirstChild("leaderstats")
    local lv = ls and ls:FindFirstChild("Lv")
    return lv and lv.Value or 1
end

local function groundY(pos)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local char = LP.Character
    params.FilterDescendantsInstances = char and { char } or {}
    local hit = Workspace:Raycast(pos + Vector3.new(0, 25, 0), Vector3.new(0, -150, 0), params)
    return hit and hit.Position.Y or pos.Y
end

local function teleportTo(pos, facePos)
    local hrp, hum = getHRP()
    if not (hrp and hum) then return false end
    local y = groundY(pos)
    local flat = Vector3.new(pos.X, y + 3, pos.Z)
    if facePos then
        hrp.CFrame = CFrame.lookAt(flat, Vector3.new(facePos.X, flat.Y, facePos.Z))
    else
        hrp.CFrame = CFrame.new(flat)
    end
    hrp.AssemblyLinearVelocity = Vector3.zero
    return true
end

local function checkpoint(name)
    local map = Workspace:FindFirstChild("Map")
    local cps = map and map:FindFirstChild("Checkpoints")
    local cp = cps and cps:FindFirstChild(name)
    local sp = cp and cp:FindFirstChild("SpawnPoint")
    return sp and sp.Position or nil
end

local function ensureTool()
    local char = LP.Character
    if not char then return nil end
    local tool = char:FindFirstChildOfClass("Tool")
    if tool then return tool end
    local pack = LP:FindFirstChild("Backpack")
    local t = pack and pack:FindFirstChildOfClass("Tool")
    if t then
        pcall(function() t.Parent = char end)
        task.wait(0.1)
        return char:FindFirstChildOfClass("Tool")
    end
    -- fallback: minta server equip slot 1-3
    for slot = 1, 3 do
        Router:FireServer("RequestHoldTool", slot)
        task.wait(0.15)
        local eq = char:FindFirstChildOfClass("Tool")
        if eq then return eq end
    end
    return nil
end

-- ============================================================
-- Data mob
-- ============================================================
local badTargets = {}

local function isBoss(m)
    return m:GetAttribute("Boss") == true
        or m:GetAttribute("RoomBoss") == true
        or m:GetAttribute("King") == true
        or CollectionService:HasTag(m, "Boss")
end

local function mobInfo(m)
    if not m:IsA("Model") then return nil end
    local hum = m:FindFirstChildOfClass("Humanoid")
    local root = m:FindFirstChild("HumanoidRootPart")
    if not (hum and root) then return nil end
    if hum.Health <= 0 then return nil end
    return {
        model = m,
        hum = hum,
        root = root,
        lvl = tonumber(m:GetAttribute("Level")) or 1,
        boss = isBoss(m),
        name = m:GetAttribute("DisplayName") or m.Name,
        hp = hum.Health,
        maxHp = hum.MaxHealth,
    }
end

local function mobList()
    local list = {}
    local ents = Workspace:FindFirstChild("Entities")
    if not ents then return list end
    for _, m in ipairs(ents:GetChildren()) do
        local info = mobInfo(m)
        if info then
            list[#list + 1] = info
        end
    end
    return list
end

local function levelCap()
    if C.MaxLevel and C.MaxLevel > 0 then return C.MaxLevel end
    return playerLevel() + 2
end

-- ============================================================
-- Nama mob (EN) + filter target
-- ============================================================
local MOB_EN = {
    ["슬라임"] = "Slime",
    ["대왕 슬라임"] = "King Slime",
    ["파편 슬라임"] = "Shard Slime",
    ["늑대"] = "Wolf",
    ["대왕 늑대"] = "King Wolf",
    ["북극곰"] = "Polar Bear",
    ["대왕 북극곰"] = "King Polar Bear",
    ["골렘"] = "Golem",
    ["대왕 골렘"] = "King Golem",
    ["거미"] = "Spider",
    ["대왕 거미"] = "King Spider",
    ["거미 알집 수호충"] = "Egg Guardian Spider",
    ["고블린"] = "Goblin",
    ["고블린 족장"] = "Goblin Chief",
    ["도적"] = "Bandit",
    ["도적 두목"] = "Bandit Chief",
    ["해골 광부"] = "Skeleton Miner",
}

local function mobLabel(name)
    local en = MOB_EN[name]
    if en then return en .. " (" .. name .. ")" end
    return name
end

local function buildMobOptions()
    local seen, names = {}, {}
    local folder = ReplicatedStorage:FindFirstChild("Mobs")
    if folder then
        for _, m in ipairs(folder:GetChildren()) do
            if not seen[m.Name] then
                seen[m.Name] = true
                names[#names + 1] = m.Name
            end
        end
    end
    local ents = Workspace:FindFirstChild("Entities")
    if ents then
        for _, m in ipairs(ents:GetChildren()) do
            if m:FindFirstChildOfClass("Humanoid") then
                local n = m:GetAttribute("DisplayName") or m.Name
                if not seen[n] then
                    seen[n] = true
                    names[#names + 1] = n
                end
            end
        end
    end
    local sorted = {}
    for _, n in ipairs(names) do
        sorted[#sorted + 1] = { label = mobLabel(n), key = MOB_EN[n] or n }
    end
    table.sort(sorted, function(a, b) return a.key < b.key end)
    local labels, nameOf = {}, {}
    for _, e in ipairs(sorted) do
        labels[#labels + 1] = e.label
    end
    for _, n in ipairs(names) do
        nameOf[mobLabel(n)] = n
    end
    return labels, nameOf
end

local function mobPass(info)
    if not C.MobFilter then return true end
    if next(C.MobFilter) == nil then return true end
    return C.MobFilter[info.name] == true or C.MobFilter[info.model.Name] == true
end

local function pickTarget(hrp)
    local cap = levelCap()
    local now = os.clock()
    local best, bestScore
    for _, info in ipairs(mobList()) do
        local badUntil = badTargets[info.model]
        local ok = info.lvl >= C.MinLevel
            and info.lvl <= cap
            and (C.IncludeBosses or not info.boss)
            and (not badUntil or badUntil < now)
            and mobPass(info)
        if ok then
            local d = (info.root.Position - hrp.Position).Magnitude
            if d <= C.MaxChase then
                local score = d
                if C.Priority == "Lowest HP" then
                    score = info.hp
                elseif C.Priority == "Highest Level" then
                    score = -info.lvl
                end
                if not bestScore or score < bestScore then
                    best, bestScore = info, score
                end
            end
        end
    end
    return best
end

-- ============================================================
-- Auto revive
-- ============================================================
local lastRevive = 0
local lastRetreatNote = 0
local function reviveNow()
    if os.clock() - lastRevive < 4 then return end
    lastRevive = os.clock()
    pcall(function() Router:FireServer("RequestRespawn") end)
end

-- ============================================================
-- Auto loot
-- ============================================================
local function dropList()
    local out = {}
    local drops = Workspace:FindFirstChild("Drops") or Workspace:FindFirstChild("DropsLoot")
    if not drops then return out end
    for _, d in ipairs(drops:GetChildren()) do
        if d:IsA("BasePart") then
            local prompt = d:FindFirstChildOfClass("ProximityPrompt")
            if prompt then
                out[#out + 1] = { part = d, prompt = prompt, label = prompt.ObjectText }
            end
        end
    end
    return out
end

local function collectDrop(drop)
    local hrp = getHRP()
    if not hrp then return end
    local pos = drop.part.Position
    local y = groundY(pos + Vector3.new(0, 0, 3))
    hrp.CFrame = CFrame.new(Vector3.new(pos.X + 2, y + 3, pos.Z + 2))
    task.wait(0.15)
    if not drop.prompt.Parent then return end
    pcall(function()
        drop.prompt:InputHoldBegin()
        task.wait(0.08)
        drop.prompt:InputHoldEnd()
    end)
end

-- ============================================================
-- Crystal / mining
-- ============================================================
local function crystalList()
    local out = {}
    local folder = Workspace:FindFirstChild("CrystalNodes")
    if not folder then return out end
    for _, node in ipairs(folder:GetChildren()) do
        local hp = tonumber(node:GetAttribute("MiningHealth")) or tonumber(node:GetAttribute("Health"))
        if hp and hp > 0 then
            out[#out + 1] = { model = node, hp = hp }
        end
    end
    return out
end

local function findPickaxe()
    local char = LP.Character
    local pack = LP:FindFirstChild("Backpack")
    for _, cont in ipairs({ char, pack }) do
        if cont then
            for _, t in ipairs(cont:GetChildren()) do
                if t:IsA("Tool") and (string.find(string.lower(t.Name), "pick") or t:GetAttribute("Pickaxe")) then
                    return t
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- Loop: Farm
-- ============================================================
local farmThread = nil
local tracker = { model = nil, hp = 0, since = 0 }
local retreating = false
local hudState = { target = "-", state = "IDLE", kills = 0, loots = 0 }

local function farmStep()
    local hrp, hum, char = getHRP()
    if not (hrp and hum) then
        if C.AutoRevive and LP.Character then
            local h = LP.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health <= 0 then
                hudState.state = "DEAD"
                reviveNow()
            end
        end
        task.wait(0.6)
        return
    end

    -- HP rendah: kabur ke Town dan tunggu regen sampai aman
    local hpPct = (hum.Health / math.max(hum.MaxHealth, 1)) * 100
    local bossFight = false
    if tracker.model and tracker.model.Parent then
        local th = tracker.model:FindFirstChildOfClass("Humanoid")
        bossFight = th ~= nil and th.Health > 0 and isBoss(tracker.model)
    end
    local retreatAt = C.RetreatHP
    if bossFight and (C.BossRetreatHP or 0) > retreatAt then
        retreatAt = C.BossRetreatHP
    end
    if hpPct <= retreatAt then
        retreating = true
    end
    if retreating then
        hudState.state = "RETREAT"
        local p = checkpoint("Town")
        if p and (hrp.Position - p).Magnitude > 40 then
            teleportTo(p + Vector3.new(0, 4, 0))
            if os.clock() - lastRetreatNote > 8 then
                lastRetreatNote = os.clock()
                notify("Retreat", "HP rendah (" .. math.floor(hpPct) .. "%), nunggu regen di Town", "shield-alert")
            end
        end
        if hpPct >= C.ResumeHP then
            retreating = false
        else
            task.wait(1)
            return
        end
    end

    -- tetap kejar target yang sama sampai mati (biar kill cepat)
    local target
    if tracker.model and tracker.model.Parent then
        local info = mobInfo(tracker.model)
        if info and (info.root.Position - hrp.Position).Magnitude <= C.MaxChase then
            target = info
        end
    end
    if not target then
        target = pickTarget(hrp)
    end
    if not target then
        hudState.state = "IDLE"
        hudState.target = "-"
        tracker.model = nil
        task.wait(0.5)
        return
    end

    -- hitung kill saat ganti target dan target lama sudah mati
    if tracker.model and tracker.model ~= target.model then
        local oldHum = tracker.model:FindFirstChildOfClass("Humanoid")
        if not oldHum or oldHum.Health <= 0 then
            hudState.kills = hudState.kills + 1
        end
    end

    hudState.state = "FARMING"
    hudState.target = string.format("%s Lv.%d", target.name, target.lvl)

    -- deteksi target tidak bisa dilukai (di balik dinding / tidak sinkron)
    if tracker.model ~= target.model then
        tracker.model = target.model
        tracker.hp = target.hp
        tracker.since = os.clock()
    elseif target.hp < tracker.hp then
        tracker.hp = target.hp
        tracker.since = os.clock()
    elseif os.clock() - tracker.since > 6 then
        badTargets[target.model] = os.clock() + 25
        tracker.model = nil
        task.wait(0.2)
        return
    end

    local rootPos = target.root.Position
    local myPos = hrp.Position
    local dir = Vector3.new(myPos.X - rootPos.X, 0, myPos.Z - rootPos.Z)
    if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, 1) end
    local stand
    if target.boss then
        -- boss: cari posisi di belakang biar serangan depan meleset
        local look = Vector3.new(target.root.CFrame.LookVector.X, 0, target.root.CFrame.LookVector.Z)
        if look.Magnitude < 0.1 then look = Vector3.new(0, 0, 1) else look = look.Unit end
        stand = rootPos - look * 4.5
    else
        stand = rootPos + dir.Unit * 3.2
    end

    if (myPos - stand).Magnitude > 7 or math.abs(myPos.Y - rootPos.Y) > 8 then
        hrp.CFrame = CFrame.lookAt(Vector3.new(stand.X, rootPos.Y + 3, stand.Z), rootPos)
        hrp.AssemblyLinearVelocity = Vector3.zero
    else
        hrp.CFrame = CFrame.lookAt(myPos, Vector3.new(rootPos.X, myPos.Y, rootPos.Z))
    end

    if C.AutoParry and (parry.blocking or (parry.nextImpact and parry.nextImpact < 0.4 and parry.nextImpact > -0.15)) then
        -- tahan pukulan sebentar supaya block/parry bisa masuk
        task.wait(0.04)
        return
    end

    if C.AutoDash and os.clock() < dashHoldUntil then
        -- habis dash, jangan langsung teleport balik ke hitbox
        task.wait(0.05)
        return
    end

    if target.boss and C.BossSafe and parry.nextImpact and parry.nextImpact < 0.6 and parry.nextImpact > -0.2 then
        -- serangan boss sudah dekat: berhenti mukul, biar parry/dash yang kerja
        task.wait(0.06)
        return
    end

    local tool = ensureTool()
    if tool then
        pcall(function() tool:Activate() end)
    end
    task.wait(C.SwingInterval)
end

local function startFarm()
    if farmThread then return end
    farmThread = task.spawn(function()
        while C.Farm and genObj.Value == MY_GEN do
            local ok, err = pcall(farmStep)
            if not ok then
                warn("[FrostHollow] farm error: " .. tostring(err))
                task.wait(1)
            end
        end
        farmThread = nil
    end)
end

-- ============================================================
-- Loop: Aura (auto attack di tempat)
-- ============================================================
local function auraStep()
    local hrp, hum, char = getHRP()
    if not (hrp and hum) then task.wait(0.4); return end
    local cap = levelCap()
    local nearest, nd
    for _, info in ipairs(mobList()) do
        if info.lvl >= C.MinLevel and info.lvl <= cap and (C.IncludeBosses or not info.boss) and mobPass(info) then
            local d = (info.root.Position - hrp.Position).Magnitude
            if d <= 10 and (not nd or d < nd) then nearest, nd = info, d end
        end
    end
    if nearest then
        hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(nearest.root.Position.X, hrp.Position.Y, nearest.root.Position.Z))
        local tool = ensureTool()
        if tool then pcall(function() tool:Activate() end) end
    end
    task.wait(0.16)
end

local auraThread = nil
local function startAura()
    if auraThread then return end
    auraThread = task.spawn(function()
        while C.Aura and genObj.Value == MY_GEN do
            local ok, err = pcall(auraStep)
            if not ok then warn("[FrostHollow] aura error: " .. tostring(err)); task.wait(0.5) end
        end
        auraThread = nil
    end)
end

-- ============================================================
-- Loop: Loot
-- ============================================================
local lootThread = nil
local function startLoot()
    if lootThread then return end
    lootThread = task.spawn(function()
        while C.AutoLoot and genObj.Value == MY_GEN do
            if C.Farm or C.Aura then
                local ok = pcall(function()
                    local hrp = getHRP()
                    if not hrp then return end
                    local best, bd
                    for _, d in ipairs(dropList()) do
                        local dist = (d.part.Position - hrp.Position).Magnitude
                        if dist <= C.LootRange and (not bd or dist < bd) then best, bd = d, dist end
                    end
                    if best then
                        collectDrop(best)
                        hudState.loots = hudState.loots + 1
                        task.wait(0.3)
                    end
                end)
                if not ok then task.wait(0.5) end
            end
            task.wait(0.8)
        end
        lootThread = nil
    end)
end

-- ============================================================
-- Loop: Mine (butuh Pickaxe)
-- ============================================================
local mineThread = nil
local mineWarned = false
local function startMine()
    if mineThread then return end
    mineThread = task.spawn(function()
        while C.AutoMine and genObj.Value == MY_GEN do
            local ok = pcall(function()
                local hrp, hum, char = getHRP()
                if not (hrp and hum) then task.wait(0.6); return end
                local pick = findPickaxe()
                if not pick then
                    if not mineWarned then
                        mineWarned = true
                        notify("Auto Mine", "Kamu belum punya Pickaxe. Beli dulu di Blacksmith.", "pickaxe")
                    end
                    task.wait(2)
                    return
                end
                local best, bd
                for _, node in ipairs(crystalList()) do
                    local root = node.model:FindFirstChild("Root") or node.model:FindFirstChild("Hitbox")
                    if root then
                        local d = (root.Position - hrp.Position).Magnitude
                        if d <= C.MaxChase and (not bd or d < bd) then best, bd = node, d end
                    end
                end
                if best then
                    local root = best.model:FindFirstChild("Root") or best.model:FindFirstChild("Hitbox")
                    local pos = root.Position
                    local dir = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
                    if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, 1) end
                    local stand = pos + dir.Unit * 3
                    hrp.CFrame = CFrame.lookAt(Vector3.new(stand.X, pos.Y + 3, stand.Z), pos)
                    if pick.Parent ~= char then
                        pcall(function() pick.Parent = char end)
                        task.wait(0.15)
                    end
                    local held = char:FindFirstChildOfClass("Tool")
                    if held then pcall(function() held:Activate() end) end
                    task.wait(0.3)
                else
                    task.wait(1)
                end
            end)
            if not ok then task.wait(0.6) end
        end
        mineThread = nil
    end)
end

-- ============================================================
-- Loop: Auto stat
-- ============================================================
local statThread = nil
local function startAutoStat()
    if statThread then return end
    statThread = task.spawn(function()
        while C.AutoStat and genObj.Value == MY_GEN do
            local pts = LP:GetAttribute("StatPoints") or 0
            if pts > 0 then
                pcall(function()
                    Router:FireServer("RequestAllocateStat", { Stat = StatChoice, Amount = pts })
                end)
                task.wait(1.5)
            end
            task.wait(0.8)
        end
        statThread = nil
    end)
end

-- ============================================================
-- Anti-AFK
-- ============================================================
local idleConn
local function setAntiAFK(on)
    if on and not idleConn then
        idleConn = LP.Idled:Connect(function()
            local ok = pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
            if not ok then
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton1(Vector2.new(0, 0))
                end)
            end
        end)
    elseif not on and idleConn then
        idleConn:Disconnect()
        idleConn = nil
    end
end

-- ============================================================
-- Movement
-- ============================================================
local moveConn = RunService.Heartbeat:Connect(function()
    if genObj.Value ~= MY_GEN then return end
    local char, hrp, hum = getChar()
    if not (char and hum and hum.Health > 0) then return end
    if C.SpeedHack then
        hum.WalkSpeed = C.Speed
    end
    if C.JumpBoost then
        hum.UseJumpPower = true
        hum.JumpPower = C.Jump
    end
    if C.Noclip then
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end
end)

local infJumpConn = UserInputService.JumpRequest:Connect(function()
    if genObj.Value ~= MY_GEN then return end
    if not C.InfJump then return end
    local _, _, hum = getChar()
    if hum and hum.Health > 0 then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

-- Fly
local flyBv, flyBg, flyConn
local function stopFly()
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyBv then flyBv:Destroy(); flyBv = nil end
    if flyBg then flyBg:Destroy(); flyBg = nil end
end

local function startFly()
    stopFly()
    local hrp, hum = getHRP()
    if not (hrp and hum) then return end
    flyBv = Instance.new("BodyVelocity")
    flyBv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBv.Velocity = Vector3.zero
    flyBv.Parent = hrp

    flyBg = Instance.new("BodyGyro")
    flyBg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    flyBg.P = 1200
    flyBg.D = 80
    flyBg.CFrame = hrp.CFrame
    flyBg.Parent = hrp

    flyConn = RunService.RenderStepped:Connect(function()
        if genObj.Value ~= MY_GEN then return end
        if not flyBv or not flyBv.Parent then return end
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local _, _, hum = getChar()
        local dir = Vector3.zero
        if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
            -- mobile: terbang ke arah pandang selama joystick digerakkan
            if hum and hum.MoveDirection.Magnitude > 0.05 then
                dir = cam.CFrame.LookVector
            end
        else
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
        end
        flyBv.Velocity = dir.Magnitude > 0 and dir.Unit * C.FlySpeed or Vector3.zero
        flyBg.CFrame = cam.CFrame
    end)
end

-- ============================================================
-- ESP
-- ============================================================
local DRAW_OK = Drawing ~= nil and type(Drawing.new) == "function"
local espObjects = {}
local function setProp(obj, prop, value)
    pcall(function() obj[prop] = value end)
end

local function espLabel(key)
    local obj = espObjects[key]
    if obj then return obj end
    obj = Drawing.new("Text")
    setProp(obj, "Size", 14)
    setProp(obj, "Center", true)
    setProp(obj, "Outline", true)
    setProp(obj, "OutlineColor", Color3.new(0, 0, 0))
    setProp(obj, "Font", 2)
    setProp(obj, "Visible", false)
    espObjects[key] = obj
    return obj
end

local function hideAllEsp()
    for _, obj in pairs(espObjects) do
        obj.Visible = false
    end
end

local function clearEsp()
    for key, obj in pairs(espObjects) do
        pcall(function() obj:Remove() end)
        espObjects[key] = nil
    end
end

local espScan = { at = 0, mobs = {}, drops = {}, crystals = {}, players = {} }

local function refreshEspCache()
    local now = os.clock()
    if now - espScan.at < 0.35 then return end
    espScan.at = now
    espScan.mobs = mobList()
    espScan.drops = dropList()
    espScan.crystals = crystalList()
    espScan.players = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local root = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 then
                espScan.players[#espScan.players + 1] = { player = p, root = root, hum = hum }
            end
        end
    end
end

local espConn = RunService.RenderStepped:Connect(function()
    if genObj.Value ~= MY_GEN then return end
    if not DRAW_OK then return end
    if not (C.EspMobs or C.EspDrops or C.EspCrystals or C.EspPlayers) then
        hideAllEsp()
        return
    end
    local cam = Workspace.CurrentCamera
    local hrp = getHRP()
    if not (cam and hrp) then hideAllEsp(); return end
    refreshEspCache()
    local seen = {}

    local function draw(key, worldPos, text, color)
        if (worldPos - hrp.Position).Magnitude > C.EspDistance then return end
        local sp, onScreen = cam:WorldToViewportPoint(worldPos)
        if not onScreen then return end
        local obj = espLabel(key)
        obj.Position = Vector2.new(sp.X, sp.Y)
        obj.Text = text
        obj.Color = color
        obj.Visible = true
        seen[key] = true
    end

    if C.EspMobs then
        for _, info in ipairs(espScan.mobs) do
            local pos = info.root.Position + Vector3.new(0, 2.6, 0)
            local text = string.format("%s  Lv.%d  [%d/%d]  %dm", info.name, info.lvl, math.floor(info.hp), math.floor(info.maxHp), math.floor((info.root.Position - hrp.Position).Magnitude))
            local color = info.boss and Color3.fromRGB(255, 160, 60) or Color3.fromRGB(255, 90, 90)
            draw(info.model, pos, text, color)
        end
    end

    if C.EspDrops then
        for i, drop in ipairs(espScan.drops) do
            draw("drop_" .. i, drop.part.Position + Vector3.new(0, 2, 0), "[DROP] " .. (drop.label ~= "" and drop.label or "Loot"), Color3.fromRGB(255, 220, 90))
        end
    end

    if C.EspCrystals then
        for i, node in ipairs(espScan.crystals) do
            local root = node.model:FindFirstChild("Root") or node.model:FindFirstChild("Hitbox")
            if root then
                draw("crystal_" .. i, root.Position + Vector3.new(0, 3, 0), string.format("Crystal  [%d]", math.floor(node.hp)), Color3.fromRGB(120, 230, 255))
            end
        end
    end

    if C.EspPlayers then
        for i, info in ipairs(espScan.players) do
            local d = math.floor((info.root.Position - hrp.Position).Magnitude)
            draw("player_" .. i, info.root.Position + Vector3.new(0, 3, 0), string.format("%s  %dm", info.player.Name, d), Color3.fromRGB(120, 255, 150))
        end
    end

    for key, obj in pairs(espObjects) do
        if not seen[key] then obj.Visible = false end
    end
end)

-- ============================================================
-- Auto Parry
-- ============================================================
local function endBlock()
    local char, _, hum = getChar()
    if char and hum then
        char:SetAttribute("Blocking", false)
    end
    pcall(function() Router:FireServer("RequestBlockEnd") end)
    parry.blocking = false
end

local function parryKey(info, action)
    return info.name .. "|" .. tostring(action)
end

-- lead otomatis: latency remote + setengah parry window (0.17s)
local function parryLead()
    local lat = parry.latency or 0.1
    return math.clamp(lat * 2 + 0.085 + C.ParryLead, 0.1, 0.6)
end

-- ukur latency remote sekali di awal (block kosong tidak makan guard)
local function calibrateLatency()
    task.spawn(function()
        local samples = {}
        for _ = 1, 3 do
            local _, _, hum = getChar()
            if not hum or hum.Health <= 0 then break end
            local char = LP.Character
            local s0 = Workspace:GetServerTimeNow()
            pcall(function() Router:FireServer("RequestBlockStart") end)
            task.wait(0.16)
            local pwe = char:GetAttribute("ParryWindowEnd")
            pcall(function() Router:FireServer("RequestBlockEnd") end)
            if pwe and pwe > s0 then
                local l = pwe - s0 - 0.17
                if l >= 0 and l <= 0.35 then samples[#samples + 1] = l end
            end
            task.wait(0.9)
        end
        if #samples > 0 then
            local sum = 0
            for _, v in ipairs(samples) do sum = sum + v end
            parry.latency = sum / #samples
        end
    end)
end

-- Dash pakai Q (mekanik asli game: stamina + cooldown 1.2s)
local function doDash(hrp, attackerPos)
    local char = LP.Character
    if not (char and hrp) then return false end
    if os.clock() < dashReadyAt then return false end
    if char:GetAttribute("IsDashing") then return false end
    if char:GetAttribute("Blocking") then endBlock() end
    local away = Vector3.new(hrp.Position.X - attackerPos.X, 0, hrp.Position.Z - attackerPos.Z)
    if away.Magnitude < 0.1 then away = hrp.CFrame.LookVector end
    local side = hrp.CFrame.RightVector
    local dir = (away.Unit + Vector3.new(side.X, 0, side.Z) * 0.4)
    if dir.Magnitude < 0.1 then dir = away.Unit else dir = dir.Unit end
    hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + dir)
    dashReadyAt = os.clock() + 1.25
    dashHoldUntil = os.clock() + 0.55
    pcall(function()
        VIM:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
        task.delay(0.06, function()
            pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Q, false, game) end)
        end)
    end)
    hudState.state = "DASH"
    return true
end

local function refreshParry(hrp, hum)
    local sNow = Workspace:GetServerTimeNow()
    parry.nextImpact = nil
    parry.attacker = nil
    local nearestCulprit, nearestDist = nil, math.huge

    for _, info in ipairs(mobList()) do
        local dist = (info.root.Position - hrp.Position).Magnitude
        if dist <= C.ParryRange then
            local action = info.model:GetAttribute("Action")
            if action and not PARRY_ATTACK_ACTIONS_EXCLUDED[action] then
                local key = parryKey(info, action)
                local elapsed = sNow - (info.model:GetAttribute("ActionAt") or 0)
                -- boss umumnya windup lebih lama; default impact lebih besar
                local impact = parry.impact[key] or (info.boss and 1.05 or 0.62)
                local untilImpact = impact - elapsed
                if untilImpact > -0.35 and untilImpact < 1.6 then
                    if not parry.nextImpact or untilImpact < parry.nextImpact then
                        parry.nextImpact = untilImpact
                        parry.attacker = { info = info, elapsed = elapsed, key = key, untilImpact = untilImpact }
                    end
                    if elapsed > 0.05 and dist < nearestDist then
                        nearestCulprit, nearestDist = { info = info, elapsed = elapsed, key = key }, dist
                    end
                end
            end
        end
    end

    -- belajar timing impact per mob+serangan dari HP yang turun
    if parry.lastHP and hum.Health < parry.lastHP and nearestCulprit then
        local e = nearestCulprit.elapsed
        if e > 0.1 and e < 2.5 then
            local old = parry.impact[nearestCulprit.key] or parry.impact[nearestCulprit.info.name]
            parry.impact[nearestCulprit.key] = old and (old * 0.6 + e * 0.4) or e
        end
    end
    parry.lastHP = hum.Health
end

RunService.Heartbeat:Connect(function()
    if genObj.Value ~= MY_GEN then return end
    if not (C.AutoParry or C.AutoDash) then
        if parry.blocking then endBlock() end
        return
    end
    local char, hrp, hum = getChar()
    if not (char and hrp and hum and hum.Health > 0) then
        parry.blocking = false
        return
    end
    local now = os.clock()

    -- parry sukses: server set attribute ParryAt di karakter kita
    local pa = char:GetAttribute("ParryAt")
    if pa and pa ~= parry.lastSelfParryAt then
        parry.lastSelfParryAt = pa
        if math.abs(Workspace:GetServerTimeNow() - pa) < 1.5 then
            parry.successes = parry.successes + 1
            local att = parry.lastAttempt
            if att and now - att.at < 0.9 then att.success = true end
        end
    end

    if now - parry.scanAt >= 0.06 then
        parry.scanAt = now
        refreshParry(hrp, hum)
    end

    -- ukur latency remote dari ParryWindowEnd yang diset server
    local att = parry.lastAttempt
    if att and not att.measured and now - att.at >= 0.2 then
        att.measured = true
        local pwe = char:GetAttribute("ParryWindowEnd")
        if pwe and att.firedAt and pwe > att.firedAt then
            local l = pwe - att.firedAt - 0.17
            if l >= 0 and l <= 0.35 then
                parry.latency = parry.latency and (parry.latency * 0.7 + l * 0.3) or l
            end
        end
    end

    local ni = parry.nextImpact

    -- Auto Dash: hindari serangan boss / saat HP rendah
    if C.AutoDash and ni and ni <= 0.32 and ni >= -0.3 and parry.attacker then
        local hpPct = (hum.Health / math.max(hum.MaxHealth, 1)) * 100
        local wantDash = (C.DashBoss and parry.attacker.info.boss) or hpPct <= C.DashHP
        if wantDash and not char:GetAttribute("IsDashing") then
            if parry.blocking then endBlock() end
            if doDash(hrp, parry.attacker.info.root.Position) then
                return
            end
        end
    end

    if not C.AutoParry then
        if parry.blocking then endBlock() end
        return
    end

    if parry.blocking then
        if now >= parry.busyUntil then
            endBlock()
        end
        return
    end

    -- ParryCooldown game = 0.8s, BlockCooldown = 0.35s
    if now - parry.lastTry < 0.8 then return end
    if ni and parry.attacker then
        local key = parry.attacker.key
        if ni <= parryLead() and ni >= -0.1 then
            parry.blocking = true
            local boss = parry.attacker.info.boss
            -- boss: tahan block melewati impact (mitigasi), karena timing
            -- windup boss susah ditebak. Mob biasa juga sama.
            parry.busyUntil = now + math.max(0.3, ni + (boss and 0.5 or 0.25))
            parry.lastTry = now
            parry.attempts = parry.attempts + 1
            parry.lastAttempt = {
                key = key,
                at = now,
                success = false,
                holdUntil = parry.busyUntil,
                firedAt = Workspace:GetServerTimeNow(),
            }
            char:SetAttribute("Blocking", true)
            pcall(function() Router:FireServer("RequestBlockStart") end)
        end
    end
end)

-- ============================================================
-- UI
-- ============================================================
WindUI:SetNotificationLower(true)

local Window = WindUI:CreateWindow({
    Title = "FrostHollow [F1] — Auto Farm",
    Author = "WindUI · " .. LP.Name,
    Icon = "snowflake",
    Folder = "FrostHollowFarm",
    Size = UDim2.fromOffset(640, 500),
    Theme = "Dark",
    NewElements = true,
    HideSearchBar = true,
    ToggleKey = Enum.KeyCode.RightShift,
    OpenButton = {
        Title = "FrostHollow",
        Icon = "snowflake",
        Enabled = true,
        OnlyMobile = true,
        Draggable = true,
        CornerRadius = UDim.new(1, 0),
        Color = ColorSequence.new(Color3.fromHex("#7C5CFF"), Color3.fromHex("#3EC7FF")),
    },
})

-- ---------------------------------------------------------- Farm
local FarmTab = Window:Tab({ Title = "Farm", Icon = "swords" })

local FarmMain = FarmTab:Section({ Title = "Auto Farm", Box = true, BoxBorder = true })

FarmMain:Toggle({
    Title = "Auto Farm",
    Desc = "Teleport ke mob, pukul sampai mati, pindah target",
    Value = false,
    Callback = function(v)
        C.Farm = v
        if v then
            startFarm()
            notify("Auto Farm", "Aktif - target Lv " .. C.MinLevel .. "-" .. levelCap(), "play")
        else
            notify("Auto Farm", "Nonaktif", "pause")
        end
    end,
})

FarmMain:Toggle({
    Title = "Kill Aura",
    Desc = "Serang otomatis mob dalam radius 10 (tanpa teleport)",
    Value = false,
    Callback = function(v)
        C.Aura = v
        if v then startAura() end
    end,
})

FarmMain:Toggle({
    Title = "Auto Loot",
    Desc = "Ambil LootDrop sekitar saat farm/aura aktif",
    Value = true,
    Callback = function(v)
        C.AutoLoot = v
        if v then startLoot() end
    end,
})

FarmMain:Toggle({
    Title = "Auto Revive",
    Desc = "Langsung tekan revive saat mati",
    Value = true,
    Callback = function(v) C.AutoRevive = v end,
})

FarmMain:Toggle({
    Title = "Auto Mine (butuh Pickaxe)",
    Desc = "Hancurkan CrystalNode terdekat",
    Value = false,
    Callback = function(v)
        C.AutoMine = v
        if v then
            startMine()
            notify("Auto Mine", "Kalau belum punya Pickaxe, beli dulu di Blacksmith", "pickaxe")
        end
    end,
})

local FarmTarget = FarmTab:Section({ Title = "Target", Box = true, BoxBorder = true })

FarmTarget:Dropdown({
    Title = "Prioritas Target",
    Values = { "Nearest", "Lowest HP", "Highest Level" },
    Value = "Nearest",
    Callback = function(v) C.Priority = v end,
})

FarmTarget:Toggle({
    Title = "Ikut Serang Boss / King",
    Desc = "Boss punya HP besar dan damage tinggi",
    Value = false,
    Callback = function(v) C.IncludeBosses = v end,
})

local mobLabels, mobNameOf = buildMobOptions()

local mobDropdown = FarmTarget:Dropdown({
    Title = "Target Mob (kosong = semua)",
    Desc = "Pilih satu / lebih jenis mob yang mau dibunuh",
    Values = mobLabels,
    Multi = true,
    AllowNone = true,
    Callback = function(selected)
        local set = {}
        if type(selected) == "table" then
            for _, lbl in ipairs(selected) do
                local n = mobNameOf[lbl]
                if n then set[n] = true end
            end
        elseif type(selected) == "string" then
            local n = mobNameOf[selected]
            if n then set[n] = true end
        end
        C.MobFilter = set
        local count = 0
        for _ in pairs(set) do count = count + 1 end
        notify("Target Mob", count == 0 and "Semua jenis mob" or (count .. " jenis mob dipilih"), "crosshair")
    end,
})

FarmTarget:Button({
    Title = "Refresh Daftar Mob",
    Desc = "Scan ulang jenis mob yang ada di game",
    Icon = "refresh-cw",
    Callback = function()
        local labels, nameOf = buildMobOptions()
        mobLabels, mobNameOf = labels, nameOf
        pcall(function() mobDropdown:Refresh(labels) end)
        notify("Target Mob", #labels .. " jenis mob ditemukan", "crosshair")
    end,
})

FarmTarget:Slider({
    Title = "Level Minimum",
    Step = 1,
    Value = { Min = 1, Max = 100, Default = 1 },
    Callback = function(v) C.MinLevel = v end,
})

FarmTarget:Slider({
    Title = "Level Maksimum (0 = auto)",
    Desc = "Auto = level kamu + 2",
    Step = 1,
    Value = { Min = 0, Max = 100, Default = 0 },
    Callback = function(v) C.MaxLevel = v end,
})

FarmTarget:Slider({
    Title = "Jeda Pukulan (detik)",
    Step = 0.01,
    Value = { Min = 0.1, Max = 1, Default = 0.18 },
    Callback = function(v) C.SwingInterval = v end,
})

FarmTarget:Slider({
    Title = "Kabur kalau HP di bawah (%)",
    Step = 1,
    Value = { Min = 0, Max = 80, Default = 20 },
    Callback = function(v) C.RetreatHP = v end,
})

FarmTarget:Slider({
    Title = "Lanjut farm kalau HP sudah (%)",
    Desc = "Sambil nunggu regen di Town",
    Step = 1,
    Value = { Min = 30, Max = 100, Default = 65 },
    Callback = function(v) C.ResumeHP = v end,
})

FarmTarget:Slider({
    Title = "Radius Loot (stud)",
    Step = 10,
    Value = { Min = 50, Max = 2000, Default = 120 },
    Callback = function(v) C.LootRange = v end,
})

FarmTab:Button({
    Title = "Teleport ke Mob Terdekat",
    Desc = "Sekali jalan, tanpa mengaktifkan farm",
    Icon = "crosshair",
    Callback = function()
        local hrp = getHRP()
        if not hrp then return notify("Teleport", "Karakter belum hidup", "alert-triangle") end
        local best, bd
        for _, info in ipairs(mobList()) do
            if mobPass(info) then
                local d = (info.root.Position - hrp.Position).Magnitude
                if not bd or d < bd then best, bd = info, d end
            end
        end
        if not best then return notify("Teleport", "Tidak ada mob yang cocok", "alert-triangle") end
        teleportTo(best.root.Position + Vector3.new(0, 3, 4))
        notify("Teleport", string.format("%s Lv.%d (%dm)", best.name, best.lvl, bd), "map-pin")
    end,
})

-- ---------------------------------------------------------- Defense / Parry
local ParryTab = FarmTab:Section({ Title = "Defense", Box = true, BoxBorder = true })

ParryTab:Toggle({
    Title = "Auto Parry",
    Desc = "Block tepat sebelum serangan masuk (bonus XP + gold)",
    Value = true,
    Callback = function(v)
        C.AutoParry = v
        if not v then endBlock() end
        parry.lastSelfParryAt = nil
        if v and not parry.latency then calibrateLatency() end
        notify("Auto Parry", v and "Aktif" or "Nonaktif", "shield")
    end,
})

ParryTab:Slider({
    Title = "Offset Parry (0 = auto)",
    Desc = "Auto pakai latency terukur. Geser kalau masih sering meleset",
    Step = 0.01,
    Value = { Min = -0.15, Max = 0.25, Default = 0 },
    Callback = function(v) C.ParryLead = v end,
})

ParryTab:Slider({
    Title = "Parry Hold (detik)",
    Desc = "Lama menahan block",
    Step = 0.01,
    Value = { Min = 0.1, Max = 0.6, Default = 0.3 },
    Callback = function(v) C.ParryHold = v end,
})

ParryTab:Slider({
    Title = "Jarak Parry",
    Step = 1,
    Value = { Min = 5, Max = 30, Default = 16 },
    Callback = function(v) C.ParryRange = v end,
})

ParryTab:Toggle({
    Title = "Auto Dash (Q)",
    Desc = "Dodge pakai dash asli game (stamina + cooldown)",
    Value = true,
    Callback = function(v)
        C.AutoDash = v
        notify("Auto Dash", v and "Aktif" or "Nonaktif", "wind")
    end,
})

ParryTab:Slider({
    Title = "Dash kalau HP di bawah (%)",
    Step = 5,
    Value = { Min = 10, Max = 90, Default = 45 },
    Callback = function(v) C.DashHP = v end,
})

ParryTab:Toggle({
    Title = "Dash untuk serangan Boss",
    Desc = "Selalu dash saat boss menyerang, walau HP masih penuh",
    Value = true,
    Callback = function(v) C.DashBoss = v end,
})

ParryTab:Toggle({
    Title = "Boss Safe Mode",
    Desc = "Saat boss windup/serang, berhenti memukul (biar parry/dash kerja)",
    Value = true,
    Callback = function(v) C.BossSafe = v end,
})

ParryTab:Slider({
    Title = "Kabur dari Boss kalau HP (%)",
    Step = 5,
    Value = { Min = 10, Max = 90, Default = 50 },
    Callback = function(v) C.BossRetreatHP = v end,
})

ParryTab:Button({
    Title = "Kalibrasi Latency",
    Desc = "Ukur ulang latency remote buat timing parry",
    Icon = "gauge",
    Callback = function()
        parry.latency = nil
        calibrateLatency()
        notify("Auto Parry", "Kalibrasi latency...", "gauge")
    end,
})

ParryTab:Button({
    Title = "Reset Timing Belajar",
    Desc = "Hapus data impact + lead adaptif yang sudah dipelajari",
    Icon = "rotate-ccw",
    Callback = function()
        parry.impact = {}
        parry.latency = nil
        parry.lastAttempt = nil
        notify("Auto Parry", "Timing mob di-reset", "rotate-ccw")
    end,
})

-- ---------------------------------------------------------- Teleport
local TpTab = Window:Tab({ Title = "Teleport", Icon = "map-pinned" })

local TpWaypoints = TpTab:Section({ Title = "Waypoint", Box = true, BoxBorder = true })

local waypoints = { "Town", "Harbor", "Temple", "Mine", "Highlands", "Summit", "Forest", "MineLake" }
for _, name in ipairs(waypoints) do
    TpWaypoints:Button({
        Title = name,
        Icon = "map-pin",
        Callback = function()
            local p = checkpoint(name)
            if p then
                teleportTo(p + Vector3.new(0, 4, 0))
                notify("Waypoint", "Pindah ke " .. name, "map-pin")
            else
                notify("Waypoint", name .. " belum ditemukan", "alert-triangle")
            end
        end,
    })
end

local TpOther = TpTab:Section({ Title = "Lainnya", Box = true, BoxBorder = true })

TpOther:Button({
    Title = "Ke Quest Target",
    Desc = "Pakai posisi QuestTarget dari game",
    Icon = "flag",
    Callback = function()
        local t = LP:GetAttribute("QuestTarget")
        if typeof(t) == "Vector3" then
            teleportTo(t)
            local label = LP:GetAttribute("QuestTargetLabel")
            notify("Quest", tostring(label or "Target"), "flag")
        else
            notify("Quest", "Tidak ada quest aktif", "alert-triangle")
        end
    end,
})

TpOther:Button({
    Title = "Ke Crystal Terdekat",
    Icon = "gem",
    Callback = function()
        local hrp = getHRP()
        if not hrp then return end
        local best, bd
        for _, node in ipairs(crystalList()) do
            local root = node.model:FindFirstChild("Root") or node.model:FindFirstChild("Hitbox")
            if root then
                local d = (root.Position - hrp.Position).Magnitude
                if not bd or d < bd then best, bd = root, d end
            end
        end
        if best then
            teleportTo(best.Position + Vector3.new(0, 3, 4))
            notify("Crystal", "Menuju crystal terdekat", "gem")
        else
            notify("Crystal", "Tidak ada crystal hidup", "alert-triangle")
        end
    end,
})

TpOther:Button({
    Title = "Ke Loot Terdekat",
    Icon = "package",
    Callback = function()
        local hrp = getHRP()
        if not hrp then return end
        local best, bd
        for _, d in ipairs(dropList()) do
            local dist = (d.part.Position - hrp.Position).Magnitude
            if not bd or dist < bd then best, bd = d, dist end
        end
        if best then
            collectDrop(best)
            notify("Loot", tostring(best.label), "package")
        else
            notify("Loot", "Tidak ada drop", "alert-triangle")
        end
    end,
})

-- ---------------------------------------------------------- Movement
local MoveTab = Window:Tab({ Title = "Movement", Icon = "move" })

local MoveSec = MoveTab:Section({ Title = "Exploit Movement", Box = true, BoxBorder = true })

MoveSec:Toggle({
    Title = "Speed Hack",
    Desc = "Paksa WalkSpeed terus-menerus",
    Value = false,
    Callback = function(v) C.SpeedHack = v end,
})

MoveSec:Slider({
    Title = "WalkSpeed",
    Step = 1,
    Value = { Min = 16, Max = 200, Default = 30 },
    Callback = function(v) C.Speed = v end,
})

MoveSec:Toggle({
    Title = "Jump Boost",
    Value = false,
    Callback = function(v) C.JumpBoost = v end,
})

MoveSec:Slider({
    Title = "JumpPower",
    Step = 5,
    Value = { Min = 50, Max = 500, Default = 80 },
    Callback = function(v) C.Jump = v end,
})

MoveSec:Toggle({
    Title = "Fly (PC: WASD+Space · HP: joystick)",
    Value = false,
    Callback = function(v)
        C.Fly = v
        if v then
            startFly()
            notify("Fly", UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and "Aktif - geser joystick, lihat atas/bawah untuk naik-turun" or "Aktif - Space naik, LeftCtrl turun", "bird")
        else
            stopFly()
        end
    end,
})

MoveSec:Slider({
    Title = "Fly Speed",
    Step = 5,
    Value = { Min = 20, Max = 300, Default = 70 },
    Callback = function(v) C.FlySpeed = v end,
})

MoveSec:Toggle({
    Title = "Noclip",
    Desc = "Tembus dinding / terrain",
    Value = false,
    Callback = function(v)
        C.Noclip = v
        if not v then
            local char = LP.Character
            if char then
                for _, p in ipairs(char:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = true end
                end
            end
        end
    end,
})

MoveSec:Toggle({
    Title = "Infinite Jump",
    Value = false,
    Callback = function(v) C.InfJump = v end,
})

MoveSec:Toggle({
    Title = "Anti-AFK",
    Desc = "Cegah kick karena idle",
    Value = true,
    Callback = function(v)
        C.AntiAFK = v
        setAntiAFK(v)
    end,
})

-- ---------------------------------------------------------- Visuals
local VisTab = Window:Tab({ Title = "Visuals", Icon = "eye" })

local VisSec = VisTab:Section({ Title = "ESP (Drawing)", Box = true, BoxBorder = true })

VisSec:Toggle({
    Title = "ESP Mobs",
    Desc = "Nama, level, HP, jarak",
    Value = false,
    Callback = function(v) C.EspMobs = v end,
})

VisSec:Toggle({
    Title = "ESP Loot Drops",
    Value = false,
    Callback = function(v) C.EspDrops = v end,
})

VisSec:Toggle({
    Title = "ESP Crystal Nodes",
    Value = false,
    Callback = function(v) C.EspCrystals = v end,
})

VisSec:Toggle({
    Title = "ESP Players",
    Value = false,
    Callback = function(v) C.EspPlayers = v end,
})

VisSec:Slider({
    Title = "Jarak Maksimal ESP",
    Step = 25,
    Value = { Min = 50, Max = 1500, Default = 400 },
    Callback = function(v) C.EspDistance = v end,
})

-- ---------------------------------------------------------- Misc
local MiscTab = Window:Tab({ Title = "Misc", Icon = "wrench" })

local StatSec = MiscTab:Section({ Title = "Stat Points", Box = true, BoxBorder = true })

StatSec:Dropdown({
    Title = "Stat Tujuan",
    Values = { "Damage", "Health", "CritChance", "CritDamage" },
    Value = "Damage",
    Callback = function(v) StatChoice = v end,
})

StatSec:Button({
    Title = "Allocate Semua Poin",
    Desc = "Kirim semua StatPoints ke stat terpilih",
    Icon = "trending-up",
    Callback = function()
        local pts = LP:GetAttribute("StatPoints") or 0
        if pts <= 0 then
            return notify("Stat", "Tidak ada poin tersisa", "alert-triangle")
        end
        Router:FireServer("RequestAllocateStat", { Stat = StatChoice, Amount = pts })
        notify("Stat", string.format("%d poin -> %s", pts, StatChoice), "trending-up")
    end,
})

StatSec:Toggle({
    Title = "Auto Allocate",
    Desc = "Otomatis buang poin tiap kali dapat",
    Value = false,
    Callback = function(v)
        C.AutoStat = v
        if v then startAutoStat() end
    end,
})

local MiscActs = MiscTab:Section({ Title = "Aksi", Box = true, BoxBorder = true })

MiscActs:Button({
    Title = "Revive Sekarang",
    Icon = "heart-pulse",
    Callback = function() reviveNow() end,
})

MiscActs:Button({
    Title = "Teleport ke Town (selamat)",
    Icon = "house",
    Callback = function()
        local p = checkpoint("Town")
        if p then teleportTo(p + Vector3.new(0, 4, 0)) end
    end,
})

local InfoSec = MiscTab:Section({ Title = "Info", Box = true, BoxBorder = true })

InfoSec:Paragraph({
    Title = "Cara Pakai",
    Desc = "1) Aktifkan Auto Farm. 2) Atur Level Maks (0 = level kamu +2). 3) Pilih Target Mob kalau cuma mau jenis tertentu (kosong = semua). 4) Biarkan script teleport & mukul. 5) Auto Loot / Auto Parry ada di tab Farm. Tekan RightShift untuk buka/tutup menu.",
})

InfoSec:Paragraph({
    Title = "Boss",
    Desc = "Untuk boss: nyalakan 'Ikut Serang Boss/King', biarkan Boss Safe Mode + Auto Dash ON. Saat boss windup, script berhenti mukul, parry kalau timing pas, atau dash menjauh kalau HP di bawah batas / lawan boss. Kalau HP tembus Boss Retreat HP, script kabur ke Town dan nunggu regen.",
})

InfoSec:Paragraph({
    Title = "Peringatan",
    Desc = "Speed di atas ~60 dan fly bisa terlihat mencurigakan. Gunakan wajar. Script ini client-side; damage tetap dihitung server lewat Tool:Activate().",
})

InfoSec:Paragraph({
    Title = "Mobile",
    Desc = "Menu bisa dibuka lewat tombol melayang 'FrostHollow' (hanya tampil di mobile). Auto Farm, Auto Parry, Loot, Teleport, Revive, Speed, Jump, Noclip, Infinite Jump jalan di HP. Fly di HP: geser joystick, arahkan kamera ke atas/bawah untuk naik-turun. ESP butuh executor yang mendukung Drawing.",
})

-- ============================================================
-- Boot
-- ============================================================
-- watchdog revive (jalan walau Auto Farm mati)
task.spawn(function()
    while genObj.Value == MY_GEN do
        task.wait(1)
        if C.AutoRevive then
            local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if h and h.Health <= 0 then
                hudState.state = "DEAD"
                reviveNow()
                task.wait(3)
            end
        end
    end
end)

setAntiAFK(C.AntiAFK)
if C.AutoLoot then startLoot() end
if C.AutoParry then calibrateLatency() end

-- Akses cepat buat debug / dipanggil manual dari console
genv.FrostHollowFarm = {
    Config = C,
    StartFarm = startFarm,
    StartAura = startAura,
    StartLoot = startLoot,
    StartMine = startMine,
    Revive = reviveNow,
    Teleport = teleportTo,
    Checkpoint = checkpoint,
    CollectDrop = collectDrop,
    SetAntiAFK = setAntiAFK,
    Notify = notify,
    Parry = parry,
    Hud = hudState,
}

LP.CharacterAdded:Connect(function(char)
    task.wait(1)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        if C.SpeedHack then hum.WalkSpeed = C.Speed end
        if C.JumpBoost then hum.UseJumpPower = true; hum.JumpPower = C.Jump end
    end
    if C.Fly then
        task.wait(0.5)
        if C.Fly then startFly() end
    end
    tracker.model = nil
end)

notify("FrostHollow Auto Farm", "Loaded. Tekan RightShift untuk buka menu.", "snowflake")
print("[FrostHollow] Auto Farm loaded")

if STATE and STATE.onCleanup then
    STATE.onCleanup(function()
        C.Farm = false
        C.Aura = false
        C.AutoLoot = false
        C.AutoMine = false
        C.AutoStat = false
        C.AutoParry = false
        C.AutoDash = false
        pcall(endBlock)
        clearEsp()
        stopFly()
        if moveConn then moveConn:Disconnect() end
        if infJumpConn then infJumpConn:Disconnect() end
        if espConn then espConn:Disconnect() end
        setAntiAFK(false)
        pcall(function() Window:Destroy() end)
    end)
end
