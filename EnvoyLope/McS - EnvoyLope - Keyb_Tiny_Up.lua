 -- @description Keyb_Tiny_Up
 -- @author McSound
 -- @version 1.08
 -- @repository https://github.com/McSound/Reaper-scripts/raw/master/index.xml
 -- @licence GPL v3

local r = reaper
local sep = package.config:sub(1,1)

mcs_gl_envoylope_command = {km=1 ,rft=3, sign=1} -- Keyb Tiny Up

local path = r.GetExePath()
dofile(path..sep.."Scripts"..sep.."McSound Scripts"..sep.."EnvoyLope"..sep.."McS - EnvoyLope - Service Execution.lua")

