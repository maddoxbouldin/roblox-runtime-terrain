local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local Runtime = {}

function Runtime.EnsureInstance(parent, className, name)
	local current = parent:FindFirstChild(name)
	if current then
		assert(current:IsA(className), string.format("%s must be a %s", current:GetFullName(), className))
		return current
	end

	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function Runtime.EnsureFolder(parent, name)
	return Runtime.EnsureInstance(parent, "Folder", name)
end

function Runtime.GetRequiredAssetFolder(key)
	local name = Config.Assets[key]
	assert(name, string.format("unknown terrain asset key: %s", tostring(key)))

	local folder = ReplicatedStorage:FindFirstChild(name)
	assert(folder and folder:IsA("Folder"), string.format("ReplicatedStorage.%s must be a Folder", name))
	return folder
end

function Runtime.GetModels(folder)
	local models = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end
	return models
end

function Runtime.ValidateRequiredAssets()
	Runtime.GetRequiredAssetFolder("Rocks")
	Runtime.GetRequiredAssetFolder("Trees")
	Runtime.GetRequiredAssetFolder("Vegetation")
end

function Runtime.Initialize(terrainFolder)
	local seed = terrainFolder:GetAttribute("ResolvedSeed")
	if typeof(seed) ~= "number" then
		seed = Config.Seed
		if seed == 0 then
			seed = Random.new():NextInteger(Config.RandomSeedMin, Config.RandomSeedMax)
		end
		terrainFolder:SetAttribute("ResolvedSeed", seed)
	end

	return {
		Seed = seed,
		Vegetation = Runtime.EnsureFolder(Workspace, Config.Runtime.VegetationFolder),
		Ores = Runtime.EnsureFolder(Workspace, Config.Runtime.OreFolder),
		Workers = Runtime.EnsureFolder(Workspace, Config.Runtime.WorkerFolder),
		ChunkComputed = Runtime.EnsureInstance(terrainFolder, "BindableEvent", Config.Runtime.ChunkResultEvent),
		WorkerReady = Runtime.EnsureInstance(terrainFolder, "BindableEvent", Config.Runtime.WorkerReadyEvent),
	}
end

function Runtime.CreateVegetationChunk(root, cx, cz)
	local name = string.format("ChunkVeg_%d_%d", cx, cz)
	local previous = root:FindFirstChild(name)
	if previous then
		previous:Destroy()
	end

	local chunk = Instance.new("Folder")
	chunk.Name = name
	chunk.Parent = root

	Runtime.EnsureFolder(chunk, "Rocks")
	Runtime.EnsureFolder(chunk, "Trees")
	Runtime.EnsureFolder(chunk, "Vegetation")
	return chunk
end

function Runtime.CreateWorkers(root, template, count)
	-- remove workers created by an earlier initialization
	for _, child in ipairs(root:GetChildren()) do
		if child:GetAttribute("TerrainGeneratorWorker") then
			child:Destroy()
		end
	end

	local workers = {}
	for index = 1, count do
		local actor = Instance.new("Actor")
		actor.Name = string.format("TerrainWorker%d", index)
		actor:SetAttribute("TerrainGeneratorWorker", true)
		actor.Parent = root

		local worker = template:Clone()
		worker.Name = "ChunkWorker"
		worker.Enabled = false
		worker.Parent = actor
		worker.Enabled = true

		table.insert(workers, actor)
	end
	return workers
end

return Runtime
