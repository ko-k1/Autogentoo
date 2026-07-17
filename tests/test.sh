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
assert_true() { "$@"; pass=$((pass + 1)); }
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
assert_false available_username daemon
assert_false available_username sddm
assert_true valid_locale en_US.UTF-8
assert_true valid_locale sr_RS.UTF-8@latin
assert_false valid_locale '../etc/passwd'
assert_true valid_layout us
assert_false valid_layout 'us;reboot'
mkdir -p "$TEST_TMP/keymaps"
: >"$TEST_TMP/keymaps/us.map.gz"
assert_true supported_keymap us "$TEST_TMP/keymaps"
assert_false supported_keymap missing "$TEST_TMP/keymaps"
assert_true valid_timezone UTC
assert_false valid_timezone zone.tab

test_password_hash=$(hash_password 'correct horse battery staple')
assert_true valid_password_hash "$test_password_hash"
assert_false valid_password_hash 'correct horse battery staple'
unset test_password_hash

assert_eq "$(jobs_for 16 1024)" 1 "sub-2-GiB RAM still permits one job"
assert_eq "$(jobs_for 16 8192)" 4 "RAM caps build jobs"
assert_eq "$(jobs_for 2 65536)" 2 "CPU caps build jobs"

make_conf_includes_virtual_gpu_support() (
    TARGET="$TEST_TMP/make-conf-target"
    ARCH=amd64 CPU_THREADS=4 RAM_MIB=8192 NVIDIA=0
    mkdir -p "$TARGET/etc/portage"
    write_make_conf
    grep -Fqx 'VIDEO_CARDS="amdgpu radeonsi intel virgl"' \
        "$TARGET/etc/portage/make.conf"
)
assert_true make_conf_includes_virtual_gpu_support

base_install_reconciles_world_and_filesystems() (
    local -a calls=()
    ARCH=arm64 CPU_VENDOR=""
    chroot_run() { calls+=("$*"); }
    install_base
    [[ ${calls[0]} == '/usr/bin/emerge --sync' &&
        ${calls[1]} == *'--update --deep --newuse @world'* &&
        ${calls[1]} == *'sys-fs/btrfs-progs sys-fs/dosfstools'* ]]
)
assert_true base_install_reconciles_world_and_filesystems

desktop_packages_precede_login_creation() (
    local order=""
    PROFILE=desktop
    storage_plan_still_valid() { :; }
    prepare_stage_metadata() { :; }
    run() { :; }
    setup_storage() { :; }
    mount_layout() { :; }
    download_and_extract_stage() { :; }
    bind_chroot_filesystems() { :; }
    write_system_configuration() { :; }
    install_base() { :; }
    install_desktop() { order+=D; }
    create_user() { order+=U; }
    write_hyprland_config() { order+=C; }
    write_fstab() { :; }
    install_bootloader() { :; }
    perform_install
    [[ $order == DUC ]]
)
assert_true desktop_packages_precede_login_creation

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

assert_eq "$(bounded_uint 08 10)" 8 "leading-zero integer normalization"
assert_eq "$(bounded_uint 0 10)" 0 "zero is a valid bounded integer"
assert_false bounded_uint 11 10
assert_false bounded_uint 9999999999999999999 999999999999999999
assert_eq "$(aligned_extent 2049 10000 512)" "4096 8191 4096" "512-byte-sector alignment"
assert_eq "$(aligned_extent 257 999 4096)" "512 767 256" "4-KiB-sector alignment"

assert_eq "$(partition_name /dev/sda 3)" /dev/sda3
assert_eq "$(partition_name /dev/nvme0n1 3)" /dev/nvme0n1p3
assert_eq "$(partition_name /dev/mmcblk0 2)" /dev/mmcblk0p2
assert_eq "$(confirmation_phrase whole /dev/sda)" "ERASE /dev/sda"
assert_eq "$(confirmation_phrase unallocated /dev/nvme0n1)" "CREATE IN /dev/nvme0n1"
assert_eq "$(confirmation_phrase replace /dev/sda3)" "FORMAT /dev/sda3"
assert_true confirm_matches whole /dev/sda "ERASE /dev/sda"
assert_false confirm_matches whole /dev/sda "erase /dev/sda"

