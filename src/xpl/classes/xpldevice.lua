---------------------------------------------------------------------
-- The base object for xPL devices. It features all the main characteristics
-- of the xPL devices, so only user code needs to be added. Starting, stopping,
-- regular heartbeats, configuration has all been implemented in this base class.<br/>
-- <br/>No global will be created, it just returns the xpldevice base class. The main
-- xPL module will create a global <code>xpl.classes.xpldevice</code> to access it.<br/>
-- <br/>You can create a new device from; <code>xpl.classes.xpldevice:new( {} )</code>,
-- but it is probably best to use the
-- <a href="../files/src/xpl/new_device_template.html">new_device_template.lua</a>
-- file as an example on how to use the <code>xpldevice</code> class
-- @class module
-- @name xpldevice
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, LuaxPL framework.

local copas = require("copas.timer")
local eventer = require("copas.eventer")

-- set the proper classname here, this should match the filename without the '.lua' extension
local classname = "xpldevice"

-----------------------------------------------------------------------------------------
-- Members of the xpldevice object
-- @class table
-- @name xpldevice fields/properties
-- @field address (string) the xpladdress of the device
-- @field interval (number) the xpl heartbeat interval in minutes
-- @field status (string) current status of the connection for this device; <code>"online", "connecting", "offline"</code>
-- @field filter either <code>nil</code> or the <a href="xplfilters.html">xplfilters object</a> with the filter list for the device
-- @field classname (string) the name of this class, basically the filename without the extension. Required to identify the type
-- of class, but also to re-create a device from persistence.
-- @field configitems table to hold the current config items, will start with the regular xPL config items; newconf, interval, filters, groups
-- @field configurable (boolean) if <code>false</code> the device will not respond to configuration messages
-- @field configured (boolean) <code>true</code> if the device has been configured
-- @field version (string) a version number to report in the hearbeat messages, set to <code>nil</code> to not report a version
local xpldevice = xpl.classes.base:subclass({
	address = "tieske-mydev.instance",
    heartbeat = nil,                -- hbeat timer
    status = "offline",             -- device status; offline, connecting, online
    connectinterval = 3,            -- heartbeat interval in seconds, while not yet connected/configured
    lasthbeats = 0,                 -- last hbeat send
    lasthbeatr = 0,                 -- last hbeat received
    heartbeatcheck = nil,           -- timer for checking if we receive our own heartbeat
    filter = nil,                   -- filter object to verify our incoming messages against
    classname = nil,                -- classname, to persist and recreate the device, will be set by initialize()
    configitems = nil,              -- config items, each item is a list keyed by name. The list has 2 keyed
                                    -- values; 'max' with max nr elements, 'type' with type (config/reconf/option)
    configurable = true,            -- is the device configurable or not
    configured = false,             -- has the device been configured
    version = "not set",            -- version number to report in heartbeat, set to nil, to not report it.
    oldhbeataddress = nil,          -- will hold the address the last hbeat is send from, to be able to send
                                    -- a proper end-message.
})

-- Calculates the number of seconds from 1-jan-2010 to now.
local getseconds = function()
    t = os.date("!*t")  -- UTC, no daylight saving
    return (((((t.year-2010) * 365 + t.yday) * 24 + t.hour) * 60 + t.min) * 60 + t.sec)
end

-----------------------------------------------------------------------------------------
-- Initializes the xpldevice.
-- Will be called upon instantiation of an object, override this method to set default
-- values for all properties. It will also subscribe to <code>copas</code> and
-- <code>xpl.listener</code> events for starting, stopping and new message events.
-- Use <code>setsettings()</code> to restore settings from persistence.
-- @see xpldevice:setsettings
-- @see xpldevice:eventhandler
function xpldevice:initialize()
    -- subscribe to events of listener and copas
    xpl.listener:subscribe(self, self.eventhandler)
    copas:subscribe(self, self.eventhandler)
    self.classname = classname
    self.configitems = {
        filters = { max = 16, type = "option" },
        groups = { max = 16, type = "option" },
        interval = { max = 1, type = "option", [1] = 5 },           -- hbeat interval in minutes
        newconf = { max = 1, type = "reconf", [1] = "instance" },   -- instance ID
    }
    -- override in child classes
