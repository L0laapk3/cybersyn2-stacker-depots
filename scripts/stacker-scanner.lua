require("scripts.rail-util")

local front = {} -- Not in storage: RailEnd userdata can't be serialized
local debug_render = false
local rescan_all -- forward declaration

local function add_to_front(re) -- assumes re.valid
	local re2 = re.make_copy()
	re.move_to_segment_end()
	re2.flip_direction()
	re2.move_to_segment_end()
	local k = key(re)
	local k2 = key(re2)
	if not storage.stacker_new_viable_segments[k2] then -- we are iterating in reverse, so flip the key in the forwards direction again before storing
		storage.stacker_new_viable_segments[k2] = true
		front[k] = re
		if debug_render then
			local rails = re.rail.get_rail_segment_rails(re.direction)
			for _, rail in pairs(rails) do
				rendering.draw_line({
					color = { 0, 1, 0 },
					width = 3,
					from = rail.get_rail_end(FRONT).location.position,
					to = rail.get_rail_end(BACK).location.position,
					surface = rail.surface,
					time_to_live = 60,
				})
			end
		end
	end
end


local function taint_block(prev_re) -- assumes prev_re is at the beginning of a segment
	prev_re.move_to_segment_end()
	if debug_render then
		local rails = prev_re.rail.get_rail_segment_rails(prev_re.direction)
		for _, rail in pairs(rails) do
			rendering.draw_line({
				color = { 0, 1, 1 },
				width = 3,
				from = rail.get_rail_end(FRONT).location.position,
				to = rail.get_rail_end(BACK).location.position,
				surface = rail.surface,
				time_to_live = 60,
			})
		end
	end
	for _, dir in pairs(CONNECTION_DIRECTIONS) do
		local re = prev_re.make_copy()
		if re.move_forward(dir) then
			local forward_signal = get_signals_from_last_rail(re, prev_re, true)  -- forward = towards station
			local reverse_signal = get_signals_from_last_rail(re, prev_re, false) -- reverse = how we're walking
			if forward_signal and forward_signal.type == "rail-signal" then
				goto continue_dir
			end
			if reverse_signal and not forward_signal then
				goto continue_dir
			end
			local re2 = re.make_copy()
			re2.flip_direction()
			storage.stacker_new_viable_segments[key(re2)] = true
			taint_block(re)
		end
	::continue_dir::
	end

end

local processed = 0
local function scan_tick()
	local budget = settings.global["cybersyn2-stacker-depots-scan-budget"].value
	while budget > 0 and next(front) do
		budget = budget - 1
		processed = processed + 1
		local k, prev_re = next(front)
		front[k] = nil
		if prev_re.valid then
			for _, dir in pairs(CONNECTION_DIRECTIONS) do
				local re = prev_re.make_copy()
				if re.move_forward(dir) then
					local stop = re.rail.get_rail_segment_stop(flip(re.direction))
					if stop then -- always end on a station: if it is depot should end for sure, if it is not depot it was already scanned anyway. (mark the station sections themselves as viable)
						local re2 = re.make_copy()
						re2.flip_direction()
						if not storage.stacker_new_viable_segments[key(re2)] then
							storage.stacker_new_viable_segments[key(re2)] = true
							taint_block(re)
						end
					else
						local forward_signal = get_signals_from_last_rail(re, prev_re, true)  -- forward = towards station
						local reverse_signal = get_signals_from_last_rail(re, prev_re, false) -- reverse = how we're walking
						if forward_signal or not reverse_signal then -- dont travel away from back of station on one way signal
							add_to_front(re)
						end
					end
				end
			end
		end
	end
	if not next(front) then
		storage.stacker_viable_segments = storage.stacker_new_viable_segments
		storage.stacker_new_viable_segments = {}
		-- if debug_render then
			-- game.print("Stacker viable segments: " .. table_size(storage.stacker_viable_segments) .. " (processed " .. processed .. ")")
		-- end

		-- local count = 0
		-- for _, _ in pairs(storage.stacker_viable_segments) do count = count + 1 end
		-- game.print("Stacker viable segments: " .. count .. " (processed " .. processed .. ")")

		-- repeat forever...
		rescan_all()
	end

	-- for _, train in pairs(game.train_manager.get_trains({})) do
	-- 	local re = get_train_furthest_reserved_re(train)
	-- 	rendering.draw_line({
	-- 		color = { 1, 1, 1 },
	-- 		width = 3,
	-- 		from = train.get_rail_end(FRONT).location.position,
	-- 		to = re.location.position,
	-- 		surface = re.rail.surface,
	-- 		time_to_live = 1,
	-- 	})
	-- end
end



function rescan_all()
	storage.stacker_new_viable_segments = {}
	processed = 0
	-- Seed the taint from every cs2 train stop in the world. A station
	-- sits at one end of its rail segment; the segment is reachable to that
	-- station, so it is tainted, and we begin walking upstream from it.

	-- Get all train stops via Factorio API, then filter to CS2 stations
	local all_stops = game.train_manager.get_train_stops({})
	local unit_numbers = {}
	for _, stop in pairs(all_stops) do
		unit_numbers[#unit_numbers + 1] = stop.unit_number
	end

	-- Query CS2 to find which are CS2 stations (returns nil for non-CS2 stops)
	local result = remote.call("cybersyn2", "query", { type = "stops", all = true })
	local cs2_stops = result and result.data or {}

	for _, stop in pairs(cs2_stops) do
		if stop then -- CS2 returns nil for non-CS2 stops in the list
			local stop_entity = stop.entity
			if stop_entity and stop_entity.valid then
				local rail = stop_entity.connected_rail
				if rail then
					local re = rail.get_rail_end(flip(stop_entity.connected_rail_direction))
					add_to_front(re)
				end
			end
		end
	end
end



-- on placement of rails
-- on adding a travel direction to a segment by adding/removing a signal
-- on adding a cs2 station
local function added_rails(rails)
	-- TODO: incremental update: if placed rail attaches to tainted area, add it to the front
end

-- on destroy of rails
-- on removing a travel direction from a segment by adding/removing a signal
-- on removing a cs2 station
local function removed_rails(rails)
	-- TODO: incremental update: untaint and run a pathfinder on every intersection until a cs2 station can be reached
	rescan_all()
end



local function init_storage()
	storage.stacker_viable_segments = storage.stacker_viable_segments or {}
	storage.stacker_new_viable_segments = storage.stacker_new_viable_segments or {}
end

script.on_init(function()
	init_storage()
	rescan_all()
end)

script.on_configuration_changed(function()
	init_storage()
	rescan_all()
end)
script.on_event(defines.events.on_tick, scan_tick)

commands.add_command("cs2-stacker-debug", nil, function()
	debug_render = not debug_render
	game.print("Stacker debug render: " .. (debug_render and "ON" or "OFF"))
end)
