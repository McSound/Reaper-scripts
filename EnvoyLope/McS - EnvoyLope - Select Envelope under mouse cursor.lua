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
