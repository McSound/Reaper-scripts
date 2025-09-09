local r = reaper

function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end

function file_codec(command,txt_file)
  if windows then
    local master_command = command
    master_command = 'cmd.exe /C "'..command..'"'
    local retval = r.ExecProcess( master_command, 0 ) -- save 'video_info.txt'
  else
    os.execute(command)
  end

  local f = io.open(txt_file) -- check in 'video_info.txt' if video_file's codec is dnxhd
  local file_lines = {}
  local i = 1
  for line in f:lines() do 
    file_lines[i] = line 
    i = i + 1 
  end
  f:close()
  local codec, res, fps, bitrate = file_lines[1]:match("(.+);(.+;.+);(.+);(.+)")

  return codec
end

function execute(path, name, ext, track, pos, item)
  local windows = string.find(r.GetOS(), "Win") ~= nil
  local separator = windows and '\\' or '/'

  local reaper_path = r.GetResourcePath()
  local video_file = path..name.."."..ext
  local output_file = path..name.."-DNxHD36.mov"
  local arguments1 = " -v error -select_streams v:0 -show_entries stream=codec_name -of csv=s=;:p=0 "
  local txt_file = reaper_path..separator..'Scripts'..separator..'McSound'..separator..'video_info.txt'
  local ffprobe_file = reaper_path..separator..'UserPlugins'..separator..(windows and 'ffprobe.exe' or 'ffprobe')
  local command1 = '"'..ffprobe_file..'"'..arguments1..'"'..video_file..'"'..' >'..'"'..txt_file..'"'

  local name_low = string.lower(name)
  local input_file_codec = ""
  if name_low:find("dnxhd") then
    input_file_codec = "dnxhd"
  end

  if item==nil and input_file_codec == "dnxhd" then
    r.InsertMedia(video_file, 0)
    r.Main_OnCommand(41174, 0) --Item navigation: Move cursor to end of items
  elseif item==nil and input_file_codec ~= "dnxhd" and r.file_exists(output_file) then
    r.InsertMedia(output_file, 0)
    r.Main_OnCommand(41174, 0) --Item navigation: Move cursor to end of items
  elseif item~=nil and input_file_codec ~= "dnxhd" and r.file_exists(output_file) then
    r.DeleteTrackMediaItem(track, item)
    r.SetOnlyTrackSelected(track)
    r.SetEditCurPos(pos, false, false)
    r.InsertMedia(output_file, 0)
  elseif input_file_codec ~= "dnxhd" then
    -- local bat_file = reaper_path..separator..'Scripts'..separator..'McSound'..separator..'ReaFFMPEG'..separator..'ffmpeg_action.bat'
    local ffmpeg_file = reaper_path..separator..'UserPlugins'..separator..(windows and 'ffmpeg.exe' or 'ffmpeg')
    local arguments2 = ' -c:v dnxhd -vf "scale=1920:1080,format=yuv422p" -b:v 36M -c:a pcm_s16le -map 0 '
    local command2 = '"'..ffmpeg_file..'"'.." -n -i "..'"'..video_file..'"'..arguments2..'"'..output_file..'"'

    Msg(command2)

    if item ~= nil then
      r.DeleteTrackMediaItem(track, item)
    end
    
    if windows then
      local retval = r.ExecProcess(command2, 0)
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
        else
          local name_low = string.lower(name)
          if not name_low:find("dnxhd") then
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
  local time_msg = "Done!\nTime processing: ".. r.time_precise() - time
  Msg(time_msg)

end

r.PreventUIRefresh(1)
r.Undo_BeginBlock()

Main()

r.Undo_EndBlock("Name of Action", -1)
r.PreventUIRefresh(-1)
r.UpdateArrange()
