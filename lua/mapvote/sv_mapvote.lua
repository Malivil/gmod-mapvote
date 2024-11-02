util.AddNetworkString("RAM_MapVoteStart")
util.AddNetworkString("RAM_MapVoteUpdate")
util.AddNetworkString("RAM_MapVoteCancel")
util.AddNetworkString("RAM_MapVoteOpen")
util.AddNetworkString("RTV_Delay")

MapVote.Continued = false

net.Receive("RAM_MapVoteUpdate", function(len, ply)
    if MapVote.Allow and IsValid(ply) then
        local update_type = net.ReadUInt(3)

        if update_type == MapVote.UPDATE_VOTE then
            local map_id = net.ReadUInt(32)

            if MapVote.CurrentMaps[map_id] then
                MapVote.Votes[ply:SteamID()] = map_id

                net.Start("RAM_MapVoteUpdate")
                net.WriteUInt(MapVote.UPDATE_VOTE, 3)
                net.WriteEntity(ply)
                net.WriteUInt(map_id, 32)
                net.Broadcast()
            end
        end
    end
end)

local recentmaps
if file.Exists( "mapvote/recentmaps.txt", "DATA" ) then
    recentmaps = util.JSONToTable(file.Read("mapvote/recentmaps.txt", "DATA")) or {}
else
    recentmaps = {}
end

if file.Exists( "mapvote/config.txt", "DATA" ) then
    MapVote.Config = util.JSONToTable(file.Read("mapvote/config.txt", "DATA"))
    if not MapVote.Config then
        ErrorNoHalt("Failed to read mapvote/config.txt! Using default settings...")
        MapVote.Config = {}
    end
else
    MapVote.Config = {}
end

local excludemaps
if file.Exists( "ulx/votemaps.txt", "DATA" ) then
    local votemaps = file.Read("ulx/votemaps.txt", "DATA")
    if not votemaps then
        excludemaps = {}
    else
        excludemaps = string.Split(votemaps, "\n")
        for idx=#excludemaps,1,-1 do
            local line = excludemaps[idx];
            if string.len(line) == 0 or string.StartWith(line, ";") then
                table.remove(excludemaps, idx);
            end
        end
    end
else
    excludemaps = {}
end

local cooldownnum
function CoolDownDoStuff()
    cooldownnum = MapVote.Config.MapsBeforeRevote or 3

    while table.Count(recentmaps) > cooldownnum do
        table.remove(recentmaps)
    end

    local curmap = game.GetMap():lower()..".bsp"

    if not table.HasValue(recentmaps, curmap) then
        table.insert(recentmaps, 1, curmap)
    end

    file.Write("mapvote/recentmaps.txt", util.TableToJSON(recentmaps))
end

local function GetRandomFilteredMap(maps, search_prefixes, allow_current, current_map)
    for _, map in RandomPairs(maps) do
        for _, search_prefix in pairs(search_prefixes) do
            -- Exclude current map if allow_current is disabled
            if not allow_current and map == current_map then continue end

            if string.find(map, search_prefix) then
                return map:sub(1, -5)
            end
        end
    end

    return nil
end

