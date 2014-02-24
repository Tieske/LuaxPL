---------------------------------------------------------------------
-- The object class for xPL messages.
-- 
-- It has all the regular message properties (some depending on whether it was parsed/received
-- or created). several methods and an iterator are available to manipulate the key-value list.
--
-- The main xPL module will store it as `xpl.classes.xplmessage`.
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, LuaxPL framework.
-- @classmod xplmessage

local xpl = require("xpl")

-----------------------------------------------------------------------------------------
-- Internal representation of a key-value pair. A table with 2 keys, key and value.
-- @class table
-- @name key-value
-- @field key the `key` of the key-value pair
-- @field value the `value` of the key-value pair

-----------------------------------------------------------------------------------------
-- the xpl message type. Any of `xpl-cmnd`, `xpl-trig`, `xpl-stat`.
-- @field type (string)

-----------------------------------------------------------------------------------------
-- Origin of message. Will be `[IP address]:[port]` (when the internal LuaxPL hub is used), 
-- `EXTERNAL_HUB` or `CREATED` (when the message was locally created and not received from the network)
-- @field from (string)

-----------------------------------------------------------------------------------------
-- Hop count
-- @field hop (number)

-----------------------------------------------------------------------------------------
-- Source address of the message
-- @field source (string)

-----------------------------------------------------------------------------------------
-- Vendor part of source address (only available if parsed)
-- @field sourcevendor (string)

-----------------------------------------------------------------------------------------
-- Device part of source address (only available if parsed)
-- @field sourcedevice (string)

-----------------------------------------------------------------------------------------
-- Instance part of source address (only available if parsed)
-- @field sourceinstance (string)

-----------------------------------------------------------------------------------------
-- Target address of the message
-- @field target (string)

-----------------------------------------------------------------------------------------
-- Vendor part of source address (only available if parsed, `*` if target address is `*`)
-- @field targetvendor (string)

-----------------------------------------------------------------------------------------
-- Device part of source address (only available if parsed, `*` if target address is `*`)
-- @field targetdevice (string)

-----------------------------------------------------------------------------------------
-- Instance part of source address (only available if parsed, `*` if target address is `*`)
-- @field targetinstance (string)

-----------------------------------------------------------------------------------------
-- Message schema of the message
-- @field schema (string)

-----------------------------------------------------------------------------------------
-- Class part of the message schema (only available if parsed)
-- @field schemaclass (string)

-----------------------------------------------------------------------------------------
-- Type part of the message schema (only available if parsed)
-- @field schematype (string)

-----------------------------------------------------------------------------------------
-- List of key value pairs. Each pair is defined as; `kvp[i] = { key = 'key value', value = 'value value'}`
-- @field kvp (list) 

-----------------------------------------------------------------------------------------
local msg = xpl.classes.base:subclass({
	type = "xpl-cmnd",		-- message type
	hop = 1,				-- hop count
	source = "tieske-somedev.instance",			-- source address
	target = "*",			-- target address
	schema = "hbeat.basic",	-- message schema
    from = "CREATED",
})

-----------------------------------------------------------------------------------------
-- Initializes the xplmessage.
-- Will be called upon instantiation of an object and hence has little use other than when
-- subclassing the `xplmessage` object into a new class.
function msg:initialize()
	self.kvp = {}				-- list to store key-value pairs, each list item is a table with 2 keys; "key" and "value"
end

