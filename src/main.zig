const std = @import("std");
const time = std.time;
const Allocator = std.mem.Allocator;
const mazes = @import("mazes.zig");
const raster = @import("raster.zig");
const physics = @import("physics.zig");

pub const ray = @cImport({
    @cInclude("raylib.h");
    @cDefine("RAYMATH_IMPLEMENTATION", {});
    @cInclude("raymath.h");
});

// Window Resolution
const screen_width = 1280;
const screen_height = 720;

// Physics update frequency.
// These need to be integer multiplies
// of expected FPS to ensure synced
// behaviour.
const physics_hz: usize = 180;

// Window Drawing frequency.
// Set to monitor FPS on startup.
var draw_fps: usize = 60;

// Min sleep [nanoseconds].
// game loops or draw loops closer than this are simultaneous.
const min_sleep = time.ns_per_ms * 2;

// Helper function
fn print(str: []const u8) void {
    const out = std.io.getStdOut();
    out.writer().print("{s}", .{str}) catch {};
}

// Elapsed time since last call [nanoseconds].
fn game_loop(elapsed_time_ns: u64) void {
    _ = elapsed_time_ns;
    ray.PollInputEvents();
}

fn draw_loop() void {
    ray.BeginDrawing();
    ray.ClearBackground(ray.RAYWHITE);
    ray.SwapScreenBuffer();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .never_unmap = true,
        .retain_metadata = true,
    }){};

    defer std.debug.assert(!gpa.deinit());
    const allocator = gpa.allocator();

    ray.InitWindow(screen_width, screen_height, "Test Window");
    ray.SetWindowState(ray.FLAG_VSYNC_HINT);
    // ray.DisableEventWaiting();

    draw_fps = @intCast(usize, ray.GetMonitorRefreshRate(ray.GetCurrentMonitor()));
    ray.SetTargetFPS(@intCast(c_int, draw_fps));

    // const game_loop_interval_ns = time.ns_per_s /  physics_hz;
    // const draw_interval_ns = time.ns_per_s / draw_fps;

    // var last_game_loop: time.Instant = time.Instant.now() catch;
    // var last_draw: time.Instant = last_game_loop;

    // _ = game_loop_interval_ns;
    // _ = draw_interval_ns;
    // _ = last_draw;

    // while (!ray.WindowShouldClose()) {
    // }

    // print("Done!\n");
    // ray.CloseWindow();

    const maze = try mazes.SquareMaze.init(allocator, 40, 40);
    defer maze.deinit();

    try mazes.mazeify_graph(maze.graph, .Default, allocator);
    try mazes.mazeify_graph(maze.graph, .AddRandomEdges1Percent, allocator);

    const triangles = try raster.rasterize_square_maze(allocator, maze, .{ .wall_thickness = 0.2 });
    defer allocator.free(triangles);

    const extents = raster.calc_extents(maze, .{});

    // Now calculate the transform needed to move stuff to fit in the screen.
    const maze_height = screen_height * 9 / 10;
    const window_middle: ray.Vector2 = .{ .x = screen_width / 2, .y = screen_height / 2 };

    const scale_factor: f32 = @intToFloat(f32, maze_height) / extents.to_ray_rect().height;
    const translate = ray.Vector2Subtract(window_middle, ray.Vector2Scale(extents.center(), scale_factor));

    const drawn_triangles = try allocator.alloc(raster.Triangle, triangles.len);
    defer allocator.free(drawn_triangles);

    for (triangles, drawn_triangles) |maze_tri, *window_tri| {
        window_tri.* = maze_tri.transform(scale_factor, translate);
    }

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        ray.ClearBackground(ray.WHITE);
        for (drawn_triangles) |triangle| {
            ray.DrawTriangle(triangle.vertexes[0], triangle.vertexes[1], triangle.vertexes[2], ray.BLACK);
        }
        ray.EndDrawing();
    }
}

test {
    _ = mazes;
    _ = raster;
    _ = physics;
}
