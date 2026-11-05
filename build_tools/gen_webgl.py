#!/usr/bin/env python3
# Copyright (C) 2023-2026  Lightpanda (Selecy SAS)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
"""Generates src/browser/webapi/canvas/webgl_generated.zig from the Khronos
WebGL IDL: every WebGL 1/2 constant and method (with Chrome's `length`), the
WebGL object interfaces and the extension interfaces Chrome exposes.

Methods are no-ops; the ones whose result matters (getParameter, getExtension,
...) are listed in SPECIAL and implemented by hand in webgl_impl.zig.

Usage: build_tools/gen_webgl.py [IDL_DIR]
IDL_DIR holds webgl1.idl, webgl2.idl and ext/<NAME>.xml (Khronos's
extension.xml files). Without it, they're downloaded.
"""

import os
import re
import subprocess
import sys
import urllib.request

OUT = os.path.join(os.path.dirname(__file__), "..", "src", "browser", "webapi", "canvas", "webgl_generated.zig")

# What desktop Chrome on Linux/Windows reports from getSupportedExtensions().
WEBGL1_EXTENSIONS = [
    "ANGLE_instanced_arrays", "EXT_blend_minmax", "EXT_clip_control", "EXT_color_buffer_half_float",
    "EXT_depth_clamp", "EXT_disjoint_timer_query", "EXT_float_blend", "EXT_frag_depth",
    "EXT_polygon_offset_clamp", "EXT_shader_texture_lod", "EXT_texture_compression_bptc",
    "EXT_texture_compression_rgtc", "EXT_texture_filter_anisotropic", "EXT_texture_mirror_clamp_to_edge",
    "EXT_sRGB", "KHR_parallel_shader_compile", "OES_element_index_uint", "OES_fbo_render_mipmap",
    "OES_standard_derivatives", "OES_texture_float", "OES_texture_float_linear", "OES_texture_half_float",
    "OES_texture_half_float_linear", "OES_vertex_array_object", "WEBGL_blend_func_extended",
    "WEBGL_color_buffer_float", "WEBGL_compressed_texture_etc", "WEBGL_compressed_texture_etc1",
    "WEBGL_compressed_texture_s3tc", "WEBGL_compressed_texture_s3tc_srgb", "WEBGL_debug_renderer_info",
    "WEBGL_debug_shaders", "WEBGL_depth_texture", "WEBGL_draw_buffers", "WEBGL_lose_context",
    "WEBGL_multi_draw", "WEBGL_polygon_mode",
]
WEBGL2_EXTENSIONS = [
    "EXT_clip_control", "EXT_color_buffer_float", "EXT_color_buffer_half_float", "EXT_conservative_depth",
    "EXT_depth_clamp", "EXT_disjoint_timer_query_webgl2", "EXT_float_blend", "EXT_polygon_offset_clamp",
    "EXT_render_snorm", "EXT_texture_compression_bptc", "EXT_texture_compression_rgtc",
    "EXT_texture_filter_anisotropic", "EXT_texture_mirror_clamp_to_edge", "EXT_texture_norm16",
    "KHR_parallel_shader_compile", "NV_shader_noperspective_interpolation", "OES_draw_buffers_indexed",
    "OES_sample_variables", "OES_shader_multisample_interpolation", "OES_texture_float_linear",
    "OVR_multiview2", "WEBGL_blend_func_extended", "WEBGL_clip_cull_distance", "WEBGL_compressed_texture_etc",
    "WEBGL_compressed_texture_etc1", "WEBGL_compressed_texture_s3tc", "WEBGL_compressed_texture_s3tc_srgb",
    "WEBGL_debug_renderer_info", "WEBGL_debug_shaders", "WEBGL_lose_context", "WEBGL_multi_draw",
    "WEBGL_polygon_mode", "WEBGL_provoking_vertex", "WEBGL_stencil_texturing",
]

# Context members implemented in webgl_impl.zig (Common(Ctx)).
SPECIAL = {
    "canvas", "drawingBufferWidth", "drawingBufferHeight", "drawingBufferFormat",
    "drawingBufferColorSpace", "unpackColorSpace",
    "getParameter", "getExtension", "getSupportedExtensions", "getContextAttributes",
    "getShaderParameter", "getProgramParameter", "getShaderPrecisionFormat", "createShader",
    "checkFramebufferStatus", "getAttribLocation", "getFragDataLocation", "getUniformBlockIndex",
    "clientWaitSync", "getInternalformatParameter", "getUniformLocation",
}

