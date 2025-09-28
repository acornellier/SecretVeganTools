local addonName, NS = ...

local function InitAddonSettings()
    local category = Settings.RegisterVerticalLayoutCategory("SecretVeganTools")

    NS.SettingsCategoryID = category.ID

    local function OnEnabledSettingChanged(setting, value)
        ReloadUI()
    end

    do
        local name = "Enabled (reloads UI)"
        local variable = "Enabled"
        local variableKey = "Enabled"
        local defaultValue = true

        local setting = Settings.RegisterAddOnSetting(category, variable, variableKey, SecretVeganToolsDB, type(defaultValue), name, defaultValue)
        setting:SetValueChangedCallback(OnEnabledSettingChanged)

        local tooltip = "Quickly enable/disable the addon"
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    do
        local name = "Show interrupts on nameplates"
        local variable = "ShowInterruptOrderFrameNameplates"
        local variableKey = "ShowInterruptOrderFrameNameplates"
        local defaultValue = true

        local setting = Settings.RegisterAddOnSetting(category, variable, variableKey, SecretVeganToolsDB, type(defaultValue), name, defaultValue)
        setting:SetValueChangedCallback(NS.InitAllUnits)

        local tooltip = "Show the interrupt order frame on nameplates"
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    do
        local name = "Require party present"
        local variable = "RequireConfiguredMembersInParty"
        local variableKey = "RequireConfiguredMembersInParty"
        local defaultValue = true

        local setting = Settings.RegisterAddOnSetting(category, variable, variableKey, SecretVeganToolsDB, type(defaultValue), name, defaultValue)
        setting:SetValueChangedCallback(NS.InitAllUnits)

        local tooltip = "Only show the interrupt order frame if a mob's configured members are in your party."
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    do
        local name = "Play TTS on your turn"
        local variable = "PlaySoundOnInterruptTurn"
        local variableKey = "PlaySoundOnInterruptTurn"
        local defaultValue = true

        local setting = Settings.RegisterAddOnSetting(category, variable, variableKey, SecretVeganToolsDB, type(defaultValue), name, defaultValue)

        local tooltip = "Will play a TTS sound when it's your turn to interrupt."
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    do
        local name = "Play TTS on reflect"
        local variable = "PlaySoundOnReflect"
        local variableKey = "PlaySoundOnReflect"
        local defaultValue = true

        local setting = Settings.RegisterAddOnSetting(category, variable, variableKey, SecretVeganToolsDB, type(defaultValue), name, defaultValue)

        local tooltip = "Will play a TTS sound when the warrior has reflect up and a spell is about to be reflected."
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    Settings.RegisterAddOnCategory(category)
end

NS.InitAddonSettings = InitAddonSettings
