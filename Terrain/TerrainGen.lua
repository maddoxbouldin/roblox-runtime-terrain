local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)
local Noise = require(script.Parent.Noise)
local OreGenerator = require(script.Parent.OreGenerator)

local TerrainGen = {}

local function copyHeightMap(heightMap, cellsX, cellsZ)
	local copy = {}
	for ix = 1, cellsX do
		copy[ix] = {}
		for iz = 1, cellsZ do
			copy[ix][iz] = heightMap[ix][iz]
		end
	end
	return copy
end

local function buildSurfaceSolidity(heightMap, occupancy, cellsX, cellsY, cellsZ, cellSize)
	local surfaceSolid = {}
	for ix = 1, cellsX do
		surfaceSolid[ix] = {}
		for iz = 1, cellsZ do
			local height = heightMap[ix][iz]
			local fullVoxels = math.floor(height / cellSize)
			local remainder = (height % cellSize) / cellSize
			local topIndex = remainder > 0 and fullVoxels + 1 or fullVoxels
			local isSolid = topIndex >= 1 and topIndex <= cellsY
			if isSolid and occupancy then
				isSolid = occupancy[ix][topIndex][iz] >= 0.5
			end
			surfaceSolid[ix][iz] = isSolid
		end
	end
	return surfaceSolid
end

local function allocateVoxels(cellsX, cellsY, cellsZ)
	local materials = {}
	local occupancy = {}
	for ix = 1, cellsX do
		materials[ix] = {}
		occupancy[ix] = {}
		for iy = 1, cellsY do
			materials[ix][iy] = {}
			occupancy[ix][iy] = {}
			for iz = 1, cellsZ do
				materials[ix][iy][iz] = Enum.Material.Air
				occupancy[ix][iy][iz] = 0
			end
		end
	end
	return materials, occupancy
end

