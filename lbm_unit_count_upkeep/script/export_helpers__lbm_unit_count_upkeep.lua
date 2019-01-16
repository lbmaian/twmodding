-- Note: export_helpers/export_triggers/export_ancillaries*.lua scripts run after all other scripts are run, including all the mod/*.lua scripts, after the LoadingGame,
-- and during the UICreated (game created) events (see cm:load_exported_files calls in wh_campaign_setup.lua).
-- In particular, all the mod/*.lua scripts are guaranteed to be loaded so you don't need to require them.

out("UnitCountBasedUpkeep: setup...")

cm:load_global_script "lib.vanish_safe_caller"

local utils = cm:load_global_script "lib.lbm_utils"
local custom_ui_listeners = cm:load_global_script "lib.lbm_custom_ui_listeners"

local local_faction_name = cm:get_local_faction(true)
if not (local_faction_name and utils.get_faction(local_faction_name)) then
    out("UnitCountBasedUpkeep: Autorun running, not applying upkeep penalties for additional units")
    return
end

local config = cm:load_global_script "lbm_unit_count_upkeep_config"

-- Function defined in wh_campaign_setup.lua
local is_valid_faction = upkeep_penalty_condition

-- Logic copied from wh_campaign_setup.lua
local function is_valid_army(mf)
    return not mf:is_armed_citizenry() and mf:has_general() and not mf:general_character():character_subtype("wh2_main_def_black_ark") -- neither garrison nor black ark
end

local factions_tracker = cm:load_global_script("lbm_factions_tracker").new(is_valid_army)

local orig_upkeep_pct_per_army_calc = cm:load_global_script("lbm_orig_upkeep_pct_per_army_calc").new(factions_tracker)

--local upkeep_calc = cm:load_global_script("lbm_unit_count_upkeep_calc").new(factions_tracker, orig_upkeep_pct_per_army_calc)

-- Computes the unit-count-based faction-wide upkeep % based.
-- If include_details is false or omitted, then returns only the computed upkeep %.
-- Else if include_details is true, then returns a table with entries:
-- * upkeep_pct = the rounded and bounded faction-wide upkeep % (where bounds is simply an upper bound of max_upkeep_ct)
-- * raw_upkeep_pct = the unrounded and unbounded faction-wide upkeep % (aka raw upkeep %)
-- * upkeep_pct_per_unit = the upkeep % per unit
-- * orig_upkeep_pct_per_army = the original upkeep % per army
-- * num_units = the # units, including free (discounted) units
-- * num_unfree_units = the # units, excluding free (discounted) units
-- * is_dummy_upkeep_pct = true if the original upkeep % per army is a dummy 0 (due to <= 1 armies and <= 20 units)
local function get_upkeep_pct(faction, include_details)
    local num_units = factions_tracker:get_unit_count(faction)
    local num_unfree_units = math.max(0, num_units - config.num_free_units)
    local orig_upkeep_pct_per_army, is_dummy_upkeep_pct = orig_upkeep_pct_per_army_calc:get(faction)
    local upkeep_pct_per_unit = orig_upkeep_pct_per_army / config.max_num_units_per_army
    local raw_upkeep_pct = num_unfree_units * upkeep_pct_per_unit
    local upkeep_pct = math.min(config.max_upkeep_pct, math.round(raw_upkeep_pct))
    if include_details then
        return {
            upkeep_pct = upkeep_pct,
            raw_upkeep_pct = raw_upkeep_pct,
            upkeep_pct_per_unit = upkeep_pct_per_unit,
            orig_upkeep_pct_per_army = orig_upkeep_pct_per_army,
            num_units = num_units,
            num_unfree_units = num_unfree_units,
            is_dummy_upkeep_pct = is_dummy_upkeep_pct,
        }
    else
        return upkeep_pct
    end
end

local function get_upkeep_pct_details(faction)
    return get_upkeep_pct(faction, true)
end

local dummy_upkeep_effect_bundle = config.dummy_upkeep_effect_bundle

local function is_dummy_upkeep_effect_bundle(effect_bundle_name)
    return effect_bundle_name == dummy_upkeep_effect_bundle
end

-- XXX: For some reason, the effect bundle icons aren't the same size & position as the original supply lines effect bundle icon, so 'fix' them so that they are the same.
-- The problem is that the variable_upkeep.png has dimensions of 27 x 29 pixels, while the effect bundle icons should each have dimensions of 24 x 24 pixels.
-- The layout special-cases the fake supply lines effect bundle (fake because the actual effect bundles are applied at army-level rather than faction-level and are hidden anyway),
-- so that the extra right 3px width and extra top 5px height appears fine for the supply lines effect icon, but it doesn't work for normal effect bundles,
-- such that an effect bundle with variable_upkeep.png icon will instead be resized down to 24px x 24px.
-- Also for some reason, the (dis)appearance of certain UI components (such as closing certain panels or new faction-wide effect bundle) can cause the fix to at least partially revert,
-- with the way the layout regenerates the top bar that the effect bundle icons appear on.
-- The workaround is two fold:
-- 1) Add a child UIC on the upkeep effect bundle that has its position and image set as if it was the actual original supply lines effect bundle icon.
--    This icon UIC survives certain layout regenerations, such as closing certain panels, while retaining the relative position and visibility of its parent.
-- 2) Have the upkeep effect bundle dummy use a truncated variable_upkeep.png where the right 3px and the top 5px is cropped off to fit into 24px x 24px dimensions.
--    This serves as a fallback if the above icon UIC is ever removed in some other types of layout regenerations, such as when a faction-wide effect bundle is added or removed.
-- Called whenever the upkeep effect bundle dummy is added (see show_dummy_upkeep_effect_bundle) and whenever an effect bundle is added (see UnitCountBasedUpkeepCampaignEffectsBundleAwarded).
local function fix_dummy_upkeep_effect_bundle(do_not_retry)
    local uic_dummy_upkeep_effect_bundle = find_uicomponent(core:get_ui_root(), "layout", "resources_bar", "topbar_list_parent", "global_effect_list", config.dummy_upkeep_effect_bundle)
    if not uic_dummy_upkeep_effect_bundle then
        if not do_not_retry then
            -- If effect bundle was just applied, the UIC for it might not be created yet, so wait a 'tick' and retry
            cm:callback(function() fix_dummy_upkeep_effect_bundle() end, 0)
        end
        return
    end
    
    -- region_info_pip used here is just a simple dummy template that can be rejiggered into an icon UIC - inspired from the UIMF.
    local uic_dummy_upkeep_effect_bundle_icon, was_created = core:get_or_create_component(dummy_upkeep_effect_bundle .. "_icon", "ui/campaign ui/region_info_pip", uic_dummy_upkeep_effect_bundle)
    if was_created then
        utils.uic_resize(uic_dummy_upkeep_effect_bundle_icon, 27, 29)
        local pos_x, _ = uic_dummy_upkeep_effect_bundle:Position()
        uic_dummy_upkeep_effect_bundle_icon:MoveTo(pos_x, 2)
        uic_dummy_upkeep_effect_bundle_icon:SetImage("ui/campaign ui/effect_bundles/variable_upkeep.png")
        uic_dummy_upkeep_effect_bundle_icon:PropagatePriority(uic_dummy_upkeep_effect_bundle:Priority())
        out("UnitCountBasedUpkeep: fix_dummy_upkeep_effect_bundle: " .. uicomponent_to_str(uic_dummy_upkeep_effect_bundle_icon) .. " created")
    else
        out("UnitCountBasedUpkeep: fix_dummy_upkeep_effect_bundle: " .. uicomponent_to_str(uic_dummy_upkeep_effect_bundle_icon) .. " already created")
    end
end

-- Faction-wide effect bundle icons are ordered in the top bar by appearance order. The upkeep icon should always appear last, so remove & re-add the dummy upkeep effect bundle if needed.
-- There is also workaround for our dummy upkeep effect bundle 'fix' being undone whenever a new visible faction-wide effect bundle is added, due to the layout regenerating the top bar.
-- The solution is to simply reapply the 'fix'.
-- Note: Unfortunately, this also happens when a faction-wide effect bundle is removed, but there's no event hook to listen on for that case.
core:add_listener(
    "UnitCountBasedUpkeepCampaignEffectsBundleAwarded",
    "CampaignEffectsBundleAwarded",
    function(context)
        if not custom_ui_listeners.enabled() then
            return false
        end
        
        -- Only trigger during player turns, since the resources bar at the top that contains the faction effect bundles is hidden outside player turns anyway.
        local faction = context:faction()
        if faction:name() == faction:model():world():whose_turn_is_it():name() then
            if is_valid_faction(faction) then
                if faction:has_effect_bundle(dummy_upkeep_effect_bundle) then
                    return true
                end
            end
        end
        return false
    end,
    function(context)
        local faction = context:faction()
        local faction_name = faction:name()
        out("UnitCountBasedUpkeepCampaignEffectsBundleAwarded: " .. faction_name)
        if faction:has_effect_bundle(dummy_upkeep_effect_bundle) then
            custom_ui_listeners.disable_during_call(function()
                cm:remove_effect_bundle(dummy_upkeep_effect_bundle, faction_name)
                cm:apply_effect_bundle(dummy_upkeep_effect_bundle, faction_name, 0)
            end)
            cm:callback(function() fix_dummy_upkeep_effect_bundle() end, 0) -- delay a 'tick' so that the effect bundle (which may not be the dummy one) appears
        end
    end,
    true
)

-- If mouse is hovered over the top bar, player attention is probably focused there, so take the opportunity to apply the dummy upkeep effect bundle 'fix' if needed.
core:add_listener(
    "UnitCountBasedUpkeepComponentMouseOnResourcesBar",
    "ComponentMouseOn",
    function(context)
        if not custom_ui_listeners.enabled() then
            return false
        end
        
        local uic = UIComponent(context.component)
        return uicomponent_descended_from(uic, "resources_bar")
    end,
    custom_ui_listeners.enabled,
    function(context)
        out("UnitCountBasedUpkeepComponentMouseOn: " .. uicomponent_to_str(UIComponent(context.component)))
        fix_dummy_upkeep_effect_bundle(true)
    end,
    true
)

-- TEMP?
--[[
core:add_listener(
    "UnitCountBasedUpkeepPanelOpenedCampaign",
    "PanelOpenedCampaign",
    custom_ui_listeners.enabled,
    function(context)
        out("UnitCountBasedUpkeepPanelOpenedCampaign: " .. context.string)
        cm:callback(function() fix_dummy_upkeep_effect_bundle(true) end, 0)
    end,
    true
)
--]]

-- TEMP?
--[[
core:add_listener(
    "UnitCountBasedUpkeepPanelClosedCampaign",
    "PanelClosedCampaign",
    custom_ui_listeners.enabled,
    function(context)
        out("UnitCountBasedUpkeepPanelClosedCampaign: " .. context.string)
        cm:callback(function() fix_dummy_upkeep_effect_bundle(true) end, 0)
    end,
    true
)
--]]

local function show_dummy_upkeep_effect_bundle(faction)
    out("UnitCountBasedUpkeep: show_dummy_upkeep_effect_bundle for faction " .. faction:name())
    if not faction:has_effect_bundle(dummy_upkeep_effect_bundle) then
        custom_ui_listeners.disable_during_call(function()
            cm:apply_effect_bundle(dummy_upkeep_effect_bundle, faction:name(), 0)
        end)
    end
    fix_dummy_upkeep_effect_bundle() -- should apply this regardless since we could be loading a saved game
end

local function hide_dummy_upkeep_effect_bundle(faction)
    out("UnitCountBasedUpkeep: hide_dummy_upkeep_effect_bundle for faction " .. faction:name())
    if faction:has_effect_bundle(dummy_upkeep_effect_bundle) then
        cm:remove_effect_bundle(dummy_upkeep_effect_bundle, faction:name())
    end
end

local function update_dummy_upkeep_effect_bundle_visibility(faction)
    ---out("UnitCountBasedUpkeep: update_dummy_upkeep_effect_bundle_visibility...")
    -- If # armies > 1, original supply lines dummy upkeep effect bundle is presumed to exist (or eventually will exist), so hide our custom dummy one if it exists.
    -- Else, apply our own custom dummy one.
    if factions_tracker:get_army_count(faction) > 1 then
        hide_dummy_upkeep_effect_bundle(faction)
    else
        show_dummy_upkeep_effect_bundle(faction)
    end
end

-- Computes the total increase in upkeep cost from our unit-count-based upkeep effect.
-- Note: This can't be cached, because there are insufficient events/hooks to catch every situation where the upkeep may change. In particular, we lack a hook for effect bundle removals.
local function get_upkeep_cost_increase(faction)
    local faction_name = faction:name()
    local upkeep_pct_details = get_upkeep_pct_details(faction)
    out(string.format("UnitCountBasedUpkeep: upkeep_pct = min(%d, round(max(0, %d - %d) * %d / %d)) = %d%s",
    config.max_upkeep_pct, upkeep_pct_details.num_units, config.num_free_units, upkeep_pct_details.orig_upkeep_pct_per_army, config.max_num_units_per_army, upkeep_pct_details.upkeep_pct,
        upkeep_pct_details.is_dummy_upkeep_pct and " (dummy)" or ""))
    local upkeep_effect_bundle = config.upkeep_effect_bundle_prefix .. upkeep_pct_details.upkeep_pct
    
    return custom_ui_listeners.disable_during_call(function()
        -- Since agent upkeep is currently unaffected by upkeep mods, their difference in upkeep cost is always 0. So we only need to get the difference between total army upkeeps.
        local upkeep_cost_with_effect = factions_tracker:get_total_army_upkeep(faction, utils.always_true)
        out("UnitCountBasedUpkeep: upkeep_cost_with_effect = " .. upkeep_cost_with_effect)
        cm:remove_effect_bundle(upkeep_effect_bundle, faction_name)
        local upkeep_cost_without_effect = factions_tracker:get_total_army_upkeep(faction, utils.always_true)
        out("UnitCountBasedUpkeep: upkeep_cost_without_effect = " .. upkeep_cost_without_effect)
        cm:apply_effect_bundle(upkeep_effect_bundle, faction_name, 0)
        return upkeep_cost_with_effect - upkeep_cost_without_effect
    end)
end

local current_upkeep_pct_save_key_prefix = config.army_unit_count_prefix .. "current_upkeep_pct_"

local function update_army_upkeep_effect_bundle(faction)
    local faction_name = faction:name()
    out("UnitCountBasedUpkeep: update_army_upkeep_effect_bundle for " .. faction_name)
    
    local upkeep_pct = get_upkeep_pct(faction)
    local upkeep_effect_bundle = config.upkeep_effect_bundle_prefix .. upkeep_pct
    
    local save_key = current_upkeep_pct_save_key_prefix .. faction_name
    local current_upkeep_pct = cm:get_saved_value(save_key)
    if current_upkeep_pct == nil then
        out("UnitCountBasedUpkeep: no army upkeep saved value found - new game or existing save without UnitCountBasedUpkeep mod enabled")
        if not faction:has_effect_bundle(upkeep_effect_bundle) then
            cm:apply_effect_bundle(upkeep_effect_bundle, faction_name, 0)
        else
            out("UnitCountBasedUpkeep: unexpectedly found army upkeep penalty effect already applied; scanning to ensure no other army upkeep penalty effects applied")
            for i = 0, config.max_upkeep_pct do
                local effect_bundle_i = config.upkeep_effect_bundle_prefix .. i
                if i ~= upkeep_pct then
                    if faction:has_effect_bundle(effect_bundle_i) then
                        out("UnitCountBasedUpkeep: unexpectedly found extraneous army upkeep penalty effect - removing")
                        cm:remove_effect_bundle(effect_bundle_i, faction_name)
                    end
                end
            end
        end
    else
        if current_upkeep_pct ~= upkeep_pct then
            cm:remove_effect_bundle(config.upkeep_effect_bundle_prefix .. current_upkeep_pct, faction_name)
            cm:apply_effect_bundle(upkeep_effect_bundle, faction_name, 0)
        else
            out("UnitCountBasedUpkeep: no change in army upkeep penalty")
        end
    end
    
    cm:set_saved_value(save_key, upkeep_pct)
    return upkeep_effect_bundle
end

local update_army_upkeep_singleton_callback_name_prefix = "UnitCountBasedUpkeep_callback_"

-- Updates the army upkeep penalty by refreshing faction army & unit counts, updating dummy effect bundle icon visibility, and updating the actual upkeep effect bundle.
local function update_army_upkeep_penalty(faction, delay_first_call, success_callback, failure_callback)
    local faction_name = faction:name()
    local callback_name = update_army_upkeep_singleton_callback_name_prefix .. faction_name
    out(string.format("UnitCountBasedUpkeep: update_army_upkeep_penalty(%s, %s, %s, %s)", faction_name, tostring(delay_first_call), tostring(success_callback), tostring(failure_callback)))
    
    -- Mechanism to reduce redundant calls, especially when multiple events that can affect unit counts fire consecutively (such as disbanding multiple units):
    -- If delay_first_call is true, then the upkeep updating happens in a named callback. This callback is canceled whenever this function is called, before setting up the callback again.
    -- Similarly, all retries to update_army_upkeep_effect_bundle below use the same callback name, so that even if delay_first_call is false, the retries will be canceled first,
    -- before setting up update_army_upkeep_effect_bundle tries again.
    -- In this way, the callback acts like a 'singleton' (per faction).
    -- TODO: replace callback instead of removing/adding
    cm:remove_callback(callback_name)
    if delay_first_call then
        cm:callback(function()
            -- Note: context objects tend to be destroyed after the listener and thus cause crashes if used in a callback, so refetching objects here.
            local callback_faction = utils.get_faction(faction_name)
            update_army_upkeep_penalty(callback_faction, false, success_callback, failure_callback)
        end, 0.1, callback_name)
        return
    end
    
    factions_tracker:refresh(faction)
    update_dummy_upkeep_effect_bundle_visibility(faction)
    
    utils.retry_callback({
        callback = function()
            -- Note: context objects tend to be destroyed after the listener and thus cause crashes if used in a callback, so refetching objects here.
            local callback_faction = utils.get_faction(faction_name)
            return update_army_upkeep_effect_bundle(callback_faction)
        end,
        max_tries = 15,
        base_delay = 0.1,
        exponential_backoff = 1.3, -- sum of 0.1 * 1.3^(i-1) for i = 1 to 15 => ~16.73 secs
        callback_name = callback_name,
        success_callback = success_callback,
        exhaust_tries_callback = failure_callback,
        enable_logging = true,
    })
end

-- Hack to force update the values in the treasury bar, namely its income value and its tooltip.
-- This involves opening and closing the finance panel at the bottom, so this should only be done when the panel at the bottom is currently unused for a more seamless UX.
function force_update_treasury_bar()
    local uic_root = core:get_ui_root()
    local uic_finance_screen = find_uicomponent(uic_root, "finance_screen")
    if not uic_finance_screen then
        custom_ui_listeners.disable_during_call(function()
            local uic_button_finance = find_uicomponent(uic_root, "layout", "resources_bar", "topbar_list_parent", "treasury_holder", "dy_treasury", "button_finance")
            uic_button_finance:ClearSound() -- prevent finance button from playing sound
            uic_button_finance:SimulateLClick() -- open finance panel
            uic_button_finance:SimulateLClick() -- close finance panel
        end)
        out("UnitCountBasedUpkeep: force_update_treasury_bar")
    else
        -- Shouldn't need to do anything
    end
end

-- Apply the effect bundles every time the player turn starts, including the new game case (i.e. not loading a save).
-- This should also units being destroyed due to attrition which happens right before turn start.
core:add_listener(
    "UnitCountBasedUpkeepFactionTurnStart",
    "FactionTurnStart",
    function(context)
        return is_valid_faction(context:faction())
    end,
    function(context)
        local faction = context:faction()
        out("UnitCountBasedUpkeepFactionTurnStart: " .. utils.campaign_obj_to_string(faction))
        update_army_upkeep_penalty(faction)
    end,
    true
)

-- Remove the original army-count-based upkeep listeners that are added at first tick.
-- Following first tick callback should happen after the one that adds those listeners.
-- Also take the opportunity to remove any existing original army-count-based upkeep effect bundles.
cm:add_first_tick_callback(function(context)
    out("UnitCountBasedUpkeep: removing original upkeep listeners and effect bundles")
    core:remove_listener("player_army_turn_start_listener")
    core:remove_listener("player_army_created_listener")
    core:remove_listener("confederation_player_army_count_listener")
    
    local human_faction_names = cm:get_human_factions()
    for i = 1, #human_faction_names do
        local faction = utils.get_faction(human_faction_names[i])
        if is_valid_faction(faction) then
            local mf_list = faction:military_force_list()
            for j = 1, mf_list:num_items() - 1 do -- mf_list is 0-indexed, and explicitly ignoring the first army since it shouldn't have effect applied to it
                local mf = mf_list:item_at(j)
                if is_valid_army(mf) then
                    for difficulty_level = 1, -3, -1 do
                        local effect_bundle = orig_upkeep_pct_per_army_calc:get_effect_bundle(difficulty_level)
                        if mf:has_effect_bundle(effect_bundle) then
                            cm:remove_effect_bundle_from_characters_force(effect_bundle, mf:general_character():cqi())
                        end
                    end
                end
            end
        end
    end
end)

-- Apply the effect bundles ASAP (FirstTickAfterWorldCreated event works well enough) in the case of loading a save, where the player turn start event won't be triggered.
-- Note that this can't be done in the LoadingGame event since that happens too early, before the game/UI is created.
-- On the other hand, the FirstTickAfterWorldCreated event is guaranteed to happen after the game/UI is created.
cm:add_first_tick_callback(function(context)
    out("UnitCountBasedUpkeep: first tick")
    if not cm:is_new_game() then
        local faction = context:world():whose_turn_is_it()
        if is_valid_faction(faction) then
            update_army_upkeep_penalty(faction)
        end
    end
end)

-- The last FactionTurnEnd is the final guaranteed moment when we can update faction army/unit counts before upkeep/income is applied for the next round.
-- Assume that the rebel faction (CQI 1) always exists and always is the last faction to turn before the round ends.
core:add_listener(
    "UnitCountBasedUpkeepLastFactionTurnEnd",
    "FactionTurnEnd",
    function(context)
        return context:faction():command_queue_index() == 1 -- rebel faction
    end,
    function(context)
        out("UnitCountBasedUpkeepLastFactionTurnEnd: " .. utils.campaign_obj_to_string(context:faction()))
        local human_faction_names = cm:get_human_factions()
        for i = 1, #human_faction_names do
            local faction = utils.get_faction(human_faction_names[i])
            if is_valid_faction(faction) then
                update_army_upkeep_penalty(faction)
            end
        end
    end,
    true
)

-- TODO UnitCountBasedUpkeepMilitaryForceCreated/UnitCountBasedUpkeepScriptedForceCreated/UnitCountBasedUpkeepFactionJoinsConfederation below
-- may not be necessary due to UnitCreated also being fired, though UnitCreated call to update_army_upkeep_penalty is delayed...

-- Recalc and reapply the effect bundles every time the player creates a new force (and hires a lord)
core:add_listener(
    "UnitCountBasedUpkeepMilitaryForceCreated",
    "MilitaryForceCreated", -- fires when lord is hired normally, does NOT fire for cm:create_force*
    function(context)
        return is_valid_faction(context:military_force_created():faction())
    end,
    function(context)
        local faction = context:military_force_created():faction()
        local debug_obj_str = utils.campaign_obj_to_string(faction)
        out("UnitCountBasedUpkeepMilitaryForceCreated: " .. debug_obj_str)
        update_army_upkeep_penalty(faction)
    end,
    true
)

-- ScriptedForceCreated is fired when cm:create_force* finishes creating a new force, but the event context is empty, so there's no way to find the faction/force/character created.
-- The workaround is to wrap cm:force_created to intercept the passed faction name/key.
local orig_cm_force_created = cm.force_created
function cm.force_created(self, id, listener_name, faction_key, ...)
    local ret_val = orig_cm_force_created(self, id, listener_name, faction_key, ...)
    local faction = utils.get_faction(faction_key)
    if is_valid_faction(faction) then
        local debug_obj_str = utils.campaign_obj_to_string(faction)
        out("UnitCountBasedUpkeepScriptedForceCreated: " .. debug_obj_str)
        update_army_upkeep_penalty(faction)
    end
    return ret_val
end

-- Recalc and reapply the effect bundles every time the player confederates
core:add_listener(
    "UnitCountBasedUpkeepFactionJoinsConfederation",
    "FactionJoinsConfederation",
    function(context)
        return is_valid_faction(context:confederation())
    end,
    function(context)
        local faction = context:confederation()
        out("UnitCountBasedUpkeepFactionJoinsConfederation: " .. utils.campaign_obj_to_string(faction))
        -- TODO: wait for diplomacy_dropdown panel to close if it's open
        update_army_upkeep_penalty(faction, false, function() -- success callback
            force_update_treasury_bar() -- since it doesn't update on its own for some reason (vanilla bug)
        end)
    end,
    true
)

core:add_listener(
    "UnitCountBasedUpkeepUnitCreated",
    "UnitCreated",
    function(context)
        -- Only include units that are created during player's turn, since units that are trained by x turn are created before the FactionTurnStart for x,
        -- and thus shouldn't count toward upkeep that's applied at FactionRoundStart (which takes place before all factions' FactionTurnStart for the round).
        local faction = context:unit():faction()
        if faction:name() == faction:model():world():whose_turn_is_it():name() then
            if is_valid_faction(faction) then
                -- For some reason, unit:military_force() crashes the game during this event, so the following check needs to happen in a callback
                -- if is_valid_army(unit:military_force())
                return true
            end
        end
        return false
    end,
    function(context)
        local unit = context:unit()
        out("UnitCountBasedUpkeepUnitCreated: " .. utils.campaign_obj_to_string(unit))
        -- Reason for delay_first_call=true in following call:
        -- In the common case of multiple units being created at once, keep delaying (and canceling previous delayed update_army_upkeep_penalty's),
        -- so that the meat of update_army_upkeep_penalty fires only once.
        update_army_upkeep_penalty(unit:faction(), true)
    end,
    true
)

--[[
-- TEMP?
core:add_listener(
    "UnitCountBasedUpkeepUnitTrained",
    "UnitTrained",
    function(context)
        local unit = context:unit()
        return is_valid_faction(unit:faction()) and is_valid_army(unit:military_force())
    end,
    function(context)
        out("UnitCountBasedUpkeepUnitTrained: " .. campaign_obj_to_string(context:unit()))
    end,
    true
)
--]]

core:add_listener(
    "UnitCountBasedUpkeepUnitDisbanded",
    "UnitDisbanded",
    function(context)
        local unit = context:unit()
        return is_valid_faction(unit:faction()) and is_valid_army(unit:military_force())
    end,
    function(context)
        local unit = context:unit()
        out("UnitCountBasedUpkeepUnitDisbanded: " .. utils.campaign_obj_to_string(unit))
        -- Reason for delay_first_call=true in following call:
        -- Disbanding unit still exists in the military force, so wait a bit so that force's # units actually decrements.
        update_army_upkeep_penalty(unit:faction(), true)
    end,
    true
)

core:add_listener(
    "UnitCountBasedUpkeepUnitMergedAndDestroyed",
    "UnitMergedAndDestroyed",
    function(context)
        local unit = context:unit()
        return is_valid_faction(unit:faction()) and is_valid_army(unit:military_force())
    end,
    function(context)
        out("UnitCountBasedUpkeepUnitMergedAndDestroyed: " .. utils.campaign_obj_to_string(context:unit()))
    end,
    true
)

-- Listen to when an agent (non-embedded hero) spawns on the map
core:add_listener(
    "UnitCountBasedUpkeepCharacterCreated",
    "CharacterCreated",
    function(context)
        return is_valid_faction(context:character():faction())
    end,
    function(context)
        local char = context:character()
        out("UnitCountBasedUpkeepCharacterCreated: " .. utils.campaign_obj_to_string(char))
        if not char:is_embedded_in_military_force() and cm:char_is_agent(char) then -- agent
            update_army_upkeep_penalty(char:faction(), false, function() -- success callback
                force_update_treasury_bar() -- since it doesn't update on its own for some reason (vanilla bug)
            end)
        end
    end,
    true
)

core:add_listener(
    "UnitCountBasedUpkeepCharacterConvalescedOrKilled",
    "CharacterConvalescedOrKilled",
    function(context)
        return is_valid_faction(context:character():faction())
    end,
    function(context)
        local char = context:character()
        out("UnitCountBasedUpkeepCharacterConvalescedOrKilled: " .. utils.campaign_obj_to_string(char))
        if not char:is_embedded_in_military_force() and cm:char_is_agent(char) then -- agent
            -- Reason for delay_first_call=true in following call:
            -- Disbanding unit still exists in the military force, so wait a bit so that force's # units actually decrements
            update_army_upkeep_penalty(char:faction(), true)
        end
    end,
    true
)

core:add_listener(
    "UnitCountBasedUpkeepBattleCompleted",
    "BattleCompleted",
    true,
    function(context)
        out("UnitCountBasedUpkeepBattleCompleted")
        
        -- Get set of unique faction names involved from the pending battle cache.
        local faction_names = {}
        for i = 1, cm:pending_battle_cache_num_attackers() do
            local faction_name = cm:pending_battle_cache_get_attacker_faction_name(i)
            faction_names[faction_name] = true
        end
        for i = 1, cm:pending_battle_cache_num_defenders() do
            local faction_name = cm:pending_battle_cache_get_defender_faction_name(i)
            faction_names[faction_name] = true
        end
        
        -- Update all upkeep-applicable factions involved.
        local last_ret_status, last_ret_value = true, nil
        for faction_name, _ in pairs(faction_names) do
            local faction = utils.get_faction(faction_name)
            if is_valid_faction(faction) then
                last_ret_status, last_ret_value = pcall(update_army_upkeep_penalty, faction)
            end
        end
        if not last_ret_status then
            error(last_ret_value)
        end
    end,
    true
)

--[[
-- TEMP?
core:add_listener(
    "UnitCountBasedUpkeepCharacterCharacterTargetAction",
    "CharacterCharacterTargetAction",
    true,
    function(context)
        local char, target_char = context:character(), context:target_character()
        if is_valid_faction(char:faction()) and char:is_wounded() then -- aka critical failure
            out("UnitCountBasedUpkeepCharacterCharacterTargetAction: source wounded: " .. utils.campaign_obj_to_string(char))
        elseif is_valid_faction(target_char:faction()) and context:mission_result_success() then
            -- Note: Can't use Character:is_wounded in above check since that doesn't account for assassinations, so using mission_result_success has a workaround.
            if char:faction():name() == target_char:faction():name() then -- if same faction
                out("UnitCountBasedUpkeepCharacterCharacterTargetAction: source joins target\n\tsource: " .. utils.campaign_obj_to_string(char) ..
                    "\n\ttarget: " .. utils.campaign_obj_to_string(target_char))
            else
                out("UnitCountBasedUpkeepCharacterCharacterTargetAction: target wounded/killed: " .. utils.campaign_obj_to_string(target_char))
            end
        end
    end,
    true
)

-- TEMP?
core:add_listener(
    "UnitCountBasedUpkeepCharacterGarrisonTargetAction",
    "CharacterGarrisonTargetAction",
    function(context)
        return is_valid_faction(context:character():faction()) and context:character():is_wounded() -- aka critical failure
    end,
    function(context)
        out("UnitCountBasedUpkeepCharacterGarrisonTargetAction: source wounded: " .. utils.campaign_obj_to_string(context:character()))
    end,
    true
)
--]]

-- Recalc and reapply effect bundles whenever difficulty changes (should only apply in singleplayer)
core:add_listener(
    "UnitCountBasedUpkeepNominalDifficultyLevelChangedEvent",
    "NominalDifficultyLevelChangedEvent",
    true,
    function(context)
        local model = context:model()
        out("NominalDifficultyLevelChangedEvent: " .. model:combined_difficulty_level())
        orig_upkeep_pct_per_army_calc:reset()
        local faction = model:world():faction_by_key(cm:get_local_faction(true))
        update_army_upkeep_penalty(faction, false, function() -- success callback
            force_update_treasury_bar() -- since it doesn't update on its own for some reason (vanilla bug)
        end)
    end,
    true
)


-- Custom effect bundle tooltip mechanism

-- %d (%d discounted for free)
local tooltip_num_units_format = effect.get_localised_string("ui_text_replacements_localised_text_tooltip_lbm_additional_army_unit_count_upkeep_num_units")
-- %d%% (%.2f%% per unit × %d units = %.2f%%)
local tooltip_upkeep_upkeep_percent_format = effect.get_localised_string("ui_text_replacements_localised_text_tooltip_lbm_additional_army_unit_count_upkeep_upkeep_percent")
-- %d%%
local tooltip_upkeep_dummy_upkeep_percent_format = effect.get_localised_string("ui_text_replacements_localised_text_tooltip_lbm_additional_army_unit_count_upkeep_dummy_upkeep_percent")

-- Put anything that that has the potential to effect the model (such as the effect bundle applying that can be done in factions_tracker:get_unit_count and get_upkeep_cost_increase) here.
-- This should ensure that the game model is synced between multiple players (i.e. prevent MP desyncs) when the various temporary model changes are done to compute required values.
-- This listener is triggered from the below ComponentMouseOn listener, and this trigger conveniently happens soon (if not immediately) after that listener finishes handling its event.
-- Also, for some reason, for the actual upkeep effect bundle (when >1 armies), the upkeep tooltip can be overwritten with original army-count-based values right after the
-- ComponentMouseOn listener runs, and I can find no event triggers that correspond to this. Workaround is to wait a 'tick' and reset the tooltip to use our unit-count-based values.
-- The soonest this tick can happen is via a triggered UITriggerScriptEvent, which occurs even before the 0.0 (0.1) second callback.
utils.add_custom_ui_event_listener("UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent", function(faction_cqi, tooltip_root_id, max_tries)
    -- Abort/retry if tooltip_campaign_upkeep_effect is no longer open for whatever reason
    local uic_root = core:get_ui_root()
    local uic_campaign_upkeep_tooltip = find_uicomponent(uic_root, "tooltip_campaign_upkeep_effect")
    if not uic_campaign_upkeep_tooltip then
        if max_tries > 1 then
            utils.trigger_custom_ui_event("UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent", faction_cqi, tooltip_root_id, max_tries - 1)
        end
        return
    end
    local uic_tooltip_root = uic_campaign_upkeep_tooltip
    if tooltip_root_id ~= "tooltip_campaign_upkeep_effect" then
        uic_tooltip_root = find_uicomponent(uic_root, tooltip_root_id)
        if not uic_tooltip_root then
            if max_tries > 1 then
                utils.trigger_custom_ui_event("UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent", faction_cqi, tooltip_root_id, max_tries - 1)
            end
            return
        end
    end
    --out("UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent: uic_campaign_upkeep_tooltip: " .. uicomponent_to_str(uic_campaign_upkeep_tooltip))
    --out("UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent: uic_tooltip_root: " .. uicomponent_to_str(uic_tooltip_root))
    
    local faction = utils.get_faction(faction_cqi)
    local upkeep_pct_details = get_upkeep_pct_details(faction)
    local upkeep_cost_increase = get_upkeep_cost_increase(faction)
    
    out(string.format("UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent: faction=%s, # units=%d, upkeep %%=%d%s, upkeep %%/unit=%.2f%%, upkeep cost increase=%d",
        faction:name(), upkeep_pct_details.num_units, upkeep_pct_details.upkeep_pct,
        upkeep_pct_details.is_dummy_upkeep_pct and " (dummy)" or "",
        upkeep_pct_details.upkeep_pct_per_unit, upkeep_cost_increase))
    
    local num_units_text = tooltip_num_units_format:format(upkeep_pct_details.num_units, config.num_free_units)
    local upkeep_percent_format = upkeep_pct_details.is_dummy_upkeep_pct and tooltip_upkeep_dummy_upkeep_percent_format or tooltip_upkeep_upkeep_percent_format
    local upkeep_pct_text = upkeep_percent_format:format(upkeep_pct_details.upkeep_pct, upkeep_pct_details.upkeep_pct_per_unit, upkeep_pct_details.num_unfree_units, upkeep_pct_details.raw_upkeep_pct)
    local upkeep_cost_increase_text = tostring(upkeep_cost_increase)
    
    local uic_campaign_upkeep_tooltip_list = find_uicomponent(uic_campaign_upkeep_tooltip, "list_parent")
    find_uicomponent(uic_campaign_upkeep_tooltip_list, "label_armies_parent", "label_num_armies"):SetStateText(num_units_text)
    find_uicomponent(uic_campaign_upkeep_tooltip_list, "label_upkeep_percent_parent", "label_percent_increase"):SetStateText(upkeep_pct_text)
    find_uicomponent(uic_campaign_upkeep_tooltip_list, "label_upkeep_cost_parent", "label_cost_increase"):SetStateText(upkeep_cost_increase_text)
    
    uic_tooltip_root:SetVisible(true)
    if tooltip_root_id ~= "tooltip_campaign_upkeep_effect" then
        uic_campaign_upkeep_tooltip:SetVisible(true)
    end
    out("UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent: tooltip_campaign_upkeep_effect values set")
end)

core:add_listener(
    "UnitCountBasedUpkeepEffectTooltip",
    "ComponentMouseOn",
    custom_ui_listeners.enabled,
    function(context)
        local uic = UIComponent(context.component)
        local uic_id = uic:Id()
        --out("UnitCountBasedUpkeepEffectTooltip: " .. uicomponent_to_str(uic))
        if orig_upkeep_pct_per_army_calc:is_effect_bundle(uic_id) or is_dummy_upkeep_effect_bundle(uic_id) then
            local uic_root = core:get_ui_root()
            -- Ensure that the tooltip_campaign_upkeep_effect tooltip is open, yet hidden for the time being.
            local uic_campaign_upkeep_tooltip = find_uicomponent(uic_root, "tooltip_campaign_upkeep_effect")
            local tooltip_root_id = "tooltip_campaign_upkeep_effect" -- since the actual tooltip root can be TechTooltipPopup instead (see below)
            local max_tries = 1
            if not uic_campaign_upkeep_tooltip then
                if is_dummy_upkeep_effect_bundle(uic_id) then
                    -- Wait for the normal effect bundle tooltip (TechTooltipPopup) to be created for the dummy upkeep effect bundle.
                    local uic_tooltip_root = find_uicomponent(uic_root, "TechTooltipPopup")
                    if not uic_tooltip_root then
                        -- SimulateMouseOn() to synchronously force the tooltip to be generated if it hasn't been yet, while avoiding triggering this listener again.
                        custom_ui_listeners.disable_during_call(function()
                            uic:SimulateMouseOn()
                        end)
                        uic_tooltip_root = find_uicomponent(uic_root, "TechTooltipPopup")
                    end
                    -- Hide this tooltip until UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent fires (see below for trigger) and shows it.
                    -- This should hide the just-created tooltip before it even appears in the first place.
                    -- Note: we can't just set this invisible while having the child tooltip component (see below tooltip_campaign_upkeep_effect) visible,
                    -- since it seems the parent UI component's visibility takes precedence.
                    uic_tooltip_root:SetVisible(false)
                    -- Try to prevent the parent TechTooltipPopup tooltip from showing its contents and border when it does become shown.
                    -- The following doesn't actually fully make it transparent, but it seems to hide it sufficiently when the child tooltip_campaign_upkeep_effect (see below) is shown.
                    uic_tooltip_root:DestroyChildren()
                    uic_tooltip_root:SetImage("ui/skins/default/1x1_transparent_white.png")
                    -- Create the tooltip_campaign_upkeep_effect tooltip, and make it the only child of the otherwise empty TechTooltipPopup tooltip.
                    -- This ties the lifecycle of the former to the latter, such that when the tooltip is normally removed on mouse out, tooltip_campaign_upkeep_effect also gets removed.
                    -- This is necessary since there's no reliable mouse out event that we can attach a listener to, because not everything on the screen is a UI component
                    -- that would have ComponentMouseOn triggered on them.
                    uic_campaign_upkeep_tooltip = core:get_or_create_component("tooltip_campaign_upkeep_effect", "UI/common ui/tooltip_campaign_upkeep_effect", uic_tooltip_root)
                    uic_tooltip_root:Adopt(uic_campaign_upkeep_tooltip:Address()) -- this is somehow different from just creating the tooltip UIC as a child of uic_tooltip_root
                    tooltip_root_id = uic_tooltip_root:Id()
                    out("UnitCountBasedUpkeepEffectTooltip: tooltip_campaign_upkeep_effect created")
                else -- if orig_upkeep_pct_per_army_calc:is_effect_bundle(uic_id)
                    -- XXX: tooltip_campaign_upkeep_effect never exists by ComponentMouseOn, and when it does appear moments later, it always has default army-count-based values.
                    -- Similarly, if we call SimulateMouseOn(), tooltip_campaign_upkeep_effect does appear (by then?), but moments later, it gets reset to its default army-count-based values.
                    -- This unfortunately means that even if we get tooltip_campaign_upkeep_effect to exist by now and update its values* or is hidden, it will get appear reset momentarily later.
                    -- * ...which is a moot point, since it needs to be delayed until UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent to prevent multiplayer desyncs.
                    -- The tooltip seems to get updated with its defaults values before the triggered (see below) UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent fires,
                    -- so there's a split second of time, where tooltip_campaign_upkeep_effect will appear with default values, and I can't find any way to fully solve this.
                    -- (I tried tracking all event handlers/listeners/timers via lbm_events_tracker.lua but to no avail.)
                    out("UnitCountBasedUpkeepEffectTooltip: tooltip_campaign_upkeep_effect should exist but doesn't exist yet")
                    -- tooltip_campaign_upkeep_effect should appear before UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent fires, but add retries just in case.
                    max_tries = 3
                end
            else
                -- See above comment about the timing issues of the actual tooltip_campaign_upkeep_effect and its default values.
                -- Also don't bother trying to hide it if it's already open, since it'll just cause a flicker.
                out("UnitCountBasedUpkeepEffectTooltip: tooltip_campaign_upkeep_effect already opened - no need to create")
            end
            
            local faction = utils.get_faction(cm:get_local_faction(true))
            utils.trigger_custom_ui_event("UnitCountBasedUpkeepEffectTooltipUITriggerScriptEvent", faction:command_queue_index(), tooltip_root_id, max_tries)
        end
    end,
    true
)

out("UnitCountBasedUpkeep: setup done")
