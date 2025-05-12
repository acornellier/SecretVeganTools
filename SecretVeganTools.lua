---@class KickBox: Frame
---@field icon Texture
---@field border Texture

---@class InterruptFrame: Frame
---@field reflectIcon Frame
---@field kickBox KickBox
---@field nextKickBox KickBox

---@class SvtNameplate: Nameplate?
---@field interruptFrame InterruptFrame
---@field lastCastDuration number
---@field endLockoutTime number

local addonName, NS = ...

-- Table to track active nameplate frames
---@type table<string, SvtNameplate>
local nameplateFrames = {}

-- Table to track party member data
---@class VeganData
---@field unitID string
---@field specId integer
---@field interruptSpellId integer
---@field lockoutDuration integer
---@field reflectCooldown integer?
---@field spellAvailableTime table<integer, integer>?
---@type table<string, VeganData>
local veganPartyData = {}

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
---@field noStop boolean
---@field group string?
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
---@field kickIndex integer
---@field nextKickerGuid string?
---@field stopIndex integer
---@field nextStopperGuid string?
---@field kickAssignment KickAssignment?
---@type table<string, UnitState>
local unitStates = {}

-- Function to create interrupt display
local function CreateInterruptAnchor(nameplate)
    if nameplate.interruptFrame then return end

    -- Create a frame to display interrupt status
    local interruptFrame = CreateFrame("Frame", nil, nameplate)
    nameplate.interruptFrame = interruptFrame
    interruptFrame:SetSize(50, 20)
    interruptFrame:SetPoint("TOP", nameplate, "TOP", 0, 20)

    local kickBox = CreateFrame("Frame", nil, interruptFrame)
    interruptFrame.kickBox = kickBox

    local iconSize = 32
    local borderSize = 3
    kickBox:SetSize(iconSize + 2 * borderSize, iconSize + 2 * borderSize)
    kickBox:SetPoint("CENTER", interruptFrame, "CENTER", 0, 0)

    kickBox.border = kickBox:CreateTexture(nil, "BACKGROUND")
    kickBox.border:SetColorTexture(1, 1, 0, 1)
    kickBox.border:SetAllPoints(kickBox)

    kickBox.icon = kickBox:CreateTexture(nil, "ARTWORK")
    kickBox.icon:SetPoint("TOPLEFT", kickBox, "TOPLEFT", borderSize, -borderSize)
    kickBox.icon:SetPoint("BOTTOMRIGHT", kickBox, "BOTTOMRIGHT", -borderSize, borderSize)

    local nextKickBox = CreateFrame("Frame", nil, interruptFrame)
    interruptFrame.nextKickBox = nextKickBox

    local nextIconSize = 16
    local nextBorderSize = 1.5
    nextKickBox:SetSize(nextIconSize + 2 * nextBorderSize, nextIconSize + 2 * nextBorderSize)
    nextKickBox:SetPoint("TOP", interruptFrame, "CENTER", iconSize, 0)

    nextKickBox.border = nextKickBox:CreateTexture(nil, "BACKGROUND")
    nextKickBox.border:SetColorTexture(1, 1, 0, 1)
    nextKickBox.border:SetAllPoints(nextKickBox)

    nextKickBox.icon = nextKickBox:CreateTexture(nil, "ARTWORK")
    nextKickBox.icon:SetPoint("TOPLEFT", nextKickBox, "TOPLEFT", nextBorderSize, -nextBorderSize)
    nextKickBox.icon:SetPoint("BOTTOMRIGHT", nextKickBox, "BOTTOMRIGHT", -nextBorderSize, nextBorderSize)
    nextKickBox.icon:SetTexture("Interface\\Icons\\inv_misc_questionmark")

    local reflectIcon = CreateFrame("Frame", nil, interruptFrame)
    reflectIcon:SetSize(30, 30)
    reflectIcon:SetPoint("RIGHT", interruptFrame, "LEFT", -10, 0)
    reflectIcon.bg = reflectIcon:CreateTexture(nil, "BACKGROUND")
    reflectIcon.bg:SetAllPoints()
    reflectIcon.bg:SetTexture("Interface\\Icons\\ability_warrior_shieldreflection")
    reflectIcon.text = reflectIcon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reflectIcon.text:SetPoint("RIGHT", reflectIcon, "LEFT", -3, 0)
    reflectIcon.text:SetTextColor(1, 1, 1)
    reflectIcon.text:SetText("Reflect")
    reflectIcon:Hide()
    interruptFrame.reflectIcon = reflectIcon
end

