! Built and linked through wi4mpi's mpifort wrapper, which picks up the
! mpi.mod installed by the package. No MPI routine is called, so the binary
! needs no target MPI implementation at run time.
program wrapper_fortran
    use mpi
    implicit none
    integer :: world

    world = MPI_COMM_WORLD
    print '(a,i0)', 'wi4mpi fortran wrapper ok ', world
end program wrapper_fortran
