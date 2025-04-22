--[[----------------------------------------------------------------------------

  TradeWhisper

----------------------------------------------------------------------------]]--

local addOnName, addOnTable = ...

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")
local Chomp = LibStub("Chomp")

local printTag = ORANGE_FONT_COLOR:WrapTextInColorCode(addOnName .. ": ")

local function printf(fmt, ...)
    local msg = string.format(fmt, ...)
    SELECTED_CHAT_FRAME:AddMessage(printTag .. msg)
end

--[[------------------------------------------------------------------------]]--

TradeWhisperMixin = {}

function TradeWhisperMixin:PrintHelp()
    printf("Usage:")
    printf("  /tw add playerName text | itemlinks")
    printf("  /tw del text | index")
    printf("  /tw clear")
    printf("  /tw list")
    printf("  /tw ignore add playerName[-Realm]")
    printf("  /tw ignore del playerName[-Realm]")
    printf("  /tw ignore clear")
    printf("  /tw ignore list")
    printf("  /tw opt")
    printf("  /tw scan")
    printf("  /tw show")
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
    elseif arg == 'opt' then
        LibStub("AceConfigDialog-3.0"):Open(addOnName)
        return true
    elseif arg == 'show' then
        self:Show()
        return true
    elseif arg == 'scan' then
        self:ScanOpenTradeSkill()
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

function TradeWhisperMixin:ReceiveComms(prefix, message, distribution, sender)
    local isValid, data = self:DecodeDB(message)
    DevTools_Dump(data)
end

function TradeWhisperMixin:SendDatabase(recipient)
    local messageOptions = {
        serialize = false,
        binaryBlob = true
    }
    local message = self:ExportDB()
    Chomp.SmartAddonMessage(addOnName, message, "WHISPER", recipient, messageOptions)
end

function TradeWhisperMixin:ScanOpenTradeSkill()
    local function GetBestItemID(reagents)
       local bestItemID, bestQuality
       for _, r in ipairs(reagents) do
          local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(r.itemID)
          if not bestQuality or quality > bestQuality then
             bestQuality, bestItemID = quality, r.itemID
          end
       end
       return bestItemID
    end

    local allowedDataSlotTypes = {
       -- [Enum.TradeskillSlotDataType.Reagent] = true,
       [Enum.TradeskillSlotDataType.ModifiedReagent] = true,
    }

    local allowedReagentTypes = {
       [Enum.CraftingReagentType.Basic] = true,
       [Enum.CraftingReagentType.Finishing] = true,
    }

    local function ShouldUseReagent(rss)
       if not allowedDataSlotTypes[rss.dataSlotType] then
          return false
       elseif not allowedReagentTypes[rss.reagentType] then
          return false
       else
          return true
       end
    end

    local function CreateBestReagentsTable(recipeID)
       local out = {}
       local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
       for i, rss in ipairs(schematic.reagentSlotSchematics) do
          if ShouldUseReagent(rss) then
             local itemID = GetBestItemID(rss.reagents)
             local info = Professions.CreateCraftingReagentInfo(itemID, rss.dataSlotIndex, rss.quantityRequired)
             table.insert(out, info)
          end
       end
       return out
    end

    local allowItemClass = {
       [Enum.ItemClass.Armor] = true,
       [Enum.ItemClass.Weapon] = true,
       [Enum.ItemClass.Profession] = true,
    }

    local function ShouldScanRecipe(recipeID)
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if recipeInfo.learned == false then
            return false
        end
        local profInfo = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
        local link = C_TradeSkillUI.GetRecipeItemLink(recipeID)
        local classID, subClassID = select(6, C_Item.GetItemInfoInstant(link))
        if profInfo.expansionName ~= "Khaz Algar" then
            return false
        end
        if not allowItemClass[classID] then
            return false
        end
        return true
    end

    local function ScanRecipe(recipeID)
        local reagents = CreateBestReagentsTable(recipeID)
        local opInfo = C_TradeSkillUI.GetCraftingOperationInfo(recipeID, reagents, nil, false)
        if opInfo and opInfo.baseDifficulty == opInfo.lowerSkillThreshold then
            return C_TradeSkillUI.GetRecipeItemLink(recipeID)
        end
    end

    local allRecipes = C_TradeSkillUI.GetAllRecipeIDs()

    for _, recipeID in ipairs(allRecipes) do
        if ShouldScanRecipe(recipeID) then
            local link = ScanRecipe(recipeID)
            if link then
                local item = Item:CreateFromItemLink(link)
                item:ContinueOnItemLoad(
                    function ()
                        self:ScanAdd(self.playerName, item:GetItemName())
                    end)
            end
        end
    end
