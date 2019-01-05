--luacheck:no unused

-- Note: require/loadfile seems finicky since it doesn't seem guaranteed that the same global environment is always used (might be scripts being loaded from different threads?)
-- so using cm:load_global_script, which ensures the same global environment is used, to be safe.
cm:load_global_script "lib.vanish_safe_caller"
local utils = cm:load_global_script "lib.lbm_utils"
local events_tracker = cm:load_global_script "lib.lbm_events_tracker"

core:add_listener(
    "ShortcutTriggeredF9LbmTest",
    "ShortcutTriggered",
    function(context)
        return context.string == "camera_bookmark_view0" -- F9 by default
    end,
    function(context)
        if events_tracker.enabled() then
            events_tracker.disable()
        else
            events_tracker.enable(2)
        end
        
        --[[
        local faction_list = cm:model():world():faction_list()
        for i = 0, faction_list:num_items() - 1 do
            local faction = faction_list:item_at(i)
            if not faction:is_dead() then
                out("faction " .. i .. ": " .. faction:name() .. " (" .. faction:command_queue_index() .. "): # armies=" .. tostring(faction:military_force_list():num_items()))
            end
        end
        local rebel_faction = utils.get_faction(1)
        out("faction ?: " .. rebel_faction:name() .. " (" .. rebel_faction:command_queue_index() .. "): dead=" .. tostring(rebel_faction:is_dead()) ..
            ", # armies=" .. tostring(rebel_faction:military_force_list():num_items()))
        events.FactionTurnEnd[#events.FactionTurnEnd + 1] = function(context2)
            local faction = context2:faction()
            out("FactionTurnEnd: faction " .. faction:name() .. " (" .. faction:command_queue_index() .. "): dead=" .. tostring(faction:is_dead()) ..
                ", # armies=" .. tostring(faction:military_force_list():num_items()))
        end
        events.FactionRoundStart[#events.FactionRoundStart + 1] = function(context2)
            local faction = context2:faction()
            out("FactionRoundStart: faction " .. faction:name() .. " (" .. faction:command_queue_index() .. "): dead=" .. tostring(faction:is_dead()) ..
                ", # armies=" .. tostring(faction:military_force_list():num_items()))
        end
        --]]
    end,
    true
)

utils.add_custom_ui_event_listener("myevent",
    function(cqi, i)
        out("myevent fired " .. i)
    end,
    true
)

core:add_listener(
    "ShortCutTriggeredF10LbmTest",
    "ShortcutTriggered",
    function(context)
        return context.string == "camera_bookmark_view1" -- F10 by default
    end,
    function(context)
        local async = cm:load_global_script "lib.lbm_async"
        
        out("event listener coroutine: " .. tostring(coroutine.running()))
        
        cm:callback(function()
            out("callback fired 1")
        end, 0)
        cm:callback(function()
            out("callback fired 2")
        end, 0)
        cm:callback(function()
            out("callback fired 3")
        end, 0)
        utils.trigger_custom_ui_event("myevent", nil, 1)
        utils.trigger_custom_ui_event("myevent", nil, 2)
        utils.trigger_custom_ui_event("myevent", nil, 3)
        utils.retry_callback({
            callback = function(try_count)
                error("0.1-delay retry " .. try_count)
            end,
            max_tries = 3,
            base_delay = 0.1,
            --enable_logging = true,
        })
        utils.retry_callback({
            callback = function(try_count)
                error("0-delay retry " .. try_count)
            end,
            max_tries = 3,
            base_delay = 0,
            --enable_logging = true,
        })
        utils.cancel_retries(utils.retry_callback({
            callback = function(try_count)
                error("CANCELED 0.1-delay retry " .. try_count)
            end,
            max_tries = 3,
            base_delay = 0.1,
            enable_logging = true,
        }))
        utils.cancel_retries(utils.retry_callback({
            callback = function(try_count)
                error("CANCELED 0-delay retry " .. try_count)
            end,
            max_tries = 3,
            base_delay = 0,
            enable_logging = true,
        }))
        
        local id = async(function()
            out("inside async coroutine: " .. tostring(coroutine.running()))
            local val = async.retry({
                callback = function(try_count)
                    out("try count: " .. try_count)
                    if try_count < 3 then
                        error(try_count)
                    end
                    return "inner done"
                end,
                 max_tries = 3,
                 base_delay = 1.0,
                 exponential_backoff = 1.1,
                 --enable_logging = true,
            })
            out(val)
            
            async.sleep(2.5)
            out("I'm awake again!")
            
            async.sleep(0)
            out("after 0 sec sleep")
            
            local faction_name = cm:get_local_faction(true)
            out("faction " .. faction_name)
            
            local model = cm:model()
            out("model: " .. tostring(model))
            
            local world = model:world()
            out("world: " .. tostring(world))
            
            local faction = world:faction_by_key(faction_name)
            out("faction " .. faction:name() .. " " .. faction:command_queue_index())
            
            local faction2 = utils.get_faction(faction:command_queue_index())
            out("faction " .. faction2:name() .. " " .. faction2:command_queue_index())
            
            local uic = find_uicomponent(core:get_ui_root(), "layout", "radar_things", "dropdown_parent", "units_dropdown", "panel", "panel_clip", "sortable_list_units", "list_box")
            out(tostring(uic))
            utils.output_all_uicomponent_children(uic)
            
            local localised_str = effect.get_localised_string("ui_text_replacements_localised_text_tooltip_lbm_additional_army_unit_count_upkeep_num_units")
            out(tostring(localised_str))
            
            async(function()
                out("inside nested async coroutine: " .. tostring(coroutine.running()))
                async.sleep(0, true)
                out("inside nested async foo")
                async.sleep(2, true)
                out("inside nested async bar")
            end)
            
            out(utils.serialize(string.find("hi world", "or")))
            out(utils.serialize(string.find("hi world", "foo")))
            out(utils.serialize(string.find("hi world", "")))
            
            val = async.retry(function()
                error("HAHA YOU ARE A FAILURE")
            end, 3, 1.0)
            out(val)
        end)
        async.resume(id) -- start it immediately, instead of after this listener finishes
        
        out("event listener done")
    end,
    true
)

local function test_create_force()
    --[
    do
        local region = utils.get_faction("wh2_main_hef_eataine"):home_region()
        cm:create_force(
            "wh2_main_hef_eataine",
            "wh2_main_hef_inf_spearmen_0,wh2_main_hef_inf_archers_1,wh2_main_hef_inf_spearmen_0,wh2_main_hef_inf_archers_1",
            "wh2_main_eataine_lothern",
            region:settlement():logical_position_x() - 1,
            region:settlement():logical_position_y() - 1,
            true,
            true,
            function(char_cqi)
                local char = cm:get_character_by_cqi(char_cqi)
                cm:grant_unit_to_character(cm:char_lookup_str(char), "wh2_main_hef_inf_archers_0")
            end
        )
    end
    --]]
    --[
    do
        local region = utils.get_faction("wh2_main_hef_eataine"):home_region()
        cm:create_force_with_general(
            "wh2_main_hef_eataine",
            "wh2_main_hef_inf_spearmen_0",
            "wh2_main_eataine_lothern",
            region:settlement():logical_position_x() + 1,
            region:settlement():logical_position_y() + 1,
            "general",
            "wh2_main_hef_princess",
            "names_name_355845708",
            "",
            "",
            "",
            false,
            function(char_cqi)
                local char = cm:get_character_by_cqi(char_cqi)
                local unit_list = char:military_force():unit_list()
                cm:remove_unit_from_character(cm:char_lookup_str(char), unit_list:item_at(1):unit_key())
            end
        )
    end
    --]]
    --[
    do
        local region = utils.get_faction("wh2_main_hef_eataine"):home_region()
        cm:create_agent(
            "wh2_main_hef_eataine",
            "general",
            "wh2_main_hef_princess",
            region:settlement():logical_position_x() - 1,
            region:settlement():logical_position_y() - 1,
            true
        )
    end
    --]]
