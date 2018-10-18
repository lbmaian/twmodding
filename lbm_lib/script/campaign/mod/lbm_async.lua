-- Enables asynchronous programming to avoid callback hell
-- WARNING: EXPERIMENTAL PROOF OF CONCEPT THAT MAY HAVE POOR PERFORMANCE

-- Typical usage:
--  local id = async(function()
--      ... can call async.retry, async.sleep, etc.
--  end)
-- Enables async operations (such as async.retry and async.sleep) within the nullary function passed to async (denoted as the async block).
-- Returns an id that can be used to cancel an ongoing async block at the next opportunity via async.cancel.
-- Execution of the async block proceeds immediately until the first async operation, during which point, it yields control to the main coroutine, resumes execution at approximately
-- the async operation-specified delay until the next async operation, and so forth, until the async block is finished.
-- To immediately defer execution at the start of an async block (instead of at the first async operation), just use async.sleep(0) as the first statement of the async block.

local utils = cm:load_global_script "lbm_utils"

local async = {}

local async_entries = {}
local coroutine_to_async_entry_id = {}

local function new_async_entry(func)
    local id = 1
    while async_entries[id] ~= nil do
        id = id + 1
    end
    local co = coroutine.create(func)
    coroutine_to_async_entry_id[co] = id
    local async_entry = {
        id = id,
        coroutine = co,
    }
    async_entries[id] = async_entry
    return id
end

local function remove_async_entry(async_entry)
    async_entries[async_entry.id] = nil
    coroutine_to_async_entry_id[async_entry.coroutine] = nil
end

local all_orig_game_object_functions = {}

-- All calls to cm.game_interface functions via functions like cm:callback must be run in the main coroutine, or else such methods will crash the game.
-- So this wraps such functions to yield to the main coroutine (specifically, yielded to async_trampoline) if it's in an async-created coroutine.
local function update_game_object_functions(game_object_name, game_object)
    if game_object == nil then
        return
    end
    local orig_game_object_functions = all_orig_game_object_functions[game_object_name]
    if orig_game_object_functions then
        return -- already registered
    end
    --out("update_game_object(" .. game_object_name .. ", " .. tostring(game_object) .. ")")
    orig_game_object_functions = {}
    all_orig_game_object_functions[game_object_name] = orig_game_object_functions
    --out.inc_tab()
    for prop, orig_func in pairs(game_object) do
        --out(prop .. ": " .. tostring(orig_func))
        orig_game_object_functions[prop] = orig_func
        game_object[prop] = function(...)
            if coroutine_to_async_entry_id[coroutine.running()] then
                -- Yield to async_trampoline to execute orig_func(...) on the main coroutine.
                return coroutine.yield(orig_func, ...)
            else
                return orig_func(...)
            end
        end
    end
    --out.dec_tab()
end

local function update_all_game_object_functions()
    if all_orig_game_object_functions == nil then
        all_orig_game_object_functions = {}
    end
    --out("update_game_object_metatables()")
    local game_objects = {
        CampaignUI = CampaignUI,
        effect = effect,
    }
    local registry = debug.getregistry()
    for k, v in pairs(registry) do
        --out("registry." .. tostring(k) .. ": " .. tostring(v))
        if k == "GAME" or k == "UIComponent" or k == "cinematic_script" or (type(k) == "string" and string.ends_with(k, "_SCRIPT_INTERFACE")) then
            game_objects[k] = v.__metatable -- same as v.__index as well
        end
    end
    --for game_object_name, _ in pairs(game_objects) do
    --    out(game_object_name)
    --end
    for game_object_name, game_object in pairs(game_objects) do
        update_game_object_functions(game_object_name, game_object)
    end
end

-- string.sub crashes the game in a non-main coroutine, but that's already fixed in lbm_utils.lua.

-- string.find also crashes the game in a non-main coroutine, but it's not trivial to reimplement, so apply the same yield to async_trampoline trick.
-- This is less performant, of course.
local orig_string_find = string.find
string._orig_find = orig_string_find --luacheck:no global
function string.find(...) --luacheck:no global
    if coroutine_to_async_entry_id[coroutine.running()] then
        -- Yield to async_trampoline to execute orig_string_find(...) on the main coroutine.
        return coroutine.yield(orig_string_find, ...)
    else
        return orig_string_find(...)
    end
end

local async_processor_ui_trigger_prefix = "AsyncProcessor" .. string.char(31)