end

-----------------------------------------------------------------------------------------
-- Handles incoming events. Will deal with copas starting/stopping and listener messages.
-- See CopasTimer documentation on how to use the events.
-- @param sender the originator of the event
-- @param event the event string
-- @param param first event parameter, in case of an <code>xpllistener</code> event <code>newmessage</code> this
-- will for example be the xplmessage received.
-- @param ... any additional event parameters
function xpldevice:eventhandler(sender, event, param, ...)
    if sender == copas then
        if event == copas.events.loopstarted then
            -- must start now
            self:start()
        elseif event == copas.events.loopstopping then
            -- must stop now
            self:stop()
        else
            -- unknown Copas event, do nothing
        end
    elseif sender == xpl.listener then
        if event == xpl.listener.events.newmessage then
            -- got a new message
            self:handlemessage(param)
        elseif event == xpl.listener.events.networkchange then
            -- network info has changed, send hbeat to announce myself again
            self:sendhbeat()
        else
            -- unknown listener event, do nothing
        end
    else
        -- unknown sender, do nothing
    end
    -- override in child classes
end

-----------------------------------------------------------------------------------------
-- Starts the xpldevice.
-- Will run on the copas start event.
-- @see xpldevice:eventhandler
function xpldevice:start()
    if self.status == "offline" then
        self.connectinterval = 3
        lasthbeats = 0                  -- last hbeat send
        lasthbeatr = 24 * 60 * 60       -- last hbeat received, set at 24 hours after lasthbeats
        self.heartbeatcheck = copas.newtimer(nil, function() self:checkhbeat() end, nil, false)
        self:changestatus("connecting")
        local f = function() self:sendhbeat() end
        self.heartbeat = copas.newtimer(f, f, nil, true)
        self.heartbeat:arm(self.connectinterval)
    end
end

-----------------------------------------------------------------------------------------
-- Stops the xpldevice.
-- Will run on the copas stop event.
-- @see xpldevice:eventhandler
function xpldevice:stop()
    if self.status ~= "offline" then
        self:sendhbeat(true) -- send exit hbeat
        if self.heartbeat then
            self.heartbeat:cancel()     -- cancel heartbeat timer
        end
        if self.heartbeatcheck then
            self.heartbeatcheck:cancel()     -- cancel heartbeatcheck timer
        end
        self:changestatus("offline")
    end
end

-----------------------------------------------------------------------------------------
-- Restarts the xpldevice (only if already started, remains stopped otherwise).
-- Use this method after configuration changes that require a device restart.
-- @see xpldevice:setsettings
function xpldevice:restart()
    if self.status ~= "offline" then
        self:stop()
        self:start()
    end
end


-----------------------------------------------------------------------------------------
-- Send configuration capabilities
local sendconfiglist = function(self)
    local settings = self:getsettings()
    local m = xpl.classes.xplmessage:new({})
    m.type = "xpl-stat"
    m.source = self.address
    m.target = "*"
    m.schema = "config.list"
    for name, list in pairs(settings.configitems) do
        local type, val = list.type, name
        if type ~= "config" and type ~= "newconf" then
            type = "option"
        end
        if list.max and list.max > 1 then
            val = val .. "[" .. tostring(list.max) .. "]"
        end
        m:add(type, val)
    end
    m:send()
end

-----------------------------------------------------------------------------------------
-- Send current configuration
local sendconfigcurrent = function(self)
    local settings = self:getsettings()
    local m = xpl.classes.xplmessage:new({})
    m.type = "xpl-stat"
    m.source = self.address
    m.target = "*"
    m.schema = "config.current"
    for name, list in pairs(settings.configitems) do
        for i, val in ipairs(list) do
            m:add(name, val)
        end
    end
    m:send()
end

