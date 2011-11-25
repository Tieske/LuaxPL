-- Implements the listener

---------------------------------------------------------------------
-- This module contains the network listener function that listens for inbound
-- xPL messages. Do not use it directly, it will be invoked automatically when
-- the <code>copas</code> loop starts.<br/>
-- <br/>No global will be created, it just returns the listener table. The main
-- xPL module will create a global <code>xpl.listener</code> to access it. To
-- receive incoming messages subscribe to the <code>'newmessage'</code> event.
-- @class module
-- @name xpllistener
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, LuaxPL framework.

local socket = require("socket")
local copas = require("copas.timer")
local netcheck = require("netcheck")
local hub       -- will be 'required' only if its actually being used
local listener  -- will contain the listener table

local host              -- system hostname
local sysip             -- system IP address
local port              -- port to listen on for my devices, incoming from external hub
local xplsocket         -- the socket used for listening for xPL messages
local hub               -- xPL hub
local checker           -- the checkfunction for network changes
local checktimer        -- timer for running the network check




-- creates and initializes an xPL socket to be listened on
-- @param port if provided, the port that will be listened on, if not provided a free
-- port will be sought and bound to.
-- @return socket to listen on, or nil and error message
local createxplsocket = function(port)
    local status
    local skt, err = socket.udp()
    if not skt then return skt, err end
    skt:settimeout(1)
    skt:setoption("broadcast", true)

    status, err = skt:setsockname('*', port)
    if not status then
        return nil, err
    end
    return skt
end

-- creates and initializes the xPL socket to be listened on
-- @return a luasocket.udp socket or nil  and an error message
local getsocket = function()
    host = socket.dns.gethostname()
    sysip = socket.dns.toip(host)
    if not xplsocket then
        port = 50000
        repeat
            xplsocket = createxplsocket(port)
            if not xplsocket then port = port + 1 end
        until xplsocket or port > 50100
        if not xplsocket then
            return nil, "Could not configure a UDP socket"
        end
    end
    return xplsocket
end


-- handles incoming xPL data
local function sockethandler(skt)
    local data
    skt = copas.wrap(skt)
    while true do
        local s, err
        s, err = skt:receive(2048)
        if not s then
            print("Receive error: ", err)
            return
        else
            data = (data or "") .. s
            -- check for messages
            local parsesuccess = true
            while data ~= "" and parsesuccess do
                local msg, remain = xpl.classes.xplmessage.parse(data)
                if msg then
                    data = remain
                    msg.from = "EXTERNAL_HUB"
                    -- regular message on xPL device specific port
                    listener:dispatch(listener.events.newmessage, msg)
                else
                    -- parse failed, so exit loop and wait for more data
                    parsesuccess = false
                end
            end
        end
    end
end

-- whenever the network check determines a change in network connectivity this is called
local function networkchanged(newState, oldState)
    -- restart listener socket
    xplsocket:close()
    xplsocket = nil
    xplsocket = getsocket()
    -- restart hub
    if hub then
        hub.restart()
    end
    -- dispatch an event
    listener:dispatch(listener.events.networkchange, newState, oldState)
end

-- Makes the listener start and stop on Copas events
local eventhandler = function(self, sender, event)
    if sender == copas then
        if event == "loopstarting" then
            local result, err
            -- must start the sockets
            if xpl.settings.listento then
                -- make sure this table is a set (key = value)
                local list = {}
                for k,v in pairs(xpl.settings.listento) do
                    list[v] = v
                end
                xpl.settings.listento = list
            end
            -- start hub
            if xpl.settings.xplhub then
                hub, err = copcall(require, "xpl.xplhub")
                if hub == true then
                    hub = err
                else
                    print(err)
                    copas.exitloop(0,true)
                end
                result, err = hub.start()
                if not result then
                    print(err)
                    copas.exitloop(0,true)
                end
            end
            -- setup/start device socket
            xplsocket, err = xplsocket or getsocket()
            if xplsocket then
                copas.addserver(xplsocket, sockethandler)
            else
                print("Socket could not be created; " .. tostring(err))
                copas.exitloop(0,true)
            end
            -- Setup checking the network status at intervals
            checker = netcheck.getchecker()
            checktimer = copas.newtimer(nil, function()
                    local changed, newState, oldState = checker()
                    if changed then
                        networkchanged(newState, oldState)
                    end
                end, nil, true):arm(xpl.settings.netcheckinterval or 30)
        elseif event == "loopstopped" then
            -- stop the network check
            if checktimer then
                checktimer:cancel()
                checktimer = nil
            end
            checker = nil
            -- must stop the sockets
            xplsocket:close()
            xplsocket = nil
            if hub then
                hub.stop()
                hub = nil
            end
        else
            -- unknown copas event
        end
    else
        -- unknown event source
    end
