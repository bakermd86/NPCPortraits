function onInit()
    Interface.onDesktopInit = onDesktopInit;
end

function onDesktopInit()
    if User.isLocal() or User.isHost() then
        ChatManager.registerDeliverMessageCallback(insertNpcPortraits)
        for _, npc_node in pairs(DB.getChildren("npc")) do
            createDummyPortrait(npc_node, DB.getValue(npc_node, "token"))
            DB.addHandler(npc_node.getNodeName()..".token", "onUpdate", handleTokenChanged)
        end
    end
    DB.addHandler(".npc", "onChildAdded", handleNPCAdded)
end

function handleNPCAdded(nodeParent, nodeChildAdded)
    createDummyPortrait(nodeChildAdded, DB.getValue(nodeChildAdded, "token"))
    DB.addHandler(nodeChildAdded.getNodeName()..".token", "onUpdate", handleTokenChanged)
end

function handleTokenChanged(tokenNode)
    createDummyPortrait(tokenNode.getParent(), DB.getValue(tokenNode, ""))
end

function createDummyPortrait(npc_node, tokenStr)
    if (tokenStr or "") ~= "" then
        local npc_ident = formatDynamicPortraitName(npc_node)
        local dummy_node = DB.createChild("charsheet", npc_ident)
        if not (pcall(CampaignDataManager.setCharPortrait, dummy_node, tokenStr)) then
            Debug.chat("Bad token found in NPC " .. DB.getValue(npc_node, "name") .. " with token path: " .. tokenStr)
        end
        DB.deleteNode(dummy_node)
    end
end

function formatDynamicPortraitName(npc_node)
    return "dummy_portrait_".. npc_node.getParent().getName() .. "_" .. npc_node.getName()
end

function getNPCByName(name)
    for _, node in pairs(DB.getChildren("npc")) do
        if DB.getValue(node, "name") == name then return node end
    end
end

function getCharsheetByName(name)
    for _, node in pairs(DB.getChildren("charsheet")) do
        if DB.getValue(node, "name") == name then return node end
    end
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