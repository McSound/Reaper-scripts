 --@ description: All in name.
 --@ author: McSound
 --@ version:1.08
 --@ instructions: Select Video file(s) and run script. 
 --@ repository: https://github.com/McSound/Reaper-scripts/raw/master/index.xml
 --@ licence: GPL v3
 --@ forum thread:
 --@ Reaper v 7.61
 
--[[
 * Changelog:
 * v1.0 (2025-11-14)
  + Initial Release
--]]

local r = reaper
local sep = package.config:sub(1,1)

mcs_gl_envoylope_command = {km=1 ,rft=3, sign=1} -- Keyb Tiny Up

local path = r.GetExePath()
dofile(path..sep.."Scripts"..sep.."McSound_Scripts"..sep.."EnvoyLope"..sep.."McS - EnvoyLope - Service Execution.lua")

