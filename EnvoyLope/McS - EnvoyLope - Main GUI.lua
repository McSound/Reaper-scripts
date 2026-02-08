 --@ description: Main Envoylope script you shoud run.
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

local font_size_main = 14-- change this font size to increase or reduce overall GUI size

local r = reaper
local floor = math.floor
local log = math.log
local huge = math.huge
local format = string.format
local tonum = tonumber
local tostr = tostring

local window_flags, collapsed, docked, gotoexit = nil

local MBR_was_clicked = false

local ctrl
local shift
local alt
local super

function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end

function no_undo() r.defer(function()end) end

package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return floor(num * mult + 0.5) / mult
end

local razor = {rt=nil, table={}, sel_env=nil, sel_env_ptrack=nil}

local inac = 0.0001--0.00000001
local retval, envtrt = r.get_config_var_string("envtranstime")
envtrt = tonum(envtrt)

local env_menu_name = {"Volume","Pan","Width","Volume(Pre-FX)","Pan(Pre-FX)","Width(Pre-FX)","Mute","Trim Volume","Selected Env"}
local env_chunkname = {"<VOLENV2","<PANENV2","<WIDTHENV2","<VOLENV","<PANENV","<WIDTHENV","<MUTEENV","<VOLENV3","SEL"}

local EL_check = {state_curr=nil, state_prev=nil}
local EL_preset = {
      {nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil},
      {nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil},
      {nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil},
      {nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil},
      {nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil},
      restored=false, count=5, par_count=17}

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
  respect_lane=1, -- apply changes only on razor ranges on corresponding envelopes
  env_on_lane=1, -- place activated envelope on envelope lane
  envtranstime=envtrt, -- time of transitions of envelope
  project_saved=0 -- if params was saved to current project
  }

local check_time = 0
local project = {curr=nil, prev=nil, state_curr=nil, state_prev=nil, path_curr=nil, path_prev=nil, name_curr=nil, name_prev=nil}

project.state_curr = r.GetProjectStateChangeCount(0)
project.state_prev = project.state_curr-2

local ctx = ImGui.CreateContext("EnvoyLope", ImGui.ConfigFlags_DockingEnable)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 1)

local font_size_add = round(font_size_main/1.15)
local font = ImGui.CreateFont('tahoma', font_size_main)
ImGui.Attach(ctx, font)
local fontI = ImGui.CreateFont('tahoma', font_size_add)--, ImGui.FontFlags_Italic)
ImGui.Attach(ctx, fontI)

function HSV(H, S, V, A)
  local R, G, B = ImGui.ColorConvertHSVtoRGB(H, S, V)
  return ImGui.ColorConvertDouble4ToU32(R, G, B, A or 1.0)
end

