--[[----------------------------------------------------------------------------

  TradeWhisper/Options.lua

  Copyright 2024 Mike Battersby

----------------------------------------------------------------------------]]--

local addOnName, addOnTable = ...

local L = setmetatable({}, { __index=function(_,k) return k end })

local AceGUI = LibStub("AceGUI-3.0")

local order
do
    local n = 0
    order = function () n = n + 1 return n end
end

local addRecipeCrafter, addRecipeText, addIgnorePlayer

local options = {
    type = "group",
    childGroups = "tab",
    args = {
        GeneralGroup = {
            type = "group",
            name = GENERAL,
            inline = false,
            order = order(),
            args = {
                topGap = {
                    type = "description",
                    name = "\n",
                    width = "full",
                    order = order(),
                },
                message = {
                    type = "input",
                    multiline = 4,
                    name = L["Message"],
                    order = order(),
                    get = function () return TradeWhisper.db.global.message end,
                    set = function (_, v) TradeWhisper.db.global.message = v end,
                    width = "full",
                },
            },
        },
        ScanGroup = {
            type = "group",
            name = L["Scan Keywords"],
            inline = false,
            order = order(),
            args = {
                crafter = {
                    name = L["Crafter"],
                    type = "input",
                    width = 1.4,
                    order = order(),
                    get = function () return addRecipeCrafter end,
                    set = function (_, v) addRecipeCrafter = v end,
                },
                preTextGap = {
                    name = "",
                    type = "description",
                    width = 0.1,
                    order = order(),
                },
                text = {
                    name = L["Text"],
                    type = "input",
                    width = 1.4,
                    order = order(),
                    get = function () return addRecipeText end,
                    set = function (_, v) addRecipeText = v end,
                },
                preAddButtonGap = {
                    name = "",
                    type = "description",
                    width = 0.1,
                    order = order(),
                },
                AddButton = {
                    name = ADD,
                    type = "execute",
                    width = 0.5,
                    order = order(),
                    disabled =
                        function ()
                            return addRecipeCrafter == nil or addRecipeText == nil
                        end,
                    func =
                        function ()
                            if addRecipeCrafter and addRecipeText then
                                TradeWhisper:ScanAdd(addRecipeCrafter, addRecipeText)
                                addRecipeCrafter = nil
                                addRecipeText = nil
                            end
                        end,
                },
                ScanList = {
                    name = L["Scan list"],
                    type = "group",
                    order = order(),
                    inline = true,
                    args = {},
                    plugins = {},
                }
            }
        },
        IgnoreGroup = {
            type = "group",
            name = L["Ignored players"],
            order = order(),
            inline = false,
            args = {
                ignoreAbility = {
                    name = L["Player"],
                    type = "input",
                    width = 1,
                    order = order(),
                    get = function () return addIgnorePlayer end,
                    set = function (_, v) addIgnorePlayer = v end,
                },
                AddButton = {
                    name = ADD,
                    type = "execute",
                    width = 1,
                    order = order(),
                    disabled = function () return addIgnorePlayer == nil end,
                    func =
                        function ()
                            if addIgnorePlayer then
                                TradeWhisper:IgnoreAdd(addIgnorePlayer)
                                addIgnorePlayer = nil
                            end
                        end,
                },
                IgnoreList = {
                    name = L["Ignore list"],
                    type = "group",
                    order = order(),
                    inline = true,
                    args = {},
                    plugins = {},
                },
            },
        },
        ImportExport = {
            type = "group",
            name = L["Import / Export"],
            order = order(),
            inline = false,
            args = {
                Text = {
                    name = L["Import/Export String"],
                    type = "input",
                    width = "full",
                    multiline = 22,
                    confirm = function () end,
                    set = function (_, text) TradeWhisper:ImportDB(text) end,
                    get = function () return TradeWhisper:ExportDB() end,
                },
            },
        },
    },
}

local function GenerateOptions()
    local scanList = { }
    local scanKeys = GetKeysArray(TradeWhisper.db.global.tradeScan)
    table.sort(scanKeys)

    for i, text in ipairs(scanKeys) do
        local crafter = TradeWhisper.db.global.tradeScan[text]
        scanList["index"..i] = {
            order = 10*i+1,
            name = tostring(i),
            type = "description",
            width = 0.2,
        }
        scanList["scanCrafter"..i] = {
            order = 10*i+2,
            name = crafter,
            type = "description",
            width = 1.1,
        }
        scanList["scanText"..i] = {
            order = 10*i+3,
            name = text,
            type = "description",
            width = 1.7,
        }
        scanList["delete"..i] = {
            order = 10*i+4,
            name = DELETE,
            type = "execute",
            func = function () TradeWhisper:ScanDel(text) end,
            width = 0.45,
        }
    end
    options.args.ScanGroup.args.ScanList.plugins.scanList = scanList

    local ignoreKeys = GetKeysArray(TradeWhisper.db.global.tradeIgnore)
    table.sort(ignoreKeys)
    local ignoreList = {}

    for i, playerName in ipairs(ignoreKeys) do
        ignoreList["index"..i] = {
            name = tostring(i),
            type = "description",
            width = 0.2,
            order = 10*i+1,
        }
        ignoreList["playerName"..i] = {
            name = playerName,
            type = "description",
            width = 2.8,
            order = 10*i+2,
        }
        ignoreList["delete"..i] = {
            name = DELETE,
            type = "execute",
            func = function () TradeWhisper:IgnoreDel(playerName) end,
            width = 0.5,
            order = 10*i+3,
        }
    end
    options.args.IgnoreGroup.args.IgnoreList.plugins.ignoreList = ignoreList

    return options
end

-- The sheer amount of crap required here is ridiculous. I bloody well hate
-- frameworks, just give me components I can assemble. Dot-com weenies ruined
-- everything, even WoW.

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions =  LibStub("AceDBOptions-3.0")

-- AddOns are listed in the Blizzard panel in the order they are
-- added, not sorted by name. In order to mostly get them to
-- appear in the right order, add the main panel when loaded.

AceConfig:RegisterOptionsTable(addOnName, GenerateOptions)
local optionsPanel, category = AceConfigDialog:AddToBlizOptions(addOnName)
