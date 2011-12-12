---------------------------------------------------------------------
-- This module contains the main xPL functionality. Upon requiring it,
-- it will load all supporting modules and classes. To use the framework
-- you should only need to <code>require("xpl")</code> and any of your own
-- devices (see the included device template for a quick start).<br/>
-- <br/>A global <code>xpl</code> will be created. Through this global the
-- following components are accessible;<ul>
-- <li><code><a href="xpllistener.html">xpl.listener</a></code> the network listener that will receive the messages from the network</li>
-- <li><code><a href="../files/src/xpl/classes/base.html">xpl.classes.base</a></code> base class for all other classes</li>
-- <li><code><a href="xplfilters.html">xpl.classes.xplfilters</a></code> implements the filters for an xPL device</li>
-- <li><code><a href="xplmessage.html">xpl.classes.xplmessage</a></code> message object</li>
-- <li><code><a href="xpldevice.html">xpl.classes.xpldevice</a></code> device baseclass</li>
-- </ul>
-- <br/>The xPL framework uses 'CopasTimer' to provide timers, events and
-- backgroundworkers. Please consult the 'CopasTimer' documentation on how
-- this works.
-- @class module
-- @name xpl
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, LuaxPL framework.


local socket = require("socket")
local copas = require("copas.timer")
copas.eventer = require("copas.eventer")

----------------------------------------------------------------
-- define global tables for xPL related functions and settings
----------------------------------------------------------------

-- create global xpl table
xpl = {
    _COPYRIGHT   = "Copyright (C) 2011 Thijs Schreijer",
    _DESCRIPTION = "LuaxPL; Lua framework for xPL applications/devices",
    _VERSION     = "0.1",
}

----------------------------------------------------------------
-- contains all the objects for the xPL module
-- class table
xpl.classes = {}


----------------------------------------------------------------
-- contains the general settings for the xPL module
-- @class table
-- @name settings
-- @field _DEBUG (boolean) set the debug flag and executes available tests at startup
-- @field listenon unused for now
-- @field listento ANY_LOCAL (peers within same subnet) or table with IP addresses (applies only to hub function)
-- @field broadcast the IP address to use for broadcasting xPL messages onto the xPL network
-- @field xplport the xPL network port, do not change! only if you want to create a private network and know what you are doing
-- @field xplhub (boolean) should the internal hub be started
-- @field netcheckinterval (number) interval in seconds for checking the network connection for any changes (defaults to 30).
-- @field devices (table) table with device specific settings, <code>key</code> is device table, <code>value</code>
-- is device specific settings. Fixed fields in the settings table are; <ul>
-- <li><code>classname</code> (string) name of the class to create the device</li>
-- <li><code>updatehandler</code> (function) may be called from the device when its settings have changed</li>
-- <li><code>...</code></li>
-- <li><code>...</code></li>
-- </ul>
xpl.settings = {
--	_DEBUG = true,					-- will run any tests at startup
--	listenon = "ANY_LOCAL",			-- ANY_LOCAL (any local adapter) or a specific IP address TODO: make this work
	listento = { "ANY_LOCAL" },		-- ANY_LOCAL (peers within same subnet) or table with IP addresses. Applies only to hub function.
                                    -- will be made into a set (key = value) when the listener starts
	broadcast = "255.255.255.255",	-- to whom to broadcast outgoing messages
	xplport = 3865,					-- standard xPL port to send to
    xplhub = false,                 -- should the embedded hub be used
    netcheckinterval = 30,          -- how often to check for changes in network state (in seconds)
    devices = {},                   -- table with device settings, key = devicetable, value = settingstable
}

