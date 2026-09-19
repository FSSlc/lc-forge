/* Downstream consumer check for an installed LIS: solve the 2D Laplacian from
   the example data set with the C API, distributed over 2 MPI ranks and
   threaded with 2 OpenMP threads. */

#include <stdio.h>
#include <stdlib.h>

#include <mpi.h>
#include <omp.h>

#include "lis.h"

int main(int argc, char* argv[])
{
	LIS_MATRIX A;
	LIS_VECTOR b, x, u;
	LIS_SOLVER solver;
	LIS_INT err, iter, nprocs, my_rank;
	LIS_REAL resid;
	int threads;

	if (argc != 2) {
		fprintf(stderr, "usage: %s matrix.mtx\n", argv[0]);
		return 2;
	}

	lis_initialize(&argc, &argv);
	MPI_Comm_size(MPI_COMM_WORLD, &nprocs);
	MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);
	threads = omp_get_max_threads();

	lis_matrix_create(MPI_COMM_WORLD, &A);
	lis_vector_create(MPI_COMM_WORLD, &b);
	lis_vector_create(MPI_COMM_WORLD, &x);
	lis_matrix_set_type(A, LIS_MATRIX_CSR);
	err = lis_input(A, b, x, argv[1]);
	if (err) {
		fprintf(stderr, "lis_input(%s) failed with %d\n", argv[1], (int)err);
		MPI_Abort(MPI_COMM_WORLD, 1);
	}

	/* The example matrix stores only the matrix, so build b = A * 1. */
	if (lis_vector_is_null(b)) {
		lis_vector_destroy(b);
		lis_vector_duplicate(A, &b);
		lis_vector_duplicate(A, &u);
		lis_vector_set_all(1.0, u);
		lis_matvec(A, u, b);
		lis_vector_destroy(u);
	}
	if (lis_vector_is_null(x)) {
		lis_vector_destroy(x);
		lis_vector_duplicate(A, &x);
	}

	lis_solver_create(&solver);
	lis_solver_set_option("-i cg -p jacobi", solver);
	err = lis_solve(A, b, x, solver);
	lis_solver_get_iter(solver, &iter);
	lis_solver_get_residualnorm(solver, &resid);

	if (my_rank == 0) {
		printf("lis C API: ranks=%d threads=%d iter=%d residual=%e\n",
		       (int)nprocs, threads, (int)iter, (double)resid);
	}

	lis_solver_destroy(solver);
	lis_vector_destroy(x);
	lis_vector_destroy(b);
	lis_matrix_destroy(A);
	lis_finalize();

	if (err != LIS_SUCCESS) {
		fprintf(stderr, "lis_solve failed with %d\n", (int)err);
		return 1;
	}
	if (!(resid < 1.0e-8)) {
		fprintf(stderr, "unexpected residual %e\n", (double)resid);
		return 1;
	}
	if (nprocs != 2) {
		fprintf(stderr, "expected 2 MPI ranks, got %d\n", (int)nprocs);
		return 1;
	}
	if (threads != 2) {
		fprintf(stderr, "expected 2 OpenMP threads, got %d\n", threads);
		return 1;
	}
	return 0;
}
