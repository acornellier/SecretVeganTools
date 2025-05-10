---@class InterruptFrame: Frame
---@field reflectIcon Frame
---@field kickBox Frame

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
---@field spellAvailableTime table<integer, integer>
---@type table<string, VeganData>
local veganPartyData = {}

-- Group definitions with markers and rotation
---@class StopAssignment
---@field player string
---@field spellId integer

---@class GroupAssignment
---@field markers string[]
---@field kicks string[]
---@field stops StopAssignment[]

---@type table<string, GroupAssignment>
local groups = {}

-- Enabled NPCs and number of kicks associated with them
---@type table<string, integer>
local npcAssignments = {}

-- Enemy unit tracking
---@class UnitState
---@field groupName string
---@field kickIndex integer
---@field nextKickerGuid string?
---@field stopIndex integer
---@field nextStopperGuid string?
---@field kickAssignment KickAssignment?
---@type table<string, UnitState>
local unitStates = {}

-- Default Interrupt Frame
local nonAnchoredInterruptFrame = CreateFrame("Frame", nil, UIParent)
nonAnchoredInterruptFrame:SetSize(100, 100)
nonAnchoredInterruptFrame:SetPoint("CENTER", UIParent, "RIGHT", -140, 40)
nonAnchoredInterruptFrame:Show()

local function SetupDefaultInterruptFrame()
    nonAnchoredInterruptFrame.movableTexture = nonAnchoredInterruptFrame:CreateTexture(nil, "BACKGROUND")
    nonAnchoredInterruptFrame.movableTexture:SetSize(100, 100)
    nonAnchoredInterruptFrame.movableTexture:SetPoint("CENTER", nonAnchoredInterruptFrame, "CENTER", 0, 0)
    nonAnchoredInterruptFrame.movableTexture:SetColorTexture(0, 0, 0, 0.5)

    local kickBox = CreateFrame("Frame", nil, nonAnchoredInterruptFrame)
    -- TODO: copy from nameplate
    nonAnchoredInterruptFrame.kickBox = kickBox
    nonAnchoredInterruptFrame.kickBox:Hide()

    if (SecretVeganToolsDB.InterruptFramePosition ~= nil) then
        local point, relativePoint, offsetX, offsetY = SecretVeganToolsDB.InterruptFramePosition[1], SecretVeganToolsDB.InterruptFramePosition[2], SecretVeganToolsDB.InterruptFramePosition[3], SecretVeganToolsDB.InterruptFramePosition[4]
        nonAnchoredInterruptFrame:SetPoint(point, UIParent, relativePoint, offsetX, offsetY)
    end

    if (SecretVeganToolsDB.ShowInterruptOrderFrame) then
        nonAnchoredInterruptFrame:Show()
    else
        nonAnchoredInterruptFrame:Hide()
    end

    if (SecretVeganToolsDB.DragInterruptOrderFrame) then
        nonAnchoredInterruptFrame:Show()
        nonAnchoredInterruptFrame:SetMovable(true)
        nonAnchoredInterruptFrame:EnableMouse(true)
        nonAnchoredInterruptFrame.movableTexture:Show()
    else
        nonAnchoredInterruptFrame:SetMovable(false)
        nonAnchoredInterruptFrame:EnableMouse(false)
        nonAnchoredInterruptFrame.movableTexture:Hide()
    end

end

nonAnchoredInterruptFrame:RegisterForDrag("LeftButton")
nonAnchoredInterruptFrame:SetScript("OnDragStart", function(self, button)
	self:StartMoving()
end)
nonAnchoredInterruptFrame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
    local point, _, relativePoint, offsetX, offsetY = nonAnchoredInterruptFrame:GetPoint(1)
    SecretVeganToolsDB.InterruptFramePosition = { point, relativePoint, offsetX, offsetY }
end)

NS.nonAnchoredInterruptFrame = nonAnchoredInterruptFrame