----------------------------------------------------------------
-- contains constants for the xPL module
-- @class table
-- @name const
-- @field CAP_ADDRESS pattern to return the three elements of an address, no wildcards allowed
-- @field CAP_FILTER pattern to return the 6 elements of an xPL filter, wildcards are allowed, and the '-' instead of a '.' between vendor and device is also supported (special case)
-- @field CAP_MESSAGE pattern that returns the header information, body (as one string) and the remaining string (the remaining string can be used for the next iteration)
-- @field CAP_KEYVALUE pattern that captures a key-value pair (must end with \n), and the remaining string (the remaining string can be used for the next iteration)
-- @field CAP_SCHEMA pattern that captures a schema class and type from a full schema
-- @field FMT_KEYVALUE format string for creating the message body; existing body, key, value
-- @field FMT_MESSAGE format string for creating messages; type, hop, source, target, schema, body (hop is number, others string)
xpl.const = {
    -- define standard captures
	CAP_ADDRESS = "([%l%u%d]+)[%-]([%l%u%d]+)%.([%l%u%d%-]+)",
	CAP_FILTER = "([%l%u%-%*]+)%.([%l%u%d%*]+)[%.%-]([%l%u%d%*]+)%.([%l%u%d%-%*]+)%.([%l%u%d%-%*]+)%.([%l%u%d%-%*]+)",
	CAP_MESSAGE = "(xpl%-[%l%u]+)\n{\nhop=(%d+)\nsource=([%l%u%d%-%.]+)\ntarget=([%l%u%d%-%.%*]+)\n}\n([%l%u%d%-]+%.[%l%u%d%-]+)\n{\n(.-\n)}\n(.*)",
	CAP_KEYVALUE = "([%l%u%d%-]+)=(.-)\n(.*)",
	CAP_SCHEMA = "(.-)%.(.*)",

    -- define standard formats
    FMT_KEYVALUE = "%s%s=%s\n",
	FMT_MESSAGE = "%s\n{\nhop=%s\nsource=%s\ntarget=%s\n}\n%s\n{\n%s}\n",
}


