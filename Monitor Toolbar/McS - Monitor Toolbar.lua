--- The script was made with great help of vitalker, X-Raym, mpl and other scripters.
--- There's some pieces of code from these authors scripts here.

--- User config

local font_size = 14 -- 14 is default 

--- Monitor Toolbar
local r = reaper
local floor = math.floor
local abs = math.abs
local log = math.log
local huge = math.huge

local ctrl = r.JS_Mouse_GetState(4) == 4 --CTRL
local shift = r.JS_Mouse_GetState(8) == 8 --SHIFT
local alt = r.JS_Mouse_GetState(16) == 16 --ALT
local super = r.JS_Mouse_GetState(32) == 32 --WIN
local MBL = r.JS_Mouse_GetState(1) == 1 --left mouse button
local MBR = r.JS_Mouse_GetState(2) == 2 --right mouse button
--local fx_num = 1 -- slot number in which "Multichannel Volume Trim 2" is placed

local Main_HWND = r.GetMainHwnd()
local MonitorToolbar_HWND
local project = {curr=nil, prev=-1, curr_path=nil, prev_path="-1"}
local mon_fx_vol_exist = false

local xfadeshape = tonumber(({r.get_config_var_string( "defxfadeshape" )})[2])
local xfadetime = 2/r.TimeMap_curFrameRate(0)
local inac = 0.001 --0.0001 --0.00000001

local windows = string.find(r.GetOS(), "Win") ~= nil
local sep = package.config:sub(1,1)
local reaper_path = r.GetResourcePath()

package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10.0.2'

function Msg(param) r.ShowConsoleMsg(tostring(param) .. "\n") end

function in_range(value, min, max)
  if value==nil or min==nil or max==nil then return nil end
  if value >= min and value < max then
    return true
  else
    return false
  end
end

function in_range_equal(value, min, max)
  if value==nil or min==nil or max==nil then return nil end
  if value >= min and value <= max then
    return true
  else
    return false
  end
end

function in_range_notequal(value, min, max)
  if value==nil or min==nil or max==nil then return nil end
  if value > min and value < max then
    return true
  else
    return false
  end
end

function limit(value, min, max)
  if value > max then value = max end
  if value < min then value = min end
  return value
end

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return floor(num * mult + 0.5) / mult
end

local dir_list = {}
local ch_n = 0

function folder_exists(path) -- sometimes doesn't work!
--[[
  -- some error codes:
  -- 13 : EACCES - Permission denied
  -- 17 : EEXIST - File exists
  -- 20 : ENOTDIR - Not a directory
  -- 21 : EISDIR - Is a directory
  --
  local isok, errstr, errcode = os.rename(path, path)
  if isok == nil then
     if errcode == 13 then 
        -- Permission denied, but it exists
        return true
     end
     return false
  end
  return true
--]]
  local rt, size = r.JS_File_Stat(path)
  if rt==0 then
    return true
  elseif rt<0 then
    return false
  end
end

function fix_path_name(path)
  path = path:gsub([[\\]], [[\]])
  path = path:gsub([[/]], [[\]])
  return path
end