-- Function to create interrupt display
local function CreateInterruptAnchor(nameplate)
    if nameplate.interruptFrame then return end

    -- Create a frame to display interrupt status
    local interruptFrame = CreateFrame("Frame", nil, nameplate)
    nameplate.interruptFrame = interruptFrame
    interruptFrame:SetSize(50, 20)
    interruptFrame:SetPoint("TOP", nameplate, "TOP", 0, 20)

    local kickBox = CreateFrame("Frame", nil, interruptFrame)
    kickBox:SetSize(60, 20)
    kickBox:SetPoint("CENTER", interruptFrame, "CENTER", 0, 0)
    kickBox.bg = kickBox:CreateTexture(nil, "BACKGROUND")
    kickBox.bg:SetSize(60, 20)
    kickBox.bg:SetPoint("BOTTOM")
    kickBox.bg:SetColorTexture(1, 0, 0, 0.5)
    kickBox.text2 = kickBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    kickBox.text2:SetPoint("CENTER")
    kickBox.text2:SetTextColor(1, 1, 0)
    kickBox.text2:SetText()
    interruptFrame.kickBox = kickBox
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
        return nil
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

---@class KickAssignment
---@field unitId UnitToken
---@field type "kick" | "stop"
---@field stopId integer

---@param unitState UnitState
---@param castEndTime number
---@param nextGuessCastTime number
---@return KickAssignment?
local function GetKickAssignment(unitState, castEndTime, nextGuessCastTime)
    local group = groups[unitState.groupName]
    if not group then return nil end

    local function isSpellAvailable(unitGuid, spellId)
        local data = veganPartyData[unitGuid]
        if not data then return false end
        if not data.spellAvailableTime then data.spellAvailableTime = {} end
        return not data.spellAvailableTime[spellId] or data.spellAvailableTime[spellId] <= castEndTime
    end

    local function isKickAvailable(unitGuid)
        local data = veganPartyData[unitGuid]
        return isSpellAvailable(unitGuid, data.interruptSpellId)
    end

    local kickRotation = group.kicks
    local stopRotation = group.stops
    local totalKicks = #kickRotation
    local totalStops = #stopRotation

    -- Try to find the next kick that is available, starting from current index
    for i = 0, totalKicks - 1 do
        local idx = (unitState.kickIndex + i - 1) % totalKicks + 1
        local kicker = kickRotation[idx]
        local unitId, unitGuid = GetUnitIDAndGuidInPartyOrSelfByName(kicker)

        if isKickAvailable(unitGuid) then
            unitState.nextKickerGuid = unitGuid
            return { unitId = unitId, type = "kick", stopId = 0 }
        end
    end

    -- If no kicks available, try a stop from stopRotation
    for i = 0, totalStops - 1 do
        local idx = (unitState.stopIndex + i - 1) % totalStops + 1
        local stop = stopRotation[idx]
        local unitId, unitGuid = GetUnitIDAndGuidInPartyOrSelfByName(stop.player)

        if isSpellAvailable(unitGuid, stop.spellId) then
            unitState.nextStopperGuid = unitGuid
            return { unitId = unitId, type = "stop", stopId = stop.spellId }
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
        if (castName ~= nil and spellId ~= nil and spellId > 0 and endTime ~= nil and UnitGUID(unitID.."-target") == p_TargetGUID) then
            if (GetTime() < endTime / 1000) then
                if (endTime < p_EndTime) then
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
    [4] = "triangle",
    [5] = "moon",
    [6] = "square",
    [7] = "cross",
    [8] = "skull",
}

