--luacheck:no unused

cm:load_global_script "lib.vanish_safe_caller"

out("mod script package.path: " .. package.path)

local function output_faction_forces(faction)
    out(tostring(faction) .. " | " .. cm:campaign_obj_to_string(faction))
    local mf_list = faction:military_force_list()
    for i = 0, mf_list:num_items() - 1 do
        local mf = mf_list:item_at(i)
        out(tostring(mf) .. " | " .. cm:campaign_obj_to_string(mf))
        local unit_list = mf:unit_list()
        for j = 0, unit_list:num_items() - 1 do
            local unit = unit_list:item_at(j)
            out(tostring(unit) .. " | " .. cm:campaign_obj_to_string(unit))
        end
    end
end

function lbm_test_3() --luacheck:no global
    out("mod script load package.path: " .. package.path)
    
    core:add_listener(
        "UITriggerScriptEventLbmTest",
        "UITriggerScriptEvent",
        function(context)
            return context:trigger():starts_with("LbmTest|")
        end,
        function(context)
            local cqi, trigger_str = context:faction_cqi(), context:trigger()
            out("UITriggerScriptEvent: cqi=" .. tostring(cqi) .. ", trigger=" .. tostring(trigger_str))
        end,
        true
    )
    
    core:add_listener(
        "UnitCreatedLbmTest",
        "UnitCreated",
        function(context)
            return context:unit():faction():is_human()
        end,
        function(context)
            local unit = context:unit()
            out("UnitCreated: " .. tostring(unit) .. " | " .. cm:campaign_obj_to_string(unit))
            local unit_key = unit:unit_key()
            cm:callback(function() out("UnitCreated callback: " .. unit_key) end, 0)
            CampaignUI.TriggerCampaignScriptEvent(unit:faction():command_queue_index(), "LbmTest|Created|" .. unit_key)
        end,
        true
    )
    
    core:add_listener(
        "UnitDisbandedLbmTest",
        "UnitDisbanded",
        function(context)
            return context:unit():faction():is_human()
        end,
        function(context)
            local unit = context:unit()
            out("UnitDisbanded: " .. tostring(unit) .. " | " .. cm:campaign_obj_to_string(unit))
            local unit_key = unit:unit_key()
            cm:callback(function() out("UnitDisbanded callback: " .. unit_key) end, 0)
            CampaignUI.TriggerCampaignScriptEvent(unit:faction():command_queue_index(), "LbmTest|Disbanded|" .. unit_key)
        end,
        true
    )
    
    core:add_listener(
        "FactionTurnStartLbmTest",
        "FactionTurnStart",
        function(context)
            return context:faction():is_human()
        end,
        function(context)
            out("FactionTurnStart: ...")
            local faction = context:faction()
            output_faction_forces(faction)
        end,
        true
    )
    
    core:add_listener(
        "ScriptEventPendingBattleLbmTest",
        "ScriptEventPendingBattle",
        true,
        function(context)
            out("ScriptEventPendingBattle: ...")
            local faction_names = {}
            for i = 1, cm:pending_battle_cache_num_attackers() do
                local faction_name = cm:pending_battle_cache_get_attacker_faction_name(i)
                faction_names[faction_name] = true
            end
            for i = 1, cm:pending_battle_cache_num_defenders() do
                local faction_name = cm:pending_battle_cache_get_defender_faction_name(i)
                faction_names[faction_name] = true
            end
            
            for faction_name, _ in pairs(faction_names) do
                local faction = cm:get_faction(faction_name)
                if faction:is_human() then
                    output_faction_forces(faction)
                end
            end
        end,
        true
    )
    
    core:add_listener(
        "BattleCompletedLbmTest",
        "BattleCompleted",
        true,
        function(context)
            out("BattleCompleted: ...")
            local faction_names = {}
            for i = 1, cm:pending_battle_cache_num_attackers() do
                local faction_name = cm:pending_battle_cache_get_attacker_faction_name(i)
                faction_names[faction_name] = true
            end
            for i = 1, cm:pending_battle_cache_num_defenders() do
                local faction_name = cm:pending_battle_cache_get_defender_faction_name(i)
                faction_names[faction_name] = true
            end
            
            for faction_name, _ in pairs(faction_names) do
                local faction = cm:get_faction(faction_name)
                if faction:is_human() then
                    output_faction_forces(faction)
                end
            end
        end,
        true
    )
    
    core:add_listener(
        "ShortCutTriggeredF9LbmTest",
        "ShortcutTriggered",
        function(context)
            return context.string == "camera_bookmark_view0" -- F9 by default
        end,
        function(context)
            out("F9: ...")
            local faction = cm:get_faction(cm:get_local_faction(true))
            output_faction_forces(faction)
            os.execute("CHOICE /n /d:y /c:yn /t:9999") -- hacky way to completely pause the game
        end,
        true
    )
end