-- Function that returns a colored unit name based on class
local function GetColoredUnitClassAndName(unit)
    -- Get the unit's class and name
    local unitName = UnitName(unit)
    local _, class = UnitClass(unit)

    if not unitName or not class then
        return ""
    end

    local classColor = RAID_CLASS_COLORS[class]
    if classColor then
        local colorCode = string.format("|cff%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
        return colorCode .. unitName .. "|r"
    else
        return unitName
    end
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
    if UnitName("player") == name then
        return "player", UnitGUID("player")
    end
    for i = 1, GetNumGroupMembers() do
        if UnitExists("party" .. i) and select(1, UnitName("party" .. i)) == name then
            return "party" .. i, UnitGUID("party" .. i)
        end
    end
    return nil
end

---@param unitState UnitState
---@param castEndTime number
---@param skipAssignment KickAssignment?
---@return KickAssignment?
local function GetKickAssignment(unitState, castEndTime, skipAssignment)
    local function isSpellAvailable(unitGuid, spellId)
        local data = veganPartyData[unitGuid]
        if not data then return false end
        if not data.spellAvailableTime then data.spellAvailableTime = {} end
        if skipAssignment and skipAssignment.unitId == data.unitID and skipAssignment.spellId == spellId then return false end
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
            unitState.nextKickerGuid = unitGuid
            return { unitId = unitId, type = "kick", spellId = data.interruptSpellId }
        end
    end

    -- If no kicks available, try a stop from stopRotation
    if not unitState.npcConfig.noStop then
        for i = 0, totalStops - 1 do
            local idx = (unitState.stopIndex + i - 1) % totalStops + 1
            local stop = stopRotation[idx]
            local unitId, unitGuid = GetUnitIDAndGuidInPartyOrSelfByName(stop.player)

            if isSpellAvailable(unitGuid, stop.spellId) then
                unitState.nextStopperGuid = unitGuid
                return { unitId = unitId, type = "stop", spellId = stop.spellId }
            end
        end
    end

    -- Try backups
    for i = 1, #unitState.group.backups do
        local backup = unitState.group.backups[i]
        local unitId, unitGuid = GetUnitIDAndGuidInPartyOrSelfByName(backup)

        if isKickAvailable(unitGuid) then
            local data = veganPartyData[unitGuid]
            unitState.nextKickerGuid = unitGuid
            return { unitId = unitId, type = "backup", spellId = data.interruptSpellId }
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
    [3] = "purple",
    [4] = "green",
    [5] = "moon",
    [6] = "square",
    [7] = "cross",
    [8] = "skull",
}

