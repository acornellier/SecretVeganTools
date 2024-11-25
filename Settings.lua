local addonName, NS = ...

local function InitAddonSettings()
    local category = Settings.RegisterVerticalLayoutCategory("SecretVeganTools")

    local function OnSettingChanged(setting, value)
    end

    local function OnSettingChangedShowInterruptFrame(setting, value)
        if (value) then
            NS.nonAnchoredInterruptFrame:Show();
        else
            NS.nonAnchoredInterruptFrame:Hide();
        end
    end

    local function OnSettingChangedDragInterruptFrame(setting, value)
        NS.nonAnchoredInterruptFrame:SetMovable(value)
        NS.nonAnchoredInterruptFrame:EnableMouse(value)

        if (value) then
            NS.nonAnchoredInterruptFrame.movableTexture:Show();
        else
            NS.nonAnchoredInterruptFrame.movableTexture:Hide();
        end
    end

    do 
        local name = "Play Sound on Interrupt Turn"
        local variable = "PlaySoundOnInterruptTurn"
        local variableKey = "PlaySoundOnInterruptTurn"
        local defaultValue = true

        local setting = Settings.RegisterAddOnSetting(category, variable, variableKey, SecretVeganToolsDB, type(defaultValue), name, defaultValue)
        setting:SetValueChangedCallback(OnSettingChanged)

        local tooltip = "Will play a TTS sound when it's your turn to interrupt."
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    do 
        local name = "Play Sound on Reflect"
        local variable = "PlaySoundOnReflect"
        local variableKey = "PlaySoundOnReflect"
        local defaultValue = true

        local setting = Settings.RegisterAddOnSetting(category, variable, variableKey, SecretVeganToolsDB, type(defaultValue), name, defaultValue)
        setting:SetValueChangedCallback(OnSettingChanged)

        local tooltip = "Will play a TTS sound when the warrior has reflect up and a spell is about to be reflected."
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    do 
        local name = "Show Interrupt Order Frame"
        local variable = "ShowInterruptOrderFrame"
        local variableKey = "ShowInterruptOrderFrame"
        local defaultValue = false

        local setting = Settings.RegisterAddOnSetting(category, variable, variableKey, SecretVeganToolsDB, type(defaultValue), name, defaultValue)
        setting:SetValueChangedCallback(OnSettingChangedShowInterruptFrame)

        local tooltip = "Will show an interrupt order frame seperate from the default nameplate frame"
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    do 
        local name = "Drag Interrupt Order Frame"
        local variable = "DragInterruptOrderFrame"
        local variableKey = "DragInterruptOrderFrame"
        local defaultValue = false

        local setting = Settings.RegisterAddOnSetting(category, variable, variableKey, SecretVeganToolsDB, type(defaultValue), name, defaultValue)
        setting:SetValueChangedCallback(OnSettingChangedDragInterruptFrame)

        local tooltip = "Toggle the ability to drag the interrupt order frame"
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    Settings.RegisterAddOnCategory(category)
end

NS.InitAddonSettings = InitAddonSettings