local Config = {}

-- set seed to 0 to choose one seed for each server
Config.Seed = 0
Config.RandomSeedMin = 900
Config.RandomSeedMax = 1100

Config.Loader = {
	ChunkSize = 128,
	RegionHeight = 128,
	ViewDistance = 2,
	UpdateInterval = 2,
	WorkerCount = 4,
	WorkerReadyTimeout = 10,
}

Config.Terrain = {
	CellSize = 4,
	Octaves = 4,
	Persistence = 0.5,
	Lacunarity = 2,
	NoiseScale = 100,
	BaseHeight = 100,
	HeightAmplitude = 20,
}

Config.Caves = {
	Scale = 66,
	Threshold = 0.4,
	MaxDepth = 80,
	MinHeight = 10,
}

Config.Spring = {
	Chance = 10,
	PoolHalfLength = 30,
	PoolHalfWidth = 15,
	BankHalfLength = 18,
	BankHalfWidth = 18,
	MaxSlope = 20,
	BankHeight = 4,
	WaterVoxelDepth = 1,
	MinPoolCells = 20,
	MaxBasinDepth = 8,
}

Config.Vegetation = {
	BiomeScale = 512,
	BiomeWeights = {
		Forest = 3,
		Plains = 2,
	},
	SpawnChances = {
		Forest = {
			Rock = 0.01,
			Tree = 0.08,
			Vegetation = 0.06,
		},
		Plains = {
			Rock = 0.005,
			Tree = 0.08 / 3,
			Vegetation = 0.03,
		},
	},
}

Config.Ores = {
	-- ore generation does not begin if no ore models are available
	Enabled = true,
	MaxClustersPerChunk = 15,
	ChestChance = 25,
	Definitions = {
		["Gold Ore"] = { Weight = 0.2, MinY = 0, MaxY = 78, MaxClusterSize = 2 },
		["Silver Ore"] = { Weight = 0.4, MinY = 0, MaxY = 78, MaxClusterSize = 3 },
		["Copper Ore"] = { Weight = 0.7, MinY = 0, MaxY = 78, MaxClusterSize = 4 },
		["Diamond Ore"] = { Weight = 0.1, MinY = 0, MaxY = 78, MaxClusterSize = 1 },
	},
}

-- rock, tree, and vegetation folders are required; ore and chest assets are optional
Config.Assets = {
	Rocks = "Rocks",
	Trees = "Trees",
	Vegetation = "Vegetation",
	Ores = "Ores",
	Chest = "Chest",
}

Config.Runtime = {
	VegetationFolder = "Vegetation",
	OreFolder = "OreChunks",
	WorkerFolder = "TerrainWorkers",
	ChunkResultEvent = "ChunkComputed",
	WorkerReadyEvent = "TerrainWorkerReady",
}

return Config
