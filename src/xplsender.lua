#!/usr/local/bin/lua

----------------------------------------------------------------------------
-- @copyright 2011 Thijs Schreijer
-- @release Version 0.1, commandline xPL message sender utility.
-- @description# Commandline utility for sending xPL messages, message can be specified on the commandline (<code>-m</code> option) or send from files (<code>-f</code> option). Use option <code>-help</code> for a full description.
-- &nbsp
-- Example: <code>
-- xplsender.lua -f="C:\samplemsg.txt" -m="xpl-trig\n{\nhop=1\nsource=tieske-upnp.somedev\ntarget=*\n}\nsome.schema\n{\ncommand=unknown\n}\n"
-- </code>
-- This module is standalone and has no dependencies on any other of the xPL code files. It only depends on the luasocket module.
-- @name xplsender.lua

module ("xplsender", package.seeall)

local prog = {
	name = "xPL message sender",
	banner = "version 0.1, Copyright 2011 Thijs Schreijer",
	use = "Send xPL messages from a commandline",
	options = arg[0] .. [[ [OPTIONS...]
Options;
   -b, -broadcast[=255.255.255.255]       Broadcast address to use for sending
   -f, -file[=FILE]                       Text file with message content to send
   -m, -msg[='xpl-cmnd\n{\nhop=1\n...']   Escaped message on commandline to send
   -v, -verbose                           Displays message contents while sending
   -version                               Print version info
   -h, -help                              Display this usage information

option -file and -msg may be combined and may contain multiple messages each.

	]],
}

--local rocks = require ("luarocks.loader")
local socket = require ("socket")
local msgs = {}		-- list of messages to be sent, digested from commandline
local opt = {
			broadcast = { "broadcast", "b" },
			file = { "file", "f" },
			message = { "message", "msg", "m" },
			verbose = { "verbose", "v" },
			version = { "version" },
			help = { "help", "h"},
			}
local arg = arg		-- argument list, after parsing only unrecognized arguments
local BROADCAST = "255.255.255.255"		-- default broadcast address
local XPLPORT = 3865					-- xPL network port

local function unescape_string (s)
	----------------------------------------------------------------------
	-- unescape a whole string, applying [unesc_digits] and
	-- [unesc_letter] as many times as required.
	-- Code from MetaLua project, file; lexer.lua
	-- Copyright (c) 2006, Fabien Fleutot <metalua@gmail.com>.
	-- released under the MIT Licence
	--
	-- see: https://github.com/fab13n/metalua/blob/master/src/compiler/lexer.lua
	--
	----------------------------------------------------------------------

    -- Turn the digits of an escape sequence into the corresponding
    -- character, e.g. [unesc_digits("123") == string.char(123)].
    local function unesc_digits (backslashes, digits)
		if #backslashes%2==0 then
			-- Even number of backslashes, they escape each other, not the digits.
			-- Return them so that unesc_letter() can treaat them
			return backslashes..digits
		else
			-- Remove the odd backslash, which escapes the number sequence.
			-- The rest will be returned and parsed by unesc_letter()
			backslashes = backslashes :sub (1,-2)
		end
		local k, j, i = digits:reverse():byte(1, 3)
		local z = _G.string.byte "0"
		local code = (k or z) + 10*(j or z) + 100*(i or z) - 111*z
		if code > 255 then
			error ("Illegal escape sequence '\\"..digits..
				"' in string: ASCII codes must be in [0..255]")
		end
		return backslashes .. string.char (code)
   end

	-- Take a letter [x], and returns the character represented by the
	-- sequence ['\\'..x], e.g. [unesc_letter "n" == "\n"].
	local function unesc_letter(x)
		local t = {
			a = "\a", b = "\b", f = "\f",
			n = "\n", r = "\r", t = "\t", v = "\v",
			["\\"] = "\\", ["'"] = "'", ['"'] = '"', ["\n"] = "\n" }
		return t[x] or error([[Unknown escape sequence '\]]..x..[[']])
	end

	return s
		:gsub ("(\\+)([0-9][0-9]?[0-9]?)", unesc_digits)
		:gsub ("\\(%D)",unesc_letter)
