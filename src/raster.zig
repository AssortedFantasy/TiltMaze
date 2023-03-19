const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const mazes = @import("mazes.zig");
const ray = @import("main.zig").ray;

// This zig file contains rasterization. I.E turning mazes into sets of triangles.
// Also some functions to rotate and other similar features.
pub const triangle = struct {
    vertexes: [3]ray.Vector2,
};

pub const rectangle = struct {
    // Top left is minimum x,y
    top_left: ray.Vector2,
    // Bottom right is maximum x,y
    bottom_right: ray.Vector2,

    const Self = @This();

    pub fn to_ray_rect(self: Self) ray.Rectangle {
        return .{
            .x = self.top_left.x,
            .y = self.top_left.y,
            .width = self.bottom_right.x - self.top_left.x,
            .height = self.bottom_right.y - self.top_left.y,
        };
    }

    pub fn center(self: Self) ray.Vector2 {
        return ray.Vector2Scale(ray.Vector2Add(self.top_left, self.bottom_right), 0.5);
    }

    pub fn transform(self: Self, scale: f32, translate: ray.Vector2) Self {
        const new_top_left = ray.Vector2Add(ray.Vector2Scale(self.top_left, scale), translate);
        const new_bottom_right = ray.Vector2Add(ray.Vector2Scale(self.bottom_right, scale), translate);
        return .{
            .top_left = new_top_left,
            .bottom_right = new_bottom_right,
        };
    }
};

pub const SquareMazeConfig = struct {
    // The maze is on an exact grid pattern, top at (0.,0.) growing right and down.
    // each cell is cell_width by cell_height in dimensions.
    wall_thickness: f32 = 0.1,
    cell_width: f32 = 1.0,
    cell_height: f32 = 1.0,
};

pub fn rects_to_triangles(allocator: Allocator, rects: []const rectangle) []triangle {
    _ = allocator;
    _ = rects;
}

// Helper function
// Vertical wall from line
fn vert_wall(x: f32, y0: f32, y1: f32, config: SquareMazeConfig) rectangle {
    const y_max = @max(y0, y1);
    const y_min = @min(y0, y1);
    const half_width = config.wall_thickness / 2;
    return .{
        .top_left = .{ .x = x - half_width, .y = y_min - half_width },
        .bottom_right = .{ .x = x + half_width, .y = y_max + half_width },
    };
}

// Helper function
// Horizontal wall from line
fn horz_wall(y: f32, x0: f32, x1: f32, config: SquareMazeConfig) rectangle {
    const x_max = @max(x0, x1);
    const x_min = @min(x0, x1);
    const half_width = config.wall_thickness / 2;
    return .{
        .top_left = .{ .x = x_min - half_width, .y = y - half_width },
        .bottom_right = .{ .x = x_max + half_width, .y = y + half_width },
    };
}

