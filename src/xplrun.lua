#!/usr/local/bin/lua

----------------------------------------------------------------------------
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, xPL application framework
-- @description xPL framework to run multiple xPL applications in a single process/Lua state
-- to minimize resources used. A config file can be specified on the commandline. Use
-- option <code>-help</code> for a full description.

local xpl = require ("xpl")
local appversion = "0.1"

local prog = {
	name = "xPL application framework",
	banner = "version " .. appversion .. ", Copyright 2011 Thijs Schreijer",
	use = "Runs multiple xPL applications in a single process/Lua state to minimize resources used",
	options = arg[0] .. [[ [OPTIONS...]
Options;
   -t, -time=[xx]                         How long should the application run (in seconds)
   -H, -hub                               Start included xPL hub function
   -c, -config=[filename]                 Configfile to start from
   -b, -broadcast[=255.255.255.255]       Broadcast address to use for sending
   -version                               Print version info
   -h, -help                              Display this usage information

The config file has the following format;

bla, bla, bla,  must find some time to do this...

	]],
}
local sampleconfig = [[
-- This is a sample config file for xplrun using the xPL for Lua framework
return {

}
]]

local opt = {
            time = { "time", "t" },
            hub = { "hub", "H"},
            config = { "config", "c" },
            broadcast = { "broadcast", "b" },
			version = { "version" },
			help = { "help", "h"},
			}
local arg = arg		-- argument list, after parsing only unrecognized arguments

local function usage()
	print(prog.name)
	print(prog.banner)
	print(prog.use)
	print(prog.options)
end

local function version()
	print(prog.name .. ", " .. prog.banner)
end

local function parsecommandline(opt,arg)
	-- arg is argument list, global _G.arg is used if nil is provided
	-- opt is list of possible options in table as;
	--   opt = { fullname1 = { name1, name2, name3 },
	--           fullname2 = { name1, name2, name3 },
	--         }
	-- returns;
	--    parsed options table
	--    unparsed options table

	arg = arg or _G.arg		-- get global argument list if none provided
	local unp = {}			-- unparsable arguments remaining
	local result = {}		-- parsed list
	for _, a in ipairs(arg) do
		local key, val = string.match(a,'\-+(%a+)\=*(.*)')
		if key == nil then
			-- not recognized/parsable
			table.insert(unp,a)
		else
			-- see if we can find a match
			local m
			for fullname, namelist in pairs(opt) do
				for _, name in ipairs(namelist) do
					if name == key then
						-- match found
						m = fullname
					end
				end
			end
			if m then
				-- we have a match, so store it
				if val == "" then
					val = true		-- convert to boolean option
				end
				result[m] = val
			else
				-- there was no match
				table.insert(unp, a)
			end
		end
	end
	return result, unp
end

local function exit(err)
    -- print error and exit
    print(version())
    print(err)
    os.exit()
end

opt, arg = parsecommandline(opt)		-- Go parse commandline options

if opt.help then						-- display message and exit
	usage()
	os.exit()
end
if opt.version then					-- display message and exit
	version()
	os.exit()
end

-- load config file first to enable the other options to override values
local conf
if not opt.config then
    exit("missing switch -c.  Use -help for help on the commandline.")
else
    -- try to load config
    local err
    conf, err = load(io.lines(opt.config) ,"configfile; " .. tostring(opt.config))
    if conf then
        -- loading and compiling succeeded, now execute function
        conf, err = pcall(conf())
    end
    if type(conf) ~= "table" then
        exit("Error loading configuration file '" .. tostring(opt.config) .. "'; " .. tostring(err))
    end
    if type(conf.devices) ~= "table" then
        exit("Error loading configuration file '" .. tostring(opt.config) .. "'; No devices defined.")
    end
end

if opt.time then
    local f = function()
        exit("invalid value for switch -t; " .. tostring(opt.time) .. ".  Use -help for help on the commandline.")
    end
    if tonumber(opt.time) then
        opt.time = tonumber(opt.time)
        if opt.time < 0 then
            f()
        end
    else
        f()
    end
end

if opt.hub then
    -- make the listener start the hub functionality as well
    xpl.settings.xplhub = true
else
    xpl.settings.xplhub = false
end

if opt.broadcast then
    -- set a non-default broadcast address
    xpl.settings.broadcast = opt.broadcast
end

if opt.time then
    -- create a timer to shutdown the logger when due
    copas.delayedexecutioner(opt.time, function() xpl.stop() end)
end

--------------------------------------------------------------------------------------
-- Load configuration
--------------------------------------------------------------------------------------

-- do not copy full table, just the ones we know (use white-list, not black-list)
xpl.settings.listenon = conf.listenon or xpl.settings.listenon
xpl.settings.listento = conf.listento or xpl.settings.listento
xpl.settings.broadcast = conf.broadcast or xpl.settings.broadcast
xpl.settings.xplport = conf.xplport or xpl.settings.xplport
xpl.settings.xplhub = conf.xplhub or xpl.settings.xplhub

local loaddev = function(settings)
    -- function to load a single device from a settings table
    local f = function()
        -- require class, instantiate and load settings
        xpl.classes[settings.classname] = require("xpl.classes." .. tostring(settings.classname))
        local dev = xpl.classes[settings.classname]:new({})
        dev:setsettings(settings)
        return dev
    end
    local r, dev_or_err = pcall(f)
    if not r then
        exit("Error loading device class '" .. tostring(class) .. "'; " .. tostring(dev_or_err))
    end
    return dev_or_err
end

print(prog.name)
print(prog.banner)
print("")
-- load all devices in the settings table
for _, devsett in pairs(conf.devices) do
    print("Loading device with classname; " .. tostring(devsett.classname) .. " ...")
    local dev = loaddev(devsett)
    xpl.settings.devices[dev] = devsett
    print("   ... device loaded as;" .. tostring(dev.address))
end


-- start listening
xpl.start()
print("")

