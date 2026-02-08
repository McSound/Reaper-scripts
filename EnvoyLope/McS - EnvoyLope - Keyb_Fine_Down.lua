local r = reaper
local sep = package.config:sub(1,1)

mcs_gl_envoylope_command = {km=1 ,rft=2, sign=-1} -- Keyb Fine Down

local path = r.GetExePath()
dofile(path..sep.."Scripts"..sep.."McSound"..sep.."EnvoyLope"..sep.."McS - EnvoyLope - Main Execution.lua")
