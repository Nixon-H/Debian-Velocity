# Debian-Velocity 🚀

**The Definitive Linux System Optimizer for High-Performance Workloads on Limited Hardware.**

![Bash](https://img.shields.io/badge/language-Bash-green.svg) ![Platform](https://img.shields.io/badge/platform-Debian%20%7C%20Ubuntu%20%7C%20Kali-orange.svg)

**Debian-Velocity** is an intelligent, menu-driven optimization suite designed to push the limits of Linux system responsiveness. It is engineered specifically for penetration testers, developers, and power users running heavy multitasking workloads (Burp Suite, Compiling, Virtual Machines) on hardware with limited physical RAM (4GB - 16GB).

Unlike generic scripts, Debian-Velocity implements a **Priority-Tiered Hybrid Memory Architecture**, forcing the kernel to use ultra-fast compressed RAM (ZRAM) as its primary workspace before ever touching your physical SSD.

---

## ⚡ Feature Breakdown

### 1. Hybrid Priority-Tiered Memory Architecture

Most optimization scripts force a choice: speed (ZRAM) or capacity (Disk Swap). **Debian-Velocity delivers both** using strict kernel priority rules:

* **Tier 1: High-Velocity ZRAM (Priority 100)**
* **Mechanism:** Creates a compressed block device in RAM using the **zstd** (Zstandard) algorithm.
* **Behavior:** The Kernel is forced to swap data here *first*. Because `zstd` offers high compression ratios (~3:1), 10GB of ZRAM effectively stores 30GB of data while only consuming ~3GB of actual physical RAM.
* **Speed:** Near-instantaneous read/write latency (nanoseconds).


* **Tier 2: SSD Swapfile Safety Net (Priority -2)**
* **Mechanism:** A standard swapfile located on your physical drive.
* **Behavior:** This tier acts as an "Overflow Buffer." The kernel will **only** touch your SSD if the ZRAM is 100% full.
* **Result:** You get the speed of RAM-disk computing with the crash-protection of a massive physical swap file.



### 2. Network Stack Modernization (TCP BBR)

By default, Linux uses "Cubic" congestion control, which can be inefficient on variable networks (like Wi-Fi).

* **Optimization:** Enables **Google's TCP BBR (Bottleneck Bandwidth and Round-trip propagation time)**.
* **Benefit:** drastically improves throughput and reduces latency on packet-lossy networks.
* **Use Case:** Critical for faster `git clones`, massive `apt updates`, and high-speed network scanning tools (Nmap/Masscan).

### 3. I/O & SSD Lifespan Preservation

* **`noatime` Mounting:** Linux default writes a metadata timestamp to the disk every time you simply *read* a file. This generates thousands of useless write operations. We remount the filesystem with `noatime` to eliminate this overhead, speeding up file access and extending SSD health.
* **`fstrim` Timer:** Enables the weekly SSD trim timer to ensure deleted blocks are properly wiped, maintaining long-term write performance.

### 4. Intelligent OOM (Out-Of-Memory) Prevention

* **Nohang (Monitor Mode):** Installs the `nohang` daemon to prevent system lockups.
* **Pentester-Safe Config:** Unlike standard configurations that aggressively kill high-RAM processes (like your Browser or Password Cracker), Debian-Velocity configures `nohang` in **non-lethal mode**. It monitors pressure to prevent hard freezes but will **not** automatically snipe your critical tools during a session.

### 5. CPU & Kernel Interrupt Tuning

* **Watchdog Disable:** Disables the NMI Watchdog (`nowatchdog nmi_watchdog=0`). This stops the OS from interrupting the CPU periodically to check for lockups, freeing up cycles for actual processing.
* **Governor Lock:** Forces the CPU scaling governor to `performance`, preventing the processor from downclocking to save power during heavy tasks.

---

## 📊 The "Velocity" Configuration Matrix

The script features an **Automatic Detection Mode** that calculates the optimal configuration based on your hardware.

| Detected Physical RAM | Optimization Profile | ZRAM Size (Tier 1) | SSD Swap Size (Tier 2) | Total Virtual Memory | Best Use Case |
| --- | --- | --- | --- | --- | --- |
| **< 2 GB** | ⛔ **Safety Abort** | N/A | N/A | N/A | System too weak for heavy optimization. |
| **2 GB - 3 GB** | **"Lightweight"** | **3 GB** | **4 GB** | **~9 GB** | Basic browsing, lightweight Linux usage. |
| **4 GB - 7 GB** | **"Standard"** | **6 GB** | **6 GB** | **~16 GB** | Coding, Web Development, Daily Driver. |
| **8 GB - 15 GB** | **"The Sweet Spot"** | **10 GB** | **10 GB** | **~28 GB** | **Pentesting, VMs, Heavy Multitasking.** |
| **16 GB +** | **"Power User"** | **10 GB** | **10 GB** | **36 GB+** | 4K Editing, Complex Compiling, Gaming. |

> **Note:** "Total Virtual Memory" represents the combined capacity of Physical RAM + ZRAM + Disk Swap, giving you massive headroom for memory-hungry applications.

---

## 🔧 Technical Deep Dive: Sysctl Parameters

Debian-Velocity applies specific values to `/etc/sysctl.conf` that might look "wrong" to a novice but are essential for ZRAM performance.

| Parameter | Value | Explanation |
| --- | --- | --- |
| `vm.swappiness` | **180** | **Aggressive Swapping.** Standard advice is "low swappiness (10 or 60)". However, with ZRAM, swapping is *faster* than dropping file caches. We want the system to aggressively push idle apps into ZRAM to keep Physical RAM free for your active window. |
| `vm.page-cluster` | **0** | **No Read-Ahead.** Standard spinning HDDs benefit from reading big blocks of data (Read-Ahead). ZRAM is random-access memory; it has no seek time. Setting this to 0 reduces latency by reading exactly what is needed, page by page. |
| `vm.vfs_cache_pressure` | **50** | **Cache Retention.** Tells the kernel to prefer keeping file system metadata in RAM. This makes navigating directories (`ls`, `cd`, `find`) feel snappier. |
| `vm.overcommit_memory` | **1** | **Always Say Yes.** Tells the kernel to always grant memory allocation requests, relying on our massive Swap/ZRAM buffer to handle it. Prevents "Can't allocate memory" errors in applications. |

---

## 📥 Installation

### 1. Clone the Repository

```bash
git clone https://github.com/Nixon-H/Debian-Velocity.git
cd Debian-Velocity

```

### 2. Make Executable & Run

```bash
chmod +x debian-velocity.sh
sudo ./debian-velocity.sh

```

### 3. Select Mode

* **[1] Automatic:** Recommended for 99% of users. Detects RAM and applies the Matrix logic above.
* **[2] Manual:** For experts who want specific sizing (limited to 2GB-16GB for safety).
* **[3] Uninstall:** Reverts all changes to stock.

### 4. Reboot

**Crucial:** You must reboot for the GRUB command line (Kernel) and Partition Table changes to take effect.

---

## ⚠️ Safety & Compatibility

* **Zswap vs ZRAM:** This script **disables Zswap**. Running Zswap (compressed cache) on top of ZRAM (compressed disk) is redundant and wastes CPU cycles. We enforce a "Pure ZRAM" pipeline.
* **GPU Drivers:** This script focuses on CPU/RAM. If you have an NVIDIA GPU, ensure you install proprietary drivers separately for maximum performance.
* **Warning:** While the script includes safety checks (refusing to run on <2GB RAM), always backup critical data before modifying kernel parameters or partition tables.

---

**Author:** [Nixon-H](https://www.google.com/search?q=https://github.com/Nixon-H)
