---@class KickBox: Frame
---@field icon Texture
---@field border Texture
---@field pulseAnimation SimpleAnimGroup

---@class InterruptFrame: Frame
---@field kickBox KickBox
---@field nextKickBox KickBox

---@class SvtNameplate: Nameplate?
---@field interruptFrame InterruptFrame
---@field reflectIcon Frame

local addonName, NS = ...

-- Table to track active nameplate frames
---@type table<string, SvtNameplate>
local nameplateFrames = {}

-- Table to track party member data
---@class VeganData
---@field unitID string
---@field specId integer
---@field interruptSpellId integer
---@field reflectCooldown integer?
---@field spellAvailableTime table<integer, integer>?
---@type table<string, VeganData>
local veganPartyData = {}

local isTestModeActive = false
---@type SvtNameplate?
local testModeNameplate = nil

local parseResultFrame = nil
-- Add this new table
---@type table<string, string>
local playerAliases = {} -- Maps any character name to their "main" name

---@type table<string, boolean>
local priorityPlayers = {} -- Tracks players who need extra emphasis on their interrupts

-- Group definitions with markers and rotation
---@class StopAssignment
---@field player string
---@field spellId integer

---@class GroupAssignment
---@field name string
---@field markers string[]
---@field kicks string[]
---@field backups string[]
---@field stops StopAssignment[]

---@type GroupAssignment[]
local groups = {}

---@class NpcConfig
---@field castTime number -- Cast time of the npc's main spell
---@field cd number -- Minimum time between a successful cast and the next cast
---@field noStop boolean -- Mob is immune to stops
---@field group string? -- Only allow this group to be assigned to this npc
---@field bangroup string? -- Ban a group from being assigned to this npc
---@type table<string, NpcConfig>
local npcConfigs = {}

-- Enemy unit tracking
---@class KickAssignment
---@field unitId UnitToken
---@field type "kick" | "stop" | "backup"
---@field spellId integer
---@field isPrediction boolean?

---@class UnitState
---@field group GroupAssignment
---@field npcConfig NpcConfig
---@field isCasting boolean?
---@field earliestNextCast number?
---@field kickIndex integer
---@field nextKickerGuid string?
---@field stopIndex integer
---@field nextStopperGuid string?
---@field kickAssignment KickAssignment?
---@type table<string, UnitState>
local unitStates = {}

-- Assume 3 seconds for everybody
local lockoutDuration = 3

local function MakePulseAnimation(frame)
    local ag = frame:CreateAnimationGroup()
    ag:SetLooping("REPEAT")

    local bounceUp = ag:CreateAnimation("Scale")
    bounceUp:SetScale(1.3, 1.3)
    bounceUp:SetDuration(0.15)
    bounceUp:SetOrder(1)
    bounceUp:SetSmoothing("OUT")

    local bounceDown = ag:CreateAnimation("Scale")
    bounceDown:SetScale(0.95, 0.95)
    bounceDown:SetDuration(0.15)
    bounceDown:SetOrder(2)

    local settle = ag:CreateAnimation("Scale")
    settle:SetScale(1.0, 1.0)
    settle:SetDuration(0.2)
    settle:SetOrder(3)
    settle:SetSmoothing("OUT")

    return ag
end

local function AddBorderFrame(box, thickness)
    if box.borderFrame then return end
    local t = thickness or 2

    local bf = CreateFrame("Frame", nil, box, "BackdropTemplate")
    box.borderFrame = bf
    bf:SetFrameLevel(box:GetFrameLevel() + 5)
    bf:ClearAllPoints()
    bf:SetPoint("TOPLEFT",     box.icon, "TOPLEFT",     0,  0)
    bf:SetPoint("BOTTOMRIGHT", box.icon, "BOTTOMRIGHT", 0,  0)

    bf:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8", -- plain square
        edgeSize = t,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
end

local function SetBorderColor(box, r, g, b, a)
    if not box.borderFrame then return end
    box.borderFrame:SetBackdropBorderColor(r, g, b, a or 1)
end

local function SetBorderRed(box)
  SetBorderColor(box, 0.8, 0.0, 0.0, 1)
end

local function SetBorderYellow(box)
  SetBorderColor(box, 1.0, 0.8, 0.0, 1)
end

local function SetBorderGreen(box)
  SetBorderColor(box, 0.0, 0.6, 0.0, 1)
end

local function MakeKickBox(parent, iconSize, borderSize)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(iconSize, iconSize)

    box.icon = box:CreateTexture(nil, "ARTWORK")
    box.icon:SetAllPoints(box)

    AddBorderFrame(box, borderSize)
    SetBorderColor(box, 0, 0.8, 0, 1) -- green

    return box
end

local function CreateInterruptFrame(nameplate)
    if nameplate.interruptFrame then return end

    -- Right side: interrupt frame
    local interruptFrame = CreateFrame("Frame", nil, nameplate)
    nameplate.interruptFrame = interruptFrame
    interruptFrame:SetFrameStrata("TOOLTIP")
    interruptFrame:SetSize(50, 20)
    interruptFrame:SetPoint("LEFT", nameplate, "RIGHT", SecretVeganToolsDB.InterruptXOffset, 0)

    local kickBox = MakeKickBox(interruptFrame, 24, 2)
    kickBox:SetPoint("LEFT", interruptFrame, "LEFT", 0, 0)
    interruptFrame.kickBox = kickBox

    kickBox.pulseAnimation = MakePulseAnimation(kickBox)

    local nextKickBox = MakeKickBox(interruptFrame, 12, 1)
    interruptFrame.nextKickBox = nextKickBox
    nextKickBox:SetPoint("LEFT", kickBox, "RIGHT", 4, 0)
    nextKickBox.icon:SetTexture("Interface\\Icons\\inv_misc_questionmark")
end

local function CreateReflectFrame(nameplate)
    if nameplate.reflectIcon then return end

    local reflectIcon = CreateFrame("Frame", nil, nameplate)
    reflectIcon:SetFrameStrata("TOOLTIP")
    reflectIcon:SetSize(24, 24)
    reflectIcon:SetPoint("RIGHT", nameplate, "LEFT", SecretVeganToolsDB.ReflectXOffset, 0)
    reflectIcon.bg = reflectIcon:CreateTexture(nil, "BACKGROUND")
    reflectIcon.bg:SetAllPoints()
    reflectIcon.bg:SetTexture("Interface\\Icons\\ability_warrior_shieldreflection")
    reflectIcon.text = reflectIcon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reflectIcon.text:SetPoint("RIGHT", reflectIcon, "LEFT", -3, 0)
    reflectIcon.text:SetTextColor(1, 1, 1)
    reflectIcon.text:SetText("Reflect")
    reflectIcon:Hide()
    nameplate.reflectIcon = reflectIcon
