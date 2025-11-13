local r = reaper
local huge = math.huge
local floor = math.floor
local abs = math.abs
local random = math.random
local pow = math.pow

function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end

local sep = package.config:sub(1,1)
local windows = string.find(r.GetOS(), "Win") ~= nil
local reaper_path = r.GetResourcePath()
-- local ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
local ffmpeg_file = reaper_path..sep..'Scripts'..sep..'McSound'..sep..'FFMPEG Utils'..sep..'FFMPEG'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')

if not r.file_exists(ffmpeg_file) then
  ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
end

if not r.file_exists(ffmpeg_file) then
  Msg("ffmpeg.exe is not found!")
  return
end

local process_performing = false
local check = {}

function ffmpeg_execute(path, name, ext)

  local video_file = path..sep..name.."."..ext
  local output_file = path..sep..name..".wav"

  local arguments = ' -vn -acodec pcm_s24le -ar 48000 -ac 2 '
  local command = '"'..ffmpeg_file..'"'.." -n -i "..'"'..video_file..'"'..arguments..'"'..output_file..'"'

  -- ffmpeg -i input.mp4 -vn -acodec pcm_s24le -ar 48000 -ac 2 output.wav

  if windows then
    local retval = r.ExecProcess(command, 0)
    -- Msg(output_file)
    -- Msg("done!")
    table.insert(check, output_file)
  else
    os.execute(command)
  end
end

function create_guide(path, name, ext, track, st, ln, take_off)
  if r.file_exists(path..sep..name..".wav") then
    local source = r.PCM_Source_CreateFromFile(path..sep..name..".wav")
    -- Msg(source)
    if source then
      local new_item = r.AddMediaItemToTrack(track)
      local take = r.AddTakeToMediaItem(new_item)
      r.SetMediaItemTake_Source(take, source)
      r.SetActiveTake(take)
      r.SetMediaItemInfo_Value(new_item, "D_POSITION", st)
      r.SetMediaItemInfo_Value(new_item, "D_LENGTH", ln)
      r.SetMediaItemTakeInfo_Value(take,"D_STARTOFFS", take_off)
      r.SetMediaItemInfo_Value(new_item, "B_LOOPSRC", 0)
      r.SetMediaItemInfo_Value(new_item,"D_VOL", 1)
    end
  end
end

function Main()
  count_sel_items = r.CountSelectedMediaItems(0)
  if count_sel_items == 0 then return end

  r.SetCursorContext(1)

  local sel_items = {}
  for i=0,count_sel_items-1 do
    local item = r.GetSelectedMediaItem(0, i)
    local st = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local ln = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local track = r.GetMediaItemTrack(item)
    local track_num = r.GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER')
    local _,name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    local take = r.GetActiveTake(item)
    local take_off = r.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS")
    local source = r.GetMediaItemTake_Source(take)
    local file_name = r.GetMediaSourceFileName(source)
    local str = r.GetMediaSourceType(source)
    if str == 'VIDEO' then
      sel_items[i+1] = {item=item, st=st, ln=ln, take_off=take_off, 
      track=track, track_name=name, track_num=track_num, file_name=file_name, done=false}
      -- Msg('Some of selected files are not VIDEO! Please select only VIDEO files')
      -- return
    end
  end


  if #sel_items>0 then

    for i=1, #sel_items do
      local item = sel_items[i].item
      local st = sel_items[i].st
      local ln = sel_items[i].ln
      local take_off = sel_items[i].take_off
      local file_name = sel_items[i].file_name
      local path, name, ext =  file_name:match("^(.-)([^\\/]-)%.([^\\/%.]-)%.?$")
      local track_guide = r.GetTrack(0, sel_items[i].track_num)
      r.SetMediaItemInfo_Value(item,"D_VOL", 0)

      ffmpeg_execute(path, name, ext)
      create_guide(path, name, ext, track_guide, st, ln, take_off)
    end
    r.Main_OnCommand(40047,0) --Peaks: Build any missing peaks

  end
end

r.PreventUIRefresh(1)
r.Undo_BeginBlock()

Main()

r.Undo_EndBlock("Extract Audio from Video", 0)
r.PreventUIRefresh(-1)
r.UpdateArrange()