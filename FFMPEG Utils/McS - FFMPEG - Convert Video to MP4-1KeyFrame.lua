 --@ description: Converts Video to MP4 with 1 key frame for archiving or smooth editing purposes.
 --@ author: McSound
 --@ version:1.0
 --@ instructions: Select Video file(s) and run script. 
 --@ repository: https://github.com/McSound/Reaper-scripts/raw/master/index.xml
 --@ licence: GPL v3
 --@ forum thread:
 --@ Reaper v 7.53
 
--[[
 * Changelog:
 * v1.0 (2025-11-14)
  + Initial Release
--]]

local r = reaper
local modf = math.modf
local floor = math.floor
local abs = math.abs
local log = math.log
local tonum = tonumber
local tostr = tostring

local windows = string.find(r.GetOS(), "Win") ~= nil
local sep = package.config:sub(1,1)
local reaper_path = r.GetResourcePath()


function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return floor(num * mult + 0.5) / mult
end

-- local ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
local ffmpeg_file = reaper_path..sep..'Scripts'..sep..'McSound'..sep..'FFMPEG Utils'..sep..'FFMPEG'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')

if not r.file_exists(ffmpeg_file) then
  ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
end

if not r.file_exists(ffmpeg_file) then
  Msg("ffmpeg.exe is not found!")
  return
end

function output_file_already_exists(output_file)
  local fv = io.open(output_file)
  if fv then 
    fv:close()
    return true
  else
    return false
  end
end

function execute(path, name, ext, track, pos, item)
  
  local video_file = path..name.."."..ext
  local output_file = path..name.."-KF1.mp4"
  
  -- local arguments1 = " -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of csv=s=;:p=0 "
  -- local txt_file = reaper_path..sep..'Scripts'..sep..'McSound'..sep..'video_info.txt'
  -- local ffprobe_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffprobe.exe' or 'ffprobe')
  -- local command1 = '"'..ffprobe_file..'"'..arguments1..'"'..video_file..'"'..' >'..'"'..txt_file..'"'

  -- if windows then
    -- local retval = r.ExecProcess(command1, 0)
    -- if retval== "NULL" then Msg("Something's gone really wrong") end
  -- else
    -- os.execute(command1)
  -- end
-- 
  -- local f = io.open(txt_file)
  -- local file_lines = {}
  -- local i = 1
  -- for line in f:lines() do file_lines[i] = line i = i + 1 end
  -- f:close()
  -- local codec, width, height, fps, bitrate = "","","","",""
  -- if #file_lines~=0 then
    -- codec, width, height, fps, bitrate = file_lines[1]:match("(.+);(.+);(.+);(.+);(.+)")
  -- end


  local name_low = string.lower(name)
  local input_file_codec = ""
  if name_low:find("-1kf") then
    input_file_codec = "-1kf"
  end

  if item==nil and input_file_codec == "-1kf" then
    r.InsertMedia(video_file, 0)
    r.Main_OnCommand(41174, 0) --Item navigation: Move cursor to end of items
  elseif item==nil and input_file_codec ~= "-1kf" and output_file_already_exists(output_file) then
    r.InsertMedia(output_file, 0)
    r.Main_OnCommand(41174, 0) --Item navigation: Move cursor to end of items
  elseif item~=nil and input_file_codec ~= "-1kf" and output_file_already_exists(output_file) then
    r.DeleteTrackMediaItem(track, item)
    r.SetOnlyTrackSelected(track)
    r.SetEditCurPos(pos, false, false)
    r.InsertMedia(output_file, 0)
  elseif input_file_codec ~= "-1kf" then

    local arguments2 = ' -vcodec libx264 -x264-params keyint=1:scenecut=0 -acodec copy '
    local command2 = '"'..ffmpeg_file..'"'.." -i "..'"'..video_file..'"'..arguments2..'"'..output_file..'"'
  
    if item ~= nil then
      r.DeleteTrackMediaItem(track, item)
    end

    if windows then
      local retval = r.ExecProcess(command2, 0)
      if retval== "NULL" then Msg("Something's gone really wrong") end
    else
      os.execute(command2)
    end

    if item ~= nil then
      r.SetOnlyTrackSelected(track)
      r.SetEditCurPos(pos, false, false)
    end
    r.InsertMedia(output_file, 0)
  end

