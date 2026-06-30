mkdir -p $PREFIX/lib
pushd $PREFIX/lib/

if [[ "$target_platform" == "osx-"* ]]; then
  rm -f $PREFIX/lib/libgomp.*dylib
  echo "Linking 'libgomp.dylib' to 'libomp.dylib'"
  ln -sf libomp.dylib libgomp.1.dylib
  echo "Linking 'libgomp.1.dylib' to 'libomp.dylib'"
  ln -sf libomp.dylib libgomp.dylib
else
  rm -f $PREFIX/lib/libgomp.so
  echo "Linking 'libgomp.so.1' to 'libomp.so'"
  ln -sf libomp.so libgomp.so.1
fi

echo "Checking link"
ls -lah libgomp*

popd
