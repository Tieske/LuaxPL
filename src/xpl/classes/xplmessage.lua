---------------------------------------------------------------------
-- The object class for xPL messages.
-- It has all the regular message properties (some depending on whether it was parsed/received
-- or created). several methods and an iterator are available to manipulate the key-value list.
-- <br/>No global will be created, it just returns the xplmessage class. The main
-- xPL module will create a global <code>xpl.classes.xplmessage</code> to access it.
-- @class module
-- @name xplmessage
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, LuaxPL framework.


local k -- make local, to trick luadoc
-----------------------------------------------------------------------------------------
-- Internal representation of a key-value pair. A table with 2 keys, key and value.
-- @class table
-- @name key-value pair
-- @field key the <code>key</code> of the key-value pair
-- @field value the <code>value</code> of the key-value pair
k = {}
k = nil

-----------------------------------------------------------------------------------------
-- Members of the xplmessage object
-- @class table
-- @name xplmessage fields/properties
-- @field type the xpl message type; <code>"xpl-cmnd", "xpl-trig", "xpl-stat"</code>
-- @field from origin of message; <code>"[IP address]:[port]"</code> (when the internal
-- LuaxPL hub is used), <code>"EXTERNAL_HUB"</code> or <code>"CREATED"</code> (when the
-- message was locally created and not received from the network)
-- @field hop hop count
-- @field source source address of the message
-- @field sourcevendor vendor part of source address (only available if parsed)
-- @field sourcedevice device part of source address (only available if parsed)
-- @field sourceinstance instance part of source address (only available if parsed)
-- @field target target address of the message
-- @field targetvendor vendor part of source address (only available if parsed, '*' if target address is '*')
-- @field targetdevice device part of source address (only available if parsed, '*' if target address is '*')
-- @field targetinstance instance part of source address (only available if parsed, '*' if target address is '*')
-- @field schema message schema of the message
-- @field schemaclass class part of the message schema (only available if parsed)
-- @field schematype type part of the message schema (only available if parsed)
-- @field# kvp list of key value pairs, where each pair is defined as;
-- <code>kvp[i] = { key = 'key value',
--            value = 'value value'}</code>
-- See <a href="xplmessage.html#msg:eachkvp"><code>msg:eachkvp()</code></a> for an iterator.
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
-- subclassing the xplmessage object into a new class.
function msg:initialize()
	self.kvp = {}				-- list to store key-value pairs, each list item is a table with 2 keys; "key" and "value"
end

------------------------------------------
-- Turn a message string into a message object.
-- if called as a method, the parsed message is loaded into the existing object. If called as a
-- function on the super class, a new message object will be created.
-- @param msgstring the string containing the message to be parsed
-- @usage# -- load a parsed message into the object
-- local msg, remainder = xpl.classes.xplmessage:new({})
-- msg, remainder = msg:parse(messagestring)
-- &nbsp
-- -- parse directly to a new message
-- local msg, remainder = xpl.classes.xplmessage.parse(messagestring)
-- @return parsed message object
-- @return remainder of input string (characters positioned after the parsed message), or <code>nil</code> if there is no remainder
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
-- @return key-value pair inserted (table with 2 keys; <code>key</code> and <code>value</code>)
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
-- @usage# for key, value, i in msg:eachkvp() do
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
-- get a value from the message body by key
-- @param key either the <code>key</code> or the <code>index</code> of the key-value pair sought
-- @param occurence optional, if a <code>key</code> is specified, the occurence to return if
-- there are duplicates (default 1), will be ignored if an <code>index</code> was provided
-- @return value (string) as set in the key-value pair, or <code>nil</code> if not found
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
-- @return key (string) if found or <code>nil</code> otherwise
function msg:getkey(index)
    assert(type(index) == "number", "illegal 'key', expected number, got " .. type(index))
    local kvp = self.kvp[index]
    if not kvp then return nil end	-- index not found, return nil
    return kvp.key	-- success, return key found
end

------------------------------------------
-- sets value of a key-value pair in the message body.
-- @param key either the <code>key</code> or <code>index</code> of the key-value pair whose value to update.
-- If a key, then the 1st occurrence will be updated.
-- @param value the value to set for the specified key/index
-- @return key-value pair updated (table with 2 keys; <code>key</code> and
-- <code>value</code>), or <code>nil</code> + error if the key or index wasn't found
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
-- @param key the <code>key</code> to be sought in the mesage body
-- @param occurence (optional) in case of duplicate keys the occurence can be specified (default 1)
-- @return <code>index</code> of the <code>key</code> (at mentioned occurence) in the message body or <code>nil</code> if not found
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
-- @usage# -- Create a new message
-- local msg = xpl.classes.xplmessage:new({})
-- &nbsp
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
-- @return <code>true</code> if succesfull, <code>nil</code> + error otherwise
function msg:send()
    -- send it
    local success, err = xpl.send(tostring(self))
    if not success then
        print ("xPLMessage send error; ", err)
    end
    return success, err
end

------------------------------------------
-- matches the message against an xplfilter
-- @param filter <a href="xplfilters.html">xplfilters object</a> (contains list of filters). In case
-- the filter is <code>nil</code> it will return <code>true</code> (default xpl behaviour with absent filters).
-- @return <code>true</code> or <code>false</code> based upon matching the filter or not.
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
