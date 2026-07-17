# Autogentoo

Autogentoo v1 is a public, interactive Gentoo installer: one Bash 5 executable, `dialog`, and the tools on official Gentoo minimal media. It installs an OpenRC UEFI base on amd64 or generic arm64/SBSA hardware, with an optional amd64 Hyprland workstation.

This is a destructive installer. Back up every disk that is attached to the machine. Review the final partition boundaries and preserved-partition list before typing the confirmation phrase.

## Run

Boot the official minimal ISO matching the target architecture with UEFI and Secure Boot disabled, connect to the internet, then:

```sh
chmod +x autogentoo
sudo ./autogentoo --dry-run
sudo ./autogentoo
```

Other public commands are `./autogentoo --help` and `./autogentoo --version`. There is intentionally no unattended configuration format.

The dry run performs preflight detection and the full non-secret TUI planning flow, and never asks for a password. It does not download, mount, format, partition, or chroot. A redacted log is kept under `/tmp`; a real installation also copies it to `/var/log/autogentoo.log` in the target.

## What it installs

- OpenRC, `gentoo-kernel-bin`, firmware/microcode, Btrfs tools, NetworkManager, sudo, GRUB, and a wheel user, with root locked by default.
- Btrfs `@` and `@home` subvolumes using `noatime,compress=zstd:1`. Nonzero swap gets a separate `@swap` subvolume and a `btrfs filesystem mkswapfile` swap file, outside root snapshots.
- UUID-based `fstab` and an initramfs. Whole-disk installs use the UEFI bootloader ID `Gentoo`; coexistence installs use `Gentoo-<root UUID>` to avoid colliding with another installation. Whole-disk installs also write the removable UEFI fallback path; coexistence installs do not.
- On amd64, the default workstation profile installs native Hyprland 0.55.4-r1 with XWayland, portals, PipeWire/WirePlumber, Waybar, Fuzzel, Foot, Mako, Hyprpaper, Hyprlock/Hypridle, NetworkManager applet, a polkit agent, clipboard/screenshot/media/brightness tools, fonts, and `firefox-bin`.
- The Hyprland profile uses `~/.config/hypr/hyprland.lua`, SDDM by default, or pinned GURU Ly on TTY 2. Select the `Autogentoo Hyprland` session at login; it creates a D-Bus user session, and the configuration starts Gentoo's PipeWire launcher.

Autogentoo pins Hyproverlay at `208de784dfeac00d87dfd153f27b3cd866243dff` and GURU at `d5bbb6ac453db1d1280eb0e1ab9e9685c6cd102b` while installing, then returns each repository to its normal branch for future syncs. Testing keywords are scoped to Hyproverlay and the Ly atom. The GURU SHA replaces the proposed `b9b3e1ac4765ed77fc6a29d753173e03f2d77f76`, which does not exist in the canonical repository or mirror.

NVIDIA workstations require the user to confirm Turing/GTX 1650 or newer hardware. They use the open NVIDIA kernel modules, Wayland support, distribution-kernel integration, and DRM modesetting. Hybrid graphics is best-effort. Older NVIDIA hardware can still use the base profile.

## Storage workflows

1. **Whole disk** erases a selected non-live disk and creates GPT, a 1 GiB FAT32 ESP, and a Btrfs root using the rest.
2. **Unallocated extent** requires GPT, never resizes a neighbor, and consumes one 1 MiB-aligned usable range inside a chosen free extent (alignment slivers can remain). It reuses a same-disk FAT32 ESP with at least 32 MiB proven free, or creates a 1 GiB ESP in the chosen extent.
3. **Replace partition** formats only one unmounted ordinary GPT Linux partition and requires a reusable same-disk FAT32 ESP.

“Erase” means rewriting signatures, the partition table, and filesystems; it is not a secure overwrite or cryptographic erase, and old data can remain recoverable from untouched blocks.

The installer rejects mounted or read-only targets and descendants, live-media ancestors, active swap, active or offline multi-device Btrfs members, and LVM/RAID/dm-crypt or other storage-stack member signatures. It also rejects non-GPT coexistence, unsuitable ESP/recovery/swap partitions, and undersized roots. Minimum root sizes are 12 GiB for base and 32 GiB for desktop.

Typed confirmation is exact: `ERASE <disk>`, `CREATE IN <disk>`, or `FORMAT <partition>`. Device sequence, size, sector geometry, and selected partition identities are captured with the menu choices, checked after confirmation, and checked again after new partition nodes appear but before formatting.

Before the first disk write, the installer downloads the small signed Gentoo metadata, dearmors the configured Gentoo release key, and parses only cleartext authenticated by `gpgv`. The signed stage path, size, and SHA-512 digest are validated. The larger stage archive is downloaded into a temporary directory on the target filesystem, checked by detached signature, size, and SHA-512 digest, and removed immediately after extraction.

Password entry is hashed with a random-salt SHA-512 crypt hash inside a short-lived subprocess before installer-created swap is activated; the parent installer retains only the hash. Any configured swap remains unencrypted.

Swap is editable from zero to a space-safe maximum. The default follows the Gentoo Handbook bands and is reduced when needed to preserve 8 GiB for base files or 24 GiB for desktop files and builds. Portage uses `-O2 -pipe` plus `-march=native` on amd64 or `-mcpu=native` on arm64; build jobs are capped by both CPU threads and one job per 2 GiB RAM. Separate emerges are never parallelized.

## Deliberate limits

There is no encryption, hibernation, Secure Boot signing, BIOS boot, board-specific ARM firmware, filesystem resizing, snapshot manager, dotfile import, custom ISO, `os-prober`, or checkpoint/resume engine. Recovery is a clean rerun after inspecting the retained log.

## Tests

The framework-free test script exercises validators, signed-stage parsing and verified-output provenance, storage identity and fail-closed protections, swap and Portage calculations, cleanup failures, environment sanitization, CLI status, and the dry-run write guard:

```sh
./tests/test.sh
```

An opt-in root test uses disposable sparse loop disks, including a 4 KiB-sector loop device, to exercise the three storage workflows, sentinel preservation, Btrfs subvolumes, and Btrfs swap:

```sh
sudo AUTOGENTOO_DESTRUCTIVE_TESTS=1 ./tests/test.sh
```

Release acceptance additionally requires disposable QEMU UEFI boots for amd64 and arm64 base, separate SDDM and Ly virtio-gpu workstation boots, failure injection, and one physical Turing-or-newer NVIDIA run. Those hardware/firmware tests are not faked by the shell test.

## References

- [Gentoo Handbook: disks and swap](https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Disks)
- [Gentoo Handbook: stages and build jobs](https://wiki.gentoo.org/wiki/Handbook:AMD64/Installation/Stage)
- [Btrfs swapfile rules](https://btrfs.readthedocs.io/en/stable/btrfs-man5.html)
- [Hyprland 0.55 Lua configuration](https://wiki.hypr.land/Configuring/Start/)
- [Hyprland NVIDIA guidance](https://wiki.hypr.land/Nvidia/)

## License

GPL-2.0-or-later. See [LICENSE](LICENSE).
