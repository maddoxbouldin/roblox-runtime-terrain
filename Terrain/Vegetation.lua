local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)
local Noise = require(script.Parent.Noise)
local Runtime = require(script.Parent.Runtime)

local Vegetation = {}

local modelPools = {
	Rocks = Runtime.GetModels(Runtime.GetRequiredAssetFolder("Rocks")),
	Trees = Runtime.GetModels(Runtime.GetRequiredAssetFolder("Trees")),
	Vegetation = Runtime.GetModels(Runtime.GetRequiredAssetFolder("Vegetation")),
}

Vegetation.BIOME_SCALE = Config.Vegetation.BiomeScale
Vegetation.BIOME_WEIGHTS = Config.Vegetation.BiomeWeights

local vegetationState = {}

local function getBiomeAt(x, z, biomeScale, biomeWeights)
	local forestWeight = biomeWeights.Forest or 1
	local plainsWeight = biomeWeights.Plains or 1
	local totalWeight = forestWeight + plainsWeight
	if totalWeight <= 0 then
		return "Forest"
	end

	local sample = Noise:noise3D(x, 0, z, biomeScale)
	local normalized = (sample + 1) / 2
	if normalized < forestWeight / totalWeight then
		return "Forest"
	end
	return "Plains"
end

local function getDirection(vector)
	if vector.Y == 0 then
		return Vector3.zero
	elseif vector.Y > 0 then
		return -vector
	end
	return vector
end

local function computeLowestLocalVector(cframe, size)
	return getDirection(cframe.RightVector) * (size.X / 2)
		+ getDirection(cframe.UpVector) * (size.Y / 2)
		+ getDirection(cframe.LookVector) * (size.Z / 2)
end

local function getSurfaceY(x, z)
	local terrainConfig = Config.Terrain
	local sample = Noise:fBm2D(
		x,
		z,
		terrainConfig.Octaves,
		terrainConfig.Persistence,
		terrainConfig.Lacunarity,
		terrainConfig.NoiseScale
	)
	return terrainConfig.BaseHeight + sample * terrainConfig.HeightAmplitude
end

local function isCaveAt(x, y, z)
	if y <= Config.Caves.MinHeight then
		return false
	end
	return Noise:noise3D(x, y, z, Config.Caves.Scale) > Config.Caves.Threshold
end

local function applySavedState(chunkName, vegetationName, model)
	local chunkState = vegetationState[chunkName]
	local savedState = chunkState and chunkState[vegetationName]
	if savedState and savedState.removed then
		model:Destroy()
		return true
	end
	return false
end

local function makeVegetationName(cx, cz, ix, iz)
	return string.format("Veg_C%d_Z%d_X%d_Z%d", cx, cz, ix, iz)
end

local function columnHasWater(x, z, cellSize)
	local surfaceY = getSurfaceY(x, z)
	local half = cellSize / 2
	local region = Region3.new(
		Vector3.new(x - half, surfaceY - cellSize * 3, z - half),
		Vector3.new(x + half, surfaceY + cellSize, z + half)
	):ExpandToGrid(cellSize)

	local materials = Workspace.Terrain:ReadVoxels(region, cellSize)
	for ix = 1, #materials do
		for iy = 1, #materials[1] do
			for iz = 1, #materials[1][1] do
				if materials[ix][iy][iz] == Enum.Material.Water then
					return true
				end
			end
		end
	end
	return false
end

