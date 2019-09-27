# crestron-am-toolchain
Source, scripts, and tools used to build a toolchain for Crestron AirMedia devices

Source Versions:
* Linux version 2.6.32.9-default
* binutils-2.20.1
* GCC: 4.5.1
* mpc: 0.8.1
* mpfr: 2.4.2
* gmp: 4.3.1
* GLIBC: 2.11.1 (libc-2.11.1.so)

My first target reports itself as a Crestron wm8750 AM-100 v1.1.11 - the original. An untouched virgin. This is, of course, ultra vulnerable to numerous remote command execution, as root, methods. I have gained access to the host (and many like it), I want to upload a GDB server to the host, and continue other exploit development and research. To do so, I need to cross compile gdbserver correctly, and this repo is a summation of my efforts to do so. Now, let's profile the host.

"uname -a":
  Linux Crestron.AirMedia-1.1.wm8750 2.6.32.9-default #3 Mon Aug 25 16:02:49 CST 2014 armv6l GNU/Linux

If we "cat /proc/version", we get this nice info:
  Linux version 2.6.32.9-default (tutu@eds1) (gcc version 4.5.1 (Sourcery G++ Lite 2010.09-50) ) #3 Mon Aug 25 16:02:49 CST 2014

Next, we'll "cat /proc/cpuinfo":
        Processor       : ARMv6-compatible processor rev 7 (v6l)
        BogoMIPS        : 532.24
        Features        : swp half thumb fastmult vfp edsp java 
        CPU implementer : 0x41
        CPU architecture: 7
        CPU variant     : 0x0
        CPU part        : 0xb76
        CPU revision    : 7
        Hardware        : WMT
        Revision        : 0000
        Serial          : 0000000000000000

Dynamic linker: /lib/ld-linux.so.3 -> /lib/ld-2.11.1.so
    ELF Header:
      Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00 
      Class:                             ELF32
      Data:                              2's complement, little endian
      Version:                           1 (current)
      OS/ABI:                            UNIX - System V
      ABI Version:                       0
      Type:                              DYN (Shared object file)
      Machine:                           ARM
      Version:                           0x1
      ...
      Flags:                             0x5000002, Version5 EABI, <unknown>
      ...
    File Attributes
      Tag_CPU_name: "5TE"
      Tag_CPU_arch: v5TE
      Tag_ARM_ISA_use: Yes
      Tag_THUMB_ISA_use: Thumb-1
      Tag_ABI_PCS_wchar_t: 4
      Tag_ABI_FP_denormal: Needed
      Tag_ABI_FP_exceptions: Needed
      Tag_ABI_FP_number_model: IEEE 754
      Tag_ABI_align_needed: 8-byte
      Tag_ABI_align_preserved: 8-byte, except leaf SP
      Tag_ABI_enum_size: int
      Tag_ABI_optimization_goals: Aggressive Speed
    Symbol table '.dynsym' contains 28 entries:
      ... entries suggest glibc 2.4, so we'll se how that goes ...

Very first obvious thing to do is download the exact toolchain used (Sourcery G++ Lite 2010.09-50). Would love to, but it doesn't seem to be available for free, anymore (also this is a learning oportunity), so we're left with notes and things from other people as to what was in the toolchain.
