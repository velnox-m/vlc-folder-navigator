-- folder_nav.lua

local CHECK_INTERVAL_US = 500000

local cfg = type(config) == "table" and config or {}

local function as_bool(value, default)
	if value == nil then
		return default
	end
	if type(value) == "string" then
		local v = value:lower()
		return not (v == "false" or v == "0" or v == "no" or v == "off" or v == "")
	end
	if type(value) == "number" then
		return value ~= 0
	end
	return value and true or false
end

local DEPTH = math.max(0, math.floor(tonumber(cfg.depth) or 0))
local AUTO_LOOP = as_bool(cfg.loop, false)
local PRESERVE_CUSTOM = as_bool(cfg.preserve_custom, true)
local DEBUG = as_bool(cfg.debug, false)

local STAT_KEYS = { mtime = "modification_time", ctime = "creation_time", size = "size" }

local SORT_FIELD, SORT_DESC
do
	local spec = tostring(cfg.sort or "name"):lower()
	SORT_DESC = spec:match("_desc$") ~= nil
	SORT_FIELD = (spec:gsub("_desc$", ""):gsub("_asc$", ""))
	if SORT_FIELD ~= "name" and not STAT_KEYS[SORT_FIELD] then
		SORT_FIELD, SORT_DESC = "name", false
	end
end

local NEED_STAT = SORT_FIELD ~= "name"

local MEDIA_EXTENSIONS = {
	"mkv", "mp4", "avi", "webm", "mov", "m4v", "flv", "wmv", "mpg", "mpeg",
	"ts", "m2ts", "mts", "ogm", "ogv", "vob", "divx", "asf", "rmvb", "3gp",
	"3g2", "f4v", "mxf", "mp3", "flac", "wav", "ogg", "m4a", "opus", "wma",
	"aac", "alac", "ape", "aiff", "aif", "mka", "wv", "dsf", "dff", "mpc",
}

local media_exts = {}
for _, ext in ipairs(MEDIA_EXTENSIONS) do
	media_exts[ext] = true
end

local IS_WINDOWS = (package and package.config and package.config:sub(1, 1) == "\\")
	or vlc.win ~= nil

local managed_ids = {}
local handled_id = nil
local last_error = nil

local function log(message)
	if DEBUG then
		vlc.msg.warn("[folder_nav] " .. tostring(message))
	end
end

local function normalize(path)
	local p = path:gsub("\\", "/")
	return IS_WINDOWS and p:lower() or p
end

local function is_media_file(name)
	local ext = name:match("%.([^%.\\/]+)$")
	return ext ~= nil and media_exts[ext:lower()] == true
end

local function basename(path)
	return path:match("([^/\\]+)$")
end