----------------------------------------------------------------
-- generic utility functions
----------------------------------------------------------------

    ----------------------------------------------------------------
	-- Starts the loop and from there the listener, hub and devices.
    -- This is a simple shortcut to <code>copas.loop()</code> and it
    -- takes the same parameters
    xpl.start = function(...)
        copas.loop(...)
    end

    ----------------------------------------------------------------
	-- Exits the loop and from there stops the listener, hub and devices.
    -- This is a simple shortcut to <code>copas.exitloop()</code> and it
    -- takes the same parameters
    xpl.stop = function(...)
        copas.exitloop(...)
    end

    ----------------------------------------------------------------
	-- Sends an xPL message
    -- @param msg (string) message to be sent.
    -- @param ip (string) optional, do not use, only for internal use by the hub
    -- @param port (number) optional, do not use, only for internal use by the hub
    -- @return <code>true</code> if succesfull, <code>nil</code> and error otherwise
	xpl.send = function (msg, ip, port)
		assert (type(msg) == "string", "illegal message format, expected string, got " .. type (msg))
        assert ((ip and port) or not (ip or port), "provide both ip and port, or provide neither")
		local skt, emsg = socket.udp()			-- create and prepair socket
        if not skt then
            return nil, "Failed to create UDP socket; " .. (emsg or "")
        end
		skt:settimeout(1)
        if ip == nil and port == nil then   -- not provided, so do a regular broadcast
            skt:setoption("broadcast", true)
        end
        if not ip then
            local loopbackip = socket.dns.toip("localhost")
            if loopbackip and loopbackip == xpl.listener.getipaddress() then
                -- we're connected on loopback only, send directly, no routing/broadcast
                ip = loopbackip
                port = xpl.settings.xplport
            end
        end
		local success, emsg = skt:sendto(msg, ip or xpl.settings.broadcast, port or xpl.settings.xplport)
        if not success then
            return nil, "Failed to send message over UDP socket; " .. (emsg or "")
        end
		return true
	end

    ----------------------------------------------------------------
	-- Creates an xPL address.
    -- @param vendor (string) the vendor id to use in the address
    -- @param device (string) the device id to use in the address
    -- @param instance (string) the instance id to use in the address, with 2 special cases;
    -- <ul><li><code>'HOST'</code> will generated an instance id based upon the system hostname</li>
    -- <li><code>'RANDOM'</code> will generate a random instance id</li></ul>
    -- @return xPL address string, formatted as 'vendor-device.instance'
	xpl.createaddress = function (vendor, device, instance)
		assert (type(vendor) == "string", "illegal vendor value, expected string, got " .. type(vendor))
		assert (type(device) == "string", "illegal device value, expected string, got " .. type(device))
		if instance == "" then
			instance = nil
		end
		instance = instance or "HOST"
		assert (type(instance) == "string", "illegal instance value, expected string, got " .. type(instance))
		local allowed = "abcdefghijklmnopqrstuvwxyz1234567890-"		-- allowed characters in instance id
		if instance == "HOST" then
			local r, sysname = pcall(socket.dns.gethostname)
			if r then
				sysname = string.lower(sysname)
			else
				sysname = "hostunknown"
			end
			instance = ""
			if sysname then
				for _, c in ipairs({string.byte(sysname, 1, #sysname)}) do
					if string.find(allowed, string.char(c)) then
						-- its in the allowed list, so add it
						instance = instance .. string.char(c)
					end
				end
				if #instance > 16 then	-- too long, shorten.
					instance = string.sub(instance, 1, 16)
				end
				if instance == "" then	-- empty, fall back to randomized
					instance = "RANDOM"
				end
			else
				-- something went wrong, switch to random id
				instance="RANDOM"
			end
		end
		if instance == "RANDOM" then
			instance = ""
			for n = 1,16 do
				instance = instance .. string.char(string.byte(allowed, math.random(1,#allowed)))
			end
		end
		return string.format("%s-%s.%s", vendor, device, instance)
	end

----------------------------------------------------------------
-- load xpl related classes, functions and modules
----------------------------------------------------------------

	-- load classes
    xpl.classes.base = require("xpl.classes.base")
	xpl.classes.xplfilters = require ("xpl.classes.xplfilter")
	xpl.classes.xplmessage = require ("xpl.classes.xplmessage")
	xpl.classes.xpldevice = require ("xpl.classes.xpldevice")
    -- load listener
    xpl.listener = require("xpl.xpllistener")


----------------------------------------------------------------
-- tests for xPLbase
----------------------------------------------------------------

if xpl.settings._DEBUG then
	print ()
	print ("Testing capture patterns")
	local f = "tieske-device.instance"
	assert ( f == string.format("%s-%s.%s", string.match(f, xpl.const.CAP_ADDRESS)), "expected the address to be dissected correctly")
	print ("   Address dissection succes")

	local f = "schema.class"
	assert ( f == string.format("%s.%s", string.match(f, xpl.const.CAP_SCHEMA)), "expected the schema to be dissected correctly")
	print ("   Schema dissection succes")

	f = "xpl-cmnd.tieske-device.instance.schema.class"
	assert ( f == string.format("%s.%s-%s.%s.%s.%s", string.match( f, xpl.const.CAP_FILTER)), "expected the filter to be dissected correctly")
	f = "*.*.*.*.*.*"
	assert ( f == string.format("%s.%s.%s.%s.%s.%s", string.match( f, xpl.const.CAP_FILTER)), "expected the filter to be dissected correctly")
	print ("   Filter dissection success")

	local msg = "somenonxpltextxpl-cmnd\n{\nhop=2\nsource=tieske-dev.inst\ntarget=*\n}\nschema.class\n{\nmy-key=some=value in=the=list\nsecond-key=some other value\nonemore=last one in the line\n}\n"
	msg = msg .. msg
	local cnt = 0
	while msg do
		local tpe, hop, source, target, schema, body
		tpe, hop, source, target, schema, body, msg = string.match(msg, xpl.const.CAP_MESSAGE)
		if not tpe then break end	-- no more found, exit loop
		cnt = cnt + 1
		assert (tpe == "xpl-cmnd", "Expected command type message")
		assert (hop == "2", "Expected hop count 1")
		assert (source == "tieske-dev.inst", "Expected other address")
		assert (target == "*", "Expected target *")
		assert (schema == "schema.class", "Expected other schema")
		local i = 0
		while body do
			local key, value
			key, value, body = string.match(body,xpl.const.CAP_KEYVALUE)
			if not key then break end -- no more found, exit loop
			if i == 0 then assert(key == "my-key" and value == "some=value in=the=list", "Expected different key-value pair") end
			if i == 1 then assert(key == "second-key" and value == "some other value", "Expected different key-value pair") end
			if i == 2 then assert(key == "onemore" and value == "last one in the line", "Expected different key-value pair") end
			i = i + 1
		end
		assert ( i ==3 , "expected more key-value pairs")
		print ("   Message " .. cnt .. " dissection success")
	end
	print ("Testing capture patterns - end")

	print()
	print ("Testing xpl.createaddress")
	print ("   Hostname based address: ", xpl.createaddress("tieske","dev","HOST"))
	print ("   Randomized address    : ", xpl.createaddress("tieske","dev","RANDOM"))
	print ("   Set address           : ", xpl.createaddress("tieske","dev","greatstuff"))
	print ("Testing xpl.createaddress - end")
	print ()

	print ("=================================================================================================")
	print ("TODO: xpl.send() when not connected to a network; error!, use 'dontroute' option maybe or bind to")
	print ("      localhost address first. see if that takes the error away.")
	print ("=================================================================================================")

end

return xpl
