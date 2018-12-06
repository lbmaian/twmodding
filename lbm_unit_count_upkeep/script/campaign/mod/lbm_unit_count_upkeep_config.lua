local config = {}

-- Non-configurable config
config.max_num_units_per_army = 20
config.max_upkeep_pct = 250 -- max value of x for which the effect bundle 'lbm_additional_army_unit_count_upkeep_<x>' exists
config.army_unit_count_prefix = "lbm_additional_army_unit_count_"
config.upkeep_effect_bundle_prefix = config.army_unit_count_prefix .. "upkeep_"
config.dummy_upkeep_effect_bundle = config.upkeep_effect_bundle_prefix .. "dummy"
config.sample_upkeep_effect_bundle_prefix = config.upkeep_effect_bundle_prefix .. "sample_"

-- Configuration
config.num_free_units = config.max_num_units_per_army

return config
