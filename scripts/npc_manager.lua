function onInit()
    Interface.onDesktopInit = onDesktopInit;
end

local _npcNamesToPortraitMap = {};
local _npcNonIdNamesToPortraitMap = {};
local _charsheetNamesToPortraitMap = {};
local _customDataTypes = {}
local _orgCreateBaseMessage = nil
local _debugMode = false

function debugPrint(fCall, fIdx, msg)
    msg = fCall .. ":" .. fIdx .. " | " .. tostring(msg)
    if _debugMode then
        Debug.chat(msg)
    else
        Debug.console(msg)
    end
end

function onDesktopInit()
    debugPrint("onDesktopInit", 1, (User.isLocal() or User.isHost()))
    if User.isLocal() or User.isHost() then
        ChatManager.registerDeliverMessageCallback(insertNpcPortraits)
        _orgCreateBaseMessage = ChatManager.createBaseMessage
        ChatManager.createBaseMessage = createBaseMessage
        -- Call change handler for all existing NPCs and charsheets at startup to create the dummy portraits (for NPCs) and map the names (for both)
        for _, npc_node in pairs(DB.getChildren("npc")) do
            debugPrint("onDesktopInit", 2, npc_node.getNodeName())
            handleNPCAdded(npc_node.getParent(), npc_node)
        end
        for _, pc_node in pairs(DB.getChildren("charsheet")) do
            debugPrint("onDesktopInit", 3, pc_node.getNodeName())
            handleCharsheetAdded(pc_node.getParent(), pc_node)
        end
        -- Add DB onChildAdded handlers
        DB.addHandler(".npc", "onChildAdded", handleNPCAdded)
        DB.addHandler(".charsheet", "onChildAdded", handleCharsheetAdded)
    end
    self.addCustomRecordTypes()
end

function addCustomRecordTypes()
    for _, dataType in ipairs(_customDataTypes) do
        for _, dataNode in pairs(DB.getChildren(dataType)) do
            handleNPCAdded(dataNode.getParent(), dataNode)
        end
    end
end

function registerDataType(dataType)
    table.insert(_customDataTypes, dataType)
end

function handleNPCAdded(nodeParent, nodeChildAdded)
    DB.addHandler(nodeChildAdded.getNodeName()..".name", "onUpdate", handleNPCNameChanged)
    DB.addHandler(nodeChildAdded.getNodeName()..".nonid_name", "onUpdate", handleNPCNonIdNameChanged)
    DB.addHandler(nodeChildAdded.getNodeName()..".token", "onUpdate", handleTokenChanged)
    DB.addHandler(nodeChildAdded.getNodeName(), "onDelete", removeNPCNameMapping)
    createDummyPortrait(nodeChildAdded, DB.getValue(nodeChildAdded, "token"))
    local name = DB.getValue(nodeChildAdded, "name", "")
    if not (name == "") then
        addNPCNameMapping(nodeChildAdded, name)
    end
    local nonid_name = DB.getValue(nodeChildAdded, "nonid_name", "")
    if not (nonid_name == "") then
        addNPCNonIdNameMapping(nodeChildAdded, nonid_name)
    end
end

function handleCharsheetAdded(nodeParent, nodeChildAdded)
    DB.addHandler(nodeChildAdded.getNodeName()..".name", "onUpdate", handleCharsheetNameChanged)
    DB.addHandler(nodeChildAdded.getNodeName(), "onDelete", removeCharsheetNameMapping)
    local name = DB.getValue(nodeChildAdded, "name", "")
    if not (name == "") then
        addCharsheetNameMapping(nodeChildAdded, name)
    end
end

function handleNPCNameChanged(nameNode)
    local npc_node = nameNode.getParent()
    local npc_name = nameNode.getValue()
    removeNPCNameMapping(npc_node)
    addNPCNameMapping(npc_node, npc_name)
end

function handleNPCNonIdNameChanged(nameNode)
    local npc_node = nameNode.getParent()
    local npc_name = nameNode.getValue()
    removeNPCNonIdNameMapping(npc_node)
    addNPCNonIdNameMapping(npc_node, npc_name)
end

function handleCharsheetNameChanged(nameNode)
    local charsheet_node = nameNode.getParent()
    local pc_name = nameNode.getValue()
    removeCharsheetNameMapping(charsheet_node)
    addCharsheetNameMapping(charsheet_node, pc_name)
end

function removeNPCNameMapping(npc_node)
    removeNameMapping(_npcNamesToPortraitMap, npc_node)
end

function removeNPCNonIdNameMapping(npc_node)
    removeNameMapping(_npcNonIdNamesToPortraitMap, npc_node)
end

function removeCharsheetNameMapping(charsheet_node)
    removeNameMapping(_charsheetNamesToPortraitMap, charsheet_node)
end

function removeNameMapping(nameMap, mappedNode)
    for name, node in pairs(nameMap) do
        if node == mappedNode then
            nameMap[name] = nil
            break
        end
    end
end

