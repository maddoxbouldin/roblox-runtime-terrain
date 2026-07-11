# Roblox Runtime Terrain

![License](https://img.shields.io/badge/license-MIT-blue.svg)

An open-source runtime terrain generation system for Roblox featuring chunk streaming, Parallel Luau, caves, springs, and procedural vegetation.

<p align="center">
  <img src="https://github.com/maddoxbouldin/roblox-runtime-terrain/blob/main/docs/images/terrain-forest.png" alt="Generated caves" width="49%">
  <img src="docs/images/terrain-forest.jpg" alt="Generated forest" width="49%">
</p>

## Features

- Chunk-based terrain loading and unloading around players
- Parallel Luau Actor workers for terrain computation
- Configurable fractal noise height generation
- Smoothed terrain surfaces
- Underground cave generation
- Small randomly generated springs and water pools
- Forest and plains biomes
- Deterministic vegetation placement
- Trees, rocks, flowers, ferns, and other vegetation
- Optional ore and chest generation inside caves
- Deterministic generation from a shared server seed
- Automatic creation of runtime folders, events, and workers
- Centralized configuration
- Public generation API for custom loaders

## Installation

Place the terrain code inside `ServerScriptService.Terrain`.

Place the required asset folders directly inside `ReplicatedStorage`.

```text
ServerScriptService
└── Terrain
    ├── Config
    ├── Runtime
    ├── Noise
    ├── TerrainGen
    ├── Vegetation
    ├── OreGenerator
    ├── ChunkWorker
    └── TerrainLoader

ReplicatedStorage
├── Rocks
├── Trees
└── Vegetation
```

`ChunkWorker` should remain disabled. `TerrainLoader` clones and enables it automatically inside the generated Actor workers.

You do not need to create anything in `Workspace`. The system creates the following folders at runtime:

```text
Workspace
├── Vegetation
├── OreChunks
└── TerrainWorkers
```

Once the scripts and assets are in place, press **Play**. Terrain will begin generating around each player automatically.

## Configuration

The main settings are located in:

```text
ServerScriptService.Terrain.Config
```

The configuration module controls:

- Seed behavior
- Chunk size and region height
- Player view distance
- Worker count
- Terrain height and noise scale
- Cave depth and frequency
- Spring size, frequency, banks, and water depth
- Forest and plains biome distribution
- Tree, rock, and vegetation density
- Ore rarity and cluster size

### Seeds

Setting `Config.Seed` to `0` selects one random seed for each server.

Using a specific number produces repeatable terrain:

```lua
Config.Seed = 12345
```

### Chunk dimensions

Chunk size and region height must remain multiples of the terrain cell size.

```lua
Config.Loader = {
    ChunkSize = 128,
    RegionHeight = 128,
    ViewDistance = 2,
    UpdateInterval = 2,
    WorkerCount = 4,
    WorkerReadyTimeout = 10,
}
```

Increasing chunk size or view distance will increase generation time and memory usage.

## Springs and caves

Springs and caves are separate systems.

- **Springs** are small surface water pools scattered throughout the generated terrain.
- **Caves** are underground spaces carved using three-dimensional noise.

They can be configured independently through:

```lua
Config.Spring
Config.Caves
```

## Vegetation assets

The following folders are required in `ReplicatedStorage`:

```text
ReplicatedStorage.Rocks
ReplicatedStorage.Trees
ReplicatedStorage.Vegetation
```

Each asset should be a `Model` containing at least one `BasePart`.

The generator uses `Model.PrimaryPart` when available. Otherwise, it selects the first `BasePart` it can find.

Models can also contain an optional `Vector3Value` named `Offset` to correct their final placement.

## Optional ore generation

Ore generation stays inactive when `ReplicatedStorage.Ores` is absent.

To enable it, add the optional assets:

```text
ReplicatedStorage
├── Ores
└── Chest
```

`Ores` should be a folder containing ore models. Each ore model needs a matching entry under `Config.Ores.Definitions`.

The `Chest` model is optional.

Example definition:

```lua
Config.Ores.Definitions = {
    ["Gold Ore"] = {
        Weight = 0.2,
        MinY = 0,
        MaxY = 78,
        MaxClusterSize = 2,
    },
}
```

## Public API

The main `TerrainGen` module exposes the following functions.

### `TerrainGen.ComputeChunk()`

Computes the terrain data for a chunk without writing it to the DataModel.

```lua
local computed = TerrainGen.ComputeChunk(
    chunkX,
    chunkZ,
    chunkSize,
    regionHeight
)
```

### `TerrainGen.ApplyChunk()`

Writes previously computed terrain data and applies optional ore generation.

```lua
local heightMap, surfaceSolid = TerrainGen.ApplyChunk(computed)
```

### `TerrainGen:GenerateChunk()`

Computes and applies a chunk synchronously.

```lua
local heightMap, surfaceSolid = TerrainGen:GenerateChunk(
    chunkX,
    chunkZ,
    chunkSize,
    regionHeight
)
```

### `TerrainGen:UnloadChunk()`

Removes the generated objects associated with a chunk.

```lua
TerrainGen:UnloadChunk(chunkX, chunkZ)
```

### `TerrainGen:GetNearestChunk()`

Returns the chunk coordinates nearest to a position or part.

```lua
local chunkX, chunkZ = TerrainGen:GetNearestChunk(position)
```

These functions allow you to replace the included player-based loader with your own streaming system.

## Project structure

| Module | Purpose |
| --- | --- |
| `Config` | Contains all public configuration |
| `Runtime` | Creates runtime folders, events, and Actor workers |
| `Noise` | Provides deterministic two-dimensional and three-dimensional noise |
| `TerrainGen` | Computes and applies terrain chunks |
| `Vegetation` | Computes and places rocks, trees, and vegetation |
| `OreGenerator` | Handles optional ore and chest placement |
| `ChunkWorker` | Runs chunk computation through Parallel Luau |
| `TerrainLoader` | Streams chunks around players |

## Notes

- Generated runtime folders should not be included with the release.
- Terrain generation is performed on the server.
- Ore and chest assets are optional.
- Larger chunks and view distances require more server memory.
- The default loader creates four Actor workers.
- The generator uses Roblox's built-in voxel terrain.

## Contributing

Bug reports, improvements, and pull requests are welcome.

If you use this system in a project, I would love to see what you make with it.

## License

This project is licensed under the [MIT License](LICENSE).