INT_TYPES = {"GLenum", "GLint", "GLuint", "GLsizei", "GLintptr", "GLsizeiptr", "GLint64", "GLuint64", "GLbitfield",
             "long", "unsigned long", "long long", "unsigned long long"}

# WebGL object interfaces: instances created by create* calls.
OBJECT_TYPES = [
    "WebGLBuffer", "WebGLFramebuffer", "WebGLProgram", "WebGLRenderbuffer", "WebGLShader", "WebGLTexture",
    "WebGLUniformLocation", "WebGLQuery", "WebGLSampler", "WebGLSync", "WebGLTransformFeedback",
    "WebGLVertexArrayObject", "WebGLActiveInfo", "WebGLObject",
]


def fetch(url):
    with urllib.request.urlopen(url) as r:
        return r.read().decode()


def load(idl_dir):
    def read(rel, url):
        if idl_dir:
            with open(os.path.join(idl_dir, rel)) as f:
                return f.read()
        return fetch(url)

    w1 = read("webgl1.idl", "https://registry.khronos.org/webgl/specs/latest/1.0/webgl.idl")
    w2 = read("webgl2.idl", "https://registry.khronos.org/webgl/specs/latest/2.0/webgl2.idl")
    exts = {}
    for name in sorted(set(WEBGL1_EXTENSIONS) | set(WEBGL2_EXTENSIONS)):
        xml = read(f"ext/{name}.xml", f"https://raw.githubusercontent.com/KhronosGroup/WebGL/main/extensions/{name}/extension.xml")
        m = re.search(r"<idl[^>]*>(.*?)</idl>", xml, re.S)
        exts[name] = m.group(1).replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&") if m else ""
    return w1, w2, exts


def strip(idl):
    idl = re.sub(r"/\*.*?\*/", "", idl, flags=re.S)
    idl = re.sub(r"//[^\n]*", "", idl)
    return idl


def interfaces(idl):
    out = {}
    for m in re.finditer(r"(?:partial\s+)?interface(?:\s+mixin)?\s+(\w+)\s*(?::\s*(\w+))?\s*\{(.*?)\}\s*;", strip(idl), re.S):
        out.setdefault(m.group(1), []).extend(members(m.group(3)))
    return out


def split_top(s, sep=","):
    parts, depth, cur = [], 0, ""
    for c in s:
        if c in "<([":
            depth += 1
        elif c in ">)]":
            depth -= 1
        if c == sep and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += c
    if cur.strip():
        parts.append(cur)
    return parts


def members(body):
    out = []
    for raw in split_top(body, ";"):
        m = re.sub(r"\[[^\]]*\]", "", raw).strip()
        m = " ".join(m.split())
        if not m or m.startswith("constructor("):
            continue
        c = re.match(r"const \w+(?: \w+)* (\w+) = (-?\w+)$", m)
        if c:
            out.append(("const", c.group(1), c.group(2)))
            continue
        a = re.match(r"(readonly )?attribute (.+) (\w+)$", m)
        if a:
            out.append(("attr", a.group(3), a.group(2).strip(), a.group(1) is None))
            continue
        o = re.match(r"(.+?) (\w+)\((.*)\)$", m)
        if o:
            args = [x.strip() for x in split_top(o.group(3))]
            required = 0
            for x in args:
                if x.startswith("optional") or "..." in x:
                    break
                required += 1
            out.append(("op", o.group(2), o.group(1).strip(), required))
            continue
        raise SystemExit(f"unparsed IDL member: {m}")
    return out


def collect(ifaces, names):
    consts, attrs, ops = {}, {}, {}
    for n in names:
        for mem in ifaces[n]:
            if mem[0] == "const":
                consts.setdefault(mem[1], mem[2])
            elif mem[0] == "attr":
                attrs.setdefault(mem[1], mem)
            else:
                _, name, ret, req = mem
                if name in ops:
                    ops[name] = (ops[name][0], min(ops[name][1], req))
                else:
                    ops[name] = (ret, req)
    return consts, attrs, ops