// Memory is allocatored with allocator.
pub fn rasterize_square_maze_rect(allocator: Allocator, maze: mazes.SquareMaze, config: SquareMazeConfig) ![]rectangle {
    var created = try std.ArrayList(rectangle).initCapacity(allocator, 4);
    errdefer created.deinit();

    // First 4 are the boundry walls.
    {
        const total_width = config.cell_width * @intToFloat(f32, maze.width);
        const total_height = config.cell_height * @intToFloat(f32, maze.height);
        created.appendSliceAssumeCapacity(&.{
            vert_wall(0.0, 0.0, total_height, config), // Left
            vert_wall(total_width, 0.0, total_height, config), // Right
            horz_wall(0.0, 0.0, total_width, config), // Top
            horz_wall(total_height, 0.0, total_width, config), // Bottom
        });
    }

    // Now Vertical walls.
    for (0..maze.width - 1) |col| {
        const col_x = config.cell_width * @intToFloat(f32, col + 1);
        // To avoid excess shapes, we consolidate walls together vertically.
        var row: usize = 0;
        var wall_start: f32 = -0.0;
        var partial_wall: bool = false;

        while (row < maze.height) : (row += 1) {
            const self = maze.index(row, col);
            const right = maze.index(row, col + 1);
            // Mistake if not square maze.
            std.debug.assert(maze.graph.is_adjacent(self, right));
            if (!maze.graph.is_edge(self, right)) {
                // Wall is here
                if (partial_wall) {
                    // not new wall.
                    continue;
                } else {
                    // start of new wall.
                    wall_start = @intToFloat(f32, row);
                    partial_wall = true;
                    continue;
                }
            } else {
                // No edge
                if (partial_wall) {
                    // Complete partial wall.
                    partial_wall = false;
                    const wall_end = @intToFloat(f32, row);
                    try created.append(vert_wall(col_x, wall_start * config.cell_height, wall_end * config.cell_height, config));
                    continue;
                } else {
                    // No partial wall to complete.
                    continue;
                }
            }
        }
        if (partial_wall) {
            // Complete final wall.
            const wall_end = @intToFloat(f32, maze.height);
            try created.append(vert_wall(col_x, wall_start * config.cell_height, wall_end * config.cell_height, config));
        }
    }

    // Now Horizontal walls.
    for (0..maze.height - 1) |row| {
        const row_y = config.cell_height * @intToFloat(f32, row + 1);
        // To avoid excess shapes, we consolidate walls together horizontally.
        var col: usize = 0;
        var wall_start: f32 = -0.0;
        var partial_wall: bool = false;

        while (col < maze.width) : (col += 1) {
            const self = maze.index(row, col);
            const below = maze.index(row + 1, col);
            // Mistake if not square maze.
            std.debug.assert(maze.graph.is_adjacent(self, below));
            if (!maze.graph.is_edge(self, below)) {
                // Wall is here
                if (partial_wall) {
                    // not new wall.
                    continue;
                } else {
                    // start of new wall.
                    wall_start = @intToFloat(f32, col);
                    partial_wall = true;
                    continue;
                }
            } else {
                // No edge
                if (partial_wall) {
                    // Complete partial wall.
                    partial_wall = false;
                    const wall_end = @intToFloat(f32, col);
                    try created.append(horz_wall(row_y, wall_start * config.cell_width, wall_end * config.cell_width, config));
                } else {
                    // No partial wall to complete.
                    continue;
                }
            }
        }
        if (partial_wall) {
            // Complete final wall.
            const wall_end = @intToFloat(f32, maze.width);
            try created.append(horz_wall(row_y, wall_start * config.cell_width, wall_end * config.cell_width, config));
        }
    }

    return created.toOwnedSlice();
}

// Memory is allocated with allocator.
pub fn rasterize_square_maze(allocator: Allocator, maze: mazes.SquareMaze, config: SquareMazeConfig) ![]triangle {
    _ = allocator;
    _ = maze;
    _ = config;
}

// Find the dimensions of a rectangle that covers everything.
pub fn calc_extents(maze: mazes.SquareMaze, config: SquareMazeConfig) rectangle {
    const half_width = config.cell_width / 2;

    const min_x: f32 = -half_width;
    const min_y: f32 = -half_width;

    const max_x: f32 = half_width + config.cell_width * @intToFloat(f32, maze.width);
    const max_y: f32 = half_width + config.cell_height * @intToFloat(f32, maze.height);
    return rectangle{
        .top_left = .{ .x = min_x, .y = min_y },
        .bottom_right = .{ .x = max_x, .y = max_y },
    };
}

test "Making rectangularized maze" {
    const allocator = testing.allocator;
    const width = 4;
    const height = 4;

    const maze = try mazes.SquareMaze.init(allocator, height, width);
    defer maze.deinit();
    try mazes.mazeify_graph(maze.graph, .Default, allocator);

    const rects = try rasterize_square_maze_rect(allocator, maze, .{});
    defer allocator.free(rects);

    for (rects) |rect| {
        // Basic checks to make sure rects are ordered correctly.
        try std.testing.expect(rect.top_left.x <= rect.bottom_right.x);
        try std.testing.expect(rect.top_left.y <= rect.bottom_right.y);
        //std.debug.print("\n[({d:.2},{d:.2}),({d:.2},{d:.2})]", .{ rect.top_left.x, rect.top_left.y, rect.bottom_right.x, rect.bottom_right.y });
    }
}
