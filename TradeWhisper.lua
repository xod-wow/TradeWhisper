--[[----------------------------------------------------------------------------

  TradeWhisper

----------------------------------------------------------------------------]]--

local addOnName, addOnTable = ...

local printTag = ORANGE_FONT_COLOR:WrapTextInColorCode(addOnName .. ": ")

local function printf(fmt, ...)
    local msg = string.format(fmt, ...)
    SELECTED_CHAT_FRAME:AddMessage(printTag .. msg)
end

--[[------------------------------------------------------------------------]]--

TradeWhisperMixin = {}

function TradeWhisperMixin:PrintHelp()
    printf("Usage:")
    printf("  /tw add text | itemlinks")
    printf("  /tw del text | index")
    printf("  /tw clear")
    printf("  /tw list")
    printf("  /tw ignore add playerName[-Realm]")
    printf("  /tw ignore del playerName[-Realm]")
    printf("  /tw ignore clear")
    printf("  /tw ignore list")
end

function TradeWhisperMixin:SlashCommand(arg)
    -- Zero / One arg
    if not arg or arg == '' or arg == 'help' then
        self:PrintHelp()
        return true
    elseif arg == 'clear' then
        self:ScanClear()
        return true
    elseif arg == 'list' then
        self:ScanList()
        return true
    end

    local arg1, arg2, arg3

    -- Two arg
    arg1, arg2 = string.split(' ', arg, 2)

    if arg1 == 'del' and arg2 then
        self:ScanDel(arg2)
        return true
    elseif arg1 == 'ignore' and arg2 == 'clear' then
        self:IgnoreClear()
        return true
    elseif arg1 == 'ignore' and arg2 == 'list' then
        self:IgnoreList()
        return true
    end

    -- Three arg
    arg1, arg2, arg3 = string.split(' ', arg, 3)

    if arg1 == 'add' and arg2 and arg3 then
        self:ScanAdd(arg2, arg3)
        return true
    elseif arg1 == 'ignore' and arg2 == 'add' then
        self:IgnoreAdd(arg3)
        return true
    elseif arg1 == 'ignore' and arg2 == 'del' then
        self:IgnoreDel(arg3)
        return true
    end

    self:PrintHelp()
    return true
end

function TradeWhisperMixin:SetupSlashCommand()
    SlashCmdList['TradeWhisper'] = function (...) self:SlashCommand(...) end
    _G.SLASH_TradeWhisper1 = "/tradewhisper"
    _G.SLASH_TradeWhisper2 = "/tw"
end

local function FindMatchingLink(chatMsgText, text)
    for link in chatMsgText:gmatch([[|c.-|H.-|h.-|h|r]]) do
        if link:lower():find(text) then
            return link
        end
        local item = Item:CreateFromItemLink(link)
        if item and not Item:IsItemEmpty() and Item:IsItemDataCached() then
            if item:GetItemName():lower():find(text) then
                return link
            end
        end
    end
end

function TradeWhisperMixin:PlayerOnConnectedRealm(playerName)
    local _, playerRealm = string.split('-', playerName)
    if not playerRealm then
        return true
    elseif tContains(self.validRealms, playerRealm) then
        return true
    else
        return false
    end
end

local function GetNameAndRealm(playerName)
    if playerName:find('-') then
        return playerName
    else
        return playerName .. '-' .. GetRealmName()
    end
end

function TradeWhisperMixin:IsIgnoredSender(playerName)
    playerName = GetNameAndRealm(playerName)
    return self:IsMe(playerName) or self.db.tradeIgnore[playername] ~= nil
end

function TradeWhisperMixin:IgnoreAdd(playerName)
    playerName = GetNameAndRealm(playerName)
    self.db.tradeIgnore[playerName] = true
end

function TradeWhisperMixin:IgnoreDel(playerName)
    playerName = GetNameAndRealm(playerName)
    self.db.tradeIgnore[playerName] = nil
end

function TradeWhisperMixin:IgnoreClear()
    table.wipe(self.db.tradeIgnore)
end

function TradeWhisperMixin:IgnoreList()
    printf("Ignore list:")
    if next(self.db.tradeIgnore) then
        local names = GetKeysArray(self.db.tradeIgnore)
        table.sort(names)
        for i, name in ipairs(names) do
            printf("%d. %s", i, name)
        end
    else
        printf("   None.")
    end
