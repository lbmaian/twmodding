local utils = cm:load_global_script "lib.lbm_utils"
local benchmarking = cm:load_global_script "lib.lbm_benchmarking"

--[[
Given max_time of 120, max_iters of 1000000000, and 4 total suite runs, on my machine, I get the following benchmark results:

BENCHMARKS
----------
NAME                                              | # ITERS       | TIME ELAPSED  | TIME PER ITER | MINUS CONTROL
-----------------------------------------------------------------------------------------------------------------
control (only benchmarking overhead)              |    1000000000 |       24.367s |      24.367ns |       0.000ns
#<string>                                         |    1000000000 |       29.753s |      29.753ns |       5.386ns
string.len                                        |    1000000000 |       72.305s |      72.305ns |      47.938ns
(string.)len                                      |    1000000000 |       44.037s |      44.037ns |      19.670ns
<string>:len                                      |    1000000000 |       54.760s |      54.760ns |      30.393ns
new table with 0 items                            |     573422976 |      120.000s |     209.270ns |     184.903ns
new table with 2 items                            |     452756000 |      120.001s |     265.046ns |     240.679ns
new table with 20 items                           |     200755008 |      120.001s |     597.749ns |     573.382ns
new table with 20 key-values                      |      90250000 |      120.001s |    1329.651ns |    1305.284ns
pass/access 20 param                              |    1000000000 |       84.458s |      84.458ns |      60.091ns
pass/access list param with 20 items              |     644105024 |      120.001s |     186.307ns |     161.940ns
noop with 0 args                                  |    1000000000 |       49.656s |      49.656ns |      25.289ns
noop with 2 args                                  |    1000000000 |       50.157s |      50.157ns |      25.790ns
noop with 20 args                                 |    1000000000 |       97.663s |      97.663ns |      73.296ns
pcall(error)                                      |     656148992 |      120.001s |     182.887ns |     158.520ns
pcall(noop with 0 args)                           |    1000000000 |      100.531s |     100.531ns |      76.164ns
pcall(noop with 2 args)                           |    1000000000 |      107.396s |     107.396ns |      83.029ns
pcall(noop with 20 args)                          |     786937984 |      120.001s |     152.491ns |     128.124ns
passthrough (near noop) with 0 args               |    1000000000 |       53.553s |      53.553ns |      29.186ns
passthrough (near noop) with 2 args               |    1000000000 |       59.630s |      59.630ns |      35.263ns
passthrough (near noop) with 20 args              |    1000000000 |      118.682s |     118.682ns |      94.315ns
new function                                      |     631872000 |      120.001s |     189.913ns |     165.546ns
coroutine empty                                   |     704321024 |      120.001s |     170.378ns |     146.011ns
async_trampoline-like coroutine passthrough       |     314595008 |      120.001s |     381.446ns |     357.079ns
async.id                                          |    1000000000 |      116.669s |     116.669ns |      92.302ns
async passthrough                                 |     211567008 |      120.001s |     567.202ns |     542.835ns
orig string.find                                  |     352156000 |      120.001s |     340.761ns |     316.394ns
new string.find                                   |     269984000 |      120.001s |     444.474ns |     420.107ns
new string.find with pack/unpack args/retvals     |     101955000 |      120.001s |    1176.999ns |    1152.632ns
async new string.find                             |     133585000 |      120.001s |     898.312ns |     873.945ns
old string.sub                                    |     327904000 |      120.001s |     365.964ns |     341.597ns
new string.sub                                    |     407025984 |      120.001s |     294.824ns |     270.457ns
cm:get_faction                                    |      17610000 |      120.001s |    6814.365ns |    6789.998ns
cm:get_faction no checks                          |      23184000 |      120.010s |    5176.415ns |    5152.048ns
async cm:get_faction no checks                    |      18061000 |      120.005s |    6644.434ns |    6620.067ns
find_uicomponent 1 deep                           |      36708000 |      120.005s |    3269.175ns |    3244.808ns
async find_uicomponent 1 deep                     |      31869000 |      120.004s |    3765.537ns |    3741.170ns
find_uicomponent 8 deep                           |       4049000 |      120.001s |   29637.189ns |   29612.822ns
async find_uicomponent 8 deep                     |       3562000 |      120.004s |   33690.102ns |   33665.734ns
count_armies_and_units (1 army, 2 chars)          |       4647000 |      120.209s |   25868.082ns |   25843.715ns
async count_armies_and_units (1 army, 2 chars)    |       3107000 |      120.004s |   38623.723ns |   38599.355ns
count_armies_and_units (2 armies, 5 chars)        |       9444000 |      480.550s |   50884.164ns |   50859.271ns OLD
async count_armies_and_units (2 armies, 5 chars)  |       6168000 |      480.132s |   77842.445ns |   77817.552ns OLD
count_armies_and_units (10 armies, 12 chars)      |       1841000 |      480.529s |  261015.141ns |  260990.248ns OLD
async count_armies_and_units (10 armies, 12 chars)|       1223000 |      480.417s |  392818.469ns |  392793.576ns OLD
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
    
    suite:add("#<string>", function()
        return #"hello world"
    end)
    suite:add("string.len", function()
        return string.len("hello world")
    end)
    local stringlen = string.len
    suite:add("(string.)len", function()
        return stringlen("hello world")
    end)
    suite:add("<string>:len", function()
        return ("hello world"):len()
    end)
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
    suite:add("pcall(error)", function()
        pcall(error)
    end)
    suite:add("pcall(noop with 0 args)", function()
        pcall(noop)
    end)
    suite:add("pcall(noop with 2 args)", function()
        pcall(noop, "hello world", "orl")
    end)
    suite:add("pcall(noop with 20 args)", function()
        pcall(noop, "Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", ".")
    end)
    suite:add("passthrough (near noop) with 0 args", function()
        passthrough()
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
    suite:add("async_trampoline-like coroutine passthrough", function(co)
        local ret_status, ret_val, x = coroutine.resume(co, 1)
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
        return x
    end, function(func)
        local co = coroutine.create(function()
            while true do
                local _ = coroutine.yield(passthrough, 2)
            end
        end)
        return func(co)
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
        return not mf:is_armed_citizenry() and mf:has_general() and not mf:general_character():character_subtype("wh2_main_def_black_ark") -- neither garrison nor black ark
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
    for _ = 1, num_suite_runs do
        utils.callback_without_performance_monitor(function()
            suite_results[#suite_results + 1] = suite:run_suite()
            if #suite_results == num_suite_runs then
                suite:aggregate_results(suite_results)
            end
        end, 0)
    end
end

return run_benchmarks