end

local function FindMatchingLink(chatMsgText, text)
    for link in chatMsgText:gmatch([[|c.-|H.-|h.-|h|r]]) do
        if link:lower():find(text, nil, true) then
            return link
        end
        local item = Item:CreateFromItemLink(link)
        if item and not item:IsItemEmpty() and item:IsItemDataCached() then
            if item:GetItemName():lower():find(text, nil, true) then
                return link
            end
        end
    end
end

local function GetNameAndRealm(playerName)
    if playerName:find('-', nil, true) then
        return playerName
    else
        return playerName .. '-' .. GetRealmName()
    end
end

local function GetRealm(playerName)
    local _, realm = string.split('-', playerName)
    return realm or GetRealmName()
end


function TradeWhisperMixin:ValidCustomer(customerName, crafterName)
    local customerRealm = GetRealm(customerName)
    local crafterRealm = GetRealm(crafterName)
    return tContains(self.db.global.connectedRealms[crafterRealm] or {}, customerRealm)
end

function TradeWhisperMixin:IsCurrentCustomer(playerName)
    playerName = GetNameAndRealm(playerName)
    return playerName == GetNameAndRealm(self.Recipient:GetText())
end

function TradeWhisperMixin:IsRecentCustomer(playerName, seconds)
    playerName = GetNameAndRealm(playerName)
    local now = time()
    for i, info in ipairs_reverse(self.db.global.chatHistory) do
        local msgTime, _, _, _, msgPlayer = unpack(info)
        if seconds == 0 then
            return true
        elseif msgTime < now - seconds then
            break
        elseif msgPlayer == playerName then
            return true
        end
    end
    return false
end

function TradeWhisperMixin:IsIgnoredSender(playerName)
    playerName = GetNameAndRealm(playerName)
    return self:IsMe(playerName) or self.db.global.tradeIgnore[playerName] ~= nil
end

function TradeWhisperMixin:IgnoreAdd(playerName)
    playerName = GetNameAndRealm(playerName)
    self.db.global.tradeIgnore[playerName] = true
end

function TradeWhisperMixin:IgnoreDel(playerName)
    playerName = GetNameAndRealm(playerName)
    self.db.global.tradeIgnore[playerName] = nil
end

function TradeWhisperMixin:IgnoreClear()
    table.wipe(self.db.global.tradeIgnore)
end

function TradeWhisperMixin:IgnoreList()
    printf("Ignore list:")
    if next(self.db.global.tradeIgnore) then
        local names = GetKeysArray(self.db.global.tradeIgnore)
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

function TradeWhisperMixin:GetWhisperMessage(item, crafter)
    local repl = {
        item = item,
        crafter = self:IsMe(crafter) and "this character" or "my alt "..crafter,
    }
    return self.db.global.message:gsub('{(.-)}', repl)
end

function TradeWhisperMixin:AddChatHistory(...)
    -- Timestamps are only 1s granularity, so add an order received so that we
    -- can sort them later and preserve the order correctly.

    local n = #self.db.global.chatHistory + 1
    if select('#', ...) == 3 then
        data = { time(), n, ... }
    else
        local msgTime = ...
        data = { msgTime, n, select(3, ...) }
    end
    table.insert(self.db.global.chatHistory, data)
end

