-- Implements the listener

-- TODO: check usage of isexiting

local socket = require("socket")
local copas = require("copas.timer")

local host, sysip, port, iplist
local xplsocket             -- the socket used for listening for xPL messages
local handlerlist = {}
local hubsocket         -- socket used by the hub
local clientlist = {}   -- hub clients to forward messages to


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
    sysip, data = socket.dns.toip(host)
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

-- handles incoming xPL messages, distributes to registered devices/handlers.
local function messagehandler(msg)
    for _, handler in pairs(handlerlist) do
        if type(handler) == "function" then
            handler(msg)
        else
            handler:handlemessage(msg)
        end
    end
end

-- updates the hub clientlist.
-- to be called when schemaclass 'hbeat' arrives
local function updateclientlist(msg)
    local clientaddress = msg.source
    local clientip = msg:getvalue("remote-ip")
    local clientport = tonumber(msg:getvalue("port"))
    local clientinterval = tonumber(msg:getvalue("interval"))
    if clientip == sysip and clientport == port then
        -- its one of my own, no need to add it to the list
        return
    end
    if clientip and clientaddress and clientport and clientinterval then
        -- we've got stuff to work with
        -- is it on our system?
        local match
        for i, v in ipairs(iplist) do
            if v == clientip then
                match = v
                break
            end
        end
        -- is it a local IP?
        if not match then return end
        -- so update/add our local client
        local client = clientlist[clientaddress] or { address = clientaddress }
        client.remoteip = clientip
        client.port = clientport
        client.expire = socket.gettime() + 60 * (clientinterval * 2 + 1)
        clientlist[clientaddress] = client
    end
    -- cleanup client list
    local t = socket.gettime()
    for addr, client in pairs(clientlist) do
        if client.expire < t then
            -- expired, so clean up
            clientlist[addr] = nil
        end
    end
end

-- updates the hub clientlist by removing the device
-- to be called when schemaclass 'hbeat.end' or 'config.end' arrives
local function removeclient(msg)
    clientlist[msg.source] = nil
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
                    if hubsocket then
                        -- message for the hub on xPL port 3865
                        if msg.schema == "hbeat.app" or msg.schema == "config.app" then
                            updateclientlist(msg)
                        elseif msg.schema == "hbeat.end" or msg.schema == "config.end" then
                            removeclient(msg)
                        end
                        -- do hub thing, forward to external devices on the same system
                        local m = tostring(msg)
                        for addr, client in pairs(clientlist) do
                            xpl.send(m, client.remoteip, client.port)
                        end
                        -- now dispatch to my own devices as if it was received on the device
                        -- specific port (no need to travel over the network for these)
                        --messagehandler(msg) replaced by event
                        xpl.listener:dispatch(xpl.listener.events.newmessage, msg)
                    else
                        -- regular message on xPL device specific port
                        -- only if we use a 'foreign' hub and not my own
                        --messagehandler(msg) replaced by event
                        xpl.listener:dispatch(xpl.listener.events.newmessage, msg)
                    end
                else
                    -- parse failed, so exit loop and wait for more data
                    parsesuccess = false
                end
            end
        end
    end
end

-- creates and initializes the xPL socket to be listened on by the hub
-- @return a luasocket.udp socket or nil and an error message
local gethubsocket = function()
    host = socket.dns.gethostname()
    sysip, data = socket.dns.toip(host)
    iplist = data.ip
    if hubsocket then
        return hubsocket
    end
    local err
    hubsocket, err = createxplsocket(xpl.settings.xplport)
    return hubsocket, err
end

-- Adds the xPL hub socket to the Copas dispatcher.
-- This must be called before calling the <code>start()</code> method
-- @return true for success, or nil and an error message
local addhub = function()
    local skt, err = hubsocket or gethubsocket()
    if skt then
        copas.addserver(skt, sockethandler)
        return true
    else
        return nil, err
    end
end




-- Create listener table
local listener = {

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

    ---------------------------------------------------------------------------------
    -- property indicating whether the xPL listener is running.
    -- Note: this is a field, not a function!
    -- @return# <code>nil &nbsp:</code> if the listener is not running
    -- <code>false:</code> if the listener is running
    -- <code>true :</code> if the listener is currently exiting its loop
    isexiting = function() end,  -- Trick LuaDoc
    isexiting = nil,

    ---------------------------------------------------------------------------------
    -- Starts the xPL listener loop. This will start the underlying
    -- Copas loop, hence this will be blocking!
    -- at least one handler or timer must be added before calling start, if not
    -- you will have no means of exiting. All handlers registered will get their
    -- <code>handler:start()</code> method called.
    -- @param hub if true, the hub will started, if false, no hub will be started
    -- @return true after the loop exits or nil and an error message
    start = function(hub)
        if isexiting == nil then
            isexiting = false
            if hub then addhub() end
            local err
            xplsocket, err = xplsocket or getsocket()
            if xplsocket then
                copas.addserver(xplsocket, sockethandler)
                --starthandlers(0.5)  will run on copas event
                copas.loop()
                isexiting = nil
                return true
            else
                isexiting = nil
                return nil, err
            end
        end
    end,

    ---------------------------------------------------------------------------------
    -- stops the listener.
    -- because the start function is blocking, this can only be called from within a
    -- piece of code running within the Copas scheduler. If succesful, the function
    -- <code>start()</code> will return, and any code after that statement will continue.
    stop = function()
        if isexiting == false then
            -- stophandlers()   runs on copas events
            isexiting = true
            if not copas.isexiting() then
                copas.exitloop(5)   -- timeout of 5 seconds
            end
        end
    end,

}   -- listener


local subscribe, unsubscribe, events        -- make local trick LuaDoc
---------------------------------------------------------------------------------
-- Subscribe to events of xpllistener.
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
-- Events generated by xpllistener.
-- @see subscribe
-- @see unsubscribe
-- @class table
-- @field newmessage event to indicate a new message has arrived. The message will
-- be passed as an argument to the event handler.
events = { "newmessage" }

-- add event capability
copas.eventer.decorate(listener, events )

-- run tests
if xpl.settings._DEBUG then

	print("   ===================================================")
	print("   TODO: implement test for xpllistener")
	print("   TODO: implement test hub stuff")
	print("   ===================================================")

	print()
end

-- return listener table
return listener