-----------------------------------------------------------------------------------------
-- Update configuration with the received config information
-- @param msg the config message containing the new configuration
local updateconfig = function(self, msg)
    local settings = self:getsettings()
    settings.configitems = {}
    for k,v in msg:eachkvp() do
        settings.configitems[k] = settings.configitems[k] or {}
        table.insert(settings.configitems[k], v)
    end
    self:setsettings(settings)
    self.configured = true
end

-----------------------------------------------------------------------------------------
-- Handler for incoming messages.
-- It will handle the heartbeat messages (echos) to verify the devices own connection and
-- heartbeat requests. If the device is configurable it will also deal with the configuration
-- messages.<br/>
-- Override this method to handle incoming messages, see the
-- <a href="../files/src/xpl/new_device_template.html">new_device_template.lua</a>
-- for an example.
-- @param msg the <a href="xplmessage.html">xplmessage object</a> to be handled
-- @return the <a href="xplmessage.html">xplmessage object</a> received, or <code>nil</code> if it was handled (eg hbeat, our own
-- echo, etc.)
function xpldevice:handlemessage(msg)
    local _memberof     -- will hold cached result
    local memberof = function(addr)
        -- check if addr provided is member of groups list, cache result so this iteration needs to run only once
        if not _memberof then   -- not in cache yet, so do it now
            _memberof = false
            for i, group in ipairs(self.configitems.groups) do
                if addr == group then
                    _memberof = true
                    break
                end
            end
        end
        return _memberof
    end

    if self.status == "offline" then
        return nil
    end
    if msg.schemaclass == "hbeat" or (self.configurable and msg.schemaclass == "config") then
        if msg.source == self.address and (msg.schema == "hbeat.app" or (self.configurable and msg.schema == "config.app")) then
            -- its our own hbeat message, detect connection status
            self.lasthbeatr = getseconds()
            if self.status == "connecting" then
                self:changestatus("online")
                if self.configurable and not self.configured then
                    -- while unconfigured set heartbeat to 1 minute
                    self.heartbeat:arm(60)
                else
                    -- use configured/set interval
                    self.heartbeat:arm(self.configitems.interval[1] * 60)
                end
            end
            msg = nil
        elseif msg.type == "xpl-cmnd" and msg.schema == "hbeat.request" and (msg.target == "*" or msg.target == self.address or memberof(msg.target)) then
            -- heartbeat request, go send it, at random interval 0-3 seconds
            copas.newtimer(nil, function() self:sendhbeat() end, nil, false):arm(math.random() * 3)
            msg = nil
        end
    end
    if msg then
        -- check if its an echo
        if msg.source == self.address then
            msg = nil   -- don't pass echos
        elseif msg.target ~= "*" and msg.target ~= self.address and not memberof(msg.target) then
            -- its not targetted at me, so let go of it
            msg = nil
        else
            -- its targetted at me, so now check filter
            if self.filter then
                if not self.filter:match(string.format("%s.%s.%s", msg.type, msg.source, msg.schema)) then
                    -- doesn't match our filters, so clear it
                    msg = nil
                end
            end
        end
    end
    if msg and msg.schemaclass == "config" and self.configurable then
        -- its a configuration message
        -- NOTE: config messages are left unhandled and passed on if I'm set to NOT be configurable!
        if msg.type == "xpl-cmnd" and msg.schema == "config.list" and msg:getvalue("command") == "request" then
            -- have to send my config capabilities
            sendconfiglist(self)
            msg = nil
        elseif msg.type == "xpl-cmnd" and msg.schema == "config.current" and msg:getvalue("command") == "request" then
            -- have to send my current config
            sendconfigcurrent(self)
            msg = nil
        elseif msg.type == "xpl-cmnd" and msg.schema == "config.response" and msg.target == self.address then
            -- received new config, must update myself
            updateconfig(self, msg)
            self:restart()
            msg = nil
        end
    end
    return msg
end