function GetAllSubfolders(folderlist)
  if type(folderlist) ~= 'table' then return end
  local childs = {}
  for i, folder in ipairs(folderlist) do
    r.EnumerateSubdirectories(folder,-1) -- Rescan
    local i = 0
    while r.EnumerateSubdirectories(folder,i) do
      if i==0 then dir_list[ch_n+1].child_idx = #dir_list end
      local fld = r.EnumerateSubdirectories(folder,i)
      local path = fix_path_name(folder..sep..fld)
      table.insert(childs, path)
      table.insert(dir_list, {num=#dir_list+1, dir=path, name=fld, type="Folder1", child_idx=-1, child_count=0, parent_idx=ch_n+1})
      i = i + 1
      -- Msg("her")
    end
    ch_n = ch_n + 1
    dir_list[ch_n].child_count = i
  end
  if #childs > 0 then
    return GetAllSubfolders(childs)
  end
  return childs
end

function GetFolderStructure(path)
  dir_list = {}
  ch_n = 0
  dir_list[1] = {num=1, dir=path, name="Root \\", type="Folder2", child_idx=1, child_count=0, parent_idx=-1}
  GetAllSubfolders({path})
end

function GetAllFilesInFolder(path)
  r.EnumerateFiles(path,-1) -- Rescan
  local files_index = 0
  local files = {}
  while true do
    local file = r.EnumerateFiles(path, files_index)
    if file then
      files_index = files_index + 1
      local rv, size = r.JS_File_Stat(path..sep..file)
      local ext = file:match("^.+%.(.*)$")
      table.insert(files, {path=path,name_ext=file,ext=ext,size=size})
    else
      break
    end
  end
  return files
end


local init_performed = false
local validate_done = false

local initial_state = r.GetProjectStateChangeCount(0)
local current_state
local masterTrack = r.GetMasterTrack(0)

local processing_getting_video_info = false

local mon_vol_curr
local mon_vol_prev = -1
local monitorfxdb
local set_dock_id
local is_docked
local monitorsolo_state = {1,1,1,1,1,1} -- 0 mute, 1 on, 2 solo
local monitorsolo_jspar = {1,1,1,1,1,1}
local monitorsolo_vol = {0.5,0.5,0.5,0.5,0.5,0.5}
local monitorsolo_vol_db = {nil,nil,nil,nil,nil,nil}
local monitorsolo_alwaysmute = {0,0,0,0,0,0}

local menu_open = {vol_edit = false,
                   pan_edit = false,
                   pitch_edit = false,
                   playrate_edit = false,
                   playrate_pitch_edit = false,
                   loop = false,
                   chmode = false,
                   framerate = false,
                   monvol = false,
                   basic = false,
                   select = false,
                   close_all = false,
                  }


local combo =
  {select = 
    {
    {txt=" .. Loop, Mute, Reverse, CM, Playrate + FX", command = function () count_selected_items_with_params("ripfx",true) end},
    {txt=" .. Loop, Mute, Reverse, CM, Playrate", command  =function ()  count_selected_items_with_params("rip",true) end},
    {txt=" .. Any of All Params", command = function () count_selected_items_with_params("all",true) end},
    {txt=" .. Loop", command = function () count_selected_items_with_params("loop",true) end},
    {txt=" .. Mute", command = function () count_selected_items_with_params("mute",true) end},
    {txt=" .. Lock", command = function () count_selected_items_with_params("lock",true) end},
    {txt=" .. Reverse", command = function () count_selected_items_with_params("reverse",true) end},
    {txt=" .. Chan Mode", command = function () count_selected_items_with_params("chan_mode",true) end},
    {txt=" .. Vol", command = function () count_selected_items_with_params("vol",true) end},
    {txt=" .. Pan", command = function () count_selected_items_with_params("pan",true) end},
    {txt=" .. Pitch", command = function () count_selected_items_with_params("pitch",true) end},
    {txt=" .. Playrate", command = function () count_selected_items_with_params("playrate",true) end},
    {txt=" .. Preserve Pitch", command = function () count_selected_items_with_params("preserve_pitch",true) end},
    }
  }

local pan_init_mouse_x
local pan_mouse_delta, prev_pan_mouse_delta
local pan_init_delta = false

local pan_mouse_sensivity = 5
local pan_mouse_sensivity_shift = 10
local sens, prev_sens, pan_x_pos = pan_mouse_sensivity, pan_mouse_sensivity


local window_flags

local actual_item = r.GetSelectedMediaItem(0,0)
local actual_item_guid
if actual_item == nil then
  actual_item_guid = "-1"
else
  actual_item_guid = r.BR_GetMediaItemGUID(actual_item)
end
local actual_item_type_is = "AUDIO"
local actual_item_num

local sel_items = {}
local count_sel_items = r.CountSelectedMediaItems(0)
local preserve_pitch, item_loop, item_lock, item_mute, take_reverse, chan_mode, pitch_mode
local take_name, take_path, take_bit_depth, take_samplerate, take_channel_num, item_vol, take_pan, take_pitch, take_playrate, take_playrate_pitch
local rateL, temp_rateL= 0,0

local video_take_res
local video_take_fps
local video_take_bitrate
local video_take_codec

-- local item_vol_validated
local item_vol_db_validated
local item_vol_db_delta = 0
local vol_delta_tooltip
local vol_delta_tooltip_xpos
local vol_tooltip_enable = false

local take_pan_validated
local take_pan_delta = 0
local pan_delta_tooltip
local pan_delta_tooltip_xpos
local pan_tooltip_enable = false

local take_pitch_validated
local take_pitch_delta = 0
local pitch_delta_tooltip
local pitch_delta_tooltip_xpos
local pitch_tooltip_enable = false

local take_playrate_validated
local take_playrate_pitch_validated
local take_playrate_delta = 0
local take_playrate_pitch_delta = 0
local playrate_delta_tooltip
local playrate_delta_tooltip_xpos
local playrate_tooltip_enable = false

local playrate_pitch_xpos

local item_vol_show, take_pan_show, take_pitch_show, take_playrate_show, playrate_pitch_show, chan_mode_show = "","","","","",""
local _
local all_counted, vol_counted, pan_counted, pitch_counted, playrate_counted = false,false,false,false,false
local loop_counted, mute_counted, lock_counted, revers_counted, prspitch_counted, chan_mode_counted = false,false,false,false,false,false
local vol_count_show, pan_count_show, pitch_count_show, playrate_count_show, rip_count_show
local loop_count_show, mute_count_show, lock_count_show, revers_count_show, prspitch_count_show, chan_mode_count_show

local ripple_on = 0
local ripple_time_init = 0
local framert, dropfr = r.TimeMap_curFrameRate(0)
local framerate_i = 0
-- local framerate_prev
local get_ripple = 0
local scan_time_init = 0

function HSV(H, S, V, A)
  local R, G, B = ImGui.ColorConvertHSVtoRGB(H, S, V)
  return ImGui.ColorConvertDouble4ToU32(R, G, B, A or 1.0)
end
--function RGB(R, G, B, A)
--  return ImGui.ColorConvertDouble4ToU32(R, G, B, A or 1.0)
--end
local colors = {
  black = HSV(0.0, 0.0, 0.0),
  grey1 = HSV(0.0, 0.0, 0.1),
  grey2 = HSV(0.0, 0.0, 0.2),
  grey3 = HSV(0.0, 0.0, 0.3),
  grey4 = HSV(0.0, 0.0, 0.4),
  grey5 = HSV(0.0, 0.0, 0.5),
  grey6 = HSV(0.0, 0.0, 0.6),
  grey7 = HSV(0.0, 0.0, 0.7),
  grey8 = HSV(0.0, 0.0, 0.8),
  grey85 = HSV(0.0, 0.0, 0.85),
  grey9 = HSV(0.0, 0.0, 0.9),

  yellow5 = HSV(0.14, 0.6, 0.5),
  green5 = HSV(0.3, 0.6, 0.5),
  violet5 = HSV(0.75, 0.6, 0.5),
  blue5 = HSV(0.6, 0.6, 0.5),

  yellow6 = HSV(0.14, 0.6, 0.6),
  green6 = HSV(0.3, 0.6, 0.6),
  violet6 = HSV(0.75, 0.6, 0.6),
  blue6 = HSV(0.6, 0.6, 0.6),

  yellow7 = HSV(0.14, 0.6, 0.7),
  green7 = HSV(0.3, 0.6, 0.7),
  violet7 = HSV(0.75, 0.6, 0.7),
  blue7 = HSV(0.6, 0.6, 0.7),

  yellow75 = HSV(0.14, 0.6, 0.75),
  green75 = HSV(0.3, 0.6, 0.75),
  violet75 = HSV(0.75, 0.6, 0.75),
  blue75 = HSV(0.6, 0.6, 0.75),

  yellow8 = HSV(0.14, 0.6, 0.8),
  green8 = HSV(0.3, 0.6, 0.8),
  violet8 = HSV(0.75, 0.6, 0.8),
  blue8 = HSV(0.6, 0.6, 0.8),

  yellow85 = HSV(0.14, 0.6, 0.85),
  green85 = HSV(0.3, 0.6, 0.85),
  violet85 = HSV(0.75, 0.6, 0.85),
  blue85 = HSV(0.6, 0.6, 0.85),

  yellow9 = HSV(0.14, 0.6, 0.9),
  green9 = HSV(0.3, 0.6, 0.9),
  violet9 = HSV(0.75, 0.6, 0.9),
  blue9 = HSV(0.6, 0.6, 0.9),

  yellow95 = HSV(0.14, 0.6, 0.95),
  green95 = HSV(0.3, 0.6, 0.95),
  violet95 = HSV(0.75, 0.6, 0.95),
  blue95 = HSV(0.6, 0.6, 0.95),

  yellow10 = HSV(0.14, 0.6, 1.0),
  green10 = HSV(0.3, 0.6, 1.0),
  violet10 = HSV(0.75, 0.6, 1.0),
  blue10 = HSV(0.6, 0.6, 1.0),
  orange10 = HSV(0.07, 0.85, 1.0),
  red10 = HSV(0.0, 1.0, 1.0),

  video_name_red = HSV(0.0, 0.9, 0.7),

  buttonColor_lblue = HSV(0.47, 0.7, 0.4),
  hoveredColor_lblue = HSV(0.47, 0.7, 0.45),
  activeColor_lblue = HSV(0.47, 0.7, 0.45),

  buttonColor_blue = HSV(0.6, 0.7, 0.4),
  hoveredColor_blue = HSV(0.6, 0.7, 0.45),
  activeColor_blue = HSV(0.6, 0.7, 0.45),

  buttonColor_dblue = HSV(0.7, 0.7, 0.4),
  hoveredColor_dblue = HSV(0.7, 0.7, 0.45),
  activeColor_dblue = HSV(0.7, 0.7, 0.45),

  buttonColor_red = HSV(0.0, 1.0, 0.5),
  hoveredColor_red = HSV(0.0, 1.0, 0.55),
  activeColor_red = HSV(0.0, 1.0, 0.55),

  buttonColor_pink = HSV(0.9, 1.0, 0.5),
  hoveredColor_pink = HSV(0.9, 1.0, 0.55),
  activeColor_pink = HSV(0.9, 1.0, 0.55),

  buttonColor_lgreen = HSV(0.23, 0.7, 0.4),
  hoveredColor_lgreen = HSV(0.23, 0.7, 0.45),
  activeColor_lgreen = HSV(0.23, 0.7, 0.45),

  buttonColor_green = HSV(0.3, 0.8, 0.4),
  hoveredColor_green = HSV(0.3, 0.8, 0.45),
  activeColor_green = HSV(0.3, 0.8, 0.45),

  buttonColor_grey = HSV(0.0, 0.0, 0.8),
  hoveredColor_grey = HSV(0.0, 0.0, 0.8),
  activeColor_grey = HSV(0.0, 0.0, 1.0),

  buttonColor_darkgrey = HSV(0.0, 0.0, 0.2),
  hoveredColor_darkgrey = HSV(0.0, 0.0, 0.25),
  activeColor_darkgrey = HSV(0.0, 0.0, 0.25),

  buttonColor_darkgrey2 = HSV(0.0, 0.0, 0.1),
  hoveredColor_darkgrey2 = HSV(0.0, 0.0, 0.15),
  activeColor_darkgrey2 = HSV(0.0, 0.0, 0.15),

  buttonColor_violet = HSV(0.75, 0.6, 0.8),
  hoveredColor_violet = HSV(0.75, 0.6, 0.8),
  activeColor_violet = HSV(0.75, 0.8, 1.0),

  buttonColor_yellow = HSV(0.14, 0.6, 0.8),
  hoveredColor_yellow = HSV(0.14, 0.6, 0.8),
  activeColor_yellow = HSV(0.14, 0.8, 1.0),

  buttonColor_orange = HSV(0.07, 0.85, 0.6),
  hoveredColor_orange = HSV(0.07, 0.85, 0.65),
  activeColor_orange = HSV(0.07, 0.85, 0.65),

  textColor_white = HSV(0.0, 0.0, 1),
  textColor_darkwhite = HSV(0.0, 0.0, 0.7),
  textColor_black = HSV(0.0, 0.0, 0.0)
}
local background_color = colors.black
local vol1_color
local vol1t_color
local vol2_color
local pan1_color 
local pan1t_color
local pan2_color 
local pitch1_color
local pitch1t_color
local pitch2_color
local playrate1_color
local playrate1t_color
local playrate2_color
local framerate_color
local mon_color


local init_left_space = 20
local text_hight
local button_hight
local row1_y = 1
local row2_y = 21
local line_thickness
local xmouse, ymouse
local prev_s_val_sld = {}
local s_val_sld ={-156.0,-156.0,-156.0,-156.0,-156.0,-156.0,-156.0,-156.0,-156.0,-156.0,-156.0,-156.0}
local prev_s_val_sw = {}
local s_val_sw ={0,0,0,0,0,0,0,0,0,0,0,0}
local reset = {}
local ctx = ImGui.CreateContext('Monitor Toolbar',ImGui.ConfigFlags_DockingEnable)
-- local font_size = {10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35}
-- local font_table = {}
-- for i=1,100 do
  -- font_table[i] = ImGui.CreateFont('tahoma', i)
  -- ImGui.Attach(ctx, font_table[i])
-- end
local font = ImGui.CreateFont('tahoma', ImGui.FontFlags_None)
local font_B = ImGui.CreateFont('tahoma', ImGui.FontFlags_Bold)

local font_size_monitorsolo = round(font_size * 0.8)
-- local font_monitorsolo = ImGui.CreateFont('tahoma', font_size_monitorsolo)--, ImGui.FontFlags_Bold)
-- local font_monitorsolo = ImGui.CreateFont('arial', font_size_monitorsolo, ImGui.FontFlags_Bold)
-- local font_i
-- local font, font_size, font_size_prev

ImGui.Attach(ctx, font)
ImGui.Attach(ctx, font_B)
-- local fontnofx = ImGui.CreateFont('tahoma', 80)
-- ImGui.Attach(ctx, fontnofx)
local mouse_x, mouse_y

local mw_x, mw_y, mw_w, mw_h
local window_x, window_y, window_w, window_h

local prev_window_w, prev_window_h = 0, 0
local curr_sizes = {{}}
local curr_spaces = {{}}
local middles = {}
local curr_value_sizes = {{}}

local auto_focus = true
local monitor_toolbar_wnd_focus = false
local monitor_toolbar_wnd_focus_override = false

if r.HasExtState("McS-Tools", "MonitorToolbar_window_x") == false then
  set_dock_id = 0
  is_docked = false
  window_x, window_y = r.GetMousePosition()
  window_w = 200
  window_h = 50
  r.SetExtState("McS-Tools", "MonitorToolbar_set_dock_id", tostring(0), true)
  r.SetExtState("McS-Tools", "MonitorToolbar_window_x", tostring(window_x), true)
  r.SetExtState("McS-Tools", "MonitorToolbar_window_y", tostring(window_y), true)
  r.SetExtState("McS-Tools", "MonitorToolbar_window_w", tostring(window_w), true)
  r.SetExtState("McS-Tools", "MonitorToolbar_window_h", tostring(window_h), true)

  -- Msg(window_x)
  ImGui.SetNextWindowPos(ctx, window_x, window_y, ImGui.Cond_Always)
  ImGui.SetNextWindowSize(ctx, window_w, window_h, ImGui.Cond_Always)
end

if r.HasExtState("McS-Tools", "rateL") == true then
  rateL = tonumber(r.GetExtState("McS-Tools", "rateL"))
end

function is_any_menu_open()
  if menu_open.vol_edit == true or
    menu_open.pan_edit == true or
    menu_open.pitch_edit == true or
    menu_open.playrate_edit == true or
    menu_open.playrate_pitch_edit == true or
    menu_open.framerate == true or
    menu_open.monvol == true or
    menu_open.basic == true or
    menu_open.select == true or
    menu_open.chmode == true then
    return true
  else
    return false
  end
end

function if_close_all_menu()
  if menu_open.close_all == true then
    menu_open.close_all = false
    menu_open.vol_edit = false
    menu_open.pan_edit = false
    menu_open.pitch_edit = false
    menu_open.playrate_edit = false
    menu_open.playrate_pitch_edit = false
    menu_open.basic = false
    menu_open.select = false
    menu_open.chmode = false
    menu_open.framerate = false
    menu_open.monvol = false

    ImGui.CloseCurrentPopup(ctx)
  end
end

function close_if_open_menu()
  if is_any_menu_open() then
    menu_open.close_all = true
  end
end

function set_monitor_toolbar_autofocus()
  if is_any_menu_open() then
    monitor_toolbar_wnd_focus_override = true
  else
    monitor_toolbar_wnd_focus_override = false
  end

  if ImGui.IsMouseHoveringRect(ctx, mw_x, mw_y, mw_x+mw_w, mw_y+mw_h) and (ImGui.IsMouseClicked(ctx,0) 
    or ImGui.IsMouseClicked(ctx,1) or ImGui.IsMouseClicked(ctx,2)) then
    monitor_toolbar_wnd_focus = true
    if monitor_toolbar_wnd_focus_override == true then
      monitor_toolbar_wnd_focus_override=false
    end
    -- Msg("monitor_toolbar_wnd_focus")
    -- Msg(monitor_toolbar_wnd_focus)
  elseif ImGui.IsMouseHoveringRect(ctx, mw_x, mw_y, mw_x+mw_w, mw_y+mw_h) and not ImGui.IsAnyMouseDown(ctx) and 
    monitor_toolbar_wnd_focus == true and monitor_toolbar_wnd_focus_override==false then
 
    monitor_toolbar_wnd_focus = false
    r.SetCursorContext(1)
    -- Msg("monitor_toolbar_wnd_focus")
    -- Msg(monitor_toolbar_wnd_focus)
  elseif not ImGui.IsMouseHoveringRect(ctx, mw_x, mw_y, mw_x+mw_w, mw_y+mw_h) and monitor_toolbar_wnd_focus == true 
    and monitor_toolbar_wnd_focus_override==false then
    monitor_toolbar_wnd_focus = false
    r.SetCursorContext(1)
    -- Msg("monitor_toolbar_wnd_focus")
    -- Msg(monitor_toolbar_wnd_focus)
  end
end

function select_items_parname(parname, value, equal)

  r.Undo_BeginBlock()
  local item_count = r.CountSelectedMediaItems(0)
  for i = item_count-1, 0, -1 do
    local item = r.GetSelectedMediaItem(0,i)
    local take = r.GetActiveTake(item)
    if not take or r.TakeIsMIDI(take) then
      r.SetMediaItemSelected(item, 0)
    else
      local name, mode
      if parname == "vol" then name = "D_VOL" mode = "take"
      elseif parname == "pan" then name = "D_PAN" mode = "take"
      elseif parname == "pitch" then name = "D_PITCH" mode = "take"
      elseif parname == "playrate" then name = "D_PLAYRATE" mode = "take"
      elseif parname == "preserve_pitch" then name = "B_PPITCH" mode = "take"
      elseif parname == "chanmode" then name = "I_CHANMODE" mode = "take"
      elseif parname == "loop" then name = "B_LOOPSRC" mode = "item"
      elseif parname == "mute" then name = "B_MUTE" mode = "item"
      elseif parname == "lock" then name = "C_LOCK" mode = "item"
      end

      local par
      if parname == "reverse" then
        local _, _, _, _, _, par = r.BR_GetMediaSourceProperties(take)
      elseif mode == "item" then
        par = r.GetMediaItemInfo_Value(item, name)
      elseif mode == "take" then
        par = r.GetMediaItemTakeInfo_Value(take, name)
      end

      local sel
      if equal == true then
        if par == value then sel = 1 else sel = 0 end
      else
        if par == value then sel = 0 else sel = 1 end
      end
      r.SetMediaItemSelected(item, sel)
    end
  end
  r.UpdateArrange()
  r.Undo_EndBlock("McS_MonitorToolbar_Select Only",-1)
end

function update_sizes(ctx)

  local w,h = ImGui.CalcTextSize(ctx,'Item Name:')

  text_hight = h
  row1_y = h/18
  row2_y = h/18*21 
  button_hight = h
  line_thickness = h/18

  local take_name_space_lb = ImGui.CalcTextSize(ctx,'Item Name:')

  local vol_space_lb,text_hight = ImGui.CalcTextSize(ctx,'Volume')
  local pan_space_lb = ImGui.CalcTextSize(ctx,'Pan')
  local pitch_space_lb = ImGui.CalcTextSize(ctx,'Pitch')
  local playrate_space_lb = ImGui.CalcTextSize(ctx,'Playrate')
  local framerate_space = ImGui.CalcTextSize(ctx,'29.97ND')
  local monitorfxdb_space = ImGui.CalcTextSize(ctx,'-90.0')
  local monitorsolo_space = ImGui.CalcTextSize(ctx,'LFE')
  
  local loop_space = ImGui.CalcTextSize(ctx,'Loop')
  local mute_space = ImGui.CalcTextSize(ctx,'Mute')
  local lock_space = ImGui.CalcTextSize(ctx,'Lock')
  local reverse_space = ImGui.CalcTextSize(ctx,'Reverse')
  local chmode_space = ImGui.CalcTextSize(ctx,'CM: Reverse')
  local prspitch_space = ImGui.CalcTextSize(ctx,'Preserve Pitch')
  local rateL_space = ImGui.CalcTextSize(ctx,'<L>')
  curr_spaces = {vol_lb = vol_space_lb, pan_lb = pan_space_lb, pitch_lb = pitch_space_lb, playrate_lb = playrate_space_lb,
    framerate = framerate_space, monitorfx = monitorfx_space, monitorsolo = monitorsolo_space, loop = loop_space, mute = mute_space, 
  lock = lock_space, reverse = reverse_space, chmode = chmode_space, prspitch = prspitch_space, rateL = rateL_space}

  ---- Coordinate Points ----
  local cp_take_name_lb = {init_left_space/2, row1_y}
  local cp_take_name = {init_left_space+take_name_space_lb, row1_y}
  local cp_loop = {(init_left_space+take_name_space_lb)*1.8,row2_y}
  local cp_mute = {cp_loop[1]+init_left_space+mute_space,row2_y}
  local cp_lock = {cp_mute[1]+init_left_space+mute_space,row2_y}
  local cp_reverse = {cp_lock[1]+init_left_space+lock_space,row2_y}
  local cp_chmode = {cp_reverse[1]+init_left_space+reverse_space,row2_y}

  local cp_item_vol_lb = {cp_chmode[1]+init_left_space*3/2+chmode_space, row1_y}
  local cp_take_pan_lb = {cp_item_vol_lb[1]+init_left_space/2+vol_space_lb, row1_y}
  local cp_take_pitch_lb = {cp_take_pan_lb[1]+init_left_space/2+pan_space_lb, row1_y}
  local cp_take_playrate_lb = {cp_take_pitch_lb[1]+init_left_space/2+pitch_space_lb, row1_y}

  local cp_prspitch = {cp_take_playrate_lb[1]+init_left_space/2+playrate_space_lb, row2_y}
  local cp_rateL = {cp_prspitch[1]+prspitch_space-rateL_space,row1_y}

  local cp_framerate = {cp_prspitch[1]+init_left_space*3/2+prspitch_space, row1_y}
  local cp_monitorfxdb = {cp_framerate[1]+init_left_space/2+framerate_space, row1_y}
  local cp_monitorsolo = {cp_monitorfxdb[1]+init_left_space + monitorfxdb_space, row1_y}
  
  curr_sizes = {name_lb = cp_take_name_lb, name = cp_take_name, vol_lb = cp_item_vol_lb, pan_lb = cp_take_pan_lb, pitch_lb = cp_take_pitch_lb,
  playrate_lb = cp_take_playrate_lb, framerate = cp_framerate, monitorfxdb = cp_monitorfxdb, monitorsolo = cp_monitorsolo, loop = cp_loop, 
  mute = cp_mute, lock = cp_lock, reverse = cp_reverse, chmode = cp_chmode, prspitch = cp_prspitch, rateL = cp_rateL, 
  allend = cp_monitorsolo[1]+monitorsolo_space}

  local vol_mid = cp_item_vol_lb[1]+vol_space_lb/2
  local pan_mid = cp_take_pan_lb[1]+pan_space_lb/2
  local pitch_mid = cp_take_pitch_lb[1]+pitch_space_lb/2
  local playrate_mid = cp_take_playrate_lb[1]+playrate_space_lb/2
  local prp_mid = cp_prspitch[1]+prspitch_space/2+init_left_space/2
  middles = {vol = vol_mid, pan = pan_mid, pitch = pitch_mid, playrate = playrate_mid, playrate_pitch = prp_mid}
end

function set_chan_mode_by_mousewheel(val)
  if val ~= 0 then
    if val > 0 then
      chan_mode = chan_mode-1
      if chan_mode < 0 then chan_mode=0 end
    elseif val < 0 then
      chan_mode = chan_mode+1
      if chan_mode > 4 then chan_mode=4 end
    end
    set_chan_mode_show()
    set_all_selected_items_params("chan_mode",chan_mode)
  end
end

function set_chan_mode_show()
  if chan_mode == 0 then
    chan_mode_show = "Norm"
  elseif chan_mode == 1 then
    chan_mode_show = "Reverse"
  elseif chan_mode == 2 then
    chan_mode_show = "Mix L+R"
  elseif chan_mode == 3 then
    chan_mode_show = "L"
  elseif chan_mode == 4 then
    chan_mode_show = "R"
  end
end

function get_framerate_i()
  if framerate == "23.976" then
    framerate_i = 1
  elseif framerate == "24" then
    framerate_i = 2
  elseif framerate == "25" then
    framerate_i = 3
  elseif framerate == "29.97DF" then
    framerate_i = 4
  elseif framerate == "29.97ND" then
    framerate_i = 5
  elseif framerate == "30" then
    framerate_i = 6
  elseif framerate == "48" then
    framerate_i = 7
  elseif framerate == "50" then
    framerate_i = 8
  elseif framerate == "60" then
    framerate_i = 9
  elseif framerate == "75" then
    framerate_i = 10
  end
end


function get_framerate()
  framert, dropfr = r.TimeMap_curFrameRate(0)
  local droptxt = ""
  local a,b = math.modf(framert)
  if b == 0 then
    framerate = tostring(a) --('%.f'):format(framerate)
  elseif a == 23 then
    framerate = ('%.3f'):format(framert)
  elseif a == 29 then
    if dropfr == true then
      droptxt = "DF"
    else
      droptxt = "ND"
    end
    framerate = ('%.2f'):format(framert)..droptxt
  end
  get_framerate_i()
end

function set_framerate_by_mousewheel(val)
  if val ~= 0 then
    if val > 0 then
      framerate_i = framerate_i-1
      if framerate_i < 1 then framerate_i=1 end
    elseif val < 0 then
      framerate_i = framerate_i+1
      if framerate_i > 10 then framerate_i=10 end
    end
    set_framerate(framerate_i)
  end
end

function set_framerate(val)
  -- over_false()
  framerate_i = val
  if val == 1 then
    r.SNM_SetIntConfigVar( "projfrbase", 24)
    r.SNM_SetIntConfigVar( "projfrdrop", 2)
  elseif val == 2 then
    r.SNM_SetIntConfigVar( "projfrbase", 24)
    r.SNM_SetIntConfigVar( "projfrdrop", 0)
  elseif val == 3 then
    r.SNM_SetIntConfigVar( "projfrbase", 25)
    r.SNM_SetIntConfigVar( "projfrdrop", 0)
  elseif val == 4 then
    r.SNM_SetIntConfigVar( "projfrbase", 30)
    r.SNM_SetIntConfigVar( "projfrdrop", 1)
  elseif val == 5 then
    r.SNM_SetIntConfigVar( "projfrbase", 30)
    r.SNM_SetIntConfigVar( "projfrdrop", 2)
  elseif val == 6 then
    r.SNM_SetIntConfigVar( "projfrbase", 30)
    r.SNM_SetIntConfigVar( "projfrdrop", 0)
  elseif val == 7 then
    r.SNM_SetIntConfigVar( "projfrbase", 48)
    r.SNM_SetIntConfigVar( "projfrdrop", 0)
  elseif val == 8 then
    r.SNM_SetIntConfigVar( "projfrbase", 50)
    r.SNM_SetIntConfigVar( "projfrdrop", 0)
  elseif val == 9 then
    r.SNM_SetIntConfigVar( "projfrbase", 60)
    r.SNM_SetIntConfigVar( "projfrdrop", 0)
  elseif val == 10 then
    r.SNM_SetIntConfigVar( "projfrbase", 75)
    r.SNM_SetIntConfigVar( "projfrdrop", 0)
  end
  get_framerate()
  -- r.SetCursorContext(1)
end

function set_monitorsolo_state_to_jspar()
  local found_solo = false
  for i=1,6 do
    if monitorsolo_state[i] == 2 then
      found_solo = true
    end
  end

  if found_solo then
    for i=1,6 do
      if monitorsolo_state[i] == 2 then
        monitorsolo_jspar[i] = 1
      else
        monitorsolo_jspar[i] = 0
      end
    end
  else
    for i=1,6 do
      if monitorsolo_state[i] == 1 then
        monitorsolo_jspar[i] = 1
      else
        monitorsolo_jspar[i] = 0
      end
    end
  end

  for i=1,6 do
    if monitorsolo_alwaysmute[i] == 1 then
      monitorsolo_state[i] = 0
      monitorsolo_jspar[i] = 0
    end
  end
end

function get_set_monitorsolo(val, solo_vol, par_num)
  local ass = {1,3,2,5,4,6}

  masterTrack = r.GetMasterTrack(0)
  if masterTrack ~= nil then
    local fx_solo_51 = r.TrackFX_AddByName(masterTrack, "McS_MonitorFX_SOLO_51", true, 0)
    local fx_volume = r.TrackFX_AddByName(masterTrack, "McS_6ch_and_51_Volume", true, 0)
    if val == -1 then
      if r.HasExtState("McS-Tools", "MonFXSolo") then

        local str = r.GetExtState("McS-Tools", "MonFXSolo")
        -- Msg(str)
        local s = {nil,nil,nil,nil,nil,nil}
        local v = {nil,nil,nil,nil,nil,nil}
        s[1],s[2],s[3],s[4],s[5],s[6],v[1],v[2],v[3],v[4],v[5],v[6] = str:match("(%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
        for i=1,6 do
          local number = tonumber(s[i])
          -- Msg(number)

          if number == -1 then
            monitorsolo_alwaysmute[i] = 1
          else
            monitorsolo_state[i] = number
          end
          if tonumber(v[i]) then
            monitorsolo_vol[i] = tonumber(v[i])
          end
        end

        set_monitorsolo_state_to_jspar()

        for i=1,6 do
          r.TrackFX_SetParam(masterTrack, fx_solo_51|0x1000000, ass[i]-1, monitorsolo_jspar[i])
          r.TrackFX_SetParamNormalized(masterTrack, fx_volume|0x1000000, ass[i]-1, monitorsolo_vol[i])
          get_monitorsolo_vol_db(i)
        end
      else
        for i=1,6 do
          monitorsolo_jspar[ass[i]] = r.TrackFX_GetParam(masterTrack, fx_solo_51|0x1000000, i-1)
          monitorsolo_state[ass[i]] = monitorsolo_jspar[ass[i]]
          monitorsolo_vol[ass[i]] = r.TrackFX_GetParamNormalized(masterTrack, fx_volume|0x1000000, i-1)
          get_monitorsolo_vol_db(i)
        end
      end
    else
      if solo_vol==1 then
        for i=1,6 do
          r.TrackFX_SetParam(masterTrack, fx_solo_51|0x1000000, ass[i]-1, monitorsolo_jspar[i])
        end
      else
        if par_num==100 then
          for i=1,6 do
            r.TrackFX_SetParamNormalized(masterTrack, fx_volume|0x1000000, ass[i]-1, monitorsolo_vol[i])
            get_monitorsolo_vol_db(i)
          end
        else
          r.TrackFX_SetParamNormalized(masterTrack, fx_volume|0x1000000, ass[par_num]-1, monitorsolo_vol[par_num])
          get_monitorsolo_vol_db(par_num)
        end
      end

      local str = ""
      for i=1,6 do
        if monitorsolo_alwaysmute[i] == 1 then
          str = str .. "-1"
        else
          str = str .. tostring(monitorsolo_state[i]).." "
        end
      end
      for i=1,6 do
        str = str .. tostring(monitorsolo_vol[i])
        if i~=6 then str = str.." " end
      end      
      r.SetExtState("McS-Tools", "MonFXSolo", str, true)
    end
  end
end

function get_monitorsolo_vol_db(par_num)
  local m
  if monitorsolo_vol[par_num] >= 0.5 then
    m = round((monitorsolo_vol[par_num]-0.5)*36 , 1) -- округление до десятой доли
  else
    m = round((0.5-monitorsolo_vol[par_num])*-288 , 1)
  end
  if m == 0.0 then
    monitorsolo_vol_db[par_num] = "0"
  elseif m > 0.0 then
    monitorsolo_vol_db[par_num] = "+"..('%d'):format(tostring(m))
  else
    monitorsolo_vol_db[par_num] = ('%d'):format(tostring(m))
  end
end


function set_monsolo_vol_by_mousewheel(par_num, val)
  if val == "reset" then
    monitorsolo_vol[par_num] = 0.5
    get_set_monitorsolo(2, 2, par_num)
  elseif val ~= 0 then
    if val > 0 then
      if monitorsolo_vol[par_num] >= 0.5 then
        monitorsolo_vol[par_num] = monitorsolo_vol[par_num] + 0.02778
      else
        monitorsolo_vol[par_num] = monitorsolo_vol[par_num] + 0.003472
      end
    end
    if val < 0 then
      if monitorsolo_vol[par_num] <= 0.5 then
        monitorsolo_vol[par_num] = monitorsolo_vol[par_num] - 0.003472
      else
        monitorsolo_vol[par_num] = monitorsolo_vol[par_num] -0.02778
      end
    end
    if monitorsolo_vol[par_num]<0 then monitorsolo_vol[par_num]=0 end
    if monitorsolo_vol[par_num]>1 then monitorsolo_vol[par_num]=1 end
    if monitorsolo_vol[par_num] > 0.499 and monitorsolo_vol[par_num] < 0.501 then monitorsolo_vol[par_num] = 0.5 end
    get_set_monitorsolo(2, 2, par_num)
  end
end


function get_set_mon_fx_volume(val)
  if val==-100 then
    r.SetProjExtState(project.curr, "McS-Tools", "MonFXVol", "")
    mon_fx_vol_exist = false
    return
  end
  masterTrack = r.GetMasterTrack(0)
  
  if masterTrack ~= nil then
    local m
    local fx_volume = r.TrackFX_AddByName(masterTrack, "McS_6ch_and_51_Volume", true, 0)
    if val == -1 then
      mon_vol_curr = r.TrackFX_GetParamNormalized(masterTrack, fx_volume|0x1000000, 6)
    else
      mon_vol_curr = val
      r.TrackFX_SetParamNormalized(masterTrack, fx_volume|0x1000000, 6, mon_vol_curr)
      r.SetProjExtState(project.curr, "McS-Tools", "MonFXVol", tostring(mon_vol_curr))
      mon_fx_vol_exist = true
    end

    if mon_vol_prev ~= mon_vol_curr then
      if mon_vol_curr >= 0.5 then
        m = round((mon_vol_curr-0.5)*36 , 1) -- округление до десятой доли
      else
        m = round((0.5-mon_vol_curr)*-288 , 1)
      end
  
      if m == 0.0 then
        monitorfxdb = tostring(" 0.0")
      elseif m > 0 then
        monitorfxdb = "+"..tostring(m)
      else
        monitorfxdb = tostring(m)
      end
    end
    mon_vol_prev = mon_vol_curr
  end
end

function set_mon_fx_vol_by_mousewheel(val)
  if val ~= 0 then
    if val > 0 then
      if mon_vol_curr >= 0.5 then
        mon_vol_curr = mon_vol_curr + 0.02778
      else
        mon_vol_curr = mon_vol_curr + 0.003472
      end
    end
    if val < 0 then
      if mon_vol_curr <= 0.5 then
        mon_vol_curr = mon_vol_curr - 0.003472
      else
        mon_vol_curr = mon_vol_curr -0.02778
      end
    end
    if mon_vol_curr<0 then mon_vol_curr=0 end
    if mon_vol_curr>1 then mon_vol_curr=1 end
    if mon_vol_curr > 0.499 and mon_vol_curr < 0.501 then mon_vol_curr = 0.5 end
    get_set_mon_fx_volume(mon_vol_curr)
  end
end

function get_on_projectstate_changed()
  project.curr, project.curr_path = r.EnumProjects(-1,'')
  if project.prev ~= project.curr or project.prev_path ~= project.curr_path then
    get_framerate()
    xfadeshape = tonumber(({r.get_config_var_string( "defxfadeshape" )})[2])
    xfadetime = 2/r.TimeMap_curFrameRate(0)

    local rt, m_val = r.GetProjExtState(project.curr, "McS-Tools", "MonFXVol")
    if rt ~= 0 then
      mon_fx_vol_exist = true
      mon_vol_curr = tonumber(m_val)
      get_set_mon_fx_volume(mon_vol_curr)
      mon_fx_vol_exist = true
    else
      mon_fx_vol_exist = false
    end
    project.prev = project.curr
    project.prev_path = project.curr_path
  end

  count_sel_items = r.CountSelectedMediaItems(0)
  -- Msg(prev_count_sel_items)
  -- if count_sel_items~=prev_count_sel_items then
    validate_done = false
    vol_tooltip_enable = false
    pan_tooltip_enable = false
    pitch_tooltip_enable = false
    playrate_tooltip_enable = false
    
    all_counted, vol_counted, pan_counted, pitch_counted, playrate_counted = false,false,false,false,false
    loop_counted, mute_counted, lock_counted, revers_counted, prspitch_counted, chan_mode_counted = false,false,false,false,false,false

    -- prev_count_sel_items = count_sel_items
  -- end
end

function save_actual_item_guid()
  if actual_item ~= -1 then
    actual_item_guid = r.BR_GetMediaItemGUID(actual_item)
  else
    actual_item_guid = "-1"
  end
  validate_done = false
  vol_tooltip_enable = false
  pan_tooltip_enable = false
  pitch_tooltip_enable = false
  playrate_tooltip_enable = false
  all_counted = false
end

function refresh_actual_item()

  -- if count_sel_items < 2 then actual_item_num = nil end

  if count_sel_items == 0 and actual_item ~= -1 then
    actual_item = -1
    save_actual_item_guid()
    -- Msg(actual_item)
  elseif count_sel_items == 1 and actual_item ~= r.GetSelectedMediaItem(0,0) then
    actual_item = r.GetSelectedMediaItem(0,0)
    save_actual_item_guid()
    -- Msg(actual_item)
  elseif count_sel_items > 1 then
    if actual_item==-1 then
      actual_item = r.GetSelectedMediaItem(0,0)
      save_actual_item_guid()
      -- Msg(actual_item)
    elseif actual_item~=-1 and r.BR_GetMediaItemByGUID(0, actual_item_guid)==nil then
      actual_item = r.GetSelectedMediaItem(0,0)
      save_actual_item_guid()
      -- Msg(actual_item)
    elseif actual_item == r.BR_GetMediaItemByGUID(0, actual_item_guid) and 
        r.IsMediaItemSelected(actual_item)==false then
      actual_item = r.GetSelectedMediaItem(0,0)
      save_actual_item_guid()
      -- Msg(actual_item)
    end
  -- else
    -- actual_item_num = nil
  end
end

function WDL_DB2VAL(x) return math.exp((x)*0.11512925464970228420089957273422) end

function WDL_VAL2DB(x)
 if not x or x < 0.0000000298023223876953125 then return -150.0 end
 local v=math.log(x)*8.6858896380650365530225783783321
 return math.max(v,-150)
end

function convert_take_vol_to_item_vol(item, take)
  local take_vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
  local item_vol = r.GetMediaItemInfo_Value(item, "D_VOL")
  if take_vol ~= 1 then
    local item_db = WDL_VAL2DB(item_vol)
    local take_db = WDL_VAL2DB(take_vol)
    local diff_take_db = 0 - take_db
    local new_item_db = item_db - diff_take_db
    item_vol = WDL_DB2VAL(new_item_db)
    r.SetMediaItemInfo_Value(item, "D_VOL", item_vol)
    r.SetMediaItemTakeInfo_Value(take, "D_VOL", 1)
  end
  return item_vol
end

function update_actual_item(actual_item_guid, upp)
  if actual_item_guid ~= "-1" then
    actual_item = r.BR_GetMediaItemByGUID(0, actual_item_guid)
    if actual_item ~= nil then
      local take = r.GetActiveTake(actual_item)
      -- Msg(take)
      if take then
        item_vol = convert_take_vol_to_item_vol(actual_item, take)
        
        if 20*log(item_vol,10) < -150.5 then
          item_vol_show = "-inf"
        else
          item_vol_show = tostring(round(20*log(item_vol,10),1))
        end
  
        take_pan = r.GetMediaItemTakeInfo_Value(take,"D_PAN")
        -- Msg(take_pan)
        local take_pan_r = round(take_pan*100)
        -- Msg(take_pan_r)
        -- Msg("")
        if take_pan_r > 0 then
          take_pan_show = ('%d'):format(abs(take_pan_r)).." R"
        elseif take_pan_r < 0 then
          take_pan_show = ('%d'):format(abs(take_pan_r)).." L"
        else
          take_pan_show = "0"
        end

        take_pitch = r.GetMediaItemTakeInfo_Value(take,"D_PITCH")
        take_pitch_show = tostring(round(take_pitch,2))
        take_playrate = r.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")
        take_playrate_show = ('%.2f'):format(round(take_playrate,2))
        -- take_playrate_pitch = find_playrate_pitch(take_playrate)
        update_playrate_pitch(take_playrate, upp)

        _, _, _, _, _, take_reverse = r.BR_GetMediaSourceProperties(take)
        local path_name
        local source = r.GetMediaItemTake_Source(take)
        if take_reverse == true then
          source = r.GetMediaSourceParent(source)
          -- local ret, item_chunk = r.GetItemStateChunk(actual_item, "", false) -- isundo = false
          -- path_name = string.match(item_chunk,'<SOURCE WAVE\nFILE "(.+)"')
        end

        if source == nil then
          actual_item_type_is = "EMPTY"
          -- take_reverse = nil
          actual_item_guid = "-1"
          -- return
        else
          path_name = tostring(r.GetMediaSourceFileName(source))
    
          if path_name == nil then path_name = "no file" end
          local path, name_ext, ext = string.match(path_name,"(.-)([^\\]-([^%.]+))$")
          --string.match(path_name,"^(.-)([^\\/]-%.([^\\/%.]-))%.?$") -- another way of getting path, name, ext
          take_name = name_ext
          take_path = path
          take_channel_num = r.GetMediaSourceNumChannels(source)
          take_bit_depth = r.CF_GetMediaSourceBitDepth(source)
          take_samplerate =  r.GetMediaSourceSampleRate(source)
  
          preserve_pitch = r.GetMediaItemTakeInfo_Value(take,"B_PPITCH")
          item_loop = r.GetMediaItemInfo_Value(actual_item, "B_LOOPSRC")
          item_mute = r.GetMediaItemInfo_Value(actual_item, "B_MUTE")
          item_lock = r.GetMediaItemInfo_Value(actual_item, "C_LOCK")
          chan_mode = r.GetMediaItemTakeInfo_Value(take,"I_CHANMODE")
          -- Msg(chan_mode)
          set_chan_mode_show()
          pitch_mode = r.GetMediaItemTakeInfo_Value(take,"I_PITCHMODE")
  
          actual_item_type_is = r.GetMediaSourceType(source, "")
            -- local source = r.GetMediaItemTake_Source(lt_take)
            -- local filename = r.GetMediaSourceFileName(source)
            -- if not r.TakeIsMIDI(lt_take) and filename~="" then
  
          if ext and string.lower(ext)=="m4a" then
            actual_item_type_is = "AUDIO"
          end
          if actual_item_type_is == "VIDEO" then
  
            local video_file = r.GetMediaSourceFileName(source)
            local arguments = " -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate,bit_rate -of csv=s=;:p=0 "
      
            -- if windows then
              -- video_file = video_file:gsub("\\", "/")
              -- video_file = video_file:gsub(":", "\\:")
            -- end
  
            local txt_file = reaper_path..sep..'Scripts'..sep..'McSound'..sep..'video_info.txt'
            -- default location for ffprobe is in UserPlugins directory
            local ffprobe_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffprobe.exe' or 'ffprobe')
  
            -- local command = '"'..ffprobe_file..'"'..arguments..video_file..txt_file
            local command = '"'..ffprobe_file..'"'..arguments..'"'..video_file..'"'..' >'..'"'..txt_file..'"'
  
            if windows then
              local master_command = command
              master_command = 'cmd.exe /C "'..command..'"'
              -- Msg(master_command)
              local retval = r.ExecProcess( master_command, 0 )
            else
              -- mac/linux
              -- Msg(command)
              os.execute(command)
            end
            
            -- Msg(txt_file)
            local f = io.open(txt_file)
            local file_lines = {}
            local i = 1
            for line in f:lines() do file_lines[i] = line i = i + 1 end
            f:close()
            video_take_codec, video_take_res, video_take_fps, video_take_bitrate = "","","",""
            if #file_lines~=0 then
              video_take_codec, video_take_res, video_take_fps, video_take_bitrate = file_lines[1]:match("(.+);(.+;.+);(.+);(.+)")
    
              video_take_res = video_take_res:gsub(";","x")
    
              if video_take_bitrate ~= "N/A" then
                local br = tonumber(video_take_bitrate)
                if br < 10000000 then
                  video_take_bitrate = ('%d'):format(round(br/1000)) .. " kb/s"
                else
                  video_take_bitrate = ('%.1f'):format(round(br/1000000,1)) .. " Mb/s"
                end
              end
    
              if video_take_fps ~= "N/A" then
                if video_take_fps == "24000/1001" then
                  video_take_fps = "23.976"
                elseif video_take_fps == "24/1" then
                  video_take_fps = "24"
                elseif video_take_fps == "25/1" then
                  video_take_fps = "25"
                elseif video_take_fps == "30000/1001" then
                  video_take_fps = "29.97"
                elseif video_take_fps == "30/1" then
                  video_take_fps = "30"
                elseif video_take_fps == "48/1" then
                  video_take_fps = "48"
                elseif video_take_fps == "50/1" then
                  video_take_fps = "50"
                elseif video_take_fps == "60/1" then
                  video_take_fps = "60"
                elseif video_take_fps == "75/1" then
                  video_take_fps = "75"
                end
              end
            end
            -- video_take_fps = video_take_fps
          end
        end
        -- ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -of csv=s=x:p=0 "TZ5_EP009_RUS_ED-01.mp4" >"stream_entries.log"
      -- elseif r.TakeIsMIDI(take) then
        -- actual_item_type_is = "MIDI"
      else
        -- actual_item = -1
        actual_item_type_is = "EMPTY"
      end
    end
  else
    actual_item = -1
  end

  if actual_item == -1 or actual_item_type_is == "EMPTY" then
    take_name, item_vol_show, take_pan_show, take_pitch_show, take_playrate_show, playrate_pitch_show = "-","-","-","-","-",""
    preserve_pitch, item_mute, pitch_mode, take_reverse, item_lock, item_loop, chan_mode = nil,nil,nil,nil,nil,nil,nil
  end

  local vol_space = ImGui.CalcTextSize(ctx, item_vol_show)
  local pan_space = ImGui.CalcTextSize(ctx, take_pan_show)
  local pitch_space = ImGui.CalcTextSize(ctx, take_pitch_show)
  local playrate_space = ImGui.CalcTextSize(ctx, take_playrate_show)
  local playrate_pitch_space = ImGui.CalcTextSize(ctx, playrate_pitch_show)

  local cp_item_vol = {middles.vol-vol_space/2, row2_y}
  local cp_take_pan = {middles.pan-pan_space/2, row2_y}
  local cp_take_pitch = {middles.pitch-pitch_space/2, row2_y}
  local cp_take_playrate = {middles.playrate-playrate_space/2, row2_y}
  local cp_playrate_pitch = {curr_sizes.prspitch[1], row1_y}

  curr_value_sizes = {vol = cp_item_vol, pan = cp_take_pan, pitch = cp_take_pitch, 
  rate = cp_take_playrate, playrate_pitch = cp_playrate_pitch}
  counted = false
  loop_count_show, mute_count_show, lock_count_show, revers_count_show, prs_pitch_count_show, chan_mode_count_show
   = "","","","","",""
  -- Msg('update_act_item')
end

function validate_sel_items(val)
  if validate_done == true then return end
  -- Msg('validate')
  sel_items = {}
  count_sel_items = r.CountSelectedMediaItems(0)
  if count_sel_items == 0 then return end
  for i=0,count_sel_items-1 do
    local item = r.GetSelectedMediaItem(0,i)
    local take = r.GetActiveTake(item)
    if take then --and not r.TakeIsMIDI(take) then
      local vol = convert_take_vol_to_item_vol(item, take)
      if val ~= nil then
        local vol_db = 20*log(vol,10)-val
        vol = 10^((vol_db)/20)
      end
      local pan = r.GetMediaItemTakeInfo_Value(take,"D_PAN")
      -- if pan<-1 then pan = -1 elseif pan>1 then pan = 1 end
      local pitch = r.GetMediaItemTakeInfo_Value(take,"D_PITCH")
      local playrate = r.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")

      local length  = r.GetMediaItemInfo_Value(item,"D_LENGTH")
      local fade_in = r.GetMediaItemInfo_Value(item,"D_FADEINLEN" )
      local fade_out = r.GetMediaItemInfo_Value(item,"D_FADEOUTLEN" )
      local pos = r.GetMediaItemInfo_Value(item,"D_POSITION")
      local snap = r.GetMediaItemInfo_Value(item,"D_SNAPOFFSET")

      local loop = r.GetMediaItemInfo_Value(item,"B_LOOPSRC")
      local mute = r.GetMediaItemInfo_Value(item,"B_MUTE")
      local lock = r.GetMediaItemInfo_Value(item,"C_LOCK")
      local prspitch = r.GetMediaItemTakeInfo_Value(take,"B_PPITCH")
      local chmode = r.GetMediaItemTakeInfo_Value(take,"I_CHANMODE")
      local retval, section, start, length, fade, revrs = r.BR_GetMediaSourceProperties(take)
      sel_items[#sel_items+1] = {item=item, take=take, vol=vol, pan=pan, pitch=pitch, playrate=playrate,
      loop=loop, mute=mute, lock=lock, prspitch=prspitch, chmode=chmode, reverse = revrs, length = length, 
      fade_in = fade_in, fade_out = fade_out, pos = pos, snap = snap}
    else
      sel_items[#sel_items+1] = {item=item, take=-2}
    end
  end
  validate_done = true
end

function initialize_item_vol_delta(val)
  if count_sel_items==0 then return end

  if vol_tooltip_enable == false then --initialize
    item_vol_db_validated = 20*log(item_vol,10)
    item_vol_db_delta = 0
    vol_tooltip_enable = true
    -- Msg('initvol')
  end
end

function update_item_vol_delta_by_mousewheel()
  if count_sel_items==0 then return end

  if item_vol_db_delta > 0 then
    vol_delta_tooltip = "+"..tostring(item_vol_db_delta)
  elseif item_vol_db_delta == 0 then
    vol_delta_tooltip = " 0.0"
  else
    vol_delta_tooltip = tostring(item_vol_db_delta)
  end
  vol_delta_tooltip_xpos = middles.vol-ImGui.CalcTextSize(ctx, vol_delta_tooltip)/2
end

function initialize_take_pan_delta(val)
  if count_sel_items==0 then return end

  if pan_tooltip_enable == false then --initialize
    take_pan_validated = take_pan
    take_pan_delta = 0
    pan_tooltip_enable = true
  end
end

function update_take_pan_delta_by_mousewheel()
  if count_sel_items==0 then return end

  local take_pan_r = round(take_pan_delta*100)
  if take_pan_r > 0 then
    pan_delta_tooltip = ('%d'):format(abs(take_pan_r)).." R"
  elseif take_pan_r < 0 then
    pan_delta_tooltip = ('%d'):format(abs(take_pan_r)).." L"
  else
    pan_delta_tooltip = "0"
  end
  pan_delta_tooltip_xpos = middles.pan-ImGui.CalcTextSize(ctx, pan_delta_tooltip)/2
end

function initialize_take_pitch_delta(val)
  if count_sel_items==0 then return end

  if pitch_tooltip_enable == false then --initialize
    take_pitch_validated = take_pitch
    take_pitch_delta = 0
    pitch_tooltip_enable = true
  end
end

function update_take_pitch_delta_by_mousewheel()
  if count_sel_items==0 then return end

  pitch_delta_tooltip = tostring(round(take_pitch_delta,2))
  pitch_delta_tooltip_xpos = middles.pitch-ImGui.CalcTextSize(ctx, pitch_delta_tooltip)/2
end

function initialize_take_playrate_delta(val)
  -- Msg("ini_pr")
  if count_sel_items==0 then return end

  if playrate_tooltip_enable == false then --initialize
    take_playrate_validated = take_playrate
    take_playrate_pitch_validated = find_playrate_pitch(take_playrate)
    take_playrate_delta = 0
    take_playrate_pitch_delta = 0
    playrate_tooltip_enable = true
  end
end

function update_take_playrate_delta_by_mousewheel()
  if count_sel_items==0 then return end
  local t = round(take_playrate_delta,2)
  playrate_delta_tooltip = ('%.2f'):format(t)
  playrate_delta_tooltip_xpos = middles.playrate-ImGui.CalcTextSize(ctx, playrate_delta_tooltip)/2
end


function set_reverse_all_selected_items_params(val) -- for reversing items
  if count_sel_items == 0 then return end
  validate_sel_items()

  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()

  if val == "switch" then
    if take_reverse == true then 
      take_reverse = false
    else
      take_reverse = true
    end
  end
  val = "current"

  for i=1,#sel_items do
    local item = sel_items[i].item
    local take = sel_items[i].take

    if take~=-2 then
      local retval, section, start, length, fade, revrs = r.BR_GetMediaSourceProperties(take)

      r.Main_OnCommand(40289,0) -- Item: Unselect (clear selection of) all items

      if val == "current" then
        if retval and revrs ~= take_reverse then
          r.SetMediaItemSelected(item, 1)
          r.Main_OnCommand(41051, 0) --Item properties: Toggle take reverse
        end
      elseif val == "init" then
        if retval and revrs ~= sel_items[i].reverse then
          r.SetMediaItemSelected(item, 1)
          r.Main_OnCommand(41051, 0)
        end
      elseif val == "inverse" then
        r.SetMediaItemSelected(item, 1)
        r.Main_OnCommand(41051, 0)
      else
        local v
        if val == 1 then v = true else v = false end
        if retval and revrs ~= v then
          r.SetMediaItemSelected(item, 1)
          r.Main_OnCommand(41051, 0)
        end
      end
    end
  end
  r.Main_OnCommand(40289,0) -- Item: Unselect (clear selection of) all items
  for i=1,#sel_items do
    r.SetMediaItemSelected(sel_items[i].item, 1)
  end
  reverse_counted = false

  r.Undo_EndBlock("McS_MonitorToolbar_Item reverse", -1)
  r.PreventUIRefresh(-1)

  update_actual_item(actual_item_guid, true)
  r.UpdateArrange()
end

  -- for all other params
function set_all_selected_items_params(param,val,change_length) --val can be txt or delta of param
  if count_sel_items == 0 then return end 
  validate_sel_items()

  local upd_plr_ptc = false
  local do_validate = false

  if param == "vol" then
    if type(val)=='number' then -- first set delta and then apply it to items
      item_vol_db_delta = item_vol_db_delta + val
      close_if_open_menu() -- close all opened menu if exist
    elseif val=="undo_delta" then -- after this it goes as 'else' in vol section
      vol_tooltip_enable = false
      do_validate = true
    elseif val=="current" then
      vol_tooltip_enable = false
      do_validate = true
    elseif val=="default" then
      vol_tooltip_enable = false
      initialize_item_vol_delta(0)
      vol_tooltip_enable = false
      do_validate = true
    elseif val=="init" then
      vol_tooltip_enable = false
      item_vol_db_delta = 0
      do_validate = true
    end
  end
  if param == "pan" then
    if type(val)=='number' then
      if take_pan_validated + take_pan_delta + val <= 1 and
        take_pan_validated + take_pan_delta + val >= -1 then
        take_pan_delta = take_pan_delta + val
      else
        if take_pan_validated + take_pan_delta + val > 1 then
          take_pan_delta = 1-take_pan_validated
        elseif take_pan_validated + take_pan_delta + val < -1 then
          take_pan_delta = -1-take_pan_validated
        end
      end
      close_if_open_menu()
    elseif val=="undo_delta" then
      pan_tooltip_enable = false
      do_validate = true
    elseif val=="current" then
      pan_tooltip_enable = false
      do_validate = true
    elseif val=="default" then
      pan_tooltip_enable = false
      initialize_take_pan_delta(0)
      pan_tooltip_enable = false
      take_pan_validated = 0
      do_validate = true
    elseif val=="init" then
      pan_tooltip_enable = false
      take_pan_delta = 0
      do_validate = true
    end
  end
  if param == "pitch" then
    if type(val)=='number' then
      take_pitch_delta = take_pitch_delta + val
      close_if_open_menu()
    elseif val=="undo_delta" then
      pitch_tooltip_enable = false
      do_validate = true
    elseif val=="current" then
      pitch_tooltip_enable = false
      initialize_take_pitch_delta(0)
      pitch_tooltip_enable = false
      do_validate = true
    elseif val=="default" then
      pitch_tooltip_enable = false
      initialize_take_pitch_delta(0)
      pitch_tooltip_enable = false
      take_pitch_validated = 0
      do_validate = true
    elseif val=="init" then
      pitch_tooltip_enable = false
      take_pitch_delta = 0
      do_validate = true
    end
  end
  if param == "playrate" then
    if type(val)=='number' then
      if take_playrate_validated + take_playrate_delta + val >= 0 then
        take_playrate_delta = take_playrate_delta + val
      -- elseif take_playrate_validated + take_playrate_delta + val < 0 then
        -- take_playrate_delta = take_playrate_delta
      end
      upd_plr_ptc = true
      close_if_open_menu()
    elseif val=="undo_delta" then
      playrate_tooltip_enable = false
      do_validate = true
    elseif val=="current" then
      playrate_tooltip_enable = false
      initialize_take_playrate_delta(0)
      playrate_tooltip_enable = false
      do_validate = true
    elseif val=="multiply" then
      playrate_tooltip_enable = false
      initialize_take_playrate_delta(0)
      playrate_tooltip_enable = false
      do_validate = true
    elseif val=="default" then
      playrate_tooltip_enable = false
      initialize_take_playrate_delta(0)
      playrate_tooltip_enable = false
      take_playrate_validated = 1
      do_validate = true
    elseif val=="init" then
      playrate_tooltip_enable = false
      take_playrate_delta = 0
      do_validate = true
    end
  end
  if param == "playrate_pitch" then
    if type(val)=='number' then
      take_playrate_pitch_delta = take_playrate_pitch_delta + val
      take_playrate_delta = take_playrate_validated*(2^(take_playrate_pitch_delta/12) - 1)
      close_if_open_menu()
    elseif val=="undo_delta" then
      playrate_tooltip_enable = false
      do_validate = true
    elseif val=="current" then
      playrate_tooltip_enable = false
      initialize_take_playrate_delta(0)
      playrate_tooltip_enable = false
      do_validate = true
    elseif val=="default" then
      playrate_tooltip_enable = false
      initialize_take_playrate_delta(0)
      playrate_tooltip_enable = false
      take_playrate_validated = 1
      do_validate = true
    elseif val=="init" then
      playrate_tooltip_enable = false
      take_playrate_delta = 0
      do_validate = true
    end
  end
  if param=="loop" then
    if val=="switch" then
      item_loop = 1-item_loop
    end 
  end
  if param=="mute" then
    if val=="switch" then
      item_mute = 1-item_mute
    end 
  end
  if param=="lock" then
    if val=="switch" then
      item_lock = 1-item_lock
    end 
  end
  if param=="preserve_pitch" then
    if val=="switch" then
      preserve_pitch = 1-preserve_pitch
    end 
  end

  for i=1, #sel_items do
    local item = sel_items[i].item
    local take = sel_items[i].take
    if take~=-2 then
      if param == "vol" then ---VOL---
        vol_counted = false
        if val == "default" then
          r.SetMediaItemInfo_Value(item, "D_VOL", 1)
        elseif val == "current" then
          r.SetMediaItemInfo_Value(item, "D_VOL", item_vol)
        elseif val == "init" then
          r.SetMediaItemInfo_Value(item, "D_VOL", sel_items[i].vol)
        elseif val == "undo_delta" then
          r.SetMediaItemInfo_Value(item, "D_VOL", sel_items[i].vol)
        ----------------------------------------------------------- VOL value
        else
          local vol_db = 20*log(sel_items[i].vol,10)
          r.SetMediaItemInfo_Value(item,"D_VOL",(10^((vol_db+item_vol_db_delta)/20)))
        end
        -----------------------------------------------------------
      elseif param == "pan" then  ---PAN---
        pan_counted = false
        if val == "default" then
          r.SetMediaItemTakeInfo_Value(take, "D_PAN", 0)
        elseif val == "current" then
          r.SetMediaItemTakeInfo_Value(take, "D_PAN", take_pan)
        elseif val == "init" then
          r.SetMediaItemTakeInfo_Value(take, "D_PAN", sel_items[i].pan)
        elseif val == "undo_delta" then
          r.SetMediaItemTakeInfo_Value(take, "D_PAN", sel_items[i].pan)
        ----------------------------------------------------------- PAN value
        else
          r.SetMediaItemTakeInfo_Value(take,"D_PAN", sel_items[i].pan+take_pan_delta)
        end
        -----------------------------------------------------------
      elseif param == "pitch" then ---PITCH---
        pitch_counted = false
        if val == "default" then
          r.SetMediaItemTakeInfo_Value(take, "D_PITCH", 0)
        elseif val == "current" then
          r.SetMediaItemTakeInfo_Value(take, "D_PITCH", take_pitch)
        elseif val == "init" then
          r.SetMediaItemTakeInfo_Value(take, "D_PITCH", sel_items[i].pitch)
        elseif val == "undo_delta" then
         r.SetMediaItemTakeInfo_Value(take,"D_PITCH",r.GetMediaItemTakeInfo_Value(take,"D_PITCH")-take_pitch_delta)
        ----------------------------------------------------------- PITCH value
        else
          r.SetMediaItemTakeInfo_Value(take,"D_PITCH", sel_items[i].pitch+take_pitch_delta)
        end
        -----------------------------------------------------------
      elseif param == "playrate" then ---PLAYRATE---
        playrate_counted = false
        if val == "default" then
          local curr_rate = r.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")
          if change_length ~= "change_length" then
            set_item_take_playrate_pitch(item, take, i,"value", curr_rate, 1-curr_rate, 1, "no_change_length")
          else
            set_item_take_playrate_pitch(item, take, i,"value", curr_rate, 1-curr_rate, 1, "change_length")
          end
        elseif val == "current" then
          if change_length ~= "change_length" then
            set_item_take_playrate_pitch(item, take, i, "value", sel_items[i].playrate, take_playrate, 0, "no_change_length")
          else
            set_item_take_playrate_pitch(item, take, i, "value", sel_items[i].playrate, take_playrate, 0, "change_length")
          end
        elseif val == "multiply" then
          set_item_take_playrate_pitch(item, take, i, "multiply", sel_items[i].playrate, change_length, 0, "change_length")
        elseif val == "init" then
          r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", sel_items[i].playrate)
          r.SetMediaItemInfo_Value(item, 'D_LENGTH', sel_items[i].length)
          r.SetMediaItemInfo_Value(item, "D_FADEINLEN", sel_items[i].fade_in)
          r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", sel_items[i].fade_out)
          r.SetMediaItemInfo_Value(item, "D_POSITION", sel_items[i].pos)
          r.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", sel_items[i].snap)
          r.SetMediaItemTakeInfo_Value(take,"B_PPITCH",sel_items[i].prspitch)
        elseif val == "undo_delta" then
          r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", sel_items[i].playrate)
          r.SetMediaItemInfo_Value(item, 'D_LENGTH', sel_items[i].length)
          r.SetMediaItemInfo_Value(item, "D_FADEINLEN", sel_items[i].fade_in)
          r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", sel_items[i].fade_out)
          r.SetMediaItemInfo_Value(item, "D_POSITION", sel_items[i].pos)
          r.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", sel_items[i].snap)
          r.SetMediaItemTakeInfo_Value(take,"B_PPITCH",sel_items[i].prspitch)
        ----------------------------------------------------------- PLAYRATE value
        else
          if change_length ~= "change_length" then
            set_item_take_playrate_pitch(item, take, i, "value", sel_items[i].playrate, take_playrate_delta, 1, "no_change_length")
          else
            set_item_take_playrate_pitch(item, take, i, "value", sel_items[i].playrate, take_playrate_delta, 1, "change_length")
          end
        end
        -----------------------------------------------------------
      elseif param == "playrate_pitch" then ---PLAYRATE_PITCH---
        playrate_counted = false
        if val == "default" then
          local curr_rate = r.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")
          if change_length ~= "change_length" then
            set_item_take_playrate_pitch(item, take, i,"value", curr_rate, 1-curr_rate, 1, "no_change_length")
          else
            set_item_take_playrate_pitch(item, take, i,"value", curr_rate, 1-curr_rate, 1, "change_length")
          end
        elseif val == "current" then
          if change_length ~= "change_length" then
            set_item_take_playrate_pitch(item, take, i, "value", sel_items[i].playrate, take_playrate, 0, "no_change_length")
          else
            set_item_take_playrate_pitch(item, take, i, "value", sel_items[i].playrate, take_playrate, 0, "change_length")
          end
        elseif val == "init" then
          r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", sel_items[i].playrate)
          r.SetMediaItemInfo_Value(item, 'D_LENGTH', sel_items[i].length)
          r.SetMediaItemInfo_Value(item, "D_FADEINLEN", sel_items[i].fade_in)
          r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", sel_items[i].fade_out)
          r.SetMediaItemInfo_Value(item, "D_POSITION", sel_items[i].pos)
          r.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", sel_items[i].snap)
          r.SetMediaItemTakeInfo_Value(take,"B_PPITCH",sel_items[i].prspitch)
        elseif val == "undo_delta" then
          r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", sel_items[i].playrate)
          r.SetMediaItemInfo_Value(item, 'D_LENGTH', sel_items[i].length)
          r.SetMediaItemInfo_Value(item, "D_FADEINLEN", sel_items[i].fade_in)
          r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", sel_items[i].fade_out)
          r.SetMediaItemInfo_Value(item, "D_POSITION", sel_items[i].pos)
          r.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", sel_items[i].snap)
          r.SetMediaItemTakeInfo_Value(take,"B_PPITCH",sel_items[i].prspitch)
        ----------------------------------------------------------- PLAYRATE_PITCH value
        else
          local k = 2^(take_playrate_pitch_delta/12)
          if change_length ~= "change_length" then
            set_item_take_playrate_pitch(item, take, i, "value", sel_items[i].playrate, (k-1)*sel_items[i].playrate, 1, "no_change_length")
          else
            set_item_take_playrate_pitch(item, take, i, "value", sel_items[i].playrate, (k-1)*sel_items[i].playrate, 1, "change_length")
          end
        end
        -----------------------------------------------------------
      elseif param == "loop" then ---LOOP---
        loop_counted = false
        if val == "default" then
          r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
        elseif val == "switch" then
          r.SetMediaItemInfo_Value(item, "B_LOOPSRC", item_loop)
        elseif val == "init" then
          r.SetMediaItemInfo_Value(item, "B_LOOPSRC", sel_items[i].loop)
        elseif val == "inverse" then
          local loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC")
          r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1-loop)
        else
          r.SetMediaItemInfo_Value(item, "B_LOOPSRC", val)
        end
      elseif param == "mute" then ---MUTE---
        mute_counted = false
        if val == "default" then
          r.SetMediaItemInfo_Value(item, "B_MUTE", 0)
        elseif val == "switch" then
          r.SetMediaItemInfo_Value(item, "B_MUTE", item_mute)
        elseif val == "init" then
          r.SetMediaItemInfo_Value(item, "B_MUTE", sel_items[i].mute)
        elseif val == "inverse" then
          local mute = r.GetMediaItemInfo_Value(item, "B_MUTE")
          r.SetMediaItemInfo_Value(item, "B_MUTE", 1-mute)
        else
          r.SetMediaItemInfo_Value(item, "B_MUTE", val)
        end
      elseif param == "lock" then ---LOCK---
        lock_counted = false
        if val == "default" then
          r.SetMediaItemInfo_Value(item, "C_LOCK", 0)
        elseif val == "switch" then
          r.SetMediaItemInfo_Value(item, "C_LOCK", item_lock)
        elseif val == "init" then
          r.SetMediaItemInfo_Value(item, "C_LOCK", sel_items[i].lock)
        elseif val == "inverse" then
          local lock = r.GetMediaItemInfo_Value(item, "C_LOCK")
          r.SetMediaItemInfo_Value(item, "C_LOCK", 1-lock)
        else
          r.SetMediaItemInfo_Value(item, "C_LOCK", val)
        end
      elseif param == "preserve_pitch" then ---PRESERVE PITCH---
        prspitch_counted = false
        if val == "default" then
          r.SetMediaItemTakeInfo_Value(take,"B_PPITCH",1)
        elseif val == "switch" then
          r.SetMediaItemTakeInfo_Value(take,"B_PPITCH",preserve_pitch)
        elseif val == "init" then
          r.SetMediaItemTakeInfo_Value(take,"B_PPITCH",sel_items[i].prspitch)
        elseif val == "inverse" then
          local pp = r.GetMediaItemTakeInfo_Value(take, "B_PPITCH")
          r.SetMediaItemTakeInfo_Value(take,"B_PPITCH",1-pp)
        else
          r.SetMediaItemTakeInfo_Value(take,"B_PPITCH",val)
        end
      elseif param == "chan_mode" then ---CHAN MODE---
        chan_mode_counted = false
        if val == "default" then
          r.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", 0)
        elseif val == "current" then
          r.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", chan_mode)
        elseif val == "init" then
          r.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", sel_items[i].chmode)
        else
          r.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", val)
        end
      end
    end
  end

  if param == "vol" or param == "pan" or param == "mute" then
    r.SetExtState("McS-Tools", "To_ReaPostPro_Actual_Item_value_changed", tostring(DB), false)
  end

  if do_validate == true then
    validate_done = false
  end

  update_actual_item(actual_item_guid, upd_plr_ptc)
  r.UpdateArrange()
end

function set_item_take_playrate_pitch(item, take, i, mode, org_rate, val, abs_rel, change_length)

  local original_rate, new_rate, item_length, item_fade_in, item_fade_out, item_position, item_snap, item_snap_absolute

  if change_length == "change_length" then
    original_rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    item_length  = r.GetMediaItemInfo_Value(item,"D_LENGTH")
    item_fade_in = r.GetMediaItemInfo_Value(item,"D_FADEINLEN" )
    item_fade_out = r.GetMediaItemInfo_Value(item,"D_FADEOUTLEN" )
    item_position = r.GetMediaItemInfo_Value(item,"D_POSITION")
    item_snap = r.GetMediaItemInfo_Value(item,"D_SNAPOFFSET")
    -- item_length  = sel_items[i].length
    -- item_fade_in = sel_items[i].fade_in
    -- item_fade_out = sel_items[i].fade_out
    -- item_position = sel_items[i].pos
    -- item_snap = sel_items[i].snap
    item_snap_absolute = item_snap + item_position
  end

  if abs_rel == 0 then --absolute
    if mode == "value" then
      new_rate = val
    elseif mode == "multiply" then
      new_rate = org_rate * val
    end
  elseif abs_rel == 1 then --relative
    new_rate = limit(org_rate + val, 0, huge)
  end

  r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", new_rate)

  if change_length == "change_length" then
    local k = original_rate/new_rate
    r.SetMediaItemInfo_Value(item, "D_LENGTH", item_length * k)
    r.SetMediaItemInfo_Value(item, "D_FADEINLEN", item_fade_in  * k)
    r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", item_fade_out * k)
    if item_snap ~= 0 then
      r.SetMediaItemInfo_Value(item, "D_POSITION", item_snap_absolute - item_snap * k)
      r.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", item_snap * k)
    end
  end
end

function convert_time_range_fps(val)

  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()

  local inac = 0.000001
  local st_time, en_time = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if st_time == en_time then
    st_time = 0
    en_time = r.GetProjectLength(0)
  end

  local it = {}
  local count_sel_items = r.CountSelectedMediaItems(0)
  local count_items = r.CountMediaItems(0)
  if count_sel_items>0 then
    for i=0,count_sel_items-1 do
      local item = r.GetSelectedMediaItem(0,i)
      local lock = r.GetMediaItemInfo_Value(item, "C_LOCK")
      if lock==0 then
        local st = r.GetMediaItemInfo_Value(item,"D_POSITION")
        if in_range_equal(st, st_time-inac, en_time+inac) then
          table.insert(it, item)
        end
      end
    end
  elseif count_items>0 then
    for i=0,count_items-1 do
      local item = r.GetMediaItem(0,i)
      local lock = r.GetMediaItemInfo_Value(item, "C_LOCK")
      if lock==0 then
        local st = r.GetMediaItemInfo_Value(item,"D_POSITION")
        if in_range_equal(st, st_time-inac, en_time+inac) then
          table.insert(it, item)
        end
      end
    end
  end
  
  ---- Items processing ----
  if #it>0 then
    for i=1,#it do
      local item =it[i]
  
      local st = r.GetMediaItemInfo_Value(item,"D_POSITION")
      local ln = r.GetMediaItemInfo_Value(item,"D_LENGTH")
      local en = st + ln
  
      local take = r.GetActiveTake(item)
      if take and not r.TakeIsMIDI(take) then
        local playrate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
        local snap_off = r.GetMediaItemInfo_Value(item,"D_SNAPOFFSET")
        local fade_in = r.GetMediaItemInfo_Value(item,"D_FADEINLEN" )
        local fade_out = r.GetMediaItemInfo_Value(item,"D_FADEOUTLEN" )
        local fadein_auto = r.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO")
        local fadeout_auto = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO")
        -- local preserve_pitch = r.GetMediaItemTakeInfo_Value(take,"B_PPITCH")
    
        local new_rate = limit(playrate+playrate*(val-1), 0, huge)
    
        r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", new_rate)
    
        -- local k = playrate/new_rate
        r.SetMediaItemInfo_Value(item, "D_POSITION", (st - st_time) / val + st_time)
        r.SetMediaItemInfo_Value(item, "D_LENGTH", ln / val)
        r.SetMediaItemInfo_Value(item, "D_FADEINLEN", fade_in / val)
        r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fade_out / val)
        r.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", fadein_auto / val)
        r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", fadeout_auto / val)
        if snap_off ~= 0 then
          r.SetMediaItemInfo_Value(item, "D_SNAPOFFSET", snap_off / val)
        end
      else
        r.SetMediaItemInfo_Value(item, "D_POSITION", (st - st_time) / val + st_time)
        r.SetMediaItemInfo_Value(item, "D_LENGTH", ln / val)
      end
    end
  end

  ---- Envelope and AutoItems processing ----
  local track_count = r.CountTracks(0)
  for i=0, track_count-1 do
    local track = r.GetTrack(0, i)
    local env_count = r.CountTrackEnvelopes(track)
    if env_count > 0 then
      for j=0, env_count-1 do
        local env = r.GetTrackEnvelope(track, j)
        local count_point =  r.CountEnvelopePoints(env)
        --Envelope Points
        for k=0,count_point-1 do
          local retval, time, value, shape, tension, selected = r.GetEnvelopePoint(env, k)
          if in_range_equal(time, st_time-inac, en_time+inac) then
          -- if time >= end_timesel then
            r.SetEnvelopePoint(env, k, (time-st_time)/val +st_time, value, shape, tension, selected, true)
          end
        end
        r.Envelope_SortPoints(env)
        --Automation Items
        local count_autoitem = r.CountAutomationItems(env)
        if count_autoitem > 0 then
          for k=0, count_autoitem-1 do
            local autoitem_st = r.GetSetAutomationItemInfo(env, k, "D_POSITION", 0, false)
            local autoitem_ln = r.GetSetAutomationItemInfo(env, k, "D_LENGTH", 0, false)
            local autoitem_playrate = r.GetSetAutomationItemInfo(env, k, "D_PLAYRATE", 0, false)

            local new_rate = limit(autoitem_playrate+autoitem_playrate*(val-1), 0, huge)
            -- local autoitem_en = autoitem_st + autoitem_ln
            if in_range_equal(autoitem_st, st_time-inac, en_time+inac) then
              r.GetSetAutomationItemInfo(env, k, 'D_POSITION', (autoitem_st-st_time)/val +st_time, true)
              r.GetSetAutomationItemInfo(env, k, 'D_LENGTH', autoitem_ln/val, true)
              r.GetSetAutomationItemInfo(env, k, "D_PLAYRATE", new_rate, true)
            end
          end
        end
      end
    end
  end

  ---- Markers and Regions processing ----
  local retval, num_markers, num_regions = r.CountProjectMarkers(0)
  if retval > 0 then
    for i=0, retval-1 do
      local rt, isrgn, st, en, name, markrgnindexnumber, color = r.EnumProjectMarkers3(0,i)

      if in_range_equal(st, st_time-inac, en_time+inac) then
        st = (st - st_time) / val + st_time
        if isrgn == true then --regions
          en = (en - st_time) / val + st_time
        end
        r.SetProjectMarkerByIndex2(0, i, isrgn, st, en, markrgnindexnumber, name, color, 0)
      end
    end
  end

  r.Undo_EndBlock("McS_MonitorToolbar", -1)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()

end

function find_playrate_pitch(take_playrate)
  local x = 0
  local final_x
  local n1,n2

  if take_playrate == 1 then
    final_x = x
  elseif take_playrate > 1 then
    for i=0,100 do
      if 2^(i/12) > take_playrate then
        n2=i
        n1=i-1
        break
      end
    end
  elseif take_playrate < 1 then
    for i= 0,-100,-1 do
      if 2^(i/12) < take_playrate then
        n1=i
        n2=i+1
        break
      end
    end
  end

  if final_x == nil then
    if n1~= nil then
      for i = n1 - 0.001, n2 + 0.001, 0.001 do
        if 2^(i/12) >= take_playrate then
          final_x = i
          break
        end
      end
    end
  end
  return final_x
end

function update_playrate_pitch(take_playrate, upd_delta)
  take_playrate_pitch = find_playrate_pitch(take_playrate)

  if take_playrate_pitch ~= nil then-- and take_playrate_pitch_validated ~= nil then
    if upd_delta == true and take_playrate_pitch_validated ~= nil then
      take_playrate_pitch_delta = take_playrate_pitch - take_playrate_pitch_validated
    end
    -- Msg(final_x)
    playrate_pitch_show = ('%.2f'):format(take_playrate_pitch ).." st"
    if take_playrate_pitch  > 0 then
      playrate_pitch_show = "+"..playrate_pitch_show
    end
  else
    playrate_pitch_show = "no range"
  end
end

function count_selected_items_with_params(val, sel_other)
  if sel_other~=nil then
    r.Undo_BeginBlock()
  end

  function set_selected(it, sel)
    if sel_other==true then
      r.SetMediaItemSelected(it, sel)
    end
  end

  local lp1,lp2,m1,m2,l1,l2,p1,p2,c1,c2,c3,c4,c5,rv1,rv2 = 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  local v1,v2,pn1,pn2,pt1,pt2,pr1,pr2 = 0,0,0,0,0,0,0,0
  count_sel_items = r.CountSelectedMediaItems(0)
  for i= count_sel_items-1,0,-1 do
    local it = r.GetSelectedMediaItem(0,i)
    local tk = r.GetActiveTake(it)
    if tk and not r.TakeIsMIDI(tk) then
      local rip_sel=false
      if val=="vol" or val=="all" then
        local vol = r.GetMediaItemInfo_Value(it, "D_VOL")
        if vol==1 then v1=v1+1 set_selected(it,0) else v2=v2+1 set_selected(it,1) end
      end
      if val=="pan" or val=="all" then
        local pan = r.GetMediaItemTakeInfo_Value(tk, "D_PAN")
        if pan==0 then pn1=pn1+1 set_selected(it,0) else pn2=pn2+1 set_selected(it,1) end
      end
      if val=="pitch" or val=="all" then
        local pitch = r.GetMediaItemTakeInfo_Value(tk, "D_PITCH")
        if pitch==0 then pt1=pt1+1 set_selected(it,0) else pt2=pt2+1 set_selected(it,1) end
      end
      if val=="playrate" or val=="all" then
        local playrate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
        if playrate==1 then pr1=pr1+1 set_selected(it,0) else pr2=pr2+1 set_selected(it,1) end
      end
      if val=="loop" or val=="all" then
        local lp = r.GetMediaItemInfo_Value(it, "B_LOOPSRC")
        if lp == 1 then lp1=lp1+1 set_selected(it,1) else lp2=lp2+1 set_selected(it,0) end
      end
      if val=="mute" or val=="all" then
        local m = r.GetMediaItemInfo_Value(it, "B_MUTE")
        if m == 1 then m1=m1+1 set_selected(it,1) else m2=m2+1 set_selected(it,0) end
      end
      if val=="lock" or val=="all" then
        local l = r.GetMediaItemInfo_Value(it, "C_LOCK")
        if l == 1 then l1=l1+1 set_selected(it,1) else l2=l2+1 set_selected(it,0) end
      end
      if val=="preserve_pitch" or val=="all" then
        local pp = r.GetMediaItemTakeInfo_Value(tk,"B_PPITCH")
        if pp == 1 then p1=p1+1 set_selected(it,1) else p2=p2+1 set_selected(it,0) end
      end
      if val=="chan_mode" or val=="all" then
        local cm = r.GetMediaItemTakeInfo_Value(tk,"I_CHANMODE")
        if cm == 0 then c1=c1+1 set_selected(it,0)
          elseif cm == 1 then c2=c2+1 set_selected(it,1)
          elseif cm == 2 then c3=c3+1 set_selected(it,1)
          elseif cm == 3 then c4=c4+1 set_selected(it,1)
          elseif cm == 4 then c5=c5+1 set_selected(it,1)
         end
      end
      if val=="reverse" or val=="all" or val=="rip" or val=="ripfx" then
        local retval, section, start, length, fade, revrs = r.BR_GetMediaSourceProperties(tk)
        if revrs == true then rv1=rv1+1 set_selected(it,1) else rv2=rv2+1 set_selected(it,0) end
      end

      if val=="fx" then
        local fx = r.TakeFX_GetCount(tk)
        if fx > 0 then set_selected(it,1) else set_selected(it,0) end
      end


      if val=="rip" or val=="ripfx" then
        local pl = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
        local pt = r.GetMediaItemTakeInfo_Value(tk, "D_PITCH")
        local lp = r.GetMediaItemInfo_Value(it, "B_LOOPSRC")
        local m = r.GetMediaItemInfo_Value(it, "B_MUTE")
        local _, _, _, _, _, revrs = r.BR_GetMediaSourceProperties(tk)
        local cm = r.GetMediaItemTakeInfo_Value(tk,"I_CHANMODE")
        local fx

        if val=="ripfx" then
          fx = r.TakeFX_GetCount(tk)
        else
          fx=0
        end

        if pl~=1 or pt~=0 or lp==1 or m==1 or revrs==true or cm~=0 or fx>0 then
          r.SetMediaItemSelected(it, 1)
        else
          r.SetMediaItemSelected(it, 0)
        end
       end
    end
  end

  if val=="vol" or val=="all" then
    -- if item_vol == 1 then
      vol_count_show = "Items with Volume 0 db : "..v1.."\nItems with other Volume : "..v2
    -- else
      -- vol_count_show = "Items with Volume "..item_vol_show.." db : "..v2.."\nItems with Volume 0 db : "..v1
    -- end
    vol_counted = true
  end
  if val=="pan" or val=="all" then
    -- if take_pan == 0 then
      pan_count_show = "Items with Pan 0 : "..pn1.."\nItems with other Pan : "..pn2
    -- else
      -- pan_count_show = "Items with Pan "..take_pan_show.." : "..pn2.."\nItems with Pan 0 : "..pn1
    -- end
    pan_counted = true
  end
  if val=="pitch" or val=="all" then
    -- if take_pitch == 0 then
      pitch_count_show = "Items with Pitch 0.0 : "..pt1.."\nItems with other Pitch : "..pt2
    -- else
      -- pitch_count_show = "Items with Pitch "..take_pitch_show.." st : "..pt2.."\nItems with Pitch 0.0 : "..pt1
    -- end
    pitch_counted = true
  end
  if val=="playrate" or val=="all" then
    -- if take_playrate == 1 then
      playrate_count_show = "Items with Playrate 1.00 : "..pr1.."\nItems with other Playrate : "..pr2
    -- else
      -- playrate_count_show = "Items with Playrate "..take_playrate_show.." : "..pr2.."\nItems with Playrate 1.00 : "..pr1
    -- end
    playrate_counted = true
  end
  if val=="loop" or val=="all" then
    loop_count_show = 'Looped items : '..lp1..'\nUnlooped items : '..lp2
    loop_counted = true
  end
  if val=="mute" or val=="all" then
    mute_count_show = 'Muted items : '..m1..'\nUnmuted items : '..m2
    mute_counted = true
  end
  if val=="lock" or val=="all" then
    lock_count_show = 'Locked items : '..l1..'\nUnlocked items : '..l2
    lock_counted = true
  end
  if val=="preserve_pitch" or val=="all" then
    prspitch_count_show = 'Preserve Pitched items : '..p1..'\nUnpreserve Pitched items: '..p2
    prspitch_counted = true
  end
  if val=="chan_mode" or val=="all" then
    chan_mode_count_show = "Items with Chan Mode 'Norm' : "..c1.."\nItems with Chan Mode 'Reverse' : "..c2.."\nItems with Chan Mode 'Mix L+R' : "..c3.."\nItems with Chan Mode 'L' : "..c4.."\nItems with Chan Mode 'R' : "..c5
    chan_mode_counted = true
  end
  if val=="reverse" or val=="all" then
    reverse_count_show = 'Reversed items : '..rv1..'\nUnreversed items : '..rv2
    reverse_counted = true
  end

  if val == "rip" or val == "all" then
    rip_count_show = "Items with Playrate 1.00 : "..pr1.."\nItems with other Playrate : "..pr2.."\n---------------------------------------------"
    ..'\nLooped items : '..lp1..'\nUnlooped items : '..lp2.."\n---------------------------------------------"
    ..'\nMuted items : '..m1..'\nUnmuted items : '..m2.."\n---------------------------------------------"
    ..'\nReversed items : '..rv1..'\nUnreversed items : '..rv2.."\n---------------------------------------------"
    .."\nItems with Chan Mode 'Norm' : "..c1.."\nItems with Chan Mode 'Reverse' : "..c2.."\nItems with Chan Mode 'Mix L+R' : "..c3.."\nItems with Chan Mode 'L' : "..c4.."\nItems with Chan Mode 'R' : "..c5
  end

  if sel_other~=nil then
    r.Undo_EndBlock("McS_MonitorToolbar", -1)
    r.UpdateArrange()
    all_counted = false
  else
    all_counted = true
  end
end


function render_in_place()--(Apply Take FX excluding ItemSendFx)
  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()

  local count_sel_items = r.CountSelectedMediaItems(0)
  if count_sel_items == 0 then return end

  local item_send_fx_name = "McS-Item Send 12 v2"

  local function apply_fx(t)
    for i=1,#t do
      r.Main_OnCommand(40289,0) -- Item: Unselect (clear selection of) all items
      r.SetMediaItemInfo_Value(t[i].item,"D_VOL", 1)
      r.SetMediaItemSelected(t[i].item, 1)
      if t[i].item_send_fx_num~=-1 then
        r.TakeFX_SetParam(t[i].take, t[i].item_send_fx_num, #t[i].item_send_fx_param-2, 1)
      end
      r.Main_OnCommand(42432, 0) --Item: Glue items
      local item = r.GetSelectedMediaItem(0,0)
      t[i].item = item
      local take = r.GetActiveTake(item)
      if take and not r.TakeIsMIDI(take) then
        r.SetMediaItemInfo_Value(item,"D_VOL", t[i].vol)
        if t[i].item_send_fx_num~=-1 then
          local item_send_fx_num = r.TakeFX_AddByName(take, item_send_fx_name, 1)
          for j=1,#t[i].item_send_fx_param do
            r.TakeFX_SetParam(take, item_send_fx_num, j, t[i].item_send_fx_param[j])
          end
        end
      end
    end
  end

  local function select_on(t)
    for i=1,#t do
      r.SetMediaItemSelected(t[i].item, 1)
    end
  end

  local items = {}

  for i=0,count_sel_items-1 do
    local item = r.GetSelectedMediaItem(0, i)
    local vol = r.GetMediaItemInfo_Value(item,"D_VOL")
    r.SetMediaItemInfo_Value(item,"D_VOL",1)
    local take = r.GetActiveTake(item)
    if take and not r.TakeIsMIDI(take) then
      local fx_count =  r.TakeFX_GetCount(take)
      local item_send_fx_num = -1
      local item_send_fx_param = {}
      if fx_count>0 then
        for j=0,fx_count-1 do
          item_send_fx_num = r.TakeFX_AddByName(take, item_send_fx_name, 0)
          if item_send_fx_num~=-1 then
            local fx_param_cnt = r.TakeFX_GetNumParams(take, j)
            for p=0, fx_param_cnt-1 do
              item_send_fx_param[p] = r.TakeFX_GetParam(take, j, p)
              local rt, parname = r.TakeFX_GetParamName(take, j, p)
              -- Msg(p)
              -- Msg(parname)
              -- Msg(item_send_fx_param[p])
            end
          end   
        end
      end
      items[#items+1] = {item=item, take=take, vol=vol, item_send_fx_num=item_send_fx_num,
                        item_send_fx_param=item_send_fx_param}
    end
  end

  if #items>0 then apply_fx(items) end


  r.Undo_EndBlock("Apply Take FX", -1)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end

function get_item_params(item, take)
  local source_length, sample_rate, num_channels, bitdepth, bitrate, 
  filename, path, name, ext, name_ext = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil

  local take_off = r.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS")
  local st = r.GetMediaItemInfo_Value(item,"D_POSITION")
  local ln = r.GetMediaItemInfo_Value(item,"D_LENGTH")
  local en = st + ln

  local loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC")
  local mute = r.GetMediaItemInfo_Value(item, "B_MUTE")
  local lock = r.GetMediaItemInfo_Value(item, "C_LOCK")
  local _, _, _, _, _, reverse = r.BR_GetMediaSourceProperties(take)
  local vol = r.GetMediaItemInfo_Value(item, "D_VOL")
  local pan = r.GetMediaItemTakeInfo_Value(take, "D_PAN")
  local pitch = r.GetMediaItemTakeInfo_Value(take, "D_PITCH")
  local playrate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local preserve_pitch = r.GetMediaItemTakeInfo_Value(take,"B_PPITCH")
  local cm = r.GetMediaItemTakeInfo_Value(take,"I_CHANMODE")
  local fx = r.TakeFX_GetCount(take)
  local count_env = r.CountTakeEnvelopes(take)
  -- local ret, item_chunk = r.GetItemStateChunk(item, "", false)
  local source = r.GetMediaItemTake_Source(take)
  if source then
    source_length = r.GetMediaSourceLength(source)
    sample_rate = r.GetMediaSourceSampleRate(source)
    num_channels = r.GetMediaSourceNumChannels(source)
    bitdepth = r.CF_GetMediaSourceBitDepth(source)
    bitrate = r.CF_GetMediaSourceBitRate(source)
    filename = r.GetMediaSourceFileName(source)
    filename = filename:gsub([[\\]], [[\]])
    filename = filename:gsub([[/]], [[\]])
    path, name, ext = string.match(filename, "(.-)([^\\]-)%p([^%.]+)$")
    path = path:match("(.+)\\$") -- delete last "\"" in path
    name_ext = name.."."..ext

  end
  return {item=item, take=take, st=st, ln=ln, en=en, take_off=take_off,
  loop=loop, mute=mute, lock=lock, reverse=reverse, cm=cm, fx=fx, -- item_chunk=item_chunk,
  vol=vol, pan=pan, pitch=pitch, playrate=playrate, preserve_pitch=preserve_pitch,
  source=source, source_length=source_length, sample_rate=sample_rate, 
  num_channels=num_channels, bitdepth=bitdepth, bitrate=bitrate, count_env=count_env,
  filename=filename, path=path, name=name, ext=ext, name_ext=name_ext}
end

function get_sel_items_table()
  local sel_item = {}
  local count_sel_items = r.CountSelectedMediaItems(0)
  for i=0,count_sel_items-1 do
    local item = r.GetSelectedMediaItem(0, i)
    local take = r.GetActiveTake(item)
    if take and not r.TakeIsMIDI(take) then
      table.insert(sel_item, get_item_params(item, take))
    end
  end
  return sel_item
end

function remove_overlapped_items_ie_doubles()
  local inac = 0.000001
  local count = 0
  local count_track = r.CountTracks(0)
  for t=0,count_track-1 do
    local track = r.GetTrack(0,t)
    local count_item = r.CountTrackMediaItems(track)
    if count_item>1 then
      for i=count_item-2,0,-1 do
        local item1 = r.GetTrackMediaItem(track,i)
        local item2 = r.GetTrackMediaItem(track,i+1)
        if item1 and item2 then
          local st1 = r.GetMediaItemInfo_Value(item1,"D_POSITION")
          local ln1 = r.GetMediaItemInfo_Value(item1,"D_LENGTH")
          local en1 = st1 + ln1
  
          local st2 = r.GetMediaItemInfo_Value(item2,"D_POSITION")
          local ln2 = r.GetMediaItemInfo_Value(item2,"D_LENGTH")
          local en2 = st2 + ln2

          if in_range_equal(st1, st2-inac, en2+inac) and in_range_equal(en1, st2-inac, en2+inac) or 
             in_range_equal(st2, st1-inac, en1+inac) and in_range_equal(en2, st1-inac, en1+inac)then
            count = count +1
            if ln1 == ln2 then
              r.DeleteTrackMediaItem(track, item2)
            elseif ln1<ln2 then
              r.DeleteTrackMediaItem(track, item1)
            elseif ln2<ln1 then
              r.DeleteTrackMediaItem(track, item2)
            end
          end
        end
      end
    end
  end
  return count
end

function spread_mono_stereo_multichannel_items_to_according_tracks()
  local count = 0
  local count_track = r.CountTracks(0)
  for t=count_track-1,0,-1 do
    local track = r.GetTrack(0,t)
    local count_item = r.CountTrackMediaItems(track)
    if count_item>1 then
      local ch = {}
      local ch_init
      local it ={}
      for i=0,count_item-1 do
        table.insert(it, r.GetTrackMediaItem(track,i))
      end      

      for i=1, #it do
        local item = it[i]
        local take = r.GetActiveTake(item)
        if take and not r.TakeIsMIDI(take) then
          local source = r.GetMediaItemTake_Source(take)
          local _, _, _, _, _, reversed = r.BR_GetMediaSourceProperties(take)
          if reversed == true then
            source = r.GetMediaSourceParent(source)
          end
          local num_chan = r.GetMediaSourceNumChannels(source)

          if i==1 then
            ch[num_chan] = track
            ch_init = num_chan
          else
            if not ch[num_chan] then
              r.SetOnlyTrackSelected(track)
              r.Main_OnCommand(40062, 0) -- Track: Duplicate tracks
              r.Main_OnCommand(r.NamedCommandLookup("_SWS_DELALLITEMS"), 0) -- SWS: Delete all items on selected track(s)
              local tr = r.GetSelectedTrack(0,0)
              ch[num_chan] = tr
            end
            if num_chan~=ch_init then
              r.MoveMediaItemToTrack(item, ch[num_chan])
            end
          end
        end
      end
    end
  end
end


function find_files_for_remove_convert_copy_render(proj_media_path)


  local count_sel_items = r.CountSelectedMediaItems(0)
  if count_sel_items == 0 then return {},{},{},{},{} end

  for i=count_sel_items-1,0,-1 do
    local item = r.GetSelectedMediaItem(0, i)
    local track = r.GetMediaItem_Track(item)
    local mute = r.GetMediaItemInfo_Value(item, "B_MUTE")
    if mute == 1 then
      r.DeleteTrackMediaItem(track, item)
    end
  end

  local sel_item = get_sel_items_table()
  local item_idx_to_render = {}
  local item_idx_to_change_source = {}
  local file_for_copying = {}
  local file_for_copying_exist = {}
  local file_for_ffconv = {}
  local file_for_ffconv_exist = {}
  for i=1, #sel_item do
    
    local gone_to_render = false

    if sel_item[i].playrate~=1 or sel_item[i].pitch~=0 or 
      sel_item[i].reverse==true or sel_item[i].cm~=0 or 
      sel_item[i].fx>0 or sel_item[i].count_env>0 then
        
      table.insert(item_idx_to_render, i)
      if sel_item[i].source_length>0 then
        gone_to_render = true
      else
         -- go to ffmpeg if wrong source (source_length==0)
      end
    end

    if not gone_to_render then
      -- Msg(sel_item[i].source_length)
      -- Msg(bitdepth)
      -- Msg(sample_rate)
      -- Msg()
      local path, name, ext = sel_item[i].path, sel_item[i].name, sel_item[i].ext
      local name_ext = sel_item[i].name_ext
  
      local gone_to_ffconv = false
      local gone_to_filecopy = false

      if sel_item[i].source_length==0 or ext~="wav" or sel_item[i].bitdepth~=24 or sel_item[i].sample_rate~=48000 then
        gone_to_ffconv = true
        if not file_for_ffconv_exist[name_ext] then -- ignore the same name files from different folders
          file_for_ffconv_exist[name_ext] = true
          table.insert(file_for_ffconv, {filename=sel_item[i].filename, 
                                         path=sel_item[i].path, 
                                         name=sel_item[i].name, 
                                         ext=sel_item[i].ext, 
                                         name_ext=sel_item[i].name_ext, 
                                         idx=i})
        end
      end
    
      if gone_to_ffconv==false and path~=proj_media_path then
        gone_to_filecopy = true
        if not file_for_copying_exist[name_ext] then
          file_for_copying_exist[name_ext] = true
          table.insert(file_for_copying, {filename=sel_item[i].filename,
                                          path=sel_item[i].path, 
                                          name=sel_item[i].name, 
                                          ext=sel_item[i].ext, 
                                          name_ext=sel_item[i].name_ext, 
                                          idx=i})
        end
      end
      if gone_to_ffconv or gone_to_filecopy then
        table.insert(item_idx_to_change_source,i)
      end
    end
  end
  -- Msg(#item_idx_to_change_source)
  return item_idx_to_render, file_for_ffconv, file_for_copying, item_idx_to_change_source, sel_item
end

function file_copy(filename, new_filename, overwrite)
  if r.file_exists(filename) then
    if overwrite or (not overwrite and not r.file_exists(new_filename)) then
      local file = io.open(filename, "rb")
      local content = file:read("*all")
      local new_file = io.open(new_filename, "wb")
      new_file:write(content)
      new_file:close()
      file:close()
      return true
    end
  end
  return false
end

function ffmpeg_convert(path, name, ext, temp_path)

  local input_file = path..sep..name.."."..ext
  local output_file = temp_path..sep..name..".wav"
  local ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
  local arguments = ' -acodec pcm_s24le -ar 48000 '
  local command = '"'..ffmpeg_file..'"'.." -y -i "..'"'..input_file..'"'..arguments..'"'..output_file..'"'
  
  -- Msg(command)
  if windows then
    local retval = r.ExecProcess(command, 0)
  else
    os.execute(command)
  end
end

function convert_for_exporting_to_nuendo_and_protools(mode)
  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()

  remove_overlapped_items_ie_doubles()

  local rt, proj = r.EnumProjects(-1)
  local proj_smp_rate_used = r.GetSetProjectInfo(project, "PROJECT_SRATE_USE", 0, false)
  local proj_smp_rate = r.GetSetProjectInfo(project, "PROJECT_SRATE", 0, false)

  if proj_smp_rate_used==0 then
    proj_smp_rate_used=1
    r.GetSetProjectInfo(project, "PROJECT_SRATE_USE", proj_smp_rate_used, true)
  end
  if proj_smp_rate~=48000 then
    proj_smp_rate=48000
    r.GetSetProjectInfo(project, "PROJECT_SRATE", proj_smp_rate, true)
  end

  local rtval, rec_path = r.GetSetProjectInfo_String(proj, "RECORD_PATH" , "", false)
  local proj_media_path = r.GetProjectPath()
  local rec_path_was_nil = false
  if rec_path=="" or rec_path==nil then rec_path_was_nil=true rec_path="Audio Files" end
  

  if not proj_media_path:match(rec_path) then
    proj_media_path = proj_media_path..sep..rec_path
    r.RecursiveCreateDirectory(proj_media_path, 0)
  end

  local temp_folder = "FFMPEG_Temp"
  local temp_path = proj_media_path..sep..temp_folder

  local item_idx_to_render, file_for_ffconv, file_for_copying, item_idx_to_change_source, sel_item = 
        find_files_for_remove_convert_copy_render(proj_media_path)
  if #sel_item==0 then return end

---[[
  ----Set media OFFLINE----
    r.Main_OnCommand(42356, 0) --Item: Toggle force media offline


  ----FFMPEG Convert to temp folder----
  if #file_for_ffconv>0 then
    r.RecursiveCreateDirectory(temp_path, 0)

    for i=1,#file_for_ffconv do
      local filename = file_for_ffconv[i].filename
      local idx = file_for_ffconv[i].idx

      local path, name, ext = file_for_ffconv[i].path ,file_for_ffconv[i].name, file_for_ffconv[i].ext
      if path~=nil and name~=nil and ext~=nil then

        ffmpeg_convert(path, name, ext, temp_path)

        -- if path~=proj_media_path or ext~="wav" then
          -- table.insert(item_idx_to_change_source, idx)
        -- end
      end
    end
  end

  ----Copy files from other paths that of no need to convert----
  if #file_for_copying>0 then
    for i=1,#file_for_copying do
      local filename = file_for_copying[i].filename
      local idx = file_for_copying[i].idx
      local path, name, ext = file_for_copying[i].path ,file_for_copying[i].name, file_for_copying[i].ext

      local new_filename = proj_media_path..sep..name..".".."wav"
      if file_copy(filename, new_filename, false) then --last flag is overwrite
        -- table.insert(item_idx_to_change_source, idx)
      end
    end
  end


  ----Change source of copied and FFMPEG converted files
  if #item_idx_to_change_source>0 then

    --move all FFMPEG converted files to "proj_media_path"
    if #file_for_ffconv>0 then
      for i=1,#file_for_ffconv do
        local filename = file_for_ffconv[i].filename
        local path, name, ext = file_for_ffconv[i].path ,file_for_ffconv[i].name, file_for_ffconv[i].ext
        filename = temp_path..sep..name..".".."wav"
        local new_filename = proj_media_path..sep..name..".".."wav"
        if r.file_exists(filename) then
          file_copy(filename, new_filename, true)
          assert(os.remove(filename))
        end
      end
    end

    ----Delete Temp Folder----
    assert(os.execute('rmdir "'..proj_media_path..sep..temp_folder..'"'))


    ----Set media ONLINE----
    r.Main_OnCommand(42356, 0) --Item: Toggle force media offline

    local old_source_to_destroy = {}

    ---- Changing Source of items ----
    -- Msg(#item_idx_to_change_source)
    for i=1,#item_idx_to_change_source do
      local idx = item_idx_to_change_source[i]
      local item = sel_item[idx].item
      local take = sel_item[idx].take
      local filename = sel_item[idx].filename
      local path, name, ext = sel_item[idx].path ,sel_item[idx].name, sel_item[idx].ext
      local ext_lower = string.lower(ext)
      local new_filename = proj_media_path..sep..name..".wav"


      if filename~=new_filename then
        -- Msg(filename)
        local old_source = r.GetMediaItemTake_Source(take)
        old_source_to_destroy[old_source] = true

        local new_source = r.PCM_Source_CreateFromFile(new_filename)
        local ret_change_source = r.SetMediaItemTake_Source(take, new_source)

        sel_item[idx].source = new_source
        sel_item[idx].filename = new_filename
        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name..".wav", true)
        -- if new_filename:match("Фон") then
          -- Msg(new_filename)
          -- Msg("new_source")
          -- Msg(new_source)
          -- Msg("ret_change_source")
          -- Msg(ret_change_source)
        -- end
      end
    end

    ---- Destroy old sources for further removing old files
    if next(old_source_to_destroy)~=nil then
      for k,v in pairs(old_source_to_destroy) do
        r.PCM_Source_Destroy(k)
      end
    end

    r.Main_OnCommand(40441, 0) --Peaks: Rebuild peaks for selected items

  end

  ----Render Items----
  if #item_idx_to_render>0 then
    for i=1,#item_idx_to_render do
      local idx = item_idx_to_render[i]
      r.Main_OnCommand(40289,0) -- Item: Unselect (clear selection of) all items
      r.SetMediaItemInfo_Value(sel_item[idx].item,"D_VOL", 1)
      r.SetMediaItemSelected(sel_item[idx].item, 1)
      r.Main_OnCommand(42432, 0) --Item: Glue items
      -- Msg(sel_item[idx].filename)
      local item = r.GetSelectedMediaItem(0,0)
      sel_item[idx].item = item
      local take = r.GetActiveTake(item)
      sel_item[idx].take = take
      r.SetMediaItemInfo_Value(item,"D_VOL", sel_item[idx].vol)
    end
  end

  r.Main_OnCommand(40182, 0) --Item: Select all items
  fix_looped_items(false, false)
  -- r.Main_OnCommand(40289,0) -- Item: Unselect (clear selection of) all items

  -- reorganize 1-2-M channel items to according track - ProTools needs it
  if mode==1 then
    spread_mono_stereo_multichannel_items_to_according_tracks()
  end

  ---- Get sel_items again since items have new sources and filenames
  sel_item = get_sel_items_table()

  ---- Check and Delete Extra Files in Project Folder----
  local files = GetAllFilesInFolder(proj_media_path)
  if #files>0 then
    for i=1,#files do
      local filename = files[i].path..sep..files[i].name_ext
      local found = false
      for j=1,#sel_item do
        if filename==sel_item[j].filename then 
          found = true
          break
        end
      end
      if found==false then
        -- Msg(filename)
        assert(os.remove(filename))
      end
    end
  end

  r.Undo_EndBlock("Apply Take FX", -1)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()

  r.Main_OnCommand(1582, 0) --Project bay: Force refresh
--]]
end

function find_items_with_fx_name(fx_name_search)
  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()
  
  function select_item_if_fx_exist(item,fx_name_search)
    local active_take = r.GetActiveTake(item)
    if active_take then
      local takecount = r.CountTakes(item)
      for i=0,takecount-1 do
        local take = r.GetTake(item,i)
        local take_fx_count = r.TakeFX_GetCount(take)
        if take_fx_count ~= 0 then
          for j=0,take_fx_count-1 do
            local retval, fx_name = r.TakeFX_GetFXName(take,j)
            if retval and string.find(string.lower(fx_name),string.lower(fx_name_search)) then
              r.SetMediaItemSelected(item,1)
            end
          end
        end
      end
    end
  end
  
  local count_sel_items = r.CountSelectedMediaItems(0)
  if count_sel_items < 2 then
    r.Main_OnCommand(40289,0) -- Item: Unselect (clear selection of) all items
    local count_items = r.CountMediaItems(0)
    if count_items == 0 then return end
    for i=0,count_items-1 do
      select_item_if_fx_exist(r.GetMediaItem(0,i),fx_name_search)
    end
  else
    local t = {}
    for i=0,count_sel_items-1 do
      t[i+1] = r.GetSelectedMediaItem(0,i)
    end
    r.Main_OnCommand(40289,0) -- Item: Unselect (clear selection of) all items
    for i=1,#t do
      select_item_if_fx_exist(t[i],fx_name_search)
    end
  end
    
  r.Undo_EndBlock("Name of Action", -1)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end

function find_items_with_name(name_search)
  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()
  
  function select_item_if_name_match(item, name_search)
    local active_take = r.GetActiveTake(item)
    if active_take then
      local takecount = r.CountTakes(item)
      for i=0,takecount-1 do
        local take = r.GetTake(item,i)
        if take then
          local _, name = r.GetSetMediaItemTakeInfo_String(take, 'P_NAME', '', 0)
          name = string.lower(name)
          if name:match(name_search) then
            r.SetMediaItemSelected(item,1)
          end
        end
      end
    end
  end
  
  local count_sel_items = r.CountSelectedMediaItems(0)
  
  name_search = string.lower(name_search)

  if count_sel_items < 2 then
    r.Main_OnCommand(40289,0) -- Item: Unselect (clear selection of) all items
    local count_items = r.CountMediaItems(0)
    if count_items == 0 then return end
    for i=0,count_items-1 do
      select_item_if_name_match(r.GetMediaItem(0,i), name_search)
    end
  else
    local t = {}
    for i=0,count_sel_items-1 do
      t[i+1] = r.GetSelectedMediaItem(0,i)
    end
    r.Main_OnCommand(40289,0) -- Item: Unselect (clear selection of) all items
    for i=1,#t do
      select_item_if_name_match(t[i], name_search)
    end
  end
    
  r.Undo_EndBlock("Name of Action", -1)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end

function fix_looped_items(undo, select)
  if undo==true then
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock()
  end

  restrict_sel_items_st_en_to_source()

  count_sel_items = r.CountSelectedMediaItems(0)

  if count_sel_items>0 then
    for i= count_sel_items-1,0,-1 do
      local item = r.GetSelectedMediaItem(0,i)
      -- Msg()
      -- if r.ValidatePtr2(0, item, "MediaItem*") then
      -- local tk = r.GetActiveTake(it)
      -- if tk and not r.TakeIsMIDI(tk) then
      local item_loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC")
      local item_st = r.GetMediaItemInfo_Value(item,"D_POSITION")
      local item_ln = r.GetMediaItemInfo_Value(item,"D_LENGTH")
      local item_en = item_st + item_ln
      local take = r.GetActiveTake(item)
      -- Msg(take)
      -- take=nil
      if take and not r.TakeIsMIDI(take) then
        local take_off = r.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS")
        local playrate = r.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")        
        local source = r.GetMediaItemTake_Source(take)
        local source_length, lengthIsQN = r.GetMediaSourceLength(source)
        -- Msg(v)
        -- item_loop=0
        if item_loop==1 and source_length > 0 and item_ln > (source_length-take_off)/playrate then
          local fadein = r.GetMediaItemInfo_Value(item, "D_FADEINLEN")
          local fadein_auto = r.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO")
          local fadein_dir = r.GetMediaItemInfo_Value(item, "D_FADEINDIR")
          local fadein_shape = r.GetMediaItemInfo_Value(item, "C_FADEINSHAPE")
          local fadeout = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
          local fadeout_auto = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO")
          local fadeout_dir = r.GetMediaItemInfo_Value(item, "D_FADEOUTDIR")
          local fadeout_shape = r.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE")
          local ret, chunk = r.GetItemStateChunk(item, "", false)
          local track = r.GetMediaItem_Track(item)
  
          item_ln = (source_length - take_off)/playrate
          r.SetMediaItemInfo_Value(item, "D_LENGTH", item_ln)
          
          if item_ln < fadein then
            fadein = item_ln - xfadetime
            r.SetMediaItemInfo_Value(item, "D_FADEINLEN", fadein)
            r.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", fadein)
          end
          r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", xfadetime)
          r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", xfadetime)
          -- r.SetMediaItemInfo_Value(item, "D_FADEOUTDIR", fadeout_dir)
          r.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", xfadeshape)
          r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
  
  
          local new_item = item
          local new_item_en = item_st + (source_length - take_off)/playrate
  
          while new_item_en < item_en do
            new_item = r.AddMediaItemToTrack(track)
  
            local new_chunk = chunk:gsub('({.-})', function() return r.genGuid() end)
            r.SetItemStateChunk(new_item, new_chunk, false)
  
            local new_take = r.GetActiveTake(new_item)
  
            local new_item_st = new_item_en - xfadetime
            local new_item_ln = source_length/playrate
            new_item_en = new_item_st + source_length/playrate
  
            local new_item_fadein = xfadetime
            local new_item_fadein_auto = xfadetime
            -- local new_item_fadein_dir = fadeout_dir
            local new_item_fadein_dir = 0
            local new_item_fadein_shape = xfadeshape
  
            local new_item_fadeout = xfadetime
            local new_item_fadeout_auto = xfadetime
            -- local new_item_fadeout_dir = fadeout_dir
            local new_item_fadeout_dir = 0
            local new_item_fadeout_shape = xfadeshape
  
            local new_item_snap_off = 0
            local new_take_off = 0
  
            r.SetMediaItemInfo_Value(new_item, "D_POSITION", new_item_st)
            r.SetMediaItemInfo_Value(new_item, "D_LENGTH", new_item_ln)
  
            r.SetMediaItemInfo_Value(new_item, "D_FADEINLEN", new_item_fadein)
            r.SetMediaItemInfo_Value(new_item, "D_FADEINLEN_AUTO", new_item_fadein_auto)
            r.SetMediaItemInfo_Value(new_item, "D_FADEINDIR", new_item_fadein_dir)
            r.SetMediaItemInfo_Value(new_item, "C_FADEINSHAPE", new_item_fadein_shape)
  
            r.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", new_item_fadeout)
            r.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN_AUTO", new_item_fadeout_auto)
            r.SetMediaItemInfo_Value(new_item, "D_FADEOUTDIR", new_item_fadeout_dir)
            r.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", new_item_fadeout_shape)
            r.SetMediaItemInfo_Value(new_item, "B_LOOPSRC", 0)
  
            r.SetMediaItemInfo_Value(new_item, "D_SNAPOFFSET", new_item_snap_off)
            r.SetMediaItemTakeInfo_Value(new_take,"D_STARTOFFS", new_take_off)
            r.SetMediaItemTakeInfo_Value(new_take,"D_PLAYRATE", playrate)
          end
  
          if new_item_en > item_en then
            local r_item = r.SplitMediaItem(new_item, item_en)
            if r_item then r.DeleteTrackMediaItem(track, r_item) end
            new_item_ln = r.GetMediaItemInfo_Value(new_item,"D_LENGTH")
            local out_ln = new_item_ln-xfadetime
            if fadeout > out_ln then
              fadeout = out_ln
              fadeout_auto = out_ln
            end
            r.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN", fadeout)
            r.SetMediaItemInfo_Value(new_item, "D_FADEOUTLEN_AUTO", fadeout_auto)
            r.SetMediaItemInfo_Value(new_item, "D_FADEOUTDIR", fadeout_dir)
            r.SetMediaItemInfo_Value(new_item, "C_FADEOUTSHAPE", fadeout_shape)
          end
        else
          if select==true then
            r.SetMediaItemSelected(item, 0)
          end
          if item_loop==1 then
            r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
          end
        end
      else
        r.SetMediaItemSelected(item, 0)
      end
    end
  end

  if undo==true then
    r.Undo_EndBlock("McS_MonitorToolbar", -1)
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
  end
end

function restrict_sel_items_st_en_to_source()
  local count_sel_items = r.CountSelectedMediaItems(0)
  if count_sel_items>0 then
    for i=0, count_sel_items-1 do
      local item = r.GetSelectedMediaItem(0,i)
      local loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC")
      local st = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local ln = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      local en = st + ln
      local old_st = st
      local fadein = r.GetMediaItemInfo_Value(item, "D_FADEINLEN")
      local fadein_auto = r.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO")
      local fadein_shape = r.GetMediaItemInfo_Value(item, "C_FADEINSHAPE")
      local fadein_dir = r.GetMediaItemInfo_Value(item, "D_FADEINDIR")
      local fadeout = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN")
      local fadeout_auto = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO")
      local fadeout_shape = r.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE")
      local fadeout_dir = r.GetMediaItemInfo_Value(item, "D_FADEOUTDIR")
      local take = r.GetActiveTake(item)
      if take and not r.TakeIsMIDI(take) then
        local take_off = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        local playrate = r.GetMediaItemTakeInfo_Value(take,"D_PLAYRATE")
        local source = r.GetMediaItemTake_Source(take)
        local source_ln = r.GetMediaSourceLength(source)        
        if take_off < 0 then
          local val = abs(take_off/playrate)
          if fadein/2 > val then
            fadein = fadein - val
            fadein_auto = fadein
            local f = false
            if fadein_shape == 0 then
              fadein_shape = 1 f = true
            elseif fadein_shape == 1 then
              fadein_shape = 3 f = true
            elseif fadein_shape == 4 then
              fadein_shape = 2 f = true
            elseif fadein_shape == 2 then
              fadein_shape = 0 f = true
            end
            if f then r.SetMediaItemInfo_Value(item, "C_FADEINSHAPE", fadein_shape) end
          else
            fadein = 0
            fadein_auto = 0
          end
          r.SetMediaItemInfo_Value(item, "D_FADEINLEN", fadein)
          r.SetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO", fadein_auto)
          st = (st*playrate-take_off)/playrate
          ln = ln - (st - old_st)
          take_off = 0
          r.SetMediaItemInfo_Value(item, "D_POSITION", st)
          r.SetMediaItemInfo_Value(item, "D_LENGTH", ln)
          r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", take_off)
        end

        if loop==0 and ln > source_ln/playrate then

          local val = ln - source_ln/playrate
          if fadeout/2 > val then
            fadeout = fadeout - val
            fadeout_auto = fadeout
            local f = false
            if fadeout_shape == 0 then
              fadeout_shape = 1 f = true
            elseif fadeout_shape == 1 then
              fadeout_shape = 3 f = true
            elseif fadeout_shape == 4 then
              fadeout_shape = 2 f = true
            elseif fadeout_shape == 2 then
              fadeout_shape = 0 f = true
            end
            if f then r.SetMediaItemInfo_Value(item, "C_FADEOUTSHAPE", fadeout_shape) end
          else
            fadeout = 0
            fadeout_auto = 0
          end
          r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", fadeout)
          r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", fadeout_auto)

          ln = (source_ln - take_off)/playrate
          r.SetMediaItemInfo_Value(item, "D_LENGTH", ln)
        end
      end
    end
  end
end


function move_reels_or_episodes_to_hours_accordingly()

  local count_sel_items = r.CountSelectedMediaItems(0)
  if count_sel_items == 0 then return end

  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()
  
  local tr = {}

  local count_track = r.CountTracks(0)
  for i=0,count_track-1 do
    local track = r.GetTrack(0,i)
    local count_item = r.CountTrackMediaItems(track)
    if count_item>0 then
      local it = {}
      for j=0,count_item-1 do
        local item = r.GetTrackMediaItem(track,j)
        if r.IsMediaItemSelected(item) then
          it[#it+1] = item
        end
      end
      tr[#tr+1] = {track = par_track, item = it}
    end
  end

  for i=1,#tr do
    for j=1,#tr[i].item do
      local pos = j*3600
      r.SetMediaItemInfo_Value(tr[i].item[j], "D_POSITION", pos)
      r.AddProjectMarker2(0, 0, pos, 0, j.." серия", 100+j, 0)
    end
  end

  r.Undo_EndBlock("Move Reels or Episodes to its Hour", -1)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end

function draw_separator_text(text, border_size, text_col, sep_col, x_align, y_align, y_spacing)
  ImGui.PushFont(ctx, font, font_size)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_col)
  ImGui.PushStyleColor(ctx, ImGui.Col_Separator, sep_col)
  ImGui.PushStyleVar (ctx, ImGui.StyleVar_SeparatorTextBorderSize, border_size)
  ImGui.PushStyleVar (ctx, ImGui.StyleVar_SeparatorTextAlign, x_align, y_align)
  if y_spacing then
    local spx, spy = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, spx, y_spacing)
  end
  ImGui.SeparatorText(ctx, text)
  if y_spacing then
    ImGui.PopStyleVar(ctx)
  end
  ImGui.PopStyleVar(ctx, 2)
  ImGui.PopStyleColor(ctx, 2)
  ImGui.PopFont(ctx)
end


function framework()
  -- is_docked = ImGui.IsWindowDocked(ctx)
  -- if is_docked == true then
  -- end
  -- if ImGui.IsWindowHovered(ctx) then ImGui.SetNextWindowFocus(ctx) end

  mw_x, mw_y = ImGui.GetWindowPos(ctx)
  mw_w, mw_h = ImGui.GetWindowSize(ctx)


  -- local keymods = ImGui.GetKeyMods(ctx)
  ctrl = r.JS_Mouse_GetState(4) == 4 --CTRL
  shift = r.JS_Mouse_GetState(8) == 8 --SHIFT
  alt = r.JS_Mouse_GetState(16) == 16 --ALT
  super = r.JS_Mouse_GetState(32) == 32 --WIN
  -- MBL = ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left)
  -- MBК = ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right)
  MBL = r.JS_Mouse_GetState(1) == 1 --left mouse button
  MBR = r.JS_Mouse_GetState(2) == 2 --right mouse button
  MBM = r.JS_Mouse_GetState(64) == 64 --middle mouse button


  --Set Edit Cursor to Mouse Cursor - no snapping
  local window, segment, details = r.BR_GetMouseCursorContext()
  if window == "arrange" and MBM and shift and not ctrl and not alt and not super then
    local pos = r.BR_GetMouseCursorContext_Position()
    r.SetEditCurPos(pos, 0, 0)
  end

  -- local key_alt = ImGui.IsKeyDown(ctx, ImGui.Mod_Alt)
  -- local key_ctrl = ImGui.IsKeyDown(ctx, ImGui.Mod_Ctrl)
  -- local key_shift = ImGui.IsKeyDown(ctx, ImGui.Mod_Shift)
  -- local key_super = ImGui.IsKeyDown(ctx, ImGui.Mod_Super)
  -- if key_alt==true then key_alt=1 elseif key_alt==false then key_alt=0 end
  -- if key_ctrl==true then key_ctrl=1 elseif key_ctrl==false then key_ctrl=0 end
  -- if key_shift==true then key_shift=1 elseif key_shift==false then key_shift=0 end
  -- if key_super==true then key_super=1 elseif key_super==false then key_super=0 end
  -- framerate = tostring(key_alt)..tostring(key_ctrl)..tostring(key_shift)..tostring(key_super)
  set_monitor_toolbar_autofocus()

  if prev_mw_w~=mw_w or prev_mw_h~=mw_h then
    update_sizes(ctx)
     prev_mw_w = mw_w
     prev_mw_h = mw_h
  end

  -- local function get_track_into_view(actual_item)
    -- local st = r.GetMediaItemInfo_Value(actual_item,"D_POSITION")
    -- r.SetEditCurPos(st, true, false)
    -- local track = r.GetMediaItem_Track(actual_item)    
    -- r.SetOnlyTrackSelected(track)
-- 
    -- local track_tcpy = r.GetMediaTrackInfo_Value( track, "I_TCPY")
    -- local track_tcph = r.GetMediaTrackInfo_Value( track, "I_TCPH")
    -- local mainHWND = r.GetMainHwnd()
    -- local windowHWND = r.JS_Window_FindChildByID(mainHWND, 1000)
    -- local scroll_retval, scroll_position, scroll_pageSize, scroll_min, scroll_max, scroll_trackPos = r.JS_Window_GetScrollInfo( windowHWND, "v" )
    -- if track_tcpy<0 then --track_tcpy<3*track_tcph
      -- r.JS_Window_SetScrollPos( windowHWND, "v", scroll_position + track_tcpy-3*track_tcph)
    -- elseif track_tcpy>scroll_pageSize-track_tcph then --track_tcpy>scroll_pageSize-4*track_tcph
      -- r.JS_Window_SetScrollPos( windowHWND, "v", scroll_position + track_tcpy - (floor(scroll_pageSize/track_tcph)-4)*track_tcph)
    -- end
      -- r.Main_OnCommand(40913, 0) --Track: Vertical scroll selected tracks into view
  -- end


  if r.HasExtState("McS-Tools", "Validate_Actual_Item_num") and
    r.GetExtState("McS-Tools", "Validate_Actual_Item_num")~= "" then
    local ac_it_num = tonumber(r.GetExtState("McS-Tools", "Validate_Actual_Item_num"))
    r.SetExtState("McS-Tools", "Validate_Actual_Item_num", "", false)
    -- Msg(ac_it_num)
    -- Msg(current_state)

  if ac_it_num == -1 then
    actual_item_num = nil
  else
    actual_item_num = ac_it_num
    actual_item = r.GetSelectedMediaItem(0,actual_item_num-1)
    save_actual_item_guid()
    update_actual_item(actual_item_guid)
  end

    -- if count_sel_items > 1 then
      -- get_track_into_view(actual_item)
    -- else
      -- if actual_item_num == -1 then actual_item_num=nil else Msg("Wrong actual_item_num :"..actual_item_num)end
    -- end
  end

  if r.HasExtState("McS-Tools", "Update_Actual_Item") and 
    r.GetExtState("McS-Tools", "Update_Actual_Item")~= "" then
    initial_state = -1
    r.SetExtState("McS-Tools", "Update_Actual_Item", "", false)
  end

  current_state = r.GetProjectStateChangeCount(0) -- проверяем каждый current_state
  if current_state ~= initial_state or init_performed == false then
    -- Msg(current_state)
    get_on_projectstate_changed()
    get_set_mon_fx_volume(-1)
    get_set_monitorsolo(-1,nil,nil)
    refresh_actual_item()
    update_actual_item(actual_item_guid, false) -- на каждом current_state параметры могут смениться, поэтому вызываем эту функцию здесь
    initial_state = current_state
    init_performed = true
  end

  -- if r.HasExtState("McS-Tools", "InitializeVol") and 
    -- r.GetExtState("McS-Tools", "InitializeVol")~= "" then
    -- local val = r.GetExtState("McS-Tools", "InitializeVol")
    -- r.SetExtState("McS-Tools", "InitializeVol", "", false)
  -- end


  if r.HasExtState("McS-Tools", "To_MonitorToolbar_Actual_Item_value_changed") and 
    r.GetExtState("McS-Tools", "To_MonitorToolbar_Actual_Item_value_changed")~= "" then
    local val = r.GetExtState("McS-Tools", "To_MonitorToolbar_Actual_Item_value_changed")
    -- initialize_item_vol_delta(0)
    -- set_all_selected_items_params("vol",tonumber(val))
    -- update_item_vol_delta_by_mousewheel()

    initialize_item_vol_delta(0)
    validate_sel_items(val)

    item_vol_db_delta = item_vol_db_delta + tonumber(val)
    update_actual_item(actual_item_guid, false)
    update_item_vol_delta_by_mousewheel()
    r.SetExtState("McS-Tools", "To_MonitorToolbar_Actual_Item_value_changed", "", false)
  end

  ---  Get Ripple ---

  -- if r.time_precise() > scan_time_init + 1 then -- scan for fps and ripple mode
    -- get_ripple = r.GetToggleCommandStateEx(0,1155)
    -- scan_time_init = r.time_precise()
  -- end  
-- 
  -- if get_ripple ~= 0 then
    -- if r.time_precise() > ripple_time_init + 0.35 then -- flash and unflash red sign
      -- ripple_on = 1 - ripple_on
      -- ripple_time_init = r.time_precise()
    -- end
  -- 
    -- if ripple_on == 1 then
      -- background_color = colors.activeColor_red
    -- else
      -- background_color = colors.black
    -- end
  -- else
    -- background_color = colors.black
    -- ripple_time_init = 0
  -- end

  ---Graphic---
  ImGui.PushFont(ctx, font, font_size)

  vol1_color = colors.yellow8
  vol1t_color = colors.grey6
  vol2_color = colors.yellow8
  pan1_color = colors.green75
  pan1t_color = colors.grey6
  pan2_color = colors.green75
  pitch1_color = colors.violet85
  pitch1t_color = colors.grey6
  pitch2_color = colors.violet85
  playrate1_color = colors.blue8
  playrate1t_color = colors.grey6
  playrate2_color = colors.blue8
  playrate_pitch_color1 = colors.grey4
  playrate_pitch_color2 = colors.violet85
  framerate_color = colors.grey5
  mon_color = colors.grey5

  if not MBL then--left mouse button
    pan_init_mouse_x = nil
    pan_init_delta = false
    pan_mouse_delta, prev_pan_mouse_delta = 0,0
  end

  if rateL ~= 1 then 
    if in_range(mouse_x, mw_x+curr_sizes.playrate_lb[1]-init_left_space/2,mw_x+curr_sizes.framerate[1]-init_left_space/2) and
      in_range(mouse_y, mw_y, mw_y+mw_h) and alt and ctrl and temp_rateL==0 then
      temp_rateL = 1
    elseif ((not in_range(mouse_x, mw_x+curr_sizes.playrate_lb[1]-init_left_space/2,mw_x+curr_sizes.framerate[1]-init_left_space/2) or
      not in_range(mouse_y, mw_y, mw_y+mw_h)) or (not alt or not ctrl)) and temp_rateL==1 then
      temp_rateL = 0
    end
  end

  local enable_length_change
  if rateL == 1 or temp_rateL == 1 then
    enable_length_change = "change_length"
  else
    enable_length_change = "no_change_length"
  end


  local mwheel_val = ImGui.GetMouseWheel(ctx)
  mouse_x, mouse_y = ImGui.GetMousePos(ctx)

  ---- undo delta to all params
  if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and
      alt and ctrl and shift and not super then 
      r.Undo_BeginBlock()
    set_all_selected_items_params("vol","init")
    set_all_selected_items_params("pan","init")
    set_all_selected_items_params("pitch","init")
    set_all_selected_items_params("playrate","init")
    set_all_selected_items_params("loop","init")
    set_all_selected_items_params("mute","init")
    set_all_selected_items_params("lock","init")
    set_all_selected_items_params("preserve_pitch","init")
    set_all_selected_items_params("chan_mode","init")
    set_reverse_all_selected_items_params("init")
    r.Undo_EndBlock("McS_MonitorToolbar_All reset", -1)
  end
  if ImGui.IsWindowHovered(ctx) and in_range(mouse_x, mw_x, mw_x+curr_sizes.vol_lb[1]-init_left_space/2) and
    in_range(mouse_y, mw_y, mw_y+mw_h) then 
    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      alt and ctrl and super and not shift then
      r.Undo_BeginBlock()
      set_all_selected_items_params("loop","init")
      set_all_selected_items_params("mute","init")
      set_all_selected_items_params("lock","init")
      set_all_selected_items_params("chan_mode","init")
      set_reverse_all_selected_items_params("init")
      r.Undo_EndBlock("McS_MonitorToolbar_All reset", -1)
    end
  elseif ImGui.IsWindowHovered(ctx) and in_range(mouse_x, mw_x+curr_sizes.vol_lb[1]-init_left_space/2,mw_x+curr_sizes.framerate[1]-init_left_space/2) and
    in_range(mouse_y, mw_y, mw_y+mw_h) then
    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      alt and ctrl and super and not shift then
      r.Undo_BeginBlock()
      set_all_selected_items_params("vol","init")
      set_all_selected_items_params("pan","init")
      set_all_selected_items_params("pitch","init")
      set_all_selected_items_params("playrate","init")
      set_all_selected_items_params("preserve_pitch","init")
      r.Undo_EndBlock("McS_MonitorToolbar_All reset", -1)
    end
  end
  if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and
      alt and ctrl and shift and super then 
      r.Undo_BeginBlock()
    set_all_selected_items_params("vol","default")
    set_all_selected_items_params("pan","default")
    set_all_selected_items_params("pitch","default")
    set_all_selected_items_params("playrate","default")
    set_all_selected_items_params("loop","default")
    set_all_selected_items_params("mute","default")
    set_all_selected_items_params("lock","default")
    set_all_selected_items_params("preserve_pitch","default")
    set_all_selected_items_params("chan_mode","default")
    set_reverse_all_selected_items_params(0)
    r.Undo_EndBlock("McS_MonitorToolbar_All reset", -1)
  end


  if in_range(mouse_x, mw_x+curr_sizes.vol_lb[1]-init_left_space/2,mw_x+curr_sizes.pan_lb[1]-init_left_space/2) and
    in_range(mouse_y, mw_y, mw_y+mw_h) and actual_item ~= -1 then
    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) 
      and not alt and not super and not ctrl and not shift then 
      ImGui.OpenPopup(ctx, "vol_edit", ImGui.PopupFlags_NoOpenOverExistingPopup)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      alt and not super and not ctrl and not shift then 
      r.Undo_BeginBlock()
      set_all_selected_items_params("vol","default")
      r.Undo_EndBlock("McS_MonitorToolbar_Vol reset", -1)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      alt and super and not ctrl and not shift then 
      r.Undo_BeginBlock()
      item_vol = 0
      set_all_selected_items_params("vol","current")
      -- update_actual_item(actual_item_guid, false)
      r.Undo_EndBlock("McS_MonitorToolbar_Vol reset -inf", -1)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      not alt and not super and ctrl and not shift then 
      r.Undo_BeginBlock()
      set_all_selected_items_params("vol","current") -- прописать во все items текущее значение
      r.Undo_EndBlock("McS_MonitorToolbar_Vol reset", -1)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      not alt and super and ctrl and not shift then 
      count_selected_items_with_params("vol",true)
    end
    if shift then
      if mwheel_val >0 then
        initialize_item_vol_delta(0)
        set_all_selected_items_params("vol",0.1)
        update_item_vol_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_item_vol_delta(0)
        set_all_selected_items_params("vol",-0.1)
        update_item_vol_delta_by_mousewheel()
      end
    elseif ctrl then
      if mwheel_val >0 then
        initialize_item_vol_delta(0)
        set_all_selected_items_params("vol",10)
        update_item_vol_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_item_vol_delta(0)
        set_all_selected_items_params("vol",-10)
        update_item_vol_delta_by_mousewheel()
      end
    else
      if mwheel_val >0 then
        initialize_item_vol_delta(0)
        set_all_selected_items_params("vol",1)
        update_item_vol_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_item_vol_delta(0)
        set_all_selected_items_params("vol",-1)
        update_item_vol_delta_by_mousewheel()
      end
    end
    vol1_color = colors.yellow9
    vol2_color = colors.yellow9
    vol1t_color = colors.grey7

    if super and ctrl and not shift and count_sel_items~=0 then -- tooltip
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, vol_count_show)
      ImGui.PopStyleColor(ctx,1)

      if all_counted == false then 
        count_selected_items_with_params("all")
      elseif vol_counted == false then
        count_selected_items_with_params("vol")
      end
    end
  elseif in_range(mouse_x, mw_x+curr_sizes.pan_lb[1]-init_left_space/2,mw_x+curr_sizes.pitch_lb[1]-init_left_space/2) and
    in_range(mouse_y, mw_y, mw_y+mw_h) and actual_item~=-1 then
    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) 
      and not alt and not super and not ctrl and not shift then 
      ImGui.OpenPopup(ctx, "pan_edit", ImGui.PopupFlags_NoOpenOverExistingPopup)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      alt and not super and not ctrl and not shift then 
      r.Undo_BeginBlock()
      set_all_selected_items_params("pan","default")
      r.Undo_EndBlock("McS_MonitorToolbar_Pan reset", -1)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      not alt and not super and ctrl and not shift then 
      r.Undo_BeginBlock()
      set_all_selected_items_params("pan","current") -- прописать во все items текущее значение
      r.Undo_EndBlock("McS_MonitorToolbar_Pan reset", -1)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      not alt and not super and not ctrl and not shift and
      pan_init_mouse_x == nil then
      pan_init_mouse_x = r.GetMousePosition()
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      not alt and super and ctrl and not shift then 
      count_selected_items_with_params("pan",true)
    end

    if shift then
      if mwheel_val >0 then
        initialize_take_pan_delta(0)
        set_all_selected_items_params("pan",-0.01)
        update_take_pan_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_take_pan_delta(0)
        set_all_selected_items_params("pan",0.01)
        update_take_pan_delta_by_mousewheel()
      end
    else
      if mwheel_val >0 then
        initialize_take_pan_delta(0)
        set_all_selected_items_params("pan",-0.05)
        update_take_pan_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_take_pan_delta(0)
        set_all_selected_items_params("pan",0.05)
        update_take_pan_delta_by_mousewheel()
      end
    end
    pan1_color = colors.green85
    pan2_color = colors.green85
    pan1t_color = colors.grey7

    if super and ctrl and not shift and count_sel_items~=0 then -- tooltip
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, pan_count_show)
      ImGui.PopStyleColor(ctx,1)

      if all_counted == false then 
        count_selected_items_with_params("all")
      elseif pan_counted == false then
        count_selected_items_with_params("pan")
      end
    end
  elseif in_range(mouse_x, mw_x+curr_sizes.pitch_lb[1]-init_left_space/2,mw_x+curr_sizes.playrate_lb[1]-init_left_space/2) and
    in_range(mouse_y, mw_y, mw_y+mw_h) and actual_item~=-1 then
    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) 
      and not alt and not super and not ctrl and not shift then 
      ImGui.OpenPopup(ctx, "pitch_edit", ImGui.PopupFlags_NoOpenOverExistingPopup)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      alt and not super and not ctrl and not shift then 
      r.Undo_BeginBlock()
      set_all_selected_items_params("pitch","default")
      r.Undo_EndBlock("McS_MonitorToolbar_Pitch reset", -1)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      not alt and not super and ctrl and not shift then 
      r.Undo_BeginBlock()
      set_all_selected_items_params("pitch","current") -- прописать во все items текущее значение
      r.Undo_EndBlock("McS_MonitorToolbar_Pitch reset", -1)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      not alt and super and ctrl and not shift then 
      count_selected_items_with_params("pitch",true)
    end
    if shift then
      if mwheel_val >0 then
        initialize_take_pitch_delta(0)
        set_all_selected_items_params("pitch",0.1)
        update_take_pitch_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_take_pitch_delta(0)
        set_all_selected_items_params("pitch",-0.1)
        update_take_pitch_delta_by_mousewheel()
      end
    else
      if mwheel_val >0 then
        initialize_take_pitch_delta(0)
        set_all_selected_items_params("pitch",1)
        update_take_pitch_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_take_pitch_delta(0)
        set_all_selected_items_params("pitch",-1)
        update_take_pitch_delta_by_mousewheel()
      end
    end
    pitch1_color = colors.violet95
    pitch2_color = colors.violet95
    pitch1t_color = colors.grey7

    if super and ctrl and not shift and count_sel_items~=0 then -- tooltip
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, pitch_count_show)
      ImGui.PopStyleColor(ctx,1)

      if all_counted == false then 
        count_selected_items_with_params("all")
      elseif pitch_counted == false then
        count_selected_items_with_params("pitch")
      end
    end
  elseif in_range(mouse_x, mw_x+curr_sizes.playrate_lb[1]-init_left_space/2,mw_x+curr_sizes.prspitch[1]-init_left_space/2) and
    in_range(mouse_y, mw_y, mw_y+mw_h) and actual_item~=-1 then

    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right)
      and not alt and not super and not ctrl and not shift then
      ImGui.OpenPopup(ctx, "playrate_edit", ImGui.PopupFlags_NoOpenOverExistingPopup)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      alt and not super and not ctrl and not shift then 
      r.Undo_BeginBlock()
      set_all_selected_items_params("playrate","default",enable_length_change)
      r.Undo_EndBlock("McS_MonitorToolbar_Playrate reset", -1)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      not alt and not super and ctrl and not shift then 
      r.Undo_BeginBlock()
      set_all_selected_items_params("playrate","current",enable_length_change) -- прописать во все items текущее значение
      r.Undo_EndBlock("McS_MonitorToolbar_Playrate reset", -1)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      not alt and super and ctrl and not shift then 
      count_selected_items_with_params("playrate",true)
    elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
      alt and super and ctrl and not shift then 
      count_selected_items_with_params("rip",true)
   end

    if shift then
      if mwheel_val >0 then
        initialize_take_playrate_delta(0)
        set_all_selected_items_params("playrate",0.01,enable_length_change)
        update_take_playrate_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_take_playrate_delta(0)
        set_all_selected_items_params("playrate",-0.01,enable_length_change)
        update_take_playrate_delta_by_mousewheel()
      end
    else
      if mwheel_val >0 then
        initialize_take_playrate_delta(0)
        set_all_selected_items_params("playrate",0.05,enable_length_change)
        update_take_playrate_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_take_playrate_delta(0)
        set_all_selected_items_params("playrate",-0.05,enable_length_change)
        update_take_playrate_delta_by_mousewheel()
      end
    end
    playrate1_color = colors.blue9
    playrate2_color = colors.blue9
    playrate1t_color = colors.grey7

    if super and ctrl and not shift and count_sel_items~=0 then -- tooltip
      local tool_txt = ""
      if alt then tool_txt=rip_count_show else tool_txt=playrate_count_show end
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, tool_txt)
      ImGui.PopStyleColor(ctx,1)

      if all_counted == false then 
        count_selected_items_with_params("all")
      elseif playrate_counted == false then
        count_selected_items_with_params("playrate")
      end
    end
  elseif in_range(mouse_x, mw_x+curr_sizes.prspitch[1]-init_left_space/2, mw_x+curr_sizes.framerate[1]-init_left_space/2) and
    in_range(mouse_y, mw_y, mw_y+mw_h) then

    if shift then
      if mwheel_val >0 then
        initialize_take_playrate_delta(0)
        set_all_selected_items_params("preserve_pitch",0)
        set_all_selected_items_params("playrate_pitch",0.1,enable_length_change)
        update_take_playrate_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_take_playrate_delta(0)
        set_all_selected_items_params("preserve_pitch",0)
        set_all_selected_items_params("playrate_pitch",-0.1,enable_length_change)
        update_take_playrate_delta_by_mousewheel()
      end
    else
      if mwheel_val >0 then
        initialize_take_playrate_delta(0)
        set_all_selected_items_params("preserve_pitch",0)
        set_all_selected_items_params("playrate_pitch",1,enable_length_change)
        update_take_playrate_delta_by_mousewheel()
      elseif mwheel_val <0 then
        initialize_take_playrate_delta(0)
        set_all_selected_items_params("preserve_pitch",0) -- прописать во все items 0
        set_all_selected_items_params("playrate_pitch",-1,enable_length_change)
        update_take_playrate_delta_by_mousewheel()
      end
    end
    playrate_pitch_color1 = colors.grey5
    playrate_pitch_color2 = colors.violet95

  elseif in_range(mouse_x, mw_x+curr_sizes.framerate[1]-init_left_space/2,mw_x+curr_sizes.monitorfxdb[1]-init_left_space/2) and
    in_range(mouse_y, mw_y, mw_y+mw_h) then
    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) then
      ImGui.OpenPopup(ctx, "framerate_menu", ImGui.PopupFlags_NoOpenOverExistingPopup)
    end
    set_framerate_by_mousewheel(mwheel_val)
    framerate_color = colors.grey6
  elseif in_range(mouse_x, mw_x+curr_sizes.monitorfxdb[1]-init_left_space/2,mw_x+curr_sizes.monitorsolo[1]-init_left_space/2) and
    in_range(mouse_y, mw_y, mw_y+mw_h) then
    if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) then
      ImGui.OpenPopup(ctx, "mon_vol_menu", ImGui.PopupFlags_NoOpenOverExistingPopup)
    end
    set_mon_fx_vol_by_mousewheel(mwheel_val)
    mon_color = colors.grey6
  elseif in_range(mouse_x, mw_x+curr_sizes.monitorsolo[1]-init_left_space/2,mw_x+curr_sizes.monitorsolo[1]+3*(init_left_space/3 + curr_spaces.monitorsolo + init_left_space/3)) and
    in_range(mouse_y, mw_y, mw_y+mw_h) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) then
    for j=1,6 do
      if monitorsolo_alwaysmute[j] ~= 1 then
        monitorsolo_state[j] = 1
        monitorsolo_jspar[j] = 1
      end
      set_monitorsolo_state_to_jspar()
      get_set_monitorsolo(1,1,nil)
    end
  end

  if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) and
    pan_init_mouse_x ~= nil and pan_init_delta == false then
    local x = r.GetMousePosition()
    -- framerate = x
    if not in_range(x - pan_init_mouse_x, -pan_mouse_sensivity, pan_mouse_sensivity) then
      pan_init_delta = true
      pan_mouse_delta, prev_pan_mouse_delta = 0,0
      -- framerate = tostring(pan_init_delta)
    end
  end

  if ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) and 
    pan_init_mouse_x ~= nil and pan_init_delta == true then
    pan_x_pos = r.GetMousePosition()
    pan_mouse_delta = floor((pan_x_pos - pan_init_mouse_x)/pan_mouse_sensivity)/100

    if pan_mouse_delta ~= prev_pan_mouse_delta then
      initialize_take_pan_delta(0)
      set_all_selected_items_params("pan",pan_mouse_delta-prev_pan_mouse_delta)
      update_take_pan_delta_by_mousewheel()
      prev_pan_mouse_delta = pan_mouse_delta
    end
  end

  if ImGui.BeginPopup(ctx, "vol_edit") then
    if_close_all_menu()
    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx)
    end
    menu_open.vol_edit = true


    -- local flags = ImGui.InputTextFlags_EnterReturnsTrue
    local wd = ImGui.CalcTextSize(ctx, "0.00000")
    ImGui.PushItemWidth(ctx, wd)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Set to:")
    ImGui.PopStyleColor(ctx, 1)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    local rt1
    local _, vol_db1 = ImGui.InputDouble(ctx,"##1", 20*log(item_vol,10) ,0.0,0.0,"%.1f")
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
      rt1 = true
    end
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Add:")
    ImGui.PopStyleColor(ctx, 1)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    local rt2
    local _, vol_db2 = ImGui.InputDouble(ctx,"##2", 0 ,0.0,0.0,"%.1f")
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
      rt2 = true
    end
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)

    if rt1 then
      item_vol = 10^((vol_db1)/20)
      set_all_selected_items_params("vol","current")
      update_actual_item(actual_item_guid, false)
      menu_open.vol_edit = false
      ImGui.CloseCurrentPopup(ctx)
    elseif rt2 then
      set_all_selected_items_params("vol",vol_db2)
      update_actual_item(actual_item_guid, false)
      menu_open.vol_edit = false
      ImGui.CloseCurrentPopup(ctx)
    elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      menu_open.vol_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end

    local col_txt = colors.grey8
    local col_but = colors.buttonColor_blue
    local col_hov = colors.blue5
    local col_act = colors.blue5
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col_but)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col_act)

    if ImGui.Button(ctx, "-inf",wd, button_hight) then
      item_vol = 0
      set_all_selected_items_params("vol","current")
      update_actual_item(actual_item_guid, false)
      menu_open.vol_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)

    ImGui.EndPopup(ctx)
  else
    menu_open.vol_edit = false
  end

  if ImGui.BeginPopup(ctx, "pan_edit") then
    if_close_all_menu()
    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx)
    end
    menu_open.pan_edit = true


    local flags = ImGui.InputTextFlags_EnterReturnsTrue

    local wd = ImGui.CalcTextSize(ctx, "0.00000")
    ImGui.PushItemWidth(ctx, wd)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Set to:")
    ImGui.PopStyleColor(ctx, 1)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    local rt1, input1 = ImGui.InputText(ctx,"##1", take_pan_show, flags, nil)
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Add:")
    ImGui.PopStyleColor(ctx, 1)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    local rt2, input2 = ImGui.InputText(ctx,"##2", 0 , flags, nil)
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)

    if rt1 then
      local d,t = string.match(input1,"(%d+)%s*(%a)")
      if (in_range_equal(tonumber(d),1,100) and (t=="L" or t=="R")) or (tonumber(input1)==0) then
        if tonumber(input1) == 0 then
          take_pan = 0
        else
          take_pan = tonumber(d)/100
          if t == "L" then take_pan = take_pan * -1 end
        end
        set_all_selected_items_params("pan","current")
        update_actual_item(actual_item_guid, false)
        menu_open.pan_edit = false
        ImGui.CloseCurrentPopup(ctx)
      end
    elseif rt2 then
      local d,t = string.match(input2,"(%d+)%s*(%a)")
      if (in_range_equal(tonumber(d),1,200) and (t=="L" or t=="R")) then
        local pan_delta = tonumber(d)/100
        if t == "L" then pan_delta = pan_delta * -1 end
        initialize_take_pan_delta(0)
        set_all_selected_items_params("pan", pan_delta)
        update_take_pan_delta_by_mousewheel()
        update_actual_item(actual_item_guid, false)
        menu_open.pan_edit = false
        ImGui.CloseCurrentPopup(ctx)
      end
    elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      menu_open.pan_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  else
    menu_open.pan_edit = false
  end

  if ImGui.BeginPopup(ctx, "pitch_edit") then
    if_close_all_menu()
    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx)
    end
    menu_open.pitch_edit = true


    -- local flags = ImGui.InputTextFlags_EnterReturnsTrue

    local wd = ImGui.CalcTextSize(ctx, "0.0000000000")
    ImGui.PushItemWidth(ctx, wd)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Set to:")
    ImGui.PopStyleColor(ctx, 1)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    local rt1
    local _, input1 = ImGui.InputDouble(ctx,"##1", take_pitch,0.0,0.0,"%.6f")
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
      rt1 = true
    end

    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Add:")
    ImGui.PopStyleColor(ctx, 1)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    local rt2
    local _, input2 = ImGui.InputDouble(ctx,"##2", 0 ,0.0,0.0,"%.6f")
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
      rt2 = true
    end
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)

    if rt1 then
      take_pitch = input1
      set_all_selected_items_params("pitch","current")
      update_actual_item(actual_item_guid, false)
      menu_open.pitch_edit = false
      ImGui.CloseCurrentPopup(ctx)
    elseif rt2 then
      initialize_take_pitch_delta(0)
      set_all_selected_items_params("pitch",input2)
      update_take_pitch_delta_by_mousewheel()
      update_actual_item(actual_item_guid, false)
      menu_open.pitch_edit = false
      ImGui.CloseCurrentPopup(ctx)
    elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      menu_open.pitch_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  else
    menu_open.pitch_edit = false
  end

  if ImGui.BeginPopup(ctx, "playrate_edit") then
    -- Msg(menu_open.playrate_edit)
    if_close_all_menu()
    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx)
    end
    menu_open.playrate_edit = true


    -- local flags = ImGui.InputTextFlags_EnterReturnsTrue
    -- | ImGui.InputTextFlags_CharsDecimal
    -- | ImGui.InputTextFlags_AutoSelectAll()

    local wd = ImGui.CalcTextSize(ctx, " Time Range conversion: ")
    ImGui.PushItemWidth(ctx, wd)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Set to:")
    ImGui.PopStyleColor(ctx, 1)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    local rt1
    local _, input1 = ImGui.InputDouble(ctx,"##1", take_playrate,0.0,0.0,"%.6f")
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
      rt1 = true
    end
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Add:")
    ImGui.PopStyleColor(ctx, 1)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    local rt2
    local _, input2 = ImGui.InputDouble(ctx,"##2", 0 ,0.0,0.0,"%.6f")
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
      rt2 = true
    end
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)

    if rt1 then
      take_playrate = input1
      set_all_selected_items_params("playrate","current",enable_length_change)
      update_actual_item(actual_item_guid, false)
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    elseif rt2 then
      initialize_take_playrate_delta(0)
      set_all_selected_items_params("playrate", input2 ,enable_length_change)
      update_take_playrate_delta_by_mousewheel()
      update_actual_item(actual_item_guid, false)
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Each Item conversion:\n(select items)")
    ImGui.PopStyleColor(ctx, 1)

                    ---BUTTONS---
    local col_txt = colors.grey8
    local col_but = colors.buttonColor_blue
    local col_hov = colors.blue5
    local col_act = colors.blue5

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col_but)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col_act)

    if ImGui.Button(ctx, "24 -> 25 FPS##but1",wd, button_hight) then
      set_all_selected_items_params("playrate","multiply",25/24)
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end
    if ImGui.Button(ctx, "25 -> 24 FPS##but2",wd, button_hight) then
      set_all_selected_items_params("playrate","multiply",24/25)
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end
    if ImGui.Button(ctx, "23.976 -> 24 FPS##but3",wd, button_hight) then
      set_all_selected_items_params("playrate","multiply",1001/1000)
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end
    if ImGui.Button(ctx, "24 -> 23.976 FPS##but4",wd, button_hight) then
      set_all_selected_items_params("playrate","multiply",1000/1001)
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end
    if ImGui.Button(ctx, "29.97 -> 30 FPS##but5",wd, button_hight) then
      set_all_selected_items_params("playrate",v"multiply",1001/1000)
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end
    if ImGui.Button(ctx, "30 -> 29.97 FPS##but6",wd, button_hight) then
      set_all_selected_items_params("playrate","multiply",1000/1001)
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)

    -- ImGui.PopID(ctx)
    ImGui.EndPopup(ctx)

  else
    menu_open.playrate_edit = false
  end

  if ImGui.BeginPopup(ctx, "framerate_menu") then
    if_close_all_menu()
    menu_open.framerate = true

    local sel0,sel1,sel2,sel3,sel4,sel5,sel6,sel7,sel8,sel9 = 
    false,false,false,false,false,false,false,false,false,false
    if framerate == "23.976" then
      sel0 = true
    elseif framerate == "24" then
      sel1 = true
    elseif framerate == "25" then
      sel2 = true
    elseif framerate == "29.97DF" then
      sel3 = true
    elseif framerate == "29.97ND" then
      sel4 = true
    elseif framerate == "30" then
      sel5 = true
    elseif framerate == "48" then
      sel6 = true
    elseif framerate == "50" then
      sel7 = true
    elseif framerate == "60" then
      sel8 = true
    elseif framerate == "75" then
      sel9 = true
    end
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header, colors.grey3)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, colors.grey3)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, colors.grey5)
    if ImGui.Selectable(ctx, "23.976",sel0) then set_framerate(1) end
    if ImGui.Selectable(ctx, "24",sel1) then set_framerate(2) end
    if ImGui.Selectable(ctx, "25",sel2) then set_framerate(3) end
    if ImGui.Selectable(ctx, "29.97DF",sel3) then set_framerate(4) end
    if ImGui.Selectable(ctx, "29.97ND",sel4) then set_framerate(5) end
    if ImGui.Selectable(ctx, "30",sel5) then set_framerate(6) end
    if ImGui.Selectable(ctx, "48",sel6) then set_framerate(7) end
    if ImGui.Selectable(ctx, "50",sel7) then set_framerate(8) end
    if ImGui.Selectable(ctx, "60",sel8) then set_framerate(9) end
    if ImGui.Selectable(ctx, "75",sel9) then set_framerate(10) end
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)
    ImGui.EndPopup(ctx)
  else
    menu_open.framerate = false
  end


  if ImGui.BeginPopup(ctx, "mon_vol_menu") then
    if_close_all_menu()
    menu_open.monvol = true

    local sel0,sel1,sel2,sel3,sel4,sel5,sel6,sel7,sel8,sel9,sel10,sel11,sel12,sel13,sel14 = 
    false,false,false,false,false,false,false,false,false,false,false,false,false,false,false
    if monitorfxdb == " 0.0" then
      sel0 = true
    elseif monitorfxdb == "-3.0" then
      sel1 = true
    elseif monitorfxdb == "-6.0" then
      sel2 = true
    elseif monitorfxdb == "-8.0" then
      sel3 = true
    elseif monitorfxdb == "-10.0" then
      sel4 = true
    elseif monitorfxdb == "-12.0" then
      sel5 = true
    elseif monitorfxdb == "-15.0" then
      sel6 = true
    elseif monitorfxdb == "-18.0" then
      sel7 = true
    elseif monitorfxdb == "-20.0" then
      sel8 = true
    elseif monitorfxdb == "-22.0" then
      sel9 = true
    elseif monitorfxdb == "-25.0" then
      sel10 = true
    elseif monitorfxdb == "-30.0" then
      sel11 = true
    elseif monitorfxdb == "-35.0" then
      sel12 = true
    elseif monitorfxdb == "-40.0" then
      sel13 = true
    elseif monitorfxdb == "Del" then
      sel14 = true
    end
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header, colors.grey3)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, colors.grey3)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, colors.grey5)
    if ImGui.Selectable(ctx, " 0.0",sel0) then get_set_mon_fx_volume(0.5) end
    if ImGui.Selectable(ctx, "-3.0",sel1) then get_set_mon_fx_volume(0.489584) end
    if ImGui.Selectable(ctx, "-6.0",sel2) then get_set_mon_fx_volume(0.479168) end
    if ImGui.Selectable(ctx, "-8.0",sel3) then get_set_mon_fx_volume(0.472224) end
    if ImGui.Selectable(ctx, "-10.0",sel4) then get_set_mon_fx_volume(0.46528) end
    if ImGui.Selectable(ctx, "-12.0",sel5) then get_set_mon_fx_volume(0.458336) end
    if ImGui.Selectable(ctx, "-15.0",sel6) then get_set_mon_fx_volume(0.44792) end
    if ImGui.Selectable(ctx, "-18.0",sel7) then get_set_mon_fx_volume(0.437504) end
    if ImGui.Selectable(ctx, "-20.0",sel8) then get_set_mon_fx_volume(0.43056) end
    if ImGui.Selectable(ctx, "-22.0",sel9) then get_set_mon_fx_volume(0.423616) end
    if ImGui.Selectable(ctx, "-25.0",sel10) then get_set_mon_fx_volume(0.4132) end
    if ImGui.Selectable(ctx, "-30.0",sel11) then get_set_mon_fx_volume(0.39584) end
    if ImGui.Selectable(ctx, "-35.0",sel12) then get_set_mon_fx_volume(0.37848) end
    if ImGui.Selectable(ctx, "-40.0",sel13) then get_set_mon_fx_volume(0.36112) end
    if ImGui.Selectable(ctx, "Del",sel13) then get_set_mon_fx_volume(-100) end
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)
    ImGui.EndPopup(ctx)
  else
    menu_open.monvol = false
  end

  local take_name_str
  if take_name~= nil then
    ImGui.PushID(ctx, 1)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey5)
    ImGui.SetCursorPos(ctx, curr_sizes.name_lb[1], curr_sizes.name_lb[2])
    ImGui.Text(ctx, "Item Name:")
    -- if ImGui.IsItemHovered(ctx) and actual_item~=-1 then -- tooltip
      -- local str
      -- if actual_item_type_is == "VIDEO" then
        -- take_name_str = "Name: "..take_name.."\nPath: "..take_path.."\n\n --- Video ---".."\nCodec: "..video_take_codec.."\nBitrate: "..video_take_bitrate.."\nResolution: "..video_take_res.."\nFramerate: "..video_take_fps.."\n\n --- Audio ---".."\nChan num: "..take_channel_num.."\nBit depth: "..take_bit_depth.."\nSamplerate: "..take_samplerate
        -- ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
        -- ImGui.SetTooltip(ctx, take_name_str)
        -- ImGui.PopStyleColor(ctx,1)
      -- elseif actual_item_type_is ~= "VIDEO" and actual_item_type_is ~= "EMPTY" then
        -- take_name_str = "Name: "..take_name.."\nPath: "..take_path.."\n\nChan num: "..take_channel_num.."\nBit depth: "..take_bit_depth.."\nSamplerate: "..take_samplerate
        -- ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
        -- ImGui.SetTooltip(ctx, take_name_str)
        -- ImGui.PopStyleColor(ctx,1)
      -- end
    -- end
    ImGui.PopStyleColor(ctx,1)
    ImGui.PopID(ctx)
  end

  ImGui.PushID(ctx, 1)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey5)
  ImGui.SetCursorPos(ctx, curr_sizes.name_lb[1], row2_y)
  ImGui.Text(ctx, "Sel Items: "..count_sel_items)
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)
  if actual_item_num ~= nil then
    ImGui.SameLine(ctx)
    ImGui.PushID(ctx, 1)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_yellow)
    ImGui.Text(ctx, actual_item_num)
    ImGui.PopStyleColor(ctx,1)
    ImGui.PopID(ctx)
  end


  local col_txt,col_but,col_hov,col_act

  if item_loop ~= nil then
    if item_loop == 1 then
      col_txt = colors.grey8
      col_but = colors.buttonColor_blue
      col_hov = colors.hoveredColor_blue
      col_act = colors.activeColor_blue
    else
      col_txt = colors.grey7
      col_but = colors.buttonColor_darkgrey
      col_hov = colors.hoveredColor_darkgrey
      col_act = colors.activeColor_darkgrey
    end

    ImGui.PushID(ctx, 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col_but)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col_act)

    ImGui.SetCursorPos(ctx, curr_sizes.loop[1],curr_sizes.loop[2])
    -- ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign(), 0.5, )
    ImGui.Button(ctx, 'Loop',curr_spaces.loop+init_left_space*2/3, button_hight)
    -- if ImGui.IsMouseDown(ctx, 1) and ImGui.IsItemHovered(ctx) then
      -- ImGui.SetTooltip(ctx, 'Turn SurPan FX ON (unbypass) in selected items')
    -- end
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)
    ImGui.PopID(ctx)
    if ImGui.IsItemHovered(ctx) then
      if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and super and not ctrl and not shift then
        set_all_selected_items_params("loop","init") -- прописать во все items начальные значения
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and not shift then
        set_all_selected_items_params("loop","switch") -- прописать во все items текущее значение
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift then
        set_all_selected_items_params("loop",0) -- прописать во все items 0
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and ctrl and not shift then
        set_all_selected_items_params("loop",1) -- прописать во все items 1
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and shift then
        set_all_selected_items_params("loop", "inverse")
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and super and ctrl and not shift then
        count_selected_items_with_params("loop", true)
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and super and ctrl and not shift then 
        count_selected_items_with_params("rip",true)
      -- elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift then 
        -- ImGui.OpenPopup(ctx, "loop_menu", ImGui.PopupFlags_NoOpenOverExistingPopup)
      end
    end

    if ImGui.IsItemHovered(ctx) and super and ctrl and not shift and count_sel_items~=0 then -- tooltip
      local tool_txt = ""
      if alt then tool_txt=rip_count_show else tool_txt=loop_count_show end
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, tool_txt)
      ImGui.PopStyleColor(ctx,1)

      if all_counted == false then 
        count_selected_items_with_params("all")
      elseif loop_counted == false then
        count_selected_items_with_params("loop")
      end
    end

  end

  if item_mute ~= nil then
    if item_mute == 1 then
      col_txt = colors.grey8
      col_but = colors.buttonColor_red
      col_hov = colors.hoveredColor_red
      col_act = colors.activeColor_red
    else
      col_txt = colors.grey7
      col_but = colors.buttonColor_darkgrey
      col_hov = colors.hoveredColor_darkgrey
      col_act = colors.activeColor_darkgrey
    end

    ImGui.PushID(ctx, 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col_but)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col_act)

    ImGui.SetCursorPos(ctx, curr_sizes.mute[1],curr_sizes.mute[2])
    -- ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign(), 0.5, )
    ImGui.Button(ctx, 'Mute',curr_spaces.mute+init_left_space*2/3, button_hight)
    -- if ImGui.IsMouseDown(ctx, 1) and ImGui.IsItemHovered(ctx) then
      -- ImGui.SetTooltip(ctx, 'Turn SurPan FX ON (unbypass) in selected items')
    -- end
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)
    ImGui.PopID(ctx)
    if ImGui.IsItemHovered(ctx) then
      if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and super and not ctrl and not shift then
        set_all_selected_items_params("mute","init") -- прописать во все items начальные значения
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and not shift then
        set_all_selected_items_params("mute","switch") -- прописать во все items текущее значение
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift then
        set_all_selected_items_params("mute",0) -- прописать во все items 0
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and ctrl and not shift then
        set_all_selected_items_params("mute",1) -- прописать во все items 1
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and shift then
        set_all_selected_items_params("mute", "inverse")
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and super and ctrl and not shift then
        count_selected_items_with_params("mute", true)
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and super and ctrl and not shift then 
        count_selected_items_with_params("rip",true)
      -- elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift then 
        -- ImGui.OpenPopup(ctx, "loop_menu", ImGui.PopupFlags_NoOpenOverExistingPopup)
      end
      

    end
    if ImGui.IsItemHovered(ctx) and super and ctrl and not shift and count_sel_items~=0 then -- tooltip
      local tool_txt = ""
      if alt then tool_txt=rip_count_show else tool_txt=mute_count_show end
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, tool_txt)
      ImGui.PopStyleColor(ctx,1)

      if all_counted == false then 
        count_selected_items_with_params("all")
      elseif mute_counted == false then
        count_selected_items_with_params("mute")
      end
    end
  end

  if item_lock ~= nil then
    if item_lock == 1 then
      col_txt = colors.grey8
      col_but = colors.buttonColor_orange
      col_hov = colors.hoveredColor_orange
      col_act = colors.activeColor_orange
    else
      col_txt = colors.grey7
      col_but = colors.buttonColor_darkgrey
      col_hov = colors.hoveredColor_darkgrey
      col_act = colors.activeColor_darkgrey
    end

    ImGui.PushID(ctx, 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col_but)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col_act)

    ImGui.SetCursorPos(ctx, curr_sizes.lock[1],curr_sizes.lock[2])
    -- ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign(), 0.5, )
    ImGui.Button(ctx, 'Lock',curr_spaces.lock+init_left_space*2/3, button_hight)
    -- if ImGui.IsMouseDown(ctx, 1) and ImGui.IsItemHovered(ctx) then
      -- ImGui.SetTooltip(ctx, 'Turn SurPan FX ON (unbypass) in selected items')
    -- end
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)
    ImGui.PopID(ctx)

    if ImGui.IsItemHovered(ctx) then
      if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and super and not ctrl and not shift then
        set_all_selected_items_params("lock","init") -- прописать во все items начальные значения
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and not shift then
        set_all_selected_items_params("lock","switch") -- прописать во все items текущее значение
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift then
        set_all_selected_items_params("lock",0) -- прописать во все items 0
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and ctrl and not shift then
        set_all_selected_items_params("lock",1) -- прописать во все items 1
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and shift then
        set_all_selected_items_params("lock", "inverse")
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and super and ctrl and not shift then
        count_selected_items_with_params("lock", true)
      -- elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift then 
        -- ImGui.OpenPopup(ctx, "loop_menu", ImGui.PopupFlags_NoOpenOverExistingPopup)
      end
    end
    if ImGui.IsItemHovered(ctx) and super and ctrl and not shift and count_sel_items~=0 then -- tooltip
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, lock_count_show)
      ImGui.PopStyleColor(ctx,1)

      if all_counted == false then 
        count_selected_items_with_params("all")
      elseif lock_counted == false then
        count_selected_items_with_params("lock")
      end
    end
  end

  if take_reverse ~= nil then
    if take_reverse == true then
      col_txt = colors.grey8
      col_but = colors.buttonColor_lblue
      col_hov = colors.hoveredColor_lblue
      col_act = colors.activeColor_lblue
    else
      col_txt = colors.grey7
      col_but = colors.buttonColor_darkgrey
      col_hov = colors.hoveredColor_darkgrey
      col_act = colors.activeColor_darkgrey
    end

    ImGui.PushID(ctx, 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col_but)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col_act)

    ImGui.SetCursorPos(ctx, curr_sizes.reverse[1],curr_sizes.reverse[2])
    ImGui.Button(ctx, 'Reverse', curr_spaces.reverse+init_left_space*2/3, button_hight)
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)
    ImGui.PopID(ctx)


    if ImGui.IsItemHovered(ctx) then
      if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and super and not ctrl and not shift then
        set_reverse_all_selected_items_params("init") -- прописать во все items начальные значения
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and not shift then
        set_reverse_all_selected_items_params("switch") -- прописать во все items текущее значение
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift then
        set_reverse_all_selected_items_params(0) -- прописать во все items 0
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and ctrl and not shift then
        set_reverse_all_selected_items_params(1) -- прописать во все items 1
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and shift then
        set_reverse_all_selected_items_params("inverse")
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and super and ctrl and not shift then
        count_selected_items_with_params("reverse", true)
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and super and ctrl and not shift then 
        count_selected_items_with_params("rip",true)
      -- elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift then 
        -- ImGui.OpenPopup(ctx, "loop_menu", ImGui.PopupFlags_NoOpenOverExistingPopup)
      end
    end
    if ImGui.IsItemHovered(ctx) and super and ctrl and not shift and count_sel_items~=0 then -- tooltip
      local tool_txt = ""
      if alt then tool_txt=rip_count_show else tool_txt=reverse_count_show end
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, tool_txt)
      ImGui.PopStyleColor(ctx,1)

      if all_counted == false then 
        count_selected_items_with_params("all")
      elseif reverse_counted == false then
        count_selected_items_with_params("reverse")
      end
    end
  end

  if preserve_pitch ~= nil then
    if preserve_pitch == 1 then
      col_txt = colors.grey8
      col_but = colors.buttonColor_blue
      col_hov = colors.hoveredColor_blue
      col_act = colors.activeColor_blue
    else
      col_txt = colors.grey7
      col_but = colors.buttonColor_darkgrey
      col_hov = colors.hoveredColor_darkgrey
      col_act = colors.activeColor_darkgrey
    end

    ImGui.PushID(ctx, 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col_but)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col_act)

    ImGui.SetCursorPos(ctx, curr_sizes.prspitch[1],curr_sizes.prspitch[2])
    ImGui.Button(ctx, 'Preserve Pitch', curr_spaces.prspitch+init_left_space*2/3, button_hight)
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)
    ImGui.PopID(ctx)

    if ImGui.IsItemHovered(ctx) then
      if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and super and not ctrl and not shift then
        set_all_selected_items_params("preserve_pitch","init") -- прописать во все items начальные значения
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and not shift then
        set_all_selected_items_params("preserve_pitch","switch") -- прописать во все items текущее значение
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift then
        set_all_selected_items_params("preserve_pitch",0) -- прописать во все items 0
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and ctrl and not shift then
        set_all_selected_items_params("preserve_pitch",1) -- прописать во все items 1
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and shift then
        set_all_selected_items_params("preserve_pitch", "inverse")
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and super and ctrl and not shift then
        count_selected_items_with_params("preserve_pitch", true)
      end
    end
    if ImGui.IsItemHovered(ctx) and super and ctrl and not shift and count_sel_items~=0 then -- tooltip
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, prspitch_count_show)
      ImGui.PopStyleColor(ctx,1)

      if all_counted == false then 
        count_selected_items_with_params("all")
      elseif prspitch_counted == false then
        count_selected_items_with_params("preserve_pitch")
      end
    end
  end
    
  ---PLAYRATE_PITCH---
  ImGui.PushID(ctx, 1)
  if preserve_pitch == 1 then
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, playrate_pitch_color1)
  else
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, playrate_pitch_color2)
  end
  ImGui.SetCursorPos(ctx, curr_value_sizes.playrate_pitch[1], curr_value_sizes.playrate_pitch[2])
  ImGui.Text(ctx, playrate_pitch_show)
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)

  if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) 
    and not alt and not super and not ctrl and not shift then
    ImGui.OpenPopup(ctx, "playrate_pitch_edit", ImGui.PopupFlags_NoOpenOverExistingPopup)
  elseif ImGui.IsItemHovered(ctx) and
    ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift then
    r.Undo_BeginBlock()
    set_all_selected_items_params("playrate","default",enable_length_change)
    r.Undo_EndBlock("McS_MonitorToolbar_Playrate Pitch reset", -1)
  end

  if ImGui.BeginPopup(ctx, "playrate_pitch_edit") then
    if_close_all_menu()
    if ImGui.IsWindowAppearing(ctx) then
      ImGui.SetKeyboardFocusHere(ctx)
    end
    menu_open.playrate_pitch_edit = true


    -- local flags = ImGui.InputTextFlags_EnterReturnsTrue

    local wd = ImGui.CalcTextSize(ctx, "0.0000000000")
    ImGui.PushItemWidth(ctx, wd)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Set to:")
    ImGui.PopStyleColor(ctx, 1)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    local rt1
    local _, input1 = ImGui.InputDouble(ctx,"##1", take_playrate_pitch,0.0,0.0,"%.2f")
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
      rt1 = true
    end
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey6)
    ImGui.Text(ctx, "Add:")
    ImGui.PopStyleColor(ctx, 1)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey8)
    local rt2
    local _, input2 = ImGui.InputDouble(ctx,"##2", 0 ,0.0,0.0,"%.2f")
    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
      rt2 = true
    end
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)

    if rt1 then
      take_playrate = 2^(input1/12)
      set_all_selected_items_params("playrate","current",enable_length_change)
      update_actual_item(actual_item_guid, false)
      menu_open.playrate_pitch_edit = false
      ImGui.CloseCurrentPopup(ctx)
    elseif rt2 then
      playrate_tooltip_enable = false
      initialize_take_playrate_delta(0)
      set_all_selected_items_params("playrate_pitch", input2, enable_length_change)
      update_take_playrate_delta_by_mousewheel()
      update_actual_item(actual_item_guid, false)
      menu_open.playrate_pitch_edit = false
      ImGui.CloseCurrentPopup(ctx)
    elseif ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  else
    menu_open.playrate_pitch_edit = false
  end


  if rateL == 1 or temp_rateL == 1 then
    col_txt = colors.grey8
    col_but = colors.buttonColor_blue
    col_hov = colors.hoveredColor_blue
    col_act = colors.activeColor_blue
  else
    col_txt = colors.grey7
    col_but = colors.buttonColor_darkgrey2
    col_hov = colors.hoveredColor_darkgrey2
    col_act = colors.activeColor_darkgrey2
  end
  ImGui.PushID(ctx, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, col_but)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col_hov)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col_act)
  ImGui.SetCursorPos(ctx, curr_sizes.rateL[1]+init_left_space*2/3-init_left_space/3,curr_sizes.rateL[2])
  ImGui.Button(ctx, '<L>', curr_spaces.rateL+init_left_space/3, button_hight)
  ImGui.PopStyleColor(ctx, 4)
  ImGui.PopStyleVar(ctx, 1)
  ImGui.PopID(ctx)
  if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and 
    not alt and not super and not ctrl and not shift then
    rateL = 1-rateL
    r.SetExtState("McS-Tools", "rateL", tostring(rateL), true)
    update_actual_item(actual_item_guid, false)
    validate_done = false
  end


  if chan_mode ~= nil then
    if chan_mode ~= 0 then
      col_txt = colors.grey8
      col_but = colors.buttonColor_blue
      col_hov = colors.hoveredColor_blue
      col_act = colors.activeColor_blue
    else
      col_txt = colors.grey7
      col_but = colors.buttonColor_darkgrey
      col_hov = colors.hoveredColor_darkgrey
      col_act = colors.activeColor_darkgrey
    end
    local sel0,sel1,sel2,sel3,sel4 = false,false,false,false,false
    if chan_mode == 0 then
      sel0 = true
    elseif chan_mode == 1 then
      sel1 = true
    elseif chan_mode == 2 then
      sel2 = true
    elseif chan_mode == 3 then
      sel3 = true
    elseif chan_mode == 4 then
      sel4 = true
    end

    ImGui.PushID(ctx, 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col_but)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col_act)

    ImGui.SetCursorPos(ctx, curr_sizes.chmode[1],curr_sizes.chmode[2])
    ImGui.Button(ctx, 'CM: '..chan_mode_show, curr_spaces.chmode+init_left_space*2/3, button_hight)
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)
    ImGui.PopID(ctx)
 
    if ImGui.IsItemHovered(ctx) then
      if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and super and not ctrl and not shift then
        set_all_selected_items_params("chan_mode","init") -- прописать во все items начальные значения
      -- elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and not shift then
        -- set_all_selected_items_params("chan_mode","switch") -- прописать во все items текущее значение
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift then
        set_all_selected_items_params("chan_mode",0) -- прописать во все items 0
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and ctrl and not shift then
        set_all_selected_items_params("chan_mode",2) -- прописать во все items 1
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and not super and not ctrl and not shift then
        ImGui.OpenPopup(ctx, 'chanmode_menu', ImGui.PopupFlags_NoOpenOverExistingPopup)
      elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Left) and not alt and super and ctrl and not shift then
        count_selected_items_with_params("chan_mode", true)
      elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and super and ctrl and not shift then 
        count_selected_items_with_params("rip",true)
      -- elseif ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift then 
        -- ImGui.OpenPopup(ctx, "loop_menu", ImGui.PopupFlags_NoOpenOverExistingPopup)
      end
    end
    if ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and ctrl and not shift then
      set_all_selected_items_params("chan_mode",2)
      chan_mode_counted = false
    elseif ImGui.IsItemClicked(ctx, ImGui.MouseButton_Right) and alt and not super and not ctrl and not shift then
      set_all_selected_items_params("chan_mode",1)
      chan_mode_counted = false
    end 

    if ImGui.IsItemHovered(ctx) and super and ctrl and not shift and count_sel_items~=0 then -- tooltip
      local tool_txt = ""
      if alt then tool_txt=rip_count_show else tool_txt=chan_mode_count_show end
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, tool_txt)
      ImGui.PopStyleColor(ctx,1)

      if all_counted == false then
        count_selected_items_with_params("all")
      elseif chan_mode_counted == false then
        count_selected_items_with_params("chan_mode")
      end
    elseif ImGui.IsItemHovered(ctx) then
      set_chan_mode_by_mousewheel(mwheel_val)
    end

    if ImGui.BeginPopup(ctx, 'chanmode_menu') then
      menu_open.chmode = true
 
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0.5, 0)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.grey9)
      ImGui.PushStyleColor(ctx, ImGui.Col_Header, colors.buttonColor_blue)
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, colors.hoveredColor_blue)
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, colors.activeColor_blue)
      if ImGui.Selectable(ctx, 'Normal',sel0) then chan_mode = 0 set_all_selected_items_params("chan_mode",chan_mode) end
      if ImGui.Selectable(ctx, 'Reverse Stereo',sel1) then chan_mode = 1 set_all_selected_items_params("chan_mode",chan_mode) end
      if ImGui.Selectable(ctx, 'Mono Down Mix L+R',sel2) then chan_mode = 2 set_all_selected_items_params("chan_mode",chan_mode) end
      if ImGui.Selectable(ctx, 'Left',sel3) then chan_mode = 3 set_all_selected_items_params("chan_mode",chan_mode) end
      if ImGui.Selectable(ctx, 'Right',sel4) then chan_mode = 4 set_all_selected_items_params("chan_mode",chan_mode) end
      ImGui.PopStyleColor(ctx, 4)
      ImGui.PopStyleVar(ctx, 1)
      ImGui.EndPopup(ctx)
    else
      menu_open.chmode = false
    end
  end
  --mw_x+curr_sizes.loop[1] , mw_y+curr_sizes.loop[2] 
  if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift and
     in_range_equal(mouse_x, mw_x, mw_x+curr_sizes.chmode[1]+curr_spaces.chmode + init_left_space) and
     in_range_equal(mouse_y, mw_y, mw_y+mw_h) then
    ImGui.OpenPopup(ctx, "basic_menu", ImGui.HoveredFlags_AllowWhenBlockedByPopup)
    -- ImGui.OpenPopupOnItemClick(ctx, "basic_menu", nil)
  end

  local open_select_menu = false

  ImGui.SetNextWindowPos(ctx,  mouse_x, mouse_y, ImGui.Cond_Appearing, 0.0, 0.0)
  -- if ImGui.BeginPopupModal(ctx, "basic_menu", nil, ImGui.WindowFlags_AlwaysAutoResize) then
  if ImGui.BeginPopup(ctx, "basic_menu", nil) then
    menu_open.basic = true
    local col_txt = colors.grey9
    local col_but = colors.buttonColor_blue
    local col_hov = colors.blue5
    local col_act = colors.blue5
    
    draw_separator_text("Preparing for AATranslator (Right MB-> info)", 1, colors.grey4, colors.grey3, 0.0, 0.5, 1)
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Right) then
      ImGui.PushStyleColor( ctx, ImGui.Col_Text, colors.grey9)
      ImGui.SetTooltip(ctx, "Copy all needed items(don't copy media) to new project created in new folder and save it.\nNuendo button just converts project as is.\nProtools first spreads mono and stereo items on different tracks then converts project.")
      ImGui.PopStyleColor(ctx, 1)
    end

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header, colors.buttonColor_blue)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, colors.hoveredColor_blue)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, colors.activeColor_blue)
    if ImGui.Selectable(ctx, "Convert sel items for exporting to Nuendo") then convert_for_exporting_to_nuendo_and_protools(2) end
    if ImGui.Selectable(ctx, "Convert sel items for exporting to Protools") then convert_for_exporting_to_nuendo_and_protools(1) end

    ImGui.Separator(ctx)

    if ImGui.BeginCombo(ctx, "##select_combo", "Select items with non-default .. ", ImGui.ComboFlags_HeightLargest) then
      for i=1,#combo.select do
        if ImGui.Selectable(ctx, combo.select[i].txt, 0) then
          combo.select[i].command()
          -- ImGui.SetItemDefaultFocus(ctx)
        end
      end
      ImGui.EndCombo(ctx)
    end



    -- if ImGui.BeginPopupModal(ctx, "select_menu", nil, ImGui.WindowFlags_AlwaysAutoResize) then

    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Select items with Name:")
    ImGui.SameLine(ctx)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    local input_flags = ImGui.InputTextFlags_EnterReturnsTrue
    local rt, name_search = ImGui.InputText(ctx,"##inp_name", "", input_flags, nil)
    ImGui.PopStyleVar(ctx)
    if rt and name_search~="" then
      find_items_with_name(name_search)
      ImGui.CloseCurrentPopup(ctx)
    end
    if ImGui.Selectable(ctx, "Select items with Any FX") then count_selected_items_with_params("fx",true) end
    ImGui.Text(ctx, "Select items with FX Name:")
    ImGui.SameLine(ctx)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    local input_flags = ImGui.InputTextFlags_EnterReturnsTrue
    local rt, fx_name_search = ImGui.InputText(ctx,"##inp_fx_nm", "", input_flags, nil)
    ImGui.PopStyleVar(ctx)
    if rt and fx_name_search~="" then
      find_items_with_fx_name(fx_name_search)
      ImGui.CloseCurrentPopup(ctx)
    end

    ImGui.Separator(ctx)
    if ImGui.Selectable(ctx, "Render in Place") then render_in_place() end
    ImGui.Separator(ctx)
    if ImGui.Selectable(ctx, "Move Reels or Episodes to Hours accordingly") then move_reels_or_episodes_to_hours_accordingly() end
    if ImGui.Selectable(ctx, "Fix looped items") then fix_looped_items(true, true) end
    if ImGui.Selectable(ctx, "Restrict Selected Items Start and End to Source") then restrict_sel_items_st_en_to_source() end
    -- ImGui.Separator(ctx)
  

    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)

    -- ImGui.Separator(ctx)
    -- ImGui.PushStyleColor( ctx, ImGui.Col_Text, col_txt)
    -- ImGui.Text(ctx, "Project Frame Rate conversion:")
    -- ImGui.PopStyleColor(ctx, 1)

    draw_separator_text("Project Frame Rate conversion (Right MB-> info)", 1, colors.grey4, colors.grey3, 0.0, 0.5, 4)

    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Right) then
      ImGui.PushStyleColor( ctx, ImGui.Col_Text, colors.grey9)
      ImGui.SetTooltip(ctx, "You may select items and range to restrict,\nelse it takes 0:00:00 for start of project and all items.\nLocked items are always respected!")
      ImGui.PopStyleColor(ctx, 1)
    end

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, col_but)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, col_hov)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, col_act)

    local wd = r.ImGui_CalcTextSize(ctx, "    24 -> 25 FPS    ")
    if ImGui.Button(ctx, "24 -> 25 FPS##but7",wd, button_hight) then
      convert_time_range_fps(25/24)
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end
    if ImGui.Button(ctx, "25 -> 24 FPS##but8",wd, button_hight) then
      convert_time_range_fps(24/25)
      menu_open.playrate_edit = false
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)

    ImGui.EndPopup(ctx)
  else
    menu_open.basic = false
  end

  if open_select_menu then
    ImGui.OpenPopup(ctx, "select_menu", ImGui.HoveredFlags_AllowWhenBlockedByPopup)
  end

  if ImGui.BeginPopup(ctx, "select_menu", nil) then
    menu_open.select = true
    local col_txt = colors.grey9
    local col_but = colors.buttonColor_blue
    local col_hov = colors.blue5
    local col_act = colors.blue5

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, col_txt)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header, colors.buttonColor_blue)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, colors.hoveredColor_blue)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, colors.activeColor_blue)

    if ImGui.Selectable(ctx, "Select items with non-default Loop,Mute,Reverse,CM,Playrate + FX") then count_selected_items_with_params("ripfx",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Loop,Mute,Reverse,CM,Playrate") then count_selected_items_with_params("rip",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Any of All Params") then count_selected_items_with_params("all",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Loop") then count_selected_items_with_params("loop",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Mute") then count_selected_items_with_params("mute",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Lock") then count_selected_items_with_params("lock",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Reverse") then count_selected_items_with_params("reverse",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Chan Mode") then count_selected_items_with_params("chan_mode",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Vol") then count_selected_items_with_params("vol",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Pan") then count_selected_items_with_params("pan",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Pitch") then count_selected_items_with_params("pitch",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Playrate") then count_selected_items_with_params("playrate",true) end
    if ImGui.Selectable(ctx, "Select items with non-default Preserve Pitch") then count_selected_items_with_params("preserve_pitch",true) end

    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)

    ImGui.EndPopup(ctx)
  else
    menu_open.select = false
  end


  ImGui.PushID(ctx, 1)
  local v_txt
  if vol_tooltip_enable == true then
    v_txt = vol_delta_tooltip
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, vol1t_color)
    ImGui.SetCursorPos(ctx, vol_delta_tooltip_xpos, curr_sizes.vol_lb[2])
  else
    v_txt = "Volume"
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, vol1_color)
    ImGui.SetCursorPos(ctx, curr_sizes.vol_lb[1], curr_sizes.vol_lb[2])
  end
  ImGui.Text(ctx, v_txt)
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)

  -- if ImGui.IsItemHovered(ctx) and 
    -- ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift then
    -- r.Undo_BeginBlock()
    -- set_all_selected_items_params("vol","undo_delta")
    -- r.Undo_EndBlock("McS_MonitorToolbar_Vol reset", -1)
  -- end

  ImGui.PushID(ctx, 1)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, vol2_color)
  ImGui.SetCursorPos(ctx, curr_value_sizes.vol[1], curr_value_sizes.vol[2])
  ImGui.Text(ctx, item_vol_show)
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)

  -- if ImGui.IsItemHovered(ctx) and ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) then 
    -- if alt and not super and not ctrl and not shift then
      -- r.Undo_BeginBlock()
      -- set_all_selected_items_params("vol","default")
      -- r.Undo_EndBlock("McS_MonitorToolbar_Vol reset", -1)
    -- elseif alt and super and not ctrl and not shift then
      -- r.Undo_BeginBlock()
      -- item_vol = 0
      -- set_all_selected_items_params("vol","current")
      -- r.Undo_EndBlock("McS_MonitorToolbar_Vol reset -inf", -1)
    -- end
  -- end

  ImGui.PushID(ctx, 1)
  local p_txt
  if pan_tooltip_enable == true then
    p_txt = pan_delta_tooltip
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, pan1t_color)
    ImGui.SetCursorPos(ctx, pan_delta_tooltip_xpos, curr_sizes.pan_lb[2])
  else
    p_txt = "Pan"
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, pan1_color)
    ImGui.SetCursorPos(ctx, curr_sizes.pan_lb[1], curr_sizes.pan_lb[2])
  end
  ImGui.Text(ctx, p_txt)
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)

  -- if ImGui.IsItemHovered(ctx) and 
    -- ((ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift) or
    -- (ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift)) then
     -- r.Undo_BeginBlock()
    -- set_all_selected_items_params("pan","undo_delta")
    -- r.Undo_EndBlock("McS_MonitorToolbar_Pan reset", -1)
  -- end

  ImGui.PushID(ctx, 1)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, pan2_color)
  ImGui.SetCursorPos(ctx, curr_value_sizes.pan[1], curr_value_sizes.pan[2])
  ImGui.Text(ctx, tostring(take_pan_show))
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)

  -- if ImGui.IsItemHovered(ctx) and 
    -- ((ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift) or
    -- (ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift)) then
    -- r.Undo_BeginBlock()
    -- set_all_selected_items_params("pan","default")
