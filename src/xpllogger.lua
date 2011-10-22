#!/usr/local/bin/lua

----------------------------------------------------------------------------
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, commandline xPL message logger utility.
-- @description# Commandline utility for sending xPL messages, message can be specified on the commandline (<code>-m</code> option) or send from files (<code>-f</code> option). Use option <code>-help</code> for a full description.
-- &nbsp
-- Example: <code>
-- xplsender.lua -f="C:\Documents and Settings\Thijs Schreijer\Desktop\Lua xPL\samplemsg.txt" -m="xpl-trig\n{\nhop=1\nsource=tieske-upnp.somedev\ntarget=*\n}\nsome.schema\n{\ncommand=unknown\n}\n"
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
   -t, -time                              How long should the logger run (in seconds)
   -b, -hbeat                             Request a heartbeat upon start
   -H, -hub                               Start included xPL hub
   -v, -verbose                           Displays message contents while sending
   -version                               Print version info
   -h, -help                              Display this usage information

option -file and -msg may be combined and may contain multiple messages each.

	]],
}

local opt = {
            instance = { "instance", "i" },
            time = { "time", "t" },
            hbeat = { "hbeat", "b" },
            hub = { "hub", "H"},
			verbose = { "verbose", "v" },
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
--------------------------------------------------------------------------------------
-- Create our device
--------------------------------------------------------------------------------------
local logger = xpl.classes.xpldevice:new({    -- create logger device object

    address = xpl.createaddress("tieske", "lualog", opt.instance or "HOST"),
    interval = 1,

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
            if #t > l then
                t = string.sub(1,l)
            end
            if #t < l then
                t = t .. string.rep(" ", l - #t)
            end
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
        print (log)
        if opt.verbose then
            for _, kvp in ipairs(msg.kvp) do
                log = "   "
                log = sizeup(log .. kvp.key, #log + 16) .. "=" .. kvp.value
                print(log)
            end
        end
    end,

    createhbeatmsg = function (self, exit)
        -- call ancestor to create hbeat messages
        local m = self.super.createhbeatmsg(self, exit)
        m:add("version", appversion)
        return m
    end,

})


-- register device
xpl.listener.register(logger)

if opt.time then
    -- create a timer to shutdown the logger
    copas.delayedexecutioner(opt.time, function() xpl.listener.stop() end)
end

-- start listening
xpl.listener.start(opt.hub)

