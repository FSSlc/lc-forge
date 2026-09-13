set -exuo pipefail

pushd EXAMPLE
mpicc pddrive.c dcreate_matrix.c -o pddrive \
  $CFLAGS \
  $LDFLAGS \
  $(pkg-config --cflags --libs superlu_dist)
mpiexec -n 2 ./pddrive g20.rua
popd

pushd FORTRAN
mpifort f_pddrive.F90 -o f_pddrive \
  $FFLAGS \
  $LDFLAGS \
  $(pkg-config --cflags superlu_dist) -lsuperlu_dist_fortran
mpiexec -n 4 ./f_pddrive ../EXAMPLE/g20.rua
popd
