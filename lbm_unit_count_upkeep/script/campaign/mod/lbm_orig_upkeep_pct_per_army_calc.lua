-- Manages the determination and storage of the original army-count-based upkeep percent.

local utils = cm:load_global_script "lib.lbm_utils"
local custom_ui_listeners = cm:load_global_script "lib.lbm_custom_ui_listeners"
local config = cm:load_global_script "lbm_unit_count_upkeep_config"

local orig_upkeep_effect_bundle_prefix = "wh_main_bundle_force_additional_army_upkeep_"

local orig_upkeep_pct_per_army_calc = {}

function orig_upkeep_pct_per_army_calc.new(factions_tracker)
    local self = {
        factions_tracker = factions_tracker,
    }
    setmetatable(self, {__index = orig_upkeep_pct_per_army_calc})
    return self
end

function orig_upkeep_pct_per_army_calc:get_effect_bundle(difficulty_level)
    if difficulty_level == nil then
        difficulty_level = cm:model():combined_difficulty_level()
    end
    if difficulty_level == -3 then
        return orig_upkeep_effect_bundle_prefix .. "legendary"
    elseif difficulty_level == -2 then
        return orig_upkeep_effect_bundle_prefix .. "very_hard"
    elseif difficulty_level == -1 then
        return orig_upkeep_effect_bundle_prefix .. "hard"
    elseif difficulty_level == 0 then
        return orig_upkeep_effect_bundle_prefix .. "normal"
    else
        return orig_upkeep_effect_bundle_prefix .. "easy"
    end
end

function orig_upkeep_pct_per_army_calc:is_effect_bundle(effect_bundle_name)
    return effect_bundle_name:starts_with(orig_upkeep_effect_bundle_prefix)
end

local orig_upkeep_pct_per_army_save_key_prefix = config.army_unit_count_prefix .. "orig_upkeep_pct_per_army_"