-----------------------------------------------------------------------------------------
-- Heartbeat message creator.
-- Will be called to create the heartbeat message to be send. Override this function
-- to modify the hbeat content.
-- @param exit if <code>true</code> then an exit hbeat message, (<code>hbeat.end</code>
-- or <code>config.end</code>) needs to be created.
-- @return <a href="xplmessage.html">xplmessage object</a> with the heartbeat message to be sent.
function xpldevice:createhbeatmsg(exit)
    local m = xpl.classes.xplmessage:new({
        type = "xpl-stat",
        source = self.address,
        target = "*",
    })
    if exit then
        -- we're leaving the network, must send an end-message
        if self.configurable and not self.configured then
            m.schema = "config.end"
        else
            m.schema = "hbeat.end"
        end
    else
        -- regular heartbeat
        if self.configurable and not self.configured then
            m.schema = "config.app"
        else
            m.schema = "hbeat.app"
        end
    end
    local ip, port = xpl.listener.getipaddress(), xpl.listener.getport()
    m:add("interval", self.configitems.interval[1])
    if ip and port then
        m:add("remote-ip", ip)
        m:add("port", port)
    end
    m:add("status", self.status)
    if self.version then
        m:add("version", tostring(self.version))
    end
    return m
end

-----------------------------------------------------------------------------------------
-- Sends heartbeat message.
-- Will send a heartbeat message, the message will be collected from the <code>createhbeatmsg()</code> function.
-- @param exit if <code>true</code> then an exit hbeat message (<code>hbeat.end</code>
-- or <code>config.end</code>) will be send.
-- @see xpldevice:createhbeatmsg
function xpldevice:sendhbeat(exit)
    if exit and self.status == "offline" then
        -- never send an endmessage when I'm offline, in this situation the device is probably
        -- being re-configured at startup from persistence
        return
    end
    local m = self:createhbeatmsg(exit)
    if exit and self.oldhbeataddress ~= m.source then
        -- we're supposed to send the exit message from a different address (this is after we've been
        -- reconfigured with a new address
        m.source = self.oldhbeataddress
    end
    m:send()
    self.oldhbeataddress = m.source
    self.lasthbeats = getseconds()
    -- check in five seconds whether the echo was received
    if self.status == "online" then
        self.heartbeatcheck:arm(5)
    end
end

-- Checks whether we're receiving our own heartbeat. This check is automatically scheduled
-- 5 seconds after a hbeat has been send
function xpldevice:checkhbeat()
    if self.status == "online" then
        local n = getseconds()
        if n - self.lasthbeatr > 5 then
            -- we're online, yet last heartbeat was not received
            -- so basically restart without sending an end-message
            if self.heartbeat then
                self.heartbeat:cancel()     -- cancel heartbeat timer
            end
            if self.heartbeatcheck then
                self.heartbeatcheck:cancel()     -- cancel heartbeatcheck timer
            end
            -- restart device
            self:changestatus("offline")
            self:start()
        end
    end
end

-- Updates currentstatus of device and calls the statuschanged method
-- @param status the new status of the device
function xpldevice:changestatus(status)
    local old = self.status
    self.status = status
    self:statuschanged(status, old)
end

-----------------------------------------------------------------------------------------
-- Handler called whenever the device status (either <code>"online", "connecting"</code> or
-- <code>"offline"</code>) changes. Override this method to implement code upon status changes.
-- @param newstatus the new status of the device
-- @param oldstatus the previous status
function xpldevice:statuschanged(newstatus, oldstatus)
    -- override
end

-----------------------------------------------------------------------------------------
-- Sends xpl message.
-- Will send either a <code>string</code> or an <a href="xplmessage.html">xplmessage object</a>. In the latter
-- case it will set the <code>source</code> property to the address of the device sending.
-- @param msg message to send
function xpldevice:send(msg)
    if type(msg) == "string" then
        local success, err = xpl.send(msg)
        if not success then
            print ("xPLDevice - Error sending xPL message (string); ", err)
        end
        return success, err
    elseif type(msg) == "table" then    -- assume its a message object
        msg.address = self.address
        return msg:send()
    else
        assert(false, "Error sending, expected 'table' (xplmessage object) or 'string', got " .. type(msg))
    end
end