end

---@param nameplate SvtNameplate
local function HideInterruptFrame(nameplate)
    if nameplate and nameplate.interruptFrame then nameplate.interruptFrame:Hide() end
end

---@param nameplate SvtNameplate
local function HideReflectFrame(nameplate)
    if nameplate and nameplate.reflectIcon then nameplate.reflectIcon:Hide() end
end

---@param nameplate SvtNameplate
local function HidePlateWidgets(nameplate)
    HideInterruptFrame(nameplate)
    HideReflectFrame(nameplate)
end

local function IsSpellReflectableAndReflectIsOffCD(caster, target, spellId)
    local veganData = veganPartyData[UnitGUID(target)]

    if veganData == nil then
        return false
    end

    local class, _, _ = UnitClass(target)
    if class == "Warrior" then
        if veganData.reflectCooldown ~= nil and veganData.reflectCooldown >= GetTime() then
            return false
        end

        return NS.g_ReflectionSpells[spellId] ~= nil
    end

    return false
end

---@return UnitToken?
local function GetUnitIDAndGuidInPartyOrSelfByName(name)
    -- Find the "main" name for the name listed in the note, falling back to the name itself.
    local noteMainName = playerAliases[name] or name

    -- Check self first
    local playerFullName = UnitName("player")
    local playerMainName = playerAliases[playerFullName] or playerFullName
    if playerMainName == noteMainName then
        return "player", UnitGUID("player")
    end

    -- Then check party members
    for i = 1, GetNumGroupMembers() do
        local unitId = "party" .. i
        if UnitExists(unitId) then
            local partyMemberFullName = select(1, UnitName(unitId))
            -- Find the "main" name for the actual player in the party.
            local partyMemberMainName = playerAliases[partyMemberFullName] or partyMemberFullName
            
            if partyMemberMainName == noteMainName then
                return unitId, UnitGUID(unitId)
            end
        end
    end

    return nil
end

---@param unitState UnitState
---@param castEndTime number
---@param prevAssignment KickAssignment?
---@return KickAssignment?
local function GetKickAssignment(unitState, castEndTime, prevAssignment)
    local function isSpellAvailable(unitGuid, spellId)
        local data = veganPartyData[unitGuid]
        if not data then return false end
        if not data.spellAvailableTime then data.spellAvailableTime = {} end
        if prevAssignment and prevAssignment.unitId == data.unitID and prevAssignment.spellId == spellId then return false end
        return not data.spellAvailableTime[spellId] or data.spellAvailableTime[spellId] <= castEndTime
    end

    local function isKickAvailable(unitGuid)
        local data = veganPartyData[unitGuid]
        if not data or not data.interruptSpellId then return false end
        return isSpellAvailable(unitGuid, data.interruptSpellId)
    end

    local kickRotation = unitState.group.kicks
    local stopRotation = unitState.group.stops
    local totalKicks = #kickRotation
    local totalStops = #stopRotation

    -- Try to find the next kick that is available, starting from current index
    for i = 0, totalKicks - 1 do
        local idx = (unitState.kickIndex + i - 1) % totalKicks + 1
        local kicker = kickRotation[idx]
        local unitId, unitGuid = GetUnitIDAndGuidInPartyOrSelfByName(kicker)

        if isKickAvailable(unitGuid) then
            local data = veganPartyData[unitGuid]
            if not prevAssignment then unitState.nextKickerGuid = unitGuid end
            return { unitId = unitId, type = "kick", spellId = data.interruptSpellId }
        end
    end

    -- Try backups
    for i = 1, #unitState.group.backups do
        local backup = unitState.group.backups[i]
        local unitId, unitGuid = GetUnitIDAndGuidInPartyOrSelfByName(backup)

        if isKickAvailable(unitGuid) then
            local data = veganPartyData[unitGuid]
            if not prevAssignment then unitState.nextKickerGuid = unitGuid end
            return { unitId = unitId, type = "backup", spellId = data.interruptSpellId }
        end
    end

    -- If no kicks available, try a stop from stopRotation
    if not unitState.npcConfig.noStop then
        for i = 0, totalStops - 1 do
            local idx = (unitState.stopIndex + i - 1) % totalStops + 1
            local stop = stopRotation[idx]
            local unitId, unitGuid = GetUnitIDAndGuidInPartyOrSelfByName(stop.player)

            if isSpellAvailable(unitGuid, stop.spellId) then
                if not prevAssignment then unitState.nextStopperGuid = unitGuid end
                return { unitId = unitId, type = "stop", spellId = stop.spellId }
            end
        end
    end

    -- No kick or stop available
    return nil
end

local function GetUnitIDInPartyOrSelfByGuid(guid)
    if UnitGUID("player") == guid then
        return "player"
    end
    for i = 1, GetNumGroupMembers() do
        if UnitExists("party" .. i) and UnitGUID("party" .. i) == guid then
            return "party" .. i
        end
    end
    return nil
end

local function IterateSelfAndPartyMembers()
    local i = 0
    return function()
        i = i + 1
        if i == 1 then
            return "player"
        elseif i <= GetNumGroupMembers() + 1 then
            return "party" .. (i - 1)
        end
    end
end

local function IsNamePlateFirstCastThatCanReflect(p_NamePlate, p_EndTime, p_TargetGUID)
    for unitID, nameplate in pairs(nameplateFrames) do
        local castName, _, _, startTime, endTime, _, _, notInterruptible, spellId = UnitCastingInfo(unitID)
        if castName ~= nil and spellId ~= nil and spellId > 0 and endTime ~= nil and UnitGUID(unitID.."-target") == p_TargetGUID then
            if GetTime() < endTime / 1000 then
                if endTime < p_EndTime then
                    return false
                end
            end
        end
    end

    return true
end

-- /dump _G.VMRT.Note.Text1
local function GetMRTNoteData()
    if _G.VMRT == nil then
        return nil
    end

    if _G.VMRT.Note == nil then
        return nil
    end

    local mrtText = _G.VMRT.Note.Text1
    return mrtText