function addNPCNameMapping(npc_node, npc_name)
    if (npc_name or "") ~= "" then
        _npcNamesToPortraitMap[npc_name] = npc_node
    end
    debugPrint("addNPCNameMapping", 1, npc_name)
    debugPrint("addNPCNameMapping", 2, npc_node.getNodeName())
end

function addNPCNonIdNameMapping(npc_node, npc_name)
    if (npc_name or "") ~= "" then
        _npcNonIdNamesToPortraitMap[npc_name] = npc_node
    end
    debugPrint("addNPCNonIdNameMapping", 1, npc_name)
    debugPrint("addNPCNaaddNPCNonIdNameMappingmeMapping", 2, npc_node.getNodeName())
end

function addCharsheetNameMapping(charsheet_node, pc_name)
    _charsheetNamesToPortraitMap[pc_name] = charsheet_node
end

function getNPCByName(name)
    if (_npcNamesToPortraitMap[name] or "") ~= "" then
        return _npcNamesToPortraitMap[name]
    elseif (_npcNonIdNamesToPortraitMap[name] or "") ~= "" then
        return _npcNonIdNamesToPortraitMap[name]
    end
    return nil
end
function getCharsheetByName(name)
    return _charsheetNamesToPortraitMap[name]
end

function handleTokenChanged(tokenNode)
    createDummyPortrait(tokenNode.getParent(), DB.getValue(tokenNode, ""))
end

-- CampaignDataManager.setCharPortrait is the only way I have found to generate a portrait set. So a dummy charsheet has to be created
function createDummyPortrait(npc_node, tokenStr)
    debugPrint("createDummyPortrait", 1, npc_node.getNodeName())
    debugPrint("createDummyPortrait", 2, tokenStr)
    if (tokenStr or "") ~= "" then
        local npc_ident = formatDynamicPortraitName(npc_node)
        local dummy_node = DB.createChild("charsheet", npc_ident)
        if not (pcall(CampaignDataManager.setCharPortrait, dummy_node, tokenStr)) then
            debugPrint("createDummyPortrait", 3, "Bad token found in NPC " .. DB.getValue(npc_node, "name") .. " with token path: " .. tokenStr)
        end
        -- Fortunately, portraits associated with deleted charsheets are only cleaned up at exit. So the dummy charsheet can be deleted here and the portrait will still work
        debugPrint("createDummyPortrait", 4, dummy_node.getNodeName())
        DB.deleteNode(dummy_node)
    end
end

function formatDynamicPortraitName(npc_node)
    return "dummy_portrait_".. npc_node.getParent().getName() .. "_" .. npc_node.getName()
end

function getPortraitByName(sName)
    local portrait = "portrait_gm_token"
    local isPlayer = false
    debugPrint("getPortraitByName", 1, Name)
    if (sName or "") ~= "" then
        local npc_node = getNPCByName(sName)
        if not(npc_node == nil) then
            debugPrint("getPortraitByName", 2, npc_node.getNodeName())
            -- If a matching NPC is found, set the msg icon to the name of the dummy portrait created for the NPC
            local npc_icon = DB.getValue(npc_node, "token", "")
            debugPrint("getPortraitByName", 3, npc_icon)
            if (npc_icon or "") ~= "" then
                portrait = "portrait_" .. formatDynamicPortraitName(npc_node).. "_chat"
            end
            debugPrint("getPortraitByName", 4, portrait)
        else
            -- If a matching NPC is not found, check if a PC is found and immitate them
            local player_node = getCharsheetByName(sName)
            if player_node and player_node.getName() then
                portrait = "portrait_" .. player_node.getName() .. "_chat";
                isPlayer = true
            end
        end
    end
    return portrait, isPlayer
end

function getMessageSource(msg)
    local gmid = ""
    local isgm = false
    if (msg.sender or GmIdentityManager.getGMIdentity()) ~= GmIdentityManager.getGMIdentity() then
        gmid = msg.sender
    else
        gmid, isgm = GmIdentityManager.getCurrent();
    end
    return gmid, isgm
end

function createBaseMessage(rSource, sUser)
    local orgMessage = _orgCreateBaseMessage(rSource, sUser)
    insertPortraitToMessage(orgMessage)
    return orgMessage
end

function insertNpcPortraits(msg, sMode)
    if sMode == "chat" then
        insertPortraitToMessage(msg)
    end
end

function insertPortraitToMessage(msg)
    local gmid, isgm = getMessageSource(msg)
    debugPrint("insertPortraitToMessage", 1, gmid)
    debugPrint("insertPortraitToMessage", 2, isgm)
    if (isgm or "") == "" then
        portrait, isPlayer = getPortraitByName(gmid)
        debugPrint("insertPortraitToMessage", 3, portrait)
        debugPrint("insertPortraitToMessage", 4, isPlayer)
        if (portrait or "") ~= "" then
            msg.icon = portrait
        end
        if isPlayer then
            msg.font = "chatfont"
        end
    end
    return msg
end