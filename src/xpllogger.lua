#!/usr/local/bin/lua

----------------------------------------------------------------------------
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, commandline xPL message logger utility.
-- @description# Commandline utility for logging xPL messages. Use option <code>-help</code> for a description.
-- &nbsp
-- Example: <code>
-- xpllogger.lua -t=60 -hub -verbose -hbeat
-- </code>

module ("xpllogger", package.seeall)

local xpl = require ("xpl")
local appversion = "0.1"


local prog = {
	name = "xPL message logger",
	banner = "version " .. appversion .. ", Copyright 2011 Thijs Schreijer",
	use = "Logs xPL messages on the commandline",
	options = arg[0] .. [[ [OPTIONS...]
Options;
   -i, -instance=HOST                     InstanceID to be used, or HOST to generate
                                          hostname based id, or RANDOM for random id.
                                          (HOST is default)
   -t, -time=[xx]                         How long should the logger run (in seconds)
   -b, -hbeat                             Request a heartbeat upon start
   -H, -hub                               Start included xPL hub
   -B, -broadcast[=255.255.255.255]       Broadcast address to use for sending
   -v, -verbose                           Displays message contents while sending
   -version                               Print version info
   -h, -help                              Display this usage information

	]],
}

local opt = {
            instance = { "instance", "i" },
            time = { "time", "t" },
            hbeat = { "hbeat", "b" },
            hub = { "hub", "H"},
			verbose = { "verbose", "v" },
            broadcast = { "broadcast", "B" },
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

opt, arg = parsecommandline(opt)		-- Go parse commandline options

if opt.help then						-- display message and exit
	usage()
	os.exit()
end
if opt.version then					-- display message and exit
	version()
	os.exit()
end

if opt.time then
    local f = function()
        print(version())
        print("invalid value for switch -t; " .. tostring(opt.time) .. ".  Use -help for help on the commandline.")
        os.exit()
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

if opt.time then
    -- create a timer to shutdown the logger when due
    copas.delayedexecutioner(opt.time, function() xpl.stop() end)
end

if opt.broadcast then
    -- set a non-default broadcast address
    xpl.settings.broadcast = opt.broadcast
end

--------------------------------------------------------------------------------------
-- Create our device
--------------------------------------------------------------------------------------
local logger = xpl.classes.xpldevice:new({    -- create a generic xPL device for the logger

    initialize = function(self)
        self.super.initialize(self)
        self.configurable = true
        self.version = appversion   -- make version be reported in heartbeats
        self.address = xpl.createaddress("tieske", "lualog", opt.instance or "HOST")
    end,

    -- overriden to request a heartbeat on startup it set to do so.
    start = function(self)
        self.super.start(self)
        if opt.hbeat then
            local m = "xpl-cmnd\n{\nhop=1\nsource=%s\ntarget=*\n}\nhbeat.request\n{\ncommand=request\n}\n"
            m = string.format(m, self.address)
            xpl.send(m)
        end
    end,

    handlemessage = function(self, msg)
        local sizeup = function (t, l)
            if #t < l then return t .. string.rep(" ", l - #t) end
            if #t > l then return string.sub(t, 1, l) end
            return t
        end
        -- call ancestor to handle hbeat messages
        self.super.handlemessage(self, msg)
        -- now do my thing
        local log = ""
        log = sizeup(log .. msg.type, 9)
        log = sizeup(log .. msg.schema, #log + 18)
        log = sizeup(log .. msg.source, #log + 35)
        log = sizeup(log .. msg.target, #log + 35)
        log = sizeup(log .. msg.from,   #log + 22)
        print (log)
        if opt.verbose then
            for key, value in msg:eachkvp() do
                log = "   "
                log = sizeup(log .. key, #log + 16) .. "=" .. value
                print(log)
            end
        end
    end,

})

-- start listening
print(prog.name)
print(prog.banner)
print("")
xpl.start()
print("")

