-- Functionality to disable our custom UI listeners.

local custom_ui_listeners_enabled = true

local custom_ui_listeners = {}

-- Disables our custom UI listeners while calling given func with no arguments.
-- If return_pcall_rvs is true, then directly returns the return vals of the internal pcall.
function custom_ui_listeners.disable_during_call(func, return_pcall_rvs)
    local old_enabled = custom_ui_listeners_enabled
    custom_ui_listeners_enabled = false
    local ret_status, val = pcall(func)
    custom_ui_listeners_enabled = old_enabled
    if return_pcall_rvs then
        return ret_status, val
    else
        if ret_status then
            return val
        else
            error(val)
        end
    end
end

-- Custom UI listeners should use this function as their condition.
function custom_ui_listeners.enabled()
    return custom_ui_listeners_enabled
end

return custom_ui_listeners
