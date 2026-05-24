extends TileMapLayer

# Ground constants (Spring themed - using same tilesets as winter for now)
var MAP_FLOOR1 = { "source": 1, "atlas": Vector2i(1,1) } # Try (1,1) for green if possible
var MAP_FLOOR2 = { "source": 1, "atlas": Vector2i(0,4) }
var MAP_FLOOR3 = { "source": 1, "atlas": Vector2i(1,4) }

# Indestructible Wall constants (Verified coordinates from winter)
var MAP_Indestructible_WALL1 = { "source": 1, "atlas": Vector2i(10,12) }
var MAP_Indestructible_WALL2 = { "source": 1, "atlas": Vector2i(5,12) }
#最外围的不可破坏墙
var MAP_Indestructible_WALL3 = { "source": 0, "atlas": Vector2i(3,2) }

# Destructible Wall constants (Verified coordinates from winter)
var MAP_Destructible_WALL1 = { "source": 0, "atlas": Vector2i(0,10) }
var MAP_Destructible_WALL2 = { "source": 0, "atlas": Vector2i(2,2) }
var MAP_Destructible_WALL3 = { "source": 1, "atlas": Vector2i(0,14) }

func cell_rode(x: int, y: int, rodes: Dictionary):
	set_cell(Vector2i(x, y), rodes.source, rodes.atlas)
