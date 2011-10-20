-- xPL library, copyright 2011, Thijs Schreijer
--
--

-----------------------------------------------------------------------------------------
-- @class table
-- @name fields/properties of the xpldevice object
-- @field address the xpladdress of the device
-- @field interval the xpl heartbeat interval in minutes
-- @field status current status of the connection for this device; online, connecting, offline
local xpldevice = xpl.classes.base:subclass({
	address = "tieske-mydev.instance",
    heartbeat = nil,                -- hbeat timer
    status = "offline",             -- device status; offline, connecting, online
    interval = 5,                   -- heartbeat interval in minutes
    connectinterval = 3,            -- heartbeat interval in seconds, while not yet connected
    lasthbeats = 0,                 -- last hbeat send
    lasthbeatr = 0,                 -- last hbeat received
    heartbeatcheck = nil,           -- timer for checking if we receive our own heartbeat
})

-- Calculates the number of seconds from 1-jan-2010 to now.
local getseconds = function()
    t = os.date("!*t")  -- UTC, no daylight saving
    return (((((t.year-2010) * 365 + t.yday) * 24 + t.hour) * 60 + t.min) * 60 + t.sec)
end

-----------------------------------------------------------------------------------------
-- Initializes the xpldevice.
-- Will be called upon instantiation of an object.
function xpldevice:initialize()
    -- override in child classes
end

-----------------------------------------------------------------------------------------
-- Starts the xpldevice.
-- The listener will automatically start all devices registered.
function xpldevice:start()
    if self.status ~= "offline" then
        self:stop()
    end
    self.connectinterval = 3
    lasthbeats = 0                  -- last hbeat send
    lasthbeatr = 24 * 60 * 60       -- last hbeat received, set at 24 hours after lasthbeats
    self.heartbeatcheck = copas.newtimer(nil, function() self:checkhbeat() end, nil, false)
    self:changestatus("connecting")
    local f = function() self:sendhbeat() end
    self.heartbeat = copas.newtimer(f, f, nil, true)
    self.heartbeat:arm(self.connectinterval)
end

-----------------------------------------------------------------------------------------
-- Stops the xpldevice.
function xpldevice:stop()
    if self.status ~= "offline" then
        self:sendhbeat(true) -- send exit hbeat
        if self.heartbeat then
            self.heartbeat:cancel()     -- cancel heartbeat timer
        end
        if self.heartbeat then
            self.heartbeatcheck:cancel()     -- cancel heartbeatcheck timer
        end
        self:changestatus("offline")
    end
end

-----------------------------------------------------------------------------------------
-- Handler for incoming messages.
-- It will handle only the heartbeat messages (echos) to verify the devices own connection.
-- @param msg the xpl message object to be handled
-- @return the message received, or <code>nil</code> if it was handled (eg hbeat, our own
-- echo etc.)
function xpldevice:handlemessage(msg)
    if self.status == "offline" then
        return nil
    end
    if msg.schemaclass == "hbeat" then
        if msg.source == self.address and msg.schema == "hbeat.app" then
            -- its our own hbeat message, detect connection status
            self.lasthbeatr = getseconds()
            if self.status == "connecting" then
                self:changestatus("online")
                self.heartbeat:cancel()
                self.heartbeat:arm(self.interval * 60)
            end
            msg = nil
        elseif msg.type == "xpl-cmnd" and msg.schema == "hbeat.request" and (msg.target == "*" or msg.target == self.address) then
            -- heartbeat request, go send it, at random interval 0-3 seconds
            copas.newtimer(nil, function() self:sendhbeat() end, nil, false):arm(math.random() * 3)
            msg = nil
        end
    end
    if msg then
        -- check if its an echo
        if msg.source == self.address then
            msg = nil   -- don't pass echos
        else
            -- check filter
            if self.filter then
                if not filter:match(string.format("%s.%s.%s", msg.type, msg.source, msg.schema)) then
                    -- doesn't match our filters, so clear it
                    msg = nil
                end
            end
        end
    end
    return msg
end

-----------------------------------------------------------------------------------------
-- Heartbeat message creator.
-- Will be called to create the heartbeat message to be send. Override this function
-- to modify the hbeat content.
-- @param exit if true then an exit hbeat message, for example 'hbeat.end' needs to be created.
-- @return xplmessage object with the heartbeat message to be sent.
function xpldevice:createhbeatmsg(exit)
    local m = xpl.classes.xplmessage:new({
        type = "xpl-stat",
        source = self.address,
        target = "*",
        schema = "hbeat.app",
    })
    if exit then
        m.schema = "hbeat.end"
    end
    m:add("interval", self.interval)
    m:add("remote-ip", xpl.listener.getipaddress())
    m:add("port", xpl.listener.getport())
    m:add("status", self.status)
    return m
end

-----------------------------------------------------------------------------------------
-- Sends heartbeat message.
-- Will send a heartbeat message, the message will be collected from the <code>createhbeatmsg()</code> function.
-- @param exit if true then an exit hbeat message, for example 'hbeat.end', will be send.
-- @see createhbeatmsg
function xpldevice:sendhbeat(exit)
    local m = self:createhbeatmsg(exit)
    xpl.send(tostring(m))
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
            -- last heartbeat was not received
            if self.heartbeat then
                self.heartbeat:cancel()     -- cancel heartbeat timer
            end
            if self.heartbeat then
                self.heartbeatcheck:cancel()     -- cancel heartbeatcheck timer
            end
            -- restart device
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
-- Handler called whenever the device status changes. Override this method
-- to implement code upon status changes.
-- @param newstatus the new status of the device
-- @param oldstatus the previous status
function xpldevice:statuschanged(newstatus, oldstatus)
    -- override
end

-----------------------------------------------------------------------------------------
-- Sends xpl message.
-- Will send either a <code>string</code> or an <code>xplmessage</code> object. In the latter
-- case it will set the <code>source</code> property to the address of the device sending.
-- @param msg message to send
function xpldevice:send(msg)
    if type(msg) == "string" then
        return xpl.send(msg)
    elseif type(msg) == "table" then    -- assume its an message object
        msg.address = self.address
        return msg:send()
    else
        return nil, "Error sending, expected 'table' (xplmessage object) or 'string', got " .. type(msg)
    end
end

return xpldevice
