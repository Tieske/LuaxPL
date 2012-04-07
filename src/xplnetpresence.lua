#!/usr/local/bin/lua

----------------------------------------------------------------------------
-- @copyright 2012 Thijs Schreijer
-- @release Version 0.1, commandline xPL network watch utility.
-- @description# Commandline utility to scan syslog output for MAC and IP addresses for domestic occupancy detection and notify through xPL. Use option <code>-help</code> for a description.
-- &nbsp
-- Example: <code>
-- xplnetpresence.lua -timeout=240 -port=53000 -instance=RANDOM -hub
-- </code>
-- Example setup using a wireless router with DD-WRT firmware (version 'DD-WRT v24-sp2 (08/12/10) std');
-- <ul>
-- <li>Enable systemlog on tab 'service / services' of the admin console and set the target ip address where xplnetpresence.lua is listening.</li>
-- <li>On tab 'security / firewall' enable logging, set level 'low' and all three options (Dropped/Rejected/Accepted) to 'Enabled'.</li>
-- <li>Start xplnetpresence.lua using defaults</li>
-- </ul>


module ("xplnetpresence", package.seeall)

local xpl = require ("xpl")
local appversion = "0.1"
local date = require("date")

local prog = {
	name = "xPL net presence",
	banner = "version " .. appversion .. ", Copyright 2011 Thijs Schreijer",
	use = "Scans syslog output for MAC and IP addresses for domestic occupancy detection",
	options = arg[0] .. [[ [OPTIONS...]
Functional options;
   -version                               Print version info
   -h, -help                              Display this usage information
   -T, -timeout=[120]                     For a MAC or IP address not being seen anymore,
                                          before notifying device as leaving (in seconds)
   -M, -mac=[lua-pattern]                 The Lua pattern to grab the MAC address from
                                          the log message; default = "MAC=([%x:]+)"
   -I, -ip=[lua-pattern]                  The Lua pattern to grab the IP address from
                                          the log message; default = "SRC=([%x%.:]+)"
   -p, -port=[514]                        Port number to listen on for incoming syslog
                                          UDP data
   -c, -config=[filename]                 Filename with a list of known devices, see the
                                          example 'luanetpres_conf.lua'
xPL device options
   -i, -instance=HOST                     InstanceID to be used, or HOST to generate
                                          hostname based id, or RANDOM for random id.
                                          (HOST is default)
   -t, -time=[xx]                         How long should the program run (in seconds),
                                          default is no end time, run continously.
   -H, -hub                               Start included xPL hub
   -B, -broadcast[=255.255.255.255]       Broadcast address to use for sending

Example;
   xplnetpresence.lua -timeout=240 -port=53000 -instance=RANDOM -hub

xPL interface
   The message schema used is 'netpres.basic' which is a custom schema. Trigger
   messages will be send upon devices arriving or departing. The 'type' key will
   specify either 'arrival' or 'departure', other keys are the same.
   A command message is available, using a single key; 'command=list'. This will
   trigger a list of status messages, where the 'type' key will have value 'list'.

	]],
}

