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

//! Build-time patch of libcurl's lib/http2.c so the HTTP/2 connection looks
//! like Chrome's (the "Akamai" HTTP/2 fingerprint
//! `1:65536;2:0;4:6291456;6:262144|15663105|0|m,a,s,p`):
//! - SETTINGS: HEADER_TABLE_SIZE 65536, ENABLE_PUSH 0, INITIAL_WINDOW_SIZE
//!   6291456, MAX_HEADER_LIST_SIZE 262144 (libcurl sends
//!   MAX_CONCURRENT_STREAMS, a 64KiB window and ENABLE_PUSH);
//! - a connection window of 15MiB, i.e. a WINDOW_UPDATE of 15663105;
//! - pseudo-headers in Chrome's :method, :authority, :scheme, :path order;
//! - HEADERS carrying Chrome's priority (exclusive, weight 256).
//!
//! Each replacement must match exactly once, so a libcurl upgrade that moves
//! the code fails the build here instead of silently dropping a change.
//!
//! Usage: patch_curl_http2 <in http2.c> <out http2.c>

const std = @import("std");

const Replacement = struct { old: []const u8, new: []const u8 };

const replacements = [_]Replacement{
    .{
        .old = "#define H2_STREAM_WINDOW_SIZE_INITIAL  (64 * 1024)",
        .new = "#define H2_STREAM_WINDOW_SIZE_INITIAL  (6 * 1024 * 1024) /* lightpanda: Chrome */",
    },
    .{
        .old = "#define HTTP2_HUGE_WINDOW_SIZE (100 * H2_STREAM_WINDOW_SIZE_MAX)",
        .new = "#define HTTP2_HUGE_WINDOW_SIZE (15 * 1024 * 1024) /* lightpanda: Chrome */",
    },
    .{
        .old = "#define H2_SETTINGS_IV_LEN 3",
        .new = "#define H2_SETTINGS_IV_LEN 4",
    },
    .{
        .old =
        \\  iv[0].settings_id = NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS;
        \\  iv[0].value = Curl_multi_max_concurrent_streams(data->multi);
        \\
        \\  iv[1].settings_id = NGHTTP2_SETTINGS_INITIAL_WINDOW_SIZE;
        \\  iv[1].value = cf_h2_initial_win_size(data);
        \\  if(ctx)
        \\    ctx->initial_win_size = iv[1].value;
        \\  iv[2].settings_id = NGHTTP2_SETTINGS_ENABLE_PUSH;
        \\  iv[2].value = !!data->multi->push_cb;
        \\
        \\  return 3;
        ,
        .new =
        \\  /* lightpanda: Chrome's SETTINGS, in Chrome's order */
        \\  iv[0].settings_id = NGHTTP2_SETTINGS_HEADER_TABLE_SIZE;
        \\  iv[0].value = 65536;
        \\  iv[1].settings_id = NGHTTP2_SETTINGS_ENABLE_PUSH;
        \\  iv[1].value = 0;
        \\  iv[2].settings_id = NGHTTP2_SETTINGS_INITIAL_WINDOW_SIZE;
        \\  iv[2].value = cf_h2_initial_win_size(data);
        \\  if(ctx)
        \\    ctx->initial_win_size = iv[2].value;
        \\  iv[3].settings_id = NGHTTP2_SETTINGS_MAX_HEADER_LIST_SIZE;
        \\  iv[3].value = 262144;
        \\
        \\  return 4;
        ,
    },
    .{
        .old =
        \\  nva = Curl_dynhds_to_nva(&h2_headers, &nheader);
        \\  if(!nva) {
        \\    result = CURLE_OUT_OF_MEMORY;
        \\    goto out;
        \\  }
        \\
        \\  h2_pri_spec(data, &pri_spec);
        ,
        .new =
        \\  nva = Curl_dynhds_to_nva(&h2_headers, &nheader);
        \\  if(!nva) {
        \\    result = CURLE_OUT_OF_MEMORY;
        \\    goto out;
        \\  }
        \\
        \\  /* lightpanda: Chrome sends :method, :authority, :scheme, :path
        \\   * (libcurl: :method, :scheme, :authority, :path). */
        \\  if(nheader >= 3 &&
        \\     nva[1].namelen == 7 && !memcmp(nva[1].name, ":scheme", 7) &&
        \\     nva[2].namelen == 10 && !memcmp(nva[2].name, ":authority", 10)) {
        \\    nghttp2_nv tmp = nva[1];
        \\    nva[1] = nva[2];
        \\    nva[2] = tmp;
        \\  }
        \\
        \\  h2_pri_spec(data, &pri_spec);
        \\  /* lightpanda: Chrome's HEADERS priority */
        \\  nghttp2_priority_spec_init(&pri_spec, 0, 256, 1);
        ,
    },
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const in_path = args.next() orelse return error.Usage;
    const out_path = args.next() orelse return error.Usage;

    const cwd = std.Io.Dir.cwd();
    var source: []const u8 = try cwd.readFileAlloc(io, in_path, gpa, .unlimited);

    for (replacements) |r| {
        const count = std.mem.count(u8, source, r.old);
        if (count != 1) {
            std.debug.print("patch_curl_http2: expected 1 match, found {d}:\n{s}\n", .{ count, r.old });
            return error.PatchMismatch;
        }
        source = try std.mem.replaceOwned(u8, gpa, source, r.old, r.new);
    }

    try cwd.writeFile(io, .{ .sub_path = out_path, .data = source });
}
