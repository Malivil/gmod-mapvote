util.AddNetworkString("RAM_MapVoteStart")
util.AddNetworkString("RAM_MapVoteUpdate")
util.AddNetworkString("RAM_MapVoteCancel")
util.AddNetworkString("RTV_Delay")

MapVote.Continued = false

net.Receive("RAM_MapVoteUpdate", function(len, ply)
    if(MapVote.Allow) then
        if(IsValid(ply)) then
            local update_type = net.ReadUInt(3)

            if(update_type == MapVote.UPDATE_VOTE) then
                local map_id = net.ReadUInt(32)

                if(MapVote.CurrentMaps[map_id]) then
                    MapVote.Votes[ply:SteamID()] = map_id

                    net.Start("RAM_MapVoteUpdate")
                    net.WriteUInt(MapVote.UPDATE_VOTE, 3)
                    net.WriteEntity(ply)
                    net.WriteUInt(map_id, 32)
                    net.Broadcast()
                end
            end
        end
    end
end)

if file.Exists( "mapvote/recentmaps.txt", "DATA" ) then
    recentmaps = util.JSONToTable(file.Read("mapvote/recentmaps.txt", "DATA"))
else
    recentmaps = {}
end

if file.Exists( "mapvote/config.txt", "DATA" ) then
    MapVote.Config = util.JSONToTable(file.Read("mapvote/config.txt", "DATA"))
else
    MapVote.Config = {}
end

if file.Exists( "mapvote/votemaps.txt", "DATA" ) then
    excludemaps = file.Read("mapvote/votemaps.txt", "DATA")

    for idx, line in pairs(excludemaps) do
        if string.StartWith( line, ";" ) then
            table.remove(excludemaps, idx);
        end
    end
else
    excludemaps = {}
end

function CoolDownDoStuff()
    cooldownnum = MapVote.Config.MapsBeforeRevote or 3

    while table.getn(recentmaps) > cooldownnum do
        table.remove(recentmaps)
    end

    local curmap = game.GetMap():lower()..".bsp"

    if not table.HasValue(recentmaps, curmap) then
        table.insert(recentmaps, 1, curmap)
    end

    file.Write("mapvote/recentmaps.txt", util.TableToJSON(recentmaps))
end

function MapVote.Start(length, current, limit, prefix, callback)
    current = current or MapVote.Config.AllowCurrentMap or false
    length = length or MapVote.Config.TimeLimit or 28
    limit = limit or MapVote.Config.MapLimit or 24
    cooldown = MapVote.Config.EnableCooldown or MapVote.Config.EnableCooldown == nil and true
    prefix = prefix or MapVote.Config.MapPrefixes

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

    if use_gamemode_maps then
        local map_prefixes = string.Split(prefix, "|")
        for i, map_prefix in pairs(map_prefixes) do
            table.insert(search_prefixes, map_prefix)
        end
    else
        for k, v in pairs(prefix) do
            table.insert(search_prefixes, "^"..v)
        end
    end

    if MapVote.Config.AdditionalMaps != nil then
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
    if MapVote.Config.MapConfigs != nil then
        for k, v in pairs(MapVote.Config.MapConfigs) do
            if table.HasValue(maps, k..".bsp") then
                for _k, _v in pairs(maps) do
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

    if excludemaps != nil then
        for k, v in pairs(excludemaps) do
            if table.HasValue(maps, v..".bsp") then
                for _k, _v in pairs(maps) do
                    if _v == v..".bsp" then
                        table.remove(maps, _k);
                        break
                    end
                end
            end
        end
    end

    for k, map in RandomPairs(maps) do
        if(not current and game.GetMap():lower()..".bsp" == map) then continue end
        if(cooldown and table.HasValue(recentmaps, map)) then continue end

        for i, search_prefix in pairs(search_prefixes) do
            if string.find(map, search_prefix) then
                table.insert(vote_maps, map:sub(1, -5))
                map_count = map_count + 1
                break
            end
        end

        if limit and map_count >= limit then break end
    end

    if map_count > 0 then
        net.Start("RAM_MapVoteStart")
        net.WriteUInt(map_count, 32)

        for i, map_name in pairs(vote_maps) do
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
                if(not map_results[v]) then
                    map_results[v] = 0
                end

                for k2, v2 in pairs(player.GetAll()) do
                    if(v2:SteamID() == k) then
                        if(MapVote.HasExtraVotePower(v2)) then
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

            timer.Simple(4, function()
                if (hook.Run("MapVoteChange", map) != false) then
                    if (callback) then
                        callback(map)
                    else
                        RunConsoleCommand("changelevel", map)
                    end
                end
            end)
        end)
    end
end

hook.Add( "Shutdown", "RemoveRecentMaps", function()
        if file.Exists( "mapvote/recentmaps.txt", "DATA" ) then
            file.Delete( "mapvote/recentmaps.txt" )
        end
end )

function MapVote.Cancel()
    if MapVote.Allow then
        MapVote.Allow = false

        net.Start("RAM_MapVoteCancel")
        net.Broadcast()

        timer.Destroy("RAM_MapVote")
    end
end
