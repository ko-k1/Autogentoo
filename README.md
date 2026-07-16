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

The dry run performs preflight detection and the full TUI planning flow. It does not download, mount, format, partition, or chroot. A redacted log is kept under `/tmp`; a real installation also copies it to `/var/log/autogentoo.log` in the target.

## What it installs

- OpenRC, `gentoo-kernel-bin`, firmware/microcode, Btrfs tools, NetworkManager, sudo, GRUB, and a locked-root/wheel-user policy.
- Btrfs `@` and `@home` subvolumes using `noatime,compress=zstd:1`. Nonzero swap gets a separate `@swap` subvolume and a `btrfs filesystem mkswapfile` swap file, outside root snapshots.
- UUID-based `fstab`, an initramfs, and a GRUB entry named `Gentoo`. Whole-disk installs also write the removable UEFI fallback path; coexistence installs do not.
- On amd64, the default workstation profile installs native Hyprland 0.55.4-r1 with XWayland, portals, PipeWire/WirePlumber, Waybar, Fuzzel, Foot, Mako, Hyprpaper, Hyprlock/Hypridle, NetworkManager applet, a polkit agent, clipboard/screenshot/media/brightness tools, fonts, and `firefox-bin`.
- The Hyprland profile uses `~/.config/hypr/hyprland.lua`, SDDM by default, or pinned GURU Ly on TTY 2.

Autogentoo pins Hyproverlay at `208de784dfeac00d87dfd153f27b3cd866243dff` and GURU at `d5bbb6ac453db1d1280eb0e1ab9e9685c6cd102b` while installing, then returns each repository to its normal branch for future syncs. Testing keywords are scoped to Hyproverlay and the Ly atom. The GURU SHA replaces the proposed `b9b3e1ac4765ed77fc6a29d753173e03f2d77f76`, which does not exist in the canonical repository or mirror.

NVIDIA workstations require the user to confirm Turing/GTX 1650 or newer hardware. They use the open NVIDIA kernel modules, Wayland support, distribution-kernel integration, and DRM modesetting. Hybrid graphics is best-effort. Older NVIDIA hardware can still use the base profile.

## Storage workflows

1. **Whole disk** erases a selected non-live disk and creates GPT, a 1 GiB FAT32 ESP, and a Btrfs root using the rest.
2. **Unallocated extent** requires GPT, never resizes a neighbor, and consumes one exact free extent. It reuses a same-disk FAT ESP with at least 32 MiB proven free, or creates a 1 GiB ESP in the chosen extent.
3. **Replace partition** formats only one unmounted ordinary GPT Linux partition and requires a reusable same-disk ESP.

The installer rejects mounted or read-only targets, live-media ancestors, LVM/RAID/dm-crypt layouts, non-GPT coexistence, unsuitable ESP/recovery/swap partitions, and undersized roots. Minimum root sizes are 12 GiB for base and 32 GiB for desktop.

Typed confirmation is exact: `ERASE <disk>`, `CREATE IN <disk>`, or `FORMAT <partition>`. Storage state is checked again after confirmation and before the first write.

Swap is editable from zero to a space-safe maximum. The default follows the Gentoo Handbook bands and is reduced when needed to preserve 8 GiB for base files or 24 GiB for desktop files and builds. Portage uses `-O2 -pipe` plus `-march=native` on amd64 or `-mcpu=native` on arm64; build jobs are capped by both CPU threads and one job per 2 GiB RAM. Separate emerges are never parallelized.

## Deliberate limits

There is no encryption, hibernation, Secure Boot signing, BIOS boot, board-specific ARM firmware, filesystem resizing, snapshot manager, dotfile import, custom ISO, `os-prober`, or checkpoint/resume engine. Recovery is a clean rerun after inspecting the retained log.

## Tests

The framework-free test script exercises validators, architecture mapping, swap recommendations and caps, Portage job calculation, device naming, confirmation phrases, and the dry-run write guard:

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
