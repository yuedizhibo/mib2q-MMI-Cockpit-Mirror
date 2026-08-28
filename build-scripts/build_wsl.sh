#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD="$ROOT/build"
STUBS="$BUILD/stubs"

mkdir -p "$STUBS"
rm -f "$BUILD/libcp_mirror.so" "$BUILD/libcp_mirror.o" \
      "$BUILD/libdisplayinit.so" "$BUILD/libdisplayinit_p1404.o" \
      "$BUILD/libegl_diag.so" "$BUILD/libegl_diag.o" \
      "$BUILD/libdirect_upload.so" "$BUILD/libdirect_upload.o" \
      "$BUILD/libport_waker.so" "$BUILD/libport_waker.o" \
      "$BUILD/libdirect_display_share.so" "$BUILD/libdirect_display_share.o"

for lib in libc.so.3 libsocket.so.3 libscreen.so.1 libz.so.2; do
    clang --target=armv7-linux-gnueabi -fuse-ld=lld -nostdlib -shared \
        -Wl,--build-id=none,-soname,"$lib",-z,max-page-size=4096 \
        "$ROOT/src/native/empty_stub.c" -o "$STUBS/$lib"
done

clang --target=armv7-linux-gnueabi -march=armv7-a -marm -mfloat-abi=softfp \
    -fPIC -O2 -ffreestanding -fno-stack-protector \
    -fno-builtin -nostdinc -c "$ROOT/src/native/libcp_mirror.c" -o "$BUILD/libcp_mirror.o"

clang --target=armv7-linux-gnueabi -fuse-ld=lld -nostdlib -shared \
    -Wl,--build-id=none,-z,norelro,-z,max-page-size=4096,--hash-style=sysv \
    -Wl,--no-as-needed -L"$STUBS" -Wl,-l:libscreen.so.1,-l:libz.so.2,-l:libsocket.so.3,-l:libc.so.3 \
    -Wl,--allow-shlib-undefined "$BUILD/libcp_mirror.o" -o "$BUILD/libcp_mirror.so"

# QNX ARM binaries use EF_ARM_EABI_VER5 | 0x2. lld emits the Linux soft-float
# flag instead, so patch only the ELF e_flags word at offset 0x24.
printf '\002\000\000\005' | dd of="$BUILD/libcp_mirror.so" bs=1 seek=36 conv=notrunc status=none

clang --target=armv7-linux-gnueabi -march=armv7-a -marm -mfloat-abi=softfp \
    -fPIC -O2 -ffreestanding -fno-stack-protector -fno-builtin -nostdinc \
    -Wall -Wextra -Werror -c "$ROOT/src/native/libdisplayinit_p1404.c" \
    -o "$BUILD/libdisplayinit_p1404.o"

clang --target=armv7-linux-gnueabi -fuse-ld=lld -nostdlib -shared \
    -Wl,--build-id=none,-z,norelro,-z,max-page-size=4096,--hash-style=sysv \
    -Wl,-soname,libdisplayinit.so -Wl,--no-as-needed -L"$STUBS" \
    -Wl,-l:libscreen.so.1,-l:libc.so.3 -Wl,--allow-shlib-undefined \
    "$BUILD/libdisplayinit_p1404.o" -o "$BUILD/libdisplayinit.so"

printf '\002\000\000\005' | dd of="$BUILD/libdisplayinit.so" bs=1 seek=36 conv=notrunc status=none

clang --target=armv7-linux-gnueabi -march=armv7-a -marm -mfloat-abi=softfp \
    -fPIC -O2 -ffreestanding -fno-stack-protector -fno-builtin -nostdinc \
    -Wall -Wextra -Werror -c "$ROOT/src/native/libegl_diag.c" \
    -o "$BUILD/libegl_diag.o"

clang --target=armv7-linux-gnueabi -fuse-ld=lld -nostdlib -shared \
    -Wl,--build-id=none,-z,norelro,-z,max-page-size=4096,--hash-style=sysv \
    -Wl,-soname,libegl_diag.so -Wl,--no-as-needed -L"$STUBS" \
    -Wl,-l:libc.so.3 -Wl,--allow-shlib-undefined \
    "$BUILD/libegl_diag.o" -o "$BUILD/libegl_diag.so"