-- async_trampoline's main "loop" are comprised of two mutually recursive functions that are tail call optimized (so also won't result in stack overflow).
-- This takes advantage of Continuation Passing Style approach to avoid the need to expensively pack/unpack args (that would've been needed in a standard loop).
local async_coroutine_resume, process_async_coroutine_resume_results

function async_coroutine_resume(async_entry, ...)
    local co = async_entry.coroutine
    if coroutine.status(co) == "dead" then
        --out("async_trampoline: done")
        remove_async_entry(async_entry)
        return true
    elseif async_entry.next_trigger_time ~= nil then
        return false
    else
        return process_async_coroutine_resume_results(async_entry, coroutine.resume(co, ...))
    end
end

function process_async_coroutine_resume_results(async_entry, ret_status, ret_val, ...)
    if not ret_status then
        --out("async_trampoline: error " .. utils.serialize(ret_val))
        remove_async_entry(async_entry)
        error(ret_val)
    elseif type(ret_val) == "function" then
        --out("async_trampoline: process_coroutine_resume: callback args: {" .. utils.serialize(...) .. "}")
        return async_coroutine_resume(async_entry, ret_val(...)) -- ret_val is a callback function
    elseif ret_val ~= nil then
        remove_async_entry(async_entry)
        error("Async block yielded/returned a non-nil/function value: (" .. type(ret_val) .. ") " .. utils.serialize(ret_val))
    else
        return async_coroutine_resume(async_entry)
    end
end

-- The guts of the async functionality: a trampoline that ensures certain functions are run on the main coroutine (i.e. the coroutine that TW starts all scripts in).
-- All calls to cm.game_interface functions via functions like cm:callback must be run in the main coroutine, or else such methods will crash the game.
local function async_trampoline(id)
    local async_entry = async_entries[id]
    -- Abort if async block is done or canceled.
    if async_entry == nil then
        return
    end
    
    -- Keep resuming coroutine as long as next_trigger_time remains nil. Run any coroutine-yielded function.
    -- This mechanism allows delegation of function calls that must be run in the main coroutine.
    async_entry.next_trigger_time = nil
    --[[
    local co = async_entry.coroutine
    local num_a = 0
    local a1, a2, a3, a4, a5, a_rest -- return values or arguments, with a_rest being an array of the 6th+ values/arguments or nil if <= 5 values/arguments
    repeat
        --out("async_trampoline: main loop: coroutine: " .. tostring(coroutine.running()) .. ", args: {" .. utils.serialize(pass_variadic_args(num_a, a1, a2, a3, a4, a5, a_rest)) ..
        --    "}, next_trigger_time @ " .. tostring(async_entry.next_trigger_time))
        num_a, a1, a2, a3, a4, a5, a_rest = process_async_coroutine_resume_results(async_entry, coroutine.resume(co, pass_variadic_args(num_a, a1, a2, a3, a4, a5, a_rest)))
        if coroutine.status(co) == "dead" then
            --out("async_trampoline: done")
            remove_async_entry(async_entry)
            return
        end
    until async_entry.next_trigger_time ~= nil
    --]]
    local done = async_coroutine_resume(async_entry)
    if done then
        return
    end
    
    local time = os.clock()
    --out("async_trampoline: after main loop: next_trigger_time @ " .. tostring(async_entry.next_trigger_time) .. " vs current time @ " .. tostring(time))
    local faction_cqi = nil -- faction_cqi can be nil, since we're not using it
    if time <= async_entry.next_trigger_time then
        --out("async_trampoline: cm:callback")
        cm:callback(function()
            --out("async_trampoline: cm:callback inner")
            async_trampoline(id)
        end, async_entry.next_trigger_time - time)
    else
        --out("async_trampoline: CampaignUI.TriggerCampaignScriptEvent")
        -- Even for an effective delay of 0 secs, trigger our UITriggerScriptEvent event, and return to let other backlogged events to process (in the main coroutine),
        -- before our UITriggerScriptEvent runs and calls this whole function again.
        CampaignUI.TriggerCampaignScriptEvent(faction_cqi, async_processor_ui_trigger_prefix .. id)
    end
end

core:add_listener(
    "UITriggerScriptEvent:AsyncProcessor",
    "UITriggerScriptEvent",
    function(context)
        return context:trigger():starts_with(async_processor_ui_trigger_prefix)
    end,
    function(context)
        local id = tonumber(context:trigger():sub(string.len(async_processor_ui_trigger_prefix) + 1), 10)
        --out("UITriggerScriptEvent:AsyncProcessor " .. id)
        async_trampoline(id)
    end,
    true
)

setmetatable(async, {
    __call = function(self, func)
        update_all_game_object_functions()
        if coroutine_to_async_entry_id[coroutine.running()] ~= nil then
            -- If we're already in an async, error for now. TODO: allow this case
            error("Nested async is currently not allowed")
        else -- we're in the main coroutine
            local id = new_async_entry(func)
            async_trampoline(id)
            return id
        end
    end
})

local function schedule_async_callback(id, delay)
    local async_entry = async_entries[id]
    async_entry.next_trigger_time = os.clock() + delay
    --out("schedule_async_callback: coroutine " .. tostring(coroutine.running()) .. " @ " .. tostring(async_entry.next_trigger_time) .. " before yielding")
    -- Return control to main coroutine while waiting for an earlier CampaignUI.TriggerCampaignScriptEvent to ultimately trigger.
    coroutine.yield()
end

function async.retry(func, max_tries, delay)
    local id = async.id()
    if id == nil then
        error("async.retry must be run in within a function passed to async")
    end
    
    if max_tries <= 0 then
        error("max_tries (" .. max_tries .. ") must be > 0")
    end
    
    local status, val
    repeat
        status, val = pcall(func)
        if status then
            break
        end
        max_tries = max_tries - 1
        if max_tries == 0 then
            error(val)
        end
        schedule_async_callback(id, delay)
    until status
    return val
end

function async.sleep(delay)
    local id = async.id()
    if id == nil then
        error("async.callback must be run in within a function passed to async")
    end
    schedule_async_callback(id, delay)
end

function async.cancel(id)
    local async_entry = async_entries[id]
    if async_entry then
        -- Signal async_trampoline to stop at next opportunity, i.e. when it's next called via callback.
        coroutine_to_async_entry_id[async_entry.coroutine] = nil
        async_entries[id] = nil
    end
end

-- If called within an async block, returns the async block's id. Else, returns nil.
function async.id()
    return coroutine_to_async_entry_id[coroutine.running()]
end

return async
