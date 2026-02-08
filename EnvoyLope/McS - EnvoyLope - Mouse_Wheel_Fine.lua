local r = reaper
local sep = package.config:sub(1,1)

mcs_gl_envoylope_command = {km=2 ,rft=2, sign=1} -- Mouse Fine Up
local _,_,_,_,_,_,val_in = r.get_action_context()
if val_in <= 0 then mcs_gl_envoylope_command.sign = -1 end -- Mouse Fine Down

local path = r.GetExePath()
dofile(path..sep.."Scripts"..sep.."McSound"..sep.."EnvoyLope"..sep.."McS - EnvoyLope - Main Execution.lua")
