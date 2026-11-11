/* Built and linked through wi4mpi's mpicc wrapper. MPI_Init is never called,
 * so the binary needs no target MPI implementation at run time. */
#include <stdio.h>
#include <mpi.h>

int main(void)
{
	int (*get_version)(int *, int *) = MPI_Get_version;

	if (get_version == NULL)
		return 1;

	printf("wi4mpi wrapper ok\n");
	return 0;
}