stage_name=stage3-amd64-openrc
stage_file=stage3-amd64-openrc-20260712T170110Z.tar.xz
stage_entry="20260712T170110Z/$stage_file 517734400"
assert_eq "$(stage_pointer_entry "$stage_name" "$stage_entry")" "$stage_entry" \
    "timestamp-directory stage pointer"
assert_false stage_pointer_entry "$stage_name" "$stage_file 517734400"
assert_false stage_pointer_entry "$stage_name" "../$stage_file 517734400"

blake=$(printf 'a%.0s' {1..128})
sha=$(printf 'b%.0s' {1..128})
cat >"$TEST_TMP/digests" <<EOF
# BLAKE2B HASH
$blake  $stage_file
# SHA512 HASH
$sha  $stage_file
EOF
assert_eq "$(sha512_digest "$TEST_TMP/digests" "$stage_file")" "$sha" \
    "SHA-512 is selected from its signed section"

ARCH=amd64 PROFILE=base
assert_eq "$(stage_pointer_url)" \
    "https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt" \
    "root stage pointer retains the signed timestamp path"
ARCH=amd64 PROFILE=desktop
assert_eq "$(stage_pointer_url)" \
    "https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-desktop-openrc.txt"
ARCH=arm64 PROFILE=base
assert_eq "$(stage_pointer_url)" \
    "https://distfiles.gentoo.org/releases/arm64/autobuilds/latest-stage3-arm64-openrc.txt"
ARCH=amd64 PROFILE=base

verified_metadata_only() (
    local good_timestamp=20260712T170110Z bad_timestamp=20200101T000000Z
    local expected
    expected=$(printf 'c%.0s' {1..128})
    mkdir -p "$TEST_TMP/metadata"
    mktemp() { printf '%s' "$TEST_TMP/metadata"; }
    stage_pointer_url() {
        printf 'https://distfiles.gentoo.org/releases/amd64/autobuilds/latest-%s.txt' "$stage_name"
    }
    run() {
        local command=$1 output=""
        local -a args
        shift
        args=("$@")
        while (($#)); do
            if [[ $1 == --output ]]; then
                (($# >= 2)) || return 98
                output=$2
                shift 2
                continue
            fi
            shift
        done
        case $command:$output in
            gpg:*)
                [[ ${#args[@]} -eq 7 &&
                    ${args[0]:-} == --no-options && ${args[1]:-} == --batch &&
                    ${args[2]:-} == --yes && ${args[3]:-} == --dearmor &&
                    ${args[4]:-} == --output &&
                    ${args[5]:-} == "$TEST_TMP/metadata/gentoo-release.gpg" &&
                    ${args[6]:-} == "$GENTOO_KEY" ]] || return 96
                : >"$output"
                ;;
            curl:*latest.txt)
                printf '%s/%s-%s.tar.xz 1\n' "$bad_timestamp" "$stage_name" "$bad_timestamp" >"$output"
                ;;
            curl:*.asc) : >"$output" ;;
            curl:*.DIGESTS)
                printf '# SHA512 HASH\n%s  attacker.tar.xz\n' "$blake" >"$output"
                ;;
            gpgv:*latest.verified)
                [[ ${#args[@]} -eq 7 &&
                    ${args[0]:-} == --homedir && ${args[1]:-} == "$TEST_TMP/metadata" &&
                    ${args[2]:-} == --output && ${args[3]:-} == "$output" &&
                    ${args[4]:-} == --keyring &&
                    ${args[5]:-} == "$TEST_TMP/metadata/gentoo-release.gpg" &&
                    ${args[6]:-} == "$TEST_TMP/metadata/latest.txt" ]] || return 97
                printf '%s/%s-%s.tar.xz 517734400\n' "$good_timestamp" "$stage_name" "$good_timestamp" >"$output"
                ;;
            gpgv:*.DIGESTS.verified)
                [[ ${#args[@]} -eq 7 &&
                    ${args[0]:-} == --homedir && ${args[1]:-} == "$TEST_TMP/metadata" &&
                    ${args[2]:-} == --output && ${args[3]:-} == "$output" &&
                    ${args[4]:-} == --keyring &&
                    ${args[5]:-} == "$TEST_TMP/metadata/gentoo-release.gpg" &&
                    ${args[6]:-} == "$TEST_TMP/metadata/$stage_name-$good_timestamp.tar.xz.DIGESTS" ]] ||
                    return 97
                printf '# SHA512 HASH\n%s  %s-%s.tar.xz\n' "$expected" "$stage_name" "$good_timestamp" >"$output"
                ;;
            gpgv:*) return 97 ;;
        esac
    }
    ARCH=amd64 PROFILE=base
    prepare_stage_metadata || return 1
    [[ $STAGE_PATH == "$good_timestamp/$stage_name-$good_timestamp.tar.xz" &&
        $STAGE_DIGEST == "$expected" ]]
)
assert_true verified_metadata_only

