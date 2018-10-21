--luacheck:no unused

local safe_caller = cm:load_global_script "lib.vanish_safe_caller"
safe_caller.enable()

local utils = cm:load_global_script "lib.lbm_utils"
local events_tracker = cm:load_global_script "lib.lbm_events_tracker"

core:add_listener(
    "UnitCountBasedUpkeepShortcutTriggeredF9",
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
    end,
    true
)

local async = cm:load_global_script "lib.lbm_async"

core:add_listener(
    "UnitCountBasedUpkeepShortCutTriggeredF10",
    "ShortcutTriggered",
    function(context)
        return context.string == "camera_bookmark_view1" -- F10 by default
    end,
    function(context)
        out("event listener coroutine: " .. tostring(coroutine.running()))
        
        async(function()
            out("inside async coroutine: " .. tostring(coroutine.running()))
            local try_count = 0
            local val = async.retry(function()
                try_count = try_count + 1
                out("try count: " .. try_count)
                if try_count < 3 then
                    error(try_count)
                end
                return "inner done"
            end, 3, 1.0)
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
            
            out(utils.serialize(string.find("hi world", "or")))
            out(utils.serialize(string.find("hi world", "foo")))
            out(utils.serialize(string.find("hi world", "")))
            
            val = async.retry(function()
                error("HAHA YOU ARE A FAILURE")
            end, 3, 1.0)
            out(val)
        end)
        
        out("event listener done")
    end,
    true
)

local benchmarking = cm:load_global_script "lib.lbm_benchmarking"

