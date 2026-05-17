# Thread Summary: Reproducible Odroid HC4 NixOS SD Image

## Goal

Recreate the `considerate/nixos-odroidhc4` approach in a new NixOS flake that builds U-Boot **from source** instead of using a hardcoded store path.

---

## The Core Problem

The user's original `build/odroidhc4/flake.nix` used a **hardcoded Nix store path** for U-Boot:

```nix
# overlay/odroid-c4.nix (original)
u-boot-armbian-hc4 = final.stdenv.mkDerivation {
  enableSandbox = false;
  installPhase = ''
    cp /nix/store/yhq8qb5rlwg9mhi47mfpq149jh8m1mll-u-boot.bin $out/u-boot.bin
  '';
};
```

This is not reproducible — the store path only exists on the specific machine where the binary was copied from Armbian.

---

## The Inspiration: considerate/nixos-odroidhc4

The original approach (from `github:considerate/nixos-odroidhc4`) forked `arapov/nixpkgs` and applied `hc4-uboot.patch` to build U-Boot properly. That fork (`arapov/nixpkgs/hardkernel`) is **no longer available** (404). However, the approach itself — building U-Boot from source using Amlogic firmware blobs — is still valid.

---

## What We Built: `build/odroidhc4-repro/`

```
build/odroidhc4-repro/
├── flake.nix                     # Flake definition
├── configuration.nix             # NixOS SD image config
└── overlay/
    └── odroid-c4.nix             # Buildable U-Boot derivation
```

### Key Insight: Use `LibreELEC/amlogic-boot-fip`

The `ubootLibreTechCC` package in nixpkgs 25.11 already demonstrates how to build U-Boot for the Amlogic SM1 (S905X3) SoC. The key is:

1. Fetch firmware blobs from `LibreELEC/amlogic-boot-fip` at a **fixed Git commit** (hash-verified)
2. The blobs include `bl2.bin`, `bl21.bin`, `bl30.bin`, `bl301.bin`, `bl31.img`
3. Use `aml_encrypt_g12a` (pre-compiled x86_64 binary from the same repo) to sign/encrypt
4. Assemble the final FIP image

Since the Odroid HC4 and C4 share the same SoC (G12A/S905X3), the `odroid-c4` blobs work for both.

### The Overlay (`overlay/odroid-c4.nix`)

```nix
# Fetch blobs from LibreELEC at fixed commit (hash-verified)
amlogic-boot-fip-odroid-c4 = final.fetchFromGitHub {
  owner = "LibreELEC";
  repo = "amlogic-boot-fip";
  rev = "4369a138ca24c5ab932b8cbd1af4504570b709df";
  sha256 = "sha256-mGRUwdh3nW4gBwWIYHJGjzkezHxABwcwk/1gVRis7Tc=";
  postFetch = ''
    rm -rf $out/{lepotato,beelink-s922x,...,odroid-c2}  # remove unwanted boards
  '';
};

# Build U-Boot from source
u-boot-odroid-c4 = final.buildUBoot {
  defconfig = "odroid-c4_defconfig";
  filesToInstall = [ "u-boot.bin" ];
  postBuild = ''
    # Sign/encrypt BL2, BL30, BL31, BL33 (U-Boot)
    cp ${amlogic-boot-fip-odroid-c4}/{bl2.bin,bl21.bin,...,aml_encrypt_g12a} .
    python3 acs_tool.py bl2.bin bl2_acs.bin acs.bin 0
    bash -e blx_fix.sh bl2_acs.bin zero bl2_zero.bin bl21.bin bl21_zero.bin bl2_new.bin bl2
    bash -e blx_fix.sh bl30.bin zero bl30_zero.bin bl301.bin bl301_zero.bin bl30_new.bin bl30
    ./aml_encrypt_g12a --bl2sig --input bl2_new.bin --output bl2.n.bin.sig
    ./aml_encrypt_g12a --bl3enc --input bl30_new.bin --output bl30_new.bin.enc
    ./aml_encrypt_g12a --bl3enc --input bl31.img --output bl31.img.enc
    ./aml_encrypt_g12a --bl3enc --input u-boot.bin --output bl33.bin.enc
    ./aml_encrypt_g12a --bootmk --output $out/u-boot.bin \
      --bl2 bl2.n.bin.sig --bl30 bl30_new.bin.enc \
      --bl31 bl31.img.enc --bl33 bl33.bin.enc
  '';
};
```

**Key changes from original:**

- `buildUBoot` instead of raw `stdenv.mkDerivation`
- No `enableSandbox = false` — fully sandboxed
- Blobs fetched from Git at hash-verified commit
- `broken = builtins.currentSystem != "x86_64-linux"` in `extraMeta` (U-Boot targets aarch64 but the host tool runs on x86_64)

---

## Host System

- **Machine**: Bronze1 (x86_64)
- **OS**: NixOS 25.11 (Xantusia)
- **Nix**: 2.31.4
- **Kernel**: 6.12.83
- **Current approach**: Cross-compilation from x86_64

---

## Comparison: Before vs After

| Aspect                  | Original (`build/odroidhc4`)                       | New (`build/odroidhc4-repro`)                |
| ----------------------- | -------------------------------------------------- | -------------------------------------------- |
| **U-Boot source**       | Hardcoded store path (`/nix/store/...-u-boot.bin`) | Built from source + hash-verified blobs      |
| **Sandbox**             | Disabled (`enableSandbox = false`)                 | Fully enabled                                |
| **Reproducibility**     | Only works on the machine with the store path      | Any Nix machine can build it                 |
| **`meson-tools` usage** | `amlbootsig` for C2-style signing                  | `aml_encrypt_g12a` for G12A-style encryption |
| **nixos-hardware**      | Not used                                           | Not yet integrated (fan, DTB inlined)        |

---

## What Was Tried

### Option B: Cross-Build from x86_64

```bash
cd build/odroidhc4-repro
nix build .#u-boot --print-build-logs --impure
```

This was started but the user stopped it. The next step is to **run it to completion** and see if the U-Boot builds, then proceed to build the full SD image:

```bash
cd build/odroidhc4-repro
nix build .#sdImage --print-build-logs --impure
```

---

## Key Files

| File                                          | Purpose                                                      |
| --------------------------------------------- | ------------------------------------------------------------ |
| `build/odroidhc4-repro/flake.nix`             | Flake definition with `nixosSystem`, `packages`, `devShells` |
| `build/odroidhc4-repro/configuration.nix`     | NixOS config: fan, SSH, extlinux, SD image assembly          |
| `build/odroidhc4-repro/overlay/odroid-c4.nix` | **Key file** — buildable U-Boot derivation                   |

---

## Next Steps for Next Thread

1. **Run the U-Boot build to completion**:

   ```bash
   cd /home/jgetreu/dev2/Armbian2Nixos\ migration/build/odroidhc4-repro
   nix build .#u-boot --print-build-logs --impure
   ```

2. **If U-Boot succeeds**, build the full SD image:

   ```bash
   nix build .#sdImage --print-build-logs --impure
   ```

3. **If it fails**, debug the error (likely `aml_encrypt_g12a` availability or the `postFetch` cleanup step)

4. **Consider integrating** `nixos-hardware` module (already provides fancontrol, DTB) instead of inlining in `configuration.nix`

5. **Validate the image** on the actual Odroid HC4 hardware
