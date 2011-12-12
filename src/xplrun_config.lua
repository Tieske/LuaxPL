-- Configuration file for the LuaxPL utility 'xplrun'.
-- Copyright 2011 Thijs Schreijer
--
-- Comments start with '--' (double-dash), multiline comments are between --[[   and   ]]

return {

    listenon = "ANY_LOCAL",         -- ANY_LOCAL (any local adapter) or a specific IP address TODO: make this work
    listento = {                    -- ANY_LOCAL (peers within same subnet) or table with IP addresses TODO: make this work
        "ANY_LOCAL"
    },
    broadcast = "255.255.255.255",  -- where to broadcast outgoing messages to
    xplport = 3865,                 -- standard xPL port to send to
    xplhub = false,                 -- either 'true' or 'false', should the embedded hub be used

    devices = {                     -- table with device settings
        -- device xyz
        {
            classname = "basicdevice",                      -- classname of device

        },
    },


}
