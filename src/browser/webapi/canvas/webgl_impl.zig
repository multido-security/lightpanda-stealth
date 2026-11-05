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

//! The parts of the WebGL contexts whose results matter: what Chrome reports
//! for a typical desktop GPU (getParameter, extensions, precision formats,
//! shader/program status). Everything else is generated as a no-op (see
//! build_tools/gen_webgl.py): nothing is rendered, but every call a page makes
//! exists and succeeds, so libraries (Three.js et al.) draw nothing instead of
//! throwing, and fingerprinting scripts see a working WebGL.

const std = @import("std");

const js = @import("../../js/js.zig");
const Frame = @import("../../Frame.zig");
const Fingerprint = @import("../../Fingerprint.zig");
const Canvas = @import("../element/html/Canvas.zig");
const gen = @import("webgl_generated.zig");

/// getParameter's result: its type depends on `pname`.
pub const Parameter = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
    string: []const u8,
    f32s: js.TypedArray(f32),
    i32s: js.TypedArray(i32),
    u32s: js.TypedArray(u32),
    bools: []const bool,
};

/// getShaderParameter / getProgramParameter.
pub const ObjectParameter = union(enum) {
    int: i64,
    bool: bool,
};

pub const WebGLShaderPrecisionFormat = struct {
    _range_min: i32,
    _range_max: i32,
    _precision: i32,

    fn getRangeMin(self: *const WebGLShaderPrecisionFormat) i32 {
        return self._range_min;
    }
    fn getRangeMax(self: *const WebGLShaderPrecisionFormat) i32 {
        return self._range_max;
    }
    fn getPrecision(self: *const WebGLShaderPrecisionFormat) i32 {
        return self._precision;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(WebGLShaderPrecisionFormat);
        pub const Meta = struct {
            pub const name = "WebGLShaderPrecisionFormat";
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const rangeMin = bridge.accessor(WebGLShaderPrecisionFormat.getRangeMin, null, .{});
        pub const rangeMax = bridge.accessor(WebGLShaderPrecisionFormat.getRangeMax, null, .{});
        pub const precision = bridge.accessor(WebGLShaderPrecisionFormat.getPrecision, null, .{});
    };
};

// GL enums used below.
const GL = struct {
    const TEXTURE0 = 0x84C0;
    const FUNC_ADD = 0x8006;
    const BACK = 0x0405;
    const LESS = 0x0201;
    const CCW = 0x0901;
    const DONT_CARE = 0x1100;
    const RGBA = 0x1908;
    const UNSIGNED_BYTE = 0x1401;
    const KEEP = 0x1E00;
    const ALWAYS = 0x0207;
    const BROWSER_DEFAULT_WEBGL = 0x9244;
    const FRAMEBUFFER_COMPLETE = 0x8CD5;
    const ALREADY_SIGNALED = 0x911A;
    const INVALID_INDEX = 0xFFFFFFFF;
    const RGBA8 = 0x8058;
    const SAMPLES = 0x80A9;
};

/// What both contexts share. `version` is 1 (WebGLRenderingContext) or 2.
pub fn Common(comptime Ctx: type, comptime version: u8) type {
    const extensions = if (version == 1) &gen.webgl1_extensions else &gen.webgl2_extensions;
    const Extension = if (version == 1) gen.Extension1 else gen.Extension2;

    return struct {
        pub fn get_canvas(self: *const Ctx) *Canvas {
            return self._canvas;
        }

        pub fn get_drawingBufferWidth(self: *const Ctx) u32 {
            return self._canvas.getWidth();
        }

        pub fn get_drawingBufferHeight(self: *const Ctx) u32 {
            return self._canvas.getHeight();
        }

        pub fn get_drawingBufferFormat(_: *const Ctx) u32 {
            return GL.RGBA8;
        }

        pub fn get_drawingBufferColorSpace(_: *const Ctx) []const u8 {
            return "srgb";
        }

        pub fn set_drawingBufferColorSpace(_: *Ctx, _: []const u8) void {}

        pub fn get_unpackColorSpace(_: *const Ctx) []const u8 {
            return "srgb";
        }

        pub fn set_unpackColorSpace(_: *Ctx, _: []const u8) void {}

        pub fn getSupportedExtensions(_: *const Ctx) []const []const u8 {
            return extensions;
        }

        /// Case-insensitive, as in Chrome; the same object every time.
        pub fn getExtension(self: *Ctx, name: []const u8, frame: *Frame) !?Extension {
            const info = @typeInfo(Extension).@"union";
            inline for (info.field_names, info.field_types, 0..) |field_name, field_type, i| {
                if (std.ascii.eqlIgnoreCase(field_name, name)) {
                    const T = @typeInfo(field_type).pointer.child;
                    const ptr: *T = if (self._extensions[i]) |cached| @ptrCast(@alignCast(cached)) else blk: {
                        const created = try frame._factory.create(T{});
                        self._extensions[i] = created;
                        break :blk created;
                    };
                    return @unionInit(Extension, field_name, ptr);
                }
            }
            return null;
        }

        pub fn getContextAttributes(_: *const Ctx) struct {
            alpha: bool = true,
            antialias: bool = true,
            depth: bool = true,
            desynchronized: bool = false,
            failIfMajorPerformanceCaveat: bool = false,
            powerPreference: []const u8 = "default",
            premultipliedAlpha: bool = true,
            preserveDrawingBuffer: bool = false,
            stencil: bool = false,
            xrCompatible: bool = false,
        } {
            return .{};
        }

        pub fn createShader(_: *Ctx, shader_type: u32, frame: *Frame) !*gen.WebGLShader {
            return frame._factory.create(gen.WebGLShader{ ._type = shader_type });
        }

        // Every shader compiles and every program links.
        pub fn getShaderParameter(_: *const Ctx, shader: *gen.WebGLShader, pname: u32) ?ObjectParameter {
            return switch (pname) {
                0x8B81 => .{ .bool = true }, // COMPILE_STATUS
                0x8B80 => .{ .bool = false }, // DELETE_STATUS
                0x8B4F => .{ .int = shader._type }, // SHADER_TYPE
                else => null,
            };
        }

        pub fn getProgramParameter(_: *const Ctx, _: *gen.WebGLProgram, pname: u32) ?ObjectParameter {
            return switch (pname) {
                0x8B82, 0x8B83 => .{ .bool = true }, // LINK_STATUS, VALIDATE_STATUS
                0x8B80 => .{ .bool = false }, // DELETE_STATUS
                0x8B85, 0x8B89, 0x8B86 => .{ .int = 0 }, // ATTACHED_SHADERS, ACTIVE_ATTRIBUTES, ACTIVE_UNIFORMS
                0x8A36 => .{ .int = 0 }, // ACTIVE_UNIFORM_BLOCKS
                0x8C83 => .{ .int = 0 }, // TRANSFORM_FEEDBACK_VARYINGS
                0x8C7F => .{ .int = 0x8C8D }, // TRANSFORM_FEEDBACK_BUFFER_MODE: SEPARATE_ATTRIBS
                else => null,
            };
        }

        /// Desktop GPUs: IEEE single precision for every float precision,
        /// 32-bit ints for every int one.
        pub fn getShaderPrecisionFormat(_: *const Ctx, _: u32, precision_type: u32, frame: *Frame) !?*WebGLShaderPrecisionFormat {
            const format: WebGLShaderPrecisionFormat = switch (precision_type) {
                0x8DF0, 0x8DF1, 0x8DF2 => .{ ._range_min = 127, ._range_max = 127, ._precision = 23 },
                0x8DF3, 0x8DF4, 0x8DF5 => .{ ._range_min = 31, ._range_max = 30, ._precision = 0 },
                else => return null,
            };
            return try frame._factory.create(format);
        }

        pub fn checkFramebufferStatus(_: *const Ctx, _: u32) u32 {
            return GL.FRAMEBUFFER_COMPLETE;
        }

        // A linked program finds its attributes and outputs at location 0.
        pub fn getAttribLocation(_: *const Ctx, _: *gen.WebGLProgram, _: []const u8) i32 {
            return 0;
        }

        pub fn getFragDataLocation(_: *const Ctx, _: *gen.WebGLProgram, _: []const u8) i32 {
            return 0;
        }

        pub fn getUniformLocation(_: *const Ctx, _: *gen.WebGLProgram, _: []const u8, frame: *Frame) !*gen.WebGLUniformLocation {
            return frame._factory.create(gen.WebGLUniformLocation{});
        }

        pub fn getUniformBlockIndex(_: *const Ctx, _: *gen.WebGLProgram, _: []const u8) u32 {
            return GL.INVALID_INDEX;
        }

        pub fn clientWaitSync(_: *const Ctx, _: *gen.WebGLSync, _: u32, _: f64) u32 {
            return GL.ALREADY_SIGNALED;
        }

        pub fn getInternalformatParameter(_: *const Ctx, _: u32, _: u32, pname: u32) ?js.TypedArray(i32) {
            if (pname != GL.SAMPLES) return null;
            return .{ .values = &.{ 8, 4, 2 } };
        }

        pub fn getParameter(self: *const Ctx, pname: u32) ?Parameter {
            if (version == 2) {
                if (webgl2Parameter(pname)) |p| return p;
            }
            const w: i32 = @intCast(@min(self._canvas.getWidth(), std.math.maxInt(i32)));
            const h: i32 = @intCast(@min(self._canvas.getHeight(), std.math.maxInt(i32)));
            const gpu = Fingerprint.get().gpu();
            return switch (pname) {
                0x1F00 => .{ .string = "WebKit" }, // VENDOR
                0x1F01 => .{ .string = "WebKit WebGL" }, // RENDERER
                0x1F02 => .{ .string = if (version == 1) "WebGL 1.0 (OpenGL ES 2.0 Chromium)" else "WebGL 2.0 (OpenGL ES 3.0 Chromium)" }, // VERSION
                0x8B8C => .{ .string = if (version == 1) "WebGL GLSL ES 1.0 (OpenGL ES GLSL ES 1.0 Chromium)" else "WebGL GLSL ES 3.00 (OpenGL ES GLSL ES 3.0 Chromium)" }, // SHADING_LANGUAGE_VERSION
                0x9245 => .{ .string = gpu.vendor }, // UNMASKED_VENDOR_WEBGL
                0x9246 => .{ .string = gpu.renderer }, // UNMASKED_RENDERER_WEBGL

                0x0D33, 0x84E8, 0x851C => .{ .int = 16384 }, // MAX_TEXTURE_SIZE, MAX_RENDERBUFFER_SIZE, MAX_CUBE_MAP_TEXTURE_SIZE
                0x8869, 0x8872, 0x8B4C => .{ .int = 16 }, // MAX_VERTEX_ATTRIBS, MAX_TEXTURE_IMAGE_UNITS, MAX_VERTEX_TEXTURE_IMAGE_UNITS
                0x8B4D => .{ .int = 32 }, // MAX_COMBINED_TEXTURE_IMAGE_UNITS
                0x8DFB => .{ .int = 4096 }, // MAX_VERTEX_UNIFORM_VECTORS
                0x8DFC => .{ .int = 30 }, // MAX_VARYING_VECTORS
                0x8DFD => .{ .int = 1024 }, // MAX_FRAGMENT_UNIFORM_VECTORS
                0x0D3A => .{ .i32s = .{ .values = &.{ 32767, 32767 } } }, // MAX_VIEWPORT_DIMS
                0x846D => .{ .f32s = .{ .values = &.{ 1, 1024 } } }, // ALIASED_POINT_SIZE_RANGE
                0x846E => .{ .f32s = .{ .values = &.{ 1, 1 } } }, // ALIASED_LINE_WIDTH_RANGE
                0x84FF => .{ .float = 16 }, // MAX_TEXTURE_MAX_ANISOTROPY_EXT
                0x0D50 => .{ .int = 4 }, // SUBPIXEL_BITS
                0x0D52, 0x0D53, 0x0D54, 0x0D55 => .{ .int = 8 }, // RED/GREEN/BLUE/ALPHA_BITS
                0x0D56 => .{ .int = 24 }, // DEPTH_BITS
                0x0D57 => .{ .int = 0 }, // STENCIL_BITS
                0x80A8 => .{ .int = 1 }, // SAMPLE_BUFFERS
                0x80A9 => .{ .int = 4 }, // SAMPLES
                0x86A3 => .{ .u32s = .{ .values = &.{} } }, // COMPRESSED_TEXTURE_FORMATS
                0x8B9B => .{ .int = GL.RGBA }, // IMPLEMENTATION_COLOR_READ_FORMAT
                0x8B9A => .{ .int = GL.UNSIGNED_BYTE }, // IMPLEMENTATION_COLOR_READ_TYPE

                // Default state.
                0x84E0 => .{ .int = GL.TEXTURE0 }, // ACTIVE_TEXTURE
                0x0BE2, 0x0B44, 0x0B71, 0x8037, 0x0C11, 0x0B90, 0x80AA, 0x9240, 0x9241, 0x809E, 0x80A0 => .{ .bool = false }, // BLEND, CULL_FACE, DEPTH_TEST, POLYGON_OFFSET_FILL, SCISSOR_TEST, STENCIL_TEST, SAMPLE_COVERAGE_INVERT, UNPACK_FLIP_Y, UNPACK_PREMULTIPLY_ALPHA, SAMPLE_ALPHA_TO_COVERAGE, SAMPLE_COVERAGE
                0x0BD0, 0x0B72 => .{ .bool = true }, // DITHER, DEPTH_WRITEMASK
                0x8005, 0x0C22 => .{ .f32s = .{ .values = &.{ 0, 0, 0, 0 } } }, // BLEND_COLOR, COLOR_CLEAR_VALUE
                0x0C23 => .{ .bools = &.{ true, true, true, true } }, // COLOR_WRITEMASK
                0x0B70 => .{ .f32s = .{ .values = &.{ 0, 1 } } }, // DEPTH_RANGE
                0x80C8, 0x80CA => .{ .int = 0 }, // BLEND_DST_RGB, BLEND_DST_ALPHA (ZERO)
                0x80C9, 0x80CB => .{ .int = 1 }, // BLEND_SRC_RGB, BLEND_SRC_ALPHA (ONE)
                0x8009, 0x883D => .{ .int = GL.FUNC_ADD }, // BLEND_EQUATION_RGB, BLEND_EQUATION_ALPHA
                0x0B45 => .{ .int = GL.BACK }, // CULL_FACE_MODE
                0x0B73, 0x0B21, 0x80AB => .{ .float = 1 }, // DEPTH_CLEAR_VALUE, LINE_WIDTH, SAMPLE_COVERAGE_VALUE
                0x0B74 => .{ .int = GL.LESS }, // DEPTH_FUNC
                0x0B46 => .{ .int = GL.CCW }, // FRONT_FACE
                0x8192 => .{ .int = GL.DONT_CARE }, // GENERATE_MIPMAP_HINT
                0x0D05, 0x0CF5 => .{ .int = 4 }, // PACK_ALIGNMENT, UNPACK_ALIGNMENT
                0x8038, 0x2A00 => .{ .float = 0 }, // POLYGON_OFFSET_FACTOR, POLYGON_OFFSET_UNITS
                0x0C10, 0x0BA2 => .{ .i32s = .{ .values = &.{ 0, 0, w, h } } }, // SCISSOR_BOX, VIEWPORT
                0x0B94, 0x0B95, 0x0B96, 0x8801, 0x8802, 0x8803 => .{ .int = GL.KEEP }, // STENCIL_FAIL/PASS_DEPTH_FAIL/PASS_DEPTH_PASS (+BACK_)
                0x0B92, 0x8800 => .{ .int = GL.ALWAYS }, // STENCIL_FUNC, STENCIL_BACK_FUNC
                0x0B97, 0x8CA3, 0x0B91 => .{ .int = 0 }, // STENCIL_REF, STENCIL_BACK_REF, STENCIL_CLEAR_VALUE
                0x0B93, 0x8CA4, 0x0B98, 0x8CA5 => .{ .int = 0x7FFFFFFF }, // STENCIL_(BACK_)VALUE_MASK, STENCIL_(BACK_)WRITEMASK
                0x9243 => .{ .int = GL.BROWSER_DEFAULT_WEBGL }, // UNPACK_COLORSPACE_CONVERSION_WEBGL
                // Bindings: nothing is bound.
                else => null,
            };
        }

        fn webgl2Parameter(pname: u32) ?Parameter {
            return switch (pname) {
                0x8073 => .{ .int = 2048 }, // MAX_3D_TEXTURE_SIZE
                0x88FF => .{ .int = 2048 }, // MAX_ARRAY_TEXTURE_LAYERS
                0x8CDF, 0x8824 => .{ .int = 8 }, // MAX_COLOR_ATTACHMENTS, MAX_DRAW_BUFFERS
                0x8D6B => .{ .int = 4294967295 }, // MAX_ELEMENT_INDEX
                0x80E8, 0x80E9 => .{ .int = 2147483647 }, // MAX_ELEMENTS_VERTICES, MAX_ELEMENTS_INDICES
                0x9125, 0x8B4B, 0x9122 => .{ .int = 120 }, // MAX_FRAGMENT_INPUT_COMPONENTS, MAX_VARYING_COMPONENTS, MAX_VERTEX_OUTPUT_COMPONENTS
                0x8A2D, 0x8A2B => .{ .int = 12 }, // MAX_FRAGMENT_UNIFORM_BLOCKS, MAX_VERTEX_UNIFORM_BLOCKS
                0x8B49 => .{ .int = 4096 }, // MAX_FRAGMENT_UNIFORM_COMPONENTS
                0x8B4A => .{ .int = 16384 }, // MAX_VERTEX_UNIFORM_COMPONENTS
                0x8905 => .{ .int = 7 }, // MAX_PROGRAM_TEXEL_OFFSET
                0x8904 => .{ .int = -8 }, // MIN_PROGRAM_TEXEL_OFFSET
                0x8D57 => .{ .int = 16 }, // MAX_SAMPLES
                0x9111, 0x9247 => .{ .int = 0 }, // MAX_SERVER_WAIT_TIMEOUT, MAX_CLIENT_WAIT_TIMEOUT_WEBGL
                0x84FD => .{ .float = 2 }, // MAX_TEXTURE_LOD_BIAS
                0x8C8A, 0x8C8B, 0x8C80 => .{ .int = 4 }, // MAX_TRANSFORM_FEEDBACK_*
                0x8A30 => .{ .int = 65536 }, // MAX_UNIFORM_BLOCK_SIZE
                0x8A2F, 0x8A2E => .{ .int = 24 }, // MAX_UNIFORM_BUFFER_BINDINGS, MAX_COMBINED_UNIFORM_BLOCKS
                0x8A33 => .{ .int = 200704 }, // MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS
                0x8A31 => .{ .int = 212992 }, // MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS
                0x8A34 => .{ .int = 256 }, // UNIFORM_BUFFER_OFFSET_ALIGNMENT
                0x0C02, 0x8825 => .{ .int = GL.BACK }, // READ_BUFFER, DRAW_BUFFER0
                0x8B8B => .{ .int = GL.DONT_CARE }, // FRAGMENT_SHADER_DERIVATIVE_HINT
                0x8C89, 0x8E24, 0x8E23 => .{ .bool = false }, // RASTERIZER_DISCARD, TRANSFORM_FEEDBACK_ACTIVE/PAUSED
                0x0D02, 0x0D03, 0x0D04, 0x0CF2, 0x0CF3, 0x0CF4, 0x806D, 0x806E => .{ .int = 0 }, // PACK_/UNPACK_ ROW_LENGTH, SKIP_*, IMAGE_HEIGHT
                else => null,
            };
        }
    };
}
