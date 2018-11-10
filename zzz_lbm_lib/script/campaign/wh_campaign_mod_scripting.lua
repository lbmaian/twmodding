-- Modified - changes below are delimited by LBM CUSTOM START/END
--luacheck:ignore
-----------------------------------------------------------------------------------------------------------
-- MODULAR SCRIPTING FOR MODDERS
-----------------------------------------------------------------------------------------------------------
-- The following allows modders to load their own script files without editing any existing game scripts
-- This allows multiple scripted mods to work together without one preventing the execution of another
--
-- Issue: Two modders cannot use the same existing scripting file to execute their own scripts as one
-- version of the script would always overwrite the other preventing one mod from working
--
--
-- The following scripting loads all scripts within a "mod" folder of each campaign and then executes
-- a function of the same name as the file (if one such function is declared)
-- Onus is on the modder to ensure the function/file name is unique which is fine
--
-- Example: The file "data/script/campaign/wh2_main_great_vortex/mod/cool_mod.lua" would be loaded and
-- then any function by the name of "cool_mod" will be run if it exists (sort of like a constructor)
--
-- ~ Mitch 18/10/17
-----------------------------------------------------------------------------------------------------------
local mod_script_interface = nil;
local mod_script_files = {};
events = get_events();

events.NewSession[#events.NewSession+1] =
function (context)
	mod_script_interface = GAME(context);
	local campaign_name = "main_warhammer";
	
	if mod_script_interface:model():campaign_name("wh2_main_great_vortex") then
		campaign_name = "wh2_main_great_vortex";
	end
	
	load_mod_scripts(campaign_name);
end

events.FirstTickAfterWorldCreated[#events.FirstTickAfterWorldCreated+1] =
function (context)
	local local_env = getfenv(1);
	
	for i = 1, #mod_script_files do
		local current_file = mod_script_files[i];
		
		-- Make sure there is a function by the same name as the file
		if type(local_env[current_file]) == "function" then
			-- If a function by that name does exist then call it
			local_env[current_file]();
		end
	end
end

function load_mod_scripts(campaign_key)
	local file_str = mod_script_interface:filesystem_lookup("/script/campaign/"..campaign_key.."/mod/", "*.lua");
	
	if file_str ~= "" then
		package.path = package.path .. ";" .. "/script/campaign/"..campaign_key.."/mod/?.lua;";
		
		for filename in string.gmatch(file_str, '([^,]+)') do
			local ok, err = pcall(load_mod_script, filename);
			
			if not ok then
				ModLog("ERROR : ["..tostring(filename).."]");
				ModLog("\t"..tostring(err));
			else
				ModLog("Loaded Mod: ["..tostring(filename).."]");
			end
		end
	end
	
	-- Also do root campaign folder
	local file_str_c = mod_script_interface:filesystem_lookup("/script/campaign/mod/", "*.lua");
	
	if file_str_c ~= "" then
		package.path = package.path .. ";" .. "/script/campaign/mod/?.lua;";
		
		for filename in string.gmatch(file_str_c, '([^,]+)') do
			local ok, err = pcall(load_mod_script, filename);
			
			if not ok then
				ModLog("ERROR : ["..tostring(filename).."]");
				ModLog("\t"..tostring(err));
			else
				ModLog("Loaded Mod: ["..tostring(filename).."]");
			end
		end
	end
end

function load_mod_script(current_file)
	local pointer = 1;
	
	while true do
		local next_separator = string.find(current_file, "\\", pointer) or string.find(current_file, "/", pointer);
		
		if next_separator then
			pointer = next_separator + 1;
		else
			if pointer > 1 then
				current_file = string.sub(current_file, pointer);
			end
			break;
		end
	end
	
	local suffix = string.sub(current_file, string.len(current_file) - 3);
	
	if string.lower(suffix) == ".lua" then
		current_file = string.sub(current_file, 1, string.len(current_file) - 4);
	end
	
	-- LBM CUSTOM START: avoid loading if already loaded
	if package.loaded[current_file] then
		return;
	end;
	-- LBM CUSTOM END
	
	-- Loads a Lua chunk from the file
	local loaded_file = loadfile(current_file);
	
	-- Make sure something was loaded from the file
	if loaded_file then
		-- Get the local environment
		local local_env = getfenv(1);
		-- Set the environment of the Lua chunk to the same one as this file
		setfenv(loaded_file, local_env);
		-- Make sure the file is set as loaded
		package.loaded[current_file] = true;
		-- Execute the loaded Lua chunk so the functions within are registered
		-- LBM CUSTOM START: pass the script name as argument to the script being loaded, so that that script can access it via `...`, and assign non-nil return value to package.loaded
		--loaded_file();
		local ret_val = loaded_file(current_file);
		if ret_val ~= nil then
			package.loaded[current_file] = ret_val;
		end;
		-- LBM CUSTOM END
		-- Add this to list of loaded mod scripts
		table.insert(mod_script_files, current_file);
	end
end

-- LBM CUSTOM START: override cm:load_global_script (see LBM CUSTOM comments within)
function campaign_manager:load_global_script(scriptname, single_player_only)

	if single_player_only and self:is_multiplayer() then
		return;
	end;

	if package.loaded[scriptname] then
		-- LBM CUSTOM START: return the value of package.loaded[scriptname]
		--return;
		return package.loaded[scriptname];
		-- LBM CUSTOM END
	end;
	
	-- LBM CUSTOM START: treat scriptname as a package name (which uses dots as separators) to a file name (which uses slashes as separators)
	--local file = loadfile(scriptname);
	local file = loadfile(string.gsub(scriptname, "%.", "/"));
	-- LBM CUSTOM END
	
	if file then
		-- the file has been loaded correctly - set its environment, record that it's been loaded, then execute it
		out("Loading faction script " .. scriptname .. ".lua");
		out.inc_tab();
		
		setfenv(file, self.env);
		package.loaded[scriptname] = true;
		-- LBM CUSTOM START: pass the script name as argument to the script being loaded, so that that script can access it via `...`, and assign non-nil return value to package.loaded
		--file();
		local ret_val = file(scriptname);
		if ret_val ~= nil then
			package.loaded[scriptname] = ret_val;
		end;
		-- LBM CUSTOM END
		
		out.dec_tab();
		out(scriptname .. ".lua script loaded");
		-- LBM CUSTOM START: return the value of package.loaded[scriptname] instead of always returning true
		--return true;
		return package.loaded[scriptname];
		-- LBM CUSTOM END
	end;
	
	-- the file was not loaded correctly, however loadfile doesn't tell us why. Here we try and load it again with require which is more verbose
	local success, err_code = pcall(function() require(scriptname) end);

	script_error("ERROR: Tried to load faction script " .. scriptname .. " without success - either the script is not present or it is not valid. See error below");
	out("*************");
	out("Returned lua error is:");
	out(err_code);
	out("*************");

	return false;
end;
-- LBM CUSTOM END

local logMade = false;
function ModLog(text)
	if logMade == false then
		logMade = true;
		local logInterface = io.open("lua_mod_log.txt", "w");
		logInterface:write(text.."\n");
		logInterface:flush();
		logInterface:close();
	else
		local logInterface = io.open("lua_mod_log.txt", "a");
		logInterface:write(text.."\n");
		logInterface:flush();
		logInterface:close();
	end
end