end

core:add_listener(
    "ShortCutTriggeredF11LbmTest",
    "ShortcutTriggered",
    function(context)
        return context.string == "camera_bookmark_view2" -- F11 by default
    end,
    function(context)
        --test_create_force()
        cm:load_global_script("test.lbm_benchmarks_1")(4)
    end,
    true
)

core:add_listener(
    "ShortCutTriggeredF12LbmTest",
    "ShortcutTriggered",
    function(context)
        return context.string == "camera_bookmark_view3" -- F12 by default (note: should change the Steam screenshot shortcut key avoid taking screenshots)
    end,
    function(context)
        --print_all_uicomponent_children(core:get_ui_root())
        utils.output_all_uicomponent_children(core:get_ui_root())
        --utils.output_all_uicomponent_children(find_uicomponent(core:get_ui_root(), "tooltip_campaign_upkeep_effect"))
        --utils.output_all_uicomponent_children(find_uicomponent(core:get_ui_root(), "TechTooltipPopup"))
        --utils.output_all_uicomponent_children(find_uicomponent(core:get_ui_root(), "tooltip_value_breakdown"))
        --utils.output_all_uicomponent_children(UIComponent(context.component))
    end,
    true
)

core:add_listener(
    "RecruitmentItemIssuedByPlayerLbmTest",
    "RecruitmentItemIssuedByPlayer",
    true,
    function(context)
        out("RecruitmentItemIssuedByPlayerLbmTest: " .. context:main_unit_record() .. " in " .. context:time_to_build() .. " turns")
    end,
    true
)

