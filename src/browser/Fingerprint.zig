// Copyright (C) 2023-2026  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

//! The device a Lightpanda process presents as: hardware and screen values
//! that real desktop Chrome installs commonly report. One profile is picked
//! at random per process (App.init), so separate instances don't share an
//! identical fingerprint, while everything a single instance reports, in
//! every frame and worker, stays consistent. Values are drawn from common
//! real-world configurations rather than noise: implausible or
//! self-contradicting values are what fingerprinting scripts look for.

const std = @import("std");
const builtin = @import("builtin");
const lp = @import("lightpanda");

const Fingerprint = @This();

hardware_concurrency: u32,
// navigator.deviceMemory: Chrome reports a power of two, capped at 8.
device_memory: f64,
// Picks among the screens that fit the viewport, see screenFor.
screen_seed: u32,
// Index into `gpus`.
gpu_index: usize,

/// What a process reports until randomize() runs (and what tests use).
pub const default: Fingerprint = .{
    .hardware_concurrency = 8,
    .device_memory = 8,
    .screen_seed = 0,
    .gpu_index = 0,
};

var current: Fingerprint = default;

pub fn get() *const Fingerprint {
    return &current;
}

/// Picks this process's profile. Call once, before any page runs.
pub fn randomize() void {
    var seed: u64 = undefined;
    lp.io.random(std.mem.asBytes(&seed));
    current = generate(seed);
}

/// Restores the deterministic profile (tests).
pub fn reset() void {
    current = default;
}

fn generate(seed: u64) Fingerprint {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    // Weighted towards the most common desktop core counts.
    const cores = [_]u32{ 4, 8, 8, 8, 12, 12, 16, 16 };
    const hardware_concurrency = cores[random.uintLessThan(usize, cores.len)];

    // Machines with few cores more often have less RAM.
    const device_memory: f64 = if (hardware_concurrency <= 4 and random.boolean()) 4 else 8;

    return .{
        .hardware_concurrency = hardware_concurrency,
        .device_memory = device_memory,
        .screen_seed = random.int(u32),
        .gpu_index = random.uintLessThan(usize, gpus.len),
    };
}

/// The GPU as WEBGL_debug_renderer_info reports it. Chrome renders through
/// ANGLE, so both strings name ANGLE's backend for the platform.
pub const Gpu = struct {
    vendor: []const u8,
    renderer: []const u8,
};

pub fn gpu(self: *const Fingerprint) Gpu {
    return gpus[self.gpu_index];
}

const gpus: []const Gpu = switch (builtin.target.os.tag) {
    .macos => &.{
        .{ .vendor = "Google Inc. (Apple)", .renderer = "ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)" },
        .{ .vendor = "Google Inc. (Apple)", .renderer = "ANGLE (Apple, ANGLE Metal Renderer: Apple M2, Unspecified Version)" },
        .{ .vendor = "Google Inc. (Apple)", .renderer = "ANGLE (Apple, ANGLE Metal Renderer: Apple M3, Unspecified Version)" },
    },
    .windows => &.{
        .{ .vendor = "Google Inc. (Intel)", .renderer = "ANGLE (Intel, Intel(R) UHD Graphics 630 (0x00003E92) Direct3D11 vs_5_0 ps_5_0, D3D11)" },
        .{ .vendor = "Google Inc. (Intel)", .renderer = "ANGLE (Intel, Intel(R) Iris(R) Xe Graphics (0x00009A49) Direct3D11 vs_5_0 ps_5_0, D3D11)" },
        .{ .vendor = "Google Inc. (NVIDIA)", .renderer = "ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 (0x00002504) Direct3D11 vs_5_0 ps_5_0, D3D11)" },
        .{ .vendor = "Google Inc. (AMD)", .renderer = "ANGLE (AMD, AMD Radeon(TM) Graphics (0x00001638) Direct3D11 vs_5_0 ps_5_0, D3D11)" },
    },
    else => &.{
        .{ .vendor = "Google Inc. (Intel)", .renderer = "ANGLE (Intel, Mesa Intel(R) UHD Graphics 630 (CFL GT2), OpenGL 4.6)" },
        .{ .vendor = "Google Inc. (Intel)", .renderer = "ANGLE (Intel, Mesa Intel(R) Xe Graphics (TGL GT2), OpenGL 4.6)" },
        .{ .vendor = "Google Inc. (AMD)", .renderer = "ANGLE (AMD, AMD Radeon Graphics (radeonsi, renoir, LLVM 15.0.7, DRM 3.54, 6.5.0-35-generic), OpenGL 4.6)" },
    },
};

/// Height of Chrome's tab strip and toolbar: window.outerHeight minus
/// window.innerHeight for a regular (non-fullscreen) window.
pub const window_chrome_height: u32 = switch (builtin.target.os.tag) {
    .macos => 80,
    .windows => 87,
    else => 85,
};

/// Space the OS keeps for itself (taskbar, menu bar, top panel): screen.height
/// minus screen.availHeight.
pub const os_reserved_height: u32 = switch (builtin.target.os.tag) {
    .macos => 25,
    .windows => 48,
    else => 32,
};

pub const Screen = struct {
    width: u32,
    height: u32,

    pub fn availHeight(self: Screen) u32 {
        return self.height -| os_reserved_height;
    }
};

// Common desktop resolutions (CSS px), most common first.
const screens = [_]Screen{
    .{ .width = 1920, .height = 1080 },
    .{ .width = 2560, .height = 1440 },
    .{ .width = 1536, .height = 864 },
    .{ .width = 1366, .height = 768 },
    .{ .width = 1440, .height = 900 },
    .{ .width = 1920, .height = 1200 },
    .{ .width = 2560, .height = 1600 },
    .{ .width = 1680, .height = 1050 },
    .{ .width = 3440, .height = 1440 },
};

/// The screen for a viewport of `width` x `height`: one of the common
/// resolutions large enough to hold a Chrome window of that size, picked by
/// the profile so that it is stable for a given viewport. A viewport too
/// large for all of them gets a screen just big enough.
pub fn screenFor(self: *const Fingerprint, width: u32, height: u32) Screen {
    const needed_height = height + window_chrome_height + os_reserved_height;

    var fitting: [screens.len]Screen = undefined;
    var count: usize = 0;
    for (screens) |s| {
        if (s.width >= width and s.height >= needed_height) {
            fitting[count] = s;
            count += 1;
        }
    }
    if (count == 0) {
        return .{ .width = width, .height = needed_height };
    }
    return fitting[self.screen_seed % count];
}

const testing = std.testing;

test "Fingerprint: generated profiles are plausible" {
    var seed: u64 = 0;
    while (seed < 256) : (seed += 1) {
        const fp = generate(seed);
        try testing.expect(fp.hardware_concurrency >= 4 and fp.hardware_concurrency <= 16);
        try testing.expect(fp.device_memory == 4 or fp.device_memory == 8);
    }
}

test "Fingerprint: screenFor holds the window" {
    var fp = default;
    var seed: u32 = 0;
    while (seed < 64) : (seed += 1) {
        fp.screen_seed = seed;
        const s = fp.screenFor(1920, 1080);
        try testing.expect(s.width >= 1920);
        try testing.expect(s.availHeight() >= 1080 + window_chrome_height);

        const small = fp.screenFor(800, 600);
        try testing.expect(small.width >= 800);
    }
    // Larger than every candidate.
    const huge = fp.screenFor(5000, 3000);
    try testing.expectEqual(5000, huge.width);
    try testing.expectEqual(3000 + window_chrome_height + os_reserved_height, huge.height);
}
