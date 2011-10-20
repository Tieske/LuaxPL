--[[

(c) Copyright 2011 Richard A Fox Jr., Thijs Schreijer

This file is part of xPLGirder.

xPLGirder is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

xPLGirder is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with xPLGirder.  If not, see <http://www.gnu.org/licenses/>.

See the accompanying ReadMe.txt file for additional information.

]]--

local Version = '0.1.3'
local PluginID = 10124
local PluginName = 'xPLGirder'
local Global = 'xPLGirder'
local Description = 'xPLGirder'
local ConfigFile = 'xPLGirder.cfg'
local ProviderName = 'xPLGirder'
local UDP_SOCKET = 50000
local XPL_PORT = 3865
local INTERVAL = 5
local handlerdir = 'luascript\\xPLHandlers'
local handlerfiles = '*.lua'


local function trim (s)
  return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- xPL parser. returns a table.
local function xPLParser(msg)
	local x = string.Split(msg, "\n")
	local xPLMsg = {}
	local Line
	local State=1

	xPLMsg.body = {}
	xPLMsg.type = x[1]

	for i in ipairs(x) do

		Line = trim(x[i])

		-- Reading the Body.
		if ( State == 5) then
			if ( Line=='}' ) then
				State = 0
			else
				local t = string.Split( Line, "=")
				if ( table.getn(t)==2 ) then
					-- 2 elements found, so key and a value
					table.insert(xPLMsg.body, { key = t[1], value = t[2] })
				elseif ( table.getn(t)==1 ) then
					-- 1 element found, so key consider it key only
					table.insert(xPLMsg.body, { key = t[1], value = "" })
				else
					-- 3 or more elements found, so value contains '=' character
					table.insert(xPLMsg.body, { key = t[1], value = string.sub(Line, string.len(t[1]) + 2) })
				end
			end
		end

		-- Waiting for Body
		if ( State == 4 ) then
			if ( Line=='{' ) then
				State = 5
			end
		end

		-- Waiting for Schema
		if ( State == 3 ) then

			--if ( Line ~= '' ) and ( Line~='\n') and ( Line~='\r\n' ) and ( Line~='\n\r' ) then
			if ( Line ~= '' ) and ( string.len(Line)>1) then
				xPLMsg.schema = Line
				State = 4
			end

		end

		-- Header.
		if ( State == 2) then
			if ( Line=='}' ) then
				State = 3
			else
				local t = string.Split( Line, "=")
				if ( table.getn(t)==2 ) then
					xPLMsg[t[1]] = t[2]
				end
			end
		end

		-- Idle
		if ( State == 1 ) then
			if ( Line=='{' ) then
				State = 2
			end
		end
	end
    if not xPLMsg.type then
        return
    end

    if not xPLMsg.source then
        return
    end

    return xPLMsg
end

local GetRegKey = function(name, default)
	local key = "HKLM"
	local path = [[Software\xPL\]]
	local reg, err, val
	local result = default

	reg, err = win.CreateRegistry(key, path)
	if (reg ~= nil) then
		val = reg:Read(name)
		if (val ~= nil) then
			result = val
		end
		reg:CloseKey()
	end
	return result
end

local CleanupIP = function(ips)
	local t = string.Split(ips, ",")
	for k,v in ipairs(t) do
		local i = string.Split(v, ".")
		for k1,v1 in ipairs(i) do
			i[k1] = v1 * 1
		end
		t[k] = table.concat(i, ".")
	end
	return table.concat(t, ",")
end


local DefaultSettings = {
}

local Events = table.makeset ( {
    'Add',
    'Remove',
    'Update',
    'xPLMessage',
} )

local socket = require('socket')

local Address, HostName = win.GetIPInfo(0)

local xPLListenOnAddress = GetRegKey("ListenOnAddress", "ANY_LOCAL")
if xPLListenOnAddress ~= "ANY_LOCAL" then
	xPLListenOnAddress = CleanupIP(xPLListenOnAddress)
end

local xPLListenToAddresses = GetRegKey("ListenToAddresses", "ANY_LOCAL")
if xPLListenToAddresses ~= "ANY_LOCAL" then
	if xPLListenToAddresses ~= "ANY" then
		xPLListenToAddresses = CleanupIP(xPLListenOnAddress)
		-- remove '.' characters because they are magical lua patterns
		xPLListenToAddresses = string.gsub(xPLListenToAddresses, "%.", "_")
	end
