const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;

const config = @import("config.zig");

const Cluster = @import("test/cluster.zig").Cluster;
const StateChecker = @import("test/state_checker.zig").StateChecker;

const StateMachine = @import("test/state_machine.zig").StateMachine;
const MessageBus = @import("test/message_bus.zig").MessageBus;

const vr = @import("vr.zig");
const Header = vr.Header;
const Client = vr.Client(StateMachine, MessageBus);

test "VR" {
    // TODO: use std.testing.allocator when all leaks are fixed.
    const allocator = std.heap.page_allocator;
    var prng = std.rand.DefaultPrng.init(0xABEE11E);

    const cluster = try Cluster.create(allocator, &prng.random, .{
        .cluster = 42,
        .replica_count = 3,
        .client_count = 1,
        .seed = prng.random.int(u64),
        .network_options = .{
            .after_on_message = StateChecker.after_on_message,
            .packet_simulator_options = .{
                .node_count = 4,
                .prng_seed = prng.random.int(u64),
                .one_way_delay_mean = 25,
                .one_way_delay_min = 10,
                .packet_loss_probability = 10,
                .path_maximum_capacity = 20,
                .path_clog_duration_mean = 200,
                .path_clog_probability = 2,
                .packet_replay_probability = 2,
            },
        },
    });
    defer cluster.destroy();

    cluster.state_checker = try StateChecker.init(allocator, cluster);
    defer cluster.state_checker.deinit(allocator);

    var tick: u64 = 0;
    while (tick < 15_000) : (tick += 1) {
        for (cluster.replicas) |*replica, i| replica.tick();

        cluster.network.packet_simulator.tick();

        for (cluster.clients) |*client| client.tick();

        if (tick == 5000) {
            const client = &cluster.clients[0];
            const message = client.get_message() orelse {
                @panic("Client message pool has been exhausted. Cannot execute batch.");
            };
            defer client.unref(message);

            std.mem.copy(
                u8,
                message.buffer[@sizeOf(Header)..],
                // TODO: this should have a random length as well, with
                // common 0-length and max-length messages
                &[_]u8{prng.random.int(u8)},
            );

            client.request(0, client_callback, .hash, message, 1);
        }
    }
}

fn client_callback(
    user_data: u128,
    operation: StateMachine.Operation,
    results: Client.Error![]const u8,
) void {
    assert(user_data == 0);
}
