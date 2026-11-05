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

//! A WebGL 1 context that renders nothing, see webgl_impl.zig.

const Canvas = @import("../element/html/Canvas.zig");
const gen = @import("webgl_generated.zig");
const impl = @import("webgl_impl.zig");

pub fn registerTypes() []const type {
    return &.{ WebGLRenderingContext, impl.WebGLShaderPrecisionFormat };
}

const WebGLRenderingContext = @This();

_canvas: *Canvas,
// getExtension's objects, by index in gen.webgl1_extensions.
_extensions: [gen.webgl1_extensions.len]?*anyopaque = @splat(null),

const C = impl.Common(WebGLRenderingContext, 1);
pub const get_canvas = C.get_canvas;
pub const get_drawingBufferWidth = C.get_drawingBufferWidth;
pub const get_drawingBufferHeight = C.get_drawingBufferHeight;
pub const get_drawingBufferFormat = C.get_drawingBufferFormat;
pub const get_drawingBufferColorSpace = C.get_drawingBufferColorSpace;
pub const set_drawingBufferColorSpace = C.set_drawingBufferColorSpace;
pub const get_unpackColorSpace = C.get_unpackColorSpace;
pub const set_unpackColorSpace = C.set_unpackColorSpace;
pub const getParameter = C.getParameter;
pub const getExtension = C.getExtension;
pub const getSupportedExtensions = C.getSupportedExtensions;
pub const getContextAttributes = C.getContextAttributes;
pub const getShaderParameter = C.getShaderParameter;
pub const getProgramParameter = C.getProgramParameter;
pub const getShaderPrecisionFormat = C.getShaderPrecisionFormat;
pub const createShader = C.createShader;
pub const checkFramebufferStatus = C.checkFramebufferStatus;
pub const getAttribLocation = C.getAttribLocation;
pub const getFragDataLocation = C.getFragDataLocation;
pub const getUniformLocation = C.getUniformLocation;
pub const getUniformBlockIndex = C.getUniformBlockIndex;
pub const clientWaitSync = C.clientWaitSync;
pub const getInternalformatParameter = C.getInternalformatParameter;

pub const JsApi = gen.WebGLRenderingContextApi(WebGLRenderingContext);

const testing = @import("../../../testing.zig");
test "WebApi: WebGL" {
    try testing.htmlRunner("canvas/webgl.html", .{});
}
