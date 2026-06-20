require("scripts.rail-util")


---Check if a train is not stuck in a non-cs2 station, such as a depot stacker.
---This is called by CS2 via the busy_plugins mechanism.
---@param vehicle_id int64 The CS2 vehicle ID (unused).
---@param lua_train LuaTrain? The train to check.
---@return boolean is_unavailable `true` if this train cannot directly reach a CS2 station without going through another station.
local function is_train_unavailable(vehicle_id, lua_train)
	if not lua_train then return false end

	local re = lua_train.get_rail_end(FRONT)
	re.move_to_segment_end()

	-- Check current segment, to see if the train can be rerouted right now, before entering a depot stacker section
	local k = key(re)
	if storage.stacker_viable_segments[k] or storage.stacker_new_viable_segments[k] then
		return false
	end

	-- Check furthest reserved segment, to see if the train has reserved a path to leave the depot stacker section
	if lua_train.speed == 0 then
		return true
	end
	re = get_train_furthest_reserved_re(re, lua_train.path)

	k = key(re)
	local can_reach = storage.stacker_viable_segments[k] or storage.stacker_new_viable_segments[k] or false
	return not can_reach
end

-- Expose via remote interface for CS2's busy_plugins system
remote.add_interface("cybersyn2-stacker-depots", {
	is_train_unavailable = is_train_unavailable,
})
