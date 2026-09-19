! Downstream consumer check for an installed LIS: assemble a 1D Laplacian with
! the Fortran interface (lisf.h), distributed over 2 MPI ranks, and solve it
! with 2 OpenMP threads. Modelled on the upstream test4f.F.

PROGRAM api_check

    IMPLICIT NONE

#include "lisf.h"

    INTEGER(KIND=4) :: my_rank, nprocs, threads
    LIS_INTEGER :: comm, matrix_type, ierr
    LIS_INTEGER :: omp_get_max_threads
    LIS_INTEGER :: i, n, gn, is, ie, iter
    LIS_MATRIX :: A
    LIS_VECTOR :: b, x, u
    LIS_SOLVER :: solver
    LIS_REAL :: resid

    CALL lis_initialize(ierr)

    comm = LIS_COMM_WORLD

    CALL MPI_Comm_size(comm, nprocs, ierr)
    CALL MPI_Comm_rank(comm, my_rank, ierr)
    threads = omp_get_max_threads()

    n = 16
    matrix_type = LIS_MATRIX_CSR

    CALL lis_matrix_create(comm, A, ierr)
    CALL lis_matrix_set_size(A, 0, n, ierr)
    CALL lis_matrix_get_size(A, n, gn, ierr)
    CALL lis_matrix_get_range(A, is, ie, ierr)
    DO i = is, ie-1
        IF (i > 1)  CALL lis_matrix_set_value(LIS_INS_VALUE, i, i-1, -1.0d0, A, ierr)
        IF (i < gn) CALL lis_matrix_set_value(LIS_INS_VALUE, i, i+1, -1.0d0, A, ierr)
        CALL lis_matrix_set_value(LIS_INS_VALUE, i, i, 2.0d0, A, ierr)
    END DO
    CALL lis_matrix_set_type(A, matrix_type, ierr)
    CALL lis_matrix_assemble(A, ierr)

    CALL lis_vector_duplicate(A, u, ierr)
    CALL lis_vector_duplicate(A, b, ierr)
    CALL lis_vector_duplicate(A, x, ierr)
    CALL lis_vector_set_all(1.0d0, u, ierr)
    CALL lis_matvec(A, u, b, ierr)

    CALL lis_solver_create(solver, ierr)
    CALL lis_solver_set_option("-i cg -p jacobi", solver, ierr)
    CALL lis_solve(A, b, x, solver, ierr)

    IF (ierr /= 0) THEN
        WRITE(*,*) 'lis_solve failed with ', ierr
        STOP 1
    END IF

    CALL lis_solver_get_iter(solver, iter, ierr)
    CALL lis_solver_get_residualnorm(solver, resid, ierr)

    IF (my_rank == 0) THEN
        WRITE(*,'(a,i0,a,i0,a,i0,a,es12.4)') 'lis Fortran API: ranks=', nprocs, &
            ' threads=', threads, ' iter=', iter, ' residual=', resid
    END IF

    CALL lis_solver_destroy(solver, ierr)
    CALL lis_vector_destroy(x, ierr)
    CALL lis_vector_destroy(b, ierr)
    CALL lis_vector_destroy(u, ierr)
    CALL lis_matrix_destroy(A, ierr)
    CALL lis_finalize(ierr)

    IF (resid >= 1.0d-8) THEN
        WRITE(*,*) 'unexpected residual ', resid
        STOP 1
    END IF
    IF (nprocs /= 2) THEN
        WRITE(*,*) 'expected 2 MPI ranks, got ', nprocs
        STOP 1
    END IF
    IF (threads /= 2) THEN
        WRITE(*,*) 'expected 2 OpenMP threads, got ', threads
        STOP 1
    END IF

    STOP 0
END PROGRAM api_check