gpgv_homedir_is_supported() {
    mkdir -p "$TEST_TMP/gpgv-home"
    gpgv --homedir "$TEST_TMP/gpgv-home" --version >/dev/null 2>&1
}
assert_true gpgv_homedir_is_supported

real_gpg_verified_output_smoke() (
    local signer="$TEST_TMP/gpg-signer" verifier="$TEST_TMP/gpg-verifier"
    local user_id='Autogentoo test <autogentoo@example.invalid>'
    mkdir -m 0700 "$signer" "$verifier"
    printf 'signed stage pointer\n' >"$TEST_TMP/pointer"
    GNUPGHOME="$signer" gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
        --quick-generate-key "$user_id" ed25519 sign 0 >/dev/null 2>&1 || return 1
    GNUPGHOME="$signer" gpg --batch --quiet --yes --armor \
        --output "$TEST_TMP/release.asc" --export "$user_id" >/dev/null 2>&1 || return 1
    GNUPGHOME="$signer" gpg --batch --quiet --yes --armor --clearsign \
        --output "$TEST_TMP/pointer.asc" "$TEST_TMP/pointer" >/dev/null 2>&1 || return 1
    gpg --no-options --batch --yes --dearmor --output "$TEST_TMP/release.gpg" \
        "$TEST_TMP/release.asc" >/dev/null 2>&1 || return 1
    gpgv --homedir "$verifier" --output "$TEST_TMP/pointer.verified" \
        --keyring "$TEST_TMP/release.gpg" "$TEST_TMP/pointer.asc" >/dev/null 2>&1 ||
        return 1
    [[ $(<"$TEST_TMP/pointer.verified") == 'signed stage pointer' ]]
)
assert_true real_gpg_verified_output_smoke

fat_fixture=$'fsck.fat 4.2\nBoot sector contents:\n      4096 bytes per cluster\nChecking free cluster summary.\n/dev/test: 0 files, 1/129021 clusters'
assert_eq "$(fat_free_bytes_from_fsck <<<"$fat_fixture")" "$(((129021 - 1) * 4096))" \
    "FAT free bytes are derived from the real fsck.fat cluster format"

invalid_fat_summary_is_rejected() {
    fat_free_bytes_from_fsck <<<'4096 bytes per cluster'
}
assert_false invalid_fat_summary_is_rejected

fat_version_probe() (
    local expected_version=$1
    blkid() {
        [[ $# == 6 && $1 == -p && $2 == -s && $4 == -o &&
            $5 == value && $6 == /dev/fake ]] || return 95
        [[ $3 == TYPE ]] && printf 'vfat\n' || printf '%s\n' "$expected_version"
    }
    is_fat32 /dev/fake
)
assert_true fat_version_probe FAT32
assert_false fat_version_probe FAT16

protected_enumeration_fails_closed() (
    findmnt() { printf '/dev/fake\n'; return 55; }
    btrfs() { :; }
    protect_source_disk() { :; }
    build_protected_disks
)
assert_false protected_enumeration_fails_closed

offline_multidevice_btrfs_is_protected() (
    findmnt() { :; }
    btrfs() {
        [[ $# == 4 && $1 == filesystem && $2 == show &&
            $3 == --all-devices && $4 == --raw ]] || return 96
        printf 'Label: none  uuid: test\n\tTotal devices 2 FS bytes used 1\n\tdevid 1 size 1 used 1 path /dev/a\n\tdevid 2 size 1 used 1 path /dev/b\n'
    }
    protect_source_disk() { PROTECTED_DISKS["$1"]=1; }
    build_protected_disks
    [[ ${PROTECTED_DISKS[/dev/a]:-} == 1 && ${PROTECTED_DISKS[/dev/b]:-} == 1 ]]
)
assert_true offline_multidevice_btrfs_is_protected

