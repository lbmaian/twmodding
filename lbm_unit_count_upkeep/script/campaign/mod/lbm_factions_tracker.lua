-- Keeps track of army and unit counts per faction, along with some utility faction-related functions.

local utils = cm:load_global_script "lib.lbm_utils"

local factions_tracker = {}

function factions_tracker.new(army_filter)
    local self = {
        army_filter = army_filter or utils.always_true,
        current_army_count_per_faction = {}, -- locally cached value
        current_unit_count_per_faction = {}, -- locally cached value
        --[[
        army_count_change_listeners = {}, -- list of functions with signature function(faction, old_army_count, new_army_count) => <true to remove this listener>
        unit_count_change_listeners = {}, -- list of functions with signature function(faction, old_unit_count, new_unit_count) => <true to remove this listener>
        --]]
    }
    setmetatable(self, {__index = factions_tracker})
    return self
end

-- Computes the faction's current # valid armies and # units in all such armies (where valid is determined by is_valid_army),
-- storing them in a local cache keyed by faction name, and returning them as (# armies, # units) tuple.
function factions_tracker:refresh(faction)
    local army_count = 0
    local unit_count = 0
    
    -- Count all units in non-garrison/non-black-ark armies, including lords and heroes
    local mf_list = faction:military_force_list()
    local army_filter = self.army_filter
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
    
    --[[
    local old_army_count = self.current_army_count_per_faction[faction_name]
    if old_army_count ~= army_count then
        local new_army_count_change_listeners = {}
        for i = 1, #self.army_count_change_listeners do
            local remove_listener = self.army_count_change_listeners[i](faction, old_army_count, army_count)
            if not remove_listener then
                new_army_count_change_listeners[#new_army_count_change_listeners + 1] = self.army_count_change_listeners[i]
            end
        end
        self.army_count_change_listeners = new_army_count_change_listeners
        self.current_army_count_per_faction[faction_name] = army_count
    end
    
    local old_unit_count = self.current_unit_count_per_faction[faction_name]
    if old_unit_count ~= unit_count then
        local new_unit_count_change_listeners = {}
        for i = 1, #self.unit_count_change_listeners do
            local remove_listener = self.unit_count_change_listeners[i](faction, old_unit_count, unit_count)
            if not remove_listener then
                new_unit_count_change_listeners[#new_unit_count_change_listeners + 1] = unit_count_change_listeners[i]
            end
        end
        self.unit_count_change_listeners = new_unit_count_change_listeners
        self.current_unit_count_per_faction[faction_name] = unit_count
    end
    --]]
    
    self.current_army_count_per_faction[faction_name] = army_count
    self.current_unit_count_per_faction[faction_name] = unit_count
    out("factions_tracker:refresh for " .. faction_name .. ": army_count = " .. army_count .. ", unit_count = " .. unit_count)
    return army_count, unit_count
end

-- Gets the faction's current # valid armies and # units in all such armies (where valid is determined by is_valid_army) as a (# armies, # units) tuple.
-- This is a memoized function, returning the cached value if found; otherwise, it calls self:refresh to (re)compute them.
function factions_tracker:get(faction)
    local faction_name = faction:name()
    local army_count = self.current_army_count_per_faction[faction_name]
    if army_count ~= nil then
        -- Assume army_count and unit_count are always computed together (they are), so don't need to check whether current_unit_count_per_faction[faction_name] exists.
        local unit_count = self.current_unit_count_per_faction[faction_name]
        return army_count, unit_count
    end
    return self:refresh(faction)
end

function factions_tracker:get_army_count(faction)
    local army_count, _ = self:get(faction)
    return army_count
end

function factions_tracker:get_unit_count(faction)
    local _, unit_count = self:get(faction)
    return unit_count
end

-- Find n-th valid army (as military force object) for faction, index starting from 1. Returns nil if not found.
function factions_tracker:get_nth_valid_army(faction, n)
    local mf_list = faction:military_force_list()
    local army_filter = self.army_filter
    local army_count = 0
    for i = 0, mf_list:num_items() - 1 do
        local mf = mf_list:item_at(i)
        if army_filter(mf) then
            army_count = army_count + 1
            if army_count == n then
                return mf
            end
        end
    end
    return nil
end

-- Sums up total upkeep across all armies in faction. Excludes agent (non-embedded hero) upkeep.
function factions_tracker:get_total_army_upkeep(faction, override_army_filter)
    local mf_list = faction:military_force_list()
    local army_filter = override_army_filter or self.army_filter
    local upkeep = 0
    for i = 0, mf_list:num_items() - 1 do
        local mf = mf_list:item_at(i)
        if army_filter(mf) then
            upkeep = upkeep + mf:upkeep()
        end
    end
    return upkeep
end

return factions_tracker
