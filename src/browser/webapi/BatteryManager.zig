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
const std = @import("std");
const js = @import("../js/js.zig");

const EventTarget = @import("EventTarget.zig");

const Execution = js.Execution;

// https://w3c.github.io/battery/#the-batterymanager-interface
//
// What Chrome reports on a desktop (no battery): plugged in and full. A
// missing navigator.getBattery is a Firefox/Safari trait that contradicts a
// Chrome user agent.
const BatteryManager = @This();

pub const Proto = EventTarget;

_proto: *EventTarget,

pub fn init(exec: *Execution) !*BatteryManager {
    return exec._factory.eventTarget(BatteryManager{ ._proto = undefined });
}

pub fn asEventTarget(self: *BatteryManager) *EventTarget {
    return self._proto;
}

fn getCharging(_: *const BatteryManager) bool {
    return true;
}

fn getChargingTime(_: *const BatteryManager) f64 {
    return 0;
}

fn getDischargingTime(_: *const BatteryManager) f64 {
    return std.math.inf(f64);
}

fn getLevel(_: *const BatteryManager) f64 {
    return 1;
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(BatteryManager);

    pub const Meta = struct {
        pub const name = "BatteryManager";
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const charging = bridge.accessor(BatteryManager.getCharging, null, .{});
    pub const chargingTime = bridge.accessor(BatteryManager.getChargingTime, null, .{});
    pub const dischargingTime = bridge.accessor(BatteryManager.getDischargingTime, null, .{});
    pub const level = bridge.accessor(BatteryManager.getLevel, null, .{});
    pub const onchargingchange = EventTarget.handlerAccessor(BatteryManager, "chargingchange");
    pub const onchargingtimechange = EventTarget.handlerAccessor(BatteryManager, "chargingtimechange");
    pub const ondischargingtimechange = EventTarget.handlerAccessor(BatteryManager, "dischargingtimechange");
    pub const onlevelchange = EventTarget.handlerAccessor(BatteryManager, "levelchange");
};
