const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});

const screen_width = 800;
const screen_height = 450;
const fps = 60;

fn print(str: []const u8) void {
    std.debug.print("{s}", .{str});
}


pub fn main() !void {

    ray.InitWindow(screen_width, screen_height, "test");
    ray.SetTargetFPS(fps);

    while (!ray.WindowShouldClose()) {
        ray.BeginDrawing();
        ray.ClearBackground(ray.RAYWHITE);
        ray.EndDrawing();
    }
    
    print("Done!\n");
    ray.CloseWindow();
}

test "simple test" {
}
