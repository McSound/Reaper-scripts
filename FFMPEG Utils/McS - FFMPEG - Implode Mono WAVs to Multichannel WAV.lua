 --@ description:
 --@ version:1.0
 --@ instructions: 
 --@ author: McSound
 --@ repository: https://github.com/McSound/Reaper-scripts/raw/master/index.xml
 --@ licence: GPL v3
 --@ forum thread:
 --@ Reaper v 7.52
 
--[[
 * Changelog:
 * v1.0 (2025-11-02)
  # Modification
  + Addition
  - Deletion
 * v1.0 (2015-02-27)
  + Initial Release
--]]

local r = reaper

local windows = string.find(r.GetOS(), "Win") ~= nil
local sep = package.config:sub(1,1)
local reaper_path = r.GetResourcePath()


function Msg(str) r.ShowConsoleMsg(tostring(str) .. "\n") end

-- local ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
local ffmpeg_file = reaper_path..sep..'Scripts'..sep..'McSound'..sep..'FFMPEG Utils'..sep..'FFMPEG'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')

if not r.file_exists(ffmpeg_file) then
  ffmpeg_file = reaper_path..sep..'UserPlugins'..sep..(windows and 'ffmpeg.exe' or 'ffmpeg')
end

if not r.file_exists(ffmpeg_file) then
  Msg("ffmpeg.exe is not found!")
  return
end


local file_exist = {}
local file_grp = {}

local pattern = {
                  {".L",".R",".C",".LFE",".Ls",".Rs"},
                  {"_L","_R","_C","_LFE","_Ls","_Rs"}, 
                  -- "","","","","","",
                  -- "","","","","","",
                  -- "","","","","","",
                  }

local dir_list = {}
local ch_n = 0

function fix_path_name(path)
  path = path:gsub([[\\]], [[\]])
  path = path:gsub([[/]], [[\]])
  return path
end

function folder_exists(path) -- sometimes doesn't work!
  local rt, size = r.JS_File_Stat(path)
  if rt==0 then
    return true
  elseif rt<0 then
    return false
  end
end

local function GetAllSubfolders(folderlist)
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
      local name, ext = file:match("^(.+)%.(.*)$")
      table.insert(files, {path=path, name_ext=file, name=name, ext=ext, size=size})
    else
      break
    end
  end
  return files
end

function execute(num)
  local file_in = file_grp[num].file_in
  local file_out = file_grp[num].file_out
  local path = file_grp[num].path
  -- local ext = file_grp[i].ext
  local mode = #file_in

  -- 6 mono wavs to 5.1 wav
  --ffmpeg -i front_left.wav -i front_right.wav -i front_center.wav -i lfe.wav -i back_left.wav -i back_right.wav -filter_complex "[0:a][1:a][2:a][3:a][4:a][5:a] amerge=inputs=6" output.wav

  local inp_sect
  local arguments
  if mode == 2 then
    inp_sect = " -i "..'"'..file_in[1]..'"'.." -i "..'"'..file_in[2]..'" '
    arguments = [[ -filter_complex "[0:a][1:a]join=inputs=2:channel_layout=stereo[a]" -map "[a]" -c:a pcm_s24le ]]
  elseif mode == 6 then
    inp_sect = " -i "..'"'..file_in[1]..'"'.." -i "..'"'..file_in[2]..'"'.." -i "..'"'..file_in[3]..'"'.." -i "..'"'..file_in[4]..'"'.." -i "..'"'..file_in[5]..'"'.." -i "..'"'..file_in[6]..'" '
    arguments = [[ -filter_complex "[0:a][1:a][2:a][3:a][4:a][5:a]join=inputs=6:channel_layout=5.1:map=0.0-FL|1.0-FR|2.0-FC|3.0-LFE|4.0-BL|5.0-BR[a]" -map "[a]" -c:a pcm_s24le ]]
  end

  -- -i front_left.wav -i front_right.wav -i front_center.wav -i lfe.wav -i back_left.wav -i back_right.wav -filter_complex "[0:a][1:a][2:a][3:a][4:a][5:a] amerge=inputs=6" output.wav

  -- local arguments = ' -c:v dnxhd -vf "scale=1920:1080,format=yuv422p" -b:v 36M -c:a pcm_s16le -map 0 '
  local command = '"'..ffmpeg_file..'"'.." -n"..inp_sect..arguments..'"'..file_out..'"'

  Msg(command)
  
  if windows then
    local retval = r.ExecProcess(command, 0)
  else
    os.execute(command)
  end
  -- r.InsertMedia(output_file, 0)

end

