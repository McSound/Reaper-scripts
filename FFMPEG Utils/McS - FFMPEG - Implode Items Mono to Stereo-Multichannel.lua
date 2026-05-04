 --@ description: McS - FFMPEG - Implode Items Mono to Stereo-Multichannel
 --@ author: McSound
 --@ version:1.0
 --@ instructions: Select at once all items that you want to convert to stereo, 
 --                L-R-C, L-R-Lb-Rb, L-R-C-Lb-Rb or L-R-C-LFE-Lb-Rb files. 
 --                They'll implode to the format corresponding to to the num of channels found.
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

local pattern = {
                  {"%.L","%.R","%.C","%.LFE","%.Ls","%.Rs"},
                  {"_L","_R","_C","_LFE","_Ls","_Rs"}, 
                  {"%.%d+"},
                  -- "","","","","","",
                  -- "","","","","","",
                  -- "","","","","","",
                  }

function execute(num)
  local file_in = item_grp[num].file_in
  local file_out = item_grp[num].file_out
  local path = item_grp[num].path
  local mode = #file_in

  local inp_sect
  local arguments
  local bits, bits_24, bits_32 = "","pcm_s24le","pcm_s32le"
  if mode == 2 then
    inp_sect = " -i "..'"'..file_in[1]..'"'.." -i "..'"'..file_in[2]..'" '
    arguments = [[ -filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[a]" -map "[a]" -c:a pcm_s24le ]]
  elseif mode == 3 then
    inp_sect = " -i "..'"'..file_in[1]..'"'.." -i "..'"'..file_in[2]..'"'.." -i "..'"'..file_in[3]..'" '
    arguments = [[ -filter_complex "[0:a][1:a][2:a]join=inputs=3:channel_layout=3.0:map=0.0-FL|1.0-FR|2.0-FC[a]" -map "[a]" -c:a pcm_s24le ]]
  elseif mode == 4 then
    inp_sect = " -i "..'"'..file_in[1]..'"'.." -i "..'"'..file_in[2]..'"'.." -i "..'"'..file_in[3]..'"'.." -i "..'"'..file_in[4]..'" '
    arguments = [[ -filter_complex "[0:a][1:a][2:a][3:a]join=inputs=4:channel_layout=4.0:map=0.0-FL|1.0-FR|2.0-BL|3.0-BR[a]" -map "[a]" -c:a pcm_s24le ]]
  elseif mode == 5 then
    inp_sect = " -i "..'"'..file_in[1]..'"'.." -i "..'"'..file_in[2]..'"'.." -i "..'"'..file_in[3]..'"'.." -i "..'"'..file_in[4]..'"'.." -i "..'"'..file_in[5]..'" '
    arguments = [[ -filter_complex "[0:a][1:a][2:a][3:a][4:a]join=inputs=5:channel_layout=5.0:map=0.0-FL|1.0-FR|2.0-FC|3.0-BL|4.0-BR[a]" -map "[a]" -c:a pcm_s24le ]]
  elseif mode == 6 then
    inp_sect = " -i "..'"'..file_in[1]..'"'.." -i "..'"'..file_in[2]..'"'.." -i "..'"'..file_in[3]..'"'.." -i "..'"'..file_in[4]..'"'.." -i "..'"'..file_in[5]..'"'.." -i "..'"'..file_in[6]..'" '
    arguments = [[ -filter_complex "[0:a][1:a][2:a][3:a][4:a][5:a]join=inputs=6:channel_layout=5.1:map=0.0-FL|1.0-FR|2.0-FC|3.0-LFE|4.0-BL|5.0-BR[a]" -map "[a]" -c:a pcm_s24le ]]
  end

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

  local _, _, _, _, _, reverse = r.BR_GetMediaSourceProperties(take)
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
    path = path:match("(.+)\\$") -- delete last "\"" in path
    name_ext = name.."."..ext

  end
  return {item=item, take=take, st=st, ln=ln, en=en, take_off=take_off, chunk=chunk,
    track=track, track_num=track_num, 
  source=source, source_length=source_length, sample_rate=sample_rate, 
  num_channels=num_channels, bitdepth=bitdepth, bitrate=bitrate, --count_env=count_env,
  filename=filename, path=path, name=name, ext=ext, name_ext=name_ext,
  file_out=nil, ptr_num=nil}  
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

function find_pattern(name)
  for i=1, #pattern do
    if i==3 then
      local str = "^(.+)("..pattern[3][1]..")$"
      local name_without_ptr, ptr = name:match(str)
      local found_num = ptr:match("%.(%d+)")
      if found_num then return 3, 1, name_without_ptr, found_num end
    else
      for j=1,#pattern[i] do
        local str = "^(.+)("..pattern[i][j]..")$"
        local name_without_ptr, ptr = name:match(str)
        if ptr then return i, j, name_without_ptr, found_num end
      end
    end
  end
  return nil
end

function find_group(out_filename, st, en, track_num, ptr_num)
  for i=1,#item_grp do
    if item_grp[i].file_out == out_filename and 
       item_grp[i].st==st and item_grp[i].en==en and 
       track_num == item_grp[i].track_num+1 and 
       item_grp[i].file_in[ptr_num-1]~=nil then
      return i
    end
  end
  return nil
end

function create_item_grp(sel_items, idx, ptr_num, out_filename, mode)
  local t = {}
  t[ptr_num] = sel_items[idx].filename
  local st = sel_items[idx].st
  local en = sel_items[idx].en
  local track_num = sel_items[idx].track_num
  table.insert(item_grp, {mode=mode, st=st, en=en, track_num=track_num, file_in=t, file_out=out_filename})
end

function resort_item_group_file_in_idx()
  for i=1,#item_grp do
    if item_grp[i].mode==2 then
      local min = huge
      for k,v in pairs(item_grp[i].file_in) do
        if k<min then min=k end
      end
      if min > 1 then
        local t = {}
        for k,v in pairs(item_grp[i].file_in) do
          t[k-min+1] = v
        end
        item_grp[i].file_in = t
      end
    end
  end
end

function Main()
  local count_sel_items = r.CountSelectedMediaItems(0)
  if count_sel_items == 0 then return end

  local sel_items = get_sel_items_table()
  if #sel_items>0 then
    local first_track_num = sel_items[1].track_num
    for i=1,#sel_items do
      local ext_input = string.lower(sel_items[i].ext)
      if ext_avail[ext_input] then
        local path = sel_items[i].path
        local name = sel_items[i].name
        local ext  = sel_items[i].ext
        local ptr_row, ptr_num, name_without_ptr, found_num = find_pattern(name)
        local mode = 1 -- mode with basic patterns _L, _R etc.

        if ptr_num then
          if found_num~=nil then
            ptr_num = tonum(found_num)
            mode = 2
          end
          local out_filename = proj_media_path..sep..name_without_ptr..".wav"
          sel_items[i].ptr_num = ptr_num
          sel_items[i].file_out = out_filename
          if sel_items[i].track_num==first_track_num then
            create_item_grp(sel_items, i, ptr_num, out_filename, mode)
          else
            local st = sel_items[i].st
            local en = sel_items[i].en
            local track_num = sel_items[i].track_num
            local num_g = find_group(out_filename, st, en, track_num, ptr_num)
            if num_g~=nil then
              item_grp[num_g].file_in[ptr_num] = sel_items[i].filename
              sel_items[i].ptr_num = -1
            else
              create_item_grp(sel_items, i, ptr_num, out_filename, mode)
            end
          end
        end

      end        
    end

  end

  if #item_grp>0 then
    resort_item_group_file_in_idx() -- works if item_group is mode 2 only

    for i=1, #item_grp do
      if not output_file_exist[item_grp[i].file_out] then
        output_file_exist[item_grp[i].file_out] = true
        if not r.file_exists(item_grp[i].file_out) then 
          execute(i)
        end
      end
    end

    for i= #sel_items, 1, -1 do
      if sel_items[i].ptr_num~=-1 then
        sel_items[i].chunk = sel_items[i].chunk:gsub([[FILE ".+"]], [[FILE "]]..sel_items[i].file_out..[["]])
        local new_chunk = sel_items[i].chunk:gsub('({.-})', function() return r.genGuid() end)
        r.SetItemStateChunk(sel_items[i].item, new_chunk, false)
      else
        r.DeleteTrackMediaItem(sel_items[i].track, sel_items[i].item)
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
