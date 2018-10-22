--Vanish's PCaller
--All credits to vanish (with some minor scaffolding by lbm)
--cm:load_global_script "lib.vanish_safe_caller" to enable. Ensure this is called early, since this only affects script-triggered event handlers, CM callbacks, and new event listeners.

--v function(func: function) --> any
local function safeCall(func)
    local status, result = pcall(func)
    if not status then
        out("LUA ERROR DETECTED")
        out(tostring(result))
        out(debug.traceback())
    end
    
    return result
end

--v [NO_CHECK] function(...: any)
local function pack2(...) return {n=select('#', ...), ...} end
--v [NO_CHECK] function(t: vector<WHATEVER>) --> vector<WHATEVER>
local function unpack2(t) return unpack(t, 1, t.n) end
    
--v [NO_CHECK] function(f: function(), argProcessor: function()) --> function()
local function wrapFunction(f, argProcessor)
    return function(...)
        local someArguments = pack2(...)
        if argProcessor then
            safeCall(function() argProcessor(someArguments) end)
        end
        local result = pack2(safeCall(function() return f(unpack2( someArguments )) end))
        return unpack2(result)
        end
end

core.trigger_event = wrapFunction(
    core.trigger_event,
    function(ab)
    end
)

cm.check_callbacks = wrapFunction(
    cm.check_callbacks,
    function(ab)
    end
)

local currentAddListener = core.add_listener
--v [NO_CHECK] function(core: any, listenerName: any, eventName: any, conditionFunc: any, listenerFunc: any, persistent: any)
local function myAddListener(core, listenerName, eventName, conditionFunc, listenerFunc, persistent)
    local wrappedCondition
    if is_function(conditionFunc) then
        --wrappedCondition =  wrapFunction(conditionFunc, function(arg) output("Callback condition called: " .. listenerName .. ", for event: " .. eventName) end)
        wrappedCondition =  wrapFunction(conditionFunc)
    else
        wrappedCondition = conditionFunc
    end
    currentAddListener(
        core, listenerName, eventName, wrappedCondition, wrapFunction(listenerFunc), persistent
        --core, listenerName, eventName, wrappedCondition, wrapFunction(listenerFunc, function(arg) output("Callback called: " .. listenerName .. ", for event: " .. eventName) end), persistent
    )
end
core.add_listener = myAddListener

out("Vanish safe caller enabled")
