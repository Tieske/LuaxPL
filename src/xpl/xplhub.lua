-- Implements the hub

---------------------------------------------------------------------
-- This module contains the embedded hub function. Do not use it directly,
-- it will be invoked automatically if <code>xpl.settings.xplhub == true</code>
-- when the listener is started.<br/>
-- <br/>No global will be created, it just returns the hub table.
-- @class module
-- @name xplhub
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, LuaxPL framework.


-- TODO: what if not connected, will it automatically use LOCALHOST???

local socket = require("socket")
local copas = require("copas.timer")

local host              -- system hostname
local sysip             -- system IP address
local iplist            -- system IP address list
local hubsocket         -- socket used by the hub
local clientlist = {}   -- hub clients to forward messages to


-- creates and initializes the xPL socket to be listened on by the hub
-- @return a luasocket.udp socket or nil and an error message
local gethubsocket = function()
    local data
    -- get/update system network info
    host = socket.dns.gethostname()
    sysip, data = socket.dns.toip(host)
    iplist = data.ip
    -- check for existing socket
    if hubsocket then           -- socket exists, so return existing socket
        return hubsocket
    end
    -- create new UDP socket
    local skt, err = socket.udp()
    if not skt then
        return skt, err
    end
    -- set socket options
    skt:settimeout(1)
    skt:setoption("broadcast", true)
    local status
    status, err = skt:setsockname('*', xpl.settings.xplport)
    if not status then
        return nil, err
    end
    -- we managed, return the configured socket
    return skt
end


-- updates the hub clientlist.
-- to be called when schemaclass 'hbeat' arrives
local function updateclientlist(msg)
    local clientaddress = msg.source
    local clientip = msg:getvalue("remote-ip")
    local clientport = tonumber(msg:getvalue("port"))
    local clientinterval = tonumber(msg:getvalue("interval")) or 5
    local myip = xpl.listener.getipaddress()
    local myport = xpl.listener.getport()
    if myip == clientip and myport == clientport then
        -- this is one of my own, don't add
        return
    end
    if clientip and clientaddress and clientport then
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
        if not match then
            return
        end
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

-- Forward a hub-received message to the local clientslist
local function forwardclient(msg)
    local msg = tostring(msg)
    local donelist = {}   -- ip-port combi we already send to
    local cb
    for addr, client in pairs(clientlist) do
        cb = client.remoteip .. ":" .. client.port
        if not donelist[cb] then
            -- not yet send to this port/ip combination, do now and add to alreadydone list
            xpl.send(msg, client.remoteip, client.port)
            donelist[cb] = cb
        end
    end
end

-- Check if a received message originates from an allowed IP address
-- @return true if it is allowed
local function listentomatch(clientip)
    if xpl.settings.listento["ANY_LOCAL"] then
        -- any local address is allowed, so match only first 3 elements of IP address, with trailing dot.
        clientip = string.format("%s.%s.%s.", string.match(clientip, "^(%d+)%.(%d+)%.(%d+)"))
    end
    for i, v in ipairs(iplist) do
        if string.find(v, clientip, 1, true) == 1 then
            return true
        end
    end
    return false
end

-- handles incoming xPL data
local function sockethandler(skt)
    local data
    skt = copas.wrap(skt)
    while true do
        local s, fromip, fromport
        s, fromip, fromport = skt:receivefrom(2048)
        if not s then
            print("xPL hub receive error: ", fromip)
            return
        else
            data = (data or "") .. s
            -- check for messages
            local parsesuccess = true
            while data ~= "" and parsesuccess do
                local msg, remain = xpl.classes.xplmessage.parse(data)
                if msg then
                    -- we've got a message for the hub on xPL port 3865
                    msg.from = fromip .. ":" .. fromport
                    data = remain
                    -- message for the hub on xPL port 3865
                    if listentomatch(fromip) then
                        -- message is within the range of adresses we're set to be listening on
                        if msg.schema == "hbeat.app" or msg.schema == "config.app" then
                            updateclientlist(msg)
                        elseif msg.schema == "hbeat.end" or msg.schema == "config.end" then
                            removeclient(msg)
                        end
                        -- do hub thing, forward to external devices on the same system
                        forwardclient(msg)
                        -- now dispatch to my own devices as if it was received on the device
                        -- specific port (no need to travel over the network for these)
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



-- Create hub table
local hub
hub = {

    ---------------------------------------------------------------------
    -- Starts the internal hub implementation. It will bind to the xPL port
    -- and start forwarding messages to its clients (external clients on the same
    -- system as well as internal LuaxPL clients)
    -- @return <code>true</code> if success, or <code>nil</code> + error message otherwise
    start = function()
        local err
        -- create socket
        hubsocket, err = gethubsocket()
        if not hubsocket then
            return nil, "Hub could not create socket; " .. err
        end
        -- initialize clientlist
        clientlist = {}
        -- add socket to copas scheduler
        copas.addserver(hubsocket, sockethandler)
        return true
    end,

    ---------------------------------------------------------------------
    -- Reallocates the xPL hub socket. Use this if the network connection
    -- changed while in operation.
    -- @return <code>true</code> if success, or <code>nil</code> + error message otherwise
    restart = function()
        if hubsocket then
            local t = clientlist        -- store current clientlist
            hub.stop()
            local r, err = hub.start()
            clientlist = t              -- restore clientlist
            if not r then
                -- we had an error
                return r, err
            end
            -- success
            return true
        end
    end,

    ---------------------------------------------------------------------
    -- Stops the internal hub implementation and releases the socket.
    -- @return <code>true</code>
    stop = function()
        -- close and destroy hubsocket
        if hubsocket then
            hubsocket:close()
            hubsocket = nil
        end
        return true
    end

}   -- hub



-- run tests
if xpl.settings._DEBUG then

	print("   ===================================================")
	print("   TODO: implement test hub stuff")
	print("   ===================================================")

	print()
end

-- return hub table
return hub
