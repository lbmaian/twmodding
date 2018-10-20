os.remove("test_log.txt")
local function mylog(input)
    local file = io.open("test_log.txt", "a")
    if file then
        file:write(tostring(input) .. "\n")
        file:close()
    end
end

function lbm_test_1() -- luacheck: no global
    mylog("ASDFASDF1")
    --string.sub("1", -1)
    --mylog("ASDFASDF2")
    --string.sub("1", -2) -- CAUSES CRASH
    --mylog("ASDFASDF3")
    --string.sub("test", -4)
    --mylog("ASDFASDF4")
    --string.sub("test", -5) -- CAUSES CRASH
    --mylog("ASDFASDF5")

    local co = coroutine.create(function()
        mylog("inside coroutine")
        mylog(string.len("test"))
        mylog(string.upper("test"))
        mylog(string.lower("TesT"))
        mylog(string.reverse("test"))
        mylog(string.rep("test", 3))
        --mylog(string.find("test", "s")) -- CAUSES CRASH
        --mylog(string.find("test", "x")) -- CAUSES CRASH
        --mylog(string.find("test", "s", 1, true)) -- CAUSES CRASH
        --mylog(string.find("test", "x", 1, true)) -- CAUSES CRASH
        mylog(string.format("hi %s world", "friendly"))
        mylog(string.gsub("test", "t", "T"))
        mylog(string.gsub("test", "x", "T"))
        mylog(string.byte("test"))
        mylog(string.byte("test", 1, 4))
        mylog(string.byte("test", 1, 5))
        mylog(string.char(string.byte("test")))
        mylog(string.char(string.byte("test", 1, 4)))
        mylog(string.sub("test", 1)) -- CAUSES CRASH
        mylog(string.sub("test", 1, 3)) -- CAUSES CRASH
        mylog(string.sub("UIComponent (0000000031905CE0)", 1)) -- CAUSES CRASH
        mylog(string.sub("UIComponent (0000000031905CE0)", 1, 12)) -- CAUSES CRASH
        local model = cm:model() -- amazingly does NOT crash despite internally using GAME:model()
        mylog(tostring(model))
        local world = model:world() -- CAUSES CRASH
        mylog(tostring(world))
        cm:callback(function() -- CAUSES CRASH (since internally uses GAME:add_time_trigger)
            mylog("will never run")
        end, 0.1)
        mylog("cause I've already crashed before this")
    end)
    coroutine.resume(co)
end
