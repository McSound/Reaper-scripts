 -- @description McS - FFMPEG - Take 1 Frame Snapshot from Video
 -- @author McSound
 -- @version 1.0
 -- @instructions Select Track and place cursor to wanted place of video (no need to select video)
 -- @repository https://github.com/McSound/Reaper-scripts/raw/master/index.xml

local r = reaper
local floor = math.floor

local windows = string.find(r.GetOS(), "Win") ~= nil
local sep = package.config:sub(1,1)
local reaper_path = r.GetResourcePath()
local proj_media_path = r.GetProjectPath()
local _, projectPath = r.EnumProjects(-1)
local path_proj, name, ext = projectPath:match("(.-)([^\\]-)%p([^%.]+)$")

function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return floor(num * mult + 0.5) / mult
end

function in_range_equal(value, min, max)
  if value==nil or min==nil or max==nil then return nil end
  if value >= min and value <= max then
    return true
  else
    return false
  end
end

local ffmpeg_file = reaper_path..sep..'Scripts'..sep..'McSound'..sep..'FFMPEG Utils'..sep..'FFMPEG'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')

if not r.file_exists(ffmpeg_file) then
  ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
end

if not r.file_exists(ffmpeg_file) then
  Msg("ffmpeg.exe is not found!")
  return
end

function folder_exists(path)
  local rt, size = r.JS_File_Stat(path)
  if rt==0 then
    return true
  elseif rt<0 then
    return false
  end
end

function find_video(cur_pos)
  local count_track = r.CountTracks(0)
  for t=0,count_track-1 do
    local track = r.GetTrack(0,t)
    local count_item = r.CountTrackMediaItems(track)
    if count_item>0 then
      for i=0, count_item-1 do
        local item = r.GetTrackMediaItem(track ,i)
        local st = r.GetMediaItemInfo_Value(item, "D_POSITION")
        local ln = r.GetMediaItemInfo_Value(item, "D_LENGTH")
        if in_range_equal(cur_pos, st, st+ln) then
          local take = r.GetActiveTake(item)
          if take then
            local source = r.GetMediaItemTake_Source(take)
            if source then
              local item_type = r.GetMediaSourceType(source, "")
              if item_type == "VIDEO" then
                return item, st
              end
            end
          end
        end
      end
    end
  end
  return nil
end

function execute(video_filename, file_out, time)

  local inp_sect = " -i "..'"'..video_filename..'"'
  local arguments1 = " -ss "
  local arguments2 = " -frames:v 1 "

  -- time = round(time,2)

  local command = '"'..ffmpeg_file..'"'..arguments1..time..inp_sect..arguments2..'"'..file_out..'"'

  -- ffmpeg -ss 00:01:30 -i input.mp4 -frames:v 1 output.jpg
  if windows then
-- Msg(command)
    local retval = r.ExecProcess(command, 0)
  else
    os.execute(command)
  end
  return file_out
end


function Main()
  local cur_pos = r.GetCursorPosition()
    
  local video_item, video_st = find_video(cur_pos)
  if video_item~=nil then
    local video_take = r.GetActiveTake(video_item)
    local video_source = r.GetMediaItemTake_Source(video_take)
    local video_filename = r.GetMediaSourceFileName(video_source)
    if video_filename~=nil then
      -- Msg(video_filename)
      local path, name, ext = video_filename:match("(.-)([^\\]-)%p([^%.]+)$")
      -- check for JPG path
      local out_path = path_proj.."JPG"
      if not folder_exists(out_path) then
        r.RecursiveCreateDirectory(out_path, 0)
      end

      -- check for jpg files
      local count = 1
      local out_name = name.."_01"
      while r.file_exists(out_path..sep..out_name..".jpg") do
        count=count+1
        local str = tostring(count)
        if count < 10 then str = "0"..tostring(count) end
        out_name = name.."_"..str
        -- Msg(out_name)
      end

      local file_out = out_path.. sep.. out_name..".jpg"
      execute(video_filename, file_out, cur_pos-video_st)


      if r.file_exists(file_out) then
        local take_name = out_name

        local userOK, new_name = r.GetUserInputs("Want to give a name to the Snapshot?", 1, "Type in new name:, extrawidth=100", "")
        if userOK then 
          take_name = new_name
        end

        local track = r.GetSelectedTrack(0, 0)
        local item = r.AddMediaItemToTrack(track)
        local take = r.AddTakeToMediaItem(item)
        r.BR_SetTakeSourceFromFile(take, file_out, false)
        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)
        r.SetMediaItemInfo_Value(item, "D_POSITION", cur_pos)
        r.SetMediaItemInfo_Value(item, "D_LENGTH", 3)
      end
    end
  end
end

r.PreventUIRefresh(1)
r.Undo_BeginBlock()

Main()

r.Undo_EndBlock("Take 1 Frame Snapshot from Video", -1)
r.PreventUIRefresh(-1)
r.UpdateArrange()

