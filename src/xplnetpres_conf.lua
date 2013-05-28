----------------------------------------------------------------------------
-- xplnetpresence sample configuration file.
-- Sample configuration file for the LuaxPL utility 'xplnetpresence', to list known devices.
--
-- These are the fields (either mac or ip is required!):
--    mac : contains the mac address, remove line if its unknown
--    ip  : ip address if known/fixed, remove line if its unknown
--    name: name of device used in messages
--    timeout: timeout in seconds for the device, overrides the commandline option
--
-- repeat the device block for as many devices as necessary
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, commandline xPL message logger utility.
-- @class module
-- @name xplnetpres_conf

return {
-- start of known device list

    -- start of device block
    {
        mac = "xx:xx:xx",
        ip = "123.123.123",
        name = "identifier",
        timeout = 120,
    },
    -- end of device block


-- end of known device list
}