function TerrainGen.ComputeChunk(cx, cz, chunkSize, regionHeight)
	local terrainConfig = Config.Terrain
	local caveConfig = Config.Caves
	local springConfig = Config.Spring
	local cellSize = terrainConfig.CellSize
	assert(chunkSize % cellSize == 0, "chunk size must be a multiple of the terrain cell size")
	assert(regionHeight % cellSize == 0, "region height must be a multiple of the terrain cell size")

	local cellsX = chunkSize / cellSize
	local cellsY = regionHeight / cellSize
	local cellsZ = cellsX
	local worldX0 = cx * chunkSize
	local worldZ0 = cz * chunkSize
	local seed = Noise.seed + cx * 1013 + cz * 9176
	local random = Random.new(seed)

	-- build the base height map
	local heightMap = {}
	for ix = 1, cellsX do
		heightMap[ix] = {}
		local worldX = worldX0 + (ix - 1) * cellSize
		for iz = 1, cellsZ do
			local worldZ = worldZ0 + (iz - 1) * cellSize
			local sample = Noise:fBm2D(
				worldX,
				worldZ,
				terrainConfig.Octaves,
				terrainConfig.Persistence,
				terrainConfig.Lacunarity,
				terrainConfig.NoiseScale
			)
			heightMap[ix][iz] = terrainConfig.BaseHeight + sample * terrainConfig.HeightAmplitude
		end
	end

	-- smooth the height map once
	do
		local smoothed = {}
		for ix = 1, cellsX do
			smoothed[ix] = {}
		end
		for ix = 2, cellsX - 1 do
			for iz = 2, cellsZ - 1 do
				local sum = heightMap[ix][iz] * 2
				sum += heightMap[ix - 1][iz]
				sum += heightMap[ix + 1][iz]
				sum += heightMap[ix][iz - 1]
				sum += heightMap[ix][iz + 1]
				smoothed[ix][iz] = sum / 6
			end
		end
		for ix = 1, cellsX do
			smoothed[ix][1] = heightMap[ix][1]
			smoothed[ix][cellsZ] = heightMap[ix][cellsZ]
		end
		for iz = 1, cellsZ do
			smoothed[1][iz] = heightMap[1][iz]
			smoothed[cellsX][iz] = heightMap[cellsX][iz]
		end
		heightMap = smoothed
	end

	local surfaceSolidBeforeCarving = buildSurfaceSolidity(
		heightMap,
		nil,
		cellsX,
		cellsY,
		cellsZ,
		cellSize
	)
	-- keep the original heights for spring depth checks
	local originalHeightMap = copyHeightMap(heightMap, cellsX, cellsZ)
	local waterMask = {}
	local bankMask = {}
	for ix = 1, cellsX do
		waterMask[ix] = {}
		bankMask[ix] = {}
	end

	-- place a spring in a small share of chunks
	if random:NextInteger(1, springConfig.Chance) == 1 then
		local bufferX = springConfig.BankHalfLength + cellSize
		local bufferZ = springConfig.BankHalfWidth + cellSize
		local centerX = worldX0 + random:NextNumber(bufferX, chunkSize - bufferX)
		local centerZ = worldZ0 + random:NextNumber(bufferZ, chunkSize - bufferZ)
		local angle = random:NextNumber(0, 2 * math.pi)
		local cosine = math.cos(angle)
		local sine = math.sin(angle)
		local minHeight = math.huge
		local maxHeight = -math.huge

		for ix = 1, cellsX do
			for iz = 1, cellsZ do
				local worldX = worldX0 + (ix - 1) * cellSize
				local worldZ = worldZ0 + (iz - 1) * cellSize
				local dx = worldX - centerX
				local dz = worldZ - centerZ
				local u = dx * cosine + dz * sine
				local v = -dx * sine + dz * cosine
				local bankDistance = (u * u) / (springConfig.BankHalfLength ^ 2)
					+ (v * v) / (springConfig.BankHalfWidth ^ 2)
				if bankDistance <= 1 then
					local height = heightMap[ix][iz]
					minHeight = math.min(minHeight, height)
					maxHeight = math.max(maxHeight, height)
				end
			end
		end

		if maxHeight - minHeight <= springConfig.MaxSlope then
			local poolCellCount = 0
			local blocked = false
			for ix = 1, cellsX do
				for iz = 1, cellsZ do
					local worldX = worldX0 + (ix - 1) * cellSize
					local worldZ = worldZ0 + (iz - 1) * cellSize
					local dx = worldX - centerX
					local dz = worldZ - centerZ
					local u = dx * cosine + dz * sine
					local v = -dx * sine + dz * cosine
					local poolDistance = (u * u) / (springConfig.PoolHalfLength ^ 2)
						+ (v * v) / (springConfig.PoolHalfWidth ^ 2)
					local bankDistance = (u * u) / (springConfig.BankHalfLength ^ 2)
						+ (v * v) / (springConfig.BankHalfWidth ^ 2)
					if poolDistance <= 1 then
						poolCellCount += 1
					end
					if bankDistance <= 1 and not surfaceSolidBeforeCarving[ix][iz] then
						blocked = true
						break
					end
				end
				if blocked then
					break
				end
			end

			if not blocked and poolCellCount >= springConfig.MinPoolCells then
				local poolMinHeight = math.huge
				local bankHeightSum = 0
				local bankCellCount = 0
				for ix = 1, cellsX do
					for iz = 1, cellsZ do
						local worldX = worldX0 + (ix - 1) * cellSize
						local worldZ = worldZ0 + (iz - 1) * cellSize
						local dx = worldX - centerX
						local dz = worldZ - centerZ
						local u = dx * cosine + dz * sine
						local v = -dx * sine + dz * cosine
						local poolDistance = (u * u) / (springConfig.PoolHalfLength ^ 2)
							+ (v * v) / (springConfig.PoolHalfWidth ^ 2)
						local bankDistance = (u * u) / (springConfig.BankHalfLength ^ 2)
							+ (v * v) / (springConfig.BankHalfWidth ^ 2)
						if poolDistance <= 1 then
							poolMinHeight = math.min(poolMinHeight, originalHeightMap[ix][iz])
						elseif bankDistance <= 1 then
							bankHeightSum += originalHeightMap[ix][iz]
							bankCellCount += 1
						end
					end
				end

				local bankAverageHeight = bankCellCount > 0 and bankHeightSum / bankCellCount or poolMinHeight
				if bankAverageHeight - poolMinHeight <= springConfig.MaxBasinDepth then
					local baseLevel = math.floor(poolMinHeight / cellSize) * cellSize
					local waterLevel = baseLevel + springConfig.WaterVoxelDepth * cellSize

					for ix = 1, cellsX do
						for iz = 1, cellsZ do
							local worldX = worldX0 + (ix - 1) * cellSize
							local worldZ = worldZ0 + (iz - 1) * cellSize
							local dx = worldX - centerX
							local dz = worldZ - centerZ
							local u = dx * cosine + dz * sine
							local v = -dx * sine + dz * cosine
							local poolDistance = (u * u) / (springConfig.PoolHalfLength ^ 2)
								+ (v * v) / (springConfig.PoolHalfWidth ^ 2)
							local bankDistance = (u * u) / (springConfig.BankHalfLength ^ 2)
								+ (v * v) / (springConfig.BankHalfWidth ^ 2)
							if poolDistance <= 1 then
								heightMap[ix][iz] = waterLevel
								waterMask[ix][iz] = true
							elseif bankDistance <= 1 then
								heightMap[ix][iz] = math.max(heightMap[ix][iz], waterLevel)
								local target = waterLevel + springConfig.BankHeight
								heightMap[ix][iz] = math.min(originalHeightMap[ix][iz], target)
								bankMask[ix][iz] = true
							end
						end
					end

					local extendedX = springConfig.BankHalfLength + cellSize
					local extendedZ = springConfig.BankHalfWidth + cellSize
					for ix = 1, cellsX do
						for iz = 1, cellsZ do
							local worldX = worldX0 + (ix - 1) * cellSize
							local worldZ = worldZ0 + (iz - 1) * cellSize
							local dx = worldX - centerX
							local dz = worldZ - centerZ
							local u = dx * cosine + dz * sine
							local v = -dx * sine + dz * cosine
							local distance = (u * u) / (extendedX * extendedX)
								+ (v * v) / (extendedZ * extendedZ)
							if distance <= 1 then
								heightMap[ix][iz] = math.max(heightMap[ix][iz], waterLevel)
							end
						end
					end
				end
			end
		end
	end

	-- fill terrain and carve caves
	local materials, occupancy = allocateVoxels(cellsX, cellsY, cellsZ)
	for ix = 1, cellsX do
		for iz = 1, cellsZ do
			local height = heightMap[ix][iz]
			local fullVoxels = math.floor(height / cellSize)
			local remainder = (height % cellSize) / cellSize
			for iy = 1, math.min(fullVoxels, cellsY) do
				materials[ix][iy][iz] = Enum.Material.Rock
				occupancy[ix][iy][iz] = 1
			end
			if remainder > 0 and fullVoxels + 1 <= cellsY then
				materials[ix][fullVoxels + 1][iz] = Enum.Material.Rock
				occupancy[ix][fullVoxels + 1][iz] = remainder
			end

			local topIndex = remainder > 0 and fullVoxels + 1 or fullVoxels
			if topIndex >= 1 and topIndex <= cellsY then
				if waterMask[ix][iz] then
					materials[ix][topIndex][iz] = Enum.Material.Water
					occupancy[ix][topIndex][iz] = 1
					if topIndex > 1 then
						materials[ix][topIndex - 1][iz] = Enum.Material.Rock
						occupancy[ix][topIndex - 1][iz] = 1
					end
				elseif bankMask[ix][iz] then
					materials[ix][topIndex][iz] = Enum.Material.Sand
					occupancy[ix][topIndex][iz] = 1
				else
					materials[ix][topIndex][iz] = Enum.Material.Grass
					if topIndex > 1 then
						materials[ix][topIndex - 1][iz] = Enum.Material.Ground
					end
					if topIndex > 2 then
						materials[ix][topIndex - 2][iz] = Enum.Material.Ground
					end
				end
			end

			local lowerY = height - caveConfig.MaxDepth
			if not waterMask[ix][iz] and not bankMask[ix][iz] then
				for iy = 1, cellsY do
					local worldY = (iy - 1) * cellSize
					if worldY > caveConfig.MinHeight
						and worldY < height
						and worldY > lowerY
						and occupancy[ix][iy][iz] > 0
						and Noise:noise3D(
							worldX0 + (ix - 1) * cellSize,
							worldY,
							worldZ0 + (iz - 1) * cellSize,
							caveConfig.Scale
						) > caveConfig.Threshold then
						materials[ix][iy][iz] = Enum.Material.Air
						occupancy[ix][iy][iz] = 0
					end
				end
			end
		end
	end

	local surfaceSolid = buildSurfaceSolidity(
		heightMap,
		occupancy,
		cellsX,
		cellsY,
		cellsZ,
		cellSize
	)
	-- collect exposed cave cells for ore placement
	local candidates = {}
	for ix = 1, cellsX do
		for iy = 1, cellsY do
			for iz = 1, cellsZ do
				if occupancy[ix][iy][iz] == 0 then
					local face
					if ix > 1 and materials[ix - 1][iy][iz] == Enum.Material.Rock then
						face = Vector3.new(1, 0, 0)
					elseif ix < cellsX and materials[ix + 1][iy][iz] == Enum.Material.Rock then
						face = Vector3.new(-1, 0, 0)
					elseif iy > 1 and materials[ix][iy - 1][iz] == Enum.Material.Rock then
						face = Vector3.new(0, 1, 0)
					elseif iy < cellsY and materials[ix][iy + 1][iz] == Enum.Material.Rock then
						face = Vector3.new(0, -1, 0)
					elseif iz > 1 and materials[ix][iy][iz - 1] == Enum.Material.Rock then
						face = Vector3.new(0, 0, 1)
					elseif iz < cellsZ and materials[ix][iy][iz + 1] == Enum.Material.Rock then
						face = Vector3.new(0, 0, -1)
					end

					if face then
						table.insert(candidates, {
							ix = ix,
							iy = iy,
							iz = iz,
							face = face,
							y = (iy - 1) * cellSize + cellSize / 2,
						})
					end
				end
			end
		end
	end

	-- shuffle candidates with the chunk random stream
	for index = #candidates, 2, -1 do
		local otherIndex = random:NextInteger(1, index)
		candidates[index], candidates[otherIndex] = candidates[otherIndex], candidates[index]
	end

	return {
		cx = cx,
		cz = cz,
		chunkSize = chunkSize,
		regionHeight = regionHeight,
		cellSize = cellSize,
		cellsX = cellsX,
		cellsY = cellsY,
		cellsZ = cellsZ,
		worldX0 = worldX0,
		worldZ0 = worldZ0,
		seed = seed,
		hm = heightMap,
		surfaceSolid = surfaceSolid,
		hmOrig = originalHeightMap,
		waterMask = waterMask,
		bankMask = bankMask,
		mat = materials,
		occ = occupancy,
		candidates = candidates,
	}