------------------------------------------
-- Turn a message string into an `xplmessage` object.
-- if called as a method, the parsed message is loaded into the existing object. If called as a
-- function on the super class, a new message object will be created.
-- @param msgstring the string containing the message to be parsed
-- @return parsed `xplmessage` object
-- @return remainder of input string (characters positioned after the parsed message), or `nil` if there is no remainder
-- @usage -- load a parsed message into the object
-- local msg, remainder = xpl.classes.xplmessage:new({})
-- msg, remainder = msg:parse(messagestring)
-- 
-- -- parse directly to a new message
-- local msg, remainder = xpl.classes.xplmessage.parse(messagestring)
function msg:parse(msgstring)
    if type(self) == "string" and msgstring == nil then
        -- not called on an object, but as a function, so create a new message object
        msgstring = self
        self = msg:new({})
    end
    if type(msgstring) ~= "string" then
        return nil, "Failed digesting string to xPL message, expected string got " .. type(msgstring)
    end
    -- digest header
    local tpe, hop, source, target, schema, body, remainder = string.match(msgstring, xpl.const.CAP_MESSAGE)
    if not tpe then
        return nil, "Failed to digest xPL message string, invalid message?"
    end
    -- digest details
    local sv, sd, si = string.match(source, xpl.const.CAP_ADDRESS)
    local tv, td, ti = "*", "*", "*"
    if target ~= "*" then
        tv, td, ti = string.match(target, xpl.const.CAP_ADDRESS)
    end
    local schemaclass, schematype = string.match(schema, xpl.const.CAP_SCHEMA)
    -- digest body
    local kvp = {}
    local cnt = 1
    while body do
        local key, value
        key, value, body = string.match(body, xpl.const.CAP_KEYVALUE)
        if not key then break end -- no more found, exit loop
        kvp[cnt] = {}
        kvp[cnt].key = key
        kvp[cnt].value = value
        cnt = cnt + 1
    end
    -- digesting complete, set properties
    self.type = tpe
    self.hop = hop
    self.source = source
    self.sourcevendor = sv
    self.sourcedevice = sd
    self.sourceinstance = si
    self.target = target
    self.targetvendor = tv
    self.targetdevice = td
    self.targetinstance = ti
    self.schema = schema
    self.schemaclass = schemaclass
    self.schematype = schematype
    self.kvp = kvp
    if remainder == "" then remainder = nil end
    return self, remainder
end

------------------------------------------
-- Add a key value pair to the message body.
-- @param key (string) the key (duplicates are allowed)
-- @param value the value to store
-- @return key-value pair inserted (table with 2 keys; `key` and `value`)
function msg:add(key, value)
    assert(type(key) == "string", "illegal 'key', expected string, got " .. type(key))
    assert(type(value) == "string" or type(value) == "number" or type(value) == "boolean", "illegal 'value', expected boolean, number or string, got " .. type(value))
    local kvp = {key = key, value = tostring(value)}
    table.insert(self.kvp,kvp)
    return kvp
end

------------------------------------------
-- Creates an iterator for the key-value pair list. The iterator will use the order as specified in the message.
-- @return iterator function
-- @usage for key, value, i in msg:eachkvp() do
--     print("KVP ", i, " has key = ", key, ", value = ", value)
-- end
function msg:eachkvp()
    local i = 0
    return function()
            i = i + 1
            local kvp = self.kvp[i]
            if not kvp then
                return nil
            else
                return kvp.key, kvp.value, i
            end
        end
end

------------------------------------------
-- Get a value from the message body by key.
-- @param key either the `key` or the `index` of the key-value pair sought
-- @param occurence optional, if a `key` is specified, the occurence to return if there are duplicates (default 1), will be ignored if an `index` was provided
-- @return value (string) as set in the key-value pair, or `nil` if not found
function msg:getvalue(key, occurence)
    assert(type(key) == "string" or type(key) == "number", "illegal 'key', expected string or number, got " .. type(key))
    occurence = occurence or 1
    assert(type(occurence) == "number", "illegal 'occurence', expected number, got " .. type(key))
    if type(key) == "string" then
        key = self:getindex(key, occurence)
        if not key then return nil end	-- key not found, return nil
    end
    local kvp = self.kvp[key]
    if not kvp then return nil end	-- index not found, return nil
    return kvp.value	-- success, return value found
end

------------------------------------------
-- Gets the key at a given index
-- @param index the index for the message body key-value pair whose key to return
-- @return key (string) if found or `nil` otherwise
function msg:getkey(index)
    assert(type(index) == "number", "illegal 'key', expected number, got " .. type(index))
    local kvp = self.kvp[index]
    if not kvp then return nil end	-- index not found, return nil
    return kvp.key	-- success, return key found
end

------------------------------------------
-- sets value of a key-value pair in the message body.
-- @param key either the `key` or `index` of the key-value pair whose value to update. If a key, then the 1st occurrence will be updated.
-- @param value the value to set for the specified key/index
-- @return key-value pair updated (table with 2 keys; `key` and `value`), or `nil` + error if the key or index wasn't found
function msg:setvalue(key, value)
    assert(type(key) == "string" or type(key) == "number", "illegal 'key', expected string or number, got " .. type(key))
    assert(type(value) == "string" or type(value) == "number" or type(value) == "boolean", "illegal 'value', expected boolean, number or string, got " .. type(value))
    local idx
    if type(key) == "string" then
        idx = self:getindex(key)
        if not idx then
            return nil, "xplmessage does not contain key; " .. tostring(key)
        end
    else
        idx = key
    end
    local kvp = self.kvp[idx]
    if not kvp then
        return nil, "xplmessage does not contain index; " .. tostring(key)
    end
    kvp.value = tostring(value)
    return kvp	-- success, return kvp found/modified
