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
local huge = math.huge
local tonum = tonumber
local tostr = tostring

local EL_par = {
  rough={1, 10}, -- db, perc
  fine={0.5, 5},
  tiny={0.1, 1},
  undo_keyb=1, --undo_keyb
  undo_mouse=0, --undo_mouse
  act_vis=1, --act_vis
  env_menu=9, -- "UNDER_RAZOR" default,  selected-chosen menu line
  auto_act_on=0, -- auto activate env
  auto_vis_on=0, -- auto visibility on
  auto_vis_off=0, -- auto visibility off
  auto_on_razor=0, -- do auto on-off on razor change
  respect_lane=0, -- apply changes only on razor ranges on corresponding envelopes
  env_on_lane=1, -- place activated envelope on envelope lane
  envtranstime=envtrt, -- time of transitions of envelope
  project_saved=0 -- if params was saved to current project
  }

function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end

function in_range(value, min, max)
  if value==nil or min==nil or max==nil then return nil end
  if value >= min and value <= max then
    return true
  else
    return false
  end
end

function assign_EL_par(num, val)
  val = tonum(val)

  if num==1 then
    EL_par.rough[1] = val
  elseif num==2 then
    EL_par.rough[2] = val
  elseif num==3 then
    EL_par.fine[1] = val
  elseif num==4 then
    EL_par.fine[2] = val
  elseif num==5 then
    EL_par.tiny[1] = val
  elseif num==6 then
    EL_par.tiny[2] = val
  elseif num==7 then
    EL_par.undo_keyb = val
  elseif num==8 then
    EL_par.undo_mouse = val
  elseif num==9 then
    EL_par.act_vis = val
  elseif num==10 then
    EL_par.env_menu = val
  elseif num==11 then
    EL_par.auto_act_on = val
  elseif num==12 then
    EL_par.auto_vis_on = val
  elseif num==13 then
    EL_par.auto_vis_off = val
  elseif num==14 then
    EL_par.auto_on_razor = val
  elseif num==15 then
    EL_par.respect_lane = val
  elseif num==16 then
    EL_par.env_on_lane = val
  elseif num==17 then
    EL_par.envtranstime = val -- envtranstime must be the last 
  end
end

function restore_EL_par_from_global_ext()
  local str
  if r.HasExtState("McS-Tools", "EnvoyLope_params") then
    str = r.GetExtState("McS-Tools", "EnvoyLope_params")
  end
  if str then
    local num = 0
    for val in str:gmatch("([^,]+)") do
      num = num+1
      assign_EL_par(num, val)
    end
  end
  if str then return true else return false end
end

function restore_EL_par_from_project_ext(proj)
  local retval, str = r.GetProjExtState(proj, "McS - EnvoyLope_params", "saved_params")
  if retval and str then
    local num = 0
    for val in str:gmatch("([^,]+)") do
      num = num+1
      assign_EL_par(num, val)
    end
  end
  if str~="" then 
    EL_par.project_saved=1 
    return true 
  else 
    EL_par.project_saved=0 
    return false
  end
end

