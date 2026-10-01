-- factorio-map: native-resolution per-surface map rendered as a GRID of
-- screenshots (each capped at CELL px) that vips stitches into one big image.
-- factorio buffers every queued screenshot in RAM until shutdown, so the render
-- is split into BATCHES (NBATCH invocations): each run only shoots the cells with
-- global-index % NBATCH == BATCH, bounding memory. FMAP_PLAN=1 renders nothing,
-- it just enumerates the grid + writes station metadata so the driver can size
-- the batches. MAP_ZOOM / CELL_PX / FMAP_* are substituted at run time.
local ZOOM = tonumber("__MAP_ZOOM__") or 1.0        -- 1.0 = 32 px/tile (native)
local CELL = tonumber("__CELL_PX__") or 16384         -- max px per screenshot
local PLAN = ("__FMAP_PLAN__" == "1")
local BATCH = tonumber("__FMAP_BATCH__") or 0
local NBATCH = tonumber("__FMAP_NBATCH__") or 1
local PAD = 32
local done = false

script.on_nth_tick(60, function()
  if done then return end
  done = true
  local ppt = 32 * ZOOM
  local cell_tiles = math.floor(CELL / ppt)

  local names = {}
  for _, s in pairs(game.surfaces) do names[#names + 1] = s.name end
  table.sort(names)                                    -- stable global cell order

  local gidx = 0
  for _, sname in ipairs(names) do
    local surface = game.surfaces[sname]
    local ents = surface.find_entities_filtered{force = "player"}
    if #ents == 0 then
      if PLAN then log("FMAP_SKIP surface=" .. sname) end
    else
      -- wipe the pollution haze so screenshots show clean ground (this is a
      -- throwaway copy of the save, the live game is untouched)
      pcall(function() surface.clear_pollution() end)
      local x1, y1, x2, y2 = math.huge, math.huge, -math.huge, -math.huge
      for _, e in pairs(ents) do
        local p = e.position
        if p.x < x1 then x1 = p.x end
        if p.y < y1 then y1 = p.y end
        if p.x > x2 then x2 = p.x end
        if p.y > y2 then y2 = p.y end
      end
      x1 = x1 - PAD; y1 = y1 - PAD; x2 = x2 + PAD; y2 = y2 + PAD
      local nx = math.max(1, math.ceil((x2 - x1) / cell_tiles))
      local ny = math.max(1, math.ceil((y2 - y1) / cell_tiles))
      local gx0 = (x1 + x2) / 2 - nx * cell_tiles / 2
      local gy0 = (y1 + y2) / 2 - ny * cell_tiles / 2
      local shots = 0
      for j = 0, ny - 1 do
        for i = 0, nx - 1 do
          local left = gx0 + i * cell_tiles
          local top = gy0 + j * cell_tiles
          local gen = false
          local cx1 = math.floor(left / 32)
          local cx2 = math.floor((left + cell_tiles - 1) / 32)
          local cy1 = math.floor(top / 32)
          local cy2 = math.floor((top + cell_tiles - 1) / 32)
          local sx = math.max(1, math.floor((cx2 - cx1) / 6))
          local sy = math.max(1, math.floor((cy2 - cy1) / 6))
          for ccx = cx1, cx2, sx do
            for ccy = cy1, cy2, sy do
              if surface.is_chunk_generated({x = ccx, y = ccy}) then gen = true; break end
            end
            if gen then break end
          end
          if gen then
            if (not PLAN) and (gidx % NBATCH == BATCH) then
              game.take_screenshot{surface = surface,
                position = {left + cell_tiles / 2, top + cell_tiles / 2},
                resolution = {CELL, CELL}, zoom = ZOOM,
                path = "map/" .. sname .. "/c_" .. j .. "_" .. i .. ".png",
                show_entity_info = true, daytime = 0, water_tick = 0, anti_alias = false}
            end
            gidx = gidx + 1
            shots = shots + 1
          end
        end
      end
      if PLAN then
        local stops = surface.find_entities_filtered{type = "train-stop"}
        local stations = {}
        for _, st in pairs(stops) do
          local c = st.color
          stations[#stations + 1] = {name = st.backer_name or "", x = st.position.x,
            y = st.position.y, color = c and {r = c.r, g = c.g, b = c.b} or nil}
        end
        helpers.write_file("map/" .. sname .. ".stations.json",
          helpers.table_to_json({w = nx * CELL, h = ny * CELL, gx0 = gx0, gy0 = gy0,
            ppt = ppt, nx = nx, ny = ny, cell = CELL, stations = stations}), false)

        -- resource patches: bucket resources per chunk (sum remaining amount +
        -- well count), merge adjacent same-type chunks (union-find) into patches
        local res = surface.find_entities_filtered{type = "resource"}
        local inf, buckets = {}, {}
        for _, r in pairs(res) do
          local nm = r.name
          if inf[nm] == nil then inf[nm] = r.prototype.infinite_resource end
          local bx = math.floor(r.position.x / 32)
          local by = math.floor(r.position.y / 32)
          local key = bx .. ":" .. by .. ":" .. nm
          local b = buckets[key]
          if not b then b = {nm = nm, bx = bx, by = by, amount = 0, count = 0}; buckets[key] = b end
          b.amount = b.amount + r.amount
          b.count = b.count + 1
        end
        local parent = {}
        local function find(k)
          while parent[k] ~= k do parent[k] = parent[parent[k]]; k = parent[k] end
          return k
        end
        for key in pairs(buckets) do parent[key] = key end
        for key, b in pairs(buckets) do
          for _, d in ipairs({{1, 0}, {0, 1}, {1, 1}, {1, -1}}) do
            local nkey = (b.bx + d[1]) .. ":" .. (b.by + d[2]) .. ":" .. b.nm
            if buckets[nkey] then
              local ra, rb = find(key), find(nkey)
              if ra ~= rb then parent[ra] = rb end
            end
          end
        end
        local patches = {}
        for key, b in pairs(buckets) do
          local root = find(key)
          local p = patches[root]
          if not p then p = {nm = b.nm, amount = 0, count = 0, sx = 0, sy = 0}; patches[root] = p end
          p.amount = p.amount + b.amount
          p.count = p.count + b.count
          p.sx = p.sx + (b.bx * 32 + 16) * b.amount
          p.sy = p.sy + (b.by * 32 + 16) * b.amount
        end
        local rlist = {}
        for _, p in pairs(patches) do
          local w = p.amount > 0 and p.amount or 1
          rlist[#rlist + 1] = {type = p.nm, amount = math.floor(p.amount), wells = p.count,
            x = math.floor(p.sx / w), y = math.floor(p.sy / w), infinite = inf[p.nm] or false}
        end
        helpers.write_file("map/" .. sname .. ".resources.json",
          helpers.table_to_json({patches = rlist}), false)

        -- rail network: flat [x0,y0,x1,y1,...] of every rail tile (drawn as a
        -- canvas highlight layer client-side). pcall per type so an unknown rail
        -- type (across versions/DLC) never breaks the whole plan pass.
        local rail_types = {"straight-rail", "half-diagonal-rail", "curved-rail-a",
          "curved-rail-b", "rail-ramp", "elevated-straight-rail", "elevated-half-diagonal-rail",
          "elevated-curved-rail-a", "elevated-curved-rail-b", "legacy-straight-rail",
          "legacy-curved-rail"}
        local rl = {}
        for _, t in ipairs(rail_types) do
          local ok, ents = pcall(function() return surface.find_entities_filtered{type = t} end)
          if ok and ents then
            for _, e in pairs(ents) do
              rl[#rl + 1] = math.floor(e.position.x + 0.5)
              rl[#rl + 1] = math.floor(e.position.y + 0.5)
            end
          end
        end
        helpers.write_file("map/" .. sname .. ".rails.json",
          helpers.table_to_json({rails = rl}), false)

        log("FMAP_OK surface=" .. sname .. " grid=" .. nx .. "x" .. ny .. " shots=" .. shots
          .. " stations=" .. #stations .. " resources=" .. #rlist .. " rails=" .. math.floor(#rl / 2))
      end
    end
  end
  log("FMAP_DONE")
end)
