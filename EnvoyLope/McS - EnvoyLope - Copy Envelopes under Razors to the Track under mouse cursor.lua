local r = reaper
local windows = string.find(r.GetOS(), "Win") ~= nil
local separator = windows and '\\' or '/'

mcs_gl_envoylope_command = {km=1 ,rft=2, sign=-1} -- Keyb Fine Down

local path = r.GetExePath()
dofile(path..separator.."Scripts"..separator.."McSound"..separator.."EnvoyLope"..separator.."McS - EnvoyLope - Main Execution.lua")
