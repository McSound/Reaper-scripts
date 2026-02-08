 --@ description: Script deletes all audiotracks in videofile and places specified audio to videofile
 --@              without recalculation video.
 --@ author: McSound
 --@ version:1.0
 --@ instructions: Select Video file or specify in browser. Then specify Audio - wav file. 
 --@               If your video codec is H264 then you should choose 1.
 --@               If your video codec is DHxHD or ProRes then choose 2.
 --@               You can select multiple video files and specify audio for each of them to perform batch conversion.
 --@ repository: https://github.com/McSound/Reaper-scripts/raw/master/index.xml
 --@ licence: GPL v3
 --@ forum thread:
 --@ Reaper v 7.53
 
--[[
 * Changelog:
 * v1.0 (2025-11-14)
  + Initial Release
--]]

local AAC_bitrate = "320k"

local r = reaper
local modf = math.modf
local floor = math.floor
local abs = math.abs
local log = math.log
local tonum = tonumber
local tostr = tostring

local audio_format
local windows = string.find(r.GetOS(), "Win") ~= nil
local sep = package.config:sub(1,1)
local reaper_path = r.GetResourcePath()

function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end
-- Msg(sep)

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return floor(num * mult + 0.5) / mult
end

local ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg') -- v4.4.1 work faster !!! ???
-- local ffmpeg_file = reaper_path..sep..'Scripts'..sep..'McSound'..sep..'FFMPEG Utils'..sep..'FFMPEG'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
-- Msg(ffmpeg_file)

if not r.file_exists(ffmpeg_file) then
  ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
end

-- Msg(ffmpeg_file)

if not r.file_exists(ffmpeg_file) then
  Msg("ffmpeg.exe is not found!")
  return
end


function in_range(value, min, max)
  if value==nil or min==nil or max==nil then return nil end
  if value >= min and value <= max then
    return true
  else
    return false
  end
end

function execute(pathV, nameV, extV, audio_file, track, item, pos)


  local arguments
  if audio_format == "AAC" then
    arguments = " -c:v copy -map 0:v:0 -c:a aac -b:a "..AAC_bitrate.." -map 1:a:0 "
  elseif audio_format == "WAV" then
    arguments = " -c:v copy -map 0:v:0 -c:a copy -map 1:a:0 "
  end
  local video_file = pathV..nameV.."."..extV
  local output_file = pathV..nameV.."-FinalSound."..extV

  local s_num = 0
  for i=1,99 do
    local f = io.open(output_file,"r")
    if f ~= nil then
      s_num = i
      local suff = ""
      if s_num > 0 then 
        suff = "-"..tostring(s_num)
        if s_num < 10 then 
          suff = "-0"..tostring(s_num)
        end
      end      
      output_file = pathV..nameV.."-FinalSound"..suff.."."..extV
      f:close()
    else
      break 
    end
  end


  local command = '"'..ffmpeg_file..'"'.." -i "..'"'..video_file..'"'.." -i "..'"'..audio_file..'"'..arguments..'"'..output_file..'"'
-- Msg(command)
  if track~= nil and item~=nil then
    r.DeleteTrackMediaItem(track, item)
  end

  if windows then
    local retval = r.ExecProcess(command, 0)
    if retval== "NULL" then Msg("Something's gone really wrong") end
  else
    os.execute(command)
  end

  if track~= nil and item~=nil then
    r.SetOnlyTrackSelected(track)
    r.SetEditCurPos(pos, false, false)
    r.InsertMedia(output_file, 0)
  end

end

function audio_format_question()
  local show_str = "Press number: Your Video is MP4 or H264- 1,  Your Video is Prores or DNxHD- 2"
  local userOK, val
  repeat
    -- "Enter full path of the folder:, File Name, extrawidth=400"
    userOK, val = r.GetUserInputs(show_str, 1, "Press 1 (AAC) or 2 (WAV),extrawidth=100", "")
    if not userOK then return end
    if val ~= "1" and val ~= "2" then
      show_str = "Wrong input. " .. show_str
    end
  until val == "1" or val == "2"
  if val == "1" then audio_format = "AAC"
  elseif val == "2" then audio_format = "WAV" end
end


function Main()
  local time = r.time_precise()
  

  local count_sel_items = r.CountSelectedMediaItems(0)
  v_items = {}
  a_items = {}
  if count_sel_items > 0 then
    for i=0,count_sel_items-1 do
      local item = r.GetSelectedMediaItem(0,i)
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local track = r.GetMediaItem_Track(item)
      local take = r.GetActiveTake(item)
      if take and not r.TakeIsMIDI(take) then
        local source = r.GetMediaItemTake_Source(take)
        local type = r.GetMediaSourceType(source, "")
        local path_name = tostring(r.GetMediaSourceFileName(source))
        local path, name, ext = string.match(path_name, "(.-)([^\\]-)%p([^%.]+)$")
        if string.lower(ext)=="m4a" then
          type = "AUDIO"
        end
        if type == "VIDEO" then
          v_items[#v_items+1] = {track=track, item=item, pos=pos, path=path, name=name, ext=ext}
        end
      end
    end

    audio_format_question()
    if audio_format == nil then return end

    for i=1,#v_items do
      local retvalV, audio_file = r.GetUserFileNameForRead("", "Select WAV audio file to replace sound for "..v_items[i].name.."."..v_items[i].ext, "wav")
      if not retvalV then return end
      local path, name, ext = string.match(audio_file, "(.-)([^\\]-)%p([^%.]+)$")
      if ext ~= "wav" then Msg("It's not a WAV audio file") return end
      a_items[i] = audio_file
    end
    for i=1,#v_items do
      execute(v_items[i].path, v_items[i].name, v_items[i].ext, a_items[i], v_items[i].track, v_items[i].item, v_items[i].pos)
    end
  else
    local windowText = "Choose VIDEO files for replacing audio:"
    local extList = "Video files ( MOV, MP4, AVI )\0*.mov;*.mp4;*.avi\0Mov files (.mov)\0*.mov\0Mp4 files (.mp4)\0*.mp4\0Avi files (.avi)\0*.avi\0\0"
    local retval, fileNames = r.JS_Dialog_BrowseForOpenFiles(windowText, "", "", extList, true)
    if retval<1 then return end

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

      audio_format_question()
      if audio_format == nil then return end

      for i=1, #v_items do
        ::rep::
        local v_name = v_items[i].name.."."..v_items[i].ext
        local retvalA, audio_file = r.GetUserFileNameForRead("", "Select AUDIO WAV file for "..v_name..":", "wav")
        if not retvalA then return end
        local pathA, nameA, extA = string.match(audio_file, "(.-)([^\\]-)%p([^%.]+)$")
        if extA ~= "wav" then Msg("It's not a valid AUDIO file") goto rep end
        a_items[i] = audio_file
      end


      for i=1, #v_items do
        execute(v_items[i].path, v_items[i].name, v_items[i].ext, a_items[i])
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
