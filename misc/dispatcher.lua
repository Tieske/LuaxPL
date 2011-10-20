
local servers = {}
local clients = {}
local eventqueue = {}   -- queue of events received from other threads
local mythread          -- dispatcher thread
local isexiting         -- nil; not running, false; running, true, will exit
local isstarted         -- true if the dispatcher is already running

-------------------------------------------------------------------------------
-- registers a server that will fire events
-- @param server a unique key to identify the specific server, can be a string or
-- table, or whatever, as long as it is unique
-- @param eventlist list of strings with event names
function register(server,eventlist)
    assert(server, "Server parameter cannot be nil")
    assert(not servers[server],"Server is already registered")
    assert(type(eventlist) == "table", "EventList must be a table with strings")
    -- build event table with listeners
    local events = {}    -- table with subscribers to SPECIFIC events of server
    for i, v in ipairs(eventlist) do
        events[v] = {}
    end
    local all = {}    -- table with subscribers to ALL events of server
    servers[server] = { events = events, all = all}
    return true
end

-------------------------------------------------------------------------------
-- unregisters a server that will fire events
-- @param server a unique key to identify the specific server, can be a string or
-- table, or whatever, as long as it is unique
function unregister(server)
    assert(server, "Server parameter cannot be nil")
    servers[server] = nil
    for c, ct in pairs(clients) do
        ct[server] = nil
    end
    return true
end

-------------------------------------------------------------------------------
-- subscribes a client to events
-- @param client unique client parameter (self)
-- @param server a unique key to identify the specific server
-- @param handler event handler function to be called
-- @param event string, nil to subscribe to all events
function subscribe(client, server, handler, event)
    assert(client, "Client parameter cannot be nil")
    assert(type(handler) == "function", "Invalid handler parameter, expected function, got " .. type(handler))
    assert(server, "Server parameter cannot be nil")
    local stable = servers[server]  -- server table
    assert(stable, "Server not found")
    if event then
        -- specific event
        local etable = stable.events[event]
        assert(etable, "Event not found for this server")
        etable[client] = handler
    else
        -- all events
        stable.all[client] = handler
    end
    if not clients[client] then
        local s = {}
        clients[client] = s
    end
    clients[client][server] = server
    return true
end

-------------------------------------------------------------------------------
-- unsubscribes a client from events
-- @param client unique client parameter (self)
-- @param server a unique key to identify the specific server, nil to unsubscribe all
-- @param event string, nil to unsubscribe from all events
function unsubscribe(client, server, event)
    assert(client, "Client parameter cannot be nil")
    assert(server, "Server parameter cannot be nil")

    local unsubserv = function(server)
        -- unsubscribe from 1 specific server
        local stable = servers[server]
        if not event then
            -- unsubscribe from all events
            stable.all[client] = nil
        else
            -- unsubscribe from specific event
            if stable.events[event] then
                stable.events[event][client] = nil
            end
        end
    end

    local servsubleft = function(server)
        -- check if the client has subscriptions left on this server
        if servers[server].all[client] then
            return true
        end
        local evs = servers[server].events
        for ev, _ in pairs(evs) do
            if ev[client] then
                return true
            end
        end
        return false
    end

    local ct = clients[client]  -- client table
    if ct then
        -- this client is registered
        if server then
            -- unsubscribe from a specific server
            unsubserv(server)
            if not servsubleft(server) then
                -- no subscriptions left on this server, remove server from client list
                ct[server] = nil
            end
        else
            -- unsubscribe from all servers
            for _, svr in pairs(clients[client]) do
                unsubserv(svr)
                if not servsubleft(server) then
                    -- no subscriptions left on this server, remove server from client list
                    ct[svr] = nil
                end
            end
        end
        -- check if the client has any subscriptions left, remove if not
        if next(ct) == nil then
            clients[client] = nil
        end
    end
end


-------------------------------------------------------------------------------
-- local function to do the actual dispatching and yielding
local disp = function(client, handler, ...)
    local param = {...}
    coxpcall(function() handler(client, unpack(param)) end, _missingerrorhandler)
    -- yield after each handler
    coroutine.yield(true)   -- signal there is work to be done
end

-------------------------------------------------------------------------------
-- dispatches an event from a server
-- @param server a unique key to identify the specific server
-- @param event string
-- @param ... other arguments to be passed on as arguments to the eventhandler
-- @return boolean, true if event dispatching completed, false if only queued (events
-- dispatched from the dispatcher thread itself will return true, from other threads
-- will return false).
function dispatch(server, event, ...)
    assert(isstarted, "Dispatcher hasn't been started yet, call 'start()' first to setup the dispatcher thread, before dispatching events")

    -- we're up and running, so check what's coming in
    assert(event, "Event parameter cannot be nil")
    assert(server, "Server parameter cannot be nil")
    local stable = servers[server]
    assert(stable, "Server not found")
    local etable = stable.events[event]
    assert(etable, "Event not found for this server")

    -- check am I on my own thread?
    if coroutine.running() ~= mythread then
        -- called from another thread, store it in the queue for future processing
        table.insert(eventqueue, { server = server, event = event, args = {...} })
        return false    -- signal event wasn't dealt with just yet
    else
        -- on my own thread, so called recursively (chain of events)
        -- call all event handlers
        for cl, hdlr in pairs(stable.all) do
            disp(cl, hdlr, ...)
        end
        -- call event specific handlers
        for cl, hdlr in pairs(etable) do
            disp(cl, hdlr, ...)
        end
        return true -- signal event has been completed
    end
end

-------------------------------------------------------------------------------
-- Main loop for dispatcher thread
local function loop()
    while not isexiting do
        if #eventqueue > 0 then
            -- get work from the queue and handle it
            local s = eventqueue[1].server
            local e = eventqueue[1].event
            local a = eventqueue[1].args
            local stable = servers[s]
            local etable = stable.events[e]
            -- call all event handlers
            for cl, hdlr in pairs(stable.all) do
                disp(cl, hdlr, unpack(a))
            end
            -- call event specific handlers
            for cl, hdlr in pairs(etable) do
                disp(cl, hdlr, unpack(a))
            end
            table.remove(eventqueue,1)
        else
            coroutine.yield(false)   -- false; no more work to do
        end
    end
    -- exit and terminate dispatcher thread
    isstarted = false
    isexiting = nil
    mythread = nil
end
-------------------------------------------------------------------------------
-- Starts the dispatcher. If it already runs, just returns the existing thread.
-- @return thread on which the dispatcher has been started
function start()
    -- setup my own thread here, if not running already
    if not mythread then
        isstarted = true
        local t = coroutine.create(loop)
        mythread = t
    end
    return mythread
end

-------------------------------------------------------------------------------
-- Stops the dispatcher. Blocks execution until all events are done, must be called from a thread
-- other than the dispatcher thread.
-- @param cancelqueue if true, the incoming queue will not be dealt with, but will be abandoned.
function stop(cancelqueue)
    if isstarted then
        assert (coroutine.running() ~= mythread, "Cannot be called from the dispatchers own thread")
        -- rundown queue if requested
        if cancelqueue == true then
            while #eventqueue>0 do
                coroutine.resume(mythread)
            end
        end
        -- exit thread
        isexiting = true
        while coroutine.status(mythread) ~= "dead" do
            coroutine.resume(mythread)
        end
    end
end
