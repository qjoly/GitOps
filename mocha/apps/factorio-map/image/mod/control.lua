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
        log("FMAP_OK surface=" .. sname .. " grid=" .. nx .. "x" .. ny
          .. " shots=" .. shots .. " stations=" .. #stations)
      end
    end
  end
  log("FMAP_DONE")
end)
