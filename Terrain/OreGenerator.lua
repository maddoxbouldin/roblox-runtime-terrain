local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)
local Runtime = require(script.Parent.Runtime)

local OreGenerator = {}

local function weightedSelect(entries, totalWeight, random)
	local roll = random:NextNumber() * totalWeight
	local accumulated = 0
	for _, entry in ipairs(entries) do
		accumulated += entry.Weight
		if roll <= accumulated then
			return entry.Value
		end
	end
	return nil
end

local function shuffle(list, random)
	for index = #list, 2, -1 do
		local otherIndex = random:NextInteger(1, index)
		list[index], list[otherIndex] = list[otherIndex], list[index]
	end
end

local function getOreList(regionHeight)
	if not Config.Ores.Enabled then
		return {}
	end

	local folder = ReplicatedStorage:FindFirstChild(Config.Assets.Ores)
	if not folder or not folder:IsA("Folder") then
		return {}
	end

	-- use ore models only when matching config is available
	local ores = {}
	for _, model in ipairs(folder:GetChildren()) do
		local definition = Config.Ores.Definitions[model.Name]
		if model:IsA("Model") and definition then
			table.insert(ores, {
				Model = model,
				Weight = definition.Weight,
				MinY = definition.MinY,
				MaxY = definition.MaxY or regionHeight,
				MaxClusterSize = definition.MaxClusterSize,
			})
		end
	end
	return ores
end

local function createChunkFolder(cx, cz)
	local oreRoot = Runtime.EnsureFolder(Workspace, Config.Runtime.OreFolder)
	local name = string.format("Chunk_%d_%d", cx, cz)
	local previous = oreRoot:FindFirstChild(name)
	if previous then
		previous:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = oreRoot
	return folder
end

function OreGenerator.ApplyChunk(computed)
	local oreList = getOreList(computed.regionHeight)
	if #oreList == 0 then
		return
	end

	local chunkFolder = createChunkFolder(computed.cx, computed.cz)
	local random = Random.new(computed.seed + 4242)
	local chestAsset = ReplicatedStorage:FindFirstChild(Config.Assets.Chest)
	local clusters = 0

	for _, position in ipairs(computed.candidates) do
		if clusters >= Config.Ores.MaxClustersPerChunk then
			break
		end

		local weighted = {}
		local totalWeight = 0
		for _, ore in ipairs(oreList) do
			if position.y >= ore.MinY and position.y <= ore.MaxY then
				totalWeight += ore.Weight
				table.insert(weighted, { Value = ore, Weight = ore.Weight })
			end
		end

		if totalWeight <= 0 then
			continue
		end

		local selected = weightedSelect(weighted, totalWeight, random)
		if not selected then
			continue
		end

		-- group nearby exposed cells into one cluster
		local neighbors = {}
		for _, candidate in ipairs(computed.candidates) do
			if math.abs(candidate.ix - position.ix) <= 1
				and math.abs(candidate.iy - position.iy) <= 1
				and math.abs(candidate.iz - position.iz) <= 1 then
				table.insert(neighbors, candidate)
			end
		end
		shuffle(neighbors, random)

		local clusterSize = random:NextInteger(1, selected.MaxClusterSize)
		local placed = 0
		for _, candidate in ipairs(neighbors) do
			if placed >= clusterSize then
				break
			end
			if computed.occ[candidate.ix][candidate.iy][candidate.iz] ~= 0 then
				continue
			end

			local normal = candidate.face.Unit
			local useChest = chestAsset
				and chestAsset:IsA("Model")
				and normal.Y == 1
				and random:NextInteger(1, Config.Ores.ChestChance) == 1
			local model = (useChest and chestAsset or selected.Model):Clone()
			local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
			if not primary then
				model:Destroy()
				continue
			end
			model.PrimaryPart = primary
			model.Parent = chunkFolder

			local worldPosition = Vector3.new(
				computed.worldX0 + (candidate.ix - 1) * computed.cellSize + computed.cellSize / 2,
				(candidate.iy - 1) * computed.cellSize + computed.cellSize / 2,
				computed.worldZ0 + (candidate.iz - 1) * computed.cellSize + computed.cellSize / 2
			)
			local size = primary.Size
			local thickness = math.abs(normal.X * size.X)
				+ math.abs(normal.Y * size.Y)
				+ math.abs(normal.Z * size.Z)
			local baseOffset = computed.cellSize * (useChest and 1 or 0.8) + thickness / 2
			local initialPosition = worldPosition + normal * baseOffset

			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = { chunkFolder }
			local result = Workspace:Raycast(initialPosition, -normal * (baseOffset + 5), raycastParams)
			local finalPosition = result and result.Position + normal * (thickness * 0.2) or initialPosition

			-- align the model with the exposed cave face
			local tangent = normal:Cross(Vector3.yAxis)
			if tangent.Magnitude < 0.001 then
				tangent = normal:Cross(Vector3.xAxis)
			end
			tangent = tangent.Unit
			local right = tangent:Cross(normal)
			model:PivotTo(CFrame.fromMatrix(finalPosition, right, normal))
			primary.CanCollide = false
			primary.CastShadow = false

			computed.occ[candidate.ix][candidate.iy][candidate.iz] = 1
			placed += 1
		end

		clusters += 1
	end
end

function OreGenerator.UnloadChunk(cx, cz)
	local oreRoot = Workspace:FindFirstChild(Config.Runtime.OreFolder)
	if not oreRoot then
		return
	end

	local folder = oreRoot:FindFirstChild(string.format("Chunk_%d_%d", cx, cz))
	if folder then
		folder:Destroy()
	end
end

return OreGenerator
