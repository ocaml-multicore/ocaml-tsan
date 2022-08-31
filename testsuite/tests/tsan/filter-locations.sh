#!/bin/sh

set -eu

# https://stackoverflow.com/questions/29613304/is-it-possible-to-escape-regex-metacharacters-reliably-with-sed/29626460#29626460
progpath_escaped=$(echo ${program} | sed 's/[^^\\]/[&]/g; s/\^/\\^/g; s/\\/\\\\/g')
progname_escaped=$(echo ${program} | sed 's/^.*\/\([^\/]\+\)/\1/' | sed 's/\\/\\\\/g')
regex_trim_fun='\(caml[a-zA-Z_0-9]\+\.[a-zA-Z_0-9]\+\)_[[:digit:]]\+'
regex_mem_location='of size \([0-9]\+\) at 0x[0-9a-f]\+'
regex_mutex_location='M\([0-9]\+\) (0x[0-9a-f]\+)'

# - Remove mangling of functions (NOTE: functions of the same name, or
#   anonymous functions, become indistinguishable) and replace it with
#   '<implemspecific>'
# - Replace hexadecimal locations with '<implemspecific>'
# - Replace the complete path of the program by '<systemspecific>/' followed by
#   the program filename.
sed -e \
  "s/+0x[0-9a-f]\+)/+<implemspecific>)/
   s/pid=[0-9]\+/pid=<implemspecific>/
   s/tid=[0-9]\+/tid=<implemspecific>/
   s/${regex_mem_location}/of size \1 at <implemspecific>/
   s/${regex_trim_fun}/\1_<implemspecific>/
   s/${regex_mutex_location}/M\1 (<implemspecific>)/
   s/${progpath_escaped}/<systemspecific>\/${progname_escaped}/"
