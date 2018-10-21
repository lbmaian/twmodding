-- Provides a singleton that tracks and adds output to each event handler and listener and script timer being fired. Meant for debugging purposes.
-- Event handlers are the functions on each list of the events object.
-- Event listeners include the functions that are added via core:add_listener.
-- Script timers include the functions that are added via cm:callback.
-- Internally, all event listeners for a particular event name are done in an event handler, while all script timers are done in a TimeTrigger event listener.

-- Note: Only including lbm_utils for the new methods it adds to table et al, rather than functions on lbm_utils itself.
cm:load_global_script "lib.lbm_utils"

local events_tracker = {
    logging_level = 0,
    all_event_handler_records = nil,
    event_listener_records = nil,
    event_listener_to_record = nil,
    orig_core_add_listener = nil,
    orig_core_clean_listeners = nil,
    orig_core_remove_listener = nil,
    script_timer_records = nil,
    orig_cm_callback = nil,
    orig_cm_remove_callback = nil,
}

function events_tracker.enabled()
    return events_tracker.logging_level > 0
end

-- Enables tracking (simple log output) of each event handler and listener being fired.
-- Optional argument specifies the logging level to enable it. If omitted, defaults to logging level 1.
-- * Log level 1: Only logs when handlers/listeners/timers fire.
-- * Log level 2: Also logs when handlers/listeners/timers are added or removed.
-- * Log level 3: Also logs each handler/listener/timer that exists upon enabling and disabling.
-- To disable event tracking, call events_tracker.disable().
-- WARNING: This may cause an initial noticeable pause while executing, especially at higher log levels, and continues to slow the game down until disabled.
function events_tracker.enable(logging_level)
    if logging_level == nil then
        logging_level = 1
    elseif logging_level < 1 then
        error("[event] logging level must be >=1")
    end
    if events_tracker.logging_level > 1 then
        if events_tracker.logging_level ~= logging_level then
            events_tracker.logging_level = logging_level
            out("[event] tracking already enabled - updating logging level to " .. logging_level)
        else
            out("[event] tracking already enabled at logging level " .. logging_level)
        end
        return
    end
    
    local events = get_events()
    local all_event_handler_records = {}
    events_tracker.all_event_handler_records = all_event_handler_records
    
    local function track_event_handler(event_name, i)
        local event_handlers = events[event_name]
        local event_handler_records = all_event_handler_records[event_name]
        if not event_handler_records then
            event_handler_records = {}
            all_event_handler_records[event_name] = event_handler_records
        end
        local event_handler_record = {
            orig_handler = event_handlers[i],
            desc = event_name .. (event_handlers[i] and " handler " .. i or " temporary handler"),
        }
        event_handler_records[i] = event_handler_record
        event_handlers[i] = function(context, ...)
            out("[event] firing " .. event_handler_record.desc .. ": string => " .. tostring(context.string))
            --out("[event] firing " .. event_handler_record.desc .. ": string => " .. tostring(context.string) .. " - context interface: " .. tostring(getmetatable(context)))
            if event_handler_record.orig_handler then
                return event_handler_record.orig_handler(context, ...)
            end
        end
        event_handler_record.new_handler = event_handlers[i]
        if events_tracker.logging_level >= 3 then
            out("[event] enabled tracking of " .. event_handler_record.desc)
        end
        return event_handler_record
    end
    
    for event_name, event_handlers in pairs(events) do
        if event_name == "_NAME" or event_name == "_M" or event_name == "_PACKAGE" then
            -- These are 'hidden' properties added by the module() call within events.lua, so ignore them.
        else
            local event_handler_records = all_event_handler_records[event_name]
            if not event_handler_records then
                event_handler_records = {}
                all_event_handler_records[event_name] = event_handler_records
            end
            local num_event_handlers = #event_handlers
            if num_event_handlers == 0 then
                track_event_handler(event_name, 1)
            else
                for i = 1, num_event_handlers do
                    track_event_handler(event_name, i)
                end
            end
        end
    end
    
    local event_listener_records, event_listener_to_record = {}, {}
    events_tracker.event_listener_records, events_tracker.event_listener_to_record = event_listener_records, event_listener_to_record
    
    local function track_event_listener(event_listener, adjective, cur_logging_level, req_logging_level)
        local event_listener_record = {
            event_listener = event_listener,
            orig_condition = event_listener.condition,
            orig_callback = event_listener.callback,
            desc = (event_listener.persistent and "" or "non-persistent ") .. event_listener.event .. " listener " .. event_listener.name,
        }
        if type(event_listener.condition) ~= 'boolean' then
            event_listener.condition = function(context, ...)
                local ret_status, ret_val = pcall(event_listener_record.orig_condition, context, ...)
                if ret_status then
                    if not ret_val then
                        out("[event] not firing " .. event_listener_record.desc .. ": condition => " .. tostring(ret_val) .. "; string => " .. tostring(context.string))
                    end
                    return ret_val
                else
                    out("[event] not firing " .. event_listener_record.desc .. ": condition => ERROR: " .. tostring(ret_val) .. "; string => " .. tostring(context.string))
                    error(ret_val)
                end
            end
        end
        event_listener.callback = function(context, ...)
            out("[event] firing " .. event_listener_record.desc .. ": string => " .. tostring(context.string))
            return event_listener_record.orig_callback(context, ...)
        end
        if cur_logging_level >= req_logging_level then
            out("[event] enabled tracking of " .. adjective .. event_listener_record.desc)
        end
        event_listener_to_record[event_listener] = event_listener_record
        event_listener_records[#event_listener_records + 1] = event_listener_record
        return event_listener_record
    end
    
    local event_listeners = core.event_listeners
    for i = 1, #event_listeners do
        track_event_listener(event_listeners[i], "", logging_level, 3)
    end
    
    local orig_core_add_listener = core.add_listener
    events_tracker.orig_core_add_listener = orig_core_add_listener
    core.add_listener = function(self, new_name, event_name, ...)
        -- Add new event handler if one's going to be created by add_listener.
        local old_num_event_handlers = #(events[event_name] or {})
        core:attach_to_event(event_name)
        local new_num_event_handlers = #events[event_name]
        if old_num_event_handlers ~= new_num_event_handlers then
            track_event_handler(event_name, new_num_event_handlers)
        end
        
        local success = orig_core_add_listener(self, new_name, event_name, ...)
        if success == false then -- check for explicit false, don't include nil
            return false
        end
        track_event_listener(event_listeners[#event_listeners], "new ", events_tracker.logging_level, 2)
    end
    
    -- Note: core.clean_listeners and core.remove_listener are recursive functions, which are hard to hook into, so just replace them wholesale.
    -- They also provide convenient opportunities to track any event listeners that we somehow missed.
    local function remove_event_listeners(predicate, untracked_listener_callback, postfix_phrase, cur_logging_level)
        for i = #event_listener_records, 1, -1 do
            local event_listener_record = event_listener_records[i]
            local event_listener = event_listener_record.event_listener
            if predicate(event_listener) then
                table.remove(event_listener_records, i)
                local j = i
                if event_listeners[i] ~= event_listener then
                    j = table.key_of(event_listeners, event_listener)
                end
                if j then
                    table.remove(event_listeners, j)
                    if cur_logging_level >= 2 then
                        out("[event] removed " .. event_listener_record.desc .. postfix_phrase)
                    end
                else
                    out("[event] WARNING: could not find (to remove) tracked " .. event_listener_record.desc)
                end
            end
        end
        
        for i = #event_listeners, 1, -1 do
            local event_listener = event_listeners[i]
            if not event_listener_to_record[event_listener] then
                local will_remove = predicate(event_listener)
                untracked_listener_callback(event_listener, will_remove)
                if will_remove then
                    table.remove(event_listeners, i)
                    if cur_logging_level >= 2 then
                        local event_listener_desc = (event_listener.persistent and "" or "non-persistent ") .. event_listener.event .. " listener " .. event_listener.name
                        out("[event] removed " .. event_listener_desc .. postfix_phrase)
                    end
                end
            end
        end
    end
    
    local orig_core_clean_listeners = core.clean_listeners
    events_tracker.orig_core_clean_listeners = orig_core_clean_listeners
    core.clean_listeners = function(self)
        remove_event_listeners(function(event_listener) -- predicate
            return event_listener.to_remove
        end, function(event_listener, will_remove) -- untracked_listener_callback
            -- Even if removing this missed event listener, we're going to track it, since it's about to fire once
            track_event_listener(event_listener, "previously unexpectedly non-tracked ", events_tracker.logging_level, 2)
        end, " (about to fire once)", events_tracker.logging_level)
    end
    
    local orig_core_remove_listener = core.remove_listener
    events_tracker.orig_core_remove_listener = orig_core_remove_listener
    core.remove_listener = function(self, listener_name)
        remove_event_listeners(function(event_listener) -- predicate
            return event_listener.name == listener_name
        end, function(event_listener, will_remove) -- untracked_listener_callback
            if not will_remove then -- if it's being removed, don't bother tracking it
                track_event_listener(event_listener, "previously unexpectedly non-tracked ", events_tracker.logging_level, 2)
            end
        end, "", events_tracker.logging_level)
    end
    
    local script_timer_records = {}
    events_tracker.script_timer_records = script_timer_records
    
    local function track_script_timer(id, script_timer, adjective, cur_logging_level, req_logging_level)
        local script_timer_record = {
            id = id,
            script_timer = script_timer,
            orig_callback = script_timer.callback,
            desc = "script timer " .. id .. (script_timer.name and " named " .. script_timer.name or ""),
        }
        script_timer.callback = function(...)
            out("[event] one-time firing " .. script_timer_record.desc)
            script_timer_records[id] = nil
            script_timer_record.orig_callback(...)
        end
        if cur_logging_level >= req_logging_level then
            out("[event] enabled tracking of " .. adjective .. script_timer_record.desc)
        end
        script_timer_records[id] = script_timer_record
        return script_timer_record
    end
    
    local script_timers = cm.script_timers
    for id, script_timer in pairs(script_timers) do
        track_script_timer(id, script_timer, "", logging_level, 3)
    end
    
    local orig_cm_callback = cm.callback
    events_tracker.orig_cm_callback = orig_cm_callback
    cm.callback = function(...)
        -- Get next script timer's id by copying logic in cm:callback.
        local new_id = 0
        while script_timers[new_id] do
            new_id = new_id + 1
        end
        local success = orig_cm_callback(...)
        if success == false then -- check for explicit false, don't include nil
            return false
        end
        local script_timer = script_timers[new_id]
        track_script_timer(new_id, script_timer, "new ", events_tracker.logging_level, 2)
    end
    
    local orig_cm_remove_callback = cm.remove_callback
    events_tracker.orig_cm_remove_callback = orig_cm_remove_callback
    cm.remove_callback = function(self, name)
        for id, script_timer_record in pairs(script_timer_records) do
            local script_timer = script_timer_record.script_timer
            if script_timer.name == name then
                script_timer_records[id] = nil
                if events_tracker.logging_level >= 2 then
                    out("[event] removed " .. script_timer_record.desc)
                end
            end
        end
        orig_cm_remove_callback(self, name)
    end
    
    events_tracker.logging_level = logging_level
    out("[event] tracking enabled")
end

-- Disables tracking added via events_tracker:enable().
-- WARNING: This may cause a noticeable pause while executing.
function events_tracker.disable()
    local logging_level = events_tracker.logging_level
    if logging_level == 0 then
        out("[event] tracking already disabled")
        return
    end
    
    local events = get_events()
    for event_name, event_handler_records in pairs(events_tracker.all_event_handler_records) do
        local event_handlers = events[event_name]
        if type(event_handlers) ~= "table" then
            out("[event] WARNING: event handlers for " .. event_name .. " are of type '" .. type(event_handlers) .. "' instead of expected type 'table'")
        end
        if event_handlers then
            for i = 1, #event_handler_records do
                local event_handler_record = event_handler_records[i]
                local j = i
                if event_handlers[i] ~= event_handler_record.new_handler then
                    j = table.key_of(event_handlers, event_handler_record.new_handler)
                end
                if j then
                    if event_handler_record.orig_handler == nil then
                        table.remove(event_handlers, j)
                        if logging_level >= 3 then
                            out("[event] removed temporary " .. event_name .. " handler")
                        end
                    else
                        event_handlers[j] = event_handler_record.orig_handler
                        if logging_level >= 3 then
                            out("[event] disabled tracking of " .. event_name .. " handler " .. i)
                        end
                    end
                else
                    out("[event] WARNING: could not find (to disable) tracking of " .. event_name .. " handler " .. i)
                end
            end
        end
    end
    
    local event_listeners = core.event_listeners
    local event_listener_records = events_tracker.event_listener_records
    for i = 1, #event_listener_records do
        local event_listener_record = event_listener_records[i]
        local event_listener = event_listener_record.event_listener
        event_listener.condition = event_listener_record.orig_condition
        event_listener.callback = event_listener_record.orig_callback
        local j = i
        if event_listeners[i] ~= event_listener then
            j = table.key_of(event_listeners, event_listener)
        end
        if j then
            if logging_level >= 3 then
                out("[event] disabled tracking of " .. event_listener_record.desc)
            end
        else
            out("[event] WARNING: could not find (to disable) tracking of " .. event_listener_record.desc)
        end
    end
    
    core.add_listener = events_tracker.orig_core_add_listener
    core.clean_listeners = events_tracker.orig_core_clean_listeners
    core.remove_listener = events_tracker.orig_core_remove_listener
    
    local script_timers = cm.script_timers
    for id, script_timer_record in pairs(events_tracker.script_timer_records) do
        local script_timer = script_timer_record.script_timer
        script_timer.callback = script_timer_record.orig_callback
        if script_timers[id] == script_timer then
            if logging_level >= 3 then
                out("[event] disabled tracking of " .. script_timer_record.desc)
            end
        else
            out("[event] WARNING: could not find (to disable) tracking of " .. script_timer_record.desc)
        end
    end
    
    cm.callback = events_tracker.orig_cm_callback
    cm.remove_callback = events_tracker.orig_cm_remove_callback
    
    -- Nil out the fields with table values to help with gc
    events_tracker.all_event_handler_records = nil
    events_tracker.event_listener_records = nil
    events_tracker.event_listener_to_record = nil
    events_tracker.script_timer_records = nil
    
    events_tracker.logging_level = 0
    out("[event] tracking disabled")
end

-- Temporarily adds output to each event handler and listener being fired during the call of given func and arguments.
-- Optional first argument specifies the logging level to enable it. If omitted, defaults to logging level 1.
-- Internally uses events_tracker.enable() and events_tracker.disable() - see WARNINGs in their docs.
function events_tracker.enable_during_call(logging_level, func, ...)
    local ret_status, ret_val
    if type(logging_level) == "function" then
        -- Then logging_level was omitted, and logging_level is actually the function, and func is the first argument to the function call.
        events_tracker.enable()
        ret_status, ret_val = pcall(logging_level, func, ...)
    else
        events_tracker.enable(logging_level)
        ret_status, ret_val = pcall(func, ...)
    end
    events_tracker.disable()
    if ret_status then
        return ret_val
    else
        error(ret_val)
    end
end

return events_tracker