end



-- Create listener table
listener = {

    ----------------------------------------------------------------------------------------
    -- Returns the current IP address in use by the xpllistener
    -- @return the IP address now used by the listener and to be used in hbeat messages for the
    -- 'remote-ip' key.
    getipaddress = function ()
        return sysip
    end,

    ----------------------------------------------------------------------------------------
    -- Returns the current network port in use by the xpllistener
    -- @return the network port now used by the listener and to be used in hbeat messages for the
    -- 'port' key.
    getport = function ()
        return port
    end,

    ----------------------------------------------------------------------------------------
    -- Returns the LuaxPL devices registered with the xpllistener. Every xpldevice created
    -- will upon initialization automatically register itself for xpllistener events.
    -- @param status if <code>nil</code> then all devices will be added to the return table,
    -- otherwise only the devices with a status property matching this status will be returned.
    -- @return a table keyed by xPL-address, with value being the xpldevice table/object
    getmydevices = function(status)
        if xplsocket then
            -- we're running, get clientlist
            local list = copas.eventer.getclients(listener)
            if list then
                -- listener is registered as a server, get 'newmessage' clients
                list = list[copas.events.newmessage]
                if list then
                    -- verify clients to be xpldevices
                    local mydevs = {}
                    for _, device in pairs(list) do
                        if device.address and device.status and device.connectinterval then
                            -- safe to assume its a device
                            if not status then
                                mydevs[device.address] = device
                            elseif device.status == status then
                                mydevs[device.address] = device
                            else
                                -- don't add, status doesn't match
                            end
                        end
                    end
                    return mydevs
                end
            end
        end
        return nil
    end

}   -- listener


local subscribe, unsubscribe, events        -- make local trick LuaDoc
---------------------------------------------------------------------------------
-- Subscribe to events of xpllistener.
-- @usage# function xpldevice:eventhandler(sender, event, msg, ...)
--     -- do your stuff with the message
-- end
-- &nbsp
-- function xpldevice:initialize()
--     -- subscribe to events of listener for new messages
--     xpl.listener:subscribe(self, self.eventhandler, xpl.listener.events.newmessage)
-- end
-- @see copas.eventer
-- @see events
subscribe = function()
end
---------------------------------------------------------------------------------
-- Unsubscribe from events of xpllistener.
-- @see copas.eventer
-- @see events
unsubscribe = function()
end
---------------------------------------------------------------------------------
-- Events generated by xpllistener. There is only one event, for additional events
-- the start and stop events of the <code>copas</code> scheduler may be used (see
-- 'CopasTimer' and specifically the <code>copas.eventer</code> module).
-- @see subscribe
-- @see unsubscribe
-- @class table
-- @name events
-- @field newmessage event to indicate a new message has arrived. The message will
-- be passed as an argument to the event handler.
-- @field networkchange event to indicate that the newtork state changed (ip address,
-- connectio lost/restored, etc.). The <code>newState</code> and <code>oldState</code>
-- will be passed as arguments to the event handler (see 'NetCheck' documentation for
-- details on the <code>xxxState</code> format)
-- @see subscribe
events = { "newmessage", "networkchange" }

-- add event capability
copas.eventer.decorate(listener, events )

-- subscribe to copas events
copas:subscribe(listener, eventhandler)

-- run tests
if xpl.settings._DEBUG then

	print("   ===================================================")
	print("   TODO: implement test for xpllistener")
	print("   ===================================================")
	print("")
end

-- return listener table
return listener
