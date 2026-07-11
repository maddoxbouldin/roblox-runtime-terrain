local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local terrainFolder = script.Parent
local Config = require(terrainFolder.Config)
local Runtime = require(terrainFolder.Runtime)

Runtime.ValidateRequiredAssets()
local runtime = Runtime.Initialize(terrainFolder)
local TerrainGen = require(terrainFolder.TerrainGen)
local Vegetation = require(terrainFolder.Vegetation)

local workerTemplate = terrainFolder:FindFirstChild("ChunkWorker")
assert(workerTemplate and workerTemplate:IsA("Script"), "Terrain.ChunkWorker must be a Script")

local readyWorkers = {}
local readyCount = 0
local readyConnection = runtime.WorkerReady.Event:Connect(function(actor)
	if not readyWorkers[actor] then
		readyWorkers[actor] = true
		readyCount += 1
	end
end)

local workers = Runtime.CreateWorkers(runtime.Workers, workerTemplate, Config.Loader.WorkerCount)
-- wait until each actor has registered its message handler
local readyDeadline = os.clock() + Config.Loader.WorkerReadyTimeout
while readyCount < #workers and os.clock() < readyDeadline do
	task.wait()
end
readyConnection:Disconnect()
assert(readyCount == #workers, string.format("only %d of %d terrain workers started", readyCount, #workers))

local chunks = {}
local playerState = {}
local pending = {}
local nextWorker = 1
local nextJobId = 0

local function chunkKey(cx, cz)
	return string.format("%d,%d", cx, cz)
end

local function parseChunkKey(key)
	local cx, cz = key:match("^(%-?%d+),(%-?%d+)$")
	return tonumber(cx), tonumber(cz)
end

local function getWorker()
	local worker = workers[nextWorker]
	nextWorker += 1
	if nextWorker > #workers then
		nextWorker = 1
	end
	return worker
end

runtime.ChunkComputed.Event:Connect(function(jobId, computed)
	local job = pending[jobId]
	if not job then
		return
	end
	pending[jobId] = nil

	local entry = chunks[job.key]
	if not entry or entry.refCount <= 0 or entry.jobId ~= jobId then
		return
	end

	TerrainGen.ApplyChunk(computed)
	local vegetationFolder = Runtime.CreateVegetationChunk(runtime.Vegetation, job.cx, job.cz)
	Vegetation:PopulateChunk(job.cx, job.cz, Config.Loader.ChunkSize, vegetationFolder, {
		cellSize = computed.cellSize,
		heightMap = computed.hm,
		waterMask = computed.waterMask,
		biomeScale = Config.Vegetation.BiomeScale,
		biomeWeights = Config.Vegetation.BiomeWeights,
	})

	entry.vegFolder = vegetationFolder
	entry.status = "ready"
end)

local function loadChunk(cx, cz)
	-- keep one chunk instance shared by all nearby players
	local key = chunkKey(cx, cz)
	local entry = chunks[key]
	if entry then
		entry.refCount += 1
		return
	end

	nextJobId += 1
	entry = {
		refCount = 1,
		vegFolder = nil,
		jobId = nextJobId,
		status = "pending",
	}
	chunks[key] = entry
	pending[nextJobId] = {
		key = key,
		cx = cx,
		cz = cz,
	}

	getWorker():SendMessage(
		"GenerateChunk",
		nextJobId,
		cx,
		cz,
		Config.Loader.ChunkSize,
		Config.Loader.RegionHeight
	)
end

local function unloadChunk(cx, cz)
	local key = chunkKey(cx, cz)
	local entry = chunks[key]
	if not entry then
		return
	end

	entry.refCount -= 1
	if entry.refCount > 0 then
		return
	end

	if entry.jobId then
		pending[entry.jobId] = nil
	end

	-- clear terrain after the last player releases a chunk
	local region = Region3.new(
		Vector3.new(cx * Config.Loader.ChunkSize, 0, cz * Config.Loader.ChunkSize),
		Vector3.new(
			(cx + 1) * Config.Loader.ChunkSize,
			Config.Loader.RegionHeight,
			(cz + 1) * Config.Loader.ChunkSize
		)
	):ExpandToGrid(Config.Terrain.CellSize)
	Workspace.Terrain:FillRegion(region, Config.Terrain.CellSize, Enum.Material.Air)

	if entry.vegFolder then
		entry.vegFolder:Destroy()
	end
	TerrainGen:UnloadChunk(cx, cz)
	chunks[key] = nil
end

local function updatePlayerChunks(player)
	local state = playerState[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not state or not root then
		return
	end

	local position = root.Position
	local cx = math.floor(position.X / Config.Loader.ChunkSize)
	local cz = math.floor(position.Z / Config.Loader.ChunkSize)
	if state.currCX == cx and state.currCZ == cz then
		return
	end
	state.currCX = cx
	state.currCZ = cz

	local required = {}
	for dx = -Config.Loader.ViewDistance, Config.Loader.ViewDistance do
		for dz = -Config.Loader.ViewDistance, Config.Loader.ViewDistance do
			local targetX = cx + dx
			local targetZ = cz + dz
			required[chunkKey(targetX, targetZ)] = { x = targetX, z = targetZ }
		end
	end

	for key, coordinates in pairs(required) do
		if not state.loaded[key] then
			loadChunk(coordinates.x, coordinates.z)
			state.loaded[key] = true
		end
	end

	for key in pairs(state.loaded) do
		if not required[key] then
			local oldX, oldZ = parseChunkKey(key)
			unloadChunk(oldX, oldZ)
			state.loaded[key] = nil
		end
	end
end

local function registerPlayer(player)
	if playerState[player] then
		return
	end

	playerState[player] = {
		currCX = nil,
		currCZ = nil,
		loaded = {},
	}

	local function characterAdded(character)
		local state = playerState[player]
		if not state then
			return
		end
		state.currCX = nil
		state.currCZ = nil

		task.defer(function()
			if character:WaitForChild("HumanoidRootPart", 10) then
				updatePlayerChunks(player)
			end
		end)
	end

	player.CharacterAdded:Connect(characterAdded)
	if player.Character then
		characterAdded(player.Character)
	end
end

Players.PlayerAdded:Connect(registerPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	registerPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	local state = playerState[player]
	if not state then
		return
	end

	for key in pairs(state.loaded) do
		local cx, cz = parseChunkKey(key)
		unloadChunk(cx, cz)
	end
	playerState[player] = nil
end)

-- update all players on one shared interval
task.spawn(function()
	while true do
		for player in pairs(playerState) do
			updatePlayerChunks(player)
		end
		task.wait(Config.Loader.UpdateInterval)
	end
end)
