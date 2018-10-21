-- General utility functions
---------------------------------------------------------------------

local utils = {}

-- Imports all key-values in a table, presumably the public entries in a module, into the current environment.
-- If a key being imported already exists in the current environment, the current value for it is clobbered.
function utils.import(module)
    local env = getfenv(1)
    for k, v in pairs(module) do
        env[k] = v
    end
end

-- Simply returns its given arguments. Can be used as a near-noop callback function.
function utils.passthrough(...)
    return ...
end

-- Convenience function that simply returns true, intended for use as functional argument.
function utils.always_true()
    return true
end

-- Convenience function that simply returns false, intended for use as functional argument.
    function utils.always_false()
    return false
end

-- Serializes value(s) into a string that can be evaluated via loadstring. If multiple values are passed, they are each serialized and concatenated with the "," delimiter.
function utils.serialize(...)
    local arg_len = select("#", ...)
    if arg_len == 0 then
        return ""
    elseif arg_len > 1 then
        local serialized_vals = {}
        for i = 1, arg_len do
            local val = select(i, ...) -- This has to be done in its own statement, since select(i, ...) returns all i-th to arg_len-th arguments
            serialized_vals[i] = utils.serialize(val)
        end
        return table.concat(serialized_vals, ",", 1, arg_len)
    end
    
    local val = select(1, ...)
    if val == nil then
        return "nil"
    end
    local val_type = type(val)
    if val_type == "string" then
        return string.format("%q", val)
    elseif val_type == "number" or val_type == "boolean" then
        return tostring(val)
    elseif val_type == "table" then
        local str_arr = {}
        local len
        if table.is_array(val) then
            len = #val
            for i = 1, len do
                str_arr[i] = utils.serialize(val[i])
            end
        else
            len = 0
            for k, v in pairs(val) do
                len = len + 1
                local key_str = k
                if type(k) ~= "string" or not k:match("^[%a_][%w_]*$") then
                    key_str = "[" .. utils.serialize(k) .. "]"
                end
                str_arr[len] = key_str .. "=" .. utils.serialize(v)
            end
        end
        return "{" .. table.concat(str_arr, ",", 1, len) .. "}"
    else -- unserializable value like function, thread, or userdata - just wrap its tostring value in quotes and angle brackets
        return '"<' .. tostring(val) .. '>"'
    end
end

-- Serializes given value into JSON. Treats tables are JSON objects rather than arrays. Treats nil as JSON null.
-- WARNING: Cyclic references will cause an infinite recursion.
function utils.to_json(val)
    if val == nil then
        return "null"
    end
    local val_type = type(val)
    if val_type == "table" then
        return table.to_json(val)
    elseif val_type == "number" or val_type == "boolean" then
        return tostring(val)
    elseif val_type == "string" then
        return string.to_json(val)
    else -- unserializable value like function, thread, or userdata - just wrap its tostring value in quotes and angle brackets
        return '"<' .. tostring(val) .. '>"'
    end
end

-- If given value is not a table, simply returns the given value.
-- If given value is is a table, then shallow copies the table into a second table, optionally passed in as the second argument.
-- If this second argument is not a table (e.g. is omitted), then a new table is created with the same metatable as the given table.
function utils.shallow_copy(t, new_t)
    if type(t) ~= 'table' then
        return t
    end
    if type(new_t) ~= 'table' then
        new_t = {}
        setmetatable(new_t, getmetatable(t))
    end
    for k, v in next, t do
        new_t[k] = v
    end
    return new_t
end

-- If given value is not a table, simply returns the given value.
-- If given value is is a table, then deep copies the table into a second table, optionally passed in as the second argument.
-- If this second argument is not a table (e.g. is omitted), then a new table is created with the same metatable as the given table.
-- WARNING: Cyclic references will cause an infinite recursion.
function utils.deep_copy(t, new_t)
    if type(t) ~= 'table' then
        return t
    end
    if type(new_t) ~= 'table' then
        new_t = {}
        setmetatable(new_t, getmetatable(t))
    end
    setmetatable(new_t, getmetatable(t))
    for k, v in next, t do
        new_t[utils.deep_copy(k)] = utils.deep_copy(v)
    end
    return new_t
end

-- Helper function for utils.timed_run, taking advantage of the fact that arguments (whether function arguments, return arguments, assignment right-hand-side arguments)
-- are evaluated from left to right in Lua.
local function prepend_time_diff(start_time, ...)
    return os.difftime(os.clock(), start_time), ...
end