function TradeWhisperMixin:CHAT_MSG_CHANNEL(...)
    local zoneChannelID = select(7, ...)
    if zoneChannelID ~= 2 then return end

    local chatMsgText, chatMsgSender = ...
    if self:IsIgnoredSender(chatMsgSender) then return end

    for text, crafter in pairs(self.db.global.tradeScan) do
        if chatMsgText:lower():find(text, nil, true) and self:ValidCustomer(chatMsgSender, crafter) then
            local link = FindMatchingLink(chatMsgText, text) or text
            local reply = self:GetWhisperMessage(link, crafter)
            self:AddChatHistory('CHANNEL', chatMsgText, chatMsgSender)
            self:Open(chatMsgSender, reply)
            PlaySound(11466)
            return
        end
    end
end

function TradeWhisperMixin:ScanList()
    printf("Scan for trade:")
    if next(self.db.global.tradeScan) then
        local texts = GetKeysArray(self.db.global.tradeScan)
        table.sort(texts)
        for i, text in ipairs(texts) do
            printf("%d. %s : %s", i, self.db.global.tradeScan[text], text)
        end
    else
        printf("   None.")
    end
end

function TradeWhisperMixin:ScanClear()
    self.db.global.tradeScan = table.wipe(self.db.global.tradeScan)
    self:UpdateScanning()
end

function TradeWhisperMixin:ScanAdd(playerName, text)
    if not text or text == '' then
        return
    end

    if not playerName:sub(1,1):match('[A-Z]') then
        printf("Error: %s : player name must start with a capital letter.", playerName)
        return
    elseif playerName:find("[^-'A-Za-z]") then
        printf("Error: %s : player name contains invalid letters.", playerName)
        return
    end

    playerName = GetNameAndRealm(playerName)

    if text:find('|H.-|h') then
        -- Remove the quality texture part
        text = text:gsub(' ?|A.-|a', '')
        for itemText in text:gmatch('|H.-|h%[(.-)%]') do
            itemText = itemText:lower()
            self.db.global.tradeScan[itemText] = playerName
        end
    else
        text = text:lower()
        self.db.global.tradeScan[text] = playerName
    end
    self:UpdateScanning()
end

function TradeWhisperMixin:ScanDel(text)
    local n = tonumber(text)
    if n then
        local keys = GetKeysArray(self.db.global.tradeScan)
        table.sort(keys)
        self.db.global.tradeScan[keys[n]] = nil
    else
        self.db.global.tradeScan[text:lower()] = nil
    end
    self:UpdateScanning()
end

function TradeWhisperMixin:UpdateScanning()
    if next(self.db.global.tradeScan) then
        self:RegisterEvent("CHAT_MSG_CHANNEL")
    else
        self:UnregisterEvent("CHAT_MSG_CHANNEL")
    end
end

function TradeWhisperMixin:OnEvent(e, ...)
    if self[e] then self[e](self, ...) end
end

TradeWhisperRecipientHistoryDropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin)

function TradeWhisperRecipientHistoryDropdownMixin:OnButtonStateChanged()
    local atlas = GetWowStyle1ArrowButtonState(self)
    self.Texture:SetAtlas(atlas, true)
end

local function IsSelected(playerName)
    return playerName == TradeWhisper.Recipient:GetText()
end

local function SetSelected(playerName)
    TradeWhisper.Recipient:SetText(playerName)
end

function TradeWhisperRecipientHistoryDropdownMixin:OnLoad()
    ButtonStateBehaviorMixin.OnLoad(self)

    self:SetupMenu(
        function(dropdown, rootDescription)
            local customerList = TradeWhisper:GetCustomerList()
            rootDescription:SetTag("Recipients")
            rootDescription:SetScrollMode(300)
            for _,playerName in ipairs(customerList) do
                rootDescription:CreateRadio(playerName, IsSelected, SetSelected, playerName)
            end
        end)
end

function TradeWhisperMixin:OnLoad()
    self.Conversation:SetFading(false)
    self.Conversation:SetMaxLines(128)
    self.Conversation:SetFontObject(ChatFontNormal)
    self.Conversation:SetTextColor(1, 0.5, 1)
    self.Conversation:SetIndentedWordWrap(true)
    self.Conversation:SetJustifyH("LEFT")
    ScrollUtil.InitScrollingMessageFrameWithScrollBar(self.Conversation, self.Conversation.ScrollBar)
    self.Message.EditBox:SetFontObject(ChatFontNormal)
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("CHAT_MSG_WHISPER")
    self:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
    self:RegisterEvent("CRAFTINGORDERS_DISPLAY_CRAFTER_FULFILLED_MSG")
    self:RegisterEvent("CRAFTINGORDERS_UPDATE_PERSONAL_ORDER_COUNTS")
    C_ChatInfo.RegisterAddonMessagePrefix(addOnName)
    self:SetTitle(addOnName)