function Vegetation.ComputeChunk(cx, cz, chunkSize, hints)
	local cellSize = Config.Terrain.CellSize
	local cells = chunkSize / cellSize
	local baseX = cx * chunkSize
	local baseZ = cz * chunkSize
	local half = cellSize / 2
	local biomeScale = hints and hints.biomeScale or Vegetation.BIOME_SCALE
	local biomeWeights = hints and hints.biomeWeights or Vegetation.BIOME_WEIGHTS
	local placements = {}

	for ix = 1, cells do
		for iz = 1, cells do
			-- skip cells occupied by spring water
			if hints and hints.waterMask and hints.waterMask[ix] and hints.waterMask[ix][iz] then
				continue
			end

			local x = baseX + (ix - 1) * cellSize + half
			local z = baseZ + (iz - 1) * cellSize + half
			local biome = getBiomeAt(x, z, biomeScale, biomeWeights)
			local chances = Config.Vegetation.SpawnChances[biome] or Config.Vegetation.SpawnChances.Forest
			local rockChance = chances.Rock
			local treeChance = chances.Tree
			local vegetationChance = chances.Vegetation
			local totalChance = rockChance + treeChance + vegetationChance
			if totalChance <= 0 then
				continue
			end

			-- use a stable seed for each cell
			local seed = Noise.seed + cx * 1013 + cz * 9176 + ix * 37 + iz
			local random = Random.new(seed)
			local roll = random:NextNumber()
			if roll >= totalChance then
				continue
			end

			local poolName
			if roll < rockChance then
				poolName = "Rocks"
			elseif roll < rockChance + treeChance then
				poolName = "Trees"
			else
				poolName = "Vegetation"
			end

			local pool = modelPools[poolName]
			if #pool == 0 then
				continue
			end

			local surfaceY = getSurfaceY(x, z)
			if hints and hints.heightMap and hints.heightMap[ix] then
				surfaceY = hints.heightMap[ix][iz] or surfaceY
			end

			-- keep models away from cave openings
			local avoidPlacement = false
			local corners = {
				{ x + half, surfaceY, z + half },
				{ x - half, surfaceY, z + half },
				{ x + half, surfaceY, z - half },
				{ x - half, surfaceY, z - half },
			}
			for _, corner in ipairs(corners) do
				if isCaveAt(corner[1], corner[2] - cellSize, corner[3]) then
					avoidPlacement = true
					break
				end
			end
			if avoidPlacement then
				continue
			end

			table.insert(placements, {
				x = x,
				z = z,
				surfaceY = surfaceY,
				yawDegrees = random:NextNumber(0, 360),
				poolName = poolName,
				modelIndex = random:NextInteger(1, #pool),
				name = makeVegetationName(cx, cz, ix, iz),
				biome = biome,
			})
		end
	end

	return {
		cx = cx,
		cz = cz,
		cellSize = cellSize,
		placements = placements,
	}
end

function Vegetation.ApplyChunkPlan(plan, parentFolder)
	local buckets = {
		Rocks = Runtime.EnsureFolder(parentFolder, "Rocks"),
		Trees = Runtime.EnsureFolder(parentFolder, "Trees"),
		Vegetation = Runtime.EnsureFolder(parentFolder, "Vegetation"),
	}
	local chunkName = string.format("Chunk_%d_%d", plan.cx, plan.cz)

	for _, placement in ipairs(plan.placements) do
		local source = modelPools[placement.poolName][placement.modelIndex]
		if not source then
			continue
		end

		local model = source:Clone()
		-- confirm the final terrain column is dry
		if columnHasWater(placement.x, placement.z, plan.cellSize) then
			model:Destroy()
			continue
		end

		model.Name = placement.name
		if applySavedState(chunkName, placement.name, model) then
			continue
		end

		local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if not primary then
			model:Destroy()
			continue
		end
		model.PrimaryPart = primary

		local rotation = CFrame.Angles(0, math.rad(placement.yawDegrees), 0)
		local lowestVector = computeLowestLocalVector(rotation, primary.Size)
		local pivotY = placement.surfaceY - lowestVector.Y
		local offset = Vector3.zero
		local offsetValue = model:FindFirstChild("Offset")
		if offsetValue and offsetValue:IsA("Vector3Value") then
			offset = offsetValue.Value
		end

		model:PivotTo(
			CFrame.new(
				placement.x - offset.X,
				pivotY - offset.Y,
				placement.z - offset.Z
			) * rotation
		)
		model.Parent = buckets[placement.poolName]
	end
end

function Vegetation:PopulateChunk(cx, cz, chunkSize, parentFolder, hints)
	local plan = Vegetation.ComputeChunk(cx, cz, chunkSize, hints)
	Vegetation.ApplyChunkPlan(plan, parentFolder)
end

function Vegetation:RemoveVegetation(chunkName, vegetationName)
	vegetationState[chunkName] = vegetationState[chunkName] or {}
	vegetationState[chunkName][vegetationName] = { removed = true }
end

return Vegetation