-- Calls the given function with given arguments and returns the CPU time (in seconds) it took for that call, along with all that call's return values.
-- For example:
--  function expensive_function(x, y, z)
--      -- expensive operations...
--      return a, b, c, d
--  end
--  local time_diff, my_a, my_b, my_c, my_d = utils.timed_call(expensive_function, my_x, my_y, my_z)
function utils.timed_call(func, ...)
    return prepend_time_diff(os.clock(), func(...))
end


-- Lua Standard Library extensions
---------------------------------------------------------------------

function string.to_json(s)
    return string.gsub(string.format("%q", s), "\\\n", "\\n")
end

function string.at(s, i)
    return string.char(string.byte(s, i)) -- apparently a bit faster than string.sub(s, i, i)
end

-- XXX: There seems to be a string.sub bug where if the end string length is greater than the input string length, the game crashes.
-- I can only replicate this bug in the Lua embedded within TW, not on any other Lua 5.1.x version I can build or otherwise get my hands on.
-- The game also crashes whenever string.sub is called in a non-main coroutine (i.e. a coroutine that's not the one that scripts start in).
-- So redefining string.sub here to avoid such crashes.
-- Technically, this redefinition allows i to be omitted, while string.sub should disallow it, but other than that, I can't find any other behavioral difference.
-- Somehow, this is also a bit faster than the original string.sub.
string._orig_sub = string.sub --luacheck:no global
function string.sub(s, i, j) --luacheck:no global
    if j == nil then
        j = -1
    end
    return string.char(string.byte(s, i, j))
end

-- string.starts_with(s, start_str) already implemented in lib_common.lua.
-- string.ends_with(s, end_str) already implemented in lib_common.lua.

-- Convenience function that simply returns a new empty table, intended for use as functional argument.
function table.new()
    return {}
end

function table.includes(t, value)
    for _, v in pairs(t) do
        if v == value then
            return true
        end
    end
    return false
end

function table.key_of(t, value)
    for k, v in pairs(t) do
        if v == value then
            return k
        end
    end
    return nil
end

function table.find(t, pred)
    for k, v in pairs(t) do
        if pred(v, k) then
            return v, k
        end
    end
    return nil, nil
end

function table.some(t, pred)
    for k, v in pairs(t) do
        if pred(v, k) then
            return true
        end
    end
    return false
end

function table.every(t, pred)
    for k, v in pairs(t) do
        if not pred(v, k) then
            return false
        end
    end
    return true
end

function table.for_each(t, func)
    for k, v in pairs(t) do
        func(v, k)
    end
end

function table.map(t, func)
    local new_t = {}
    setmetatable(new_t, getmetatable(t))
    for k, v in pairs(t) do
        new_t[k] = func(v, k)
    end
    return new_t
end

function table.filter_array(t, pred)
    local new_t = {}
    setmetatable(new_t, getmetatable(t))
    local size = 1
    for i, v in ipairs(t) do
        if pred(v, i) then
            new_t[size] = v
            size = size + 1
        end
    end
    return new_t
end

function table.filter(t, pred)
    local new_t = {}
    setmetatable(new_t, getmetatable(t))
    for k, v in pairs(t) do
        if pred(v, k) then
            new_t[k] = v
        end
    end
    return new_t
end

function table.reduce(t, acc_func, init_value)
    local value = init_value
    for k, v in pairs(t) do
        value = acc_func(value, v, k)
    end
    return value
end

function table.merge(t1, t2)
    local new_t = {}
    setmetatable(new_t, getmetatable(t1))
    return table.merge_in_place(table.merge_in_place(new_t, t1), t2)
end

function table.merge_in_place(t1, t2)
    for k, v in pairs(t2) do
        t1[k] = v
    end
    return t1
end

function table.is_array(t)
    local i = 1
    for _ in pairs(t) do -- do n iterations where n = # entries in t, don't care about the actual iterated values
        if t[i] == nil then
            return false
        end
        i = i + 1
    end
    return true
end

function table.to_json(t)
    if table.is_array(t) then
        local arr = {}
        local len = #t
        for i = 1, len do
            arr[i] = utils.to_json(t[i])
        end
        return "[" .. table.concat(arr, ",", 1, len) .. "]"
    else
        local arr = {}
        local len = 0
        for k, v in pairs(t) do
            len = len + 1
            arr[len] = '"' .. tostring(k) .. '": ' .. utils.to_json(v)
        end
        return "{" .. table.concat(arr, ",", 1, len) .. "}"
    end
end

function math.round(x)
    return math.floor(0.5 + x)
end


-- TW:WH utility functions --
---------------------------------------------------------------------

-- Retries given callback until either given max tries or callback does not error or given max tries, with a given (re)try delay in secs and with an optional exponential backoff.
-- If the callback does not error before max tries, calls the given success_callback with the first callback's return value.
-- If the callback keeps erroring by max tries, calls the given exhaust_tries_callback with no argument.
-- Inputs can be passed to this function in one of two ways:
-- a) As standard sequential function parameters as shown in the function signature: callback, max_tries, base_delay, exponential_backoff, callback_name, success_callback, exhaust_tries_callback.
-- b) As a single settings table where each key corresponds to a parameter in the function signature (e.g. max_tries) and the value is the input for that parameter.
-- The following parameters can be omitted (or passes as nil):
-- * exponential_backoff (defaults to 1.0)
-- * callback_name (defaults to nil)
-- * success_callback (defaults to noop)
-- * exhaust_tries_callback (defaults to noop).
function utils.retry_callback(callback, max_tries, base_delay, exponential_backoff, callback_name, success_callback, exhaust_tries_callback)
    if type(callback) == "table" then
        local settings = callback
        callback = settings.callback
        max_tries = settings.max_tries
        base_delay = settings.base_delay
        exponential_backoff = settings.exponential_backoff
        callback_name = settings.callback_name
        success_callback = settings.success_callback
        exhaust_tries_callback = settings.exhaust_tries_callback
    end
    exponential_backoff = exponential_backoff or 1.0
    
    if max_tries <= 0 then
        error("max_tries (" .. max_tries .. ") must be > 0")
    end
    
    out("retry_callback" .. utils.serialize({
        callback = callback,
        max_tries = max_tries,
        base_delay = base_delay,
        exponential_backoff = exponential_backoff,
        callback_name = callback_name,
        success_callback = success_callback,
        exhaust_tries_callback = exhaust_tries_callback,
    }))
    
    local succeeded, value = pcall(callback)
    out("=> succeeded=" .. tostring(succeeded) .. ", value=" .. utils.serialize(value))
    if succeeded then
        if success_callback then
            success_callback(value)
        end
        return
    end
    
    max_tries = max_tries - 1
    if max_tries == 0 then
        if exhaust_tries_callback then
            exhaust_tries_callback(value)
        end
        return
    end
    
    cm:callback(function()
        utils.retry_callback(callback, max_tries, base_delay * exponential_backoff, exponential_backoff, callback_name, success_callback, exhaust_tries_callback)
    end, base_delay, callback_name)