end

function TradeWhisperMixin:IsMe(name)
    return name == self.playerName
end

function TradeWhisperMixin:GetWhisperMessage(link, crafter)
    local msg = 'I can craft ' .. link .. ', guaranteed 5* with 3* mats.'
    if self:IsMe(crafter) then
        return msg .. " Send to this toon if interested."
    else
        return msg .. " Send to my alt " .. crafter .. " if interested."
    end
end

function TradeWhisperMixin:CHAT_MSG_CHANNEL(...)
    local zoneChannelID = select(7, ...)
    if zoneChannelID ~= 2 then return end

    local chatMsgText, chatMsgSender = ...
    if not self:PlayerOnConnectedRealm(chatMsgSender) then return end
    if self:IsIgnoredSender(chatMsgSender) then return end

    for text, crafter in pairs(self.db.tradeScan) do
        if chatMsgText:lower():find(text) then
            local link = FindMatchingLink(chatMsgText, text) or text
            local msg = self:GetWhisperMessage(link, crafter)
            self:Open(msg, chatMsgSender)
            printf("%s : %s", chatMsgSender, chatMsgText)
            PlaySound(11466)
        end
    end
end

function TradeWhisperMixin:ScanList()
    printf("Scan for trade:")
    if next(self.db.tradeScan) then
        local texts = GetKeysArray(self.db.tradeScan)
        table.sort(texts)
        for i, text in ipairs(texts) do
            printf("%d. %s : %s", i, self.db.tradeScan[text], text)
        end
    else
        printf("   None.")
    end
end

function TradeWhisperMixin:ScanClear()
    self.db.tradeScan = table.wipe(self.db.tradeScan)
    self:UpdateScanning()
end

function TradeWhisperMixin:ScanAdd(playerName, text)
    if not text or text == '' then
        return
    end

    playerName = GetNameAndRealm(playerName)

    if text:find('|H.-|h') then
        -- Remove the quality texture part
        text = text:gsub(' ?|A.-|a', '')
        for itemText in text:gmatch('|H.-|h%[(.-)%]') do
            itemText = itemText:lower()
            self.db.tradeScan[itemText] = playerName
        end
    else
        text = text:lower()
        self.db.tradeScan[text] = playerName
    end
    self:UpdateScanning()
end

function TradeWhisperMixin:ScanDel(text)
    local n = tonumber(text)
    if n then
        local keys = GetKeysArray(self.db.tradeScan)
        table.sort(keys)
        self.db.tradeScan[keys[n]] = nil
    else
        self.db.tradeScan[text:lower()] = nil
    end
    self:UpdateScanning()
end

function TradeWhisperMixin:UpdateScanning()
    if next(self.db.tradeScan) then
        self:RegisterEvent("CHAT_MSG_CHANNEL")
    else
        self:UnregisterEvent("CHAT_MSG_CHANNEL")
    end
end

function TradeWhisperMixin:OnEvent(e, ...)
    if self[e] then self[e](self, ...) end
end

function TradeWhisperMixin:OnLoad()
    self:RegisterEvent('PLAYER_LOGIN')
    self:SetTitle(addOnName)
end

function TradeWhisperMixin:OnHide()
    self.Message:SetText('')
    self.Recipient:SetText('')
end

function TradeWhisperMixin:SendWhisper()
    SendChatMessage(self.Message:GetText(), "WHISPER", nil, self.Recipient:GetText())
    self:Hide()
end

function TradeWhisperMixin:Open(message, recipient)
    self.Message:SetText(message or "")
    self.Recipient:SetText(recipient or "")
    self:Show()
end

function TradeWhisperMixin:PLAYER_LOGIN()
    printf('Initialized.')

    self.playerName = string.format('%s-%s', UnitFullName('player'))
    self.validRealms = GetAutoCompleteRealms()

    TradeWhisperDB = TradeWhisperDB or {}
    self.db = TradeWhisperDB

    self.db.tradeScan = self.db.tradeScan or {}
    self.db.tradeIgnore = self.db.tradeIgnore or {}

    self:SetupSlashCommand()
    self:UpdateScanning()
end
