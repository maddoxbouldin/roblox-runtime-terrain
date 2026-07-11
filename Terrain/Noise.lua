local Config = require(script.Parent.Config)

local Noise = {}

local resolvedSeed = script.Parent:GetAttribute("ResolvedSeed")
if typeof(resolvedSeed) ~= "number" then
	resolvedSeed = Config.Seed ~= 0 and Config.Seed or Config.RandomSeedMin
end
Noise.seed = resolvedSeed

-- layer two-dimensional noise over the xz plane
function Noise:fBm2D(x, z, octaves, persistence, lacunarity, scale)
	local value = 0
	local amplitude = 1
	local frequency = 1

	for _ = 1, octaves do
		value += math.noise(self.seed, x * frequency / scale, z * frequency / scale) * amplitude
		amplitude *= persistence
		frequency *= lacunarity
	end

	return value
end

function Noise:noise3D(x, y, z, scale)
	return math.noise(x / scale, y / scale, (z + self.seed) / scale)
end

return Noise
