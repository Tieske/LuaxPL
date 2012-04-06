
---------------------------------------------------------------------
-- The filter object for xPL devices. It maintains a list of filters for
-- matching incoming messages.
-- <br/>No global will be created, it just returns the filter class. The main
-- xPL module will create a global <code>xpl.classes.xplfilters</code> to access it.<br/>
-- <br/>An xpl filter is a set of xpl message elements; <code>[msgtype].[vendor].[device].[instance].[schema-class].[schema-type]</code>
-- For each element a '<code>*</code>' can be used as a wildcard. Only arriving messages that
-- match at least 1 filter entry will be dealt with by an xpl device.<br/>
-- <br/>
-- Example (assuming <code>self</code> is an <code>xpldevice</code> object) <code><br/>
--        self.filter = xpl.classes.xplfilters:new({})<br/>
--        self.filter:add("xpl-cmnd.*.*.*.homeeasy.basic")<br/>
--        self.filter:add("xpl-cmnd.*.*.*.x10.*")<br/>
-- </code>
-- @class module
-- @name xplfilters
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, LuaxPL framework.

local flt = xpl.classes.base:subclass({
    ------------------------------------------------------------------------------------------
	-- Members of the filter object
    -- @class table
    -- @name xplfilter fields/properties
    -- @field list Table to store the individual filter entries, each filter-table in the
    -- list is keyed by its full filter string.
	list = nil,
})