-- TEMP DEBUG
--[=[
local army_count_prefix = "lbm_additional_army_unit_count_"
local upkeep_effect_bundle_prefix = army_count_prefix .. "upkeep_"
local dummy_upkeep_effect_bundle = upkeep_effect_bundle_prefix .. "dummy"
local orig_upkeep_effect_bundle_prefix = "wh_main_bundle_force_additional_army_upkeep_"

local custom_ui_listeners = cm:load_global_script "lib.lbm_custom_ui_listeners"

core:add_listener(
    "ComponentLClickUpLbmTest",
    "ComponentLClickUp",
    custom_ui_listeners.enabled,
    function(context)
        local uic = UIComponent(context.component)
        local uic_id = uic:Id()
        if uic_id:starts_with(orig_upkeep_effect_bundle_prefix) or uic_id == dummy_upkeep_effect_bundle or uicomponent_descended_from(uic, "treasury_holder") then
            --[
            local faction = utils.get_faction(cm:get_local_faction(true))
            --local general_cqi = get_nth_valid_army(faction, 1):general_character():cqi()
            if faction:has_effect_bundle("wh2_main_incident_hef_campign_movement_up") then
                cm:remove_effect_bundle("wh2_main_incident_hef_campign_movement_up", faction:name())
                --cm:apply_effect_bundle_to_characters_force("wh2_main_effect_army_movement_up", general_cqi, 0, false)
            else
                cm:apply_effect_bundle("wh2_main_incident_hef_campign_movement_up", faction:name(), 0)
                --cm:remove_effect_bundle_from_characters_force("wh2_main_effect_army_movement_up", general_cqi)
            end
            
            local orig_upkeep_effect_bundle_found = false
            local mf_list = faction:military_force_list()
            for i = 0, mf_list:num_items() - 1 do
                local mf = mf_list:item_at(i)
                if not mf:is_armed_citizenry() and mf:has_general() and not character_is_black_ark(mf:general_character()) then -- neither garrison nor black ark
                    for _, difficulty in ipairs{"easy", "normal", "hard", "very_hard", "legendary"} do
                        if mf:has_effect_bundle("wh_main_bundle_force_additional_army_upkeep_" .. difficulty) then
                            out("[WARNING] Found wh_main_bundle_force_additional_army_upkeep_" .. difficulty .. " on army " .. i)
                            orig_upkeep_effect_bundle_found = true
                        end
                    end
                end
            end
            if not orig_upkeep_effect_bundle_found then
                out("Did not find any wh_main_bundle_force_additional_army_upkeep_* on any armies")
            end
            --]]
        end
    end,
    true
)
--]=]

-- TEMP DEBUG
--[=[
core:add_listener(
    "TimeTriggerLbmTest",
    "TimeTrigger",
    true,
    function(context)
        out("TimeTriggerLbmTest: " .. tostring(context.string))
    end,
    true
)
--]=]