local function ParseMRTNote()
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
            if line == "svtgroupstart" then
                foundStart = true
            end
        else
            if line == "svtgroupend" then
                break
            end
            
            local splitLine = SplitResponse(line, " ")
            local groupName = splitLine[1]

            if groups[groupName] == nil then
                groups[groupName] = {
                    markers = {},
                    kicks = {},
                    stops = {}
                }
            end

            -- find the group number based on the marker
            for j = 2, #splitLine do
                local part = splitLine[j]

                local mark = ParseMrtMark(part)
                if mark then
                    table.insert(groups[groupName].markers, mark)
                else
                    local splitName = SplitResponse(part, "-")
                    local playerName = ParsePlayerName(splitName[1])
                    if playerName ~= nil then
                        local spellId = nil
                        if splitName[2] then
                            spellId = ParseSpellId(splitName[2])
                            table.insert(groups[groupName].stops, {
                                player = playerName,
                                spellId = spellId
                            })
                        else
                            table.insert(groups[groupName].kicks, playerName)
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
            if line == "svtnpcstart" then
                foundStart = true
            end
        else
            if line == "svtnpcend" then
                break
            end
            
            local splitLine = SplitResponse(line, " ")
            local npcId = tonumber(splitLine[1])
            if npcId then
                npcAssignments[npcId] = tonumber(splitLine[2])
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

    if (icon == nil) then
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

    local warrHasReflectAuraUp = false
    local canReflectIt = false

    if (castID ~= nameplate.lastTrackedCastID) then
        nameplate.lastTrackedCastID = castID
        nameplate.endLockoutTime = nil
    end

    if (castID == nameplate.failedCastID) then
        nameplate.interruptFrame:Hide()
        return warrHasReflectAuraUp, canReflectIt
    end

    if (GetTime() >= (endTime / 1000)) then
        nameplate.interruptFrame:Hide()
        return warrHasReflectAuraUp, canReflectIt
    end

    -- track last duration of cast to guess future kick order
    nameplate.lastCastDuration = (endTime - startTime) / 1000.0

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

function GetNpcCastCount(unitGuid)
    local type, _, _, _, _, npcID = strsplit("-", unitGuid)
    if type ~= "Creature" then return false end

    return npcAssignments[tonumber(npcID)]
end

local function GetGroupForMarker(mrtMark)
    for groupName, group in pairs(groups) do
        for i, mark in ipairs(group.markers) do
            if mark == mrtMark then
                return groupName
            end
        end
    end
    return nil
end

local function GetUnitIdNamePlateByGuid(unitGuid)
    for unitId, nameplate in pairs(nameplateFrames) do
        local nameplateGuid = UnitGUID(unitId)
        if nameplateGuid == unitGuid then
            return unitId, nameplate
        end
    end
    return nil
end