end

function TerrainGen.ApplyChunk(computed)
	local region = Region3.new(
		Vector3.new(computed.worldX0, 0, computed.worldZ0),
		Vector3.new(
			computed.worldX0 + computed.chunkSize,
			computed.regionHeight,
			computed.worldZ0 + computed.chunkSize
		)
	):ExpandToGrid(computed.cellSize)

	-- write to terrain using the instance api
	Workspace.Terrain:WriteVoxels(region, computed.cellSize, computed.mat, computed.occ)
	OreGenerator.ApplyChunk(computed)
	return computed.hm, computed.surfaceSolid
end

function TerrainGen:GenerateChunk(cx, cz, chunkSize, regionHeight)
	debug.profilebegin("TerrainGen")
	local computed = TerrainGen.ComputeChunk(cx, cz, chunkSize, regionHeight)
	local heightMap, surfaceSolid = TerrainGen.ApplyChunk(computed)
	debug.profileend()
	return heightMap, surfaceSolid
end

function TerrainGen:UnloadChunk(cx, cz)
	OreGenerator.UnloadChunk(cx, cz)
end

function TerrainGen:GetNearestChunk(positionOrPart)
	local position = typeof(positionOrPart) == "Vector3" and positionOrPart or positionOrPart.Position
	return math.floor(position.X / Config.Loader.ChunkSize), math.floor(position.Z / Config.Loader.ChunkSize)
end

return TerrainGen

