local utils = cm:load_global_script "lib.lbm_utils"
local benchmarking = cm:load_global_script "lib.lbm_benchmarking"

--[[
Given max_time of 120, max_iters of 1000000000, and 4 total suite runs, on my machine, I get the following benchmark results:

BENCHMARKS AGGREGATE
--------------------
NAME                                              | # ITERS       | TIME ELAPSED  | TIME PER ITER | MINUS CONTROL
-----------------------------------------------------------------------------------------------------------------
control (only benchmarking overhead)              |    4000000000 |       99.574s |      24.893ns |       0.000ns
new table with 0 items                            |    2155362048 |      480.004s |     222.702ns |     197.809ns
new table with 2 items                            |    1744903936 |      480.005s |     275.090ns |     250.197ns
new table with 20 items                           |     799800000 |      480.008s |     600.160ns |     575.267ns
new table with 20 key-values                      |     372769024 |      480.010s |    1287.687ns |    1262.794ns
pass/access 20 param                              |    4000000000 |      341.598s |      85.400ns |      60.507ns
pass/access list param with 20 items              |    2478748928 |      480.004s |     193.648ns |     168.755ns
noop with 0 args                                  |    4000000000 |      205.769s |      51.442ns |      26.549ns
noop with 2 args                                  |    4000000000 |      205.149s |      51.287ns |      26.394ns
noop with 20 args                                 |    4000000000 |      396.339s |      99.085ns |      74.191ns
passthrough (near noop) with 0 args               |    4000000000 |      241.035s |      60.259ns |      35.365ns
passthrough (near noop) with 2 args               |    4000000000 |      240.801s |      60.200ns |      35.307ns
passthrough (near noop) with 20 args              |    3956001024 |      480.004s |     121.336ns |      96.442ns
new function                                      |    2426061056 |      480.004s |     197.853ns |     172.960ns
coroutine empty                                   |    2711382016 |      480.004s |     177.033ns |     152.139ns
async_trampoline-like coroutine passthrough       |    1335106048 |      480.004s |     359.525ns |     334.632ns
async.id                                          |    3932091968 |      480.004s |     122.073ns |      97.180ns
async passthrough                                 |     827916928 |      480.003s |     579.772ns |     554.879ns
orig string.find                                  |    1359634944 |      480.004s |     353.039ns |     328.145ns
new string.find                                   |    1038760960 |      480.003s |     462.092ns |     437.199ns
new string.find with pack/unpack args/retvals     |     403145024 |      480.007s |    1190.656ns |    1165.762ns
async new string.find                             |     514091008 |      480.004s |     933.694ns |     908.801ns
old string.sub                                    |    1263738880 |      480.004s |     379.828ns |     354.935ns
new string.sub                                    |    1560678016 |      480.004s |     307.561ns |     282.668ns
cm:get_faction                                    |      68037000 |      480.040s |    7055.577ns |    7030.684ns
cm:get_faction no checks                          |      89980000 |      480.009s |    5334.624ns |    5309.731ns
async cm:get_faction no checks                    |      67957000 |      480.067s |    7064.276ns |    7039.383ns
find_uicomponent 1 deep                           |     145587008 |      480.029s |    3297.197ns |    3272.304ns
async find_uicomponent 1 deep                     |     124546000 |      480.007s |    3854.052ns |    3829.159ns
find_uicomponent 8 deep                           |      15840000 |      480.054s |   30306.438ns |   30281.545ns
async find_uicomponent 8 deep                     |      13887000 |      480.106s |   34572.320ns |   34547.427ns
count_armies_and_units (1 army, 2 chars)          |      20583000 |      480.029s |   23321.627ns |   23296.734ns
async count_armies_and_units (1 army, 2 chars)    |      13883000 |      480.060s |   34578.977ns |   34554.084ns
count_armies_and_units (2 armies, 5 chars)        |       9444000 |      480.550s |   50884.164ns |   50859.271ns
async count_armies_and_units (2 armies, 5 chars)  |       6168000 |      480.132s |   77842.445ns |   77817.552ns
count_armies_and_units (10 armies, 12 chars)      |       1841000 |      480.529s |  261015.141ns |  260990.248ns
async count_armies_and_units (10 armies, 12 chars)|       1223000 |      480.417s |  392818.469ns |  392793.576ns
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
    
    local noop = utils.noop
    local passthrough = utils.passthrough
    
    local async = cm:load_global_script "lib.lbm_async"
    local function async_and_resume(func)
        local id = async(func)
        async.resume(id)
    end
    
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
    end, async_and_resume)
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
    end, async_and_resume)
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
    end, async_and_resume)
    suite:add("find_uicomponent 1 deep", function()
        find_uicomponent(core:get_ui_root(), "layout")
    end)
    suite:add("async find_uicomponent 1 deep", function()
        find_uicomponent(core:get_ui_root(), "layout")
    end, async_and_resume)
    suite:add("find_uicomponent 8 deep", function()
        find_uicomponent(core:get_ui_root(), "layout", "radar_things", "dropdown_parent", "units_dropdown", "panel", "panel_clip", "sortable_list_units", "list_box")
    end)
    suite:add("async find_uicomponent 8 deep", function()
        find_uicomponent(core:get_ui_root(), "layout", "radar_things", "dropdown_parent", "units_dropdown", "panel", "panel_clip", "sortable_list_units", "list_box")
    end, async_and_resume)
    
    local my_faction = utils.get_faction("wh2_main_hef_eataine")
    local function is_valid_army(mf)
        return not mf:is_armed_citizenry() and mf:has_general() and not character_is_black_ark(mf:general_character()) -- neither garrison nor black ark
    end
    local function count_armies_and_units(faction)
        local army_count = 0
        local unit_count = 0
        -- Count all units in non-garrison/non-black-ark armies, including lords and heroes
        local mf_list = faction:military_force_list()
        local army_filter = is_valid_army
        for i = 0, mf_list:num_items() - 1 do
            local mf = mf_list:item_at(i)
            if army_filter(mf) then
                army_count = army_count + 1
                unit_count = unit_count + mf:unit_list():num_items()
            end
        end
        -- Count all non-embedded heroes (agents) as units
        local char_list = faction:character_list()
        local num_char = char_list:num_items()
        for i = 0, num_char - 1 do
            local char = char_list:item_at(i)
            if not char:is_embedded_in_military_force() and cm:char_is_agent(char) then
                unit_count = unit_count + 1
            end
        end
        local faction_name = faction:name()
        return faction_name, army_count, unit_count
    end
    suite:add("count_armies_and_units", function()
        count_armies_and_units(my_faction)
    end)
    suite:add("async count_armies_and_units", function()
        count_armies_and_units(my_faction)
    end, async_and_resume)
    
    return suite
end

local function run_benchmarks(num_suite_runs)
    local suite = setup_benchmarks()
    local suite_results = {}
    for i = 1, num_suite_runs do
        utils.callback_without_performance_monitor(function()
            suite_results[#suite_results + 1] = suite:run_suite()
            if #suite_results == num_suite_runs then
                suite:aggregate_results(suite_results)
            end
        end, 0)
    end
end

return run_benchmarks
