const std = @import("std");
const ray = @import("main.zig").ray;
const Triangle = @import("raster.zig").Triangle;
const assert = std.debug.assert;

// Collides with balls on one side.
// Line segment from point A to Point B.
// V = B-A (cached)
// Normal vector is point N.
pub const One_Sided_Wall = struct {
    A: ray.Vector2,
    B: ray.Vector2,
    V: ray.Vector2,
    N: ray.Vector2,
    L2: f32,

    const Self = @This();

    // Signed Distance d.
    fn calc_d(self: Self, P: ray.Vector2) f32 {
        const R = ray.Vector2Subtract(P, self.A);
        return ray.Vector2DotProduct(R, self.N);
    }

    // A number which tells you how far along A->B you are.
    fn calc_l(self: Self, P: ray.Vector2) f32 {
        const R = ray.Vector2Subtract(P, self.A);
        return ray.Vector2DotProduct(R, self.V);
    }

    // Alternate co-ordinate system. Useful for physics calculations.
    fn calc_ld(self: Self, P: ray.Vector2) struct { l: f32, d: f32 } {
        const R = ray.Vector2Subtract(P, self.A);
        return .{
            .l = ray.Vector2DotProduct(R, self.V),
            .d = ray.Vector2DotProduct(R, self.N),
        };
    }

    fn from_two_points(A: ray.Vector2, B: ray.Vector2) Self {
        // A -> B.
        // Normal is 90 degrees CW rotation
        const V = ray.Vector2Subtract(B, A);
        const L2 = ray.Vector2LengthSqr(V);
        const N = ray.Vector2Normalize(.{ .x = -V.y, .y = V.x });
        return .{
            .A = A,
            .B = B,
            .V = V,
            .N = N,
            .L2 = L2,
        };
    }

    pub fn from_triangles(tri: Triangle) [3]Self {
        const walls = [3]Self{
            from_two_points(tri.vertexes[0], tri.vertexes[1]),
            from_two_points(tri.vertexes[1], tri.vertexes[2]),
            from_two_points(tri.vertexes[2], tri.vertexes[0]),
        };
        // Make sure that the walls arent degenerate.
        assert(walls[0].calc_d(tri.vertexes[2]) < 0);
        assert(walls[1].calc_d(tri.vertexes[0]) < 0);
        assert(walls[2].calc_d(tri.vertexes[1]) < 0);
        return walls;
    }
};

pub const Ball = struct {
    center: ray.Vector2,
    radius: f32,
    velocity: ray.Vector2,

    const Self = @This();
};

// Balls don't collide with each other. Only walls.
pub const physics = struct {
    gravity: ray.Vector2,
    resistance: f32,
    static_bodies: []One_Sided_Wall,
    dynamic_bodies: []Ball,

    const Self = @This();
    pub fn simulate(self: Self, time: f32) void {
        for (self.dynamic_bodies) |*ball| {
            const add = ray.Vector2Add;
            const sub = ray.Vector2Subtract;
            const mul = ray.Vector2Scale;

            // d vector
            const drag_vector = sub(self.gravity - mul(ball.velocity, self.resistance));

            // p = p + vt + (0.5t^2 - 1/6kt^3)d
            const new_position = add(
                add(ball.center, mul(ball.velocity, time)),
                mul(drag_vector, (0.5 - 0.1666666667 * self.resistance * time) * time * time),
            );

            // Derivative of above.
            // v = v + (t - 0.5kt^2)d
            const new_velocity = add(ball.velocity, mul(drag_vector, (1.0 - 0.5 * self.resistance * time) * time));

            // TODO: Collisions.
            ball.*.center = new_position;
            ball.*.velocity = new_velocity;
        }
    }
};

test "Make walls" {
    const tri = Triangle{
        .vertexes = .{
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 1 },
            .{ .x = 1, .y = 0 },
        },
    };
    _ = One_Sided_Wall.from_triangles(tri);
}
