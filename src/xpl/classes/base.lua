-------------------------------------------------------------------------------------------------------
-- Allows for object creation.
-- Returns a single object. Call <code>object.make(tbl)</code> to turn a table into an object.
-- alternatively the <code>object</code> table can be subclassed directly;<br/>
-- <code>myObj = object:subclass({member = 'value'})</code>
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, LuaxPL framework.

local object = {}

-------------------------------------------------------------------------------------------------------
-- Creates an object from a table, a base class. This only need to be done for the very first base class
-- only, descedants or instances will automatically have the object properties.
-- Adds methods <code>new</code> and <code>subclass</code> to the supplied table to instantiate
-- and subclass the created objectclass. Property/field <code>super</code> is added as a reference to the
-- base class of the created object. Method <code>initialize(self)</code> will be called upon instantiation.
-- <ul><li><code>super:new(o)</code>; method to create an instance of <code>super</code> in table
-- <code>o</code>, whilst retaining the properties in <code>o</code></li>
-- <li><code>super:subclass(o)</code>; method to create a new class, which inherits from <code>super</code>
-- </li></ul>
-- NOTE: when calling methods on the superclass make sure to call them using function notation
-- (<code>super.method(self, param1, param2)</code>) and NOT method notation (<code>super:dosomething(param1,
-- param2)</code>), because in the latter case <code>self</code> will point to <code>super</code> and not
-- the instance called upon.
-- @param obj table to convert into an object
-- @param ... (not used, only for error checking)
-- @usage# local base = require("xpl.classes.base")
-- &nbsp
-- -- create my table
-- local myObject = {
--     data = "hello world",
-- &nbsp
--     print = function(self)
--         print(self.data)
--     end,
-- &nbsp
--     initialize = function(self)
--         -- upon initialization just print
--         self:print()
--     end
-- }
-- &nbsp
-- -- make it a class with single inheritance by subclassing
-- -- it from the base class. The 'initialize()' method will
-- -- NOT be called upon subclassing
-- myObject = base:subclass(myObject)
-- &nbsp
-- -- instantiate an object from the new class and
-- -- override field contents. This will call 'initialize()'
-- -- and print "my world".
-- local descendant = myObject:new({data = "my world"})
-- &nbsp
-- -- now override another method
-- function descendant:print()
--     -- convert data to uppercase
--     self.data = string.upper(self.data)
--     -- call ancestor method through 'super'. NOTE: you
--     -- must use 'function notation' for the call, 'method
--     -- notation' will not work.
--     self.super.print(self)
-- end
-- &nbsp
-- -- try the overriden method and print "MY WORLD"
-- descendant:print()

object.make = function(obj, ...)
    if #arg ~= 0 or type(obj) ~= 'table' then
        error("Call with only a single argument, the table to make into an object", 2)
    end

    obj.new = obj.new or function (...)
        if #arg ~= 2 then
            error("Call 'new' with 2 arguments, self (parent/superclass), and the table to make into a new object instance of this class", 2)
        end
        local self = arg[1]
        local o = arg[2]
        if type (o) ~= 'table' then
            error("No table provided to instantiate the new object from. Use; super:new({setting = 'xyz'})", 2)
        end
        if self == object then
            -- cannot instatiate this one.
            error("Cannot instantiate a base class object, must call subclass() to create a class that can be instantiated first.", 2)
        end
        setmetatable (o,self)
        self.__index = self
        o.super = self
        if type(o.initialize) == "function" then
            o:initialize()
        end
        return o
    end

    obj.subclass = obj.subclass or function (...)
        if #arg ~= 2 then
            error("Call 'subclass' with 2 arguments, self (parent/superclass), and the table to make into a new child/descendant class", 2)
        end
        local self = arg[1]
        local o = arg[2]
        if type (o) ~= 'table' then
            error("No table provided to subclass the object into. Use; super:subclass({setting = 'xyz'})", 2)
        end
        if self == object then
            -- initializing a base object, so just call 'make' on it. Otherwise it would expose the 'make' method
            -- and add an extra layer of table lookup traversals.
            return object.make(o)
        end
        setmetatable (o,self)
        self.__index = self
        o.super = self
        return o
    end

    return obj
end

-- now make 'object' itself an object
object.make(object)


local test = function()
    local initialized = false
    -- create a table with an initialize method, and inherited method
    local base = {}
    base.initialize =  function() initialized = true end
    base.inherited = function() return true end
    -- make the table into an object (just required for the initial one)
    base = object.make(base)
    -- create instance and check if the initialzeer ran (in the base object)
    local instance = base:new({})
    assert(initialized, "Should have been true")
    assert(instance.super == base, "Super class should point to base")
    -- create instance and check if the PROVIDED initializer ran
    initialized = nil
    local instance = base:new({initialize = function() initialized = false end})
    assert(initialized == false, "Should have been false")
    -- create a subclass and check that the initializer didn't run
    initialized = nil
    local base2 = base:subclass({initialize = function() initialized = "stringvalue" end})
    assert(base2.super == base, "Super class should point to base")
    assert(initialized == nil, "Should have been still nil")
    -- instantiate the subclass and check that the initializer runs
    instance = base2:new({})
    assert(instance.super == base2, "Super class should point to base")
    assert(initialized == "stringvalue", "Should have been a string value")
    -- check availability of inherited super-initialize method
    base2.super.initialize()
    assert(initialized == true, "Should have been true")
    -- check inherited method
    assert(base2:inherited() == true , "Should have returned true")
end

test()

return object
