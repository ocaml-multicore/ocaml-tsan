#!/bin/sh
set -eu

# - Remove mangling of functions (NOTE: functions of the same name, or
#   anonymous functions, become indistinguishable) and replace it with
#   '<implemspecific>'
# - Replace file+hexadecimal locations with '<implemspecific>'
# - Replace the complete path of the program by '<systemspecific>/' followed by
#   the program filename.
script='s/pid=[0-9]\+/pid=<implemspecific>/
s/tid=[0-9]\+/tid=<implemspecific>/

/\([Rr]ead\|[Ww]rite\) of size/ {
  s/of size \([0-9]\+\) at 0x[0-9a-f]\+/of size \1 at <implemspecific>/
}

/Mutex M.* created at:/ {
  s/M\([0-9]\+\) (0x[0-9a-f]\+)/M\1 (<implemspecific>)/
}

/#[0-9]\+/ {
  s/\(#[0-9]\+\) \([^ ]*\) [^ ]* (\([^ ]*\))/\1 \2 <implemspecific> (\3)/
  s/\(caml[a-zA-Z_0-9]\+__[a-zA-Z_0-9]\+\)_[[:digit:]]\+/\1_<implemspecific>/
  s/(\(.\+\)+0x[0-9a-f]\+)/(<implemspecific>)/
}

/SUMMARY/ {
  s/data race (.*\/\(.\+\)+0x[0-9a-f]\+) in /data race (<systemspecific>\/\1+<implemspecific>) in /
  s/data race .*\/\(.\+\):[[:digit:]]\+ in /data race (<systemspecific>\/\1+<implemspecific>) in /
  s/\(caml[a-zA-Z_0-9]\+__[a-zA-Z_0-9]\+\)_[[:digit:]]\+/\1_<implemspecific>/
}'

sed -e "${script}"