local function HandleUnitSpellStart(unitGuid)
    local unitState = unitStates[unitGuid]
    if not unitState then return end

    local unitId, nameplate = GetUnitIdNamePlateByGuid(unitGuid)
    if not unitId or not nameplate then print("huh"); return end

    local raidTarget = GetRaidTargetIndex(unitId)
    local mrtMark = raidTargetToMrtMark[raidTarget]
    local castName, _, _, startTime, endTime, _, castID, notInterruptible, spellId = UnitCastingInfo(unitId)

    local warrHasReflectAuraUp, canReflectIt = HandleReflect(nameplate, castName, castID, spellId, unitId, startTime, endTime)

    local kickAssignment = GetKickAssignment(unitState, endTime / 1000, nameplate.lastCastDuration)
    unitState.kickAssignment = kickAssignment
    if not kickAssignment then
        nameplate.interruptFrame.kickBox.bg:SetColorTexture(1, 0, 0, 0.5)
        nameplate.interruptFrame.kickBox.text2:SetText("STOP?")
        -- nonAnchoredInterruptFrame.kickBox.bg:SetColorTexture(1, 0, 0, 0.5)
        -- nonAnchoredInterruptFrame.kickBox.text2:SetText("STOP?")
        return
    end
    
    local text2 = ""
    local text3 = ""
    local coloredName = GetColoredUnitClassAndName(kickAssignment.unitId)
    if warrHasReflectAuraUp == true then
        text2 = coloredName .. "|cffFFFFFF|R [REFLECT!]"
    else
        text2 = coloredName
    end

    -- if nextKicker ~= nil then
    --     text3 = "Next: " .. GetColoredUnitClassAndName(nextKicker)
    -- else
    --     text3 = "Next: |cffFF0000N/A|R"
    -- end

    nameplate.interruptFrame.kickBox.text2:SetText(text2)
    -- nonAnchoredInterruptFrame.kickBox.text2:SetText(GetRaidIconText(unitId) .. text2)
    -- nonAnchoredInterruptFrame.kickBox.text3:SetText(text3)

    if kickAssignment.unitId == "player" then
        nameplate.interruptFrame.kickBox.bg:SetColorTexture(0, 1, 0, 0.5)
        -- nonAnchoredInterruptFrame.kickBox.bg:SetColorTexture(0, 1, 0, 0.5)
        if not canReflectIt then
            nameplate.kickAnnTimer = GetTime() + 5

            if SecretVeganToolsDB.PlaySoundOnInterruptTurn then
                local tts = "Kick"
                if kickAssignment.type == "stop" then
                    if kickAssignment.stopId == 408 then
                        tts = "Kidney"
                    else
                        tts = "Stop"
                    end
                end
                C_VoiceChat.SpeakText(1, tts .. " " .. mrtMark, Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
            end
        end
    else
        nameplate.interruptFrame.kickBox.bg:SetColorTexture(1, 0, 0, 0.5)
        -- nonAnchoredInterruptFrame.kickBox.bg:SetColorTexture(1, 0, 0, 0.5)
    end
end

-- Function to update interrupt information
---@param nameplate SvtNameplate
local function UpdateNameplate(unitID, nameplate)
    if not nameplate or not nameplate.interruptFrame then return end

    local castName, _, _, startTime, endTime, _, castID, notInterruptible, spellId = UnitCastingInfo(unitID)

    HandleReflect(nameplate, castName, castID, spellId, unitID, startTime, endTime)

    -- handle interrupt
    if not UnitCanAttack("player", unitID) then
        nameplate.interruptFrame.kickBox:Hide()
        nonAnchoredInterruptFrame:Hide()
    end

    local unitGuid = UnitGUID(unitID)
    local raidTarget = GetRaidTargetIndex(unitID)
    local npcCastCount = GetNpcCastCount(unitGuid)

    if not raidTarget or not npcCastCount or not unitGuid then
        nameplate.interruptFrame:Hide()
        nonAnchoredInterruptFrame:Hide()
        return
    end

    local mrtMark = raidTargetToMrtMark[raidTarget]
    local intendedGroup = GetGroupForMarker(mrtMark)
    if not intendedGroup then
        nameplate.interruptFrame:Hide()
        nonAnchoredInterruptFrame:Hide()
        return
    end

    local unitState = unitStates[unitGuid]

    if not unitState then
        unitState = { groupName = intendedGroup, kickIndex = 1, stopIndex = 1 }
        unitStates[unitGuid] = unitState
    end

    if unitState.groupName ~= intendedGroup then
        -- init, or mark/group has changed
        unitState.groupName = intendedGroup
        unitState.kickIndex = 1
        unitState.stopIndex = 1
    end

    if SecretVeganToolsDB.ShowInterruptOrderFrameNameplates then
        nameplate.interruptFrame.kickBox:Show()
    else
        nameplate.interruptFrame.kickBox:Hide()
    end

    if SecretVeganToolsDB.ShowInterruptOrderFrame then
        nonAnchoredInterruptFrame:Show()
    else
        nonAnchoredInterruptFrame:Hide()
    end

    if not castName or notInterruptible then
        -- nameplate.interruptFrame.kickBox.text2:SetText("")
        -- nameplate.interruptFrame.kickBox:Hide()

        -- if SecretVeganToolsDB.ShowInterruptOrderFrame then
        --     local endTimeToUse = GetTime() + (nameplate.lastCastDuration or 3.0)
        --     if nameplate.endLockoutTime ~= nil and nameplate.endLockoutTime > GetTime() then
        --         endTimeToUse = nameplate.endLockoutTime
        --     end

        --     local kickAssignment = GetKickAssignment(unitState, endTimeToUse, nameplate.lastCastDuration or 3.0)

        --     local text2 = ""
        --     local text3 = ""

        --     if kickAssignment ~= nil then
        --         text2 = GetColoredUnitClassAndName(kickAssignment.unitId)
        --     end

        --     if kickAssignment ~= nil then
        --         text3 = "Next: " .. GetColoredUnitClassAndName(kickAssignment.unitId)
        --     else
        --         text3 = "Next: |cffFF0000N/A|R"
        --     end

        --     nonAnchoredInterruptFrame.kickBox.text2:SetText(GetRaidIconText(unitID) .. text2)
        --     nonAnchoredInterruptFrame.kickBox.text3:SetText(text3)
        --     nonAnchoredInterruptFrame.kickBox.text:SetText(tostring(order))

            
        --     if kickAssignment ~= nil and kickAssignment.unitId == "player" then
        --         nonAnchoredInterruptFrame.kickBox.bg:SetColorTexture(0, 1, 0, 0.5)
        --     else
        --         nonAnchoredInterruptFrame.kickBox.bg:SetColorTexture(1, 0, 0, 0.5)
        --     end
        -- end
    end
end

local function UpdateAllNameplates()
    for unitID, nameplate in pairs(nameplateFrames) do
        UpdateNameplate(unitID, nameplate)
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
            if (specId ~= nil) then
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

        if subevent == "SPELL_CAST_START" then
            HandleUnitSpellStart(sourceGUID)
        elseif subevent == "SPELL_CAST_SUCCESS" then
            local spellID = select(12, CombatLogGetCurrentEventInfo())
            local veganData = veganPartyData[sourceGUID];
            if not veganData then return; end

            if spellID == 23920 then
                veganData.reflectCooldown = GetTime() + 25
            else
                local cooldown = GetSpellBaseCooldown(spellID) / 1000
                veganData.spellAvailableTime[spellID] = GetTime() + cooldown
            end
        elseif subevent == "SPELL_INTERRUPT" then
            local unitState = unitStates[destGUID]
            if unitState and unitState.nextKickerGuid == sourceGUID then
                unitState.nextKickerGuid = nil
                unitState.kickIndex = unitState.kickIndex + 1
            end
        end

        UpdateAllNameplates()
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Clean up partyCooldowns table for missing members
        for unit in IterateSelfAndPartyMembers() do
            if (UnitExists(unit)) then
                local guid = UnitGUID(unit)
                if (not veganPartyData[guid]) then
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
        local inInstance, instanceType = IsInInstance()
        -- TODO: UNCOMMENT
        if nameplate -- and inInstance and instanceType == "party"
         then
            CreateInterruptAnchor(nameplate)
            nameplateFrames[unitID] = {}
            nameplateFrames[unitID] = nameplate
            UpdateNameplate(unitID, nameplate)
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local unitID = ...
        if nameplateFrames[unitID] and nameplateFrames[unitID].interruptFrame then
            nameplateFrames[unitID].interruptFrame:Hide()
            nameplateFrames[unitID] = nil
        end
    elseif event == "RAID_TARGET_UPDATE" then
        UpdateAllNameplates()
    elseif event == "UNIT_AURA" then
        local unit, info = ...
        local guid = UnitGUID(unit)
        if (veganPartyData[guid] == nil) then
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

                if (veganPartyData[guid] == nil) then
                    veganPartyData[guid] = {}
                    veganPartyData[guid].unitID = GetUnitIDInPartyOrSelfByGuid(guid)
                end

                veganPartyData[guid].specId = specId

                if (NS.interruptSpecInfoTable[specId] ~= nil) then
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
            SetupDefaultInterruptFrame()
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
    elseif event == "PLAYER_REGEN_DISABLED" then
        TryParseMrt()
    end
end


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