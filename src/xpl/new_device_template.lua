-- xPL library, copyright 2011, Thijs Schreijer
--
--

require ("xpl")

local xpldevice = xpl.classes.xpldevice:subclass({})

-----------------------------------------------------------------------------------------
-- Initializes the xpldevice.
-- Will be called upon instantiation of an object (when this file is 'required').
function xpldevice:initialize()
    -- call ancestor
    self.super.initialize(self)

    -- add your stuff here
	self.address = xpl.createaddress("tieske", "luadev", "RANDOM")


end

-----------------------------------------------------------------------------------------
-- Starts the xpldevice.
-- The listener will automatically call this method just before starting the network activity.
function xpldevice:start()
    -- call ancestor
    self.super.start(self)

    -- add your stuff here

end

-----------------------------------------------------------------------------------------
-- Stops the xpldevice.
function xpldevice:stop()

    -- add your stuff here


    -- call ancestor
    self.super.stop(self)
end

-----------------------------------------------------------------------------------------
-- Handler for incoming messages.
-- It will handle only the heartbeat messages (echos) to verify the devices own connection.
-- @param msg the xplmessage object that has to be handled
-- @return the message received or <code>nil</code> if it was fully handled
function xpldevice:handlemessage(msg)

    -- add your stuff here, for the raw unhandled message, still has echos, hbeat,
    -- non-filtered stuff etc.


    -- call ancestor, will handle heartbeat, filtermatching, clearing echos
    msg = self.super.handlemessage(self, msg)

    if msg then

       -- add your stuff here, message is yet unhandled, but passed the filter

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

    -- call ancestor
    local msg = self.super.createhbeatmsg(self, exit)


    -- add your stuff here


    return msg
end

-----------------------------------------------------------------------------------------
-- Handler called whenever the device status changes. Override this method
-- to implement code upon status changes.
-- @param newstatus the new status of the device
-- @param oldstatus the previous status
function xpldevice:statuschanged(newstatus, oldstatus)
    -- call ancestor
    local msg = self.super.statuschanged(self, newstatus, oldstatus)


    -- add your stuff here


end

-- Pick your option here
--=======================================================================================
-- 1) store the class for future use, instantiation and subclassing
-- xpl.classes.yourclassname = xpldevice    -- store the class
-- return xpldevice                         -- return the class, not an instance

-- 2) do not store the class for reuse/subclassing, just return an instance
return xpldevice:new({})                 -- instantiate (calls initialize()!) and return
