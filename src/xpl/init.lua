

local require, type, assert, print, pcall, ipairs = require, type, assert, print, pcall, ipairs
local socket = require ("socket")
local string = require ("string")
local math = require ("math")
local _G = _G

require("base")
local prettytostring = prettytostring

module "xpl"


----------------------------------------------------------------
-- define global tables for xPL related functions and settings
----------------------------------------------------------------

----------------------------------------------------------------
-- contains all the objects for the xPL module
-- class table
classes = {}


----------------------------------------------------------------
-- contains the general setting for the xPL module
-- @class table
-- @name settings
-- @field _DEBUG (boolean) set the debug flag and executes available tests at startup
-- @field listenon unused for now
-- @field listento unused for now
-- @field broadcast the IP address to use for broadcasting xPL messages onto the xPL network
-- @field xplport the xPL network port, do not change! only if you want to create a private network and knwo what you are doing
-- @field CAP_ADDRESS pattern to return the three elements of an address, no wildcards allowed
-- @field CAP_FILTER pattern to return the 6 elements of an xPL filter, wildcards are allowed, and the '-' instead of a '.' between vendor and device is also supported (special case)
-- @field CAP_MESSAGE pattern that returns the header information, body (as one string) and the remaining string (the remaining string can be used for the next iteration)
-- @field CAP_KEYVALUE pattern that captures a key-value pair (must end with \n), and the remaining string (the remaining string can be used for the next iteration)
-- @field CAP_SCHEMA pattern that captures a schema class and type from a full schema
-- @field FMT_KEYVALUE format string for creating the message body; existing body, key, value
-- @field FMT_MESSAGE format string for creating messages; type, hop, source, target, schema, body (hop is number, others string)
settings = {
--	_DEBUG = true,					-- will run any tests at startup
--	listenon = "ANY_LOCAL",			-- ANY_LOCAL (any local adapter) or a specific IP address TODO: make this work
--	listento = { "ANY_LOCAL" },		-- ANY_LOCAL (peers within same subnet) or table with IP addresses TODO: make this work
	broadcast = "255.255.255.255",	-- to whom to broadcast outgoing messages
	xplport = 3865,					-- standard xPL port to send to

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
	-- Sends an xPL message
    -- @param msg (string) message to be sent.
    -- @param ip (string) optional, do not use, only for internal use by the hub
    -- @param port (number) optional, do not use, only for internal use by the hub
    -- @return true if succesfull, nil and error otherwise
	send = function (msg, ip, port)
		assert (type(msg) == "string", "illegal message format, expected string, got " .. type (msg))
        assert ((ip and port) or not (ip or port), "provide both ip and port, or provide neither")
		local skt, emsg = socket.udp()			-- create and prepair socket
        if not skt then
            return nil, "Failed to create UDP socket; " .. (emsg or "")
        end
		--assert (skt, "failed to create UDP socket; " .. (emsg or ""))
		skt:settimeout(1)
        if ip == nil and port == nil then   -- not provided, so do a regular broadcast
            skt:setoption("broadcast", true)
        end
		local success, emsg = skt:sendto(msg, ip or settings.broadcast, port or settings.xplport)
        if not success then
            return nil, "Failed to send message over UDP socket; " .. (emsg or "")
        end
		--assert (success, "Failed to send message over UDP socket; " .. (emsg or ""))
		return true
	end

    ----------------------------------------------------------------
	-- Creates an xPL address.
    -- @param vendor (string) the vendor ID to use in the address
    -- @param device (string) the device ID to use in the address
    -- @param instance (string) the instance ID to use in the address, with 2 special cases;
    -- <ul><li><code>'HOST'</code> will generated an instance ID based upon the system hostname</li>
    -- <li><code>'RANDOM'</code> will generate a random instance ID</li></ul>
    -- @return xPL address string, as 'vendor-device.instance'
	createaddress = function (vendor, device, instance)
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
    -- Registers a list of devices with the listener. This method allows for a list of devices
    -- in separate files to be loaded at once and registered.
    -- @param list a table whose values contain the devices to register. If the value is of
    -- type <code>string</code> then it is assumed to be a module/filename that will be 'required'. The
    -- result of 'require' will then be passed on to be registered with the listener.
    -- @return new list with the same contents, except that any string value will be replaced by
    -- return value of the 'require'.
    register = function(list)
        local result = {}
        local req = function(file)
            return require(file)
        end
        for k,v in pairs(list) do
            if type(v) == "string" then
                -- go require it and replace by result
                local succes, err = pcall(function() return require(v) end)
                if not succes then
                    -- failed, show error
                    print(string.format("xpl.register(): Could not require; '%s'. Error: %s", v, err))
                    v = nil
                else
                    -- store result, we had succces
                    v = err
                end
            end
            result[k] = v
            if v then
                local succes, err = pcall(xpl.listener.register, v)
                if not succes then
                    print("xpl.register(): Error registering handler; " .. tostring(err))
                end
            end
        end
        return result
    end

    ----------------------------------------------------------------
    -- Unregisters a list of devices previously registered through <code>xpl.register()</code>
    -- @param list a table whose values contain the devices to unregister. This list should be the
    -- same as the one returned by <code>register()</code> where strings have been replaced.
    unregister = function(list)
        for _, dev in pairs(list) do
            xpl.listener.unregister(dev)
        end
    end

----------------------------------------------------------------
-- load xpl related classes, functions and modules
----------------------------------------------------------------

	-- load classes
    classes.base = require("xpl.classes.base")
	classes.xplfilters = require ("xpl.classes.xplfilter")
	classes.xplmessage = require ("xpl.classes.xplmessage")
	classes.xpldevice = require ("xpl.classes.xpldevice")
    require "xpl.xpllistener"


----------------------------------------------------------------
-- tests for xPLbase
----------------------------------------------------------------

if settings._DEBUG then
	print ()
	print ("Testing capture patterns")
	local f = "tieske-device.instance"
	assert ( f == string.format("%s-%s.%s", string.match(f, settings.CAP_ADDRESS)), "expected the address to be dissected correctly")
	print ("   Address dissection succes")

	local f = "schema.class"
	assert ( f == string.format("%s.%s", string.match(f, settings.CAP_SCHEMA)), "expected the schema to be dissected correctly")
	print ("   Schema dissection succes")

	f = "xpl-cmnd.tieske-device.instance.schema.class"
	assert ( f == string.format("%s.%s-%s.%s.%s.%s", string.match( f, settings.CAP_FILTER)), "expected the filter to be dissected correctly")
	f = "*.*.*.*.*.*"
	assert ( f == string.format("%s.%s.%s.%s.%s.%s", string.match( f, settings.CAP_FILTER)), "expected the filter to be dissected correctly")
	print ("   Filter dissection success")

	local msg = "somenonxpltextxpl-cmnd\n{\nhop=2\nsource=tieske-dev.inst\ntarget=*\n}\nschema.class\n{\nmy-key=some=value in=the=list\nsecond-key=some other value\nonemore=last one in the line\n}\n"
	msg = msg .. msg
	local cnt = 0
	while msg do
		local tpe, hop, source, target, schema, body
		tpe, hop, source, target, schema, body, msg = string.match(msg, settings.CAP_MESSAGE)
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
			key, value, body = string.match(body,settings.CAP_KEYVALUE)
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
	print ("   Hostname based address: ", createaddress("tieske","dev","HOST"))
	print ("   Randomized address    : ", createaddress("tieske","dev","RANDOM"))
	print ("   Set address           : ", createaddress("tieske","dev","greatstuff"))
	print ("Testing xpl.createaddress - end")
	print ()

	print ("=================================================================================================")
	print ("TODO: xpl.send() when not connected to a network; error!, use 'dontroute' option maybe or bind to")
	print ("      localhost address first. see if that takes the error away.")
	print ("=================================================================================================")

end

return xpl
