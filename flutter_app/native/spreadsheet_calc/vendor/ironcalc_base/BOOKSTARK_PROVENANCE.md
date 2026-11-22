# Upstream provenance

IronCalc v0.9.1, commit eb9ca75bd99160c17902359d2d87225c4571c468.
Source: https://github.com/ironcalc/IronCalc/tree/eb9ca75bd99160c17902359d2d87225c4571c468/base

Cargo.toml, README.md, src/ and examples/ copied unchanged from that revision. Retained upstream MIT and Apache-2.0 licenses. The provenance file and license copies from the upstream repository root are the additions in the vendor directory. Dependency build requires GIT_VERSION, supplied deterministically in the parent .cargo/config.toml; upstream code remains unmodified.

Host Rust 1.99.1; Cargo.lock pins transitive packages. Build output/cache belongs in NAS isolated APK test volume and must not enter source archives. This is an experimental calculation bridge, not evidence of complete Univer/Excel compatibility.
