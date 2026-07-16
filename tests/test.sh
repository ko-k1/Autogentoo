#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later

set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=autogentoo
source "$ROOT/autogentoo"
trap - ERR EXIT

TEST_TMP=$(mktemp -d /tmp/autogentoo-test.XXXXXX)
LOG="$TEST_TMP/test.log"
: >"$LOG"

pass=0
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
assert_eq() { [[ $1 == "$2" ]] || fail "${3:-expected $2, got $1}"; pass=$((pass + 1)); }
assert_true() { "$@" || fail "expected success: $*"; pass=$((pass + 1)); }
assert_false() { ! "$@" || fail "expected failure: $*"; pass=$((pass + 1)); }

assert_eq "$(arch_name x86_64)" amd64 "x86_64 architecture mapping"
assert_eq "$(arch_name aarch64)" arm64 "aarch64 architecture mapping"
assert_false arch_name riscv64

assert_true valid_hostname gentoo
assert_true valid_hostname host-1.example
assert_false valid_hostname -gentoo
assert_false valid_hostname 'bad host'
assert_true valid_username alice_1
assert_false valid_username root
assert_false valid_username 'Alice'
assert_true valid_locale en_US.UTF-8
assert_false valid_locale '../etc/passwd'
assert_true valid_layout us
assert_false valid_layout 'us;reboot'

assert_eq "$(jobs_for 16 1024)" 1 "sub-2-GiB RAM still permits one job"
assert_eq "$(jobs_for 16 8192)" 4 "RAM caps build jobs"
assert_eq "$(jobs_for 2 65536)" 2 "CPU caps build jobs"

assert_eq "$(swap_limits 1024 20000 base)" "2048 11808" "small-RAM swap"
assert_eq "$(swap_limits 2048 20000 base)" "4096 11808" "2-GiB boundary"
assert_eq "$(swap_limits 4096 20000 base)" "4096 11808" "mid-RAM swap"
assert_eq "$(swap_limits 8192 40000 desktop)" "8192 15424" "8-GiB boundary"
assert_eq "$(swap_limits 20000 50000 desktop)" "16384 25424" "16-GiB clamp"
assert_eq "$(swap_limits 65536 50000 desktop)" "8192 25424" "64-GiB boundary"
assert_eq "$(swap_limits 8192 25000 desktop)" "424 424" "desktop space cap"
assert_eq "$(swap_limits 8192 8000 base)" "0 0" "zero swap when reserve consumes root"
assert_eq "$(minimum_root_mib base)" 12288
assert_eq "$(minimum_root_mib desktop)" 32768
assert_true root_size_ok "$((12288 * MIB))" base
assert_false root_size_ok "$((12288 * MIB - 1))" base
assert_true root_size_ok "$((32768 * MIB))" desktop
assert_false root_size_ok "$((32768 * MIB - 1))" desktop

assert_eq "$(partition_name /dev/sda 3)" /dev/sda3
assert_eq "$(partition_name /dev/nvme0n1 3)" /dev/nvme0n1p3
assert_eq "$(partition_name /dev/mmcblk0 2)" /dev/mmcblk0p2
assert_eq "$(confirmation_phrase whole /dev/sda)" "ERASE /dev/sda"
assert_eq "$(confirmation_phrase unallocated /dev/nvme0n1)" "CREATE IN /dev/nvme0n1"
assert_eq "$(confirmation_phrase replace /dev/sda3)" "FORMAT /dev/sda3"
assert_true confirm_matches whole /dev/sda "ERASE /dev/sda"
assert_false confirm_matches whole /dev/sda "erase /dev/sda"

(
    mktemp() { printf '%s' "$TEST_TMP/dry-run.log"; }
    preflight() { :; }
    collect_profile() { :; }
    collect_storage() { :; }
    collect_swap() { :; }
    collect_identity() { :; }
    review_and_confirm() { return 1; }
    perform_install() { touch "$TEST_TMP/main-must-not-write"; }
    main --dry-run
)
[[ ! -e $TEST_TMP/main-must-not-write ]] || fail "dry-run entered the installation path"
pass=$((pass + 1))

