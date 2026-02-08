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

function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end

function Main()
  local window, segment, details = r.BR_GetMouseCursorContext()
  local env = r.BR_GetMouseCursorContext_Envelope()
  if r.ValidatePtr2(0, env, "TrackEnvelope*") then
    r.SetCursorContext(2,env)
  end
end

-- r.PreventUIRefresh(1)
r.Undo_BeginBlock()

Main()

r.Undo_EndBlock("McS - EnvoyLope - Select Envelope under mouse cursor", -1)
-- r.PreventUIRefresh(-1)
r.UpdateArrange()