--[[
Given max_time of 120, max_iters of 1000000000, and 4 total suite runs, on my machine, I get the following benchmark results:

BENCHMARKS AGGREGATE
--------------------
NAME                                              | # ITERS       | TIME ELAPSED  | TIME PER ITER | MINUS CONTROL
-----------------------------------------------------------------------------------------------------------------
control (only benchmarking overhead)              |    4000000000 |      99.574s |      24.893ns |       0.000ns
new table with 0 items                            |    2155362048 |     480.004s |     222.702ns |     197.809ns
new table with 2 items                            |    1744903936 |     480.005s |     275.090ns |     250.197ns
new table with 20 items                           |     799800000 |     480.008s |     600.160ns |     575.267ns
new table with 20 key-values                      |     372769024 |     480.010s |    1287.687ns |    1262.794ns
pass/access 20 param                              |    4000000000 |     341.598s |      85.400ns |      60.507ns
pass/access list param with 20 items              |    2478748928 |     480.004s |     193.648ns |     168.755ns
noop with 0 args                                  |    4000000000 |     205.769s |      51.442ns |      26.549ns
noop with 2 args                                  |    4000000000 |     205.149s |      51.287ns |      26.394ns
noop with 20 args                                 |    4000000000 |     396.339s |      99.085ns |      74.191ns
passthrough (near noop) with 0 args               |    4000000000 |     241.035s |      60.259ns |      35.365ns
passthrough (near noop) with 2 args               |    4000000000 |     240.801s |      60.200ns |      35.307ns
passthrough (near noop) with 20 args              |    3956001024 |     480.004s |     121.336ns |      96.442ns
new function                                      |    2426061056 |     480.004s |     197.853ns |     172.960ns
coroutine empty                                   |    2711382016 |     480.004s |     177.033ns |     152.139ns
async_trampoline-like coroutine passthrough       |    1335106048 |     480.004s |     359.525ns |     334.632ns
async.id                                          |    3932091968 |     480.004s |     122.073ns |      97.180ns
async passthrough                                 |     827916928 |     480.003s |     579.772ns |     554.879ns
orig string.find                                  |    1359634944 |     480.004s |     353.039ns |     328.145ns
new string.find                                   |    1038760960 |     480.003s |     462.092ns |     437.199ns
new string.find with pack/unpack args/retvals     |     403145024 |     480.007s |    1190.656ns |    1165.762ns
async new string.find                             |     514091008 |     480.004s |     933.694ns |     908.801ns
old string.sub                                    |    1263738880 |     480.004s |     379.828ns |     354.935ns
new string.sub                                    |    1560678016 |     480.004s |     307.561ns |     282.668ns
cm:get_faction                                    |      68037000 |     480.040s |    7055.577ns |    7030.684ns
cm:get_faction no checks                          |      89980000 |     480.009s |    5334.624ns |    5309.731ns
async cm:get_faction no checks                    |      67957000 |     480.067s |    7064.276ns |    7039.383ns
-----------------------------------------------------------------------------------------------------------------
]]
local function setup_benchmarks()
    local suite = benchmarking.new_suite({
        max_time = 120, -- in seconds
        max_iters = 1000000000,
        --max_time = 10, -- in seconds
        --max_iters = 1000000,
        check_time_every_n_iters = 1000,
    })
    local noop = function() end
    local passthrough = utils.passthrough
    suite:add("new table with 0 items", function()
        local _ = {}
    end)
    suite:add("new table with 2 items", function()
        local _ = {"hello world", "orl"}
    end)
    suite:add("new table with 20 items", function()
        local _ = {"Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", "."}
    end)
    suite:add("new table with 20 key-values", function()
        local _ = {Lorem = 1, ipsum = 2, dolor = 3, sit = 4, amet = 5, consectetur = 6, adipiscing = 7, elit = 8, sed = 9, ["do"] = 10,
            eiusmod = 11, tempor = 12, incididunt = 13, ut = 14, labore = 15, et = 16, dolore = 17, magna = 18, aliqua = 19, ["."] = 20}
    end)
    suite:add("pass/access 20 param", function(t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20)
        return t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, t17, t18, t19, t20
    end, function(func)
        func("Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", ".")
    end)
    suite:add("pass/access list param with 20 items", function(t)
        return t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12], t[13], t[14], t[15], t[16], t[17], t[18], t[19], t[20]
    end, function(func)
        func({"Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", "."})
    end)
    suite:add("noop with 0 args", function()
        noop()
    end)
    suite:add("noop with 2 args", function()
        noop("hello world", "orl")
    end)
    suite:add("noop with 20 args", function()
        noop("Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", ".")
    end)
    suite:add("passthrough (near noop) with 0 args", function()
        passthrough("hello world", "orl")
    end)
    suite:add("passthrough (near noop) with 2 args", function()
        passthrough("hello world", "orl")
    end)
    suite:add("passthrough (near noop) with 20 args", function()
        passthrough("Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", ".")
    end)
    suite:add("new function", function()
        local function _() end
    end)
    suite:add("coroutine empty", function(co)
        coroutine.resume(co)
    end, function(func)
        local co = coroutine.create(function()
            while true do
                coroutine.yield()
            end
        end)
        return func(co)
    end)
    suite:add("async_trampoline-like coroutine passthrough", function(co, x)
        local ret_status, ret_val = coroutine.resume(co, x)
        if not ret_status then
            error(ret_val)
        elseif type(ret_val) == "function" then
            x = ret_val(x)
        elseif ret_val ~= nil then
            error(ret_val)
        end
        if coroutine.status(co) == "dead" then
            return
        end
    end, function(func)
        local co = coroutine.create(function()
            while true do
                coroutine.yield()
            end
        end)
        return func(co, 0)
    end)
    suite:add("async.id", function()
        async.id() -- includes a couroutine.running() call
    end)
    suite:add("async passthrough", function()
        if async.id() then -- should always be true since in async block
            coroutine.yield(passthrough)
        else
            passthrough()
        end
    end, async)
    suite:add("orig string.find", function()
        string._orig_find("hello world", "orl") --luacheck:no global
    end)
    suite:add("new string.find", function()
        string.find("hello world", "orl") -- new string.find has a bit more overhead to check whether it's running in an async block
    end)
    suite:add("new string.find with pack/unpack args/retvals", function()
        unpack({string.find(unpack({"hello world", "orl"}))}) -- table creation and unpack are expensive
    end)
    suite:add("async new string.find", function()
        string.find("hello world", "orl") -- new string.find is yielded to the async trampoline, so has overhead costs
    end, async)
    suite:add("old string.sub", function()
        string._orig_sub("hello world", 3, 8) --luacheck:no global
    end)
    suite:add("new string.sub", function()
        string.sub("hello world", 3, 8)
    end)
    suite:add("cm:get_faction", function()
        cm:get_faction("wh2_main_hef_eataine")
    end)
    suite:add("cm:get_faction no checks", function()
        cm:model():world():faction_by_key("wh2_main_hef_eataine")
    end)
    suite:add("async cm:get_faction no checks", function()
        cm:model():world():faction_by_key("wh2_main_hef_eataine") -- game object functions are yielded to the async trampoline, so has overhead costs
    end, async)
    return suite
end

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
    "UnitCountBasedUpkeepShortCutTriggeredF11",
    "ShortcutTriggered",
    function(context)
        return context.string == "camera_bookmark_view2" -- F11 by default
    end,
    function(context)
        --test_create_force()
        local suite = setup_benchmarks()
        local suite_results = {}
        local num_suite_runs = 4
        for i = 1, num_suite_runs do
            utils.callback_without_performance_monitor(function()
                suite_results[#suite_results + 1] = suite:run_suite()
                if #suite_results == num_suite_runs then
                    suite:aggregate_results(suite_results)
                end
            end, 0)
        end
    end,
    true
)

core:add_listener(
    "UnitCountBasedUpkeepShortCutTriggeredF12",
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
    "RecruitmentItemIssuedByPlayerDebug",
    "RecruitmentItemIssuedByPlayer",
    true,
    function(context)
        out("RecruitmentItemIssuedByPlayerDebug: " .. context:main_unit_record() .. " in " .. context:time_to_build() .. " turns")
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
    "UnitCountBasedUpkeepComponentLClickUpDebug",
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
    "UnitCountBasedUpkeepTimeTriggerDebug",
    "TimeTrigger",
    true,
    function(context)
        out("TimeTrigger: " .. tostring(context.string))
    end,
    true
)
--]=]