local colors={
  transparent = HSV(0.0, 0.0, 0.0, 0.0),

  blackColor = HSV(0.0, 0.0, 0.0),
  grey1 = HSV(0.0, 0.0, 0.1),
  grey12 = HSV(0.0, 0.0, 0.12),
  grey15 = HSV(0.0, 0.0, 0.15),
  grey2 = HSV(0.0, 0.0, 0.2),
  grey3 = HSV(0.0, 0.0, 0.3),
  grey4 = HSV(0.0, 0.0, 0.4),
  grey5 = HSV(0.0, 0.0, 0.5),
  grey6 = HSV(0.0, 0.0, 0.6),
  grey7 = HSV(0.0, 0.0, 0.7),
  grey8 = HSV(0.0, 0.0, 0.8),
  grey85 = HSV(0.0, 0.0, 0.85),
  grey9 = HSV(0.0, 0.0, 0.9),
  grey95 = HSV(0.0, 0.0, 0.95),
  white = HSV(0.0, 0.0, 1.0),

  text_blue = HSV(0.6, 0.75, 0.9),
  buttonColor_blue = HSV(0.6, 0.75, 0.4),
  hoveredColor_blue = HSV(0.6, 0.75, 0.6),
  activeColor_blue = HSV(0.6, 0.75, 0.8),

  FrameColor_blue = HSV(0.6, 0.75, 0.25),
  hoveredFrameColor_blue = HSV(0.6, 0.75, 0.4),
  activeFrameColor_blue = HSV(0.6, 0.75, 0.6),

  buttonColor_red = HSV(0.0, 1.0, 0.4),
  hoveredColor_red = HSV(0.0, 1.0, 0.6),
  activeColor_red = HSV(0.0, 1.0, 0.9),

  text_green = HSV(0.3, 0.7, 0.9),
  buttonColor_green = HSV(0.3, 0.7, 0.35),
  hoveredColor_green = HSV(0.3, 0.7, 0.5),
  activeColor_green = HSV(0.3, 0.7, 0.6),

  buttonColor_darkgreen = HSV(0.28, 0.7, 0.2),
  hoveredColor_darkgreen = HSV(0.28, 0.7, 0.4),
  activeColor_darkgreen = HSV(0.28, 0.7, 0.6),

  buttonColor_grey = HSV(0.0, 0.0, 0.3),
  hoveredColor_grey = HSV(0.0, 0.0, 0.5),
  activeColor_grey = HSV(0.0, 0.0, 0.7),

  buttonColor_darkgrey = HSV(0.0, 0.0, 0.15),
  hoveredColor_darkgrey = HSV(0.0, 0.0, 0.3),
  activeColor_darkgrey = HSV(0.0, 0.0, 0.5),

  text_violet = HSV(0.75, 0.9, 0.9),
  buttonColor_violet = HSV(0.75, 0.9, 0.4),
  hoveredColor_violet = HSV(0.75, 0.9, 0.6),
  activeColor_violet = HSV(0.75, 0.9, 0.8),

  text_pink = HSV(0.85, 0.7, 0.9),
  buttonColor_pink = HSV(0.85, 0.7, 0.4),
  hoveredColor_pink = HSV(0.85, 0.7, 0.6),
  activeColor_pink = HSV(0.85, 0.7, 0.8),

  text_marine = HSV(0.5, 0.6, 0.8),
  buttonColor_marine = HSV(0.5, 0.6, 0.4),
  hoveredColor_marine = HSV(0.5, 0.6, 0.6),
  activeColor_marine = HSV(0.5, 0.6, 0.8),

  text_yellow = HSV(0.13, 0.7, 0.9),
  buttonColor_yellow = HSV(0.13, 0.7, 0.4),
  hoveredColor_yellow = HSV(0.13, 0.7, 0.6),
  activeColor_yellow = HSV(0.13, 0.7, 0.8),

  text_brown = HSV(0.07, 0.8, 0.9),
  buttonColor_brown = HSV(0.07, 0.8, 0.4),
  hoveredColor_brown = HSV(0.07, 0.8, 0.6),
  activeColor_brown = HSV(0.07, 0.8, 0.8),

  text_orange = HSV(0.07, 0.75, 0.9),
  buttonColor_orange = HSV(0.07, 0.75, 0.4),
  hoveredColor_orange = HSV(0.07, 0.75, 0.6),
  activeColor_orange = HSV(0.07, 0.75, 0.8),
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

function concat_EL_par(mode)

  local str = ""
  if mode == "project" then
    str = EL_par.rough[1]..","..EL_par.rough[2]..","..EL_par.fine[1]..","..EL_par.fine[2]..","..EL_par.tiny[1]..","..
    EL_par.tiny[2]..","..EL_par.undo_keyb..","..EL_par.undo_mouse..","..EL_par.act_vis..","..EL_par.env_menu..","..
    EL_par.auto_act_on..","..EL_par.auto_vis_on..","..EL_par.auto_vis_off..","..EL_par.auto_on_razor..","..
    EL_par.respect_lane..","..EL_par.env_on_lane..","..EL_par.envtranstime
  elseif mode == "global" then
    str = EL_par.rough[1]..","..EL_par.rough[2]..","..EL_par.fine[1]..","..EL_par.fine[2]..","..EL_par.tiny[1]..","..
    EL_par.tiny[2]..","..EL_par.undo_keyb..","..EL_par.undo_mouse..","..EL_par.act_vis..","..EL_par.env_menu..","..
    EL_par.auto_act_on..","..EL_par.auto_vis_on..","..EL_par.auto_vis_off..","..EL_par.auto_on_razor..","..
    EL_par.respect_lane..","..EL_par.env_on_lane
  end
  return str
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

function save_EL_par_to_global_ext()
  local str = concat_EL_par("global")
  r.SetExtState("McS-Tools", "EnvoyLope_params", str, true)
end

function save_EL_par_to_project_ext(proj)
  local str = concat_EL_par("project")
  r.SetProjExtState(proj, "McS - EnvoyLope_params", "saved_params", str)
end

function remove_EL_par_from_project_ext(proj)
  r.SetProjExtState(proj, "McS - EnvoyLope_params", "saved_params", "")
end

function restore_EL_preset_from_global()
  local str
  if r.HasExtState("McS-Tools", "EnvoyLope_presets") then
    str = r.GetExtState("McS-Tools", "EnvoyLope_presets")
  else
    save_EL_preset_to_global()
    EL_preset.restored = true
    return
  end
  if str then
    local num = 1
    local preset=1
    for val in str:gmatch("([^,]+)") do
      if val=="nil" then
        EL_preset[preset][num] = nil
      else
        EL_preset[preset][num] = tonum(val)
      end
      if num==EL_preset.par_count then
        num=1
        preset=preset+1
      else
        num=num+1
      end
    end
    EL_preset.restored = true
  end
  if str then return true else return false end
end

function save_EL_preset_to_global()
  local str = ""
  for i=1,EL_preset.count do
    for j=1,EL_preset.par_count do
      local txt
      if EL_preset[i][j] == nil then
        txt="nil"
      else
        txt=tostr(EL_preset[i][j])
      end
      str=str..txt
      
      if i==EL_preset.count and j==EL_preset.par_count then
      else
        str=str.."," 
      end
    end
  end
  r.SetExtState("McS-Tools", "EnvoyLope_presets", str, true)
end

function restore_EL_preset(num)
  if EL_preset[num][1] ~= nil then
    for i=1,EL_preset.par_count do
      assign_EL_par(i, EL_preset[num][i])
    end
  end
end

function save_EL_preset(num)
  EL_preset[num][1]= EL_par.rough[1]
  EL_preset[num][2] = EL_par.rough[2]
  EL_preset[num][3] = EL_par.fine[1]
  EL_preset[num][4] = EL_par.fine[2]
  EL_preset[num][5] = EL_par.tiny[1]
  EL_preset[num][6] = EL_par.tiny[2]
  EL_preset[num][7] = EL_par.undo_keyb
  EL_preset[num][8] = EL_par.undo_mouse
  EL_preset[num][9] = EL_par.act_vis
  EL_preset[num][10] = EL_par.env_menu
  EL_preset[num][11] = EL_par.auto_act_on
  EL_preset[num][12] = EL_par.auto_vis_on
  EL_preset[num][13] = EL_par.auto_vis_off
  EL_preset[num][14] = EL_par.auto_on_razor
  EL_preset[num][15] = EL_par.respect_lane
  EL_preset[num][16] = EL_par.env_on_lane
  EL_preset[num][17] = EL_par.envtranstime
  save_EL_preset_to_global()
end

function remove_EL_preset(num)
  for i=1,EL_preset.par_count do
    EL_preset[num][i] = nil
  end
  save_EL_preset_to_global()
end

function limit(val, min, max)
  if val<min then val=min elseif val>max then val=max end
  return val
end

function applyMouseWheel(rft, db_or_perc, val, mwheel_val)
  local ret_v = val
  local v = {{1,1},{0.5,0.5},{0.1,0.1}} -- applied values in three areas R F T
  local v_add = v[rft][db_or_perc]
  local sign = 1
  if mwheel_val<0 then sign =-1 end
  if ctrl then
    if not alt and not shift and not super then
      ret_v = limit(val + v_add*sign, 0, 100)
    elseif not alt and shift and not super then
      v_add = v_add/2
      ret_v = limit(val + v_add*sign, 0, 100)
    end
  end
  return ret_v
end

function framework()

  local mw = {x=nil,y=nil,w=nil,h=nil}
  mw.x, mw.y = ImGui.GetWindowPos(ctx)
  mw.w, mw.h = ImGui.GetWindowSize(ctx)

  if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then
    gotoexit = true
  end

  if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseClicked(ctx, 1) then
    MBR_was_clicked = true
  end
  if MBR_was_clicked and ImGui.IsMouseReleased(ctx, 1) then
    r.SetCursorContext(1)
    MBR_was_clicked = false
  end
  -- if ImGui.IsWindowFocused(ctx) and ImGui.IsKeyPressed(ctx, ImGui.Key_Enter, false) then
    -- r.SetCursorContext(1)
  -- end

  local mwheel_val = r.ImGui_GetMouseWheel(ctx)

  ctrl = r.JS_Mouse_GetState(4) == 4 --CTRL
  shift = r.JS_Mouse_GetState(8) == 8 --SHIFT
  alt = r.JS_Mouse_GetState(16) == 16 --ALT
  super = r.JS_Mouse_GetState(32) == 32 --WIN

  ------ All Logic ------
  
  project.state_curr = r.GetProjectStateChangeCount(0)
  local project_state_changed

  if project.state_curr ~= project.state_prev then -- no need to update razors info if project state is only raised by 1
    project_state_changed = true
    project.state_prev = project.state_curr

    ---- Check for Current Project Change ----
    project.curr = r.EnumProjects(-1)
    project.path_curr = r.GetProjectPathEx(project.curr)
    project.name_curr = r.GetProjectName(project.curr)

    if project.prev==nil or project.curr~=project.prev or 
       project.path_curr~=project.path_prev or project.name_curr~=project.name_prev then
      project.prev = project.curr
      project.path_prev = project.path_curr
      project.name_prev = project.name_curr
      local rt_pr = restore_EL_par_from_project_ext(project.curr)
      if not rt_pr then
        local rt_gl = restore_EL_par_from_global_ext()
        if not rt_gl then
          save_EL_par_to_global_ext()
        end
      end
    end
  end

  ------ GUI ------

  docked = ImGui.IsWindowDocked(ctx)

  local space = round(font_size_main/4)
  local space_sm = round(font_size_main/8)
  local space_y_init = space

  ImGui.SetCursorPosX(ctx, space)
  if not docked then
    space_y_init = space+font_size_main+4
    -- space_y_init = space+round(font_size_main*1.25)
  end
  ImGui.SetCursorPosY(ctx, space_y_init)

  local wd, ht = ImGui.CalcTextSize(ctx, "  0.00  ")
  local input_text_flags = ImGui.InputTextFlags_EnterReturnsTrue | ImGui.InputTextFlags_CharsDecimal

  local draw_list = ImGui.GetWindowDrawList(ctx)
  local mouse_x, mouse_y = ImGui.GetMousePos(ctx)

  ----Rough DB----
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
  ImGui.PushFont(ctx, fontI)
  ImGui.LabelText(ctx, "##rough_lb","R")
  ImGui.PopFont(ctx)
  ImGui.PopStyleColor(ctx)

  local r_wd = ImGui.CalcTextSize(ctx, "R")


  local f_txt = format("%.2f",tostr(EL_par.rough[1]))
  local wd_t = ImGui.CalcTextSize(ctx, f_txt)
  local x_sh = wd/2-wd_t/2
  local mouse_hover, rect_color = false, colors.FrameColor_blue
  local mouse_hover_curs
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm, mw.x+space+r_wd+space_sm+wd) and 
     in_range_equal(mouse_y, mw.y+space_y_init, mw.y+space_y_init+ht) then
    mouse_hover = true
    rect_color = colors.hoveredFrameColor_blue
  end
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm, mw.x+space+r_wd+space_sm+wd+x_sh) and 
     in_range_equal(mouse_y, mw.y+space_y_init, mw.y+space_y_init+ht) then
    mouse_hover_curs = true
  end
  ImGui.DrawList_AddRectFilled(draw_list,
    mw.x+space+r_wd+space_sm, 
    mw.y+space_y_init, 
    mw.x+space+r_wd+space_sm+wd, 
    mw.y+space_y_init+ht, 
    rect_color,
    2.0)

  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+x_sh)
  ImGui.SetNextItemWidth(ctx, wd)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.text_yellow)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, colors.hoveredFrameColor_blue)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, colors.hoveredFrameColor_blue)


  local r_rt_db, text = ImGui.InputText(ctx, "##rough_db", f_txt, input_text_flags)
  ImGui.PopStyleColor(ctx,4)

  if r_rt_db then
    EL_par.rough[1] = tonum(text)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end
  if mouse_hover_curs then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Arrow)
  end
  if mouse_hover and ImGui.IsMouseDown(ctx, 1) then
    ImGui.SetTooltip(ctx, "ROUGH DB value to be applied to envelope\nAppplies to envelopes with Volume parameter")
  end
  if mouse_hover and mwheel_val~=0 then
    EL_par.rough[1] = applyMouseWheel(1, 1, EL_par.rough[1], mwheel_val)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end

  ----Fine DB----
  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+wd+space*2)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
  ImGui.PushFont(ctx, fontI)
  ImGui.LabelText(ctx, "##fine_lb","F")
  ImGui.PopFont(ctx)
  ImGui.PopStyleColor(ctx)

  local f_wd = ImGui.CalcTextSize(ctx, "F")

  local f_txt = format("%.2f",tostr(EL_par.fine[1]))
  local wd_t = ImGui.CalcTextSize(ctx, f_txt)
  local x_sh = wd/2-wd_t/2
  local mouse_hover, rect_color = false, colors.FrameColor_blue
  local mouse_hover_curs
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd) and 
     in_range_equal(mouse_y, mw.y+space_y_init, mw.y+space_y_init+ht) then
    mouse_hover = true
    rect_color = colors.hoveredFrameColor_blue
  end
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+x_sh) and 
     in_range_equal(mouse_y, mw.y+space_y_init, mw.y+space_y_init+ht) then
    mouse_hover_curs = true
  end
  ImGui.DrawList_AddRectFilled(draw_list,
    mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm, 
    mw.y+space_y_init, 
    mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd, 
    mw.y+space_y_init+ht, 
    rect_color, 
    2.0)

  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+wd+space*2+f_wd+space_sm+x_sh)
  ImGui.SetNextItemWidth(ctx, wd)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.text_yellow)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, colors.transparent)


  local f_rt_db, text = ImGui.InputText(ctx, "##fine_db", f_txt, input_text_flags)
  ImGui.PopStyleColor(ctx,4)
  if f_rt_db then
    EL_par.fine[1] = tonum(text)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end
  if mouse_hover_curs then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Arrow)
  end
  if mouse_hover and ImGui.IsMouseDown(ctx, 1) then
    ImGui.SetTooltip(ctx, "FINE DB value to be applied to envelope\nAppplies to envelopes with Volume parameter")
  end
  if mouse_hover and mwheel_val~=0 then
    EL_par.fine[1] = applyMouseWheel(2, 1, EL_par.fine[1], mwheel_val)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end

  ----Tiny DB----
  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
  ImGui.PushFont(ctx, fontI)
  ImGui.LabelText(ctx, "##tiny_lb","T")
  ImGui.PopFont(ctx)
  ImGui.PopStyleColor(ctx)

  local t_wd = ImGui.CalcTextSize(ctx, "T")

  local f_txt = format("%.2f",tostr(EL_par.tiny[1]))
  local wd_t = ImGui.CalcTextSize(ctx, f_txt)
  local x_sh = wd/2-wd_t/2
  local mouse_hover, rect_color = false, colors.FrameColor_blue
  local mouse_hover_curs
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd) and 
     in_range_equal(mouse_y, mw.y+space_y_init, mw.y+space_y_init+ht) then
    mouse_hover = true
    rect_color = colors.hoveredFrameColor_blue
  end
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd+x_sh) and 
     in_range_equal(mouse_y, mw.y+space_y_init, mw.y+space_y_init+ht) then
    mouse_hover_curs = true
  end
  ImGui.DrawList_AddRectFilled(draw_list,
    mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm, 
    mw.y+space_y_init, 
    mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd, 
    mw.y+space_y_init+ht, 
    rect_color, 
    2.0)

  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+x_sh)
  ImGui.SetNextItemWidth(ctx, wd)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.text_yellow)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, colors.transparent)


  local t_rt_db, text = ImGui.InputText(ctx, "##tiny_db", f_txt, input_text_flags)
  ImGui.PopStyleColor(ctx,4)
  if t_rt_db then
    EL_par.tiny[1] = tonum(text)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end
  if mouse_hover_curs then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Arrow)
  end
  if mouse_hover and ImGui.IsMouseDown(ctx, 1) then
    ImGui.SetTooltip(ctx, "TINY DB value to be applied to envelope\nAppplies to envelopes with Volume parameter")
  end
  if mouse_hover and mwheel_val~=0 then
    EL_par.tiny[1] = applyMouseWheel(3, 1, EL_par.tiny[1], mwheel_val)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end

  ----DB----
  local db_wd = ImGui.CalcTextSize(ctx, "db")
  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd+space)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
  ImGui.LabelText(ctx, "##DB","db")
  ImGui.PopStyleColor(ctx)

  local menu_wd, menu_ht = ImGui.CalcTextSize(ctx, " Volume(Pre-FX) ")
  local menu_x=space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd+space+db_wd+space*2

  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd+space+db_wd+space*2)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey9)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, colors.FrameColor_blue)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, colors.hoveredFrameColor_blue)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, colors.activeFrameColor_blue)
  local menu_rt = ImGui.Button(ctx, env_menu_name[EL_par.env_menu].."##menu", menu_wd, menu_ht)
  ImGui.PopStyleColor(ctx,4)
  if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDown(ctx, 1) then
    ImGui.SetTooltip(ctx, "Menu for choosing Envelope to work with\nWhen 'Selected envelope' is chosen, envelope lane must be selected at first")
  end
  if menu_rt then
    r.ImGui_OpenPopup(ctx, "envelope_menu", r.ImGui_PopupFlags_NoOpenOverExistingPopup())
  end
  if ImGui.IsItemHovered(ctx) and mwheel_val~=0 and ctrl then
    local val = EL_par.env_menu
    if mwheel_val>0 then val=val-1 else val=val+1 end
    EL_par.env_menu = limit(val, 1, 9)

    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end

  if r.ImGui_BeginPopup(ctx, "envelope_menu") then

    local sel = {false,false,false,false,false,false,false,false,false}
    sel[EL_par.env_menu] = true

    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_SelectableTextAlign(), 0.5, 0)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), colors.grey8)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), colors.grey2)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), colors.grey2)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), colors.grey5)
    for i=1,9 do
      local rt = ImGui.Selectable(ctx, env_menu_name[i], sel[i])
      if rt then 
        EL_par.env_menu=i
        if EL_par.project_saved==0 then
          save_EL_par_to_global_ext()
        else
          save_EL_par_to_project_ext(project.curr)
        end
        r.SetCursorContext(1)
      end
    end

    r.ImGui_PopStyleColor(ctx, 4)
    r.ImGui_PopStyleVar(ctx, 1)
    r.ImGui_EndPopup(ctx)
  end

  local x_before = space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd+space+db_wd+space*2+menu_wd+space*2
  local bt_w, bt_h = ImGui.CalcTextSize(ctx, " if act&vis ")
  local col = {
      {colors.grey9, colors.buttonColor_green, colors.hoveredColor_green, colors.activeColor_green},
      {colors.grey9, colors.buttonColor_green, colors.hoveredColor_green, colors.activeColor_green},
      {colors.grey9, colors.buttonColor_green, colors.hoveredColor_green, colors.activeColor_green},
      {colors.grey9, colors.buttonColor_green, colors.hoveredColor_green, colors.activeColor_green},
    }
  for i=1,4 do

    local name, color = "", {}
    if i==1 then 
      name="undo kb"
      if EL_par.undo_keyb==0 then
        col[i][1]=colors.grey5
        col[i][2]=colors.grey12
        col[i][3]=colors.grey12
        col[i][4]=colors.grey12
      end
    elseif i==2 then 
      name="undo ms"
      if EL_par.undo_mouse==0 then
        col[i][1]=colors.grey5
        col[i][2]=colors.grey12
        col[i][3]=colors.grey12
        col[i][4]=colors.grey12
      end
    elseif i==3 then 
      name="if act&vis"
      if EL_par.act_vis==0 then
        col[i][1]=colors.grey5
        col[i][2]=colors.grey12
        col[i][3]=colors.grey12
        col[i][4]=colors.grey12
      end
    elseif i==4 then 
      name="resp lane"
      if EL_par.respect_lane==0 then
        col[i][1]=colors.grey5
        col[i][2]=colors.grey12
        col[i][3]=colors.grey12
        col[i][4]=colors.grey12
      end
    end


    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, x_before + (bt_w+space*2)*(i-1))
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col[i][1])
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col[i][2])
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col[i][3])
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col[i][4])
    local rt = ImGui.Button(ctx, name.."##opt"..i, bt_w, bt_h)
    ImGui.PopStyleColor(ctx,4)
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDown(ctx, 1) then
      if name=="undo kb" then
        ImGui.SetTooltip(ctx, "Switch, enables undo for EnvoyLope keyboard actions")
      elseif name=="undo ms" then
        ImGui.SetTooltip(ctx, "Switch, enables undo for EnvoyLope mouse actions")
      elseif name=="if act&vis" then
        ImGui.SetTooltip(ctx, "Switch, enables changing envelope if only it's active and visible\nfor all envelopes in Env Menu except 'Selected env'")
      elseif name=="resp lane" then
        ImGui.SetTooltip(ctx, "Switch, if On - enables changing envelope only if there's razor on its lane (respect lane)\n If Off - then any razor on track or any envelope lane will be taken in account and summed if few")
      end
    end
    if rt then
      if i==1 then EL_par.undo_keyb = 1-EL_par.undo_keyb
      elseif i==2 then EL_par.undo_mouse = 1-EL_par.undo_mouse
      elseif i==3 then EL_par.act_vis = 1-EL_par.act_vis EL_par.auto_act_on=0 EL_par.auto_vis_on=0
      elseif i==4 then EL_par.respect_lane = 1-EL_par.respect_lane end
      if EL_par.project_saved==0 then
        save_EL_par_to_global_ext()
      else
        save_EL_par_to_project_ext(project.curr)
      end
      r.SetCursorContext(1)
    end
  end

  local pres1_w = ImGui.CalcTextSize(ctx, " 10 ")
  local pres_w = pres1_w*5 + space*4
  -- local sp_w = ImGui.CalcTextSize(ctx, " Save to Poject ")
  local col = {colors.grey9, colors.buttonColor_violet, colors.hoveredColor_violet, colors.activeColor_violet}
  local txt = "Saving to Poject"
  if EL_par.project_saved==0 then
    col = {colors.grey5, colors.grey12, colors.grey12, colors.grey12}
    txt = "Global params"
  end
  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, x_before + (bt_w+space*2)*4)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, col[1])
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, col[2])
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col[3])
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col[4])
  local rt_sp = ImGui.Button(ctx, txt.."##opt_sp", pres_w, bt_h)
  ImGui.PopStyleColor(ctx,4)

  if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDown(ctx, 1) then
    if EL_par.project_saved==0 then
      ImGui.SetTooltip(ctx, "All params are saving as Global\nCtrl+LMB - start to save params to current project\nAlt+LMB - remove params from current project. Global params will load")
    else
      ImGui.SetTooltip(ctx, "All params are saving to current Project automatically\nCtrl+LMB - start to save params to current project\nAlt+LMB - remove params from current project. Global params will load")
    end
  end

  if rt_sp then
    -- if not shift and not ctrl and not alt and not super then
      -- if EL_par.project_saved == 1 then
        -- restore_EL_par_from_project_ext(project.curr)
      -- end
    if not shift and ctrl and not alt and not super then
      EL_par.project_saved = 1
      save_EL_par_to_project_ext(project.curr)
    elseif not shift and not ctrl and alt and not super then
      EL_par.project_saved = 0
      remove_EL_par_from_project_ext(project.curr)
      restore_EL_par_from_global_ext()
    end
    r.SetCursorContext(1)
  end

  ImGui.SetCursorPosY(ctx, space_y_init+ht+space)

  ----Rough %----
  local f_txt = format("%.2f",tostr(EL_par.rough[2]))
  local wd_t = ImGui.CalcTextSize(ctx, f_txt)
  local x_sh = wd/2-wd_t/2
  local mouse_hover, rect_color = false, colors.FrameColor_blue
  local mouse_hover_curs
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm, mw.x+space+r_wd+space_sm+wd) and 
     in_range_equal(mouse_y, mw.y+space_y_init+ht+space, mw.y+space_y_init+ht+space+ht) then
    mouse_hover = true
    rect_color = colors.hoveredFrameColor_blue
  end
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm, mw.x+space+r_wd+space_sm+wd+x_sh) and 
     in_range_equal(mouse_y, mw.y+space_y_init+ht+space, mw.y+space_y_init+ht+space+ht) then
    mouse_hover_curs = true
  end
  ImGui.DrawList_AddRectFilled(draw_list,
    mw.x+space+r_wd+space_sm, 
    mw.y+space_y_init+ht+space, 
    mw.x+space+r_wd+space_sm+wd, 
    mw.y+space_y_init+ht+space+ht, 
    rect_color,
    2.0)

  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+x_sh)
  ImGui.SetNextItemWidth(ctx, wd)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.text_marine)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, colors.transparent)


  local r_rt_pr, text = ImGui.InputText(ctx, "##rough_%", f_txt, input_text_flags)
  ImGui.PopStyleColor(ctx,4)
  if r_rt_pr then
    EL_par.rough[2] = tonum(text)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end

  if mouse_hover_curs then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Arrow)
  end
  if mouse_hover and ImGui.IsMouseDown(ctx, 1) then
    ImGui.SetTooltip(ctx, "ROUGH % value to be applied to envelope\nAppplies to envelopes with parameter other than Volume")
  end
  if mouse_hover and mwheel_val~=0 then
    EL_par.rough[2] = applyMouseWheel(1, 2, EL_par.rough[2], mwheel_val)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end


  ----Fine %----
  local f_txt = format("%.2f",tostr(EL_par.fine[2]))
  local wd_t = ImGui.CalcTextSize(ctx, f_txt)
  local x_sh = wd/2-wd_t/2
  local mouse_hover, rect_color = false, colors.FrameColor_blue
  local mouse_hover_curs
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd) and 
     in_range_equal(mouse_y, mw.y+space_y_init+ht+space, mw.y+space_y_init+ht+space+ht) then
    mouse_hover = true
    rect_color = colors.hoveredFrameColor_blue
  end
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+x_sh) and 
     in_range_equal(mouse_y, mw.y+space_y_init+ht+space, mw.y+space_y_init+ht+space+ht) then
    mouse_hover_curs = true
  end
  ImGui.DrawList_AddRectFilled(draw_list,
    mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm,
    mw.y+space_y_init+ht+space, 
    mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd,
    mw.y+space_y_init+ht+space+ht, 
    rect_color,
    2.0)

  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+wd+space*2+f_wd+space_sm+x_sh)
  ImGui.SetNextItemWidth(ctx, wd)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.text_marine)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, colors.transparent)


  local r_rt_pr, text = ImGui.InputText(ctx, "##fine_%", f_txt, input_text_flags)
  ImGui.PopStyleColor(ctx,4)
  if r_rt_pr then
    EL_par.fine[2] = tonum(text)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end
  if mouse_hover_curs then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Arrow)
  end
  if mouse_hover and ImGui.IsMouseDown(ctx, 1) then
    ImGui.SetTooltip(ctx, "FINE % value to be applied to envelope\nAppplies to envelopes with parameter other than Volume")
  end
  if mouse_hover and mwheel_val~=0 then
    EL_par.fine[2] = applyMouseWheel(2, 2, EL_par.fine[2], mwheel_val)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end

  ----Tiny %----
  local f_txt = format("%.2f",tostr(EL_par.tiny[2]))
  local wd_t = ImGui.CalcTextSize(ctx, f_txt)
  local x_sh = wd/2-wd_t/2
  local mouse_hover, rect_color = false, colors.FrameColor_blue
  local mouse_hover_curs
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd) and 
     in_range_equal(mouse_y, mw.y+space_y_init+ht+space, mw.y+space_y_init+ht+space+ht) then
    mouse_hover = true
    rect_color = colors.hoveredFrameColor_blue
  end
  if in_range_equal(mouse_x, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm, mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd+x_sh) and 
     in_range_equal(mouse_y, mw.y+space_y_init+ht+space, mw.y+space_y_init+ht+space+ht) then
    mouse_hover_curs = true
  end
  ImGui.DrawList_AddRectFilled(draw_list,
    mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm, 
    mw.y+space_y_init+ht+space, 
    mw.x+space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd, 
    mw.y+space_y_init+ht+space+ht, 
    rect_color,
    2.0)

  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+x_sh)
  ImGui.SetNextItemWidth(ctx, wd)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.text_marine)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, colors.transparent)


  local r_rt_pr, text = ImGui.InputText(ctx, "##tiny_%", f_txt, input_text_flags)
  ImGui.PopStyleColor(ctx,4)
  if r_rt_pr then
    EL_par.tiny[2] = tonum(text)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end
  if mouse_hover_curs then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Arrow)
  end
  if mouse_hover and ImGui.IsMouseDown(ctx, 1) then
    ImGui.SetTooltip(ctx, "TINY % value to be applied to envelope\nAppplies to envelopes with parameter other than Volume")
  end
  if mouse_hover and mwheel_val~=0 then
    EL_par.tiny[2] = applyMouseWheel(3, 2, EL_par.tiny[2], mwheel_val)
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end

  ----%----
  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, space+r_wd+space_sm+wd+space*2+f_wd+space_sm+wd+space*2+t_wd+space_sm+wd+space)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
  ImGui.LabelText(ctx, "##DB","%")
  ImGui.PopStyleColor(ctx)

  ----EnvTransTime----

  local f_txt = format("%.2f",tostr(EL_par.envtranstime*1000)).." trans time"
  local wd_t = ImGui.CalcTextSize(ctx, f_txt)
  if wd_t > menu_wd then
    f_txt = format("%.2f",tostr(EL_par.envtranstime*1000)).." tt"
    wd_t = ImGui.CalcTextSize(ctx, f_txt)
  end
  local x_sh = menu_wd/2-wd_t/2
  local mouse_hover, rect_color = false, colors.FrameColor_blue
  local mouse_hover_curs
  if in_range_equal(mouse_x, mw.x+menu_x, mw.x+menu_x+menu_wd) and 
     in_range_equal(mouse_y, mw.y+space_y_init+ht+space, mw.y+space_y_init+ht+space+ht) then
    mouse_hover = true
    rect_color = colors.hoveredFrameColor_blue
  end
  if in_range_equal(mouse_x, mw.x+menu_x, mw.x+menu_x+menu_wd+x_sh) and 
     in_range_equal(mouse_y, mw.y+space_y_init+ht+space, mw.y+space_y_init+ht+space+ht) then
    mouse_hover_curs = true
  end
  ImGui.DrawList_AddRectFilled(draw_list,
    mw.x+menu_x, 
    mw.y+space_y_init+ht+space,
    mw.x+menu_x+menu_wd, 
    mw.y+space_y_init+ht+space+ht, 
    rect_color,
    2.0)

  ImGui.SameLine(ctx)
  ImGui.SetCursorPosX(ctx, menu_x+x_sh)
  ImGui.SetNextItemWidth(ctx, menu_wd)

  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, colors.transparent)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, colors.transparent)

  local ett_rt, text = ImGui.InputText(ctx, "##ett", f_txt, input_text_flags)
  ImGui.PopStyleColor(ctx,4)
  if ett_rt then
    local val = text:match("(%d+[.%d+]*).*")
    if val then
      EL_par.envtranstime = val/1000
      r.SNM_SetDoubleConfigVar("envtranstime", EL_par.envtranstime)
    end
  end
  if mouse_hover_curs then
    ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Arrow)
  end
  if mouse_hover and ImGui.IsMouseDown(ctx, 1) then
    ImGui.SetTooltip(ctx, "Reaper parameter from Preferences,\n'Editing Behavior/Envelope Display/Transition time for automatically created envelope edge points'\nIt saves with Projects and Presets and recalls with them")
  end
  if mouse_hover and ctrl and mwheel_val~=0 then
    local val, val_add = text:match("(%d+[.%d+]*).*")
    local sign =1
    if mwheel_val<0 then sign=-1 end
    if not shift and not alt and not super then
      val_add = 1*sign
    elseif shift and not alt and not super then
      val_add = 0.1*sign
    elseif not shift and alt and not super then
      val_add = 10*sign
    end
    EL_par.envtranstime = limit(val + val_add, 0.1, huge) / 1000
    if EL_par.project_saved==0 then
      save_EL_par_to_global_ext()
    else
      save_EL_par_to_project_ext(project.curr)
    end
  end


  local col = {
      {colors.grey9, colors.buttonColor_green, colors.hoveredColor_green, colors.activeColor_green},
      {colors.grey9, colors.buttonColor_green, colors.hoveredColor_green, colors.activeColor_green},
      {colors.grey9, colors.buttonColor_green, colors.hoveredColor_green, colors.activeColor_green},
      {colors.grey9, colors.buttonColor_green, colors.hoveredColor_green, colors.activeColor_green},
    }
  for i=1,4 do

    local name, color = "", {}
    if i==1 then 
      name="act on"
      if EL_par.auto_act_on==0 then
        col[i][1]=colors.grey5
        col[i][2]=colors.grey12
        col[i][3]=colors.grey12
        col[i][4]=colors.grey12
      end
    elseif i==2 then 
      name="vis on"
      if EL_par.auto_vis_on==0 then
        col[i][1]=colors.grey5
        col[i][2]=colors.grey12
        col[i][3]=colors.grey12
        col[i][4]=colors.grey12
      end
    elseif i==3 then 
      name="vis off"
      if EL_par.auto_vis_off==0 then
        col[i][1]=colors.grey5
        col[i][2]=colors.grey12
        col[i][3]=colors.grey12
        col[i][4]=colors.grey12
      end
    elseif i==4 then 
      name="env lane"
      if EL_par.env_on_lane==0 then
        name="medialane"
        col[i][1]=colors.grey5
        col[i][2]=colors.grey12
        col[i][3]=colors.grey12
        col[i][4]=colors.grey12
      end
    end

    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, x_before + (bt_w+space*2)*(i-1))
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col[i][1])
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col[i][2])
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col[i][3])
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col[i][4])
    local rt = ImGui.Button(ctx, name.."##opt"..i, bt_w, bt_h)
    ImGui.PopStyleColor(ctx,4)
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDown(ctx, 1) then
      if name=="act on" then
        ImGui.SetTooltip(ctx, "Switch, auto activating envelopes from Env Menu, except 'Selected env'")
      elseif name=="vis on" then
        ImGui.SetTooltip(ctx, "Switch, auto enabling visibility of envelopes from Env Menu, except 'Selected env'")
      elseif name=="vis off" then
        ImGui.SetTooltip(ctx, "Switch, auto disabling visibility of envelopes which are not currently applied by actions")
      elseif name=="env lane" then
        ImGui.SetTooltip(ctx, "Switch, if On - auto placing activated envelopes on envelope lanes\nIf Off - auto placing activated envelopes on media lanes")
      end
    end
    if rt then
      if i==1 then EL_par.auto_act_on = 1-EL_par.auto_act_on EL_par.act_vis=0
      elseif i==2 then EL_par.auto_vis_on = 1-EL_par.auto_vis_on EL_par.act_vis=0
      elseif i==3 then EL_par.auto_vis_off = 1-EL_par.auto_vis_off
      elseif i==4 then EL_par.env_on_lane = 1-EL_par.env_on_lane end
      if EL_par.project_saved==0 then
        save_EL_par_to_global_ext()
      else
        save_EL_par_to_project_ext(project.curr)
      end
      r.SetCursorContext(1)
    end
  end

  local x_before2 = x_before + (bt_w+space*2)*4

  local col = {
      {colors.grey9, colors.buttonColor_yellow, colors.hoveredColor_yellow, colors.activeColor_yellow},
      {colors.grey9, colors.buttonColor_yellow, colors.hoveredColor_yellow, colors.activeColor_yellow},
      {colors.grey9, colors.buttonColor_yellow, colors.hoveredColor_yellow, colors.activeColor_yellow},
      {colors.grey9, colors.buttonColor_yellow, colors.hoveredColor_yellow, colors.activeColor_yellow},
      {colors.grey9, colors.buttonColor_yellow, colors.hoveredColor_yellow, colors.activeColor_yellow},
    }
  for i=1,EL_preset.count do

    if EL_preset[i][1]==nil then
      col[i][1]=colors.grey5
      col[i][2]=colors.grey12
      col[i][3]=colors.grey12
      col[i][4]=colors.grey12
    end

    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, x_before2 + (pres1_w+space)*(i-1))
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col[i][1])
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col[i][2])
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col[i][3])
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col[i][4])
    local rt = ImGui.Button(ctx, i.."##preset"..i, pres1_w, bt_h)
    ImGui.PopStyleColor(ctx,4)
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDown(ctx, 1) then
      ImGui.SetTooltip(ctx, "5 Presets for saving params permanently\nLMB - Restore preset\nCtrl+LMB - Save preset\nAlt+LMB - Remove preset")
    end

    if rt then
      if not shift and not ctrl and not alt and not super then
        restore_EL_preset(i)
      elseif not shift and ctrl and not alt and not super then
        save_EL_preset(i)
      elseif not shift and not ctrl and alt and not super then
        remove_EL_preset(i)
      end
      r.SetCursorContext(1)
    end
  end

