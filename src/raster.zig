const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const mazes = @import("mazes.zig");
const ray = @import("main.zig").ray;
const Ball = @import("physics.zig").Ball;

inline fn transform_point(p: ray.Vector2, scale: f32, translate: ray.Vector2) ray.Vector2 {
    return ray.Vector2Add(ray.Vector2Scale(p, scale), translate);
}

pub fn transform_ball(ball: Ball, scale: f32, translate: ray.Vector2) struct {center: ray.Vector2, radius: f32} {
    return .{
        .center = transform_point(ball.center, scale, translate),
        .radius = ball.radius * scale,
    };
}

// This zig file contains rasterization. I.E turning mazes into sets of triangles.
// Also some functions to rotate and other similar features.
pub const Triangle = struct {
    vertexes: [3]ray.Vector2,

    const Self = @This();

    pub fn transform(self: Self, scale: f32, translate: ray.Vector2) Self {
        return .{
            .vertexes = .{
                transform_point(self.vertexes[0], scale, translate),
                transform_point(self.vertexes[1], scale, translate),
                transform_point(self.vertexes[2], scale, translate),
            },
        };
    }
};

pub const Rectangle = struct {
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
        return .{
            .top_left = transform_point(self.top_left, scale, translate),
            .bottom_right = transform_point(self.bottom_right, scale, translate),
        };
    }

    pub fn trianglulate(self: Self) [2]Triangle {
        // Triangles need to be CCW oriented.
        const top_left = self.top_left;
        const bottom_right = self.bottom_right;
        const bottom_left = ray.Vector2{ .x = top_left.x, .y = bottom_right.y };
        const top_right = ray.Vector2{ .x = bottom_right.x, .y = top_left.y };

        const triangle1 = Triangle{
            .vertexes = .{
                top_left,
                bottom_left,
                bottom_right,
            },
        };

        const triangle2 = Triangle{
            .vertexes = .{
                top_left,
                bottom_right,
                top_right,
            },
        };

        return .{ triangle1, triangle2 };
    }
};

pub const SquareMazeConfig = struct {
    // The maze is on an exact grid pattern, top at (0.,0.) growing right and down.
    // each cell is cell_width by cell_height in dimensions.
    wall_thickness: f32 = 0.1,
    cell_width: f32 = 1.0,
    cell_height: f32 = 1.0,
};

pub fn rects_to_triangles(allocator: Allocator, rects: []const Rectangle) []Triangle {
    _ = allocator;
    _ = rects;
}

// Helper function
// Vertical wall from line
fn vert_wall(x: f32, y0: f32, y1: f32, config: SquareMazeConfig) Rectangle {
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
fn horz_wall(y: f32, x0: f32, x1: f32, config: SquareMazeConfig) Rectangle {
    const x_max = @max(x0, x1);
    const x_min = @min(x0, x1);
    const half_width = config.wall_thickness / 2;
    return .{
        .top_left = .{ .x = x_min - half_width, .y = y - half_width },
        .bottom_right = .{ .x = x_max + half_width, .y = y + half_width },
    };
}

// Memory is allocatored with allocator.
pub fn rasterize_square_maze_rect(allocator: Allocator, maze: mazes.SquareMaze, config: SquareMazeConfig) ![]Rectangle {
    var created = try std.ArrayList(Rectangle).initCapacity(allocator, 4);
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
pub fn rasterize_square_maze(allocator: Allocator, maze: mazes.SquareMaze, config: SquareMazeConfig) ![]Triangle {
    const rects = try rasterize_square_maze_rect(allocator, maze, config);
    defer allocator.free(rects);

    const triangles = try allocator.alloc(Triangle, 2 * rects.len);
    for (rects, 0..) |rect, i| {
        triangles[2 * i ..][0..2].* = rect.trianglulate();
    }

    return triangles;
}

// Find the dimensions of a rectangle that covers everything.
pub fn calc_extents(maze: mazes.SquareMaze, config: SquareMazeConfig) Rectangle {
    const half_width = config.cell_width / 2;

    const min_x: f32 = -half_width;
    const min_y: f32 = -half_width;

    const max_x: f32 = half_width + config.cell_width * @intToFloat(f32, maze.width);
    const max_y: f32 = half_width + config.cell_height * @intToFloat(f32, maze.height);
    return Rectangle{
        .top_left = .{ .x = min_x, .y = min_y },
        .bottom_right = .{ .x = max_x, .y = max_y },
    };
}

test "Making rectangularized maze" {
    const allocator = testing.allocator;
    const width = 8;
    const height = 9;

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

test "Making triangulated maze" {
    const allocator = testing.allocator;
    const width = 8;
    const height = 9;

    const maze = try mazes.SquareMaze.init(allocator, height, width);
    defer maze.deinit();
    try mazes.mazeify_graph(maze.graph, .Default, allocator);

    const triangles = try rasterize_square_maze(allocator, maze, .{});
    defer allocator.free(triangles);
}
