const std = @import("std");
const time = std.time;
const ray = @cImport({
    @cInclude("raylib.h");
});
const mazes = @import("mazes.zig");
const Allocator = std.mem.Allocator;

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
    // ray.InitWindow(screen_width, screen_height, "Test Window");
    // ray.DisableEventWaiting();

    // draw_fps = @intCast(usize, ray.GetMonitorRefreshRate(ray.GetCurrentMonitor()));
    // ray.SetTargetFPS(@intCast(c_int, draw_fps));

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
}

test {
    _ = mazes;
}