run_destructive_tests() {
    local required=(losetup parted mkfs.fat mkfs.btrfs btrfs mount umount swapon swapoff)
    local command image loop esp sentinel start end
    [[ $EUID -eq 0 ]] || fail "destructive loop tests require root"
    for command in "${required[@]}"; do command -v "$command" >/dev/null || fail "missing $command"; done

    local loops=()
    cleanup_loops() {
        set +e
        [[ -n ${OUR_SWAP:-} ]] && swapoff "$OUR_SWAP" 2>/dev/null
        mountpoint -q "$TARGET" 2>/dev/null && umount -R "$TARGET"
        for loop in "${loops[@]}"; do losetup -d "$loop" 2>/dev/null; done
    }
    trap cleanup_loops EXIT

    TARGET="$TEST_TMP/mnt"
    mkdir -p "$TARGET"

    image="$TEST_TMP/whole.img"
    truncate -s 3G "$image"
    loop=$(losetup --find --show --partscan "$image")
    loops+=("$loop")
    MODE=whole DISK=$loop ESP_ACTION=create SWAP_MIB=64
    plan_whole_layout "$loop"
    setup_storage
    mount_layout
    btrfs subvolume list "$TARGET" | grep -q 'path @'
    btrfs subvolume list "$TARGET" | grep -q 'path @home'
    btrfs subvolume list "$TARGET" | grep -q 'path @swap'
    swapon --show=NAME --noheadings | grep -Fxq "$OUR_SWAP"
    pass=$((pass + 4))
    swapoff "$OUR_SWAP"
    OUR_SWAP=""
    umount -R "$TARGET"
    losetup -d "$loop"
    loops=()

    image="$TEST_TMP/unallocated-4k.img"
    truncate -s 4G "$image"
    loop=$(losetup --find --show --partscan --sector-size 4096 "$image")
    loops+=("$loop")
    parted -s "$loop" mklabel gpt
    parted -s "$loop" mkpart ESP fat32 1MiB 257MiB
    parted -s "$loop" set 1 esp on
    parted -s "$loop" mkpart sentinel 3500MiB 3600MiB
    partprobe "$loop"
    udevadm settle
    esp=$(partition_name "$loop" 1)
    sentinel=$(partition_name "$loop" 2)
    mkfs.fat -F 32 "$esp" >/dev/null
    mkdir -p "$TEST_TMP/esp"
    mount "$esp" "$TEST_TMP/esp"
    printf sentinel >"$TEST_TMP/esp/keep"
    umount "$TEST_TMP/esp"
    read -r start end _ < <(free_extents "$loop" | sort -k3,3nr | head -n1)
    MODE=unallocated DISK=$loop ESP_ACTION=reuse ESP_PART=$esp
    ROOT_START=$start ROOT_END=$end
    setup_storage
    [[ -b $sentinel ]] || fail "unallocated mode removed a neighbor partition"
    mount "$esp" "$TEST_TMP/esp"
    assert_eq "$(cat "$TEST_TMP/esp/keep")" sentinel "unallocated mode preserved ESP contents"
    umount "$TEST_TMP/esp"
    assert_eq "$(blockdev --getss "$loop")" 4096 "4-KiB sector loop disk"
    losetup -d "$loop"
    loops=()

    image="$TEST_TMP/replace.img"
    truncate -s 3G "$image"
    loop=$(losetup --find --show --partscan "$image")
    loops+=("$loop")
    parted -s "$loop" mklabel gpt
    parted -s "$loop" mkpart ESP fat32 1MiB 257MiB
    parted -s "$loop" set 1 esp on
    parted -s "$loop" mkpart root ext4 257MiB 2500MiB
    parted -s "$loop" mkpart sentinel 2500MiB 2600MiB
    partprobe "$loop"
    udevadm settle
    ESP_PART=$(partition_name "$loop" 1)
    ROOT_PART=$(partition_name "$loop" 2)
    sentinel=$(partition_name "$loop" 3)
    mkfs.fat -F 32 "$ESP_PART" >/dev/null
    MODE=replace DISK=$loop ESP_ACTION=reuse SWAP_MIB=0
    setup_storage
    assert_eq "$(blkid -s TYPE -o value "$ROOT_PART")" btrfs "replace mode formats only root"
    [[ -b $sentinel ]] || fail "replace mode removed a sentinel partition"
    pass=$((pass + 1))
    losetup -d "$loop"
    loops=()
    trap - EXIT
}

if [[ ${AUTOGENTOO_DESTRUCTIVE_TESTS:-0} == 1 ]]; then
    run_destructive_tests
else
    printf 'ok - destructive loop tests skipped (set AUTOGENTOO_DESTRUCTIVE_TESTS=1 as root)\n'
fi

rm -rf "$TEST_TMP"
printf 'ok - %d assertions\n' "$pass"