local function ParseMRTNote()
    groups = {}
    npcConfigs = {}

    local mrtText = GetMRTNoteData()

    if mrtText == nil then
        return nil
    end

    -- parse the text as lines
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

            local group = {
                name = name,
                markers = {},
                kicks = {},
                stops = {},
                backups = {}
            }
            table.insert(groups, group)

            -- find the group number based on the marker
            for j = 2, #splitLine do
                local part = splitLine[j]

                local mark = ParseMrtMark(part)
                if mark then
                    table.insert(group.markers, mark)
                else --
                    local splitName = SplitResponse(part, "-")
                    local playerName = ParsePlayerName(splitName[1])
                    if playerName ~= nil then
                        local spellId = nil
                        if splitName[2] then
                            if string.lower(splitName[2]) == "backup" then
                                table.insert(group.backups, playerName)
                            else
                                spellId = ParseSpellId(splitName[2])
                                table.insert(group.stops, {
                                    player = playerName,
                                    spellId = spellId
                                })
                            end
                        else
                            table.insert(group.kicks, playerName)
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
                local npcConfig = { noStop = false }

                for j = 2, #splitLine do
                    local part = splitLine[j]
                    if part:sub(1, #"--") == "--" then break end
                    if string.lower(part) == "nostop" then
                        npcConfig.noStop = true
                    else
                        local split = SplitResponse(part, "-")
                        if split[1] == "group" then
                            npcConfig.group = split[2]
                        end
                    end
                end

                npcConfigs[npcId] = npcConfig
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

local function GetRaidIconText(unitID)
    local icon = GetRaidTargetIndex(unitID)

    if icon == nil then
        return ""
    end

    return " |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. icon .. ":0|t"
end

local function HandleReflect(nameplate, castName, castID, spellId, unitID, startTime, endTime)
    if castName == nil or spellId == nil or spellId <= 0 or endTime == nil then
        if nameplate.interruptFrame.reflectIcon:IsShown() then
            nameplate.interruptFrame.reflectIcon:Hide()
        end
        return false, false
    end

    if castID ~= nameplate.lastTrackedCastID then
        nameplate.lastTrackedCastID = castID
        nameplate.endLockoutTime = nil
    end

    if castID == nameplate.failedCastID then
        nameplate.interruptFrame:Hide()
        return false, false
    end

    if GetTime() >= endTime / 1000 then
        nameplate.interruptFrame:Hide()
        return false, false
    end

    -- track last duration of cast to guess future kick order
    nameplate.lastCastDuration = (endTime - startTime) / 1000.0

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
            nameplate.interruptFrame:Show()
            if reflectInfo ~= nil and reflectInfo.hasReflect and reflectInfo.reflectEndTime > (endTime / 1000) and reflectInfo.reflectEndTime > GetTime() then
                warrHasReflectAuraUp = true
            end

            local isReflectAvailable = IsSpellReflectableAndReflectIsOffCD(unitID, unitID.."-target", spellId)
            if not nameplate.interruptFrame.reflectIcon:IsShown() and (isReflectAvailable or warrHasReflectAuraUp) then
                nameplate.interruptFrame.reflectIcon:Show()
                canReflectIt = true
            elseif not isReflectAvailable and not warrHasReflectAuraUp then
                nameplate.interruptFrame.reflectIcon:Hide()
            end

            if warrHasReflectAuraUp then
                nameplate.interruptFrame.reflectIcon.text:SetText("Reflecting")

                if SecretVeganToolsDB.PlaySoundOnReflect then
                    if nameplate.reflectAnnTimer == nil or GetTime() > nameplate.reflectAnnTimer then
                        nameplate.reflectAnnTimer = GetTime() + 5
                        C_VoiceChat.SpeakText(1, "Reflect", Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
                    end
                end
            end

        elseif nameplate.interruptFrame.reflectIcon:IsShown() then
            nameplate.interruptFrame.reflectIcon:Hide()
        end
    elseif nameplate.interruptFrame.reflectIcon:IsShown() then
        nameplate.interruptFrame.reflectIcon:Hide()
    end

    return warrHasReflectAuraUp, canReflectIt
end

function GetNpcConfig(unitGuid)
    local type, _, _, _, _, npcID = strsplit("-", unitGuid)
    if type ~= "Creature" then return false end

    return npcConfigs[tonumber(npcID)]
end

---@param npcConfig NpcConfig
local function GetGroupForMarker(mrtMark, npcConfig)
    for i, group in ipairs(groups) do
        for j, mark in ipairs(group.markers) do
            if mark == mrtMark and (not npcConfig.group or npcConfig.group == group.name) then
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
local function ConfigureKickBox(kickBox, kickAssignment, isCasting, warrHasReflectAuraUp)
    kickBox.icon:SetAlpha(0.7)

    if not kickAssignment then
        kickBox.icon:SetTexture("Interface\\Icons\\inv_misc_questionmark")
        return
    end

    kickBox.icon:SetTexture(C_Spell.GetSpellTexture(kickAssignment.spellId))

    if isCasting then
        if kickAssignment.unitId == "player" and not warrHasReflectAuraUp then
            kickBox.icon:SetAlpha(1)
            kickBox.border:SetColorTexture(0, 0.8, 0, 0.5)
        else
            kickBox.border:SetColorTexture(0.8, 0, 0, 0.5)
        end
    elseif not isCasting then
        if kickAssignment.unitId == "player" then
            kickBox.border:SetColorTexture(1, 0.8, 0, 0.5)
        else
            kickBox.border:SetColorTexture(0.8, 0, 0, 0.5)
        end
    end
end

---@param unitId string
---@param unitState UnitState
---@param nameplate SvtNameplate
local function HandleUnitSpellStart(unitId, unitState, nameplate)
    local raidTarget = GetRaidTargetIndex(unitId)
    local mrtMark = raidTargetToMrtMark[raidTarget]
    local castName, _, _, startTime, endTime, _, castID, notInterruptible, spellId = UnitCastingInfo(unitId)

    local warrHasReflectAuraUp, canReflectIt = HandleReflect(nameplate, castName, castID, spellId, unitId, startTime, endTime)

    local kickAssignment = GetKickAssignment(unitState, endTime / 1000)
    unitState.kickAssignment = kickAssignment

    local nextKickAssignment = nil
    if kickAssignment then
        local nextEndTimeToUse = endTime / 1000 + 3
        nextKickAssignment = GetKickAssignment(unitState, nextEndTimeToUse, kickAssignment)
    end

    ConfigureKickBox(nameplate.interruptFrame.kickBox, kickAssignment, true, warrHasReflectAuraUp)
    ConfigureKickBox(nameplate.interruptFrame.nextKickBox, nextKickAssignment, false, false)

    if not kickAssignment then
        nameplate.interruptFrame.kickBox.icon:SetTexture("Interface\\Icons\\inv_misc_questionmark")
        if not canReflectIt and SecretVeganToolsDB.PlaySoundOnInterruptTurn then
            C_VoiceChat.SpeakText(1, mrtMark .. " going off", Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
        end
        return
    end

    if kickAssignment.unitId == "player" and not warrHasReflectAuraUp then
        local icon = C_Spell.GetSpellTexture(kickAssignment.spellId)
        nameplate.interruptFrame.kickBox.icon:SetTexture(icon)
        nameplate.interruptFrame.kickBox.icon:SetAlpha(1)
        nameplate.interruptFrame.kickBox.border:SetColorTexture(0, 0.8, 0, 0.5)

        if not canReflectIt and SecretVeganToolsDB.PlaySoundOnInterruptTurn then
            local tts = GetKickAssignmentTts(kickAssignment)
            C_VoiceChat.SpeakText(1, tts .. " " .. mrtMark, Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
        end
    else
        nameplate.interruptFrame.kickBox.icon:SetAlpha(0.7)
        nameplate.interruptFrame.kickBox.border:SetColorTexture(0.8, 0, 0, 0.5)
    end
end

---@param unitId string
---@param unitState UnitState
---@param nameplate SvtNameplate
local function HandleUnitSpellEnd(unitId, unitState, nameplate)
    local endTimeToUse = GetTime() + (nameplate.lastCastDuration or 3.0)
    if nameplate.endLockoutTime ~= nil and nameplate.endLockoutTime > GetTime() then
        endTimeToUse = nameplate.endLockoutTime + (nameplate.lastCastDuration or 3.0)
    end

    local kickAssignment = GetKickAssignment(unitState, endTimeToUse)
    if kickAssignment then
        kickAssignment.isPrediction = true
    end

    local nextKickAssignment = nil
    if kickAssignment then
        local nextEndTimeToUse = endTimeToUse + (nameplate.lastCastDuration or 3.0) + 3
        nextKickAssignment = GetKickAssignment(unitState, nextEndTimeToUse, kickAssignment)
    end

    unitState.kickAssignment = kickAssignment

    ConfigureKickBox(nameplate.interruptFrame.kickBox, kickAssignment, false)

    if not kickAssignment then
        nameplate.interruptFrame.kickBox.icon:SetTexture("Interface\\Icons\\inv_misc_questionmark")
        nameplate.interruptFrame.nextKickBox:Hide()
        return
    end

    nameplate.interruptFrame.nextKickBox:Show()
    ConfigureKickBox(nameplate.interruptFrame.nextKickBox, nextKickAssignment, false)

    local icon = C_Spell.GetSpellTexture(kickAssignment.spellId)
    nameplate.interruptFrame.kickBox.icon:SetTexture(icon)
    nameplate.interruptFrame.kickBox.icon:SetAlpha(0.7)

    if kickAssignment.unitId == "player" then
        nameplate.interruptFrame.kickBox.border:SetColorTexture(1, 0.8, 0, 0.5)
    else
        nameplate.interruptFrame.kickBox.border:SetColorTexture(0.8, 0, 0, 0.5)
    end
end

-- Function to update interrupt information
---@param nameplate SvtNameplate
local function UpdateUnit(unitId, nameplate)
    if not nameplate or not nameplate.interruptFrame then return end

    local unitGuid = UnitGUID(unitId)
    local unitState = unitStates[unitGuid]

    if not unitState then return end

    local castName, _, _, startTime, endTime, _, castID, notInterruptible, spellId = UnitCastingInfo(unitId)
    HandleReflect(nameplate, castName, castID, spellId, unitId, startTime, endTime)

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

---@param nameplate SvtNameplate
local function InitUnit(unitId, nameplate)
    if not nameplate or not nameplate.interruptFrame then return end

    if not UnitCanAttack("player", unitId) then
        nameplate.interruptFrame.kickBox:Hide()
    end

    local unitGuid = UnitGUID(unitId)
    local raidTarget = GetRaidTargetIndex(unitId)
    local npcConfig = GetNpcConfig(unitGuid)

    nameplate.interruptFrame:Show()
    if not raidTarget or not npcConfig or not unitGuid then
        nameplate.interruptFrame:Hide()
        return
    end

    local mrtMark = raidTargetToMrtMark[raidTarget]
    local intendedGroup = GetGroupForMarker(mrtMark, npcConfig)
    if not intendedGroup then
        nameplate.interruptFrame:Hide()
        return
    end

    local unitState = unitStates[unitGuid]

    if not unitState or unitState.group.name ~= intendedGroup.name then
        -- init, or mark/group has changed
        unitState = { group = intendedGroup, npcConfig = npcConfig, kickIndex = 1, stopIndex = 1 }
        unitStates[unitGuid] = unitState
    end

    if SecretVeganToolsDB.ShowInterruptOrderFrameNameplates then
        nameplate.interruptFrame.kickBox:Show()
    else
        nameplate.interruptFrame.kickBox:Hide()
    end

    UpdateUnit(unitId, nameplate)
end

local function InitAllUnits()
    for unitID, nameplate in pairs(nameplateFrames) do
        InitUnit(unitID, nameplate)
    end
end

local requestLock = false

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
                local msg = "SPECINFORESPONSE|" .. specId .. "|" .. myGuid .. "|"

                for i = 1, GetNumGroupMembers() do
                    if UnitExists("party" .. i) then
                        C_ChatInfo.SendAddonMessage("SVTG1", msg, "WHISPER", UnitName("party" .. i))
                        -- request party data from other party members so we can initialize the data on response
                        C_ChatInfo.SendAddonMessage("SVTG1", "REQSPECINFO|", "WHISPER", UnitName("party" .. i))
                    end
                end

                if NS.interruptSpecInfoTable[specId] ~= nil then
                    local specData = NS.interruptSpecInfoTable[specId]
                    veganPartyData[myGuid].specId = specId
                    veganPartyData[myGuid].interruptSpellId = specData.InterruptSpell
                    veganPartyData[myGuid].lockoutDuration = specData.Lockout or 3.0
                end
            end
        end

        requestLock = false
    end)
end

local function EventHandler(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subevent = CombatLogGetCurrentEventInfo()
        local sourceGUID = select(4, CombatLogGetCurrentEventInfo())
        local destGUID = select(8, CombatLogGetCurrentEventInfo())

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
        elseif subevent == "SPELL_INTERRUPT" then
            local unitState = unitStates[destGUID]
            if unitState and unitState.nextKickerGuid == sourceGUID then
                unitState.nextKickerGuid = nil
                unitState.kickIndex = unitState.kickIndex + 1
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

        CreateInterruptAnchor(nameplate)
        nameplateFrames[unitID] = {}
        nameplateFrames[unitID] = nameplate
        InitUnit(unitID, nameplate)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unitID = ...
        if nameplateFrames[unitID] and nameplateFrames[unitID].interruptFrame then
            nameplateFrames[unitID].interruptFrame:Hide()
            nameplateFrames[unitID] = nil
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
            if msgType == "REQSPECINFO" then
                local currentSpec = GetSpecialization()
                if currentSpec then
                    local specId, currentSpecName = GetSpecializationInfo(currentSpec)
                    local msg = "SPECINFORESPONSE|" .. specId .. "|" .. UnitGUID("player") .. "|"
                    C_ChatInfo.SendAddonMessage("SVTG1", msg, "WHISPER", sender)
                end
            elseif msgType == "SPECINFORESPONSE" then
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
                    veganPartyData[guid].lockoutDuration = specData.Lockout or 3.0
                end
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        SendAndRequestInitialData()
        TryParseMrt()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        SendAndRequestInitialData()
    elseif event == "GROUP_JOINED" then
        SendAndRequestInitialData()
    elseif event == "ADDON_LOADED" then
        local addonName = ...

        if addonName == "SecretVeganTools" then
            if not SecretVeganToolsDB then
                SecretVeganToolsDB = {}
            end

            NS.InitAddonSettings()
        end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        local unitTarget, castGUID, spellID = ...
        local nameplate = C_NamePlate.GetNamePlateForUnit(unitTarget)
        if nameplate then
            nameplate.failedCastID = castGUID

            if nameplate.lastTrackedCastID == castGUID then
                nameplate.lastTrackedCastID = nil
                nameplate.endLockoutTime = GetTime() + 3.0
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        TryParseMrt()
    elseif event == "PLAYER_REGEN_DISABLED" then
        TryParseMrt()
    end
end

-- local inInstance, instanceType = IsInInstance()
-- if not inInstance or instanceType ~= "party" then return end

local frame = CreateFrame("Frame")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("GROUP_JOINED")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("RAID_TARGET_UPDATE")
frame:SetScript("OnEvent", EventHandler)