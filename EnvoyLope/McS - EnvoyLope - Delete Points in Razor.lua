
local r = reaper
local tonum = tonumber
local tostr = tostring

local inac = 0.00000001

local rt, razor_table = nil, {}

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

function find_track_env(i, env_chunk_name)
  local env

  if env_chunk_name=="<VOLENV2" then env = razor_table[i].track_env.vol
  elseif env_chunk_name=="<PANENV2" then env = razor_table[i].track_env.pan
  elseif env_chunk_name=="<WIDTHENV2" then env = razor_table[i].track_env.width
  elseif env_chunk_name=="<VOLENV" then env = razor_table[i].track_env.volpre
  elseif env_chunk_name=="<PANENV" then env = razor_table[i].track_env.panpre
  elseif env_chunk_name=="<WIDTHENV" then env = razor_table[i].track_env.widthpre
  elseif env_chunk_name=="<VOLENV3" then env = razor_table[i].track_env.trim
  elseif env_chunk_name=="<MUTEENV" then env = razor_table[i].track_env.mute end

  return env
end
function get_track_envs(track)
  function get_env_act_vis(en)
    local _, act, vis
    if en ~= nil then
      _, act = r.GetSetEnvelopeInfo_String(en, "ACTIVE", "", false)
      _, vis = r.GetSetEnvelopeInfo_String(en, "VISIBLE", "", false)
    end
    return act, vis
  end

  local track_env = {}
  local vol =  r.GetTrackEnvelopeByChunkName(track,"<VOLENV2") --r.GetTrackEnvelopeByName(track,"Volume")
  local pan = r.GetTrackEnvelopeByChunkName(track,"<PANENV2") --r.GetTrackEnvelopeByName(track,"Pan")
  local width = r.GetTrackEnvelopeByChunkName(track,"<WIDTHENV2") --r.GetTrackEnvelopeByName(track,"Width")
  local volpre = r.GetTrackEnvelopeByChunkName(track,"<VOLENV") --r.GetTrackEnvelopeByName(track,"Volume (Pre-FX)")
  local panpre = r.GetTrackEnvelopeByChunkName(track,"<PANENV") --r.GetTrackEnvelopeByName(track,"Pan (Pre-FX)")
  local widthpre = r.GetTrackEnvelopeByChunkName(track,"<WIDTHENV") --r.GetTrackEnvelopeByName(track,"Width (Pre-FX)")
  local trim = r.GetTrackEnvelopeByChunkName(track,"<VOLENV3") --r.GetTrackEnvelopeByName(track,"Trim Volume")
  local mute = r.GetTrackEnvelopeByChunkName(track,"<MUTEENV") --r.GetTrackEnvelopeByName(track,"Mute")
  track_env = {vol=vol, pan=pan, width=width, volpre=volpre, panpre=panpre, widthpre=widthpre, trim=trim, mute=mute}

  local send_env = {}
  local send_count = r.GetTrackNumSends(track, 0)
  if send_count> 0 then
    for i=0, send_count-1 do
      -- local retval, name = r.GetEnvelopeName(env)
      local dest_tr = r.GetTrackSendInfo_Value(track, 0, i, "P_DESTTRACK")
      local vol = r.BR_GetMediaTrackSendInfo_Envelope(track, 0, i, 0)
      local pan = r.BR_GetMediaTrackSendInfo_Envelope(track, 0, i, 1)
      local mute = r.BR_GetMediaTrackSendInfo_Envelope(track, 0, i, 2)
      local vol_act, vol_vis = get_env_act_vis(vol)
      local pan_act, pan_vis = get_env_act_vis(pan)
      local mute_act, mute_vis = get_env_act_vis(mute)
      local e_vol = {env=vol, act=vol_act, vis=vol_vis}
      local e_pan = {env=pan, act=pan_act, vis=pan_vis}
      local e_mute = {env=mute, act=mute_act, vis=mute_vis}
      local env = {e_vol, e_pan, e_mute}
      send_env[i+1] = {dest_tr=dest_tr, env=env}
    end
  end

  local fx_env = {}
  local fx_count = r.TrackFX_GetCount(track)
  if fx_count>0 then
    for i=0,fx_count-1 do
      local retval, type_fxname = r.TrackFX_GetFXName(track, i)
      local type, fxname = type_fxname:match("(.+): (.+)")

      local fx_par_count = r.TrackFX_GetNumParams(track, i)
      if fx_par_count>0 then
        local env = {}
        for j=0,fx_par_count-1 do
          local en = r.GetFXEnvelope(track, i, j, false)
          local act, vis = get_env_act_vis(en)
          env[j+1] = {env=en, act=act, vis=vis}  -- this table may contain holes
        end
        fx_env[i+1] = {name=type_fxname, par_num=fx_par_count, env=env}
      end
    end
  end

  return track_env, send_env, fx_env
end

function get_razor_areas()
  local razor_table = {}
  local rt

  local count_track = r.CountTracks(0)

  for i=0, count_track-1 do
    local track = r.GetTrack(0, i)
    local ok, area = r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if ok and area ~= "" then
      local st, en, env
      local re ={}
      for st, en, env in string.gmatch(area, "(%S+) (%S+) (%S+)") do
        rt = true
        re[#re+1] = {st = tonum(st), en = tonum(en), env = env}
      end
      local track_env, send_env, fx_env = get_track_envs(track)
      razor_table[#razor_table+1] ={track=track, track_env=track_env, send_env=send_env, fx_env=fx_env, razor_edits=re}
    end
  end
  return rt, razor_table, raz_sel_env, raz_sel_ptrack
end

function Main()

  local rt_pr = restore_EL_par_from_project_ext(r.EnumProjects(-1))
  if not rt_pr then
    local rt_gl = restore_EL_par_from_global_ext()
  end
  if EL_par.env_menu==nil then return end
  
  local cursor_pos = r.BR_GetMouseCursorContext_Position()
  local track = r.BR_GetMouseCursorContext_Track()
  local env_chname
  if EL_par.env_menu==1 then
    env_chname = "<VOLENV2"
  elseif EL_par.env_menu==2 then
    env_chname = "<PANENV2"
  elseif EL_par.env_menu==3 then
    env_chname = "<WIDTHENV2"
  elseif EL_par.env_menu==4 then
    env_chname = "<VOLENV"
  elseif EL_par.env_menu==5 then
    env_chname = "<PANENV"
  elseif EL_par.env_menu==6 then
    env_chname = "<WIDTHENV"
  elseif EL_par.env_menu==7 then
    env_chname = "<MUTEENV"
  elseif EL_par.env_menu==8 then
    env_chname = "<VOLENV3"
  end

  rt, razor_table = get_razor_areas()

  if rt == true and ((EL_par.env_menu~=9 and env_chname) or EL_par.env_menu==9)then
    for i=1,#razor_table do
      local track = razor_table[i].track
      local razor_edits = razor_table[i].razor_edits

      if EL_par.env_menu==9 then
        r.Main_OnCommand(40697, 0) --Remove items/tracks/envelope points (depending on focus)
      else
        for j=1,#razor_edits do
          local st = razor_edits[j].st
          local en = razor_edits[j].en
          local env_tr = find_track_env(i, env_chname)
          r.DeleteEnvelopePointRange(env_tr, st, en+inac)
          r.Envelope_SortPoints(env_tr)
        end
      end
    end
  end
end

r.PreventUIRefresh(1)
r.Undo_BeginBlock()

Main()

r.Undo_EndBlock("McS - EnvoyLope - Delete Points", -1)
r.PreventUIRefresh(-1)
r.UpdateArrange()