function MapVote.Start(length, current, limit, prefix, callback)
    current = current or MapVote.Config.AllowCurrentMap or false
    length = length or MapVote.Config.TimeLimit or 28
    limit = limit or MapVote.Config.MapLimit or 24
    local cooldown = MapVote.Config.EnableCooldown or MapVote.Config.EnableCooldown == nil and true
    prefix = prefix or MapVote.Config.MapPrefixes or {}
    local allowRandom = MapVote.Config.AllowRandom or false

    if prefix and type(prefix) ~= "table" then
        prefix = {prefix}
    end

    local use_gamemode_maps = false
    if next(prefix) == nil then
        local info = file.Read(GAMEMODE.Folder.."/"..GAMEMODE.FolderName..".txt", "GAME")

        if info then
            local keys = util.KeyValuesToTable(info)
            local gamemode_maps = keys.maps
            if gamemode_maps then
                prefix = gamemode_maps
                use_gamemode_maps = true
            end
        end
    end

    local maps = file.Find("maps/*.bsp", "GAME")
    local vote_maps = {}
    local map_count = 0
    local search_prefixes = {}

    if allowRandom then
        table.insert(vote_maps, MapVote.RandomPlaceholder)
        map_count = map_count + 1
    end

    if use_gamemode_maps then
        local map_prefixes = string.Split(prefix, "|")
        for _, map_prefix in pairs(map_prefixes) do
            table.insert(search_prefixes, map_prefix)
        end
    else
        for _, v in pairs(prefix) do
            table.insert(search_prefixes, "^"..v)
        end
    end

    if MapVote.Config.AdditionalMaps ~= nil then
        for k, v in pairs(MapVote.Config.AdditionalMaps) do
            if k == GAMEMODE_NAME then
                local add_prefixes = string.Split(v, "|")
                for i, map_prefix in pairs(add_prefixes) do
                    table.insert(search_prefixes, "^"..map_prefix)
                end
                break
            end
        end
    end

    local playercount = player.GetCount();
    if MapVote.Config.MapConfigs ~= nil then
        for k, _ in pairs(MapVote.Config.MapConfigs) do
            if table.HasValue(maps, k..".bsp") then
                for _k=#maps,1,-1 do
                    local _v = maps[_k];
                    if _v == k..".bsp" then
                        if (MapVote.Config.MapConfigs[k].Min and playercount < MapVote.Config.MapConfigs[k].Min) or (MapVote.Config.MapConfigs[k].Max and playercount > MapVote.Config.MapConfigs[k].Max) then
                            table.remove(maps, _k);
                            break
                        end
                    end
                end
            end
        end
    end

    -- Remove the maps that are explicitly excluded
    for _, v in pairs(excludemaps) do
        local excludemap = string.Trim(v, "\r")
        if table.HasValue(maps, excludemap..".bsp") then
            for _k=#maps,1,-1 do
                local _v = maps[_k];
                if _v == excludemap..".bsp" then
                    table.remove(maps, _k);
                    break
                end
            end
        end
    end

    local currentMap = game.GetMap():lower()
    -- Gather the maps to show from the list of available maps
    for _, map in RandomPairs(maps) do
        -- If we allow the current map to show or this isn't the current map
        if (current or currentMap..".bsp" ~= map) and
        -- and we aren't excluding recent maps or this isn't a recent map, add it
            (not cooldown or not table.HasValue(recentmaps, map)) then
            for _, search_prefix in pairs(search_prefixes) do
                if string.find(map, search_prefix) then
                    table.insert(vote_maps, map:sub(1, -5))
                    map_count = map_count + 1
                    break
                end
            end

            if limit and map_count >= limit then break end
        end
    end

    if map_count > 0 then
        net.Start("RAM_MapVoteStart")
        net.WriteUInt(map_count, 32)

        for _, map_name in pairs(vote_maps) do
            net.WriteString(map_name)
        end

        net.WriteUInt(length, 32)
        net.Broadcast()

        MapVote.Allow = true
        MapVote.CurrentMaps = vote_maps
        MapVote.Votes = {}

        timer.Create("RAM_MapVote", length, 1, function()
            MapVote.Allow = false
            local map_results = {}

            for k, v in pairs(MapVote.Votes) do
                if not map_results[v] then
                    map_results[v] = 0
                end

                for _, v2 in pairs(player.GetAll()) do
                    if v2:SteamID() == k then
                        if MapVote.HasExtraVotePower(v2) then
                            map_results[v] = map_results[v] + 2
                        else
                            map_results[v] = map_results[v] + 1
                        end
                    end
                end
            end

            CoolDownDoStuff()

            local winner = table.GetWinningKey(map_results) or 1
            net.Start("RAM_MapVoteUpdate")
            net.WriteUInt(MapVote.UPDATE_WIN, 3)
            net.WriteUInt(winner, 32)
            net.Broadcast()

            local map = MapVote.CurrentMaps[winner]
            if map == MapVote.RandomPlaceholder then
                map = GetRandomFilteredMap(maps, search_prefixes, current, currentMap)
                if map == nil then
                    ErrorNoHalt("Could not find random map with the configured prefixes!\n")
                    return
                end
                print("Selecting random map...", map)
            end

            timer.Simple(4, function()
                if hook.Run("MapVoteChange", map) ~= false then
                    if callback then
                        callback(map)
                    else
                        RunConsoleCommand("changelevel", map)
                    end
                end
            end)
        end)
    end
end

hook.Add("Shutdown", "RemoveRecentMaps", function()
    if file.Exists("mapvote/recentmaps.txt", "DATA") then
        file.Delete("mapvote/recentmaps.txt")
    end
end)

function MapVote.Cancel()
    if MapVote.Allow then
        MapVote.Allow = false

        net.Start("RAM_MapVoteCancel")
        net.Broadcast()

        timer.Remove("RAM_MapVote")
    end
end

local chatCommands = {
    "!vote",
    "/vote",
    "vote",
    "!mapvote",
    "/mapvote",
    "mapvote"
}
hook.Add("PlayerSay", "Map Vote Commands", function(ply, text)
    -- Don't use "!" for admin because they are already used elsewhere
    if string.StartWith(text, "!") and ply:IsAdmin() then return end

    if GAMEMODE_NAME ~= "stopitslender" then
        if table.HasValue(chatCommands, string.lower(text)) then
            net.Start("RAM_MapVoteOpen")
            net.Send(ply)
            return ""
        end
    end
end)