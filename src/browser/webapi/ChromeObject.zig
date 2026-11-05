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

//! window.chrome, as desktop Chrome exposes it to a regular web page:
//! `loadTimes`, `csi` and `app` (`runtime` only appears with extensions
//! installed that list the page as externally connectable). Its absence is
//! one of the most common headless-browser checks.

const js = @import("../js/js.zig");
const Frame = @import("../Frame.zig");

pub fn registerTypes() []const type {
    return &.{ ChromeObject, App };
}

const ChromeObject = @This();
_pad: bool = false,

pub const init: ChromeObject = .{};

// Never mutated; static so chrome.app is the same object on every access.
var app: App = .{};

fn getApp(_: *const ChromeObject) *App {
    return &app;
}

// Seconds since the Unix epoch, as chrome.loadTimes reports them.
fn timeOriginSeconds(frame: *Frame) f64 {
    return @as(f64, @floatFromInt(frame.window._performance._time_origin_unix)) / 1_000_000.0;
}

fn nowSeconds(frame: *Frame) f64 {
    return timeOriginSeconds(frame) + frame.window._performance.now() / 1000.0;
}

/// Deprecated Chrome-only navigation timing, in seconds since the epoch.
fn loadTimes(_: *const ChromeObject, frame: *Frame) struct {
    requestTime: f64,
    startLoadTime: f64,
    commitLoadTime: f64,
    finishDocumentLoadTime: f64,
    finishLoadTime: f64,
    firstPaintTime: f64,
    firstPaintAfterLoadTime: f64,
    navigationType: []const u8,
    wasFetchedViaSpdy: bool,
    wasNpnNegotiated: bool,
    npnNegotiatedProtocol: []const u8,
    wasAlternateProtocolAvailable: bool,
    connectionInfo: []const u8,
} {
    const origin = timeOriginSeconds(frame);
    const now = nowSeconds(frame);
    return .{
        .requestTime = origin,
        .startLoadTime = origin,
        .commitLoadTime = origin + 0.05,
        .finishDocumentLoadTime = @max(origin + 0.1, now),
        .finishLoadTime = @max(origin + 0.12, now),
        .firstPaintTime = origin + 0.11,
        .firstPaintAfterLoadTime = 0,
        .navigationType = "Other",
        .wasFetchedViaSpdy = true,
        .wasNpnNegotiated = true,
        .npnNegotiatedProtocol = "h2",
        .wasAlternateProtocolAvailable = false,
        .connectionInfo = "h2",
    };
}

/// Deprecated Chrome-only timing: milliseconds.
fn csi(_: *const ChromeObject, frame: *Frame) struct {
    startE: f64,
    onloadT: f64,
    pageT: f64,
    tran: u32,
} {
    const origin_ms = timeOriginSeconds(frame) * 1000.0;
    const elapsed = frame.window._performance.now();
    return .{
        .startE = @floor(origin_ms),
        .onloadT = @floor(origin_ms + @min(elapsed, 120)),
        .pageT = elapsed,
        .tran = 15,
    };
}

/// chrome.app: the legacy hosted-app API, present on every page.
pub const App = struct {
    _pad: bool = false,

    fn getDetails(_: *const App) ?bool {
        return null;
    }

    fn getIsInstalled(_: *const App) bool {
        return false;
    }

    fn runningState(_: *const App) []const u8 {
        return "cannot_run";
    }

    fn getInstallState(_: *const App) struct { DISABLED: []const u8, INSTALLED: []const u8, NOT_INSTALLED: []const u8 } {
        return .{ .DISABLED = "disabled", .INSTALLED = "installed", .NOT_INSTALLED = "not_installed" };
    }

    fn getRunningState(_: *const App) struct { CANNOT_RUN: []const u8, READY_TO_RUN: []const u8, RUNNING: []const u8 } {
        return .{ .CANNOT_RUN = "cannot_run", .READY_TO_RUN = "ready_to_run", .RUNNING = "running" };
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(App);

        pub const Meta = struct {
            pub const name = "ChromeApp";
            // A plain object in Chrome.
            pub const class_string = "Object";
            pub const namespace = true;
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
        };

        pub const isInstalled = bridge.property(false, .{ .template = false });
        pub const getDetails = bridge.function(App.getDetails, .{});
        pub const getIsInstalled = bridge.function(App.getIsInstalled, .{});
        pub const runningState = bridge.function(App.runningState, .{});
        pub const InstallState = bridge.accessor(App.getInstallState, null, .{});
        pub const RunningState = bridge.accessor(App.getRunningState, null, .{});
    };
};

pub const JsApi = struct {
    pub const bridge = js.Bridge(ChromeObject);

    pub const Meta = struct {
        pub const name = "Chrome";
        // A plain object in Chrome.
        pub const class_string = "Object";
        pub const namespace = true;
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const loadTimes = bridge.function(ChromeObject.loadTimes, .{});
    pub const csi = bridge.function(ChromeObject.csi, .{});
    pub const app = bridge.accessor(ChromeObject.getApp, null, .{});
};

const testing = @import("../../testing.zig");
test "WebApi: window.chrome" {
    try testing.htmlRunner("window/chrome.html", .{});
}
