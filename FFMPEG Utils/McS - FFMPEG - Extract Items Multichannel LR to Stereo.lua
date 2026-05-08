 --@ description: McS - FFMPEG - Extract Items Multichannel LR to Stereo
 --@ author: McSound
 --@ version:1.0
 --@ instructions: Specify IN and OUT folders. All found _L,_R files or
 --@               _L,_R,_C,_LFE,_LS,_RS will be converted to stereo or 6 ch files 
 --@               accordingly and placed to OUT folder, keeping the structure.
 --@ repository: https://github.com/McSound/Reaper-scripts/raw/master/index.xml
 

local r = reaper
local modf = math.modf
local floor = math.floor
local abs = math.abs
local log = math.log
local tonum = tonumber
local tostr = tostring
local huge = math.huge

local windows = string.find(r.GetOS(), "Win") ~= nil
local sep = package.config:sub(1,1)
local reaper_path = r.GetResourcePath()
local proj_media_path = r.GetProjectPath()

function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end

function round(num, numDecimalPlaces)
  local mult = 10^(numDecimalPlaces or 0)
  return floor(num * mult + 0.5) / mult
end

local ffmpeg_file = reaper_path..sep..'Scripts'..sep..'McSound'..sep..'FFMPEG Utils'..sep..'FFMPEG'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')

if not r.file_exists(ffmpeg_file) then
  ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
end

if not r.file_exists(ffmpeg_file) then
  Msg("ffmpeg.exe is not found!")
  return
end

local item_grp = {}
local output_file_exist = {}
local output_file = {}

local ext_avail = {
                   ["wav"]=true, 
                   ["aif"]=true,
                   ["aiff"]=true,
                   ["mp3"]=true, 
                   ["wma"]=true, 
                   ["flac"]=true, 
                   ["ogg"]=true, 
                   ["w4a"]=true,
                  }

function execute(num)
  local file_in = item_grp[num].file_in
  local file_out = item_grp[num].file_out

  local inp_sect
  local arguments
  local bits, bits_24, bits_32 = "","pcm_s24le","pcm_s32le"
  inp_sect = " -i "..'"'..file_in..'" '
  arguments = [[ -af "pan=stereo|c0=FL|c1=FR" ]]

  local command = '"'..ffmpeg_file..'"'.." -n"..inp_sect..arguments..'"'..file_out..'"'

  if windows then
    local retval = r.ExecProcess(command, 0)
  else
    os.execute(command)
  end
end


function fix_path_name(path)
  path = path:gsub([[\\]], [[\]])
  path = path:gsub([[/]], [[\]])
  return path
end

function get_item_params(item, take)
  local source_length, sample_rate, num_channels, bitdepth, bitrate, 
  filename, path, name, ext, name_ext = nil, nil, nil, nil, nil, nil, nil, nil, nil, nil

  local track = r.GetMediaItem_Track(item) 
  local track_num = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
  local take_off = r.GetMediaItemTakeInfo_Value(take,"D_STARTOFFS")
  local st = r.GetMediaItemInfo_Value(item,"D_POSITION")
  local ln = r.GetMediaItemInfo_Value(item,"D_LENGTH")
  local en = st + ln

  local ret, chunk = r.GetItemStateChunk(item, "", false)
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
    path = path:match("(.+)\\$") -- delete last \ in path
    name_ext = name.."."..ext

  end
  return {item=item, take=take, st=st, ln=ln, en=en, take_off=take_off, chunk=chunk,
    track=track, track_num=track_num, 
  source=source, source_length=source_length, sample_rate=sample_rate, 
  num_channels=num_channels, bitdepth=bitdepth, bitrate=bitrate,
  filename=filename, path=path, name=name, ext=ext, name_ext=name_ext,
  file_out=nil}  
end

function get_sel_items_table()
  local sel_item = {}
  local count_sel_items = r.CountSelectedMediaItems(0)
  for i=0,count_sel_items-1 do
    local item = r.GetSelectedMediaItem(0, i)
    local take = r.GetActiveTake(item)
    if take and not r.TakeIsMIDI(take) then
      local item_par = get_item_params(item, take)
      if item_par.source~=nil then
        table.insert(sel_item, item_par)
      end
    end
  end
  return sel_item
end


function Main()
  local count_sel_items = r.CountSelectedMediaItems(0)
  if count_sel_items == 0 then return end

  local sel_items = get_sel_items_table()
  if #sel_items>0 then
    for i=1,#sel_items do
      local ext_input = string.lower(sel_items[i].ext)
      if ext_avail[ext_input] and sel_items[i].num_channels>2 then
        sel_items[i].file_out = proj_media_path..sep..sel_items[i].name.."_LR.wav"
        table.insert(item_grp, {file_in=sel_items[i].filename, file_out=sel_items[i].file_out})
      end        
    end

  end

  if #item_grp>0 then

    for i=1, #item_grp do
      if not output_file_exist[item_grp[i].file_out] then
        output_file_exist[item_grp[i].file_out] = true
        if not r.file_exists(item_grp[i].file_out) then 
          execute(i)
        end
      end
    end

    for i= #sel_items, 1, -1 do
      if sel_items[i].file_out~=nil then
        local new_source = r.PCM_Source_CreateFromFile(sel_items[i].file_out)
        r.SetMediaItemTake_Source(sel_items[i].take, new_source)
        -- sel_items[i].chunk = sel_items[i].chunk:gsub([[FILE ".+"]], [[FILE "]]..sel_items[i].file_out..[["]])
        -- local new_chunk = sel_items[i].chunk:gsub('({.-})', function() return r.genGuid() end)
        -- r.SetItemStateChunk(sel_items[i].item, new_chunk, false)
      end
    end

    r.Main_OnCommand(40245, 0) --Peaks: Build any missing peaks for selected items

  end

end

r.PreventUIRefresh(1)
r.Undo_BeginBlock()

Main()

r.Undo_EndBlock("Name of Action", -1)
r.PreventUIRefresh(-1)
r.UpdateArrange()