end

local xPLBroadcastAddress = GetRegKey("BroadcastAddress", "255.255.255.255")

if xPLListenOnAddress ~= "ANY_LOCAL" then
	Address = xPLListenOnAddress
end

require 'Components.Classes.Provider'

require 'Classes.DelayedExecutionDispatcher'

local Super = require 'Components.Classes.Provider'

local xPLGirder = Super:New ( {

    ID = PluginID,
    Name = PluginName,
    Description = Description,
    Global = Global,
    Version = Version,
    ConfigFile = ConfigFile,
    ProviderName = ProviderName,
    Source = 'tieske-girder.'..string.gsub (string.lower(HostName), "%p", ""),
    Address = Address,
	HostName = HostName,
	xPLListenOnAddress = xPLListenOnAddress,
	xPLListenToAddresses = xPLListenToAddresses,
	xPLBroadcastAddress = xPLBroadcastAddress,
    Port = UDP_SOCKET,

    xPLDevices = {},
	hbeatCount = 0,	-- counts own heartbeats send until one is received

    Initialize = function (self)
        self:AddEvents (Events)
        self:AddToDefaultSettings (DefaultSettings)

        return Super.Initialize (self)
    end,


    StartProvider = function (self)
        --Super.StartProvider (self)
    end,


    Enable = function (self)
        self:SetMode ('Startup')

		self:LoadHandlers()

        self:StartReceiver()

        self:StartHBTimer()

        self:SendHeartbeat()

        return Super.Enable (self)
    end,


    Disable = function (self)
        self:SetMode ('Offline')

        self:ShutdownReciever()

		self:RemoveAllHandlers()

        return Super.Disable (self)
    end,


    StartHBTimer = function (self)
        self.HeartbeatTimer = gir.CreateTimer (nil,function () self:SendHeartbeat () end,nil,true)
        self.HeartbeatTimer:Arm (3000)
        return true
    end,


    SendHeartbeat = function (self)
		if self.hbeatCount ~= 0 then
			-- a previous hbeat send was not received back... unstable connection!
			gir.LogMessage(self.Name, 'No connection to xPL hub. Retrying...', 1)
            if self.Mode == 'Online' then
				self:SetMode ('Startup')
				if self.HeartbeatTimer ~= nil then
					self.HeartbeatTimer:Cancel()
					self.HeartbeatTimer:Arm (3000)
				end
			end
		end
		self.hbeatCount = self.hbeatCount + 1
        local hb = "xpl-stat\n{\nhop=1\nsource=%s\ntarget=*\n}\nhbeat.app\n{\ninterval=%s\nport=%s\nremote-ip=%s\nversion=%s\n}\n"
        local msg = string.format(hb, self.Source, INTERVAL, self.Port, self.Address, self.Version)
        self:SendMessage(msg)
    end,


    SendDiscovery = function (self)
        local hb = "xpl-cmnd\n{\nhop=1\nsource=%s\ntarget=*\n}\nhbeat.request\n{\ncommand=request\n}\n"
        local msg = string.format(hb, self.Source)
        self:SendMessage(msg)
    end,


    ShutdownReciever = function (self)
        local hb = "xpl-stat\n{\nhop=1\nsource=%s\ntarget=*\n}\nhbeat.end\n{\ninterval=%s\nport=%s\nremote-ip=%s\n}\n"
        local msg = string.format(hb, self.Source, INTERVAL, self.Port, self.Address)
        self:SendMessage(msg)
		if self.HeartbeatTimer ~= nil then
			self.HeartbeatTimer:Cancel()
			self.HeartbeatTimer = nil
		end
        self.Receiver:close()
    end,


    StartReceiver = function (self)
        self.Receiver = socket.udp()
    	if not self.Receiver then
			gir.LogMessage(self.Name, 'Could not create UDP socket.', 2)
    		return false
    	end
    	self.Receiver:settimeout(1)
    	local status, err = self.Receiver:setsockname('*', self.Port)

    	while not status do
            self.Port = self.Port + 1
            self.Receiver:close()
            self.Receiver = socket.udp()
            self.Receiver:settimeout(1)
            self.Receiver:setoption("broadcast", true)
    	    status, err = self.Receiver:setsockname('*', self.Port)
    	    --print (status,err)
    	end

        local updaterunning = self.AsyncReceiverID and self.AsyncReceiverID:isthreadrunning ()
        if updaterunning or gir.IsLuaExiting () then  -- leave if we are already running or lua is shutting down
            return
        end
        self.AsyncReceiverID = thread.newthread (self.AsyncReceiver,{self,1,2})
    end,


    AsyncReceiver = function (self)
    	while not gir.IsLuaExiting() do
    		local data, err = self.Receiver:receivefrom()

    		if not data and err ~= 'timeout' then
    			-- if any error occurs end the thread, unless the error is 'timeout'
    			return false
    		end

    		if data then
				local fromip = string.gsub(err, "%.", "_") -- if data was returned, 2nd argument contains the Sender IP
				if self.xPLListenToAddresses ~= "ANY" then
					-- we need to check the from address
					if self.xPLListenToAddresses == "ANY_LOCAL" then
						-- the first three elements in our address must match
						local a = string.Split(self.Address, ".")
						a[4] = 255
						a = table.concat(a, "_")
						fromip = string.Split(fromip, "_")
						fromip[4] = 255
						fromip = table.concat(fromip, "_")
						if a ~= fromip then
							data = nil
							print ("Message from " .. err .. " not approved.")
						end
					else
						-- check if sender address is in our list, clear data if not
						if not string.find(self.xPLListenToAddresses, fromip) then
							data = nil
							print ("Message from " .. err .. " not approved.")
						end
					end
				end
				local msg = nil
				if data then msg = xPLParser(data) end
    			if msg then
                    --if not self:ProcessHeartbeat(msg) then
                        self:ProcessReceivedMessage (msg)
                    --end
                end
    		end
    	end
    end,


    ProcessReceivedMessage = function (self, data)
        if not self:ProcessHeartbeat(data) then
			local forus = data.target == '*' or data.target == self.Source
			if forus then
				if not self:ProcessMessageHandlers ( data ) then
					-- returned false, so standard xPL event should not be supressed
					local dotAddr = string.gsub(data.source, "%-", ".", 1)  -- replace address '-'  by '.'
					local eventstring = string.format("%s.%s.%s", data.type, dotAddr, data.schema)
					local pld1 = pickle(data)
					gir.TriggerEvent(eventstring, self.ID, pld1)
				end
			end
		end
    end,

	Handlers = {}, 		-- emtpy table with specific message handlers

	FilterMatch = function (self, msg, filter)
		-- filter = [msgtype].[vendor].[device].[instance].[class].[type]
		-- wildcards can be used; '*'
		-- return true if the message matches the filter

		local addr = string.gsub(msg.source, "%-", ".", 1)	-- replace address '-' with '.'
		local mflt = string.format("%s.%s.%s", msg.type, addr, msg.schema)

		-- split filter elements
		local flst = string.Split( filter, '.' )
		local mlst = string.Split( mflt, '.' )

		for i = 1,6 do
			-- check wildcard first
			if flst[i] ~= '*' then
				-- isn't a wildcard, check equality
				if flst[i] ~= mlst[i] then
					-- not equal, so match failed
					return false
				end
			end
		end
		-- we've got a match
		return true
	end,

	ProcessMessageHandlers = function (self, msg)
		local result = false
		local s, r
		-- loop through all handlers
		for ID, handler in pairs(self.Handlers) do
			-- loop through all filters
			for k, v in pairs(handler.Filters) do
				if self:FilterMatch ( msg, v ) then
					-- filter matches, go call handler, protected, s = success true/false, r = result
					s,r = pcall(handler.MessageHandler, handler, msg, v)
					if s then
						if r then
							result = true
						end
					else
						-- error was returned from handler
						print("xPLHandler " .. handler.ID .. " had a lua error;" .. r)
						print("while handling the following xPL message;")
						table.print(msg)
						gir.LogMessage(self.Name, handler.ID .. ' failed while processing a message, see lua console', 2)
					end
					-- call each handler max 1, so exit 'filter' loop, continue with next handler
					break
				end
			end
		end
		return result
	end,

	RegisterHandler = function (self, handler)
		self:RemoveHandler(handler.ID)
		-- setup defaults and ID
		local newID = handler.ID
		handler.Filters = handler.Filters or {}
		if table.IsEmpty( handler.Filters ) then
			handler.Filters = {'*.*.*.*.*.*'}	-- default filter; all messages
		end
		-- Go add to Handler list and initialize
		self.Handlers[newID] = handler
		handler:Initialize()
	end,

	RemoveHandler = function (self, ID)
		if ID ~= nil then
			local h = self.Handlers[ID]
			if h ~= nil then
				h:ShutDown()
				self.Handlers[ID] = nil
			end
		end
	end,

	RemoveAllHandlers = function (self)
		-- shutdown all handlers, and empty table
		for ID, handler in pairs(self.Handlers) do
			handler:ShutDown()
		end
		self.Handlers = {}
	end,

    LoadHandlers = function (self)
        --self:Log (3,'Loading xPL handlers')
        local dir = win.GetDirectory('GIRDERDIR').."\\"..handlerdir

        for fa in win.Files (dir..'\\'..handlerfiles) do
            if math.band (fa.FileAttributes, win.FILE_ATTRIBUTE_DIRECTORY) == 0 then
				local handler = self:ReadHandlerFile (dir..'\\'..fa.FileName)
				if handler then
					self:RegisterHandler (handler)
				end
            end
        end
    end,

    ReadHandlerFile = function (self, file)
        --self:Log (3,'Reading handler ',file)

        local f,err = loadfile (file)
        if not f then
			gir.LogMessage(self.Name, 'Error reading handler file ' .. file, 2)
            return false
        end

        local res,handler = xpcall (f, debug.traceback)

        if not res or type (handler) ~= 'table' then
			gir.LogMessage(self.Name, 'Error running handler file ' .. file, 2)
            return false
        end

        if not res then
			gir.LogMessage(self.Name, 'Error running handler file ' .. file, 2)
            return false
        end

		gir.LogMessage(self.Name, 'Loaded handler ' .. handler.ID, 3)
        return handler
    end,


    ProcessHeartbeat = function (self, data)
        if data.type == 'xpl-stat' and data.schema == "hbeat.app" then
            local source = data.source
            if self.Mode == 'Startup' then
                if source == self.Source then
					self.hbeatCount = 0		-- reset counter
					self:SetMode ('Online')
                    self.HeartbeatTimer:Cancel()
                    self.HeartbeatTimer:Arm (INTERVAL * 60000)
                    self:SendDiscovery()
                end
            end
            if self.Mode == 'Online' then
                if source == self.Source then
					self.hbeatCount = 0		-- reset counter
                end
                if not table.findvalue(self.xPLDevices, source) then
                    --print ('Adding source',source)
                    table.insert(self.xPLDevices, source)
                else
                    --print ('Source',source,'already exists')
                end
            end
            return true     -- msg was a heartbeat
        elseif data.type == 'xpl-cmnd' and data.schema == "hbeat.request" then
            self:SendHeartbeat()
            return true     -- msg was a heartbeat
        end
        return false        -- msg was not a heartbeat
    end,

	SetMode = function (self, m)
		self.Mode = m
		gir.TriggerEvent('Status changed to: ' .. self.Mode, self.ID, self.Mode)
	end,

    GetSourceDevices = function (self)
        return table.copy(self.xPLDevices)
    end,


    GetSource = function (self)
        return self.Source
    end,


    SendMessage = function (self, msg)
		if not msg then
			error ("Must provide a message string, call as; SendMessage( self, MsgString )", 2)
		end
		if type(msg) == "string" then
			self.Receiver:sendto(msg,self.xPLBroadcastAddress, XPL_PORT)
		elseif type(msg) == "table" then
----------------------------
-- to be implemented here --
----------------------------
			table.print (msg)
			error ("sending objects is not implemented yet!")
		end
    end,


    Close = function (self)
        self:ShutdownReciever()
        _ = self.HeartbeatTimer and self.HeartbeatTimer:Destroy ()

        Super.Close (self)
    end,

} )


return xPLGirder

