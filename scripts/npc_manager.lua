function onInit()
    Interface.onDesktopInit = onDesktopInit;
end

local _npcNamesToPortraitMap = {};
local _npcNonIdNamesToPortraitMap = {};
local _charsheetNamesToPortraitMap = {};
local _rollNodeMap = {}
local _rollNamesMap = {}
local _customDataTypes = {}
local _orgCreateBaseMessage = nil
local _orgSWIDManager = nil

local _swStripPrefix = "[GM] "
swadeRulesetName = "SavageWorlds"

function onDesktopInit()
    if User.isLocal() or User.isHost() then
        ChatManager.registerDeliverMessageCallback(insertNpcPortraits)
        _orgCreateBaseMessage = ChatManager.createBaseMessage
        ChatManager.createBaseMessage = createBaseMessage
        -- Call change handler for all existing CT entries and charsheets at startup to create the dummy
        -- portraits (for CT entries) and map the names (for both)
        for _, npc_node in pairs(CombatManager.getCombatantNodes()) do
            handleCTEntry(npc_node.getParent(), npc_node)
        end
        for _, pc_node in pairs(DB.getChildren("charsheet")) do
            handleCharsheetAdded(pc_node.getParent(), pc_node)
        end
        -- Add DB onChildAdded handlers
        if User.getRulesetName() == swadeRulesetName then
            DB.addHandler(CombatManager.CT_LIST .. ".*.combatants", "onChildAdded", handleCTEntry)
        else
            DB.addHandler(CombatManager.CT_LIST, "onChildAdded", handleCTEntry)
        end
        DB.addHandler(".charsheet", "onChildAdded", handleCharsheetAdded)
    end
    self.addCustomRecordTypes()
    if User.getRulesetName() == swadeRulesetName then
        _orgSWIDManager = IdentityManagerSW.addIdentity
        IdentityManagerSW.addIdentity = registerSWDId
    end
end

function registerSWDId(name, node, isGm)
    if _orgSWIDManager then
        _orgSWIDManager(name, node, isGm)
    end
    registerIdentity(node, name)
end

function registerIdentity(node, name)
    if (node or "") ~= "" then
        if node.getParent().getName() ~= "charsheet" then
            handleNPCAdded(node.getParent(), node)
        else
            handleCharsheetAdded(node.getParent(), node)
        end
    end
end

function addCustomRecordTypes()
    for _, dataType in ipairs(_customDataTypes) do
        for _, dataNode in pairs(DB.getChildren(dataType)) do
            handleNPCAdded(dataNode.getParent(), dataNode)
        end
        DB.addHandler("."..dataType, "onChildAdded", handleNPCAdded)
    end
end

function registerDataType(dataType)
    table.insert(_customDataTypes, dataType)
end

function handleCTEntry(parentNode, npc_node)
    local class, recordLink = DB.getValue(npc_node, "link")
    if (parentNode.getName() == "charsheet") or (class == "charsheet") then
        return
    end
    DB.addHandler(npc_node.getNodeName()..".token", "onUpdate", handleTokenChanged)
    DB.addHandler(npc_node.getNodeName()..".name", "onUpdate", handleNPCNameChanged)
    DB.addHandler(npc_node.getNodeName()..".nonid_name", "onUpdate", handleNPCNonIdNameChanged)
    DB.addHandler(npc_node.getNodeName(), "onDelete", removeNPCNameMapping)
    local npc_ident = createDummyPortrait(npc_node, DB.getValue(npc_node, "token"))
    _rollNodeMap[npc_node.getNodeName()] = npc_ident
    _rollNamesMap[DB.getValue(npc_node, "name", "")] = npc_node.getNodeName()
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
    local parentName = mappedNode.getParent().getName()
    local parentMap = nameMap[parentName]
    if parentMap == nil then parentMap = {} end
    for name, node in pairs(parentMap) do
        if node == mappedNode then
            nameMap[name] = nil
            break
        end
    end
    nameMap[parentName] = parentMap
end

function addNameMapping(map, name, node)
    if (name or "") ~= "" then
        local parentName = node.getParent().getName()
        local parentMap = map[parentName]
        if parentMap == nil then parentMap = {} end
        parentMap[name] = node
        map[parentName] = parentMap
    end
end

function addNPCNameMapping(npc_node, npc_name)
    if (npc_name or "") ~= "" then
        addNameMapping(_npcNamesToPortraitMap, npc_name, npc_node)
    end
end

function addNPCNonIdNameMapping(npc_node, npc_name)
    if (npc_name or "") ~= "" then
        addNameMapping(_npcNonIdNamesToPortraitMap, npc_name, npc_node)
    end
end

function addCharsheetNameMapping(charsheet_node, pc_name)
    addNameMapping(_charsheetNamesToPortraitMap, pc_name, charsheet_node)