end

function TradeWhisperMixin:OnShow()
    self:UpdateConversation()
end

function TradeWhisperMixin:OnHide()
end

function TradeWhisperMixin:SendWhisper()
    SendChatMessage(self.Message.EditBox:GetText(), "WHISPER", nil, self.Recipient:GetText())
    self.Message.EditBox:SetText('')
end

function TradeWhisperMixin:UpdateConversation()
    local conversationMessages = {}
    for i = #self.db.global.chatHistory, 1, -1 do
        local msgTime, _, msgType, msgText, msgPlayer = unpack(self.db.global.chatHistory[i])
        if self:IsCurrentCustomer(msgPlayer) then
            local timeStamp = BetterDate("%Y-%m-%d %H:%M:%S", msgTime)
            local text
            if msgType == 'WHISPER_INFORM' then
                text = string.format("%s To [%s] %s", timeStamp, msgPlayer, msgText)
            elseif msgType == 'FULFILL' then
                text = string.format("%s %s", timeStamp, msgText)
            else
                text = string.format("%s [%s] %s", timeStamp, msgPlayer, msgText)
            end
            table.insert(conversationMessages, 1, text)
            if #conversationMessages >= 128 then break end
        end
    end
    self.Conversation:Clear()
    for _, text in ipairs(conversationMessages) do
        self.Conversation:AddMessage(text)
    end
end

function TradeWhisperMixin:Open(chatMsgSender, reply)
    self.Message.EditBox:SetText(reply or "")
    self.Recipient:SetText(chatMsgSender or "")
    if self:IsShown() then
        self:UpdateConversation()
    else
        self:Show()
    end
end

function TradeWhisperMixin:UpdateConnectedRealms()
    for _, r in ipairs(GetAutoCompleteRealms()) do
        self.db.global.connectedRealms[r] = GetAutoCompleteRealms()
    end
end

function TradeWhisperMixin:GetCustomerList()
    local customerLastMessageTimes = {}

    if not self.db then
        return {}
    end

    -- chatHistory is already in chronological order
    for _, info in ipairs(self.db.global.chatHistory) do
        local msgTime, _, _, _, msgPlayer = unpack(info)
        customerLastMessageTimes[msgPlayer] = msgTime
    end

    local customerList = GetKeysArray(customerLastMessageTimes)
    table.sort(customerList,
        function (a, b)
            return customerLastMessageTimes[a] > customerLastMessageTimes[b]
        end)
    return customerList
end

local defaults = {
    global = {
        message = "I can craft {item} on {crafter}. Max spec, guaranteed 5* with 3* mats",
        tradeScan = {},
        tradeIgnore = {},
        chatHistory = {},
        connectedRealms = {},
    }
}

function TradeWhisperMixin:PLAYER_LOGIN()
    printf('Initialized.')

    if TradeWhisperDB and TradeWhisperDB.tradeScan then
        TradeWhisperDB.global = TradeWhisperDB.global or {}
        TradeWhisperDB.global.tradeScan = TradeWhisperDB.tradeScan
    end

    self.db = LibStub("AceDB-3.0"):New("TradeWhisperDB", defaults, true)

    self.playerName = string.format('%s-%s', UnitFullName('player'))
    self.validRealms = GetAutoCompleteRealms()
    self.loginTime = time()

    Chomp.RegisterAddonPrefix(addOnName, function (...) self:ReceiveComms(...) end)

    self:UpdateConnectedRealms()
    self:UpdatePersonalOrders()
    self:SetupSlashCommand()
    self:UpdateScanning()
end

