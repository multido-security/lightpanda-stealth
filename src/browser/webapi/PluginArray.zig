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
const Frame = @import("../Frame.zig");
const GenericIterator = @import("collections/iterator.zig").Entry;

pub fn registerTypes() []const type {
    return &.{ PluginArray, Plugin, PluginIterator, MimeTypeArray, MimeType, MimeTypeIterator };
}

// What desktop Chrome has exposed since it hardcoded the list (M94): five
// built-in PDF viewer plugins, each handling the same two MIME types. An
// empty navigator.plugins is a well-known headless signal.
const plugin_names = [_][]const u8{
    "PDF Viewer",
    "Chrome PDF Viewer",
    "Chromium PDF Viewer",
    "Microsoft Edge PDF Viewer",
    "WebKit built-in PDF",
};
const mime_type_names = [_][]const u8{ "application/pdf", "text/pdf" };
const pdf_description = "Portable Document Format";

// Never mutated; static so that every lookup returns the same instance (the
// identity map is keyed by address).
var plugins = blk: {
    var list: [plugin_names.len]Plugin = undefined;
    for (&list, 0..) |*p, i| p.* = .{ ._index = i };
    break :blk list;
};
var mime_types = blk: {
    var list: [mime_type_names.len]MimeType = undefined;
    for (&list, 0..) |*m, i| m.* = .{ ._index = i };
    break :blk list;
};

fn pluginAt(index: i64) ?*Plugin {
    if (index < 0 or index >= plugins.len) return null;
    return &plugins[@intCast(index)];
}

fn pluginNamed(name: []const u8) ?*Plugin {
    for (plugin_names, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) return &plugins[i];
    }
    return null;
}

fn mimeTypeAt(index: i64) ?*MimeType {
    if (index < 0 or index >= mime_types.len) return null;
    return &mime_types[@intCast(index)];
}

fn mimeTypeNamed(name: []const u8) ?*MimeType {
    for (mime_type_names, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) return &mime_types[i];
    }
    return null;
}

fn indexes(comptime len: usize, frame: *Frame) !js.Array {
    var arr = frame.js.local.?.newArray(len);
    for (0..len) |i| {
        _ = try arr.set(@intCast(i), i, .{});
    }
    return arr;
}

const PluginArray = @This();

_pad: bool = false,

pub fn refresh(_: *const PluginArray) void {}
pub fn getAtIndex(_: *const PluginArray, index: usize) ?*Plugin {
    return pluginAt(@intCast(index));
}

pub fn getByName(_: *const PluginArray, name: []const u8) ?*Plugin {
    return pluginNamed(name);
}

fn values(_: *const PluginArray, frame: *Frame) !*PluginIterator {
    return .init(.{}, frame);
}

const PluginIterator = GenericIterator(struct {
    index: usize = 0,
    pub fn next(self: *@This(), _: *Frame) ?*Plugin {
        const p = pluginAt(@intCast(self.index)) orelse return null;
        self.index += 1;
        return p;
    }
}, null);