local opt = {
            timeout = { "timeout", "T" },
            mac = { "mac", "M" },
            ip = { "ip" , "I" },
            port = { "port", "p" },
            config = { "config", "c" },
            instance = { "instance", "i" },
            time = { "time", "t" },
            hub = { "hub", "H"},
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
    -- create a timer to shutdown the program when due
    copas.delayedexecutioner(opt.time, function() xpl.stop() end)
end

if opt.broadcast then
    -- set a non-default broadcast address
    xpl.settings.broadcast = opt.broadcast
end

if opt.timeout then
    local f = function()
        print(version())
        print("invalid value for switch -T; " .. tostring(opt.timeout) .. ".  Use -help for help on the commandline.")
        os.exit()
    end
    if tonumber(opt.timeout) then
        opt.timeout = tonumber(opt.timeout)
        if opt.timeout < 0 then
            f()
        end
    else
        f()
    end
else
    -- use default
    opt.timeout = 120
end

if not opt.mac then
    -- set default MAC address capture
    opt.mac = "MAC=%x%x:%x%x:%x%x:%x%x:%x%x:%x%x:(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x):%x%x:%x%x"
end

if not opt.ip then
    -- set default IP address capture
    opt.ip = "SRC=([%x%.:]+)"
end

if opt.port then
    local f = function()
        print(version())
        print("invalid value for switch -p; " .. tostring(opt.port) .. ", expected number from 1 to 65535.  Use -help for help on the commandline.")
        os.exit()
    end
    if tonumber(opt.port) then
        opt.port = tonumber(opt.port)
        if opt.port < 1 or opt.port > 65535 then
            f()
        end
    else
        f()
    end
else
    -- set default port to listen on for syslog messages
    opt.port = 514
end

local mlist = {}
local ilist = {}
if opt.config then
    local success, devlist = pcall(loadfile, opt.config)
    if not success then
        print ("failed to load configuration file " .. tostring(opt.config))
        print ("error: " .. tostring(devlist))
        os.exit()
    end
    local success, devlist = pcall(devlist)
    if not success then
        print ("failed to load configuration file " .. tostring(opt.config))
        print ("error: " .. tostring(devlist))
        os.exit()
    end
    if not type(devlist) == "table" then
        print ("failed to load configuration file " .. tostring(opt.config))
        print ("error: Expected a table, got " .. type(devlist))
        os.exit()
    end
    -- by now devlist returned a table
    local cnt = 0
    for k, v in pairs(devlist) do
        local dev = {
            mac = string.lower(tostring(v.mac or "")),
            ip = string.lower(tostring(v.ip or "")),
            name = tostring(v.name or ""),
            timeout = tonumber(v.timeout),
        }
        if dev.name == "" then
            print ("Configfile parse error; name field is required")
            os.exit()
        end
        if dev.mac == "" then dev.mac = nil end
        if dev.ip == "" then dev.ip = nil end
        if not (dev.mac or dev.ip) then
            print ("Configfile parse error; at least field mac or field ip is required")
            os.exit()
        end
        if dev.mac then
            mlist[dev.mac] = dev
        end
        if dev.ip then
            ilist[dev.ip] = dev
        end
        cnt = cnt + 1
    end
    print ("Loaded configfile, parsed " .. cnt .. " devices")
end

local dcount = 1       -- provide unique device name
local xpldevice           -- will hold our device

-- craetes a new xpl message with device info
local function newmessage(device)
    local msg = xpl.classes.xplmessage:new({
        type = "xpl-trig",
        source = xpldevice.address,
        target = "*",
        schema = "netpres.basic"
    })
    msg:add("type", "arrival")
    msg:add("name", device.name or "")
    msg:add("mac", device.mac or "")
    msg:add("ip", device.ip or "")
    msg:add("present", device.present == true)
    if device.firstseen then
        msg:add("firstseen", device.firstseen:fmt("${iso}"))
    else
        msg:add("firstseen", "")
    end
    if device.lastseen then
        msg:add("lastseen", device.lastseen:fmt("${iso}"))
    else
        msg:add("lastseen", "")
    end
    msg:add("maxnotseen", device.maxnotseen or "")
    return msg
end

--------------------------------------------------------------------------------------
-- Main functions for arrival and departure
--------------------------------------------------------------------------------------

-- function will be called when a device has been added (or re-appeared)
local function arrival(device)
    print("Arrival;", (device.mac or device.ip), device.name)
    local msg = newmessage(device)
    msg:setvalue("type", "arrival")
    xpldevice:send(msg)
end

-- function will be called when a device has left (timeout)
local function departure(device)
    print("Departure;", (device.mac or device.ip), device.name)
    local msg = newmessage(device)
    msg:setvalue("type", "departure")
    xpldevice:send(msg)
end

-- list a device, will be called for each known device when a list command is received
local function listdevice(device)
    print("List;", (device.mac or device.ip), device.name, "Max not seen (seconds): " .. (device.maxnotseen or ""))
    local msg = newmessage(device)
    msg.type = "xpl-stat"
    msg:setvalue("type", "list")
    xpldevice:send(msg)
end


--------------------------------------------------------------------------------------
-- Create our device
--------------------------------------------------------------------------------------
xpldevice = xpl.classes.xpldevice:new({    -- create a generic xPL device for the application

    initialize = function(self)
        self.super.initialize(self)
        self.configurable = false
        self.filter = xpl.classes.xplfilters:new({})
        self.filter:add("xpl-cmnd.*.*.*.netpres.basic")
        self.version = appversion   -- make version be reported in heartbeats
        self.address = xpl.createaddress("tieske", "netpres", opt.instance or "HOST")
        self.syslogskt = nil        -- will hold the socket to listen for syslog messages
        self.maclist = mlist   -- list of devices keyed by MAC address
        self.iplist = ilist    -- list of devices keyed by IP address
        self.timer = copas.newtimer(nil,
            function ()
                -- function to check individual device
                local check = function(device)
                    local to = device.timeout or opt.timeout
                    if device.present then
                        if device.lastseen < date():addseconds(-1 * to) then
                            -- its been a while since we saw this one, report as departed
                            device.present = nil
                            departure(device)
                        end
                    end
                end

                for k,v in pairs(self.maclist) do
                    check(v)    -- check all devices for timeouts
                end
                for k,v in pairs(self.iplist) do
                    if not v.mac then
                        -- no mac address, so this one is still to do
                        check(v)
                    end
                end
            end, nil, true, nil)
    end,

    -- returns a device table by mac or ip address, or nil if not found
    getdevice = function(self, mac, ip)
        -- lookup device
        local device
        if mac then device = self.maclist[mac] end
        if not device then device = self.iplist[ip] end
        return device
    end,

    update = function(self, mac, ip)
        --print("saw: ", mac , "@", ip)
        if mac then mac = string.lower(mac) end
        if ip then ip = string.lower(ip) end

        -- lookup device
        local device = self:getdevice(mac, ip)
        local ols
        if device then
            ols = device.lastseen -- store the old lastseen value
        end

        if device then
            -- known device
            if mac and not device.mac then
                -- was found on IP address, but we have a mac now, add it
                device.mac = mac
                self.maclist[mac] = device
                -- TODO: mac address added to existing device, do something?
            end
            if ip and (ip ~= device.ip) then
                -- we didn't have an ip, or had a different ip
                if device.ip then
                    -- IP address changed !
                    self.iplist[device.ip] = nil
                    -- TODO: ip address changed of an existing device, do something?
                else
                    -- IP address added
                    -- TODO: ip address added to existing device, do something?
                end
                device.ip = ip
                self.iplist[ip] = device
            end
        else
            -- new device
            device = {}
            device.mac = mac
            device.ip = ip
            device.firstseen = date()
            device.name = "Device " .. dcount
            dcount = dcount + 1
            -- add to lists
            if mac then self.maclist[mac] = device end
            if ip then self.iplist[ip] = device end
        end
        device.lastseen = date()
        if not device.present then
            device.firstseen = device.lastseen
            device.maxnotseen = 0
            device.present = true
            arrival(device)
        else
            -- update maxnotseen value
            local span = (date() - (ols or date())):spanseconds()
            if span > device.maxnotseen then
                device.maxnotseen = span
            end
        end
    end,

    start = function(self)
        self.super.start(self)

        -- handles incoming syslog data
        local function sysloghandler(skt)
            local data
            skt = copas.wrap(skt)
            while true do
                local s, err
                s, err = skt:receive(8192)
                if not s then
                    print("Syslog receive error: ", err)
                    return
                else
                    -- go match data against MAC and IP patterns
                    local m
                    local i
                    if opt.mac then m = string.match(s, opt.mac) end
                    if opt.ip then i = string.match(s, opt.ip) end
                    -- update list if something was found
                    if m or i then
                        self:update(m, i)
                    end
                end
            end
        end

        -- setup socket to listen on
        local status
        local skt, err = socket.udp()
        if not skt then
            print("Failed creating socket; ", err)
            os.exit()
        end
        skt:settimeout(1)

        status, err = skt:setsockname('*', opt.port)
        if not status then
            print("Failed connecting socket; ", err)
            os.exit()
        end

        -- add created socket to the copas scheduler
        self.syslogskt = skt
        copas.addserver(self.syslogskt, sysloghandler)

        -- start checking for leavers
        self.timer:arm(15)
    end,

    handlemessage = function(self, msg)
        -- call ancestor to handle hbeat messages
        self.super.handlemessage(self, msg)

        if msg then
            -- only the command message will pass our filter, so assume its a list command
            if msg:getvalue("command") == "list" then
                for k,v in pairs(self.maclist) do
                    listdevice(v)
                end
                for k,v in pairs(self.iplist) do
                    if not v.mac then
                        -- no mac address, so this one is still to do
                        listdevice(v)
                    end
                end
            end
        end
    end,

    stop = function(self)
        -- clear socket
        if self.syslogskt then
            self.syslogskt:close()
            self.syslogskt = nil
        end

        -- stop timer
        self.timer:cancel()

        -- cleanup device list
        self.maclist = {}   -- list of deviecs keyed by MAC address
        self.iplist = {}    -- list of devices keyed by IP address

        -- call ancestor
        self.super.stop(self)
    end,

})

-- start listening
print(prog.name)
print(prog.banner)
print("Listening for syslog input on UDP port " .. opt.port .. ". Use option -help for additional options.")
print("")
xpl.start()
print("")