end

function loop()
  ImGui.PushFont(ctx, font)
  -- ImGui.SetNextWindowSize(ctx, 1160, 280, ImGui.Cond_FirstUseEver

  if docked then
    window_flags = ImGui.WindowFlags_None
    | ImGui.WindowFlags_NoFocusOnAppearing
    | ImGui.WindowFlags_NoScrollbar
    | ImGui.WindowFlags_NoScrollWithMouse
    | ImGui.WindowFlags_AlwaysAutoResize
    -- | ImGui.WindowFlags_NoResize
    -- | ImGui.WindowFlags_NoNav
    | ImGui.WindowFlags_NoTitleBar
    -- | ImGui.WindowFlags_NoTabBar
  else
    window_flags = ImGui.WindowFlags_None
    | ImGui.WindowFlags_NoFocusOnAppearing
    | ImGui.WindowFlags_NoScrollbar
    | ImGui.WindowFlags_NoScrollWithMouse
    | ImGui.WindowFlags_AlwaysAutoResize
    -- | ImGui.WindowFlags_NoResize
    -- | ImGui.WindowFlags_NoNav
  end

  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, colors.blackColor)--0x0F0F0FFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, colors.blackColor)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey9)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, colors.buttonColor_blue)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, colors.hoveredColor_blue)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,  colors.activeColor_blue)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 2.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 2.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_TabRounding, 2.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 2.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding, 2.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, 2.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ScrollbarRounding, 2.0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0.5)
  
 
  local visible, open = ImGui.Begin(ctx, "EnvoyLope", true, window_flags)
  --wnd_itemsend = wnd_itemsend or r.JS_Window_GetFocus()
   --ImGui.IsWindowAppearing( ctx ) 
   --Use after ImGui_Begin/ImGui_BeginPopup/ImGui_BeginPopupModal to tell if a window just opened.
  if visible then
    local wd, ht = ImGui.CalcTextSize(ctx, "Envoylope")
    ImGui.SetWindowSize(ctx, wd*2, ht)
    framework()

    ImGui.End(ctx)
  else
    -- ImGui.SetWindowSize(ctx, 100, 30)
  end


  if open and not gotoexit then
    r.defer(loop)
  -- else
    -- r.atexit(gfx.quit)
  end

  ImGui.PopStyleVar(ctx,9)
  ImGui.PopStyleColor(ctx,6)
  ImGui.PopFont(ctx)

end

if EL_preset.restored==false then 
  restore_EL_preset_from_global()
end

r.defer(loop)