------------------------------------------------------------------------------------------
-- splits a filter string into a filter table.
-- A '-' between vendor and device is accepted. It can be called as a function or as a method, either way
-- works (see example below).
-- @param flt Filter (string) as <code>[msgtype].[vendor].[device].[instance].[class].[type]</code>
-- @return a filter table with 6 indices for each filter element, and the <code>filter</code> key
-- with the full filter string value
-- @usage# -- create a new filter object
-- local flt = xpl.classes.xplfilter()
-- -- call as a function
-- local f = flt.split("xpl-cmnd.vendor.device.instance.class.type")
-- -- call as a method
-- local f = flt:split("xpl-cmnd.vendor.device.instance.class.type")
-- @see filter-table
function flt:split(flt)
    local flt = flt or self	-- allow both function calls and method calls
    assert(type(flt) == "string", "failed to split filter, string expected got " .. type(flt))
    local r = { string.match(flt, xpl.const.CAP_FILTER) }
    assert( #r == 6, "unable to split filter '" .. flt .. "'.")
    r.filter = table.concat(r, ".")
    return r
end

------------------------------------------------------------------------------------------
-- Add a filter entry to the filter list. Duplicates will be silently dismissed (no error).
-- @param flt filter to add, either a filter string or a filter table
-- @return filter table added
-- @see filter-table
function flt:add(flt)
    self.list = self.list or {}
    if type(flt) == "string" then
        flt = self:split(flt)
    end
    assert(type(flt) == "table", "cannot add filter, string or table expected, got " .. type (flt))
    if not flt.filter then
        flt.filter = string.concat(flt, ".")
    end
    if not self.list[flt.filter] then -- only add if not in the list already
        self.list[flt.filter] = flt
    end
    return self.list[flt.filter]
end

------------------------------------------------------------------------------------------
-- Remove filter from list
-- @param flt filter to remove, either a filter string or a filter table. If it doesn't exist no error will be thrown.
-- @return <code>true</code>
function flt:remove(flt)
    self.list = self.list or {}
    if type(flt) == "table" then
        if not flt.filter then
            flt.filter = table.concat(flt, ".")
        end
        flt = flt.filter
    end
    assert(type(flt) == "string", "cannot remove filter, string or table expected, got " .. type (flt))
    self.list[flt] = nil
    return true
end

------------------------------------------------------------------------------------------
-- Checks if a filter matches any of the filters in the list.
-- Wildcards are allowed both in the list (obvious), but also in the filter being matched.
-- @param flt filter to match (either a string or a table)
-- @return <code>true</code> if the filter matches an entry in the list, <code>false</code>
-- otherwise. If the filter object does not contain any filters it will <code>true</code>
-- (default xpl behaviour with absent filters).
function flt:match(flt)
    self.list = self.list or {}
    if type(flt) == "string" then
        flt = self:split(flt)
    end
    assert(type(flt) == "table", "cannot match filter, string or table expected, got " .. type (flt))
    local match = true
    for _ , filter in pairs(self.list) do
        match = true
        for n = 1,6 do
            if flt[n] == "*" or filter[n]=="*" or flt[n]==filter[n] then
                -- matches
            else
                -- no match
                match = false
                break	-- exit 1-6 elements loop as it already failed
            end
        end
        if match then break end	-- exit filters loop, we've got a match already
    end
    return match
end

local f -- local to trick luadoc
------------------------------------------------------------------------------------------
-- Internal representation of a filter entry.
-- @class table
-- @name filter-table
-- @field filter the full filter string formatted as <code>[msgtype].[vendor].[device].[instance].[schema-class].[schema-type]</code>
-- @field 1 value for the <code>msgtype</code>
-- @field 2 value for the <code>source address vendor id</code>
-- @field 3 value for the <code>source address device id</code>
-- @field 4 value for the <code>source address instance id</code>
-- @field 5 value for the <code>schema class</code>
-- @field 6 value for the <code>schema type</code>
f = {}
f = nil

-- run tests
if xpl.settings._DEBUG then
	require ("table_ext")

	print("Testing xplfilter class")
	local filters = flt:new({})	-- create instance

	-- test split (both calling as function and as method
	local f = "xpl-cmnd.tieske.somedev.inst.schema.class"
	local fs = filters:split(f)
	assert (fs.filter == f, "filter value in filter table not set properly")
	assert (#fs == 6, "too many/little items returned")
	assert (fs[1] == "xpl-cmnd", "message type is not correct ")
	assert (fs[2] == "tieske", "vendor is not correct")
	assert (fs[3] == "somedev", "device type is not correct")
	assert (fs[4] == "inst", "instance type is not correct")
	assert (fs[5] == "schema", "schema type is not correct")
	assert (fs[6] == "class", "class type is not correct")
	print ("   calling split function as method succeeded")

	local fs = filters.split(f)
	assert (fs.filter == f, "filter value in filter table not set properly")
	assert (#fs == 6, "too many/little items returned")
	assert (fs[1] == "xpl-cmnd", "message type is not correct ")
	assert (fs[2] == "tieske", "vendor is not correct")
	assert (fs[3] == "somedev", "device type is not correct")
	assert (fs[4] == "inst", "instance type is not correct")
	assert (fs[5] == "schema", "schema type is not correct")
	assert (fs[6] == "class", "class type is not correct")
	print ("   calling split function as function succeeded")

	local s = pcall(filters.split, 123)
	assert( not s, "error expected because of a number")
	local s = pcall(filters.split, {})
	assert( not s, "error expected because of a table")
	local s = pcall(filters.split, "*.to.little.items")
	assert( not s, "error expected because there are to little items")
	print ("   calling split function with errors succeeded")

	-- test add
	filters:add(f)
	local f = "xpl-cmnd.*.*.*.*.class"
	filters:add(f)
	assert(filters.list[f][2] == "*", "asterisk expected")
	assert(filters.list[f][6] == "class", "'class' expected")
	assert(filters.list[f].filter == f, "filter doesn't match")
	local f = "*.tieske.*.*.*.*"
	filters:add(f)
	assert(filters.list[f][2] == "tieske", "'tieske' expected")
	assert(filters.list[f][6] == "*", "'*' expected")
	assert(filters.list[f].filter == f, "filter doesn't match")
	local cnt = table.size(filters.list)
	filters:add(f)
	assert(cnt == table.size(filters.list), "same filter should not be added twice")
	print ("   calling add method succeeded")

	local s = pcall(filters.add, filters, 123)
	assert( not s, "error expected because of a number")
	local s = pcall(filters.add, filters, nil)
	assert( not s, "error expected because of a nil")
	print ("   calling add method with errors succeeded")

	-- test remove
	local f = "xpl-cmnd.*.*.*.*.class"
	assert(filters.list[f] ~= nil, "filter should be here, was added previously")
	filters:remove(f)
	assert(filters.list[f] == nil, "filter should have been removed")
	local f = "*.tieske.*.*.*.*"
	filters:remove(f)
	assert(filters.list[f] == nil, "filter should have been removed")
	assert(#filters.list == 0, "All filters should have been removed")
	print ("   calling remove method succeeded")

	local s = pcall(filters.remove, filters, 123)
	assert( not s, "error expected because of a number")
	local s = pcall(filters.remove, filters, nil)
	assert( not s, "error expected because of a nil")
	print ("   calling remove method with errors succeeded")

	-- test match
	filters:add("xpl-cmnd.*.*.*.*.class")
	filters:add("*.tieske.*.*.*.*")
	assert(filters:match("xpl-trig.tieske.device.inst.log.basic") == true, "filter should have matched")
	assert(filters:match("xpl-cmnd.tieske.device.inst.log.class") == true, "filter should have matched")
	assert(filters:match("xpl-trig.other.device.inst.log.basic") == false, "filter should have failed")
	print ("   calling match method succeeded")

	local s = pcall(filters.match, filters, 123)
	assert( not s, "error expected because of a number")
	local s = pcall(filters.match, filters, nil)
	assert( not s, "error expected because of a nil")
	print ("   calling match method with errors succeeded")


	print("Testing xplfilter class succeeded")
	print()
end

return flt