def zig_ident(name):
    return f'@"{name}"'


def op_code(owner, name, ret, req, objects):
    """A no-op implementation, returning Chrome's default for the type."""
    params = "".join(", _: js.Value" for _ in range(req))
    nullable = ret.endswith("?")
    base = ret.rstrip("?")
    # A successful driver: logs are empty, not missing.
    if name in ("getShaderInfoLog", "getProgramInfoLog", "getShaderSource", "getTranslatedShaderSource"):
        nullable = False
    if name in ("getAttachedShaders", "getUniformIndices"):
        nullable = False
    if (name.startswith("create") or name == "fenceSync") and base in objects:
        return f"struct {{ fn f(_: *{owner}{params}, frame: *Frame) !*{base} {{ return frame._factory.create({base}{{}}); }} }}.f"
    if base == "undefined":
        return f"struct {{ fn f(_: *{owner}{params}) void {{}} }}.f"
    if base in ("GLboolean", "boolean"):
        return f"struct {{ fn f(_: *{owner}{params}) bool {{ return false; }} }}.f"
    if base in INT_TYPES and not nullable:
        return f"struct {{ fn f(_: *{owner}{params}) i64 {{ return 0; }} }}.f"
    if base == "DOMString" and not nullable:
        return f'struct {{ fn f(_: *{owner}{params}) []const u8 {{ return ""; }} }}.f'
    if base.startswith("sequence<") and not nullable:
        return f"struct {{ fn f(_: *{owner}{params}) []const i32 {{ return &.{{}}; }} }}.f"
    if base.startswith("Promise"):
        return f"struct {{ fn f(_: *{owner}{params}, frame: *Frame) !js.Promise {{ return frame.js.local.?.resolvePromise(js.Undefined{{}}); }} }}.f"
    # Nullable results (objects, sequences, strings, `any`): null.
    return f"struct {{ fn f(_: *{owner}{params}) ?u32 {{ return null; }} }}.f"


def emit_object(lines, name, exposed=True):
    lines.append(f"pub const {name} = struct {{")
    lines.append("    _: u8 = 0,")
    lines.append("    pub const JsApi = struct {")
    lines.append(f"        pub const bridge = js.Bridge({name});")
    lines.append("        pub const Meta = struct {")
    lines.append(f'            pub const name = "{name}";')
    if not exposed:
        lines.append("            pub const no_interface_object = true;")
    lines.append("            pub var class_id: bridge.ClassId = undefined;")
    lines.append("        };")
    lines.append("    };")
    lines.append("};")
    lines.append("")


def emit_context(lines, ctx, consts, attrs, ops, objects):
    lines.append(f"pub fn {ctx}Api(comptime {ctx}: type) type {{")
    lines.append("    return struct {")
    lines.append(f"        pub const bridge = js.Bridge({ctx});")
    lines.append("        pub const Meta = struct {")
    lines.append(f'            pub const name = "{ctx}";')
    lines.append("            pub var class_id: bridge.ClassId = undefined;")
    lines.append("        };")
    lines.append("")
    for name, value in consts.items():
        lines.append(f"        pub const {zig_ident(name)} = bridge.property({value}, .{{ .template = true }});")
    lines.append("")
    for name, mem in attrs.items():
        if name not in SPECIAL:
            raise SystemExit(f"attribute without implementation: {name}")
        setter = f"{ctx}.set_{name}" if mem[3] else "null"
        lines.append(f"        pub const {zig_ident(name)} = bridge.accessor({ctx}.get_{name}, {setter}, .{{}});")
    lines.append("")
    for name, (ret, req) in sorted(ops.items()):
        impl = f"{ctx}.{name}" if name in SPECIAL else op_code(ctx, name, ret, req, objects)
        lines.append(f"        pub const {zig_ident(name)} = bridge.function({impl}, .{{}});")
    lines.append("    };")
    lines.append("}")
    lines.append("")