--[=[
estimate_orig_upkeep_pct_per_army_from_single_army: This function corresponds to case (d) in orig_upkeep_pct_per_army_calc:get(): 1 army exists, > 20 units exist:

This implies there must be agents on the map in addition to the single army.
We have access to each army's upkeep, which are fortunately synchronously updated after an upkeep effect is applied. We can then organize the inputs into a linear system that can be solved for.
First, we need to apply a sample faction-wide upkeep effect for which we know the value of, which I'll denote as sample_mod. We can then derive the following:
    (1) base_upkeep = unit[1].upkeep + ... + unit[n].upkeep [for n units]
    (2) current_upkeep = unit[1].upkeep * unit[1].current_mod + ... + unit[n].upkeep * unit[n].current_mod [for n units], where current_upkeep is known
    (3) sample_upkeep = unit[1].upkeep * (unit[1].current_mod + sample_mod) + ... + unit[n].upkeep * (unit[n].current_mod + sample_mod) [for n units], where sample_upkeep and sample_mod are known
     ↓
    (4) sample_upkeep = (unit[1].upkeep * unit[1].current_mod + ... + unit[n].upkeep * unit[n].current_mod) + (unit[1].upkeep * sample_mod + ... + unit[n].upkeep * sample_mod)
     ↓
    (5) sample_upkeep = (unit[1].upkeep * unit[1].current_mod + ... + unit[n].upkeep * unit[n].current_mod) + (unit[1].upkeep + ... + unit[n].upkeep) * sample_mod
     ↓↶(1),(2)
    (6) sample_upkeep = current_upkeep + base_upkeep * sample_mod, where current_upkeep, base_upkeep, and sample_mod are all known values.
     ↓
    (7) base_upkeep = (sample_upkeep - current_upkeep) / sample_mod
Then, we apply the sample faction-wide upkeep effect with the difficulty-based original upkeep mod of unknown value, denoted as target_mod.
    (8) target_upkeep = unit[1].upkeep * (unit[1].current_mod + sample_mod + target_mod) + ... + unit[n].upkeep * (unit[n].current_mod + sample_mod + target_mod) [for n units], where sample_mod is known
     ↓
    (9) target_upkeep = (unit[1].upkeep * (unit[1].current_mod + sample_mod) + ... + unit[n].upkeep * (unit[n].current_mod + sample_mod)) + (unit[1].upkeep * target_mod + ... + unit[n].upkeep * target_mod)
     ↓
   (10) target_upkeep = (unit[1].upkeep * (unit[1].current_mod + sample_mod) + ... + unit[n].upkeep * (unit[n].current_mod + sample_mod)) + (unit[1].upkeep + ... + unit[n].upkeep) * target_mod
     ↓↶(1),(3)
   (11) target_upkeep = sample_upkeep + base_upkeep * target_mod
     ↓
   (12) target_mod = (target_upkeep - sample_upkeep) / base_upkeep, where target_upkeep and current_upkeep are known values, and base_upkeep was calculated in step (7).
Finally, revert the applied effect bundles.
Caveats:
 1) The above calculations do not factor in the rounding behavior of upkeep, which happens at the unit level.
    There's unfortunately no way to correct for this without access to unit-level upkeep.
    Partial workaround is to use a ludicrously high sample upkeep mod to increase the granularity, and to use multiple samples to average the estimated base upkeep.
    The same can apply for sampling target upkeeps - combine the target upkeep with each sample upkeep mod.
    That doesn't fully address the low granularity with typical upkeep mods (such as the vanilla ones, especially 1% upkeep) but sufficient sampling addresses this adequately.
    Also, while this sampling is expensive, the case where this function is called is rare, and when it is called, it's only called once per campaign.
 2) original upkeep effect bundle can only be applied to armies, and we can't apply an effect bundle twice to the same object.
    Solution is to just apply it to the first valid army, since the wh_campaign_setup listener avoids doing so (the 'free' army).
    Note: We can get access to the total upkeep across all armies and agents, but they all require UI access, and worse, require a delay (i.e. a callback).
    The treasury in top bar (root > layout > resources_bar > topbar_list_parent > treasury_holder > dy_income) and its tooltip (root > tooltip_value_breakdown), which contains the total upkeep,
    aren't reliably updated, nor are they immediately available if the toolbar is hidden at the moment.
    The finance panel (root > finance_screen > TabGroup > tab_taxes > taxes > projected_income > expenditure_parent > regular_expenditure_army_upkeep > dy_value) also contains the total upkeep,
    but it requires SimulateLClick opening/closing the treasury button (root > layout > resources_bar > topbar_list_parent > treasury_holder > dy_treasury > button_finance),
    and so despite being more reliable, it still requires a delay to update and is much slower.
    (That said, one advantage of using the finance panel is that when it's opened, the values in the treasury in the top bar get updated.)
--]=]

local samples_excl_current = {
    ["1"] = 314,
    ["2"] = 1337,
    ["3"] = 5000,
    ["4"] = 9999,
    ["5"] = 1234,
}
local samples_incl_current = table.merge_in_place({[""] = 0}, samples_excl_current)

