const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});

pub fn main() !void {
    const screen_width: usize = 800;
    const screen_height: usize = 450;

    ray.InitWindow(screen_width, screen_height, "test");
    std.time.sleep(1000000000*10);
    ray.CloseWindow();
}

test "simple test" {
}
