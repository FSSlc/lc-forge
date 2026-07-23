# Cannot build with PIE as symbols (e.g. `__libc_csu_fini`) cannot be used.
if [ "$(uname)" == "Linux" ] && [ "${c_compiler}" == "gcc" ]
then
    export CFLAGS="${CFLAGS} -fno-pie -no-pie"
    export CXXFLAGS="${CFLAGS} -fno-pie -no-pie"
fi

./configure --prefix="${PREFIX}" \
            --enable-pic
make
make install