-- 
    -- r.Undo_EndBlock("McS_MonitorToolbar_Pan reset", -1)
  -- end


  ImGui.PushID(ctx, 1)
  local ptch_txt
  if pitch_tooltip_enable == true then
    ptch_txt = pitch_delta_tooltip
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, pitch1t_color)
    ImGui.SetCursorPos(ctx, pitch_delta_tooltip_xpos, curr_sizes.pitch_lb[2])
  else
    ptch_txt = "Pitch"
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, pitch1_color)
    ImGui.SetCursorPos(ctx, curr_sizes.pitch_lb[1], curr_sizes.pitch_lb[2])
  end
  ImGui.Text(ctx, ptch_txt)
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)

  -- if ImGui.IsItemHovered(ctx) and 
    -- ((ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift) or
    -- (ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift)) then
    -- r.Undo_BeginBlock()
    -- set_all_selected_items_params("pitch","undo_delta")
    -- r.Undo_EndBlock("McS_MonitorToolbar_Pitch reset", -1)
  -- end

  ImGui.PushID(ctx, 1)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, pitch2_color)
  ImGui.SetCursorPos(ctx, curr_value_sizes.pitch[1], curr_value_sizes.pitch[2])
  ImGui.Text(ctx, take_pitch_show)
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)
 
  -- if ImGui.IsItemHovered(ctx) and 
    -- ((ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift) or
    -- (ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift)) then
    -- r.Undo_BeginBlock()
    -- set_all_selected_items_params("pitch","default")
    -- r.Undo_EndBlock("McS_MonitorToolbar_Pitch reset", -1)
  -- end


  ImGui.PushID(ctx, 1)
  local pr_txt
  if playrate_tooltip_enable == true then
    pr_txt = playrate_delta_tooltip
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, playrate1t_color)
    ImGui.SetCursorPos(ctx, playrate_delta_tooltip_xpos, curr_sizes.playrate_lb[2])
  else
    pr_txt = "Playrate"
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, playrate1_color)
    ImGui.SetCursorPos(ctx, curr_sizes.playrate_lb[1], curr_sizes.playrate_lb[2])
  end    
  ImGui.Text(ctx, pr_txt)
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)
 
  -- if ImGui.IsItemHovered(ctx) and 
    -- ((ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift) or
    -- (ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift)) then
    -- r.Undo_BeginBlock()
    -- set_all_selected_items_params("playrate","undo_delta",enable_length_change)
    -- r.Undo_EndBlock("McS_MonitorToolbar_Playrate reset", -1)
  -- end
  ImGui.PushID(ctx, 1)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, playrate2_color)
  ImGui.SetCursorPos(ctx, curr_value_sizes.rate[1], curr_value_sizes.rate[2])
  ImGui.Text(ctx, take_playrate_show)
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)

  -- if ImGui.IsItemHovered(ctx) and 
    -- ((ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right) and not alt and not super and not ctrl and not shift) or
    -- (ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) and alt and not super and not ctrl and not shift)) then
    -- r.Undo_BeginBlock()
    -- set_all_selected_items_params("playrate","default",enable_length_change)
    -- r.Undo_EndBlock("McS_MonitorToolbar_Playrate reset", -1)
  -- end


  ImGui.PushID(ctx, 1)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, framerate_color)
  ImGui.SetCursorPos(ctx, curr_sizes.framerate[1], curr_sizes.framerate[2])
  ImGui.Text(ctx, framerate)

  ImGui.SetCursorPos(ctx, curr_sizes.framerate[1], curr_value_sizes.rate[2])
  ImGui.Text(ctx, 'fps')
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)

  ImGui.PushID(ctx, 1)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, mon_color)
  ImGui.SetCursorPos(ctx, curr_sizes.monitorfxdb[1], curr_sizes.monitorfxdb[2])
  ImGui.Text(ctx, monitorfxdb)


  if mon_fx_vol_exist == true then
    ImGui.SameLine(ctx, 0, 1)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.green9) --colors.yellow8)
    ImGui.Text(ctx, "*")
    ImGui.PopStyleColor(ctx,1)
  end

  ImGui.SetCursorPos(ctx, curr_sizes.monitorfxdb[1], curr_value_sizes.rate[2])
  ImGui.Text(ctx, ' db')
  ImGui.PopStyleColor(ctx,1)
  ImGui.PopID(ctx)


  ImGui.PushID(ctx, 1)

  local name_color, name_txt
  if take_name ~= "-" and actual_item_type_is == 'VIDEO' and video_take_fps ~= framerate then
    name_color = colors.video_name_red
    name_txt = take_name.." -"..video_take_fps.." fps!!!"
  else
    name_color = colors.grey5
    name_txt = take_name
  end


  local bs_text = {"L", "C", "R", "LS", "LFE", "RS"}
  local col_w = colors.grey8
  local col_b = colors.black
  local col = colors.buttonColor_blue
  local col_h = colors.hoveredColor_blue
  -- local col_a = colors.activeColor_blue
  local s_col = colors.buttonColor_yellow
  local s_col_h = colors.hoveredColor_yellow
  -- local s_col_a = colors.activeColor_yellow
  local m_col = colors.buttonColor_red
  local m_col_h = colors.hoveredColor_red
  -- local m_col_a = colors.activeColor_red
  local ma_col = colors.buttonColor_pink
  local ma_col_h = colors.hoveredColor_pink

  local bs_col_txt = {col_w,col_w,col_w,col_w,col_w,col_w}
  local bs_col = {col,col,col,col,col,col}
  local bs_col_h = {col_h,col_h,col_h,col_h,col_h,col_h}
  -- local bs_col_a = {col_a,col_a,col_a,col_a,col_a,col_a}


  ImGui.PushFont(ctx, font_B, font_size_monitorsolo)
  for i=1,6 do
    if monitorsolo_vol_db[i]~="0" then
      bs_text[i] = monitorsolo_vol_db[i]
      bs_col_txt[i] = colors.red10
    end
    if monitorsolo_alwaysmute[i]==1 then
      bs_col_txt[i] = col_b
      bs_col[i] = ma_col
      bs_col_h[i] = ma_col_h
    else  
      if monitorsolo_state[i] == 2 then
        bs_col_txt[i] = col_b
        bs_col[i] = s_col
        bs_col_h[i] = s_col_h
        -- bs_col_a[i] = s_col_a
      elseif monitorsolo_state[i] == 0 then
        bs_col_txt[i] = col_w
        bs_col[i] = m_col
        bs_col_h[i] = m_col_h
        -- bs_col_a[i] = m_col_a
      end
    end

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 0, 0)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, bs_col_txt[i])
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, bs_col[i])
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, bs_col_h[i])
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, bs_col_h[i])

    if i<=3 then ImGui.SetCursorPos(ctx, curr_sizes.monitorsolo[1]+(i-1)*(init_left_space/3 + curr_spaces.monitorsolo + init_left_space/3), round(curr_sizes.monitorsolo[2]*1.1) + round(button_hight*0.1))
    else ImGui.SetCursorPos(ctx, curr_sizes.monitorsolo[1]+(i-4)*(init_left_space/3 + curr_spaces.monitorsolo + init_left_space/3), round(curr_value_sizes.rate[2]*1.1)) end

    ImGui.Button(ctx, bs_text[i].."##txt"..i, curr_spaces.monitorsolo + init_left_space/3, round(button_hight*0.9))
    ImGui.PopStyleColor(ctx, 4)
    ImGui.PopStyleVar(ctx, 1)

    if ImGui.IsItemHovered(ctx) and mwheel_val~=0 and
      not alt and not super and ctrl and not shift then
      set_monsolo_vol_by_mousewheel(i, mwheel_val)
    end

    if ImGui.IsItemHovered(ctx) and (ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) or
      ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Right)) then
      if ImGui.IsMouseClicked(ctx, ImGui.MouseButton_Left) then
        if alt and not super and ctrl and not shift then
        elseif alt and super and ctrl and not shift then
          set_monsolo_vol_by_mousewheel(i, "reset")

        elseif not alt and not super and not ctrl and not shift then
 
          if monitorsolo_alwaysmute[i] == 0 then
            local solo_count = 0
            local solo_j
            for j=1,6 do
              if monitorsolo_state[j] == 2 then
                solo_count = solo_count + 1
                solo_j = j
              end
            end

            if solo_count==1 and solo_j==i and monitorsolo_state[i]==2 then
              monitorsolo_state[i] = 1
            else
              for j=1,6 do
                if i==j then
                  monitorsolo_state[j] = 2
                else
                  if monitorsolo_state[j] ~= 0 then
                    monitorsolo_state[j] = 1
                  end
                end
              end
            end
          end
        elseif alt and not super and not ctrl and not shift then
 
          if monitorsolo_state[i] == 2 or monitorsolo_state[i] == 1 then
            monitorsolo_state[i] = 0
          elseif monitorsolo_state[i] == 0 then
            monitorsolo_state[i] = 1
          end
        elseif alt and super and not ctrl and not shift then
 
          monitorsolo_alwaysmute[i] = 1 - monitorsolo_alwaysmute[i]
          if monitorsolo_alwaysmute[i] == 1 then
            monitorsolo_state[i] = 0
            monitorsolo_jspar[i] = 0
          elseif monitorsolo_alwaysmute[i] == 0 then
            monitorsolo_state[i] = 1
            monitorsolo_jspar[i] = 1
          end
        elseif not alt and not super and ctrl and not shift then

          if monitorsolo_state[i] == 2 or monitorsolo_state[i] == 0 then
            monitorsolo_state[i] = 1
          elseif monitorsolo_state[i] == 1 then
            monitorsolo_state[i] = 2
          end
        elseif not alt and not super and not ctrl and shift then

          if monitorsolo_alwaysmute[i] == 0 then
            ---- CENTER ----
            if i==2 then
              if monitorsolo_state[1] ~= 2 or monitorsolo_state[2] ~= 2 or monitorsolo_state[3] ~= 2 then
                monitorsolo_state[1] = 2
                monitorsolo_state[2] = 2
                monitorsolo_state[3] = 2
              elseif monitorsolo_state[i] == 2 then
                monitorsolo_state[1] = 1
                monitorsolo_state[2] = 1
                monitorsolo_state[3] = 1
              end
              for j=1,6 do
                if j~=1 and j~=2 and j~=3 then
                  if monitorsolo_state[j] ~= 0 then
                    monitorsolo_state[j] = 1
                  end
                end
              end
            end
            ---- FL + FR ----
            if i==1 or i==3 then
              if monitorsolo_state[1] ~= 2 or monitorsolo_state[3] ~= 2 then
                monitorsolo_state[1] = 2
                monitorsolo_state[3] = 2
              elseif monitorsolo_state[i] == 2 then
                monitorsolo_state[1] = 1
                monitorsolo_state[3] = 1
              end
              for j=1,6 do
                if j~=1 and j~=3 then
                  if monitorsolo_state[j] ~= 0 then
                    monitorsolo_state[j] = 1
                  end
                end
              end
            end
            ---- LS + RS ----
            if i==4 or i==6 then
              if monitorsolo_state[4] ~= 2 or monitorsolo_state[6] ~= 2 then
                monitorsolo_state[4] = 2
                monitorsolo_state[6] = 2
              elseif monitorsolo_state[i] == 2 then
                monitorsolo_state[4] = 1
                monitorsolo_state[6] = 1
              end
              for j=1,6 do
                if j~=4 and j~=6 then
                  if monitorsolo_state[j] ~= 0 then
                    monitorsolo_state[j] = 1
                  end
                end
              end
            end
          end
        elseif not alt and not super and ctrl and shift then

          if monitorsolo_alwaysmute[i] == 0 then
            ---- FL + LS ----
            if i==1 or i==4 then
              if monitorsolo_state[1] ~= 2 or monitorsolo_state[4] ~= 2 then
                monitorsolo_state[1] = 2
                monitorsolo_state[4] = 2
              elseif monitorsolo_state[i] == 2 then
                monitorsolo_state[1] = 1
                monitorsolo_state[4] = 1
              end
              for j=1,6 do
                if j~=1 and j~=4 then
                  if monitorsolo_state[j] ~= 0 then
                    monitorsolo_state[j] = 1
                  end
                end
              end
            end
            ---- FR + RS ----
            if i==3 or i==6 then
              if monitorsolo_state[3] ~= 2 or monitorsolo_state[6] ~= 2 then
                monitorsolo_state[3] = 2
                monitorsolo_state[6] = 2
              elseif monitorsolo_state[i] == 2 then
                monitorsolo_state[3] = 1
                monitorsolo_state[6] = 1
              end
              for j=1,6 do
                if j~=3 and j~=6 then
                  if monitorsolo_state[j] ~= 0 then
                    monitorsolo_state[j] = 1
                  end
                end
              end
            end
          end          
        end
      end

      set_monitorsolo_state_to_jspar()
      get_set_monitorsolo(1,1,nil)
    end
  end
  ImGui.PopFont(ctx)


  local draw_list = ImGui.GetWindowDrawList(ctx)
  -- ImGui.DrawList_AddRectFilled(draw_list, mw_x, mw_y, mw_x+mw_w/2.5, mw_y+mw_h, colors.activeColor_red)
  ImGui.DrawList_AddLine(draw_list, mw_x+curr_sizes.vol_lb[1]- init_left_space/2 ,mw_y, mw_x+curr_sizes.vol_lb[1]- init_left_space/2, mw_y+mw_h, colors.grey5, line_thickness)
  ImGui.DrawList_AddLine(draw_list, mw_x+curr_sizes.framerate[1]- init_left_space/2 ,mw_y, mw_x+curr_sizes.framerate[1]- init_left_space/2, mw_y+mw_h, colors.grey5, line_thickness)
  ImGui.PushClipRect(ctx,mw_x+curr_sizes.name[1], mw_y+curr_sizes.name[2], mw_x+curr_sizes.chmode[1]+curr_spaces.chmode+ init_left_space/2, mw_y+row2_y, true)
  ImGui.DrawList_AddText(draw_list, mw_x+curr_sizes.name[1], mw_y+curr_sizes.name[2], name_color, name_txt)

  -- local mouse_x, mouse_y = ImGui.GetMousePos(ctx)

  if not is_any_menu_open() and actual_item~=-1 and in_range_equal(mouse_x, mw_x+curr_sizes.name_lb[1], mw_x+curr_sizes.chmode[1]+curr_spaces.chmode+ init_left_space/2) and
     in_range_equal(mouse_y, mw_y+curr_sizes.name_lb[2], mw_y+row2_y) then
    local str
    if actual_item_type_is == "VIDEO" then
      take_name_str = "Name: "..take_name.."\nPath: "..take_path.."\n\n --- Video ---".."\nCodec: "..video_take_codec.."\nBitrate: "..video_take_bitrate.."\nResolution: "..video_take_res.."\nFramerate: "..video_take_fps.."\n\n --- Audio ---".."\nChan num: "..take_channel_num.."\nBit depth: "..take_bit_depth.."\nSamplerate: "..take_samplerate
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, take_name_str)
      ImGui.PopStyleColor(ctx,1)  -- Здесь на 5422 ошибка take_path nil
    elseif actual_item_type_is ~= "VIDEO" and actual_item_type_is ~= "EMPTY" and actual_item_type_is ~= "MIDI" then
      take_name_str = "Name: "..take_name.."\nPath: "..take_path.."\n\nChan num: "..take_channel_num.."\nBit depth: "..take_bit_depth.."\nSamplerate: "..take_samplerate
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, colors.buttonColor_grey)
      ImGui.SetTooltip(ctx, take_name_str)
      ImGui.PopStyleColor(ctx,1)
    end

  end      
    

  ImGui.PopID(ctx)

  ImGui.PopFont(ctx)
