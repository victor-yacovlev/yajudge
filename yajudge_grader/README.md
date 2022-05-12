## Grader Service for Yajudge

### Prerequirements

- Modern Linux Kernel and systemd-based distribution
- cgroup v2 enabled by default in Linux system (see 
notes below)
- Dart 2.12 or later
- protoc compiler

*NOTE:* It is **highly recommended** to run grader service on
Linux. It can run on macOS or some another POSIX-like system, 
but in this case all security-related features of grading
system will be not available.

### Build

Just type `make` from parent directory, or from this
directory after package `yajudge_common` built.

In order to install type `make install` as root user
to make installations into `/usr` system prefix.

### System Configuration

Only recent (by Feb, 2022) Linux distributions have enabled
by default `cgroup` version 2 but not 1.

Grader will not work in case of using legacy `cgroup` 
Linux subsystem. To enable `cgroup v2` add the following
parameters to the kernel command line:
```
systemd.unified_cgroup_hierarchy=1 cgroup_no_v1=all
```

On **x86(-64)** systems kernel parameters are set up by GRUB, so edit file `/etc/default/grub`:
```
GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=1 cgroup_no_v1=all"
```

Then run `update-grub` and reboot your system to apply changes.

On **ARM** systems with U-Boot loader (like Raspberry Pi) the same kernel parameters stored in file
`/boot/cmdline.txt` (Raspbian) or `/boot/firmware/cmdline.txt` (Ubuntu).

To check if your system configured to use `cgroup v2` examine the following command output:
```shell
mount | grep cgroup
```

You should see **exactly one** line of mounted file system of type `cgroup2` but not several `cgroup` file systems.

### Grader Configuration

Place `conf/grader.yaml` to one of the following places:
 
 - `$HOME/.config/yajudge/grader.yaml`
 - `/etc/yajudge/grader.yaml`

You can also set custom config file path
using `-C` command line option.

### Chrooted Environment Setup

Submission grading assumes using of dedicated 'clean'
Linux environment for each problem submission. So it
requires minimal Linux filesystem with required developer
tools installed in some directory that not contain any 
private data.

Such filesystem may be obtained by several ways:
 
 - Just download and upack mini root filesystem from
[Alpine Linux](https://alpinelinux.org). Note that
Alpine's provided `libc` library lacks some usable
features like sanitizers support.
 - Use `debootstrap` tool to create Debian or Ubuntu
local environment. This works not only on Debian or Ubuntu
hosts but also on openSUSE.
 - Use yours own specific distribution tool.

After creating local environment use `sudo chroot ...` (Debian)
or `unshare -muifrp --wd=/ --root=...` (Alpine) 
command to enter that environment and configure target system.

### Grader Usage

#### Service management

 - `yajudge-grader start` - starts service in background
using proper `systemd` slice
 - `yajudge-grader stop` - stops previously started service
 - `yajudge-grader daemon` - run service in foreground. 
Note that it must be running within configured dedicated
cgroup slice, for example by starting via `systemd-run --wait`
command, or to be in use while configuring `systemd` service.

#### Local submissions testing

 - `yajudge-grader run -c COURSE -p PROBLEM FILES...` -
queues local submission of problem with id `PROBLEM` and
course with data id `COURSE`. The rest of command arguments
are local submission files. 
After queuing it will wait for grader response.