pub const Plugin = struct {
    _index: usize,

    fn getName(self: *const Plugin) []const u8 {
        return plugin_names[self._index];
    }

    fn getFilename(_: *const Plugin) []const u8 {
        return "internal-pdf-viewer";
    }

    fn getDescription(_: *const Plugin) []const u8 {
        return pdf_description;
    }

    fn item(_: *const Plugin, index: i64) ?*MimeType {
        return mimeTypeAt(index);
    }

    fn getAtIndex(_: *const Plugin, index: usize) ?*MimeType {
        return mimeTypeAt(@intCast(index));
    }

    fn namedItem(_: *const Plugin, name: []const u8) ?*MimeType {
        return mimeTypeNamed(name);
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(Plugin);
        pub const Meta = struct {
            pub const name = "Plugin";
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const name = bridge.accessor(Plugin.getName, null, .{});
        pub const filename = bridge.accessor(Plugin.getFilename, null, .{});
        pub const description = bridge.accessor(Plugin.getDescription, null, .{});
        pub const length = bridge.property(mime_type_names.len, .{ .template = false });
        pub const item = bridge.function(Plugin.item, .{});
        pub const namedItem = bridge.function(Plugin.namedItem, .{});
        pub const @"[int]" = bridge.indexed(Plugin.getAtIndex, struct {
            fn wrap(_: *const Plugin, frame: *Frame) !js.Array {
                return indexes(mime_type_names.len, frame);
            }
        }.wrap, .{ .null_as_undefined = true });
        pub const @"[str]" = bridge.namedIndexed(Plugin.namedItem, null, null, null, struct {
            fn wrap(_: *const Plugin, key: []const u8) !u32 {
                if (mimeTypeNamed(key) == null) return error.NotHandled;
                return js.v8.None;
            }
        }.wrap, .{ .null_as_undefined = true });
    };
};

/// navigator.mimeTypes
pub const MimeTypeArray = struct {
    _pad: bool = false,

    fn getAtIndex(_: *const MimeTypeArray, index: usize) ?*MimeType {
        return mimeTypeAt(@intCast(index));
    }

    fn item(_: *const MimeTypeArray, index: i64) ?*MimeType {
        return mimeTypeAt(index);
    }

    fn namedItem(_: *const MimeTypeArray, name: []const u8) ?*MimeType {
        return mimeTypeNamed(name);
    }

    fn values(_: *const MimeTypeArray, frame: *Frame) !*MimeTypeIterator {
        return .init(.{}, frame);
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MimeTypeArray);
        pub const Meta = struct {
            pub const name = "MimeTypeArray";
            pub var class_id: bridge.ClassId = undefined;
            pub const empty_with_no_proto = true;
        };

        pub const length = bridge.property(mime_type_names.len, .{ .template = false });
        pub const item = bridge.function(MimeTypeArray.item, .{});
        pub const namedItem = bridge.function(MimeTypeArray.namedItem, .{});
        pub const @"[int]" = bridge.indexed(MimeTypeArray.getAtIndex, struct {
            fn wrap(_: *const MimeTypeArray, frame: *Frame) !js.Array {
                return indexes(mime_type_names.len, frame);
            }
        }.wrap, .{ .null_as_undefined = true });
        pub const @"[str]" = bridge.namedIndexed(MimeTypeArray.namedItem, null, null, null, struct {
            fn wrap(_: *const MimeTypeArray, key: []const u8) !u32 {
                if (mimeTypeNamed(key) == null) return error.NotHandled;
                return js.v8.None;
            }
        }.wrap, .{ .null_as_undefined = true });
        pub const symbol_iterator = bridge.iterator(MimeTypeArray.values, .{});
    };
};

const MimeTypeIterator = GenericIterator(struct {
    index: usize = 0,
    pub fn next(self: *@This(), _: *Frame) ?*MimeType {
        const m = mimeTypeAt(@intCast(self.index)) orelse return null;
        self.index += 1;
        return m;
    }
}, null);

pub const MimeType = struct {
    _index: usize,

    fn getType(self: *const MimeType) []const u8 {
        return mime_type_names[self._index];
    }

    fn getSuffixes(_: *const MimeType) []const u8 {
        return "pdf";
    }

    fn getDescription(_: *const MimeType) []const u8 {
        return pdf_description;
    }

    // Chrome points every PDF MIME type at the first plugin.
    fn getEnabledPlugin(_: *const MimeType) *Plugin {
        return &plugins[0];
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MimeType);
        pub const Meta = struct {
            pub const name = "MimeType";
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const @"type" = bridge.accessor(MimeType.getType, null, .{});
        pub const suffixes = bridge.accessor(MimeType.getSuffixes, null, .{});
        pub const description = bridge.accessor(MimeType.getDescription, null, .{});
        pub const enabledPlugin = bridge.accessor(MimeType.getEnabledPlugin, null, .{});
    };
};

pub const JsApi = struct {
    pub const bridge = js.Bridge(PluginArray);

    pub const Meta = struct {
        pub const name = "PluginArray";
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const length = bridge.property(plugin_names.len, .{ .template = false });
    pub const refresh = bridge.function(PluginArray.refresh, .{});
    pub const @"[int]" = bridge.indexed(PluginArray.getAtIndex, struct {
        fn wrap(_: *const PluginArray, frame: *Frame) !js.Array {
            return indexes(plugin_names.len, frame);
        }
    }.wrap, .{ .null_as_undefined = true });
    pub const @"[str]" = bridge.namedIndexed(PluginArray.getByName, null, null, null, struct {
        fn wrap(_: *const PluginArray, key: []const u8) !u32 {
            if (pluginNamed(key) == null) return error.NotHandled;
            return js.v8.None;
        }
    }.wrap, .{ .null_as_undefined = true });

    pub const item = bridge.function(struct {
        fn wrap(_: *const PluginArray, index: i64) ?*Plugin {
            return pluginAt(index);
        }
    }.wrap, .{});

    pub const namedItem = bridge.function(PluginArray.getByName, .{});
    pub const symbol_iterator = bridge.iterator(PluginArray.values, .{});
};