end

------------------------------------------
-- Gets the index of a key.
-- @param key the `key` to be sought in the mesage body
-- @param occurence (optional) in case of duplicate keys the occurence can be specified (default 1)
-- @return `index` of the `key` (at mentioned occurence) in the message body or `nil` if not found
function msg:getindex(key, occurence)
    assert(type(key) == "string", "illegal 'key', expected string, got " .. type(key))
    occurence = occurence or 1
    assert(type(occurence) == "number", "illegal 'occurence', expected number, got " .. type(key))
    local i = 1
    for idx, kvp in ipairs(self.kvp) do
        if kvp.key == key then
            if i == occurence then
                -- found it
                return idx
            end
            i = i + 1
        end
    end
    return nil		-- key was not found
end

------------------------------------------
-- Meta method to format the message as a string value for transmission
-- @return message as string that can be transmitted onto the xPL network
-- @usage -- Create a new message
-- local msg = xpl.classes.xplmessage:new({})
-- 
-- print(msg)  -- this will invoke the __tostring() meta method
function msg:__tostring()
    local body = ""
    -- format body with all key-value pairs
    for i, kvp in ipairs (self.kvp) do
        body = string.format(xpl.const.FMT_KEYVALUE, body, kvp.key, tostring(kvp.value))
    end
    -- format header and insert body
    local msg = string.format(xpl.const.FMT_MESSAGE, self.type, tostring(self.hop), self.source, self.target, self.schema, body)
    return msg
end

------------------------------------------
-- Transmits the message onto the xPL network
-- @return `true` if succesfull, `nil` + error otherwise
function msg:send()
    -- send it
    local success, err = xpl.send(tostring(self))
    if not success then
        print ("xPLMessage send error; ", err)
    end
    return success, err
end

------------------------------------------
-- Matches the message against an xplfilter
-- @param filter `xplfilters` object (contains list of filters). In case the filter is `nil` it will return `true` (default xpl behaviour with absent filters).
-- @return `true` or `false` based upon matching the filter or not.
function msg:matchfilter(filter)
    if not filter then return true end
    local result = filter:match(string.format("%s.%s.%s", self.type, self.source, self.schema))
    return result
end




-- run tests
if xpl.settings._DEBUG then
	require ("table_ext")

	print("Testing xplmessage class")
	local m = msg:new({})	-- create instance
	local kvp

	kvp = m:add("tieske","a value")
	assert (kvp.key == "tieske", "Unexpected key value")
	assert (kvp.value == "a value", "Unexpected value")
	assert (m:getvalue("tieske") == "a value", "Unexpected value; " .. m:getvalue("tieske"))
	assert (m:getvalue(1) == "a value", "Unexpected value; " .. m:getvalue(1))
	m:add("tieske","a value two")
	assert (m:getvalue("tieske") == "a value", "Unexpected value; " .. m:getvalue("tieske"))
	assert (m:getvalue("tieske", 2) == "a value two", "Unexpected value; " .. m:getvalue("tieske", 2))
	assert (m:getvalue(2) == "a value two", "Unexpected value; " .. m:getvalue(2))
	m:add("mykey","a value three")
	assert (m:getkey(1) == "tieske", "Unexpected value; " .. m:getkey(1))
	assert (m:getkey(3) == "mykey", "Unexpected value; " .. m:getkey(3))
	assert (not pcall (m.setvalue, m, "nonexist", "a value four") , "Expected an error")
	m:setvalue("tieske", "a value one")
	assert (m:getvalue(1) == "a value one", "Unexpected value; " .. m:getvalue(1))
	-- getindex has been tested implicitly
	print ("   Test to modify key-value pairs succeeded")
	m:send()
	print ("   Send test succeeded")


	print("   ===================================================")
	print("   TODO: implement test parse method")
	print("   TODO: implement test matchfilter method")
	print("   ===================================================")

	print("Testing xplmessage class succeeded")
	print()
end

return msg
