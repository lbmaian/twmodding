-- Enables asynchronous programming to avoid callback hell
-- WARNING: EXPERIMENTAL PROOF OF CONCEPT THAT MAY HAVE POOR PERFORMANCE
-- TODO: docs

-- Typical usage:
--  local id = async(function()
--      ... can call async.retry, async.sleep, etc.
--  end)
-- Enables async operations (such as async.retry and async.sleep) within the nullary function passed to async (denoted as the async block).
-- Returns an id that can be used to cancel an ongoing async block at the next opportunity via async.cancel.
-- When created, execution of the async block is deferred until after the current event handler/listener or script load is finished
-- (specifically, when the next UITriggerScriptEvent fires, which async() triggers).
-- Then execution proceeds until the first async operation, during which point, it yields control to the main coroutine,
-- resumes execution at approximately the async operation-specified delay until the next async operation, and so forth, until the async block is finished.
-- To immediately start execution of an async block just created via async(), use async.resume(<async id>).

local utils = cm:load_global_script "lib.lbm_utils"

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

local function update_all_game_object_functions_if_necessary()
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
-- The "loop" essentially keeps resuming the async coroutine as long as next_trigger_time remains nil, running any coroutine-yielded function each iteration.
-- This mechanism allows delegation of function calls that must be run in the main coroutine.
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
    
    -- Main "loop"
    async_entry.next_trigger_time = nil
    local done = async_coroutine_resume(async_entry)
    if done then
        return
    end
    
    local time = os.clock()
    --out("async_trampoline: after main loop: next_trigger_time @ " .. tostring(async_entry.next_trigger_time) .. " vs current time @ " .. tostring(time))
    local cqi = nil -- cqi can be nil, since we're not using it
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
        CampaignUI.TriggerCampaignScriptEvent(cqi, async_processor_ui_trigger_prefix .. id)
    end
end

core:add_listener(
    "UITriggerScriptEvent:async_trampoline",
    "UITriggerScriptEvent",
    function(context)
        return context:trigger():starts_with(async_processor_ui_trigger_prefix)
    end,
    function(context)
        local id = tonumber(context:trigger():sub(string.len(async_processor_ui_trigger_prefix) + 1), 10)
        --out("UITriggerScriptEvent:async_trampoline: id=" .. id)
        async_trampoline(id)
    end,
    true
)

-- async(func)
setmetatable(async, {
    __call = function(self, func)
        update_all_game_object_functions_if_necessary()
        local id = new_async_entry(func)
        CampaignUI.TriggerCampaignScriptEvent(nil, async_processor_ui_trigger_prefix .. id)
        return id
    end
})

function async.resume(id)
    local cur_id = async.id()
    if cur_id == nil then
        async_trampoline(id)
    elseif cur_id ~= id then
        error("Cannot resume an async block (" .. id .. ") inside a currently running async block (" .. cur_id .. ")")
    end -- else, do nothing, since we're already inside an async block.
end

local function schedule_async_callback_and_yield(id, delay)
    local async_entry = async_entries[id]
    async_entry.next_trigger_time = os.clock() + delay
    --out("schedule_async_callback_and_yield: coroutine " .. tostring(coroutine.running()) .. " @ " .. tostring(async_entry.next_trigger_time) .. " before yielding")
    -- Return control to main coroutine while waiting for an earlier CampaignUI.TriggerCampaignScriptEvent to ultimately trigger.
    coroutine.yield()
end

function async.retry(callback, max_tries, base_delay, exponential_backoff, callback_name, success_callback, exhaust_tries_callback, enable_logging)
    if type(callback) == "table" then
        local settings = callback
        callback = settings.callback
        max_tries = settings.max_tries
        base_delay = settings.base_delay
        exponential_backoff = settings.exponential_backoff
        callback_name = settings.callback_name
        success_callback = settings.success_callback
        exhaust_tries_callback = settings.exhaust_tries_callback
        enable_logging = settings.enable_logging
    end
    exponential_backoff = exponential_backoff or 1.0
    
    local id = async.id()
    if id == nil then
        error("async.retry must be run in within an async block")
    end
    
    if max_tries <= 0 then
        error("max_tries (" .. max_tries .. ") must be > 0")
    end
    
    if enable_logging then
        out("async.retry[async block " .. id .. "]" .. utils.serialize({
            callback = callback,
            max_tries = max_tries,
            base_delay = base_delay,
            exponential_backoff = exponential_backoff,
            callback_name = callback_name,
            success_callback = success_callback,
            exhaust_tries_callback = exhaust_tries_callback,
        }))
    end
    
    local delay = base_delay
    local succeeded, value
    repeat
        succeeded, value = pcall(callback)
        if succeeded then
            break
        end
        max_tries = max_tries - 1
        if max_tries == 0 then
            if enable_logging then
                out("async.retry[async block " .. id .. "] => succeeded=false, max_tries=" .. max_tries .. ", error=" .. value .. debug.traceback("", 2))
            end
            error(value)
        else
            if enable_logging then
                out("async.retry[async block " .. id .. "] => succeeded=false, max_tries=" .. max_tries .. ", error=" .. value .. debug.traceback("", 2))
            else
                out("retrying up to " .. max_tries .. " more times after error: " .. value .. debug.traceback("", 2))
            end
        end
        schedule_async_callback_and_yield(id, delay)
        delay = delay * exponential_backoff
        if enable_logging then
            out("async.retry[async block " .. id .. "]" .. utils.serialize({max_tries = max_tries, delay = delay}))
        end
    until succeeded
    if enable_logging then
        out("async.retry[async block " .. id .. "] => succeeded=true, value=" .. utils.serialize(value))
    end
    return value
end

function async.sleep(delay, enable_logging)
    local id = async.id()
    if id == nil then
        error("async.callback must be run in within an async block")
    end
    if enable_logging then
        out("async.sleep[async block " .. id .."](" .. delay ..")")
    end
    schedule_async_callback_and_yield(id, delay)
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