end




local function usage()
	print(prog.name)
	print(prog.banner)
	print(prog.use)
	print(prog.options)
end

local function version()
	print(prog.name .. ", " .. prog.banner)
end


local function parsecommandline(opt,arg)
	-- arg is argument list, global _G.arg is used if nil is provided
	-- opt is list of possible options in table as;
	--   opt = { fullname1 = { name1, name2, name3 },
	--           fullname2 = { name1, name2, name3 },
	--         }
	-- returns;
	--    parsed options table
	--    unparsed options table

	arg = arg or _G.arg		-- get global argument list if none provided
	local unp = {}			-- unparsable arguments remaining
	local result = {}		-- parsed list
	for _, a in ipairs(arg) do
		local key, val = string.match(a,'\-+(%a+)\=*(.*)')
		if key == nil then
			-- not recognized/parsable
			table.insert(unp,a)
		else
			-- see if we can find a match
			local m
			for fullname, namelist in pairs(opt) do
				for _, name in ipairs(namelist) do
					if name == key then
						-- match found
						m = fullname
					end
				end
			end
			if m then
				-- we have a match, so store it
				if val == "" then
					val = true		-- convert to boolean option
				end
				result[m] = val
			else
				-- there was no match
				table.insert(unp, a)
			end
		end
	end
	return result, unp
end

local function parsemessagestring(msg, msgs)
	-- parses a message string (msg) and adds the individual messages to a table (msgs) which is then returned
	msg = "\n" .. string.gsub(msg, "\r\n", "\n") .. "\n"	-- replace windows line ends with unix/xpl ones and app/prepend lineends
	local s, e = 1, 1
	while s do
		s, e = string.find(msg, '\nxpl%-.-\n}\n.-\n}\n', e)
		if s then
			-- found an xPL message store it
			msgs = msgs or {}
			table.insert(msgs, string.sub(msg,s + 1,e))
		end
	end
	return msgs
end


opt, arg = parsecommandline(opt)		-- Go parse commandline options

if opt.help then						-- display message and exit
	usage()
	os.exit()
end
if opt.version then					-- display message and exit
	version()
	os.exit()
end
BROADCAST = opt.broadcast or BROADCAST	-- Broadcast address to use when sending

if opt.file then						-- parse file contents to xPL messages
	local f, e = io.open(opt.file)
	if not f then
		print ("Opening file " .. tostring(opt.file) .. " resulted in error; " .. tostring(e))
		error()		-- exit with error code
	end
	local m = f:read("*a")
	f:close()
	msgs = parsemessagestring(m, msgs)	-- parse the file contents to xPL messages
end

if opt.message then					-- parse commandline message to xPL messages
	opt.message = unescape_string(opt.message)		-- update escaped string value to real string value
	msgs = parsemessagestring(opt.message, msgs)	-- parse the string to xPL messages
end

msgs = msgs or {}
if #msgs == 0 then						-- no messages to send
	print ("No messages could be parsed, nothing to send.")
	print ("Use '-help' option for help on using xPL sender.")
	error()
end

local skt, emsg = socket.udp()			-- create and prepair socket
if skt == nil then
	-- failure
	print ("Failed to send messages, cannot create UDP socket; " .. emsg)
	error()
end
skt:settimeout(1)
skt:setoption("broadcast", true)
local cnt = 0
for i, m in ipairs(msgs) do			-- send all messages

	local success, emsg = skt:sendto(m, BROADCAST, XPLPORT)
	if not success then
		-- failed
		print ("Error sending message " .. i .. "; " .. emsg)
		if opt.verbose then
			print(m)
			print()
		end
	else
		-- success
		cnt = cnt + 1
		if opt.verbose then
			print ("successfully send message " .. i .. ";")
			print(m)
			print()
		end
	end
end

print ("succesfully send " .. cnt .. " messages, " .. #msgs - cnt .. " messages failed.")

if #msgs ~= cnt then					-- not all messages send successfully, exit with error code
	error()
end