end

-- function contextMenu()
  -- local dock_id = ImGui.GetWindowDockID(ctx)
  -- if ImGui.BeginPopupContextWindow(ctx) then
    -- if ImGui.MenuItem(ctx, 'Dock', nil, dock_id ~= 0) then
      -- set_dock_id = dock_id == 0 and -1 or 0
    -- end
    -- ImGui.EndPopup(ctx)
  -- end
-- end

function loop()

  if set_dock_id then
    if set_dock_id ~= 0 then
      is_docked = true
      r.SetExtState("McS-Tools", "MonitorToolbar_set_dock_id", tostring(set_dock_id), true)
      r.SetExtState("McS-Tools", "MonitorToolbar_window_x", tostring(window_x), true)
      r.SetExtState("McS-Tools", "MonitorToolbar_window_y", tostring(window_y), true)
      r.SetExtState("McS-Tools", "MonitorToolbar_window_w", tostring(window_w), true)
      r.SetExtState("McS-Tools", "MonitorToolbar_window_h", tostring(window_h), true)

    end
    if set_dock_id == 0 then
      is_docked = false
      r.SetExtState("McS-Tools", "MonitorToolbar_set_dock_id", "0", true)
      window_x = tonumber(r.GetExtState("McS-Tools", "MonitorToolbar_window_x"))
      window_y = tonumber(r.GetExtState("McS-Tools", "MonitorToolbar_window_y"))
      window_w = tonumber(r.GetExtState("McS-Tools", "MonitorToolbar_window_w"))
      window_h = tonumber(r.GetExtState("McS-Tools", "MonitorToolbar_window_h"))
      -- Msg(window_x)

      ImGui.SetNextWindowPos(ctx, window_x, window_y, ImGui.Cond_Always)
      ImGui.SetNextWindowSize(ctx, window_w, window_h, ImGui.Cond_Always)
    end
    ImGui.SetNextWindowDockID(ctx, set_dock_id)
    set_dock_id = nil
  end
  
  -- ImGui.SetNextWindowSize(ctx, 1160, 280, ImGui.Cond_FirstUseEver)

  --local windowBg = ImGui.ColorConvertHSVtoRGB( 0.0, 0.0, 0.1, 1.0)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, background_color)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 2.0)
  ImGui.PushFont(ctx, font, font_size)

  local visible, open = ImGui.Begin(ctx, 'MonitorToolbar', true, window_flags)

  if visible then
    framework()
    -- contextMenu()
    ImGui.PopStyleVar(ctx)
    ImGui.PopStyleColor(ctx)
    ImGui.End(ctx)
  else
    ImGui.PopStyleVar(ctx)
    ImGui.PopStyleColor(ctx)
  end
  ImGui.PopFont(ctx)

  if open then
    r.defer(loop)
  else
    -- local dock_id = ImGui.GetWindowDockID(ctx)
    -- if dock_id == 0 then
    -- end
    ImGui.DestroyContext(ctx)
  end
end

window_flags = ImGui.WindowFlags_None
| ImGui.WindowFlags_NoFocusOnAppearing
| ImGui.WindowFlags_NoScrollbar
| ImGui.WindowFlags_NoScrollWithMouse
| ImGui.WindowFlags_NoTitleBar
-- | ImGui.WindowFlags_NoMove()
-- | ImGui.WindowFlags_NoDecoration()
-- | ImGui.WindowFlags_NoNav()
-- | ImGui.WindowFlags_NoNavFocus()

-- | ImGui.WindowFlags_NoDocking()
-- | ImGui.WindowFlags_AlwaysAutoResize()
-- | ImGui.WindowFlags_NoSavedSettings()

-- get_framerate()
-- update_actual_item(actual_item_guid)

r.defer(loop)

