function onInit()
    Interface.onDesktopInit = onDesktopInit;
end

local _npcNamesToPortraitMap = {};
local _charsheetNamesToPortraitMap = {};

function onDesktopInit()
    if User.isLocal() or User.isHost() then
        ChatManager.registerDeliverMessageCallback(insertNpcPortraits)
        -- Call change handler for all existing NPCs and charsheets at startup to create the dummy portraits (for NPCs) and map the names (for both)
        for _, npc_node in pairs(DB.getChildren("npc")) do
            handleNPCAdded(npc_node.getParent(), npc_node)
        end
        for _, pc_node in pairs(DB.getChildren("charsheet")) do
            handleCharsheetAdded(pc_node.getParent(), pc_node)
        end
        -- Add DB onChildAdded handlers
        DB.addHandler(".npc", "onChildAdded", handleNPCAdded)
        DB.addHandler(".charsheet", "onChildAdded", handleCharsheetAdded)
    end
end

function handleNPCAdded(nodeParent, nodeChildAdded)
    DB.addHandler(nodeChildAdded.getNodeName()..".name", "onUpdate", handleNPCNameChanged)
    DB.addHandler(nodeChildAdded.getNodeName()..".token", "onUpdate", handleTokenChanged)
    DB.addHandler(nodeChildAdded.getNodeName(), "onDelete", removeNPCNameMapping)
    createDummyPortrait(nodeChildAdded, DB.getValue(nodeChildAdded, "token"))
    local name = DB.getValue(nodeChildAdded, "name", "")
    if not (name == "") then
        addNPCNameMapping(nodeChildAdded, name)
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

function handleCharsheetNameChanged(nameNode)
    local charsheet_node = nameNode.getParent()
    local pc_name = nameNode.getValue()
    removeCharsheetNameMapping(charsheet_node)
    addCharsheetNameMapping(charsheet_node, pc_name)
end

function removeNPCNameMapping(npc_node)
    removeNameMapping(_npcNamesToPortraitMap, npc_node)
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
    _npcNamesToPortraitMap[npc_name] = npc_node
end

function addCharsheetNameMapping(charsheet_node, pc_name)
    _charsheetNamesToPortraitMap[pc_name] = charsheet_node
end


function getNPCByName(name)
    return _npcNamesToPortraitMap[name]
end

function getCharsheetByName(name)
    return _charsheetNamesToPortraitMap[name]
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
            Debug.chat("Bad token found in NPC " .. DB.getValue(npc_node, "name") .. " with token path: " .. tokenStr)
        end
        -- Fortunately, portraits associated with deleted charsheets are only cleaned up at exit. So the dummy charsheet can be deleted here and the portrait will still work
        DB.deleteNode(dummy_node)
    end
end

function formatDynamicPortraitName(npc_node)
    return "dummy_portrait_".. npc_node.getParent().getName() .. "_" .. npc_node.getName()
end

function insertNpcPortraits(msg, sMode)
    if sMode == "chat" then
        local gmid, isgm = GmIdentityManager.getCurrent();
        if isgm == nil then
            local npc_node = getNPCByName(gmid)
            if not(npc_node == nil) then
                -- If a matching NPC is found, set the msg icon to the name of the dummy portrait created for the NPC
                local npc_icon = DB.getValue(npc_node, "token", "")
                if (npc_icon or "") ~= "" then
                    msg.icon = "portrait_" .. formatDynamicPortraitName(npc_node).. "_chat"
                end
            else
                -- If a matching NPC is not found, check if a PC is found and immitate them
                local player_node = getCharsheetByName(gmid)
                if player_node and player_node.getName() then
                    msg.icon = "portrait_" .. player_node.getName() .. "_chat";
                    msg.font = "chatfont"
                end
            end
        end
    end
end