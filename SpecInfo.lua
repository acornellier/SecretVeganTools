local addonName, NS = ...

local interruptSpecInfoTable = {
    -- Tanks
    [66] = {
        SpecName = "Protection",
        InterruptSpell = 96231,
        InterruptName = "Rebuke",
        InterruptOrder = 1,
    },
    [73] = {
        SpecName = "Protection",
        InterruptSpell = 6552,
        InterruptName = "Pummel",
        InterruptOrder = 2,
    },
    [250] = {
        SpecName = "Blood",
        InterruptSpell = 47528,
        InterruptName = "Mind Freeze",
        InterruptOrder = 3,
    },
    [104] = {
        SpecName = "Guardian",
        InterruptSpell = 106839,
        InterruptName = "Skull Bash",
        InterruptOrder = 4,
    },
    [268] = {
        SpecName = "Brewmaster",
        InterruptSpell = 116705,
        InterruptName = "Spear Hand Strike",
        InterruptOrder = 5,
    },
    [581] = {
        SpecName = "Vengeance",
        InterruptSpell = 183752,
        InterruptName = "Disrupt",
        InterruptOrder = 6,
    },

    -- Dps
    [71] = {
        SpecName = "Arms",
        InterruptSpell = 6552,
        InterruptName = "Pummel",
        InterruptOrder = 7,
    },
    [72] = {
        SpecName = "Fury",
        InterruptSpell = 6552,
        InterruptName = "Pummel",
        InterruptOrder = 8,
    },
    [259] = {
        SpecName = "Assassination",
        InterruptSpell = 1766,
        InterruptName = "Kick",
        InterruptOrder = 9,
    },
    [260] = {
        SpecName = "Outlaw",
        InterruptSpell = 1766,
        InterruptName = "Kick",
        InterruptOrder = 10,
    },
    [261] = {
        SpecName = "Subtlety",
        InterruptSpell = 1766,
        InterruptName = "Kick",
        InterruptOrder = 11,
    },
    [253] = {
        SpecName = "Beast Mastery",
        InterruptSpell = 147362,
        InterruptName = "Counter Shot",
        InterruptOrder = 12,
    },
    [254] = {
        SpecName = "Marksmanship",
        InterruptSpell = 147362,
        InterruptName = "Counter Shot",
        InterruptOrder = 13,
    },
    [255] = {
        SpecName = "Survival",
        InterruptSpell = 187707,
        InterruptName = "Muzzle",
        InterruptOrder = 14,
    },
    [103] = {
        SpecName = "Feral",
        InterruptSpell = 106839,
        InterruptName = "Skull Bash",
        InterruptOrder = 15,
    },
    [62] = {
        SpecName = "Arcane",
        InterruptSpell = 2139,
        InterruptName = "Counterspell",
        InterruptOrder = 16,
    },
    [63] = {
        SpecName = "Fire",
        InterruptSpell = 2139,
        InterruptName = "Counterspell",
        InterruptOrder = 17,
    },
    [64] = {
        SpecName = "Frost",
        InterruptSpell = 2139,
        InterruptName = "Counterspell",
        InterruptOrder = 18,
    },
    [70] = {
        SpecName = "Retribution",
        InterruptSpell = 96231,
        InterruptName = "Rebuke",
        InterruptOrder = 19,
    },
    [102] = {
        SpecName = "Balance",
        InterruptSpell = 78675,
        InterruptName = "Solar Beam",
        InterruptOrder = 20,
    },
    [251] = {
        SpecName = "Frost",
        InterruptSpell = 47528,
        InterruptName = "Mind Freeze",
        InterruptOrder = 21,
    },
    [252] = {
        SpecName = "Unholy",
        InterruptSpell = 47528,
        InterruptName = "Mind Freeze",
        InterruptOrder = 22,
    },
    [265] = {
        SpecName = "Affliction",
        InterruptSpell = 0,
        InterruptName = "TODO",
        InterruptOrder = 23,
    },
    [266] = {
        SpecName = "Demonology",
        InterruptSpell = 0,
        InterruptName = "TODO",
        InterruptOrder = 24,
    },
    [267] = {
        SpecName = "Destruction",
        InterruptSpell = 0,
        InterruptName = "TODO",
        InterruptOrder = 25,
    },
    [258] = {
        SpecName = "Shadow",
        InterruptSpell = 15487,
        InterruptName = "Silence",
        InterruptOrder = 26,
    },
    [262] = {
        SpecName = "Elemental",
        InterruptSpell = 57994,
        InterruptName = "Wind Shear",
        InterruptOrder = 27,
    },
    [263] = {
        SpecName = "Enhancement",
        InterruptSpell = 57994,
        InterruptName = "Wind Shear",
        InterruptOrder = 28,
    },
    [269] = {
        SpecName = "Windwalker",
        InterruptSpell = 116705,
        InterruptName = "Spear Hand Strike",
        InterruptOrder = 29,
    },
    [577] = {
        SpecName = "Havoc",
        InterruptSpell = 183752,
        InterruptName = "Disrupt",
        InterruptOrder = 30,
    },
    [1467] = {
        SpecName = "Devastation",
        InterruptSpell = 351338,
        InterruptName = "Quell",
        InterruptOrder = 31,
    },
    [1473] = {
        SpecName = "Augmentation",
        InterruptSpell = 351338,
        InterruptName = "Quell",
        InterruptOrder = 32,
    },

    -- Healers

    [1468] = {
        SpecName = "Preservation",
        InterruptSpell = 351338,
        InterruptName = "Quell",
        InterruptOrder = 33,
    },
    [65] = {
        SpecName = "Holy",
        InterruptSpell = 96231,
        InterruptName = "Rebuke",
        InterruptOrder = 34,
    },
    [105] = {
        SpecName = "Restoration",
        InterruptSpell = 106839,
        InterruptName = "Skull Bash",
        InterruptOrder = 35,
    },
    [264] = {
        SpecName = "Restoration",
        InterruptSpell = 57994,
        InterruptName = "Wind Shear",
        InterruptOrder = 36,
    },
    [270] = {
        SpecName = "Mistweaver",
        InterruptSpell = 116705,
        InterruptName = "Spear Hand Strike",
        InterruptOrder = 37,
    },
}

NS.interruptSpecInfoTable = interruptSpecInfoTable