-----------------------------------------------------------------------------------------
-- Gets a table with the device settings to persist. Override this function to add
-- additional settings. All xpl config items in the <code>configitems</code> table will be included
-- automatically by the base class.
-- @return table with settings
-- @see xpldevice:setsettings
function xpldevice:getsettings()
    -- update the settings table for 'newconf' and 'filters' as they are stored elswhere
    -- Copy filter list from object to settings
    local f = {}
    f.max = self.configitems.filters.max or 16
    f.type = self.configitems.filters.type or "option"
    if self.filter and self.filter.list then
        for fltr, _ in pairs(self.filter.list) do
            table.insert(f, fltr)
        end
    end
    self.configitems.filters = f
    -- update the 'newconf' value from our current address
    local vendorid, deviceid, newconf = string.match(self.address, xpl.const.CAP_ADDRESS)
    self.configitems.newconf[1] = newconf

    -- create settings table to deliver
    local s = {}
    -- set basics
    s.classname = self.classname
    s.vendorid = vendorid
    s.deviceid = deviceid
    s.configurable = self.configurable
    s.configured = self.configured
    s.version = self.version
    -- now add config items, go through them one-by-one
    if type(self.configitems) == "table" then
        s.configitems = {}
        -- copy each configitem
        for item, list in pairs(self.configitems) do
            local t = {}
            t.max = list.max
            t.type = list.type
            -- copy each element in the config item
            for _, v in ipairs(list) do
                table.insert(t, v)
            end
            s.configitems[item] = t
        end
    end
    return s
end

-----------------------------------------------------------------------------------------
-- Sets the provided settings in the device. Override this method to add additional settings
-- @param s table with settings as generated by <code>getsettings()</code>.
-- @return <code>true</code> if the settings provided require a restart of the device (when
-- the instance name changed for example). Make sure to call <code>restart()</code> in that case.
-- @see xpldevice:restart
-- @see xpldevice:getsettings
-- @usage# if mydev:setsettings(mysettings) then mydev:restart() end
function xpldevice:setsettings(s)
    -- load the new configitem table
    local ci = {}  -- new ci table
    if self.configitems then -- use my own table, so we do not import non-existing items
        for item, list in pairs(self.configitems) do
            local t = {}
            if s.configitems[item] then
                -- this CI is present in the provided settings, so copy it
                t.max = tonumber(s.configitems[item].max) or tonumber(list.max) or 1
                t.type = s.configitems[item].type or list.type or "option"
                for i, v in ipairs(s.configitems[item]) do
                    if i <= t.max then
                        t[i] = v
                    end
                end
            else
                -- this CI is not present, just maintain generics in new empty element
                t.max = tonumber(list.max) or 1
                t.type = list.type or "option"
                -- special cases;
                if item == "interval" then
                    t[1] = self.configitems.interval[1]     -- maintain current interval
                elseif item == "newconf" then
                    t[1] = self.configitems.newconf[1]     -- maintain current instanceid (=newconf)
                end
            end
            ci[item] = t
        end
        -- table built, now replace current one
        self.configitems = ci
    end
    -- values for 'filters' and 'newconf' are stored elsewhere, so update them now
    -- update filters
    if self.configitems.filters then
        self.filter = xpl.classes.xplfilters:new({})
        for i, flt in ipairs(self.configitems.filters) do
            self.filter:add(flt)
        end
    else
        -- no filter provided
        self.filter = nil
    end
    -- update address (newconf), create new address
    local vendorid, deviceid, newconf = string.match(self.address, xpl.const.CAP_ADDRESS)
    vendorid = s.vendorid or vendorid or "tieske"
    deviceid = s.deviceid or deviceid or "mydev"
    newconf = self.configitems.newconf[1] or newconf or "RANDOM"
    self.address = xpl.createaddress(vendorid, deviceid, newconf)

    self.configurable = s.configurable or self.configurable
    self.configured = s.configured or self.configured
    self.version = s.version or self.version
    self.classname = s.classname or self.classname
    return true     -- quick and dirty shortcut, always restart
end


return xpldevice