end

-- Adds a UITriggerScriptEvent event listener that conditions on the given CQI (typically faction CQI, can be nil) and event name
-- and calls the given handler with all arguments passed to the trigger_custom_ui_event() call except the first arg (event_name).
-- For example: trigger_custom_ui_event(event_name, cqi, 1, "x", {a=0}) results in the handler for event_name being called with arguments (cqi, 1, "x", {a=0}).
function utils.add_custom_ui_event_listener(event_name, handler, persistent)
    if persistent == nil then
        persistent = true
    end
    core:add_listener(
        "UITriggerScriptEvent_" .. event_name,
        "UITriggerScriptEvent",
        function(context)
            return context:trigger():starts_with(event_name .. string.char(31))
        end,
        function(context)
            local cqi, trigger_str = context:faction_cqi(), context:trigger()
            out.ui("UITriggerScriptEvent: cqi=" .. tostring(cqi) .. ", trigger=" .. tostring(trigger_str))
            local return_args_str = trigger_str:sub(event_name:len() + 1 + 1) -- looks like e.g. "<event_name>,{key=value}" or "'arg1', 'arg2'"
            handler(cqi, loadstring("return " .. return_args_str)()) -- calls handler with the cqi and all returned args
        end,
        persistent
    )
end

-- Triggers a UITriggerScriptEvent with a specially serialized trigger string and CQI (typically faction CQI, can be nil)
-- that the handler given to add_custom_ui_event_listener() can parse. See add_custom_ui_event_listener() for an example.
function utils.trigger_custom_ui_event(event_name, cqi, ...)
    local trigger_str = event_name .. string.char(31) .. utils.serialize(...)
    out.ui("trigger_custom_ui_event: cqi=" .. cqi .. ", trigger=" .. trigger_str)
    CampaignUI.TriggerCampaignScriptEvent(cqi, trigger_str)
end

-- Weak set of callbacks, so that when the callback is gc'ed, it'll be automatically cleaned from this table
local core_monitor_performance_blacklist = setmetatable({}, {__mode = "k"})

-- Override core:monitor_performance to allow conditional disabling of the performance monitoring based off a blacklist.
local orig_core_monitor_performance = core.monitor_performance
function core.monitor_performance(self, callback, time_limit, name)
    -- If in the blacklist, just call the callback without performance monitoring.
    if core_monitor_performance_blacklist[callback] then
        callback()
    else
        orig_core_monitor_performance(self, callback, time_limit, name)
    end
