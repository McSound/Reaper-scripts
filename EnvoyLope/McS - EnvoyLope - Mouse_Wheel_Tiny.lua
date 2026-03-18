 -- @description Mouse_Wheel_Tiny
 -- @author McSound
 -- @version 1.08
 -- @repository https://github.com/McSound/Reaper-scripts/raw/master/index.xml
 -- @licence GPL v3

local r = reaper
local sep = package.config:sub(1,1)

mcs_gl_envoylope_command = {km=2 ,rft=3, sign=1} -- Mouse Tiny Up
local _,_,_,_,_,_,val_in = r.get_action_context()
if val_in <= 0 then mcs_gl_envoylope_command.sign = -1 end -- Mouse Tiny Down

local path = r.GetExePath()
dofile(path..sep.."Scripts"..sep.."McSound Scripts"..sep.."EnvoyLope"..sep.."McS - EnvoyLope - Service Execution.lua")