function get_razor_areas(tr)
  local razor_table = {}
  local razor_exist_on_track
  local rt = false
  local count_track = r.CountTracks(0)
  for i=0, count_track-1 do
    local track = r.GetTrack(0, i)
    local ok, area = r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if ok and area ~= "" then
      if track == tr then razor_exist_on_track=true end
      local st, en, env
      local re ={}
      for st, en, env in string.gmatch(area, "(%S+) (%S+) (%S+)") do
        rt = true
        re[#re+1] = {st = tonumber(st), en = tonumber(en), env = env}
      end
      razor_table[#razor_table+1] ={track = track, razor_edits = re}
    end
  end
  return rt, razor_table, razor_exist_on_track
end

function Main()

  local window, segment, details = r.BR_GetMouseCursorContext()
  if window == "arrange" then
    local rt_pr = restore_EL_par_from_project_ext(r.EnumProjects(-1))
    if not rt_pr then
      local rt_gl = restore_EL_par_from_global_ext()
    end
    if EL_par.env_menu==nil then return end
    
    local cursor_pos = r.BR_GetMouseCursorContext_Position()
    local track = r.BR_GetMouseCursorContext_Track()
    local rt, razor_table, razor_exist_on_track = get_razor_areas(track)

    if not razor_exist_on_track then return end

    local env
    if EL_par.env_menu==9 then
      local env_under_mouse = r.BR_GetMouseCursorContext_Envelope()
      if r.ValidatePtr2(0, env_under_mouse, "TrackEnvelope*") then
        env = env_under_mouse
      end
    else
      if EL_par.env_menu==1 then
        env =  r.GetTrackEnvelopeByChunkName(track,"<VOLENV2") --r.GetTrackEnvelopeByName(track,"Volume")
      elseif EL_par.env_menu==2 then
        env = r.GetTrackEnvelopeByChunkName(track,"<PANENV2") --r.GetTrackEnvelopeByName(track,"Pan")
      elseif EL_par.env_menu==3 then
        env = r.GetTrackEnvelopeByChunkName(track,"<WIDTHENV2") --r.GetTrackEnvelopeByName(track,"Width")
      elseif EL_par.env_menu==4 then
        env = r.GetTrackEnvelopeByChunkName(track,"<VOLENV") --r.GetTrackEnvelopeByName(track,"Volume (Pre-FX)")
      elseif EL_par.env_menu==5 then
        env = r.GetTrackEnvelopeByChunkName(track,"<PANENV") --r.GetTrackEnvelopeByName(track,"Pan (Pre-FX)")
      elseif EL_par.env_menu==6 then
        env = r.GetTrackEnvelopeByChunkName(track,"<WIDTHENV") --r.GetTrackEnvelopeByName(track,"Width (Pre-FX)")
      elseif EL_par.env_menu==7 then
        env = r.GetTrackEnvelopeByChunkName(track,"<MUTEENV") --r.GetTrackEnvelopeByName(track,"Mute")
      elseif EL_par.env_menu==8 then
        env = r.GetTrackEnvelopeByChunkName(track,"<VOLENV3") --r.GetTrackEnvelopeByName(track,"Trim Volume")
      end
    end

    if env then
      local rt, env_guid = r.GetSetEnvelopeInfo_String(env, "GUID", "", false)
      if EL_par.env_on_lane == 0 then env_guid = "" end
      local id1 = r.GetEnvelopePointByTime(env, cursor_pos)
      if id1 == -1 then return end
      local retval, time2, value, shape, tension, selected = r.GetEnvelopePoint(env, id1+1)
      if retval == false then return end
      local retval, time1, value, shape, tension, selected = r.GetEnvelopePoint(env, id1)
      local rz1_j, rz2_j = -1,-1
      local new_rz = ""
      if rt == true then
        for i=1, #razor_table do
          if razor_table[i].track == track then
            local razor_edits = razor_table[i].razor_edits
            for j=1,#razor_edits do
              local st = razor_edits[j].st
              local en = razor_edits[j].en
              if st<=cursor_pos and en>=cursor_pos then return end
              if st<cursor_pos and en<cursor_pos then rz1_j=j end
              if st>cursor_pos and en>cursor_pos then rz2_j=j break end
            end
            local j_dont_do = {}
            for j=1,#razor_edits do
              if not j_dont_do[j] then
                local st = razor_edits[j].st
                local en = razor_edits[j].en
                if rz1_j~=j and rz2_j~=j then
                  new_rz = new_rz..tostring(st).." "..tostring(en).." "..env_guid.." "
                elseif rz1_j~=-1 and rz2_j~=-1 and rz1_j==j then
                  j_dont_do[rz2_j] = true
                  new_rz = new_rz..tostring(st).." "..tostring(razor_edits[rz2_j].en).." "..env_guid.." "
                elseif rz1_j~=-1 and rz2_j==-1 and rz1_j==j then
                  new_rz = new_rz..tostring(st).." "..tostring(time2).." "..env_guid.." "
                elseif rz1_j==-1 and rz2_j~=-1 and rz2_j==j then
                  new_rz = new_rz..tostring(time1).." "..tostring(en).." "..env_guid.." "
                end
              end
            end
            break
          end
        end
      else
        new_rz = new_rz..tostring(time1).." "..tostring(time2).." "..env_guid
      end
      r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", new_rz, true)
      r.SetCursorContext(2,env)
    end
  end
end

r.PreventUIRefresh(1)
r.Undo_BeginBlock()

Main()

r.Undo_EndBlock("McS - EnvoyLope - Razor", -1)
r.PreventUIRefresh(-1)
r.UpdateArrange()
