const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const rand = std.rand;

pub const MazeAlgorithms = enum {
    Default,
    RecursiveBacktracker,
};

// A graph is mathematically a set of nodes and edges
// however this is a graph which also has a set of "adjacents"
// which are the potential nodes of a graph.
// Adjacent/Edge to self is a blank spot. Blanks are always at the end.
pub const Graph = struct {
    num_nodes: NodeType,
    adjacents: []EdgeType, // Cells to which we have a Potential Edge
    edges: []EdgeType, // Cells to which we have a Defined Edge
    allocator: Allocator,

    const Self = @This();

    const MAX_ADJACENTS = 6; // We allow upto 6 adjacent cells.
    const NodeType = u16; // Nodes are identified as a u16, maximum 2^16 nodes in a graph.
    const EdgeType = [MAX_ADJACENTS]NodeType;

    pub fn init(alloctor: Allocator, num_nodes: u16) !Self {
        // First create the edges and adjacents.
        const adjacents = try alloctor.alloc(EdgeType, num_nodes);
        errdefer alloctor.free(adjacents);

        const edges = try alloctor.alloc(EdgeType, num_nodes);
        errdefer alloctor.free(edges);

        for (0..num_nodes) |i| {
            for (0..MAX_ADJACENTS) |j| {
                adjacents[i][j] = @intCast(NodeType, i);
                edges[i][j] = @intCast(NodeType, i);
            }
        }

        return Self{
            .num_nodes = num_nodes,
            .adjacents = adjacents,
            .edges = edges,
            .allocator = alloctor,
        };
    }

    pub fn deinit(self: *const Self) void {
        self.allocator.free(self.adjacents);
        self.allocator.free(self.edges);
    }

    pub fn num_adjacents(self: Self, node: NodeType) NodeType {
        var i: NodeType = 0;
        while (i < MAX_ADJACENTS) : (i += 1) {
            // if you find an adjacent to ourself.
            if (self.adjacents[node][i] == node) break;
        }
        return i;
    }

    pub fn num_edges(self: Self, node: NodeType) NodeType {
        var i: NodeType = 0;
        while (i < MAX_ADJACENTS) : (i += 1) {
            // if you find an adjacent to ourself.
            if (self.edges[node][i] == node) break;
        }
        return i;
    }

    pub fn get_adjacents(self: Self, node: NodeType) []NodeType {
        return self.adjacents[node][0..self.num_adjacents(node)];
    }

    pub fn get_edges(self: Self, node: NodeType) []NodeType {
        return self.edges[node][0..self.num_edges(node)];
    }

    pub fn is_adjacent(self: Self, node0: NodeType, node1: NodeType) bool {
        if (node0 == node1) return true;
        for (self.adjacents[node0]) |other| {
            if (other == node1) return true;
        }
        return false;
    }

    pub fn is_edge(self: Self, node0: NodeType, node1: NodeType) bool {
        if (node0 == node1) return true;
        for (self.edges[node0]) |other| {
            if (other == node1) return true;
        }
        return false;
    }

    pub fn make_adjacent(self: Self, node0: NodeType, node1: NodeType) void {
        // Note: Adds to both sides, and ensures its not a duplicate.
        if (self.is_adjacent(node0, node1)) return;
        self.adjacents[node0][self.num_adjacents(node0)] = node1;
        self.adjacents[node1][self.num_adjacents(node1)] = node0;
    }

    pub fn make_edges(self: Self, node0: NodeType, node1: NodeType) void {
        // Note: Adds to both sides, and ensures its not a duplicate.
        if (self.is_edge(node0, node1)) return;
        self.edges[node0][self.num_edges(node0)] = node1;
        self.edges[node1][self.num_edges(node1)] = node0;
    }
};

// Make a maze out of a graph using an algorithm.
// Modifies existing edges, adjacents aren't changed.
// Starts at node 0.
pub fn mazeify_graph(graph: Graph, algo: MazeAlgorithms, allocator: Allocator) !void {
    var seed: u64 = undefined;
    try std.os.getrandom(std.mem.asBytes(&seed));
    var prng = std.rand.DefaultPrng.init(seed);
    const random = prng.random();

    switch (algo) {
        .RecursiveBacktracker, .Default => try recursive_backtracker(graph, allocator, random),
    }
}

pub const SquareMaze = struct {
    height: usize,
    width: usize,
    graph: Graph,

    const Self = @This();

    pub fn init(allocator: Allocator, height: usize, width: usize) !Self {
        // Degenerate mazes disallowed.
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);

        const graph = try Graph.init(allocator, @intCast(Graph.NodeType, width * height));
        const square = Self{
            .width = width,
            .height = height,
            .graph = graph,
        };

        // Connect things together.
        for (0..height) |i| {
            for (0..width) |j| {
                // Adjacent to right and below, unless on right or bottom edges.
                if (j + 1 != width) graph.make_adjacent(square.index(i, j), square.index(i, j + 1));
                if (i + 1 != height) graph.make_adjacent(square.index(i, j), square.index(i + 1, j));
            }
        }

        return square;
    }

    pub fn deinit(self: Self) void {
        self.graph.deinit();
    }

    pub fn index(self: Self, row: usize, col: usize) Graph.NodeType {
        std.debug.assert(col < self.width);
        std.debug.assert(row < self.height);
        return @intCast(Graph.NodeType, col + row * self.width);
    }
};

