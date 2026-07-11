local ServerScriptService = game:GetService("ServerScriptService")

local terrainFolder = ServerScriptService:WaitForChild("Terrain")
local TerrainGen = require(terrainFolder:WaitForChild("TerrainGen"))
local chunkComputed = terrainFolder:WaitForChild("ChunkComputed")
local workerReady = terrainFolder:WaitForChild("TerrainWorkerReady")
local actor = script:GetActor()

assert(actor, "ChunkWorker must run under an Actor")

actor:BindToMessageParallel("GenerateChunk", function(jobId, cx, cz, chunkSize, regionHeight)
	local computed = TerrainGen.ComputeChunk(cx, cz, chunkSize, regionHeight)

	-- return to synchronized execution before firing the result event
	task.synchronize()
	chunkComputed:Fire(jobId, computed)
end)

workerReady:Fire(actor)