function TradeWhisperMixin:CHAT_MSG_WHISPER(text, remoteName)
    remoteName = GetNameAndRealm(remoteName)
    if self:IsRecentCustomer(remoteName, 600) then
        self:AddChatHistory('WHISPER', text, remoteName)
        self:UpdateConversation()
    end
end

function TradeWhisperMixin:CHAT_MSG_WHISPER_INFORM(text, remoteName)
    remoteName = GetNameAndRealm(remoteName)
    local secondsSinceLogin = time() - self.loginTime
    if self:IsRecentCustomer(remoteName, math.max(secondsSinceLogin, 600)) then
        self:AddChatHistory('WHISPER_INFORM', text, remoteName)
        self:UpdateConversation()
    end
end

-- Log all of these all the time, because I'm mostly doing them on another
-- toon and without the whisper window open.
function TradeWhisperMixin:CRAFTINGORDERS_DISPLAY_CRAFTER_FULFILLED_MSG(...)
    local orderType, itemName, playerName, tipAmount, quantityCrafted = ...
    if orderType == PROF_CRAFTING_ORDER_TYPE_PERSONAL then
        playerName = GetNameAndRealm(playerName)
        local money = GetMoneyString(tipAmount, true)
        local msg
        if quantityCrafted > 1 then
            local fmt = CRAFTING_ORDERS_ORDER_FULFILLED_MULT_FMT
            msg = fmt:format(orderType, itemName, playerName, quantityCrafted, money)
        else
            local fmt = CRAFTING_ORDERS_ORDER_FULFILLED_SINGLE_FMT
            msg = fmt:format(orderType, itemName, playerName, money)
        end
        self:AddChatHistory('FULFILL', msg, playerName)
        self:UpdateConversation()
    end
end

function TradeWhisperMixin:UpdatePersonalOrders()
    local prevCount = self.personalOrderCount or 0
    self.personalOrderCount = #C_CraftingOrders.GetPersonalOrdersInfo()
    if self.personalOrderCount > prevCount then
        PlaySoundFile(1313269)
    end
end

function TradeWhisperMixin:CRAFTINGORDERS_UPDATE_PERSONAL_ORDER_COUNTS()
    self:UpdatePersonalOrders()
end

function TradeWhisperMixin:ExportDB()
    local serialized = AceSerializer:Serialize({
            global = self.db.sv.global,
            profiles = self.db.sv.profiles,
            char = self.db.sv.char,
        })
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForPrint(compressed)
    return encoded
end

-- We can't reload an AceDB in any way so we have to replace any table keys for
-- tables that already exist and hope for the best.

local function TableAppend(t1, t2)
    for _,v in ipairs(t2) do table.insert(t1, v) end
end

-- Note that this will do bad things with indexed arrays.

local function MixinRecursive(object, ...)
    for i = 1, select("#", ...) do
        local mixin = select(i, ...)
        for k, v in pairs(mixin) do
            if type(v) == 'table' and type(object[k]) == 'table' then
                MixinRecursive(object[k], v)
            else
                object[k] = v
            end
        end
    end
    return object
end

function TradeWhisperMixin:DecodeDB(encoded)
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then return end

    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then return end

    local isValid, data = AceSerializer:Deserialize(serialized)
    return isValid, data
end

function TradeWhisperMixin:ImportDB(encoded)
    local isValid, data = self:DecodeDB(encoded)

    if not isValid then return end

    Mixin(self.db.sv.global.tradeScan, data.global.tradeScan)
    Mixin(self.db.sv.global.tradeIgnore, data.global.tradeIgnore)
    Mixin(self.db.sv.global.connectedRealms, data.global.connectedRealms)

    -- Chat history merge, bit complicated trying to keep it sorted etc.
    TableAppend(self.db.sv.global.chatHistory, data.global.chatHistory)

    -- local msgTime, n, msgType, msgText, msgPlayer = unpack(a)
    local function chComp(a, b)
        if a[1] == b[1] then
            return a[2] < b[2]
        else
            return a[1] < b[1]
        end
    end
    table.sort(self.db.sv.global.chatHistory, chComp)
    for i, t in ipairs(self.db.sv.global.chatHistory) do
        t[2] = i
    end
end
