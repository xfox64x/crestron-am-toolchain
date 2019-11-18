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
```
  Linux Crestron.AirMedia-1.1.wm8750 2.6.32.9-default #3 Mon Aug 25 16:02:49 CST 2014 armv6l GNU/Linux
```

If we "cat /proc/version", we get this nice info:
```
  Linux version 2.6.32.9-default (tutu@eds1) (gcc version 4.5.1 (Sourcery G++ Lite 2010.09-50) ) #3 Mon Aug 25 16:02:49 CST 2014
```

Next, we'll "cat /proc/cpuinfo":
```
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
```
Dynamic linker: /lib/ld-linux.so.3 -> /lib/ld-2.11.1.so
```  
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
```
Very first obvious thing to do is download the exact toolchain used (Sourcery G++ Lite 2010.09-50). Would love to, but it doesn't seem to be available for free, anymore (also this is a learning oportunity), so we're left with notes and things from other people as to what was in the toolchain.

..... Time Passes .....

Did I mention I have no idea what I'm doing? Well, I've remembered a bit of the education I payed for and learned some things, along the way, and I'm not sure what the summary of these efforts should be: 
* I did a bunch of meaningless work to compile a broken gdb in an antiquated, useless way? 
* I encountered the notion that the opensource community, as a whole, is either incapable of explaining or doesn't understand compilers/building compilers/cross-compiling (here's looking at you, linuxfromscratch.org! PM the hatemail. Don't at me bro.)? 
* There are so many nuances to cross-compiling a debugger for an older Arm chip, something I hardly understand, that maybe I'll never be able to create the perfect gdb?
* That I've created something "good enough" to debug the CGI's on the Crestron devices?

At least, I think what's here works. I was able to compile gdb/gdbserver for the Crestron wm8750 AM-100, debug the CGI's, and verify some findings. However, my local copy of this repo went down a rabbit hole of getting multi-threading working, resulting in a bunch of FALLTHROUGH issues while compiling elfutils 0.148, I think. I met up with some buds at 2019's Wild West Hack'n Fest, we drank way too much, spent the whole time CTF'ing, and NOT going to talks. I got the most work done in the airports, on the way, asked everyone for help, but still couldn't figure my issues out (still in a haze), and I don't really have time to work on this anymore... so this is probably somewhere between working and not.

During all this, my secondary goal became: Find a way to explain and compile this in any environment. I shouldn't be limited to Solaris or FreeBSD or Fedora or Debian or YourBullshitHere as a platform for cross-compiling, yet that, more often than not, is the response you see to questions completely unrelated to the build environment. Asking questions on the internet is not a perfect process, but your OS is not your build environment. If you cannot overcome it, maybe you do not understand it.

[Linux from Scratch](http://www.linuxfromscratch.org/), let's talk about that. Specifically, let's talk about [versions similar to those](http://www.linuxfromscratch.org/lfs/view/6.7/chapter05/gcc-pass1.html) I'm more interested in. When compiling gcc 4.5.1, we extract mpfr, gmp, mpc, and move them to a place gcc can access during the build. Though, when we're configuring gcc we only specify the future locations of mpfr's built parts (knowing mpfr will also be built), with no explanation on why we aren't doing the same for mpc or gmp. Why? Specifying roughly the same configure parameters to include mpc and/or gmp causes issues, but why? I love the note at the top of future versions of [this page](http://www.linuxfromscratch.org/lfs/view/7.5-systemd/chapter05/gcc-pass1.html): "There are frequent misunderstandings about this chapter". Well no shit. Very little is explained; everything is just handed out. I get that the build process changes over time, but the lack of robust documentation explaining this process, while you're telling people how to do it, is a disservice to the education of our community. Yeah, I'm sure LFS works if I follow it, cover to cover, using the exact same OS, copying and pasting, but that doesn't really help me understand what I'm doing and why, so that, when I want to do essentially the same things for a different architecture and on a different OS, I can extrapolate the process. Don't get me wrong; LFS helped me understand the process better. But it also did me the disservice of handing me commands I should trust, leading to many one-off rabbit-holes and patches I'm not sure if I need. I'm left with uncertainty.
