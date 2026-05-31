meson setup builddir \
	--buildtype release \
	--prefix=$PREFIX \
	--libdir=lib

meson install -C builddir