end

local function SplitResponse(input, delimiter)
    local result = {}
    for match in (input .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

local function ParsePlayerName(coloredPlayerName)
    local playerName = string.match(coloredPlayerName, "|c%x%x%x%x%x%x%x%x(.-)|")
    return playerName
end

local function ParseSpellId(mrtSpell)
    local spellId = string.match(mrtSpell, "{spell:(%d+)}")
    if spellId then return tonumber(spellId) else return nil end
end

local function ParseMrtMark(mrtMark)
    return string.match(mrtMark, "^{(%w+)}$")
end

local raidTargetToMrtMark = {
    [1] = "star",
    [2] = "circle",
    [3] = "diamond",
    [4] = "triangle",
    [5] = "moon",
    [6] = "square",
    [7] = "cross",
    [8] = "skull",
}

local mrtMarkToRaidTarget = {
    star     = 1,
    circle   = 2,
    diamond  = 3,
    triangle = 4,
    moon     = 5,
    square   = 6,
    cross    = 7,
    skull    = 8,
}

local function ParseMRTNote()
    groups = {}
    npcConfigs = {}
    playerAliases = {}
    priorityPlayers = {} -- Reset priority players table

    local mrtText = GetMRTNoteData()

    if mrtText == nil then
        return
    end

    local lines = SplitResponse(mrtText, "\n")

    local foundStart = false
    for i = 1, #lines do
        local line = lines[i]
        if not foundStart then
            if string.lower(line) == "svtgroupstart" then
                foundStart = true
            end
        else
            if string.lower(line) == "svtgroupend" then
                break
            end
            local splitLine = SplitResponse(line, " ")
            local name = splitLine[1]
            local group = { name = name, markers = {}, kicks = {}, stops = {}, backups = {} }
            table.insert(groups, group)
            for j = 2, #splitLine do
                local part = splitLine[j]
                local mark = ParseMrtMark(part)
                if mark then
                    table.insert(group.markers, mark)
                else
                    local splitName = SplitResponse(part, "-")
                    local playerName = ParsePlayerName(splitName[1])
                    if playerName ~= nil then
                        if splitName[2] and string.lower(splitName[2]) == "backup" then
                            table.insert(group.backups, playerName)
                        else
                            local spellId = splitName[2] and ParseSpellId(splitName[2])
                            if spellId then
                                table.insert(group.stops, { player = playerName, spellId = spellId })
                            else
                                table.insert(group.kicks, playerName)
                            end
                        end
                    end
                end
            end
        end
    end

    foundStart = false
    for i = 1, #lines do
        local line = lines[i] 
        if not foundStart then
            if string.lower(line) == "svtnpcstart" then
                foundStart = true
            end
        else
            if string.lower(line) == "svtnpcend" then
                break
            end
            local splitLine = SplitResponse(line, " ")
            local npcId = tonumber(splitLine[1])
            if npcId then
                local npcConfig = { castTime = 2.5, cd = 1, noStop = false }
                npcConfigs[npcId] = npcConfig
                for j = 2, #splitLine do
                    local part = splitLine[j]
                    if part:sub(1, #"--") == "--" then break end
                    if string.lower(part) == "nostop" then
                        npcConfig.noStop = true
                    else
                        local split = SplitResponse(part, "-")
                        if #split > 1 then
                            if split[1] == "cast" then npcConfig.castTime = tonumber(split[2])
                            elseif split[1] == "cd" then npcConfig.cd = tonumber(split[2])
                            elseif split[1] == "group" then npcConfig.group = split[2]
                            elseif split[1] == "bangroup" then npcConfig.bangroup = split[2] end
                        end
                    end
                end
            end
        end
    end

    foundStart = false
    for i = 1, #lines do
        local line = lines[i] 
        if not foundStart then
            if string.lower(line) == "svtaliasstart" then
                foundStart = true
            end
        else
            if string.lower(line) == "svtaliasend" then
                break
            end
            if line ~= "" then
                local splitLine = SplitResponse(line, " ")
                local mainName = ParsePlayerName(splitLine[1])
                if mainName then
                    playerAliases[mainName] = mainName
                    for j = 2, #splitLine do
                        local altName = ParsePlayerName(splitLine[j])
                        if altName and altName ~= "" then playerAliases[altName] = mainName end
                    end
                end
            end
        end
    end

    foundStart = false
    for i = 1, #lines do
        local line = lines[i]
        local trimmedLine = line:gsub("^%s*(.-)%s*$", "%1")
        if not foundStart then
            if string.lower(trimmedLine) == "svtprioritystart" then
                foundStart = true
            end
        else
            if string.lower(trimmedLine) == "svtpriorityend" then
                break
            end
            if trimmedLine ~= "" then
                local splitLine = SplitResponse(trimmedLine, " ")
                for _, name in ipairs(splitLine) do
                    local plainName = ParsePlayerName(name) or name
                    local mainName = playerAliases[plainName] or plainName
                    if name ~= "" then
                        priorityPlayers[mainName] = true
                    end
                end
            end
        end
    end
end

local function TryParseMrt()
    local success, result = pcall(function() return ParseMRTNote() end)
    if not success then
        print("Missing or invalid MRT note data.")
        return
    end
end

local function HandleReflect(nameplate, castName, castID, spellId, unitID, startTime, endTime)
    if isTestModeActive and nameplate == testModeNameplate then return false, false end
    if castName == nil or spellId == nil or spellId <= 0 or endTime == nil then
        if nameplate.reflectIcon:IsShown() then
            nameplate.reflectIcon:Hide()
        end
        return false, false
    end

    if castID == nameplate.failedCastID then
        HidePlateWidgets(nameplate)
        return false, false
    end

    if GetTime() >= endTime / 1000 then
        HidePlateWidgets(nameplate)
        return false, false
    end

    local warrHasReflectAuraUp = false
    local canReflectIt = false

    local targetGuid = UnitGUID(unitID.."-target")
    if targetGuid ~= nil and UnitInParty(unitID.."-target") then
        local reflectInfo = veganPartyData[targetGuid]
        if UnitClass(unitID.."-target") == "Warrior" then
            if reflectInfo == nil then
                veganPartyData[targetGuid] = {}
                veganPartyData[targetGuid].unitID = GetUnitIDInPartyOrSelfByGuid(targetGuid)
                reflectInfo = veganPartyData[targetGuid]
            end
        end
        if NS.g_ReflectionSpells[spellId] ~= nil and IsNamePlateFirstCastThatCanReflect(nameplate, endTime, targetGuid) then
            if reflectInfo and reflectInfo.hasReflect and reflectInfo.reflectEndTime and reflectInfo.reflectEndTime > GetTime() then
                warrHasReflectAuraUp = true
            end

            local isReflectAvailable = IsSpellReflectableAndReflectIsOffCD(unitID, unitID.."-target", spellId)
            if not nameplate.reflectIcon:IsShown() and (isReflectAvailable or warrHasReflectAuraUp) then
                nameplate.reflectIcon:Show()
                canReflectIt = true
            elseif not isReflectAvailable and not warrHasReflectAuraUp then
                nameplate.reflectIcon:Hide()
            end

            if warrHasReflectAuraUp then
                nameplate.reflectIcon.text:SetText("Reflecting")

                if SecretVeganToolsDB.PlaySoundOnReflect then
                    if reflectInfo.reflectSoundAnnounce == nil or GetTime() > reflectInfo.reflectSoundAnnounce then
                        -- If the cooldown has expired, play the sound and set the new 10-second cooldown for this specific warrior.
                        C_VoiceChat.SpeakText(1, "Reflect", Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
                        reflectInfo.reflectSoundAnnounce = GetTime() + 10
                    end
                end
            end

        elseif nameplate.reflectIcon:IsShown() then
            nameplate.reflectIcon:Hide()
        end
    elseif nameplate.reflectIcon:IsShown() then
        nameplate.reflectIcon:Hide()
    end

    return warrHasReflectAuraUp, canReflectIt
end

function GetNpcConfig(unitGuid)
    local type, _, _, _, _, npcID = strsplit("-", unitGuid)
    if type ~= "Creature" then return nil end

    return npcConfigs[tonumber(npcID)]
end

---@param npcConfig NpcConfig
local function GetGroupForMarker(mrtMark, npcConfig)
    for i, group in ipairs(groups) do
        for j, mark in ipairs(group.markers) do
            if mark == mrtMark and (not npcConfig.group or npcConfig.group == group.name) and (not npcConfig.bangroup or npcConfig.bangroup ~= group.name) then
                return group
            end
        end
    end
    return nil
end

local function GetKickAssignmentTts(kickAssignment)
    if kickAssignment.type == "kick" then
        return "Kick"
    elseif kickAssignment.type == "backup" then
        return "Backup"
    elseif kickAssignment.type == "stop" then
        if kickAssignment.spellId == 408 then
            return "Kidney"
        elseif kickAssignment.spellId == 107570 then
            return "Stormbolt"
        elseif kickAssignment.spellId == 99 then
            return "Roar"
        elseif kickAssignment.spellId == 132469 then
            return "Typhoon"
        else
            return "Stop"
        end
    end
end

---@param kickBox KickBox
---@param kickAssignment KickAssignment?
---@param isCasting boolean
---@param warrHasReflectAuraUp boolean?
---@param isTargetPriority boolean?
local function ConfigureKickBox(kickBox, kickAssignment, isCasting, warrHasReflectAuraUp, isTargetPriority)
    if kickBox.pulseAnimation then
        kickBox.pulseAnimation:Stop()
        kickBox:SetScale(1.0) -- Reset scale and animation
    end

    kickBox.icon:SetAlpha(0.7)
    -- kickBox.border:SetAlpha(0.7)

    if not kickAssignment then
        kickBox.icon:SetTexture("Interface\\Icons\\inv_misc_questionmark")
        return
    end

    kickBox.icon:SetTexture(C_Spell.GetSpellTexture(kickAssignment.spellId))

    if isCasting then
        if kickAssignment.unitId == "player" and not warrHasReflectAuraUp then
            kickBox.icon:SetAlpha(1)
            SetBorderGreen(kickBox)
            if isTargetPriority then kickBox.pulseAnimation:Play() end
        else
            SetBorderRed(kickBox)
        end
    elseif not isCasting then
        if kickAssignment.unitId == "player" then
            SetBorderYellow(kickBox)
        else
            SetBorderRed(kickBox)
        end
    end
end

---@param unitId string
local function IsPriorityTarget(unitId)
    local targetGuid = UnitGUID(unitId .. "-target")
    if targetGuid then
        local targetData = veganPartyData[targetGuid]
        if targetData and targetData.unitID then
            local targetName = UnitName(targetData.unitID)
            if targetName then
                local mainName = playerAliases[targetName] or targetName
                if priorityPlayers[mainName] then
                    return true
                end
            end
        end
    end

    return false
end

---@param unitId string
---@param unitState UnitState
---@param nameplate SvtNameplate
local function HandleUnitSpellStart(unitId, unitState, nameplate)
    local raidTarget = GetRaidTargetIndex(unitId)
    local mrtMark = raidTargetToMrtMark[raidTarget]
    local castName, _, _, startTime, endTime, _, castID, notInterruptible, spellId = UnitCastingInfo(unitId)

    local warrHasReflectAuraUp, canReflectIt = HandleReflect(nameplate, castName, castID, spellId, unitId, startTime, endTime)
    local isTargetPriority = IsPriorityTarget(unitId)

    local kickAssignment = GetKickAssignment(unitState, endTime / 1000)
    unitState.kickAssignment = kickAssignment

    local nextKickAssignment = nil
    if kickAssignment then
        local nextEndTimeToUse = endTime / 1000 + lockoutDuration
        nextKickAssignment = GetKickAssignment(unitState, nextEndTimeToUse, kickAssignment)
    end

    ConfigureKickBox(nameplate.interruptFrame.kickBox, kickAssignment, true, warrHasReflectAuraUp, isTargetPriority)
    ConfigureKickBox(nameplate.interruptFrame.nextKickBox, nextKickAssignment, false, false, false)

    if not kickAssignment then
        nameplate.interruptFrame.kickBox.icon:SetTexture("Interface\\Icons\\inv_misc_questionmark")

        if not canReflectIt and SecretVeganToolsDB.PlaySoundOnInterruptTurn then
            if unitState.group and unitState.group.kicks then
                for i, kick in ipairs(unitState.group.kicks) do
                    local kickMainName = playerAliases[kick] or kick
                    if UnitName("player") == kickMainName then
                        C_VoiceChat.SpeakText(1, mrtMark .. " going off", Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
                        break
                    end
                end
            end
        end
        return
    end

    if kickAssignment.unitId == "player" and not warrHasReflectAuraUp then 
        local icon = C_Spell.GetSpellTexture(kickAssignment.spellId)
        nameplate.interruptFrame.kickBox.icon:SetTexture(icon)
        nameplate.interruptFrame.kickBox.icon:SetAlpha(1)
        SetBorderGreen(nameplate.interruptFrame.kickBox)

        if not canReflectIt and SecretVeganToolsDB.PlaySoundOnInterruptTurn then
            local tts = GetKickAssignmentTts(kickAssignment)
            C_VoiceChat.SpeakText(1, tts .. " " .. mrtMark, Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
        end 
    else
        nameplate.interruptFrame.kickBox.icon:SetAlpha(0.7)
        SetBorderRed(nameplate.interruptFrame.kickBox)
    end
end

---@param castTime number
---@param unitState UnitState
local function PredictCastEndTime(castTime, unitState)
    if unitState.earliestNextCast ~= nil and unitState.earliestNextCast > GetTime() then
        return unitState.earliestNextCast + castTime
    end

    return GetTime() + castTime
end

---@param unitId string
---@param unitState UnitState
---@param nameplate SvtNameplate
local function HandleUnitSpellEnd(unitId, unitState, nameplate)
    local endTimeToUse = PredictCastEndTime(unitState.npcConfig.castTime, unitState)

    local kickAssignment = GetKickAssignment(unitState, endTimeToUse)
    if kickAssignment then
        kickAssignment.isPrediction = true
    end

    local nextKickAssignment = nil
    if kickAssignment then
        local nextEndTimeToUse = endTimeToUse + unitState.npcConfig.castTime + lockoutDuration
        nextKickAssignment = GetKickAssignment(unitState, nextEndTimeToUse, kickAssignment)
    end

    unitState.kickAssignment = kickAssignment

    ConfigureKickBox(nameplate.interruptFrame.kickBox, kickAssignment, false, nil, false)

    if not kickAssignment then
        nameplate.interruptFrame.nextKickBox:Hide()
        return
    end

    nameplate.interruptFrame.nextKickBox:Show()
    ConfigureKickBox(nameplate.interruptFrame.nextKickBox, nextKickAssignment, false, nil, false)

    local icon = C_Spell.GetSpellTexture(kickAssignment.spellId)
    nameplate.interruptFrame.kickBox.icon:SetTexture(icon)
    nameplate.interruptFrame.kickBox.icon:SetAlpha(0.7)

    if kickAssignment.unitId == "player" then
        SetBorderYellow(nameplate.interruptFrame.kickBox)
    else
        SetBorderRed(nameplate.interruptFrame.kickBox)
    end
end

---@param nameplate SvtNameplate
local function UpdateUnit(unitId, nameplate)
    if isTestModeActive and nameplate == testModeNameplate then return end
    if not nameplate or not nameplate.interruptFrame then return end

    local castName, _, _, startTime, endTime, _, castID, notInterruptible, spellId = UnitCastingInfo(unitId)
    HandleReflect(nameplate, castName, castID, spellId, unitId, startTime, endTime)

    local unitGuid = UnitGUID(unitId)
    local unitState = unitStates[unitGuid]

    if not unitState then return end

    local isCasting = castName and not notInterruptible

    if not unitState.isCasting and isCasting then
        unitState.isCasting = true
        HandleUnitSpellStart(unitId, unitState, nameplate)
    elseif unitState.isCasting and not isCasting or not unitState.isCasting then
        unitState.isCasting = false
        HandleUnitSpellEnd(unitId, unitState, nameplate)
    end
end

local function UpdateAllUnits()
    for unitID, nameplate in pairs(nameplateFrames) do
        UpdateUnit(unitID, nameplate)
    end
end

---@param group GroupAssignment
local function EnsureGroupPartyData(group)
    local missing, seen = {}, {}

    local function ensureByName(name)
        local key = playerAliases[name] or name  -- canonical
        if seen[key] then return end
        local unitId, guid = GetUnitIDAndGuidInPartyOrSelfByName(key)
        if not unitId or not guid then
            seen[key] = true
            table.insert(missing, key)
        end
    end

    for _, n in ipairs(group.kicks)   do ensureByName(n) end
    for _, n in ipairs(group.backups) do ensureByName(n) end
    for _, s in ipairs(group.stops)   do ensureByName(s.player) end

    return #missing == 0, missing
end

---@param nameplate SvtNameplate
local function InitUnit(unitId, nameplate)
    if not nameplate then return end
    if isTestModeActive and nameplate == testModeNameplate then return end

    CreateReflectFrame(nameplate)

    local unitGuid = UnitGUID(unitId)

    if not unitGuid then
        HideInterruptFrame(nameplate)
        return
    end

    local raidTarget = GetRaidTargetIndex(unitId)
    local npcConfig = GetNpcConfig(unitGuid)

    if not raidTarget or not npcConfig then
        unitStates[unitGuid] = nil
        HideInterruptFrame(nameplate)
        return
    end

    local mrtMark = raidTargetToMrtMark[raidTarget]
    local intendedGroup = GetGroupForMarker(mrtMark, npcConfig)
    if not intendedGroup then
        unitStates[unitGuid] = nil
        HideInterruptFrame(nameplate)
        return
    end

    local ready, missing = EnsureGroupPartyData(intendedGroup)
    if SecretVeganToolsDB.RequireConfiguredMembersInParty and not ready then
        unitStates[unitGuid] = nil
        HideInterruptFrame(nameplate)
        print("SVT: waiting for party data for:", table.concat(missing, ", "))
        return
    end

    -- Unit is valid and has a group
    CreateInterruptFrame(nameplate)
    local unitState = unitStates[unitGuid]

    if not unitState or unitState.group.name ~= intendedGroup.name then
        -- init, or mark/group has changed
        unitState = { group = intendedGroup, npcConfig = npcConfig, kickIndex = 1, stopIndex = 1 }
        unitStates[unitGuid] = unitState
    end

    if SecretVeganToolsDB.ShowInterruptOrderFrameNameplates then
        nameplate.interruptFrame:Show()
    else
        nameplate.interruptFrame:Hide()
    end

    UpdateUnit(unitId, nameplate)
end

local function InitAllUnits()
    for unitID, nameplate in pairs(nameplateFrames) do
        InitUnit(unitID, nameplate)
    end
end

local function ReanchorAllNameplates()
    for _, nameplate in pairs(nameplateFrames) do
        if nameplate.interruptFrame then
            nameplate.interruptFrame:ClearAllPoints()
            nameplate.interruptFrame:SetPoint("LEFT", nameplate, "RIGHT", SecretVeganToolsDB.InterruptXOffset, 0)
        end
        if nameplate.reflectIcon then
            nameplate.reflectIcon:ClearAllPoints()
            nameplate.reflectIcon:SetPoint("RIGHT", nameplate, "LEFT", SecretVeganToolsDB.ReflectXOffset, 0)
        end
    end
end
NS.ReanchorAllNameplates = ReanchorAllNameplates

local SPEC_REQ = "REQSPECINFO"
local SPEC_RESP = "SPECINFORESPONSE"
local requestLock = false

local STATE_REQ = "STATEREQ" -- STATEREQ|<guid>|
local STATE_PUSH = "STATEPUSH" -- STATEPUSH|<guid>|<kickIndex>|<stopIndex>
local statePushCooldownByGuid = {}

local function SendAndRequestInitialData()
    if requestLock then return end
    requestLock = true

    C_Timer.After(1.0, function()
        local myGuid = UnitGUID("player")
        if not veganPartyData[myGuid] then
            veganPartyData[myGuid] = {} -- initalize player data
        end
        veganPartyData[myGuid].unitID = "player"
        veganPartyData[myGuid].spellAvailableTime = {}

        local currentSpec = GetSpecialization()
        if currentSpec then
            local specId, currentSpecName = GetSpecializationInfo(currentSpec)
            if specId ~= nil then
                C_ChatInfo.SendAddonMessage("SVTG1", SPEC_REQ .. "|", "PARTY")
                C_ChatInfo.SendAddonMessage("SVTG1", SPEC_RESP .. "|" .. specId .. "|" .. myGuid .. "|", "PARTY")

                if NS.interruptSpecInfoTable[specId] ~= nil then
                    local specData = NS.interruptSpecInfoTable[specId]
                    veganPartyData[myGuid].specId = specId
                    veganPartyData[myGuid].interruptSpellId = specData.InterruptSpell
                end
            end
        end

        requestLock = false
    end)
end

-- Request unit state from party members if ours has default kick and stop index
-- This is done to ensure that if we join a fight late, or if we lose and regain the nameplate, we have the correct state
local function SendStateRequestIfDefaultState(guid)
    local unitState = unitStates[guid]
    if not unitState then return end
    if unitState.kickIndex ~= 1 and unitState.stopIndex ~= 1 then return end

    C_ChatInfo.SendAddonMessage("SVTG1", STATE_REQ .. "|" .. guid .. "|", "PARTY")
end

-- Only respond if kick or stop index has changed from default values
local function SendStatePushIfChangedState(guid)
    local unitState = unitStates[guid]
    if not unitState then return end
    if unitState.kickIndex == 1 and unitState.stopIndex == 1 then return end

    local now = GetTime()
    local nextOk = statePushCooldownByGuid[guid] or 0
    if now < nextOk then return end
    statePushCooldownByGuid[guid] = now + 0.5

    local msg = table.concat({
        STATE_PUSH,
        guid,
        unitState.kickIndex,
        unitState.stopIndex,
    }, "|").."|"

    C_ChatInfo.SendAddonMessage("SVTG1", msg, "PARTY")
end

local function HideTestFrame()
    if testModeNameplate and testModeNameplate.interruptFrame then
        HidePlateWidgets(testModeNameplate)
    end
    testModeNameplate = nil
end

local function ShowTestFrame(nameplate)
    HideTestFrame()
    testModeNameplate = nameplate

    CreateInterruptFrame(nameplate)
    CreateReflectFrame(nameplate)

    local fakeKick = { unitId = "player", type = "kick", spellId = 6552 } -- Pummel
    local fakeNextKick = { unitId = "party1", type = "stop", spellId = 408 } -- Kidney Shot

    ConfigureKickBox(nameplate.interruptFrame.kickBox, fakeKick, false)
    ConfigureKickBox(nameplate.interruptFrame.nextKickBox, fakeNextKick, false)

    -- Make sure everything is visible
    nameplate.interruptFrame:Show()
    nameplate.reflectIcon.text:SetText("Reflect")
    nameplate.reflectIcon:Show()
end

local function ToggleTestMode()
    isTestModeActive = not isTestModeActive

    if not isTestModeActive then
        HideTestFrame()
        print("SVT Test Mode: |cffff0000Disabled|r.")
        return
    end

    if not UnitExists("target") or not UnitCanAttack("player", "target") then
        print("SVT Error: You must have an enemy targeted to use test mode.")
        isTestModeActive = false
        return
    end

    local nameplate = C_NamePlate.GetNamePlateForUnit("target")
    if not nameplate then
        print("SVT Error: Target's nameplate is not visible.")
        isTestModeActive = false
        return
    end

    ShowTestFrame(nameplate)
    print("SVT Test Mode: |cff00ff00Enabled|r. Run |cffffd100/svt test|r again to disable.")
end

local function padRight(str, length)
    local n = length - #str
    if n > 0 then
        return str .. string.rep(" ", n * 2)
    else
        return str:sub(1, length)  -- truncate if longer
    end
end

local function RaidIcon(id)
    local size = 14
    local tex = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
    -- Atlas layout (64x64 each on a 256x256 sheet)
    local coords = {
        [1] = {0,   0.25, 0,    0.25}, -- star
        [2] = {0.25,0.50, 0,    0.25}, -- circle
        [3] = {0.50,0.75, 0,    0.25}, -- diamond
        [4] = {0.75,1.00, 0,    0.25}, -- triangle
        [5] = {0,   0.25, 0.25, 0.50}, -- moon
        [6] = {0.25,0.50, 0.25, 0.50}, -- square
        [7] = {0.50,0.75, 0.25, 0.50}, -- cross
        [8] = {0.75,1.00, 0.25, 0.50}, -- skull
    }
    local c = coords[id]
    if not c then return "" end
    return ("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t"):format(
        tex, size, size,
        c[1]*256, c[2]*256, c[3]*256, c[4]*256
    )
end

local function markersToRaidTags(markers)
    local out = {}
    for _, name in ipairs(markers) do
        table.insert(out, RaidIcon(mrtMarkToRaidTarget[name]))
    end
    return table.concat(out, " ")
end

local function FormatParseResults()
    local t = {} -- Use a table for efficient string building

    -- Aliases Section
    table.insert(t, "|cffffff00--- Player Aliases ---|r")
    if next(playerAliases) == nil then
        table.insert(t, "  No aliases found.")
    else
        for character, main in pairs(playerAliases) do
            table.insert(t, padRight(character, 12) .. " -> " .. main)
        end
    end

    -- Priority Players Section
    table.insert(t, "\n\n|cffffff00--- Priority Players ---|r")
    if not next(priorityPlayers) then
        table.insert(t, "  No priority players defined.")
    else
        local priorityList = {}
        for player, _ in pairs(priorityPlayers) do
            table.insert(priorityList, player)
        end
        table.insert(t, "  " .. table.concat(priorityList, ", "))
    end

    -- Groups Section
    table.insert(t, "\n\n|cffffff00--- Interrupt Groups ---|r")
    if #groups == 0 then
        table.insert(t, "  No groups found.")
    else
        for _, group in ipairs(groups) do
            table.insert(t, "\n|cff00ccffGroup:|r " .. group.name)
            table.insert(t, "  |cffaaaaaaMarkers:|r " .. markersToRaidTags(group.markers))
            table.insert(t, "  |cffaaaaaaKicks:|r " .. table.concat(group.kicks, ", "))
            table.insert(t, "  |cffaaaaaaBackups:|r " .. (#group.backups > 0 and table.concat(group.backups, ", ") or "None"))
            local stops = {}
            for _, stopInfo in ipairs(group.stops) do
                local stopSpellInfo = C_Spell.GetSpellInfo(stopInfo.spellId)
                table.insert(stops, stopInfo.player .. " |T" .. stopSpellInfo.iconID .. ":16:16|t")
            end
            table.insert(t, "  |cffaaaaaaStops:|r " .. (#stops > 0 and table.concat(stops, ", ") or "None"))
        end
    end

    -- NPCs Section
    table.insert(t, "\n\n|cffffff00--- NPC Configs ---|r")
    if next(npcConfigs) == nil then
        table.insert(t, "  No NPC configs found.")
    else
        for npcId, config in pairs(npcConfigs) do
            local details = string.format("cast: %.1fs, cd: %.1fs, noStop: %s", config.castTime, config.cd, tostring(config.noStop))
            if config.group then details = details .. ", group: " .. config.group end
            if config.bangroup then details = details .. ", bangroup: " .. config.bangroup end
            table.insert(t, string.format("\n|cff00ccffNPC ID:|r %d", npcId))
            table.insert(t, "  " .. details)
        end
    end

    return table.concat(t, "\n")
end

local function CreateParseResultWindow()
    -- Main Window Frame
    local frame = CreateFrame("Frame", "SVTParseResultFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- *** FIX START ***
    -- The old line was unreliable. This directly accesses the TitleText created by the template.
    frame.TitleText:SetText("SVT MRT Parse Results")
    -- *** FIX END ***

    -- Scroll Frame for Content
    local scrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 8)

    -- Scroll Child (holds the text)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(550, 1) -- Width is fixed, height is dynamic
    scrollFrame:SetScrollChild(scrollChild)

    -- The Font String that displays the text
    local text = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    text:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -10)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWidth(530) -- Width minus some padding

    -- Store text object for easy access
    frame.text = text
    return frame
end

local function ToggleParseResultWindow()
    if not parseResultFrame then
        parseResultFrame = CreateParseResultWindow()
        parseResultFrame:Hide()
    end

    if parseResultFrame:IsShown() then
        parseResultFrame:Hide()
    else
        TryParseMrt() -- Re-parse the note to ensure data is fresh
        local formattedText = FormatParseResults()
        parseResultFrame.text:SetText(formattedText)
        parseResultFrame:Show()
    end
end

local lastTimeByGuid = {}

local function LogTime(prefix, currentTime, guid)
    local last = lastTimeByGuid[guid] or currentTime
    print(string.format("%s [%s] diff: %.2f", prefix, guid or "?", currentTime - last))
    lastTimeByGuid[guid] = currentTime
end

local function EventHandler(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subevent = CombatLogGetCurrentEventInfo()
        local sourceGUID = select(4, CombatLogGetCurrentEventInfo())
        local destGUID = select(8, CombatLogGetCurrentEventInfo())

        -- local isConfigured = false
        -- if sourceGUID then
        --     local type, _, _, _, _, npcID = strsplit("-", sourceGUID)
        --     if type == "Creature" and npcConfigs[tonumber(npcID)] then
        --         isConfigured = true
        --     end
        -- end

        -- if isConfigured then
        --     local spellID = select(12, CombatLogGetCurrentEventInfo())
        --     if subevent == "SPELL_CAST_START"   then LogTime("start:"..spellID,   timestamp, sourceGUID) end
        --     if subevent == "SPELL_CAST_SUCCESS" then LogTime("success:"..spellID, timestamp, sourceGUID) end
        -- end

        if subevent == "SPELL_CAST_SUCCESS" then
            local spellID = select(12, CombatLogGetCurrentEventInfo())
            local veganData = veganPartyData[sourceGUID]
            if veganData then
                if spellID == 23920 then
                    veganData.reflectCooldown = GetTime() + 25
                else
                    local cooldown = GetSpellBaseCooldown(spellID) / 1000
                    if not veganData.spellAvailableTime then veganData.spellAvailableTime = {} end
                    veganData.spellAvailableTime[spellID] = GetTime() + cooldown
                end
            end

            local unitState = unitStates[sourceGUID]
            if unitState then
                unitState.earliestNextCast = GetTime() + unitState.npcConfig.cd
            end
        elseif subevent == "SPELL_INTERRUPT" then
            -- LogTime("interrupt", timestamp)
            local unitState = unitStates[destGUID]
            if unitState and unitState.nextKickerGuid == sourceGUID then
                unitState.nextKickerGuid = nil
                unitState.kickIndex = unitState.kickIndex + 1

                local timeBetweenCasts = math.max(lockoutDuration, unitState.npcConfig.cd)
                unitState.earliestNextCast = GetTime() + timeBetweenCasts
            end
        end

        if (subevent == "SPELL_CAST_START" or
            subevent == "SPELL_CAST_SUCCESS" or
            subevent == "SPELL_INTERRUPT" or
            subevent == "SPELL_AURA_APPLIED") then
            UpdateAllUnits()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Clean up partyCooldowns table for missing members
        for unit in IterateSelfAndPartyMembers() do
            if UnitExists(unit) then
                local guid = UnitGUID(unit)
                if not veganPartyData[guid] then
                    veganPartyData[guid] = {}
                    veganPartyData[guid].unitID = unit
                end
            end
        end

        -- cleanup any veganData that is not in the party
        for guid, veganData in pairs(veganPartyData) do
            local unitId = GetUnitIDInPartyOrSelfByGuid(guid)
            if unitId == nil then
                veganPartyData[guid] = nil
            end
        end

        -- refresh data
        SendAndRequestInitialData()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unitID = ...
        ---@type SvtNameplate
        local nameplate = C_NamePlate.GetNamePlateForUnit(unitID)
        if not nameplate then return end

        nameplateFrames[unitID] = nameplate
        InitUnit(unitID, nameplate)

        local guid = UnitGUID(unitID)
        SendStateRequestIfDefaultState(guid)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unitID = ...
        local nameplate = nameplateFrames[unitID]

        if nameplate then
            HidePlateWidgets(nameplate)
            nameplateFrames[unitID] = nil
        end

        local guid = UnitGUID(unitID)
        if guid then unitStates[guid] = nil end

        if nameplate and testModeNameplate == nameplate then
            HideTestFrame()
            isTestModeActive = false
            print("SVT Test Mode: |cffff0000Disabled|r (target lost).")
        end
    elseif event == "RAID_TARGET_UPDATE" then
        InitAllUnits()
    elseif event == "UNIT_AURA" then
        local unit, info = ...
        local guid = UnitGUID(unit)
        if veganPartyData[guid] == nil then
            return
        end
        if info.addedAuras then
            for _, v in pairs(info.addedAuras) do
                if v.spellId == 23920 then
                    veganPartyData[guid].reflectAuraInstanceId = v.auraInstanceID
                    veganPartyData[guid].hasReflect = true
                    veganPartyData[guid].reflectEndTime = v.expirationTime
                end
            end
        end
        if info.removedAuraInstanceIDs and veganPartyData[guid]  then
            for _, v in pairs(info.removedAuraInstanceIDs) do
                if veganPartyData[guid].reflectAuraInstanceId == v then
                    veganPartyData[guid].hasReflect = false
                    veganPartyData[guid].reflectEndTime = nil
                end
            end
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == "SVTG1" then
            local msgBuffer = SplitResponse(message, "|")
            local msgType = msgBuffer[1]
            if msgType == SPEC_REQ then
                local currentSpec = GetSpecialization()
                if currentSpec then
                    local specId, currentSpecName = GetSpecializationInfo(currentSpec)
                    local msg = SPEC_RESP .. "|" .. specId .. "|" .. UnitGUID("player") .. "|"
                    C_ChatInfo.SendAddonMessage("SVTG1", msg, "PARTY")
                end
            elseif msgType == SPEC_RESP then
                local specId = tonumber(msgBuffer[2])
                local guid = msgBuffer[3]

                if veganPartyData[guid] == nil then
                    veganPartyData[guid] = {}
                    veganPartyData[guid].unitID = GetUnitIDInPartyOrSelfByGuid(guid)
                end

                veganPartyData[guid].specId = specId

                if NS.interruptSpecInfoTable[specId] ~= nil then
                    local specData = NS.interruptSpecInfoTable[specId]
                    veganPartyData[guid].interruptSpellId = specData.InterruptSpell
                end
            elseif msgType == STATE_REQ then
                local guid = msgBuffer[2]
                SendStatePushIfChangedState(guid)
            elseif msgType == STATE_PUSH then
                local guid = msgBuffer[2]
                local kickIndex = tonumber(msgBuffer[3])
                local stopIndex = tonumber(msgBuffer[4])

                local unitState = unitStates[guid]
                if not unitState then return end

                if kickIndex then unitState.kickIndex = kickIndex end
                if stopIndex then unitState.stopIndex = stopIndex end

                UpdateAllUnits()
            end
        end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        SendAndRequestInitialData()
    elseif event == "GROUP_JOINED" then
        SendAndRequestInitialData()
    elseif event == "PLAYER_REGEN_DISABLED" then
        TryParseMrt()
    end
end

local function InitAddon()
    print("SecretVeganTools loaded")
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("GROUP_JOINED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("RAID_TARGET_UPDATE")
    frame:SetScript("OnEvent", EventHandler)

    SendAndRequestInitialData()
    TryParseMrt()
end

local function ShouldInitAddon()
    return true
    -- local inInstance = IsInInstance()
    -- if not inInstance then return false end
-- 
    -- local _, _, difficultyID = GetInstanceInfo()
    -- 1 = Normal, 2 = Heroic, 8 = Mythic+, 23 = Mythic
    -- return difficultyID == 1 or difficultyID == 2 or difficultyID == 8 or difficultyID == 23
end

local addonInitialized = false
local startup = CreateFrame("Frame")
startup:RegisterEvent("ADDON_LOADED")
startup:RegisterEvent("PLAYER_ENTERING_WORLD")
startup:RegisterEvent("ZONE_CHANGED_NEW_AREA")
startup:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" and ... == "SecretVeganTools" then
        if not SecretVeganToolsDB then
            SecretVeganToolsDB = {}
        end

        C_ChatInfo.RegisterAddonMessagePrefix("SVTG1");
        NS.InitAddonSettings()
    elseif event == "PLAYER_ENTERING_WORLD"  or event == "ZONE_CHANGED_NEW_AREA" then
        if not ShouldInitAddon() then return false end

        if not addonInitialized then
            addonInitialized = true
            InitAddon()
        end
    end
end)

SLASH_SECRETVEGANTOOLS1 = "/svt"
SlashCmdList["SECRETVEGANTOOLS"] = function(msg)
    local command = msg and string.lower(msg) or ""
    if command == "reload" then
        print("SVT: Reloading MRT note...")
        TryParseMrt()
        InitAllUnits()
    elseif command == "config" then
        Settings.OpenToCategory(NS.SettingsCategoryID)
    elseif command == "test" then
        ToggleTestMode()
    elseif command == "parse" then
        ToggleParseResultWindow()
    else
        print("SVT Commands: /svt reload, /svt test, /svt parse, /svt config")
    end
end