end

function Main()
  local time = r.time_precise()

  local cursor_pos_init = r.GetCursorPosition()
  local track_init = r.GetSelectedTrack(0,0) or r.GetTrack(0, 0)
  local count_sel_items = r.CountSelectedMediaItems(0)
  v_items = {}
  if count_sel_items > 0 then
    for i=0,count_sel_items-1 do
      local item = r.GetSelectedMediaItem(0,i)
      local take = r.GetActiveTake(item)
      if take and not r.TakeIsMIDI(take) then
        local track = r.GetMediaItem_Track(item)
        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local source = r.GetMediaItemTake_Source(take)
        local type = r.GetMediaSourceType(source, "")
        local path_name = tostring(r.GetMediaSourceFileName(source))
        local path, name, ext = string.match(path_name, "(.-)([^\\]-)%p([^%.]+)$")
        if string.lower(ext)=="m4a" then
          type = "AUDIO"
        end
        if type ~= "VIDEO" then
          Msg("It's not a valid VIDEO file")
        else
          local name_low = string.lower(name)
          if not name_low:find("-kf1") then
            v_items[#v_items+1] = {item=item, track=track, pos=pos, path=path, name=name, ext=ext}
          end
        end
      end
    end

    for i=1,#v_items do
      execute(v_items[i].path, v_items[i].name, v_items[i].ext, v_items[i].track, v_items[i].pos, v_items[i].item)
    end
  else
    local windowText = "Choose files to convert to DNxHD36 and import into project:"
    local extList = "Video files ( MOV, MP4, AVI )\0*.mov;*.mp4;*.avi\0Mov files (.mov)\0*.mov\0Mp4 files (.mp4)\0*.mp4\0Avi files (.avi)\0*.avi\0\0"
    local retval, fileNames = r.JS_Dialog_BrowseForOpenFiles(windowText, "", "", extList, true)
    if retval<1 then return end
    local pos = r.GetCursorPosition()
    local track = r.GetSelectedTrack(0,0) or r.GetTrack(0,0)

    if track ~= nil then
      if not fileNames:match("\0") then -- single file selected?
        local path, name, ext = string.match(fileNames, "(.-)([^\\]-)%p([^%.]+)$")
        v_items[1] = {path=path, name=name, ext=ext}
      else -- multiple files selected
        local path = fileNames:match("^[^\0]*") -- if macOS, may be empty string, so use *
        for file in fileNames:gmatch("\0([^\0]+)") do
          local name, ext = string.match(file, "([^\\]-)%p([^%.]+)$")
          if ext == "mp4" or ext == "mov" or ext == "avi" then
            v_items[#v_items+1] = {path=path, name=name, ext=ext}
          end
        end
      end

      if #v_items > 0 then
        for i=1, #v_items do
          execute(v_items[i].path, v_items[i].name, v_items[i].ext, track , pos, nil)
        end
      end
    end
  end

  r.ClearConsole()
  
  local time_h, time_m, time_s = 0,0,0
  time_s = r.time_precise() - time

  if time_s>= 60 then
    time_m = modf(time_s/60)
    time_s = time_s - time_m*60
  end

  if time_m>= 60 then
    time_h = modf(time_m/60)
    time_m = time_m - time_h*60
  end
  time_s = round(time_s)

  local disp_h, disp_m, disp_s = "","",""
  if time_h>0 then 
    local str="hour"
    if time_h>1 then str="hours" end
    disp_h=tostr(time_h).." "..str..", "
  end
  if time_m>0 then 
    local str="minute"
    if time_m>1 then str="minutes" end
    disp_m=tostr(time_m).." "..str..", "
  end
  if time_s>0 then 
    local str="second"
    if time_s>1 then str="seconds" end
    disp_s=tostr(time_s).." "..str..", "
  end

  local time_msg = "Done! Time processing:\n"..disp_h..disp_m..disp_s
  Msg(time_msg)

end

r.PreventUIRefresh(1)
r.Undo_BeginBlock()

Main()

r.Undo_EndBlock("Name of Action", -1)
r.PreventUIRefresh(-1)
r.UpdateArrange()
