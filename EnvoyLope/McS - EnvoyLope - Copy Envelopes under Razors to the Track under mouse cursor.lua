 -- @description Copy Envelopes under Razors to the Track under mouse cursor
 -- @author McSound
 -- @version 1.08
 -- @repository https://github.com/McSound/Reaper-scripts/raw/master/index.xml
 -- @licence GPL v3
 

local r = reaper
local windows = string.find(r.GetOS(), "Win") ~= nil
local separator = windows and '\\' or '/'

mcs_gl_envoylope_command = {km=1 ,rft=2, sign=-1} -- Keyb Fine Down

local path = r.GetExePath()
dofile(path..separator.."Scripts"..separator.."McSound Scripts"..separator.."EnvoyLope"..separator.."McS - EnvoyLope - Service Execution.lua")
