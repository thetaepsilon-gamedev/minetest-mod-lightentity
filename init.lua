local libmthelpers = modns.get("com.github.thetaepsilon.minetest.libmthelpers")
local center = libmthelpers.playerpos.center_on_node

local modname = minetest.get_current_modname()
local name = modname..":light"
local source_prefix = modname..":source_"

-- for the record, I can't texture for feck all
local suntex = "lightentity_indicator.png"
local nodraw = "lightentity_nodraw.png"

local min = 1
local max = minetest.LIGHT_MAX

-- FIXME: make these configurable
local debugmode = true
local debug_nodepos = false

local compare_pos = function(a, b)
	return (a.x == b.x) and (a.y == b.y) and (a.z == b.z)
end

local warning = function(msg)
	minetest.log("warning", "[lightentity] "..msg)
end





-- light entity data, logic and definitions follow.
local k_lightlevel = "lightlevel"
local k_offset = "offset"

-- get the position at which the light node should be, given the entity position.
-- allow specifying an offset as specifying an attach offset to some entities
-- (most noticeably players as of 0.4.10) does not work correctly.
local getpos = function(self)
	return center(vector.add(self.object:get_pos(), self.data[k_offset]))
end

-- validate coordinate table passed in from staticdata.
-- returns either the passed value or an identity offset so the code has something to work with.
local validate_offset = function(c)
	local fname = "validate_offset() "
	local n = function(v) return type(v) == "number" end
	local result = {x=0,y=0,z=0}

	local t = type(c)
	if (t ~= "table") then
		warning(fname.."offset expected to be a vector table, got "..t)
	else
		if n(c.x) and n(c.y) and n(c.z) then
			result = c
		else
			warning(fname.."one or more components of xyz vector missing")
		end
	end

	return result
end

-- assign default values if they are missing so we don't get async callbacks blowing up the server.
local default_if_nil = function(tbl, key, default, warnmode)
	if tbl[key] == nil then
		tbl[key] = default
		if warnmode then
			warning("lightentity:light missing key "..key)
		end
	end
end

local issourcenode = function(pos)
	local node = minetest.get_node(pos)
	return (string.find(node.name, source_prefix) ~= nil)
end
-- it's a shame one can't cause a local "lighting glitch" for arbitary nodes with paramtype=light.
-- we have to employ a light source node and be careful about overwriting other nodes.
local islightablenode = function(pos)
	return (minetest.get_node(pos).name == "air")
end
local mklight = function(pos, self)
	local level = self.data[k_lightlevel]
	minetest.set_node(pos, {name=source_prefix..level})
end

local on_step = function(self, dtime)
	local cpos = getpos(self)
	local oldpos = self.lastpos
	self.lastpos = cpos
	-- place a new light source if the target node is different from the last one,
	-- and clear up the old one.
	-- this creates the impression that the light source moves to follow the entity.
	if not compare_pos(oldpos, cpos) then
		if islightablenode(cpos) then
			mklight(cpos, self)
		end
		-- only remove the node in the old position if it's one of ours.
		-- there's not much that can be done if it gets moved by mesecons piston say;
		-- it could have ended up anywhere, so just leave it if so.
		if issourcenode(oldpos) then
			minetest.set_node(oldpos, {name="air"})
		end
	end
end

-- when de-serialising, check that the light level is set to something sane.
-- if not, coerce the light level to avoid spewing error messages and/or unknown nodes
local setupwarning = function(msg) warning(name.." on_activate() "..msg) end
local coercewarning = function(value, min, max)
	setupwarning("light level "..value.." outside of range "..min.."-"..max..", coercing")
end
local check_light_limits = function(tbl)
	local light = tbl[k_lightlevel]
	if light < min then
		coercewarning()
		light = min
	elseif light > max then
		coercewarning()
		light = max
	end
	tbl[k_lightlevel] = light
end

local lightentity_defaults = function(tbl, warnmode)
	default_if_nil(tbl, k_lightlevel, minetest.LIGHT_MAX, warnmode)
	check_light_limits(tbl)
	tbl[k_offset] = validate_offset(tbl[k_offset])
end

local init = function(self, staticdata, dtime_s)
	local result = {}
	local warnmode = false
	if staticdata ~= "" then
		-- expect valid data to be present in the staticdata
		warnmode = true
		result = minetest.parse_json(staticdata)
	end
	-- repair any missing keys so stuff doesn't blow up
	if result == nil then result = {} end
	lightentity_defaults(result, warnmode)

	self.data = result
	self.lastpos = getpos(self)
end
local on_save = function(self) return minetest.write_json(self.data) end

local sprite
if debugmode then
	sprite = suntex
else
	sprite = nodraw
end
local nametag
if debugmode then nametag = name end

minetest.register_entity(name, {
	collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
	backface_culling = true,
	nametag = nametag,
	visual = "sprite",
	textures = { sprite },
	on_step = on_step,
	on_activate = init,
	get_staticdata = on_save,
})





-- light source nodes that the entity produces and cleans up after it.
-- also make a perfectly useable standalone invisible light.
print("[lightentity] generating light level nodes for "..min.." to "..max)
for light_level = min, max, 1 do
	name = source_prefix..tostring(light_level)
	local def = {}
	def.paramtype = "light"
	def.sunlight_propogates = true
	def.walkable = false
	def.wield_image = suntex

	-- debug node position makes the source nodes selectable,
	-- and gives them a texture of a little sun.
	-- debug mode might be useful for fixing up maps with lots of these stuck around.
	if debug_nodepos then
		def.drawtype = "glasslike"
		def.tiles = { suntex }
	else
		def.drawtype = "airlike"
	end
	def.pointable = debug_nodepos

	def.diggable = false
	def.buildable_to = true
	def.floodable = true
	def.light_source = light_level
	def.drop = ""

	minetest.register_node(name, def)
end
