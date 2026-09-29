-- factorio-map: render one auto-framed full-map screenshot per surface, then quit.
-- RESOLUTION is substituted at container build/run time (see render.sh).
local RES = tonumber("__RESOLUTION__") or 8192
local PAD = 24
local done = false

script.on_nth_tick(60, function()
  if done then return end
  done = true
  for _, surface in pairs(game.surfaces) do
    local ents = surface.find_entities_filtered{force = "player"}
    if #ents == 0 then
      log("FMAP_SKIP surface=" .. surface.name)
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
      local cx = (x1 + x2) / 2
      local cy = (y1 + y2) / 2
      local span = math.max(x2 - x1, y2 - y1)
      local zoom = RES / (span * 32)
      if zoom > 1 then zoom = 1 end
      game.take_screenshot{
        surface = surface,
        position = {cx, cy},
        resolution = {RES, RES},
        zoom = zoom,
        path = "map/" .. surface.name .. ".png",
        show_entity_info = true,
        daytime = 0,
        water_tick = 0,
        anti_alias = true,
      }
      -- train-stop overlay data (name + position + colour), with the projection
      -- transform so the web frontend can place markers at image pixels.
      local stops = surface.find_entities_filtered{type = "train-stop"}
      local slist = {}
      for _, st in pairs(stops) do
        local c = st.color
        slist[#slist + 1] = {
          name = st.backer_name or "",
          x = st.position.x,
          y = st.position.y,
          color = c and {r = c.r, g = c.g, b = c.b} or nil,
        }
      end
      helpers.write_file("map/" .. surface.name .. ".stations.json",
        helpers.table_to_json({res = RES, cx = cx, cy = cy, zoom = zoom, stations = slist}), false)
      log("FMAP_OK surface=" .. surface.name .. " entities=" .. #ents
        .. " stations=" .. #slist .. " span=" .. math.floor(span)
        .. " zoom=" .. string.format("%.4f", zoom))
    end
  end
  game.set_wait_for_screenshots_to_finish()
  log("FMAP_DONE")
end)
