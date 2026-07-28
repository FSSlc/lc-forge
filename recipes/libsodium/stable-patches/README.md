# patches 

libsodium 'stable' branch contains several patches for the stable version.
This is available as the 'stable' tarball, but its hash changes.

Strategy:

- build from release tarball
- carry a snapshot of stable as a list of patches

All the patches in here are automatically generated,
any manual patches we need should not go here.

Generate patch list:

```
TAG=1.0.22
git rm -f  recipe/stable-patches/*.patch
git clone https://github.com/jedisct1/libsodium -b stable
cd libsodium
git format-patch ${TAG}
mv *.patch ../recipe/stable-patches
cd ../recipe
git add stable-patches
ls stable-patches/*.patch | sort | sed 's@^@    - @g' | pbcopy
# paste updated list in source.patches
```