end

function getNPCByName(name)
    for parentName, parentMap in pairs(_npcNamesToPortraitMap) do
        if (parentMap[name] or "") ~= "" then
            return parentMap[name]
        end
    end
    for parentName, parentMap in pairs(_npcNonIdNamesToPortraitMap) do
        if (parentMap[name] or "") ~= "" then
            return parentMap[name]
        end
    end
    if (_rollNamesMap[name] or "") ~= "" then
        if (_rollNodeMap[_rollNamesMap[name]] or "") ~= "" then
            return DB.findNode(_rollNamesMap[name])
        end
    end
    return nil
end

function getCharsheetByName(name)
    for parentName, parentMap in pairs(_charsheetNamesToPortraitMap) do
        if (parentMap[name] or "") ~= "" then
            return parentMap[name]
        end
    end
    return nil
end

function handleTokenChanged(tokenNode)
    createDummyPortrait(tokenNode.getParent(), DB.getValue(tokenNode, ""))
end

-- CampaignDataManager.setCharPortrait is the only way I have found to generate a portrait set. So a dummy charsheet has to be created
function createDummyPortrait(npc_node, tokenStr)
    if (tokenStr or "") ~= "" then
        local npc_ident = formatDynamicPortraitName(npc_node)
        local dummy_node = DB.createChild("charsheet", npc_ident)
        if not (pcall(CampaignDataManager.setCharPortrait, dummy_node, tokenStr)) then
            Debug.console("Bad token found in NPC " .. DB.getValue(npc_node, "name") .. " with token path: " .. tokenStr)
        end
        -- Fortunately, portraits associated with deleted charsheets are only cleaned up at exit. So the dummy charsheet can be deleted here and the portrait will still work
        DB.deleteNode(dummy_node)
        return npc_ident
    end
end

function formatDynamicPortraitName(npc_node)
    return "dummy_portrait_".. string.gsub(string.gsub(npc_node.getNodeName(), "%.", "_"), '[%p%c%s]', "-")
end

function stripRulesetPrefixes(sName)
    if string.sub(sName, 1, 5) == _swStripPrefix then
        sName = string.sub(sName, 6)
    end
    return sName
end

function getPortraitByName(sName)
    local portrait = "portrait_gm_token"
    local isPlayer = false
    if (sName or "") ~= "" then
        sName = stripRulesetPrefixes(sName)
        -- First check if a PC is found and imitate them
        local player_node = getCharsheetByName(sName)
        if player_node and player_node.getName() then
            portrait = "portrait_" .. player_node.getName() .. "_chat";
            isPlayer = true
        else
            -- If a matching PC is not found, check if a matching NPC can be found
            local npc_node = getNPCByName(sName)
            if (npc_node or "") ~= "" then
                local npc_icon = DB.getValue(npc_node, "token", "")
                if (npc_icon or "") ~= "" then
                    portrait = "portrait_" .. formatDynamicPortraitName(npc_node).. "_chat"
                end
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
    insertPortraitToMessage(orgMessage, rSource)
    return orgMessage
end

function insertNpcPortraits(msg, sMode)
    if (sMode == "chat") then
        insertPortraitToMessage(msg, nil)
    elseif (sMode == "" and msg.hasdice) then
        handleRollReveal(msg)
    end
end

function handleRollReveal(msg)
    local rSource = {["sCreatureNode"]=_rollNamesMap[msg.sender]}
    insertPortraitToMessage(msg, rSource)
end

function insertPortraitToMessage(msg, rSource)
    local portrait = ""
    local isPlayer = false
    if ((rSource and rSource.sCreatureNode) or "") ~= "" then
        local sourceNode = DB.findNode(rSource.sCreatureNode)
        isPlayer = sourceNode.getParent().getName() == "charsheet"
        local npc_ident = _rollNodeMap[rSource.sCreatureNode]
        if (npc_ident or "") == "" then
            if isPlayer then
                npc_ident = sourceNode.getName()
            else
                npc_ident = createDummyPortrait(sourceNode, DB.getValue(sourceNode, "token"))
            end
            DB.addHandler(sourceNode.getNodeName()..".token", "onUpdate", handleTokenChanged)
            _rollNodeMap[rSource.sCreatureNode] = npc_ident
        end
        if (npc_ident or "") ~= "" then
            _rollNamesMap[DB.getValue(sourceNode, "name", "")] = rSource.sCreatureNode
            portrait = "portrait_" .. npc_ident .. "_chat"
        end
   else
        local gmid, isgm = getMessageSource(msg)
        if (isgm or "") == "" then
            portrait, isPlayer = getPortraitByName(gmid)
        end
    end
    if (portrait or "") ~= "" then
        msg.icon = portrait
    end
    if isPlayer then
        msg.font = "chatfont"
    end
    return msg
end