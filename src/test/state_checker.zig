const std = @import("std");
const mem = std.mem;

const config = @import("config.zig");

const Cluster = @import("cluster.zig").Cluster;
const Network = @import("network.zig").Network;

const MessagePool = @import("../message_pool.zig").MessagePool;
const Message = MessagePool.Message;

const log = std.log.scoped(.state_checker);

pub const StateChecker = struct {
    // Indexed by client index used by Cluster
    inflight_client_messages: []?*Message,

    // Indexed by replica index
    state_machine_states: []u128,

    pub fn init(allocator: *mem.Allocator, cluster: *Cluster) !StateChecker {
        const inflight_client_messages = try allocator.alloc(?*Message, cluster.options.client_count);
        errdefer allocator.free(inflight_client_messages);

        const state_machine_states = try allocator.alloc(u128, cluster.options.replica_count);
        errdefer allocator.free(state_machine_states);

        for (cluster.state_machines) |state_machine, i| {
            state_machine_states[i] = state_machine.state;
        }

        return StateChecker{
            .inflight_client_messages = inflight_client_messages,
            .state_machine_states = state_machine_states,
        };
    }

    pub fn deinit(state_checker: *StateChecker, allocator: *mem.Allocator) void {
        allocator.free(state_checker.inflight_client_messages);
        allocator.free(state_checker.state_machine_states);
    }

    pub fn after_on_message(network: *Network, message: *Message, path: Network.Path) void {
        const cluster = @fieldParentPtr(Cluster, "network", network);
        const state_checker = &cluster.state_checker;

        // Ignore if the message is being delivered to a client
        if (path.target == .client) return;

        const a = state_checker.state_machine_states[path.target.replica];
        const b = cluster.state_machines[path.target.replica].state;

        if (b == a) return;

        log.debug("replica {} changed state={}..{}\n", .{
            path.target.replica, a, b,
        });

        state_checker.state_machine_states[path.target.replica] = b;
    }
};
