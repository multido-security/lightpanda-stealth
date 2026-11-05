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

//! Makes the TLS ClientHello match desktop Chrome's. Chrome and Lightpanda
//! both use BoringSSL, so this is a matter of configuring it the way Chrome's
//! net/socket/ssl_client_socket_impl.cc does: GREASE, a shuffled extension
//! order, Chrome's cipher suites, groups (with the X25519MLKEM768 hybrid) and
//! signature algorithms, OCSP stapling and SCT requests, brotli certificate
//! compression, ALPS for h2 and an ECH GREASE extension. A libcurl-shaped
//! ClientHello (JA3/JA4) contradicts a Chrome User-Agent, and bot-protection
//! CDNs check exactly that.

const std = @import("std");
const crypto = @import("../sys/libcrypto.zig");
const brotli = @import("../sys/brotli.zig");

/// Chrome's TLS 1.2 suites, in order. BoringSSL always puts its fixed TLS 1.3
/// suites (AES-128-GCM, AES-256-GCM, ChaCha20) first, as Chrome sends them.
const cipher_list = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:" ++
    "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:" ++
    "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:" ++
    "ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:" ++
    "AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA:AES256-SHA";

/// Chrome's supported groups. BoringSSL then sends key shares for the first
/// (post-quantum) group and the first classical one, as Chrome does.
pub const curves: [:0]const u8 = "X25519MLKEM768:X25519:P-256:P-384";

/// Chrome's signature_algorithms extension.
const verify_algorithms = [_]u16{
    0x0403, // ecdsa_secp256r1_sha256
    0x0804, // rsa_pss_rsae_sha256
    0x0401, // rsa_pkcs1_sha256
    0x0503, // ecdsa_secp384r1_sha384
    0x0805, // rsa_pss_rsae_sha384
    0x0501, // rsa_pkcs1_sha384
    0x0806, // rsa_pss_rsae_sha512
    0x0601, // rsa_pkcs1_sha512
};

const TLSEXT_cert_compression_brotli: u16 = 2;

pub const Opts = struct {
    // False when --http-curves chose the groups.
    set_curves: bool = true,
};

/// Configures a fresh SSL_CTX (from CURLOPT_SSL_CTX_FUNCTION, which libcurl
/// calls after its own setup, before creating the connection's SSL).
pub fn apply(ctx: *crypto.SSL_CTX, opts: Opts) bool {
    if (crypto.SSL_CTX_set_strict_cipher_list(ctx, cipher_list) != 1) return false;
    if (opts.set_curves and crypto.SSL_CTX_set1_curves_list(ctx, curves) != 1) return false;
    if (crypto.SSL_CTX_set_verify_algorithm_prefs(ctx, &verify_algorithms, verify_algorithms.len) != 1) return false;

    // libcurl turns TLS 1.2 tickets off; Chrome offers the session_ticket
    // extension (JA4 counts it).
    _ = crypto.SSL_CTX_clear_options(ctx, crypto.SSL_OP_NO_TICKET);
    crypto.SSL_CTX_set_grease_enabled(ctx, 1);
    crypto.SSL_CTX_set_permute_extensions(ctx, 1);
    crypto.SSL_CTX_enable_ocsp_stapling(ctx);
    crypto.SSL_CTX_enable_signed_cert_timestamps(ctx);
    // Fails only if already registered (a reused SSL_CTX): harmless.
    _ = crypto.SSL_CTX_add_cert_compression_alg(ctx, TLSEXT_cert_compression_brotli, null, decompressBrotli);
    crypto.SSL_CTX_set_info_callback(ctx, infoCallback);
    return true;
}

// The per-connection part: BoringSSL calls this at the start of the handshake,
// before it builds the ClientHello.
fn infoCallback(ssl: ?*const crypto.SSL, @"type": c_int, _: c_int) callconv(.c) void {
    if (@"type" != crypto.SSL_CB_HANDSHAKE_START) return;
    const s: *crypto.SSL = @constCast(ssl orelse return);
    // ALPS (application_settings), with the codepoint current Chrome uses.
    crypto.SSL_set_alps_use_new_codepoint(s, 1);
    _ = crypto.SSL_add_application_settings(s, "h2", 2, null, 0);
    crypto.SSL_set_enable_ech_grease(s, 1);
}

fn decompressBrotli(_: ?*crypto.SSL, out: *?*crypto.CRYPTO_BUFFER, uncompressed_len: usize, in: [*]const u8, in_len: usize) callconv(.c) c_int {
    var data: [*]u8 = undefined;
    const buf = crypto.CRYPTO_BUFFER_alloc(&data, uncompressed_len) orelse return 0;
    var decoded_len = uncompressed_len;
    const result = brotli.BrotliDecoderDecompress(in_len, in, &decoded_len, data);
    if (result != .success or decoded_len != uncompressed_len) {
        crypto.CRYPTO_BUFFER_free(buf);
        return 0;
    }
    out.* = buf;
    return 1;
}

test "chrome_tls: applies to a fresh SSL_CTX" {
    const ctx = crypto.SSL_CTX_new(crypto.TLS_method()) orelse return error.OutOfMemory;
    defer crypto.SSL_CTX_free(ctx);
    try std.testing.expect(apply(ctx, .{}));
}
