/* Downstream consumer smoke test.
 *
 * Creates a single-application coupling set on MPI_COMM_WORLD to prove that
 * libple was built with MPI and links cleanly from plain C via mpicc.
 */
#include <mpi.h>
#include <stdio.h>

#include "ple_config.h"
#include "ple_coupling.h"

int
main(int argc, char *argv[])
{
  int rank = 0;

  MPI_Init(&argc, &argv);
  MPI_Comm_rank(MPI_COMM_WORLD, &rank);

#ifndef PLE_HAVE_MPI
  if (rank == 0)
    fprintf(stderr, "libple was built without MPI support\n");
  MPI_Abort(MPI_COMM_WORLD, 1);
#endif

  ple_coupling_mpi_set_t *s
    = ple_coupling_mpi_set_create(PLE_COUPLING_NO_SYNC, "ple-smoke", NULL,
                                  MPI_COMM_WORLD, MPI_COMM_WORLD);
  if (s == NULL) {
    if (rank == 0)
      fprintf(stderr, "ple_coupling_mpi_set_create returned NULL\n");
    MPI_Abort(MPI_COMM_WORLD, 1);
  }

  ple_coupling_mpi_set_destroy(&s);

  if (rank == 0)
    printf("ple coupling smoke test passed\n");

  MPI_Finalize();
  return 0;
}