local base = require("xpl.classes.base")

-- create my table
local myObject = {
    data = "hello world",

    print = function(self)
        print(self.data)
    end,

    initialize = function(self)
        -- upon initialization just print
        self:print()
    end
}

-- make it a class with single inheritance by subclassing
-- it from the base class. The 'initialize()' method will
-- NOT be called upon subclassing
myObject = base:subclass(myObject)

-- instantiate an object from the new class and
-- override field contents. This will call 'initialize()'
-- and print "my world".
local descendant = myObject:new({data = "my world"})

-- now override another method
function descendant:print()
    -- convert data to uppercase
    self.data = string.upper(self.data)
    -- call ancestor method through 'super'. NOTE: you
    -- must use 'function notation' for the call, 'method
    -- notation' will not work.
    self.super.print(self)
end

-- try the overriden method and print "MY WORLD"
descendant:print()
