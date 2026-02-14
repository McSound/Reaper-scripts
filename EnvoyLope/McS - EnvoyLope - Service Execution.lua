 --@ description: All in name.
 --@ author: McSound
 --@ version:1.08
 --@ provides [nomain] .
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

---- Main Execution Script v1.08 ----

local r = reaper
local floor = math.floor
local log = math.log
local huge = math.huge
local format = string.format
local tonum = tonumber
local tostr = tostring

function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end

function no_undo() r.defer(function()end) end

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return floor(num * mult + 0.5) / mult
end

local razor = {rt=nil, table={}, sel_env=nil, sel_env_ptrack=nil}
local cmd = {undo=nil, db_or_perc=nil, rft=nil, sign=nil, val_db=nil, val_perc=nil, sel_env=nil, sel_env_ptrack=nil}

local inac = 0.0001--0.00000001
local retval, envtrt = r.get_config_var_string("envtranstime")
envtrt = tonum(envtrt)
local retval, defenvs = r.get_config_var_string("defenvs")
local pointshape
if defenvs == "0" then pointshape=0
elseif defenvs == "65536" then pointshape=1
elseif defenvs == "131072" then pointshape=2
elseif defenvs == "196608" then pointshape=3
elseif defenvs == "262144" then pointshape=4
elseif defenvs == "327680" then pointshape=5 end


local env_menu_name = {"Volume","Pan","Width","Volume(Pre-FX)","Pan(Pre-FX)","Width(Pre-FX)","Mute","Trim Volume","Selected Env"}
local env_chunkname = {"<VOLENV2","<PANENV2","<WIDTHENV2","<VOLENV","<PANENV","<WIDTHENV","<MUTEENV","<VOLENV3","SEL"}

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


function in_range_equal(value, min, max)
  if value==nil or min==nil or max==nil then return nil end
  if value >= min and value <= max then
    return true
  else
    return false
  end
end

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return floor(num * mult + 0.5) / mult
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

function recognize_command(command)

  if command.km==1 then
    cmd.undo = EL_par.undo_keyb
  elseif command.km==2 then
    cmd.undo = EL_par.undo_mouse
  end

  if EL_par.env_menu ~= 9 then
    if EL_par.env_menu==1 or EL_par.env_menu==4 or EL_par.env_menu==8 then
      cmd.db_or_perc = 1
    else
      cmd.db_or_perc = 2
    end
  else
    cmd.db_or_perc = 2
  end

  cmd.sign = command.sign

  cmd.rft = command.rft

  if cmd.rft==1 then
    cmd.val_db = EL_par.rough[1] * cmd.sign
    cmd.val_perc = EL_par.rough[2] * cmd.sign
  elseif cmd.rft==2 then
    cmd.val_db = EL_par.fine[1] * cmd.sign
    cmd.val_perc = EL_par.fine[2] * cmd.sign
  elseif cmd.rft==3 then
    cmd.val_db = EL_par.tiny[1] * cmd.sign
    cmd.val_perc = EL_par.tiny[2] * cmd.sign
  end

  return cmd
end