local function natural_key(name)
	local key = name:lower():gsub("%d+", function(digits)
		local n = digits:gsub("^0+", "")
		if n == "" then
			n = "0"
		end
		return string.format("%03d", #n) .. n
	end)
	return key
end

local function by_name(a, b)
	if a.key ~= b.key then
		return a.key < b.key
	end
	if a.lname ~= b.lname then
		return a.lname < b.lname
	end
	return a.name < b.name
end

local function build_comparator()
	if SORT_FIELD == "name" then
		if SORT_DESC then
			return function(a, b) return by_name(b, a) end
		end
		return by_name
	end
	return function(a, b)
		local av, bv = a[SORT_FIELD], b[SORT_FIELD]
		if av ~= bv then
			if av == nil then
				return false
			end
			if bv == nil then
				return true
			end
			if SORT_DESC then
				return av > bv
			end
			return av < bv
		end
		return by_name(a, b)
	end
end

local compare_items = build_comparator()

local function percent_decode(text)
	return (text:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

local function percent_encode(text)
	return (text:gsub("[^%w%-%._~/:]", function(c)
		return string.format("%%%02X", c:byte())
	end))
end

local function path_to_uri(path)
	local p = path:gsub("\\", "/")
	local host = ""
	if p:sub(1, 2) == "//" then
		host, p = p:match("^//([^/]*)(.*)$")
	elseif p:sub(1, 1) ~= "/" then
		p = "/" .. p
	end
	return "file://" .. host .. percent_encode(p)
end

local function uri_to_path(uri)
	local rest = uri:match("^[fF][iI][lL][eE]://(.*)$")
	if not rest then
		return nil
	end
	rest = rest:gsub("[?#].*$", "")

	local host, path = rest:match("^([^/]*)(/.*)$")
	if not host then
		return nil
	end
	path = percent_decode(path)

	local remote = host ~= "" and host:lower() ~= "localhost"
	if IS_WINDOWS then
		if remote then
			return "\\\\" .. host .. (path:gsub("/", "\\"))
		end
		path = path:gsub("^/(%a:)", "%1")
		return (path:gsub("/", "\\"))
	end
	if remote then
		return nil
	end
	return path
end

local function split_dir(path)
	local dir = path:gsub("\\", "/"):match("^(.*)/[^/]*$")
	if dir == nil then
		return nil
	end
	if IS_WINDOWS then
		dir = dir:gsub("/", "\\")
		if dir:match("^%a:$") then
			dir = dir .. "\\"
		end
	elseif dir == "" then
		dir = "/"
	end
	return dir
end

local function join_path(dir, name)
	local last = dir:sub(-1)
	if last == "\\" or last == "/" then
		return dir .. name
	end
	return dir .. (IS_WINDOWS and "\\" or "/") .. name
end

local function current_uri()
	if not (vlc.input and vlc.input.item) then
		return nil
	end
	local ok, uri = pcall(function()
		local item = vlc.input.item()
		return item and item:uri() or nil
	end)
	return ok and uri or nil
end

local function stat_path(path)
	local stat_fn = (vlc.net and vlc.net.stat) or (vlc.io and vlc.io.stat)
	if not stat_fn then
		return nil
	end
	local ok, stat = pcall(stat_fn, path)
	if ok and type(stat) == "table" then
		return stat
	end
	return nil
end

local function list_entries(dir)
	local readers = {}
	if vlc.io and vlc.io.readdir then
		readers[#readers + 1] = vlc.io.readdir
	end
	if vlc.net and vlc.net.opendir then
		readers[#readers + 1] = vlc.net.opendir
	end
	for _, reader in ipairs(readers) do
		local ok, entries = pcall(reader, dir)
		if ok and type(entries) == "table" then
			return entries
		end
	end
	return nil
end

local function is_dir(path)
	local stat = stat_path(path)
	if stat and stat.type then
		return stat.type == "dir"
	end
	return list_entries(path) ~= nil
end

local function make_item(dir, name)
	local path = join_path(dir, name)
	local item = {
		name = name,
		lname = name:lower(),
		key = natural_key(name),
		path = path,
	}
	if NEED_STAT then
		local stat = stat_path(path)
		item[SORT_FIELD] = stat and tonumber(stat[STAT_KEYS[SORT_FIELD]]) or nil
	end
	return item
end

local function list_files(dir)
	local files = {}
	for _, name in pairs(list_entries(dir) or {}) do
		if type(name) == "string" and is_media_file(name) then
			files[#files + 1] = make_item(dir, name)
		end
	end
	table.sort(files, compare_items)
	return files
end

local function list_dirs(dir)
	local dirs = {}
	for _, name in pairs(list_entries(dir) or {}) do
		if type(name) == "string" and name ~= "." and name ~= ".." and not is_media_file(name) then
			local item = make_item(dir, name)
			if is_dir(item.path) then
				dirs[#dirs + 1] = item
			end
		end
	end
	table.sort(dirs, compare_items)
	return dirs
end

local function scan_tree(dir, depth)
	local files = list_files(dir)
	if depth > 0 then
		for _, subdir in ipairs(list_dirs(dir)) do
			for _, file in ipairs(scan_tree(subdir.path, depth - 1)) do
				files[#files + 1] = file
			end
		end
	end
	return files
end

local function find_index(files, path)
	local wanted = normalize(path)
	for i, file in ipairs(files) do
		if normalize(file.path) == wanted then
			return i
		end
	end
	return nil
end

local function current_playlist_id()
	if not (vlc.playlist and vlc.playlist.current) then
		return nil
	end
	local ok, id = pcall(vlc.playlist.current)
	if ok and type(id) == "number" and id >= 0 then
		return id
	end
	return nil
end

local function playlist_leaves()
	local ids, root_id = {}, nil
	if not vlc.playlist then
		return ids, root_id
	end

	local function visit(node)
		if type(node.children) == "table" then
			for _, child in ipairs(node.children) do
				visit(child)
			end
		elseif node.id then
			ids[#ids + 1] = node.id
		end
	end

	if vlc.playlist.get then
		local ok, tree = pcall(vlc.playlist.get, "playlist")
		if ok and type(tree) == "table" then
			root_id = tree.id
			visit(tree)
			return ids, root_id
		end
	end

	if vlc.playlist.list then
		local ok, list = pcall(vlc.playlist.list)
		if ok and type(list) == "table" then
			for _, item in ipairs(list) do
				if type(item) == "table" and item.id then
					ids[#ids + 1] = item.id
				end
			end
		end
	end
	return ids, root_id
end

local function adopt_playlist()
	managed_ids = {}
	for _, id in ipairs((playlist_leaves())) do
		managed_ids[id] = true
	end
end

local function count_unmanaged()
	local count = 0
	for _, id in ipairs((playlist_leaves())) do
		if not managed_ids[id] then
			count = count + 1
		end
	end
	return count
end

local function delete_others(keep_id)
	for _, id in ipairs((playlist_leaves())) do
		if id ~= keep_id then
			pcall(vlc.playlist.delete, id)
		end
	end
end

local function move_to_top(ids, count, root_id)
	if count > #ids or not root_id or not (vlc.playlist and vlc.playlist.move) then
		return false
	end
	for i = #ids, #ids - count + 1, -1 do
		local ok, ret = pcall(vlc.playlist.move, ids[i], root_id)
		if not ok or (ret ~= nil and ret ~= 0) then
			return false
		end
	end
	return true
end

local function build_queue(path)
	local dir = split_dir(path)
	if not dir then
		return nil
	end

	local files = list_files(dir)
	local index = find_index(files, path)
	if not index then
		local name = basename(path)
		if not name then
			return nil
		end
		files[#files + 1] = make_item(dir, name)
		table.sort(files, compare_items)
		index = find_index(files, path)
		if not index then
			return nil
		end
	end

	local following, preceding = {}, {}
	for i = index + 1, #files do
		following[#following + 1] = files[i]
	end
	if DEPTH > 0 then
		for _, subdir in ipairs(list_dirs(dir)) do
			for _, file in ipairs(scan_tree(subdir.path, DEPTH - 1)) do
				following[#following + 1] = file
			end
		end
	end
	for i = 1, index - 1 do
		preceding[#preceding + 1] = files[i]
	end
	return following, preceding
end

local function handle_new_item(path, id)
	if PRESERVE_CUSTOM and count_unmanaged() > 1 then
		adopt_playlist()
		log("kept custom playlist untouched")
		return
	end

	local following, preceding = build_queue(path)
	if not following then
		adopt_playlist()
		log("could not index current file in its folder")
		return
	end

	delete_others(id)

	local known = {}
	for _, leaf in ipairs((playlist_leaves())) do
		known[leaf] = true
	end

	local entries = {}
	for _, group in ipairs({ following, preceding }) do
		for _, file in ipairs(group) do
			entries[#entries + 1] = { path = path_to_uri(file.path), name = file.name }
		end
	end

	if #entries > 0 then
		vlc.playlist.enqueue(entries)
	end

	local leaves, root_id = playlist_leaves()
	local fresh = {}
	for _, leaf in ipairs(leaves) do
		if not known[leaf] then
			fresh[#fresh + 1] = leaf
		end
	end

	local ordered = #preceding == 0 or (#fresh == #entries and move_to_top(fresh, #preceding, root_id))

	if AUTO_LOOP or not ordered then
		pcall(vlc.playlist.loop, "on")
	end

	adopt_playlist()
	log(string.format("queued %d file(s) after and %d before the current one", #following, #preceding))
end

local function poll()
	local uri = current_uri()
	local path = uri and uri_to_path(uri)
	if not path then
		return
	end

	local id = current_playlist_id()
	if not id or managed_ids[id] or id == handled_id then
		return
	end

	handled_id = id
	handle_new_item(path, id)
end

while true do
	local ok, err = pcall(poll)
	if not ok and tostring(err) ~= last_error then
		last_error = tostring(err)
		vlc.msg.err("[folder_nav] " .. last_error)
	end
	vlc.misc.mwait(vlc.misc.mdate() + CHECK_INTERVAL_US)
end