// Algorithms for mazes.
fn recursive_backtracker(graph: Graph, allocator: Allocator, random: rand.Random) !void {
    // Degenerate graph.
    std.debug.assert(graph.num_nodes != 0);

    var visited = try std.DynamicBitSet.initEmpty(allocator, graph.num_nodes);
    defer visited.deinit();

    // Rather than recursing completely, we allocate a stack so that we don't go overboard.
    var stack = try std.ArrayList(Graph.NodeType).initCapacity(allocator, graph.num_nodes);
    defer stack.deinit();

    // Always start at 0, we could choose a starting point randomly but it doesn't really matter.
    stack.appendAssumeCapacity(0);
    // We have visited 0.
    visited.set(0);

    while (stack.getLastOrNull()) |visiting| {
        // See if we have some unvisited adjacents.
        const adjacents = graph.get_adjacents(visiting);

        var unvisited_buff: [Graph.MAX_ADJACENTS]Graph.NodeType = undefined;
        var num_unvisited: usize = 0;

        for (adjacents) |adjacent| {
            if (!visited.isSet(adjacent)) {
                unvisited_buff[num_unvisited] = adjacent;
                num_unvisited += 1;
            }
        }

        if (num_unvisited > 0) {
            // If we have an unvisited neighbour, then randomly pick one and recurse.
            // While also carving an edge to it.
            const next_visit = unvisited_buff[random.uintLessThan(usize, num_unvisited)];
            graph.make_edges(visiting, next_visit);
            stack.appendAssumeCapacity(next_visit);
            visited.set(next_visit);
        } else {
            // Dead end, we must pop and repeat.
            _ = stack.pop();
        }
    }

    // For this to be a proper maze, there shouldn't be any unvisited nodes. If there are then we have a bug.
    // Or the graph is disconnected because it is not a spanning tree.
    std.debug.assert(visited.count() == visited.capacity());
}

test "Graph initialization" {
    const allocator = testing.allocator;

    const graph_size = 128;
    const graph = try Graph.init(allocator, graph_size);
    defer graph.deinit();

    try testing.expectEqual(graph.adjacents.len, graph_size);
    try testing.expectEqual(graph.edges.len, graph_size);
}

test "Graph adjacents and Edges" {
    const allocator = testing.allocator;

    const graph_size = 128;
    const graph = try Graph.init(allocator, graph_size);
    defer graph.deinit();

    // All should be 0.
    for (0..graph.num_nodes) |i| {
        try testing.expectEqual(graph.num_edges(@intCast(Graph.NodeType, i)), 0);
        try testing.expectEqual(graph.num_adjacents(@intCast(Graph.NodeType, i)), 0);
    }

    graph.make_adjacent(2, 3);
    graph.make_adjacent(3, 4);
    graph.make_adjacent(1, 2);
    graph.make_adjacent(1, 1);
    graph.make_adjacent(2, 1);

    graph.make_edges(3, 4);
    graph.make_edges(4, 5);
    graph.make_edges(2, 3);
    graph.make_edges(2, 2);
    graph.make_edges(3, 2);

    try std.testing.expect(!graph.is_adjacent(1, 3));
    try std.testing.expect(graph.is_adjacent(1, 2));
    try std.testing.expect(graph.is_adjacent(2, 3));
    try std.testing.expect(graph.is_adjacent(3, 4));

    try std.testing.expect(!graph.is_edge(2, 4));
    try std.testing.expect(graph.is_edge(2, 3));
    try std.testing.expect(graph.is_edge(3, 4));
    try std.testing.expect(graph.is_edge(5, 4));

    try std.testing.expectEqual(graph.num_adjacents(1), 1);
    try std.testing.expectEqual(graph.num_adjacents(2), 2);
    try std.testing.expectEqual(graph.num_adjacents(3), 2);
    try std.testing.expectEqual(graph.num_adjacents(4), 1);

    try std.testing.expectEqual(graph.num_edges(2), 1);
    try std.testing.expectEqual(graph.num_edges(3), 2);
    try std.testing.expectEqual(graph.num_edges(4), 2);
    try std.testing.expectEqual(graph.num_edges(5), 1);
}

test "Make Maze" {
    const allocator = testing.allocator;

    const width = 127;
    const height = 128;

    const maze = try SquareMaze.init(allocator, height, width);
    defer maze.deinit();

    try mazeify_graph(maze.graph, .Default, allocator);
}