loop_backing_file_protects_its_host_disk() (
    local backing_path="$TEST_TMP/live.squashfs"
    : >"$backing_path"
    losetup() {
        [[ $# == 5 && $1 == --noheadings && $2 == --raw &&
            $3 == --output && $4 == BACK-FILE && $5 == /dev/loop7 ]] || return 95
        printf '%s\n' "$backing_path"
    }
    findmnt() {
        [[ $# == 6 && $1 == -n && $2 == -e && $3 == -T &&
            $4 == "$backing_path" && $5 == -o && $6 == SOURCE ]] || return 95
        printf '/dev/sdz1\n'
    }
    protect_source_disk() {
        [[ $1 == /dev/sdz1 && $2 == 1 ]]
    }
    protect_loop_backing /dev/loop7 0
)
assert_true loop_backing_file_protects_its_host_disk

loop_ancestors_are_followed_through_stacked_devices() (
    local followed=0
    readlink() {
        [[ $# == 3 && $1 == -f && $2 == -- ]] || return 95
        printf '%s\n' "$3"
    }
    protect_loop_backing() {
        [[ $1 == /dev/loop7 && $2 == 0 ]] || return 95
        followed=1
    }
    protect_ancestor_rows $'/dev/mapper/live crypt\n/dev/loop7 loop' 0 || return 1
    (( followed == 1 ))
)
assert_true loop_ancestors_are_followed_through_stacked_devices

whole_device_stack_is_complex() (
    lsblk() { printf '/dev/sdz disk 0\n'; }
    blkid() { printf 'zfs_member\n'; }
    disk_has_complex_stack /dev/sdz
)
assert_true whole_device_stack_is_complex

readonly_child_is_complex() (
    lsblk() { printf '/dev/sdz disk 0\n/dev/sdz1 part 1\n'; }
    blkid() { return 2; }
    disk_has_complex_stack /dev/sdz
)
assert_true readonly_child_is_complex

regular_target_is_rejected() (
    TARGET=$LOG
    storage_plan_still_valid
)
assert_false regular_target_is_rejected

assert_true env TAR_OPTIONS='--checkpoint=1 --checkpoint-action=exec=sh' \
    OPENSSL_CONF=/tmp/untrusted-openssl.cnf \
    /bin/bash -c 'source "$1"; [[ -z ${TAR_OPTIONS+x} && -z ${OPENSSL_CONF+x} ]]' \
    _ "$ROOT/autogentoo"

(
    mktemp() { printf '%s' "$TEST_TMP/dry-run.log"; }
    preflight() { :; }
    collect_profile() { :; }
    collect_storage() { :; }
    collect_swap() { :; }
    collect_identity() { :; }
    review_and_confirm() { :; }
    perform_install() { touch "$TEST_TMP/main-must-not-write"; }
    main --dry-run
)
[[ ! -e $TEST_TMP/main-must-not-write ]] || fail "dry-run entered the installation path"
pass=$((pass + 1))

cleanup_without_password() (
    trap - ERR EXIT
    unset USER_PASSWORD_HASH
    OUR_SWAP="" STAGE_DIR="" WORKDIR=""
    TARGET_ACTIVE=1
    TARGET="$TEST_TMP/cleanup-target"
    mkdir -p "$TARGET"
    mountpoint() { return 0; }
    umount() { : >"$TEST_TMP/cleanup-reached"; }
    cleanup
)
assert_true cleanup_without_password
[[ -e $TEST_TMP/cleanup-reached ]] || fail "cleanup stopped before unmount"
pass=$((pass + 1))

cleanup_failure_is_reported() (
    trap - ERR EXIT
    USER_PASSWORD_HASH=hash
    OUR_SWAP="" STAGE_DIR="" WORKDIR=""
    TARGET_ACTIVE=1
    TARGET="$TEST_TMP/cleanup-failure-target"
    mkdir -p "$TARGET"
    mountpoint() { return 0; }
    umount() { return 1; }
    cleanup
) 2>/dev/null
assert_false cleanup_failure_is_reported

cleanup_swapoff_failure_is_reported() (
    trap - ERR EXIT
    USER_PASSWORD_HASH=hash
    OUR_SWAP="$TEST_TMP/missing-swap"
    STAGE_DIR="" WORKDIR=""
    TARGET_ACTIVE=0
    swapoff() { return 42; }
    cleanup
) 2>/dev/null
assert_false cleanup_swapoff_failure_is_reported

cleanup_mount_inspection_failure_is_reported() (
    trap - ERR EXIT
    USER_PASSWORD_HASH=hash
    OUR_SWAP="" STAGE_DIR="" WORKDIR=""
    TARGET_ACTIVE=1
    TARGET="$TEST_TMP/cleanup-inspection-target"
    mkdir -p "$TARGET"
    mountpoint() { return 2; }
    cleanup
) 2>/dev/null
assert_false cleanup_mount_inspection_failure_is_reported

changed_disk_sequence_is_rejected() (
    DISK=/dev/fake
    ORIGINAL_DISKSEQ=7 ORIGINAL_DISK_BYTES=1000 ORIGINAL_SECTOR_SIZE=512
    disk_state() { printf '8 1000 512'; }
    disk_state_still_valid
)
assert_false changed_disk_sequence_is_rejected

whole_disk_boot_fallback_precedes_nvram() (
    local -a calls=()
    TARGET="$TEST_TMP/boot-target" ROOT_PART=/dev/root ARCH=amd64 MODE=whole
    find() { printf '6.12.1-gentoo\n'; }
    blkid() { printf 'root-uuid\n'; }
    chroot_run() {
        calls+=("$*")
        if [[ $1 == /usr/sbin/grub-install && $* != *--removable* ]]; then
            return 55
        fi
    }
    install_bootloader || return 1
    [[ ${#calls[@]} == 4 &&
        ${calls[1]} == '/usr/sbin/grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo --removable' &&
        ${calls[2]} == '/usr/sbin/grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=Gentoo' &&
        ${calls[3]} == '/usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg' ]]
)
assert_true whole_disk_boot_fallback_precedes_nvram

coexistence_boot_id_is_unique() (
    local -a calls=()
    TARGET="$TEST_TMP/boot-target" ROOT_PART=/dev/root ARCH=arm64 MODE=replace
    find() { printf '6.12.1-gentoo\n'; }
    blkid() { printf '1234-abcd\n'; }
    chroot_run() { calls+=("$*"); }
    install_bootloader || return 1
    [[ ${#calls[@]} == 3 &&
        ${calls[1]} == '/usr/sbin/grub-install --target=arm64-efi --efi-directory=/efi --bootloader-id=Gentoo-1234-abcd' ]]
)
assert_true coexistence_boot_id_is_unique

cli_status=0
"$ROOT/autogentoo" --not-an-option >"$TEST_TMP/cli.out" 2>"$TEST_TMP/cli.err" || cli_status=$?
assert_eq "$cli_status" 2 "invalid option exit status"
assert_false grep -q 'No such file' "$TEST_TMP/cli.err"

run_destructive_tests() {
    local required=(
        losetup truncate parted partprobe udevadm lsblk findmnt blockdev blkid
        wipefs mkfs.fat fsck.fat mkfs.btrfs btrfs mount mountpoint umount
        swapon swapoff readlink sort head grep tee
    )
    local command image loop esp sentinel start end extents aligned
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

    remember_loop_state() {
        local state
        state=$(disk_state "$1") || fail "could not capture loop-device identity"
        read -r ORIGINAL_DISKSEQ ORIGINAL_DISK_BYTES ORIGINAL_SECTOR_SIZE <<<"$state"
        SECTOR_SIZE=$ORIGINAL_SECTOR_SIZE
    }

    TARGET="$TEST_TMP/mnt"
    mkdir -p "$TARGET"

    image="$TEST_TMP/whole.img"
    truncate -s 3G "$image"
    loop=$(losetup --find --show --partscan "$image")
    loops+=("$loop")
    MODE=whole DISK=$loop ESP_ACTION=create SWAP_MIB=64
    ORIGINAL_ROOT_ID="" ORIGINAL_ESP_ID=""
    remember_loop_state "$loop"
    plan_whole_layout
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
    udevadm settle
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
    extents=$(free_extents "$loop") || fail "could not enumerate the test free extent"
    read -r start end _ <<<"$(sort -k3,3nr <<<"$extents" | head -n1)"
    aligned=$(aligned_extent "$start" "$end" 4096) || fail "could not align the test free extent"
    read -r start end _ <<<"$aligned"
    MODE=unallocated DISK=$loop ESP_ACTION=reuse ESP_PART=$esp
    remember_loop_state "$loop"
    ORIGINAL_ROOT_ID=""
    ORIGINAL_ESP_ID=$(partition_identity "$ESP_PART") || fail "could not capture the test ESP identity"
    GAP_START=$start ROOT_START=$start ROOT_END=$end
    ROOT_BYTES=$(((ROOT_END - ROOT_START + 1) * SECTOR_SIZE))
    ORIGINAL_ROOT_BYTES=$ROOT_BYTES
    setup_storage
    [[ -b $sentinel ]] || fail "unallocated mode removed a neighbor partition"
    mount "$esp" "$TEST_TMP/esp"
    assert_eq "$(cat "$TEST_TMP/esp/keep")" sentinel "unallocated mode preserved ESP contents"
    umount "$TEST_TMP/esp"
    assert_eq "$(blockdev --getss "$loop")" 4096 "4-KiB sector loop disk"
    losetup -d "$loop"
    udevadm settle
    loops=()

    image="$TEST_TMP/unallocated-create.img"
    truncate -s 4G "$image"
    loop=$(losetup --find --show --partscan "$image")
    loops+=("$loop")
    parted -s "$loop" mklabel gpt
    parted -s "$loop" mkpart sentinel 3500MiB 3600MiB
    partprobe "$loop"
    udevadm settle
    sentinel=$(partition_name "$loop" 1)
    extents=$(free_extents "$loop") || fail "could not enumerate the create-ESP test extent"
    read -r start end _ <<<"$(sort -k3,3nr <<<"$extents" | head -n1)"
    aligned=$(aligned_extent "$start" "$end" 512) ||
        fail "could not align the create-ESP test extent"
    read -r start end _ <<<"$aligned"
    MODE=unallocated DISK=$loop ESP_ACTION=create ESP_PART="(new)" SWAP_MIB=0
    ORIGINAL_ROOT_ID="" ORIGINAL_ESP_ID=""
    remember_loop_state "$loop"
    GAP_START=$start
    ROOT_START=$((start + GIB / SECTOR_SIZE))
    ROOT_END=$end
    ROOT_BYTES=$(((ROOT_END - ROOT_START + 1) * SECTOR_SIZE))
    ORIGINAL_ROOT_BYTES=$ROOT_BYTES
    setup_storage
    [[ -b $sentinel ]] || fail "new-ESP mode removed a neighbor partition"
    pass=$((pass + 1))
    assert_eq "$(blkid -s VERSION -o value "$ESP_PART")" FAT32 \
        "unallocated mode creates a FAT32 ESP"
    assert_eq "$(blkid -s TYPE -o value "$ROOT_PART")" btrfs \
        "unallocated mode creates a Btrfs root"
    losetup -d "$loop"
    udevadm settle
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
    remember_loop_state "$loop"
    ORIGINAL_ROOT_ID=$(partition_identity "$ROOT_PART") || fail "could not capture the test root identity"
    ORIGINAL_ESP_ID=$(partition_identity "$ESP_PART") || fail "could not capture the test ESP identity"
    ROOT_BYTES=$(blockdev --getsize64 "$ROOT_PART")
    ORIGINAL_ROOT_BYTES=$ROOT_BYTES
    setup_storage
    assert_eq "$(blkid -s TYPE -o value "$ROOT_PART")" btrfs "replace mode formats only root"
    [[ -b $sentinel ]] || fail "replace mode removed a sentinel partition"
    pass=$((pass + 1))
    losetup -d "$loop"
    udevadm settle
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
