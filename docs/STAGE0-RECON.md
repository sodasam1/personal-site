# Stage 0: what I need from the owner (read-only; nothing on the server changes)

## 1. Two files from your one-time copy of Tech Independence
Put them in `reference/`: `ti.sh` and `ti.tar` (the tar holds `httpd.conf`, `relayd.conf`, `pf.conf` and the other files
`ti.sh` unpacks). Not a fork, only a frozen copy so the install blocks can be written against your real files.

## 2. Output of these commands, run on the server (pasted into a file `reference/server-recon.txt`)
```sh
rcctl ls on                               # services that start at boot
ls -la /var/www /var/www/htdocs           # the web folder and who owns it (httpd's chroot)
which python3; pkg_info | grep -i python  # Python is installed, and by which package
pkg_info -Q ffmpeg                        # is ffmpeg in OpenBSD's package list (changes nothing)
man httpd.conf | col -b | grep -n -i -B1 -A5 'authenticate\|location'
```
- `man httpd.conf` prints the manual page; `col -b` strips its formatting; `grep -n -i -B1 -A5` searches ignoring case,
  printing line numbers and 1 line before / 5 after each match.
- Why: the manual on your own server is the authority for your OpenBSD version; it could not be read from the build machine.
