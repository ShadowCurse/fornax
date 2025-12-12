const std = @import("std");

total_threads: u32 = 0,
count: std.atomic.Value(u32) = .init(0),
futex: std.atomic.Value(u32) = .init(0),

const Self = @This();

pub fn wait(self: *Self) void {
    const current_futex = self.futex.load(.acquire);
    const count = self.count.fetchAdd(1, .acq_rel) + 1;
    if (count == self.total_threads) {
        self.futex.store(current_futex + 1, .release);
        std.Thread.Futex.wake(&self.futex, self.total_threads - 1);
        return;
    }
    while (self.futex.load(.acquire) == current_futex) {
        std.Thread.Futex.wait(&self.futex, current_futex);
    }
}