function join_razors(un_items)
  -- Let's sort un_items by the start value
  local items = {}
  local exist = {}
  local j_min
  for i=1,#un_items do
    local min=huge
    for j=1,#un_items do
      if un_items[j].st<min and not exist[j] then 
        min = un_items[j].st
        j_min = j
      end
    end
    exist[j_min] = true
    items[i] = {st=un_items[j_min].st, en=un_items[j_min].en} -- sorted table
  end

  local e_it = {}
  for i=1,#items do
    if i==1 then
      e_it[1] = {st=items[i].st, en=items[i].en}
    else
      local f=false
      for j=1,#e_it do

        -- Start
        if e_it[j].st>items[i].st and e_it[j].en>=items[i].en and e_it[j].st<=items[i].en then
          f=true
          e_it[j].st = items[i].st

        -- Both inside, do nothing
        elseif e_it[j].st<=items[i].st and e_it[j].en>=items[i].en then
          f=true

        -- End
        elseif e_it[j].st<=items[i].st and e_it[j].en>=items[i].st and e_it[j].st<items[i].en then
          f=true
          e_it[j].en = items[i].en

        -- Both outside
        elseif e_it[j].st>items[i].st and e_it[j].en<items[i].en then
          f=true
          e_it[j].st = items[i].st
          e_it[j].en = items[i].en

        end
      end
      if f == false then
        e_it[#e_it+1] = {st=items[i].st, en=items[i].en}
      end
    end
  end
  return e_it
end

function find_track_env(i, env_chunk_name)
	local env

  if env_chunk_name=="<VOLENV2" then env = razor.table[i].track_env.vol
  elseif env_chunk_name=="<PANENV2" then env = razor.table[i].track_env.pan
  elseif env_chunk_name=="<WIDTHENV2" then env = razor.table[i].track_env.width
  elseif env_chunk_name=="<VOLENV" then env = razor.table[i].track_env.volpre
  elseif env_chunk_name=="<PANENV" then env = razor.table[i].track_env.panpre
  elseif env_chunk_name=="<WIDTHENV" then env = razor.table[i].track_env.widthpre
  elseif env_chunk_name=="<VOLENV3" then env = razor.table[i].track_env.trim
  elseif env_chunk_name=="<MUTEENV" then env = razor.table[i].track_env.mute end

  return env
end

function find_send_env(i, env_chunk_name, send_dest_track)
  local send_env_index

  if env_chunk_name=="<AUXVOLENV" then send_env_index=1
  elseif env_chunk_name=="<AUXPANENV" then send_env_index=2
  elseif env_chunk_name=="<AUXMUTEENV" then send_env_index=3 end

  if #razor.table[i].send_env>0 then
    for j=1,#razor.table[i].send_env do
      if razor.table[i].send_env[j].dest_tr==send_dest_track then
        return razor.table[i].send_env[j].env[send_env_index].env
      end
    end
  end
  return nil
end

function find_fx_env(i, fx_name, par_num, par_idx)
  if #razor.table[i].fx_env>0 then
    for j=1,#razor.table[i].fx_env do
      if razor.table[i].fx_env[j].name == fx_name and 
        razor.table[i].fx_env[j].par_num == par_num then
        return razor.table[i].fx_env[j].env[par_idx].env
      end
    end
  end
  return nil
end

function get_env_chunk_name(env)
  local chunk_name
  if r.ValidatePtr2(0, env, "TrackEnvelope*" ) then
    local retval, env_chunk = r.GetEnvelopeStateChunk(env, "", false)
    chunk_name = env_chunk:match("(<.-)\n")
  end
  return chunk_name
end

function get_env_chunk_name_and_send_idx(env, ptrack)
  local track_send_fx, send_idx, dest_track, fx_idx, fx_par_idx, fx_par_num, fx_name, bypass_par

  function fx_idx_from_env(env, track)
    local fx_count = r.TrackFX_GetCount(track)
    for j = 0, fx_count-1 do
      local fxparam_count = r.TrackFX_GetNumParams(track, j)
      local _, fx_name = r.TrackFX_GetFXName(track, j)
      for k = 0, fxparam_count-1 do
        if r.GetFXEnvelope(track, j, k, false) == env then
          return j, k, fxparam_count, fx_name  -- returns fx_index, fx_param_index, fxparam_count
        end
      end
    end
    return nil
  end

  local chunk_name = get_env_chunk_name(env)

  local retval, env_name = r.GetEnvelopeName(env)
  if env_name~=nil and env_name~="" then
  	env_name = string.lower(env_name)
  	local str1 = env_name:find("bypass")
  	local str2 = env_name:find("mute")
  	if str1 or str2 then bypass_par=1 end
  end

  if r.ValidatePtr2(0, env, "TrackEnvelope*" ) then
    send_idx = r.GetEnvelopeInfo_Value(env, "I_SEND_IDX")
    fx_idx, fx_par_idx, fx_par_num, fx_name = fx_idx_from_env(env, ptrack)

    if send_idx~=0 then
      track_send_fx = 2 -- env is send env
      dest_track = r.GetEnvelopeInfo_Value(env, "P_DESTTRACK")
    end

    if fx_idx~=nil then
      track_send_fx = 3 -- env is fx env
    end

    if chunk_name~=nil and track_send_fx==nil then
      for i=1,8 do
        if chunk_name==env_chunkname[i] then
          track_send_fx = 1 -- env is track env
          break
        end
      end
    end
  end
  return chunk_name, track_send_fx, send_idx-1, dest_track, fx_idx, fx_par_idx, fx_par_num, fx_name, bypass_par
end

function set_env_chunk(env, act, val1, vis, val2, val3, name)
-- <AUXVOLENV
-- EGUID {97614E1F-6C1A-4EEE-99D6-ADD8F2DF8EDD}
-- ACT 1 -1
-- VIS 1 1 1 -- 1 0 1 для env в треке
-- LANEHEIGHT 268 0
-- ARM 0
-- DEFSHAPE 0 -1 -1
-- VOLTYPE 1
-- PT 0 1 0
  function set(env_chunk, txt, val, valadd, pt)
    local f = false

    if txt == "LANEHEIGHT " then
      local t = tostr(val)
      if not env_chunk:find(txt..t) then
        env_chunk = env_chunk:gsub(txt.."%d+", txt..t)
        f = true
      end
    elseif txt == "VIS " then
      local t, tadd = tostr(val), tostr(valadd)
      if not env_chunk:find(txt..t.." "..tadd) then
        env_chunk = env_chunk:gsub(txt.."%d+".." %d+", txt..t.." "..tadd)
        f = true
      end
    else
      local t0, t1 = "0","1"
      if val == 0 then t0, t1 = t1, t0 end
      if not env_chunk:find(txt..t1) then
        env_chunk = env_chunk:gsub(txt..t0, txt..t1)
        f = true
      end
    end
    if ((txt=="ACT " or txt=="VIS ") and val==1) and not env_chunk:find("PT %d+ %d+ %d+") then
      env_chunk = env_chunk:gsub("\n>", "\nPT "..pt.."\n>")
    end
    return f, env_chunk
  end

  if r.ValidatePtr2(0, env, "TrackEnvelope*" ) then
    local retval, env_chunk = r.GetEnvelopeStateChunk(env, "", false)
    local pt
    if name then
      if name:find("VOLENV") or name:find("WIDTHENV") then pt = "0 1 0"
      elseif name:find("PANENV") or name:find("MUTEENV") then pt = "0 0 0" end
    end

    local rt_act, rt_vis, rt_arm, rt_laneheight
    if act == true then
      rt_act, env_chunk = set(env_chunk, "ACT ", val1, nil, pt)
    end
    if vis == true then
      rt_vis, env_chunk = set(env_chunk, "VIS ", val2, val3, pt)
    end
    if arm == true then
      rt_arm, env_chunk = set(env_chunk, "ARM ", val4, nil, pt)
    end 
    if laneheight == true then
      rt_laneheight, env_chunk = set(env_chunk, "LANEHEIGHT ", val5, nil, pt)
    end
    if rt_act or rt_vis or rt_arm or rt_laneheight then
      r.SetEnvelopeStateChunk(env, env_chunk, false)
    end
  end
end

function get_track_envs(track)
  function get_env_act_vis(en)
    local _, act, vis, env_lane
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

function hide_envs(track, sel_env)

  local track_env, send_env, fx_env = get_track_envs(track)
  local vol_vis = r.GetSetEnvelopeInfo_String(track_env.vol, "VISIBLE", "", false)
  if ((sel_env and sel_env~=track_env.vol) or sel_env==nil) and vol_vis == true then 
    set_env_chunk(track_env.vol, false, -1, true, 0, EL_par.env_on_lane) end
  local pan_vis = r.GetSetEnvelopeInfo_String(track_env.pan, "VISIBLE", "", false)
  if ((sel_env and sel_env~=track_env.pan ) or sel_env==nil) and pan_vis == true then 
    set_env_chunk(track_env.pan, false, -1, true, 0, EL_par.env_on_lane) end
  local width_vis = r.GetSetEnvelopeInfo_String(track_env.width, "VISIBLE", "", false)
  if ((sel_env and sel_env~=track_env.width ) or sel_env==nil) and width_vis == true then 
    set_env_chunk(track_env.width, false, -1, true, 0, EL_par.env_on_lane) end
  local volpre_vis = r.GetSetEnvelopeInfo_String(track_env.volpre, "VISIBLE", "", false)
  if ((sel_env and sel_env~=track_env.volpre ) or sel_env==nil) and volpre_vis == true then 
    set_env_chunk(track_env.volpre, false, -1, true, 0, EL_par.env_on_lane) end
  local panpre_vis = r.GetSetEnvelopeInfo_String(track_env.panpre, "VISIBLE", "", false)
  if ((sel_env and sel_env~=track_env.panpre ) or sel_env==nil) and panpre_vis == true then 
    set_env_chunk(track_env.panpre, false, -1, true, 0, EL_par.env_on_lane) end
  local widthpre_vis = r.GetSetEnvelopeInfo_String(track_env.widthpre, "VISIBLE", "", false)
  if ((sel_env and sel_env~=track_env.widthpre ) or sel_env==nil) and widthpre_vis == true then 
    set_env_chunk(track_env.widthpre, false, -1, true, 0, EL_par.env_on_lane) end
  local trim_vis = r.GetSetEnvelopeInfo_String(track_env.trim, "VISIBLE", "", false)
  if ((sel_env and sel_env~=track_env.trim ) or sel_env==nil) and trim_vis == true then 
    set_env_chunk(track_env.trim, false, -1, true, 0, EL_par.env_on_lane) end
  local mute_vis = r.GetSetEnvelopeInfo_String(track_env.mute, "VISIBLE", "", false)
  if ((sel_env and sel_env~=track_env.mute ) or sel_env==nil) and mute_vis == true then 
    set_env_chunk(track_env.mute, false, -1, true, 0, EL_par.env_on_lane) end
  if #send_env>0 then
    for i=1,#send_env do
      for j=1,3 do
        local env = send_env[i].env[j].env
        local vis = send_env[i].env[j].vis
        if ((sel_env and sel_env~=env) or sel_env==nil) and vis == "1" then
          set_env_chunk(env, false, -1, true, 0, EL_par.env_on_lane) end
      end
    end
  end
  if #fx_env>0 then
    for i=1,#fx_env do
      for j=1,fx_env[i].par_num do
        local env = fx_env[i].env[j].env
        local vis = fx_env[i].env[j].vis
        if ((sel_env and sel_env~=env) or sel_env==nil) and vis == "1" then 
          set_env_chunk(env, false, -1, true, 0, EL_par.env_on_lane) end
      end
    end
  end
end

function get_razor_areas()
  local razor_table = {}
  local rt
  local sel_env = r.GetSelectedEnvelope(0) 
  local sel_env_ptrack
  if sel_env then
    sel_env_ptrack = r.GetEnvelopeInfo_Value(sel_env, "P_TRACK")
  end

  local count_track = r.CountTracks(0)

  local raz_sel_env -- selected envelope
  local raz_sel_ptrack

  for i=0, count_track-1 do
    local track = r.GetTrack(0, i)
    local ok, area = r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", false)
    if ok and area ~= "" then
      local st, en, env
      local re ={}
      for st, en, env in string.gmatch(area, "(%S+) (%S+) (%S+)") do
        rt = true
        re[#re+1] = {st = tonum(st), en = tonum(en), env = env}

        if not raz_sel_env and sel_env_ptrack and track==sel_env_ptrack then
          raz_sel_env=sel_env
          raz_sel_ptrack=sel_env_ptrack
        end

      end
      local track_env, send_env, fx_env = get_track_envs(track)
      razor_table[#razor_table+1] ={track=track, track_env=track_env, send_env=send_env, fx_env=fx_env, razor_edits=re}
    else
      if EL_par.auto_vis_off==1 then
        hide_envs(track) -- hides envs for tracks with no razors
      end
    end
  end
  return rt, razor_table, raz_sel_env, raz_sel_ptrack
end

function move_razors_to_lane(track, env, env_lane, razor_edits)
  local _, env_guid
  if env_lane==1 then
    _, env_guid = r.GetSetEnvelopeInfo_String(env, "GUID", "", false)
    env_guid = '"'..env_guid..'"'
  else
    env_guid = ""
  end
  local re = {}
  local str = ""
  for j=1,#razor_edits do
    re[j] = {st=razor_edits[j].st, en=razor_edits[j].en, env=env_guid}
    str = str..tostring(razor_edits[j].st).." "..tostring(razor_edits[j].en).." "..env_guid
    if j~=#razor_edits then str = str.." " end
  end
  r.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", str, true)
  return re
end

function Main()

  -- local str = r.GetExtState("McS-Tools", "EnvoyLope")
  -- r.SetExtState("McS-Tools", "EnvoyLope", "", false)
  -- if str==nil then return end

  local rt_pr = restore_EL_par_from_project_ext(r.EnumProjects(-1))
  if not rt_pr then
    local rt_gl = restore_EL_par_from_global_ext()
  end
  if EL_par.env_menu==nil then return end
  if mcs_gl_envoylope_command==nil then return end

  cmd = recognize_command(mcs_gl_envoylope_command)

  razor.rt, razor.table, razor.sel_env, razor.sel_env_ptrack = get_razor_areas()
	if razor.rt==nil then return end

  local val_in, db_or_perc_in, env_chunk_name_in, track_send_fx_in, bypass_par
  local send_idx_in, send_dest_track_in
  local fx_idx_in, fx_par_idx_in, fx_par_num_in, fx_name_in
  local auto_act_on, auto_vis_on

  if EL_par.env_menu == 9 then
    cmd.sel_env = razor.sel_env
    cmd.sel_env_ptrack = razor.sel_env_ptrack
    if cmd.sel_env~=nil then
      env_chunk_name_in, track_send_fx_in, send_idx_in, send_dest_track_in, fx_idx_in, fx_par_idx_in, fx_par_num_in, fx_name_in, bypass_par = get_env_chunk_name_and_send_idx(cmd.sel_env, cmd.sel_env_ptrack)
      if env_chunk_name_in=="<VOLENV" or env_chunk_name_in=="<VOLENV2" or env_chunk_name_in=="<VOLENV3" or env_chunk_name_in=="<AUXVOLENV" then
        db_or_perc_in = 1
        val_in = cmd.val_db
      else
        db_or_perc_in = 2
        val_in = cmd.val_perc
      end
    end
  else
    env_chunk_name_in = env_chunkname[EL_par.env_menu]
    if EL_par.env_menu==1 or EL_par.env_menu==4 or EL_par.env_menu==8 then
      db_or_perc_in = 1
      val_in = cmd.val_db
    else
      db_or_perc_in = 2
      val_in = cmd.val_perc
	    if EL_par.env_menu==7 then bypass_par=1 end
    end
    if EL_par.auto_act_on==1 then auto_act_on=true end
    if EL_par.auto_vis_on==1 then auto_vis_on=true end
  end

  if cmd.undo==1 then
    r.Undo_BeginBlock()
  end

  for i=1,#razor.table do
    local track = razor.table[i].track
    local razor_edits = razor.table[i].razor_edits
    local env, env_guid
    if EL_par.env_menu ~= 9 then
      env = r.GetTrackEnvelopeByChunkName(track, env_chunk_name_in)
    else
      if track_send_fx_in==1 then
      	env = find_track_env(i, env_chunk_name_in)
      elseif track_send_fx_in==2 then
        env = find_send_env(i, env_chunk_name_in, send_dest_track_in)
      elseif track_send_fx_in==3 then
        env = find_fx_env(i, fx_name_in, fx_par_num_in, fx_par_idx_in+1)
      end
    end
    if EL_par.respect_lane == 1 then
      if env then
        _, env_guid = r.GetSetEnvelopeInfo_String(env, "GUID", "", false)
        env_guid = '"'..env_guid..'"'
      end
    else
      razor_edits = join_razors(razor_edits)
    end

    if env~=nil then
      local br_env = r.BR_EnvAlloc(env, false)
      local active, visible, armed, inLane, laneHeight, defaultShape, minValue, maxValue, centerValue, type, faderScaling = r.BR_EnvGetProperties(br_env)
      local act_changed, vis_changed
      if auto_act_on and active==false then active=true act_changed=true end
      if auto_vis_on and visible==false then visible=true vis_changed=true end
      local act_val, vis_val
      if active == true then act_val=1 else act_val=0 end
      if visible == true then vis_val=1 else vis_val=0 end
      if act_changed or vis_changed then
        set_env_chunk(env, act_changed, act_val, vis_changed, vis_val, EL_par.env_on_lane, env_chunk_name_in)
        if vis_changed and vis_val==1 then
          razor_edits = move_razors_to_lane(track, env, EL_par.env_on_lane, razor_edits)
        end
      end
      if EL_par.auto_vis_off == 1 then
        hide_envs(track, env) -- hides other envelopes except envon the track
      end
      if (inLane==true and EL_par.env_on_lane==0) or (inLane==false and EL_par.env_on_lane==1) then
        set_env_chunk(env, false, -1, true, vis_val, EL_par.env_on_lane, env_chunk_name_in)
        razor_edits = move_razors_to_lane(track, env, EL_par.env_on_lane, razor_edits)
      end

      if EL_par.act_vis==0 or (EL_par.act_vis==1 and active and visible) then
        for j=1,#razor_edits do
  
          local st = razor_edits[j].st
          local en = razor_edits[j].en
          local env_tr = razor_edits[j].env
          if EL_par.respect_lane==0 or 
            (EL_par.respect_lane==1 and EL_par.env_on_lane==0) or 
            (EL_par.respect_lane==1 and EL_par.env_on_lane==1 and env_tr==env_guid) then
          -- if EL_par.env_menu~=9 or (EL_par.env_menu == 9 and env_tr==env_guid) then

            local p1_time = st-EL_par.envtranstime
            local p2_time = st
            local p3_time = en
            local p4_time = en+EL_par.envtranstime
            local p_time = {p1_time,p2_time,p3_time,p4_time}
    
            local p1 = r.GetEnvelopePointByTime(env, p1_time+inac)
            local p2 = r.GetEnvelopePointByTime(env, p2_time)
            local p3 = r.GetEnvelopePointByTime(env, p3_time)
            local p4 = r.GetEnvelopePointByTime(env, p4_time)
            local p = {p1,p2,p3,p4}
    
            local insert_done = false
            for m=4,1,-1 do
              local retval, time, value, shape, tension, selected = r.GetEnvelopePoint(env, p[m])
              if not in_range_equal(time, p_time[m]-inac,p_time[m]+inac) then
                local retval, value, dVdSOutOptional, ddVdSOutOptional, dddVdSOutOptional = r.Envelope_Evaluate(env, p_time[m],0,0)
                r.InsertEnvelopePoint(env, p_time[m], value, pointshape, 0, false, true)
                insert_done = true
              end
            end
            if insert_done == true then
              r.Envelope_SortPoints(env)
            end
    
            local count_point = r.CountEnvelopePoints(env)
            for k=0, count_point-1 do
              local retval, time, value, shape, tension, selected = r.GetEnvelopePoint(env, k)
    
              if in_range_equal(time,st,en+inac) then
                if db_or_perc_in == 1 then
                  local scale = r.GetEnvelopeScalingMode(env)
                  local new_value = r.ScaleFromEnvelopeMode(scale, value)
                  local val_db = 20*log(new_value,10) + val_in
                  
                  local val
      
                  if value == minValue and val_in > 0 then
                    val = r.ScaleToEnvelopeMode(scale,10^(-150/20))
                  else
                    if val_db < -150 then
                      val = minValue
                      val = r.ScaleToEnvelopeMode(scale,val)
                    elseif val_db > 20*log(maxValue,10) then
                      val = maxValue
                      val = r.ScaleToEnvelopeMode(scale,val)
                    elseif in_range_equal(val_db,-0.01, 0.01) then
                      val = centerValue
                      val = r.ScaleToEnvelopeMode(scale,val)
                    else
                      val = r.ScaleToEnvelopeMode(scale,10^(val_db/20))
                    end
                  end
                  r.SetEnvelopePoint(env, k, time, val, shape, tension, selected, true) -- last true = No Sort Point
                else
                	local val_new
                	if bypass_par==1 then
                		if val_in >= 0 then 
                			val_new = maxValue
                		else
                			val_new = minValue
                		end
                	else
                  	if maxValue < minValue then maxValue, minValue = minValue, maxValue end
                  	local perc_1 = (maxValue - minValue)/100
                  	local val_perc = val_in * perc_1
                  	val_new = value + val_perc
  	
                  	if val_new > maxValue then val_new = maxValue
                  	elseif val_new < minValue then val_new = minValue end
                  end
                  r.SetEnvelopePoint(env, k, time, val_new, shape, tension, selected, true) -- last true = No Sort Point
                end
              end
            end
          end
        end
        r.BR_EnvFree(br_env, 1)
        r.Envelope_SortPoints(env)
      end
    end
  end

  if cmd.undo==1 then
    r.Undo_EndBlock("McS - EnvoyLope - Change Value", -1)
  else
    no_undo()
  end
end


Main()
r.UpdateArrange()