end

-- Creates a callback via cm:callback while disabling performance monitoring (that can cause the "PERFORMANCE WARNING" to be logged) for this callback.
function utils.callback_without_performance_monitor(callback, time, name)
    local ret_val = cm:callback(callback, time, name)
    core_monitor_performance_blacklist[callback] = true -- only add to blacklist if cm:callback didn't fail
    return ret_val
end

function utils.campaign_obj_to_string(input)
    if is_character(input) then
        local s = cm:campaign_obj_to_string(input) .. ", type[" .. input:character_type_key() .. "], subtype[" .. input:character_subtype_key() .. "]"
        if input:has_military_force() then
            return s .. " @ " .. cm:campaign_obj_to_string(input:military_force())
        else
            return s
        end
    elseif is_militaryforce(input) then
        local s = "MILITARY_FORCE faction[" .. input:faction():name() .. "] units[" .. tostring(input:unit_list():num_items()) .. "], upkeep[" .. tostring(input:upkeep()) .. "]"
        if input:has_general() then
            local char = input:general_character()
            return s .. " WITH " .. cm:campaign_obj_to_string(char) .. ", type[" .. char:character_type_key() .. "], subtype[" .. char:character_subtype_key() .. "]"
        else
            return s .. ", general: [none], logical pos[unknown]"
        end
    -- XXX: Some unit methods like military_force() cause crashes under certain circumstances (such as during a UnitCreated event), so don't special case here.
    -- elseif is_unit(input) then
    else
        return cm:campaign_obj_to_string(input)
    end
end

function utils.output_all_uicomponent_children(uic)
    if not is_uicomponent(uic) or not uic:Id() then
        out.ui(utils.to_json(uic))
        return
    end
    local function out_non_empty(prop)
        local val = uic[prop](uic)
        if val ~= nil and val ~= "" then
            out.ui(prop .. ":\t\t" .. utils.to_json(val))
        end
    end
    --if uic:Visible() and is_fully_onscreen(uic) then
        --output_uicomponent(uic, true)
        out.ui(uicomponent_to_str(uic))
        out.inc_tab("ui")
        out.ui("Visible:\t\t" .. utils.to_json(uic:Visible()))
        out.ui("Priority:\t\t" .. utils.to_json(uic:Priority()))
        out.ui(string.format("Position:\t\tx=%d, y=%d", uic:Position()))
        out.ui(string.format("Bounds:\t\tx=%d, y=%d", uic:Bounds()))
        out.ui(string.format("Dimensions:\t\tx=%d, y=%d", uic:Dimensions()))
        out.ui("Height:\t\t" .. utils.to_json(uic:Height()))
        out.ui("Width:\t\t" .. utils.to_json(uic:Width()))
        out.ui(string.format("TextDimensions:\t\tx=%d, y=%d, l=%d", uic:TextDimensions()))
        out.ui("CurrentState:\t\t" .. utils.to_json(uic:CurrentState()))
        out_non_empty("CurrentStateUI")
        out_non_empty("GetStateText")
        out_non_empty("GetStateTextDetails")
        out_non_empty("GetTooltipText")
        out_non_empty("CurrentAnimationId")
        out_non_empty("DockingPoint")
        out_non_empty("CallbackId")
        out.ui("HasInterface\t\t: " .. utils.to_json(uic:HasInterface()))
        out.dec_tab("ui")
    --else
    --    out.ui(uicomponent_to_str(uic))
    --end
    for i = 0, uic:ChildCount() - 1 do
        local uic_child = UIComponent(uic:Find(i))
        utils.output_all_uicomponent_children(uic_child)
    end
end

-- Convenience function for getting faction by CQI (if integer is passed) or name (if string is passed).
-- Also supposedly significantly faster than cm:get_faction if looking up by faction name (by skipping the world:faction_exists check?).
function utils.get_faction(faction_cqi_or_name)
    local input_type = type(faction_cqi_or_name)
    if input_type == "number" then
        return cm:model():faction_for_command_queue_index(faction_cqi_or_name)
    elseif input_type == "string" then
        return cm:model():world():faction_by_key(faction_cqi_or_name)
    else
        error("get_faction: expected faction CQI (integer) or faction name (string)")
    end
end

function utils.uic_resize(uic, width, height)
    uic:SetCanResizeWidth(true)
    uic:SetCanResizeHeight(true)
    uic:Resize(width, height)
    uic:SetCanResizeWidth(false)
    uic:SetCanResizeHeight(false)
end

return utils
