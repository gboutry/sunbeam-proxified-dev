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
    """Get list of all block devices from /sys/block/."""
    block_dir = Path("/sys/block")
    if not block_dir.exists():
        raise RuntimeError("/sys/block not found")

    devices = []
    for device in block_dir.iterdir():
        # Skip loop devices
        if device.name.startswith("loop"):
            continue
        # Skip ram devices
        if device.name.startswith("ram"):
            continue
        devices.append(device.name)
    return devices


def get_disk_size(device):
    """Get the size of a disk in bytes."""
    size_file = Path(f"/sys/block/{device}/size")
    if not size_file.exists():
        return 0

    # Size is in 512-byte sectors
    try:
        with open(size_file) as f:
            sectors = int(f.read().strip())
            return sectors * 512
    except (IOError, ValueError):
        return 0


def is_partition(device):
    """Check if the device is a partition (not a whole disk)."""
    # A device is a partition if it has a directory in /sys/block/*/device
    # or if its name contains a number (e.g., sda1, nvme0n1p1)
    # For whole disks like sda, there's typically no /sys/block/sda/device
    device_path = Path(f"/sys/block/{device}")

    # Check if it's a partition by looking at the device link
    device_file = Path(f"/dev/{device}")
    if device_file.is_symlink():
        target = device_file.resolve()
        # Partitions are typically linked to ../devices/...
        if "part" in str(target):
            return True

    # Check if it's an NVMe partition (ends with p followed by number)
    if re.match(r".*nvme\d+n?\d+p\d+$", device):
        return True

    # Check if device name ends with a number (partition naming convention)
    if re.search(r"\d+$", device):
        # But not if it's a whole NVMe (nvme0n1 is whole, nvme0n1p1 is partition)
        if not re.match(r"nvme\d+n?\d+$", device):
            return True

    return False


def is_in_use(device):
    """Check if the disk is currently in use (mounted, part of LVM, etc.)."""
    # Check if mounted
    try:
        result = subprocess.run(
            ["lsblk", "-o", "MOUNTPOINT", "-n", f"/dev/{device}"],
            capture_output=True,
            text=True
        )
        mountpoint = result.stdout.strip()
        if mountpoint:
            return True
    except Exception:
        pass

    # Check if part of LVM
    lvm_path = Path(f"/sys/block/{device}/dm")
    if lvm_path.exists():
        return True

    # Check if it's a LUKS container
    crypt_path = Path(f"/sys/block/{device}/crypt")
    if crypt_path.exists():
        return True

    return False


def get_disk_info(device):
    """Get detailed information about a disk."""
    # Get rotational (HDD vs SSD)
    rotational_file = Path(f"/sys/block/{device}/queue/rotational")
    is_rotational = False
    if rotational_file.exists():
        try:
            with open(rotational_file) as f:
                is_rotational = f.read().strip() == "1"
        except IOError:
            pass

    # Get device model/vendor
    device_path = Path(f"/sys/block/{device}/device")
    model = "Unknown"
    vendor = "Unknown"
    if device_path.exists():
        model_file = device_path / "model"
        vendor_file = device_path / "vendor"
        if model_file.exists():
            try:
                model = model_file.read_text().strip()
            except IOError:
                pass
        if vendor_file.exists():
            try:
                vendor = vendor_file.read_text().strip()
            except IOError:
                pass

    return {
        "device": device,
        "path": f"/dev/{device}",
        "rotational": is_rotational,
        "model": model,
        "vendor": vendor,
    }


def find_largest_unused_disk():
    """Find the largest unused disk on the system."""
    devices = get_block_devices()

    largest_disk = None
    largest_size = 0
    largest_info = None

    for device in devices:
        # Skip partitions
        if is_partition(device):
            continue

        # Skip in-use disks
        if is_in_use(device):
            continue

        size = get_disk_size(device)
        if size > largest_size:
            largest_size = size
            largest_disk = device
            largest_info = get_disk_info(device)
            largest_info["size"] = size

    return largest_info


def format_size(size_bytes):
    """Format size in human-readable form."""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size_bytes < 1024:
            return f"{size_bytes:.1f}{unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f}PB"


def main():
    try:
        disk = find_largest_unused_disk()

        if disk is None:
            print("No unused disk found", file=__import__("sys").stderr)
            return 1

        print(f"Device: {disk['path']}")
        print(f"Size: {format_size(disk['size'])}")
        print(f"Type: {'HDD' if disk['rotational'] else 'SSD'}")
        print(f"Model: {disk['model']}")
        print(f"Vendor: {disk['vendor']}")
        print(f"---")
        print(disk["path"])

        return 0

    except Exception as e:
        print(f"Error: {e}", file=__import__("sys").stderr)
        return 1


if __name__ == "__main__":
    exit(main())