local function estimate_orig_upkeep_pct_per_army_from_single_army(self, faction, general_cqi, orig_upkeep_effect_bundle)
    local faction_name = faction:name()
    local factions_tracker = self.factions_tracker
    
    local ret_status, orig_upkeep_pct_per_army = custom_ui_listeners.disable_during_call(function()
        local current_upkeep = factions_tracker:get_total_army_upkeep(faction, utils.always_true)
        --out("current_upkeep = " .. current_upkeep)
        
        local function get_upkeeps_from_samples(samples, target_force_effect_bundle)
            if target_force_effect_bundle then
                cm:apply_effect_bundle_to_characters_force(target_force_effect_bundle, general_cqi, 0, false)
            end
            local sample_upkeeps = {}
            for sample_name, _ in pairs(samples) do
                local sample_upkeep
                if sample_name == "" then
                    if target_force_effect_bundle then
                        sample_upkeep = factions_tracker:get_total_army_upkeep(faction, utils.always_true)
                        --out("sample upkeep from " .. target_force_effect_bundle .. " = " .. sample_upkeep)
                    else
                        sample_upkeep = current_upkeep
                    end
                else
                    local sample_upkeep_effect_bundle = config.sample_upkeep_effect_bundle_prefix .. sample_name
                    cm:apply_effect_bundle(sample_upkeep_effect_bundle, faction_name, 0)
                    sample_upkeep = factions_tracker:get_total_army_upkeep(faction, utils.always_true)
                    cm:remove_effect_bundle(sample_upkeep_effect_bundle, faction_name)
                    --if target_force_effect_bundle then
                    --    out("sample upkeep from " .. sample_upkeep_effect_bundle .. " + " .. target_force_effect_bundle .. " = " .. sample_upkeep)
                    --else
                    --    out("sample upkeep from " .. sample_upkeep_effect_bundle .. " = " .. sample_upkeep)
                    --end
                end
                sample_upkeeps[sample_name] = sample_upkeep
            end
            if target_force_effect_bundle then
                cm:remove_effect_bundle_from_characters_force(target_force_effect_bundle, general_cqi)
            end
            return sample_upkeeps
        end
        
        local function estimate_base_upkeep(samples, sample_upkeeps)
            local base_upkeep_sum = 0
            local num_samples = 0
            for sample_name, sample_mod in pairs(samples) do
                --local sample_upkeep_effect_bundle = sample_upkeep_effect_bundle_prefix .. sample_name
                local sample_upkeep = sample_upkeeps[sample_name]
                local base_upkeep = (sample_upkeep - current_upkeep) / (sample_mod / 100) -- sample mod is in percent, so /100 to convert from percent to fraction
                --out("estimated base upkeep from " .. sample_upkeep_effect_bundle .. " = " .. base_upkeep)
                num_samples = num_samples + 1
                base_upkeep_sum = base_upkeep_sum + base_upkeep
            end
            local base_upkeep = base_upkeep_sum / num_samples
            --out("estimated base upkeep = " .. base_upkeep)
            return base_upkeep
        end
        
        local function estimate_target_upkeep_diff(sample_upkeeps, sample_target_upkeeps)
            local target_upkeep_diff_sum = 0
            local num_samples = 0
            for sample_name, sample_upkeep in pairs(sample_upkeeps) do
                local sample_target_upkeep = sample_target_upkeeps[sample_name]
                local target_upkeep_diff = sample_target_upkeep - sample_upkeep
                --out("target upkeep diff for sample " .. sample_name .. " = " .. sample_target_upkeep .. " - " .. sample_upkeep .. " = " .. target_upkeep_diff)
                num_samples = num_samples + 1
                target_upkeep_diff_sum = target_upkeep_diff_sum + target_upkeep_diff
            end
            local target_upkeep_diff = target_upkeep_diff_sum / num_samples
            --out("estimated target upkeep diff = " .. target_upkeep_diff)
            return target_upkeep_diff
        end
        
        local function estimate_target_mod(base_upkeep, samples, sample_upkeeps, target_force_effect_bundle)
            local sample_target_upkeeps = get_upkeeps_from_samples(samples, target_force_effect_bundle)
            local target_upkeep_diff = estimate_target_upkeep_diff(sample_upkeeps, sample_target_upkeeps)
            local target_unrounded_mod = target_upkeep_diff / base_upkeep * 100 -- upkeep effect mods need percent values, so *100 to convert from fraction to percent
            --out("estimated target mod (unrounded) for " .. target_force_effect_bundle .. " = " .. target_unrounded_mod)
            return math.round(target_unrounded_mod)
        end
        
        -- Estimate the base upkeep and target_upkeep using multiple samples.
        local sample_upkeeps = get_upkeeps_from_samples(samples_incl_current)
        local base_upkeep = estimate_base_upkeep(samples_excl_current, sample_upkeeps)
        local target_mod = estimate_target_mod(base_upkeep, samples_incl_current, sample_upkeeps, orig_upkeep_effect_bundle)
        
        --[[ -- Uncomment this section to test for each difficulty level
        estimate_target_mod(base_upkeep, samples_incl_current, sample_upkeeps, self:get_effect_bundle(1))
        estimate_target_mod(base_upkeep, samples_incl_current, sample_upkeeps, self:get_effect_bundle(0))
        estimate_target_mod(base_upkeep, samples_incl_current, sample_upkeeps, self:get_effect_bundle(-1))
        estimate_target_mod(base_upkeep, samples_incl_current, sample_upkeeps, self:get_effect_bundle(-2))
        estimate_target_mod(base_upkeep, samples_incl_current, sample_upkeeps, self:get_effect_bundle(-3))
        --]]
        
        return target_mod
    end, true)
    if ret_status then
        return orig_upkeep_pct_per_army
    else
        -- Remove temp effect bundles just in case they were added yet weren't removed in the above 'try'
        for sample_name, _ in pairs(samples_incl_current) do
            cm:remove_effect_bundle(config.sample_upkeep_effect_bundle_prefix .. sample_name, faction_name)
        end
        cm:remove_effect_bundle_from_characters_force(orig_upkeep_effect_bundle, general_cqi)
        error(orig_upkeep_pct_per_army) -- actually the error message
    end
