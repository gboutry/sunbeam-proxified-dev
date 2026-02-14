#!/usr/bin/env python3
"""
Find the largest unused disk on a physical machine.
Useful for creating an LXD storage pool.
"""

import os
import subprocess
import re
from pathlib import Path


def get_block_devices():
    """Get list of all block devices from /sys/block."""
    devices = []
    sys_block = Path("/sys/block")

    if not sys_block.exists():
        raise RuntimeError("/sys/block not found. Are you running on a Linux system?")

    for device in sys_block.iterdir():
        if device.name.startswith(("sd", "nvme", "vd", "hd", "sr")):
            # Skip partitions (e.g., sda1) - only want whole disks
            if not re.match(r'.*\d+$', device.name):
                devices.append(device.name)

    return sorted(devices)


def is_disk_used(disk_name):
    """
    Check if a disk is already in use.
    Returns True if the disk is used, False if it's available.
    """
    # Check 1: Is the disk mounted?
    try:
        with open("/proc/mounts", "r") as f:
            for line in f:
                if f"/dev/{disk_name}" in line:
                    return True
    except IOError:
        pass

    # Check 2: Does the disk have a filesystem (blkid)?
    try:
        result = subprocess.run(
            ["blkid", "-o", "device"],
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode == 0:
            mounted_devices = result.stdout.strip().split("\n")
            if f"/dev/{disk_name}" in mounted_devices:
                return True
    except FileNotFoundError:
        pass  # blkid not available

    # Check 3: Is the disk part of an LVM physical volume?
    try:
        result = subprocess.run(
            ["pvs", "--noheadings", "-o", "pv_name"],
            capture_output=True,
            text=True,
            check=False
        )
        if result.returncode == 0:
            pvs = result.stdout.strip().split("\n")
            if f"/dev/{disk_name}" in [pv.strip() for pv in pvs]:
                return True
    except FileNotFoundError:
        pass  # lvm2 not available

    # Check 4: Is the disk part of a RAID array?
    md_stat = Path(f"/proc/mdstat")
    if md_stat.exists():
        try:
            with open(md_stat, "r") as f:
                content = f.read()
                if disk_name in content:
                    return True
        except IOError:
            pass

    # Check 5: Check if disk is a LUKS container
    cryptsetup = Path(f"/sys/class/block/{disk_name}/holders")
    if cryptsetup.exists():
        try:
            holders = list(cryptsetup.iterdir())
            if holders:
                return True
        except OSError:
            pass

    # Check 6: Check if disk has partitions that are in use
    sys_block = Path(f"/sys/block/{disk_name}")
    if sys_block.exists():
        partitions = sys_block / "mmcblk0p" / "part"
        # For mmcblk0, partitions are mmcblk0p1, etc.
        if "mmcblk" in disk_name or "nvme" in disk_name:
            # Check for partition pattern
            partition_path = Path(f"/sys/block/{disk_name}")
            for child in partition_path.iterdir():
                if re.match(rf"{disk_name}p\d+", child.name):
                    # Check if partition is used
                    if child.exists() and list(child.iterdir()):
                        return True

    return False


def get_disk_size(disk_name):
    """Get the size of a disk in bytes."""
    size_file = Path(f"/sys/block/{disk_name}/size")
    try:
        with open(size_file, "r") as f:
            # Size is in 512-byte sectors
            sectors = int(f.read().strip())
            return sectors * 512
    except (IOError, ValueError):
        return 0


def format_size(size_bytes):
    """Format bytes to human-readable string."""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size_bytes < 1024:
            return f"{size_bytes:.1f}{unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f}PB"


def find_largest_unused_disk():
    """Find the largest unused disk on the system."""
    print("Scanning for block devices...")

    try:
        devices = get_block_devices()
    except RuntimeError as e:
        print(f"Error: {e}")
        return None

    if not devices:
        print("No block devices found.")
        return None

    unused_disks = []

    print(f"\nFound {len(devices)} disk(s): {', '.join(devices)}\n")

    for disk in devices:
        if is_disk_used(disk):
            print(f"  {disk}: used (skipping)")
            continue

        size = get_disk_size(disk)
        if size == 0:
            print(f"  {disk}: unable to determine size (skipping)")
            continue

        print(f"  {disk}: {format_size(size)} - available")
        unused_disks.append((disk, size))

    if not unused_disks:
        print("\nNo unused disks found.")
        return None

    # Sort by size (largest first)
    unused_disks.sort(key=lambda x: x[1], reverse=True)

    largest_disk, largest_size = unused_disks[0]

    print(f"\nLargest unused disk: /dev/{largest_disk} ({format_size(largest_size)})")

    return {
        "path": f"/dev/{largest_disk}",
        "name": largest_disk,
        "size": largest_size,
        "size_human": format_size(largest_size)
    }


def main():
    result = find_largest_unused_disk()

    if result:
        print(f"\nResult:")
        print(f"  Device: {result['path']}")
        print(f"  Size: {result['size_human']}")
        return result
    else:
        print("\nNo suitable disk found.")
        return None


if __name__ == "__main__":
    main()