def main():
    idl_dir = sys.argv[1] if len(sys.argv) > 1 else None
    w1, w2, exts = load(idl_dir)
    i1 = interfaces(w1)
    i2 = interfaces(w2)
    all_ifaces = {**i1, **i2}

    ext_ifaces = {}
    ext_objects = []
    for name, idl in exts.items():
        parsed = interfaces(idl)
        for iname, mems in parsed.items():
            if iname == name:
                ext_ifaces[name] = mems
            elif iname not in OBJECT_TYPES:
                ext_objects.append(iname)
        ext_ifaces.setdefault(name, [])

    objects = set(OBJECT_TYPES) | set(ext_objects)

    lines = [
        "// GENERATED by build_tools/gen_webgl.py from the Khronos WebGL IDL. Do not edit.",
        "",
        'const js = @import("../../js/js.zig");',
        'const Frame = @import("../../Frame.zig");',
        "",
        "pub fn registerTypes() []const type {",
        "    return &.{",
    ]
    for o in OBJECT_TYPES + sorted(set(ext_objects)):
        lines.append(f"        {o},")
    for e in sorted(ext_ifaces):
        lines.append(f"        {e},")
    lines += ["    };", "}", ""]

    lines.append("pub const webgl1_extensions = [_][]const u8{")
    lines += [f'    "{e}",' for e in WEBGL1_EXTENSIONS]
    lines += ["};", ""]
    lines.append("pub const webgl2_extensions = [_][]const u8{")
    lines += [f'    "{e}",' for e in WEBGL2_EXTENSIONS]
    lines += ["};", ""]

    # Extension objects returned by getExtension, by name.
    for version, names in (("1", WEBGL1_EXTENSIONS), ("2", WEBGL2_EXTENSIONS)):
        lines.append(f"pub const Extension{version} = union(enum) {{")
        for e in names:
            lines.append(f"    {e}: *{e},")
        lines += ["};", ""]

    for o in OBJECT_TYPES:
        if o != "WebGLShader":
            emit_object(lines, o)
    for o in sorted(set(ext_objects)):
        emit_object(lines, o, exposed=False)

    # WebGLShader keeps its type (getShaderParameter(SHADER_TYPE)).
    lines += [
        "pub const WebGLShader = struct {",
        "    _type: u32 = 0,",
        "    pub const JsApi = struct {",
        "        pub const bridge = js.Bridge(WebGLShader);",
        "        pub const Meta = struct {",
        '            pub const name = "WebGLShader";',
        "            pub var class_id: bridge.ClassId = undefined;",
        "        };",
        "    };",
        "};",
        "",
    ]

    for e in sorted(ext_ifaces):
        consts, _, ops = collect({e: ext_ifaces[e]}, [e])
        lines.append(f"pub const {e} = struct {{")
        lines.append("    _: u8 = 0,")
        lines.append("    pub const JsApi = struct {")
        lines.append(f"        pub const bridge = js.Bridge({e});")
        lines.append("        pub const Meta = struct {")
        lines.append(f'            pub const name = "{e}";')
        lines.append("            pub const no_interface_object = true;")
        lines.append("            pub var class_id: bridge.ClassId = undefined;")
        lines.append("        };")
        for name, value in consts.items():
            lines.append(f"        pub const {zig_ident(name)} = bridge.property({value}, .{{ .template = false }});")
        for name, (ret, req) in sorted(ops.items()):
            lines.append(f"        pub const {zig_ident(name)} = bridge.function({op_code(e, name, ret, req, objects)}, .{{}});")
        lines.append("    };")
        lines.append("};")
        lines.append("")

    c1, a1, o1 = collect(all_ifaces, ["WebGLRenderingContextBase", "WebGLRenderingContextOverloads"])
    emit_context(lines, "WebGLRenderingContext", c1, a1, o1, objects)
    c2, a2, o2 = collect(all_ifaces, ["WebGLRenderingContextBase", "WebGL2RenderingContextBase", "WebGL2RenderingContextOverloads"])
    emit_context(lines, "WebGL2RenderingContext", c2, a2, o2, objects)

    with open(OUT, "w") as f:
        f.write("\n".join(lines))
    subprocess.run(["zig", "fmt", OUT], check=True, stdout=subprocess.DEVNULL)
    print(f"wrote {OUT}: {len(o1)} WebGL1 methods, {len(c1)} constants; {len(o2)} WebGL2 methods, {len(c2)} constants; {len(ext_ifaces)} extensions")


main()