printf '\002\000\000\005' | dd of="$BUILD/libegl_diag.so" bs=1 seek=36 conv=notrunc status=none

clang --target=armv7-linux-gnueabi -march=armv7-a -marm -mfloat-abi=softfp \
    -fPIC -O3 -ffreestanding -fno-stack-protector -fno-builtin -nostdinc \
    -Wall -Wextra -Werror -c "$ROOT/src/native/libdirect_upload.c" \
    -o "$BUILD/libdirect_upload.o"

clang --target=armv7-linux-gnueabi -fuse-ld=lld -nostdlib -shared \
    -Wl,--build-id=none,-z,norelro,-z,max-page-size=4096,--hash-style=sysv \
    -Wl,-soname,libdirect_upload.so -Wl,--no-as-needed -L"$STUBS" \
    -Wl,-l:libscreen.so.1,-l:libc.so.3 -Wl,--allow-shlib-undefined \
    "$BUILD/libdirect_upload.o" -o "$BUILD/libdirect_upload.so"

printf '\002\000\000\005' | dd of="$BUILD/libdirect_upload.so" bs=1 seek=36 conv=notrunc status=none

clang --target=armv7-linux-gnueabi -march=armv7-a -marm -mfloat-abi=softfp \
    -fPIC -O2 -ffreestanding -fno-stack-protector -fno-builtin -nostdinc \
    -Wall -Wextra -Werror -c "$ROOT/src/native/libport_waker.c" \
    -o "$BUILD/libport_waker.o"

clang --target=armv7-linux-gnueabi -fuse-ld=lld -nostdlib -shared \
    -Wl,--build-id=none,-z,norelro,-z,max-page-size=4096,--hash-style=sysv \
    -Wl,-soname,libport_waker.so -Wl,--no-as-needed -L"$STUBS" \
    -Wl,-l:libsocket.so.3,-l:libc.so.3 -Wl,--allow-shlib-undefined \
    "$BUILD/libport_waker.o" -o "$BUILD/libport_waker.so"

printf '\002\000\000\005' | dd of="$BUILD/libport_waker.so" bs=1 seek=36 conv=notrunc status=none

clang --target=armv7-linux-gnueabi -march=armv7-a -marm -mfloat-abi=softfp \
    -fPIC -O2 -ffreestanding -fno-stack-protector -fno-builtin -nostdinc \
    -Wall -Wextra -Werror -c "$ROOT/src/native/libdirect_display_share.c" \
    -o "$BUILD/libdirect_display_share.o"

clang --target=armv7-linux-gnueabi -fuse-ld=lld -nostdlib -shared \
    -Wl,--build-id=none,-z,norelro,-z,max-page-size=4096,--hash-style=sysv \
    -Wl,-soname,libdirect_display_share.so -Wl,--no-as-needed -L"$STUBS" \
    -Wl,-l:libc.so.3 -Wl,--allow-shlib-undefined \
    "$BUILD/libdirect_display_share.o" -o "$BUILD/libdirect_display_share.so"

printf '\002\000\000\005' | dd of="$BUILD/libdirect_display_share.so" bs=1 seek=36 conv=notrunc status=none

sha256sum "$BUILD/libcp_mirror.so"
file "$BUILD/libcp_mirror.so"
readelf -h -d -s "$BUILD/libcp_mirror.so"
sha256sum "$BUILD/libdisplayinit.so"
file "$BUILD/libdisplayinit.so"
readelf -h -d -s "$BUILD/libdisplayinit.so"
sha256sum "$BUILD/libegl_diag.so"
file "$BUILD/libegl_diag.so"
readelf -h -d -s "$BUILD/libegl_diag.so"
sha256sum "$BUILD/libdirect_upload.so"
file "$BUILD/libdirect_upload.so"
readelf -h -d -s "$BUILD/libdirect_upload.so"
sha256sum "$BUILD/libport_waker.so"
file "$BUILD/libport_waker.so"
readelf -h -d -s "$BUILD/libport_waker.so"
sha256sum "$BUILD/libdirect_display_share.so"
file "$BUILD/libdirect_display_share.so"
readelf -h -d -s "$BUILD/libdirect_display_share.so"