function get_source_params(source, file_name)
  local source_length, lengthIsQN = r.GetMediaSourceLength(source)
  local sample_rate = r.GetMediaSourceSampleRate(source)
  local num_channels = r.GetMediaSourceNumChannels(source)
  local bitdepth = r.CF_GetMediaSourceBitDepth(source)
  local bitrate = r.CF_GetMediaSourceBitRate(source)
  local rv, size = r.JS_File_Stat(file_name)
  -- local path, name_ext = string.match(file_name,"(.-)([^\\]-[^%.]+)$")
  -- local path, name, ext =  file_name:match("^(.-)([^\\/]-)%.([^\\/%.]-)%.?$")
  -- path = path:match("(.+)\\*$")

  return source_length, sample_rate, num_channels, bitdepth, bitrate, size
end


function get_file_properties(filename)
  local source = r.PCM_Source_CreateFromFile(filename)

  if source then
    r.PCM_Source_Destroy(source)
    return get_source_params(source, filename)
  end
  return nil
end

function find_pattern(name)
  for i=1, #pattern do
    for j=1,#pattern[i] do
      -- Msg(pattern[i][j])
      -- "^(.+)%.(.*)$"
      local str = "^(.+)("..pattern[i][j]..")$"
      -- Msg(str)
      local name_without_ptr, ptr = name:match(str)
      if ptr then return j,name_without_ptr end
    end
  end
  return nil
end

function find_group(out_filename)
  for i=1,#file_grp do
    if file_grp[i].file_out == out_filename then
      return i
    end
  end
  return nil
end

function Main()
  
  local retval, folder_in = r.JS_Dialog_BrowseForFolder("Choose Folder of INPUT WAV Files to Convert", nil )

  if retval==1 then
    
    local rt, folder_out = r.JS_Dialog_BrowseForFolder("Choose OUTPUT Folder", nil )

    if rt==1 then
      local time = r.time_precise()
    
      GetFolderStructure(folder_in)
  
      if #dir_list>0 then
        local sc,tk = 1,1
        for i=1,#dir_list do
          local files = GetAllFilesInFolder(dir_list[i].dir)
          if #files>0 then
            for j=1,#files do
              if string.lower(files[j].ext) == "wav" then
                local path = files[j].path
                local name = files[j].name
                local ext = files[j].ext
                local filename = path..sep..name.."."..ext
  
                local num, name_without_ptr = find_pattern(name)
                -- Msg(num)
                if num then
                  local source_length, sample_rate, num_channels, bitdepth, bitrate, size = get_file_properties(filename)
                  local new_folder
                  if not folder_exists(new_folder) then-- if folder is not found
                    r.RecursiveCreateDirectory(new_folder, 0)
                  end
                  -- local out_filename = path..sep..name_without_ptr..".wav"
                  local out_filename = "E:\\1"..sep..name_without_ptr..".wav"
                  if not file_exist[out_filename] then
                    file_exist[out_filename] = true
                    local t = {}
                    table.insert(t, {nil,nil,nil,nil,nil,nil})
                    t[num] = filename
                    table.insert(file_grp, {path=path, ext="wav",  file_in=t, file_out=out_filename})
                  else
                    local num_g = find_group(out_filename)
                    -- Msg(num_g)
                    if num_g then
                      file_grp[num_g].file_in[num] = filename
                    end
                  end
                end
  
              end
            end
          end
        end
      end
    
      if #file_grp>0 then
        for i=1,#file_grp do
          local f=true
          local count
          ---- check if we got all 6 files
          -- Msg(#file_grp[i].file_in)
          if #file_grp[i].file_in~=6 and #file_grp[i].file_in~=2 then f=false end
          
          if f then
            for j=1,#file_grp[i].file_in do
              if file_grp[i].file_in[j]==nil then
                f=false
                break
              end
            end
          end
  
          -- Msg(f)
          if f then
            execute(i)
          end
        end
      end
  
      -- r.ShowMessageBox("Please wait...", "Processing files", 0)
      -- for i=1,#v_items do
        -- execute(v_items[i].path, v_items[i].name, v_items[i].ext, v_items[i].track, v_items[i].pos, v_items[i].item)
      -- end
    
      local time_msg = "Done!\nTime processing: ".. r.time_precise() - time
      Msg(time_msg)
    end
    -- local msg_hwnd = r.JS_Window_Find("Processing files", true)
    -- r.JS_WindowMessage_Send(msg_hwnd, "WM_CLOSE")
  end

end

r.PreventUIRefresh(1)
r.Undo_BeginBlock()

Main()

r.Undo_EndBlock("Name of Action", -1)
r.PreventUIRefresh(-1)
r.UpdateArrange()