end

-- Returns the original upkeep percent per army, i.e. the army-count-based upkeep rather than our unit-count-based upkeep, lazily computing it if necessary.
-- Also returns whether this upkeep percent is a dummy value (of 0) if we can't actually find out this value yet (i.e. # armies <= 1 and # units <= 20).
-- Although (human) faction object is an input, the army-count-based upkeep is the same for all human player factions. The faction object is just necessary to compute the value.
-- The value shouldn't actually differ per human faction, but there's a case where it can't be computed perfectly reliably, so to help prevent desyncs in multiplayer,
-- this is computed per human faction.
local function compute_orig_upkeep_pct_per_army(self, faction)
    --out("orig_upkeep_pct_per_army_calc: compute orig_upkeep_pct_per_army for " .. faction:name())
    local army_count, unit_count = self.factions_tracker:get(faction)
    
    -- There's no direct way to determine the original faction-wide upkeep per army value for a difficulty level,
    -- and I'd rather not hard-code the values, so that this mod remains compatible with other upkeep mods. It can be derived though as follows:
    -- Possible scenarios:
    
    -- a) 0 armies exist: 0 upkeep obviously, so return dummy value of 0.
    if army_count == 0 then
        out("orig_upkeep_pct_per_army_calc: # armies = 0 => 0 (dummy)")
        return 0, true
    end
    
    local orig_upkeep_effect_bundle = self:get_effect_bundle()
    
    -- b) >1 armies exist: Orig upkeep bundle effect UIC should exist, and we can derive upkeep per army from its tooltip, so temporarily apply the effect bundle to get the value, then revert.
    if army_count > 1 then
        local orig_upkeep_pct_per_army = custom_ui_listeners.disable_during_call(function()
            local uic_root = core:get_ui_root()
            local uic_orig_upkeep_effect_bundle = find_uicomponent(uic_root, "layout", "resources_bar", "topbar_list_parent", "global_effect_list", orig_upkeep_effect_bundle)
            if not uic_orig_upkeep_effect_bundle then
                -- Warn and potentially retry (see update_army_upkeep_penalty)
                error("[WARNING] orig_upkeep_pct_per_army_calc: # armies > 1 (" .. army_count .. ") yet " .. orig_upkeep_effect_bundle .. " UIComponent not found (yet)")
            end
            
            local uic_campaign_upkeep_tooltip = find_uicomponent(uic_root, "tooltip_campaign_upkeep_effect")
            if not uic_campaign_upkeep_tooltip then -- if upkeep tooltip isn't opened yet, open it
                uic_orig_upkeep_effect_bundle:SimulateMouseOn() -- should synchronously force the tooltip to be generated if it hasn't been yet
                uic_campaign_upkeep_tooltip = find_uicomponent(uic_root, "tooltip_campaign_upkeep_effect")
                if not uic_campaign_upkeep_tooltip then -- there is the possibility that above SimulateMouseOn is not synchronous, so error (and potentially retry)
                    error("[WARNING] orig_upkeep_pct_per_army_calc: # armies > 1 (" .. army_count .. ") and tooltip_campaign_upkeep_effect sim-clicked, " ..
                        "yet tooltip_campaign_upkeep_effect UIComponent not found (yet)")
                end
                uic_campaign_upkeep_tooltip:SetVisible(false) -- then hide it immediately, since we only want info from it
            end
            local uic_upkeep_pct = find_uicomponent(uic_campaign_upkeep_tooltip, "list_parent", "label_upkeep_percent_parent", "label_percent_increase")
            local upkeep_pct_text = uic_upkeep_pct:GetStateText()
            --out("orig_upkeep_pct_per_army_calc: upkeep_pct_text: " .. upkeep_pct_text)
            if upkeep_pct_text:sub(-1, -1) == "%" then -- typically either "0" or "<integer>%"
                upkeep_pct_text = upkeep_pct_text:sub(1, -2) -- chop off the % suffix
            end
            return tonumber(upkeep_pct_text) / (army_count - 1)
        end)
        out("orig_upkeep_pct_per_army_calc: # armies > 1 (" .. army_count .. ") => " .. orig_upkeep_pct_per_army)
        return orig_upkeep_pct_per_army, false
    end
    
    -- c) 1 army exists, <= 20 units exist: orig upkeep bundle effect UIC doesn't exist, but we also discount 20 units anyway, so there's 0 upkeep anyway and can return dummy value of 0.
    if unit_count <= config.max_num_units_per_army then
        out("orig_upkeep_pct_per_army_calc: # units <= " .. config.max_num_units_per_army .. " (" .. unit_count .. ") => 0 (dummy)")
        return 0, true
    end
    
    -- d) 1 army exists, > 20 units exist: see estimate_orig_upkeep_pct_per_army_from_single_army
    --out("orig_upkeep_pct_per_army_calc: # armies = 1, # units > " .. config.max_num_units_per_army .. " (" .. unit_count .. ") ...")
    local orig_upkeep_pct_per_army = estimate_orig_upkeep_pct_per_army_from_single_army(self, faction, self.factions_tracker:get_nth_valid_army(faction, 1):general_character():cqi(), orig_upkeep_effect_bundle)
    out("orig_upkeep_pct_per_army_calc: # armies = 1, # units > " .. config.max_num_units_per_army .. " (" .. unit_count .. ") => " .. orig_upkeep_pct_per_army)
    
    -- With the amount of sampling done in estimate_orig_upkeep_pct_per_army_from_single_army, I'm confident enough that the correct orig upkeep % per army will be correct, so commenting out below.
    --[[
    -- Since this is only an estimation, it's not guaranteed to be correct, so be sure to refresh whenever the army count changes to be >1.
    -- It happens to be the case whenever army count changes (via recruitment, disbanding, or battle results) themselves trigger our event listeners that update army counts,
    -- which in turn triggers this army count change listener, before this whole function is called.
    local faction_name = faction:name()
    factions_tracker.army_count_change_listeners[#factions_tracker.army_count_change_listeners + 1] = function(listener_faction, old_army_count, new_army_count)
        if faction_name == listener_faction:name() and new_army_count > 1 then
            self:reset(faction_name)
            return true -- return true to remove this listener
        end
        return false
    end
    --]]
    
    return orig_upkeep_pct_per_army, false
end

function orig_upkeep_pct_per_army_calc:reset(faction)
    local faction_names = faction and {type(faction) == "string" and faction or faction:name()} or cm:get_human_factions()
    out("orig_upkeep_pct_per_army_calc: reset to nil for faction(s) " .. table.concat(faction_names, ", "))
    for i = 1, #faction_names do
        local faction_name = faction_names[i]
        cm.saved_values[orig_upkeep_pct_per_army_save_key_prefix .. faction_name] = nil -- cm:set_saved_value doesn't allow nil to be passed as the value
    end
end

function orig_upkeep_pct_per_army_calc:get(faction)
    local faction_name = faction:name()
    local save_key = orig_upkeep_pct_per_army_save_key_prefix .. faction_name
    local orig_upkeep_pct_per_army = cm:get_saved_value(save_key);
    if orig_upkeep_pct_per_army == nil then
        local is_dummy_value
        orig_upkeep_pct_per_army, is_dummy_value = compute_orig_upkeep_pct_per_army(self, faction)
        if is_dummy_value then
            out("orig_upkeep_pct_per_army_calc: NOT saving for dummy value " .. orig_upkeep_pct_per_army .. " for " .. faction_name)
        else
            out("orig_upkeep_pct_per_army_calc: saving value " .. orig_upkeep_pct_per_army .. " for " .. faction_name)
            cm:set_saved_value(save_key, orig_upkeep_pct_per_army)
        end
    end
    return orig_upkeep_pct_per_army
end

core:add_listener(
    "NominalDifficultyLevelChangedEvent:orig_upkeep_pct_per_army_calc",
    "NominalDifficultyLevelChangedEvent",
    true,
    function(context)
        orig_upkeep_pct_per_army_calc:reset()
    end,
    true
)

return orig_upkeep_pct_per_army_calc
