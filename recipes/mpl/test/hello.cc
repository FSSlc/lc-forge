// Minimal downstream consumer of the installed mpl package.
// Based on the "Hello parallel world" example from the upstream README.
#include <cstdlib>
#include <iostream>

#include <mpl/mpl.hpp>

int main() {
  const mpl::communicator &comm_world{mpl::environment::comm_world()};
  std::cout << "Hello world! I am running on \"" << mpl::environment::processor_name()
            << "\". My rank is " << comm_world.rank() << " out of " << comm_world.size()
            << " processes.\n";
  comm_world.barrier();

  const int rank{comm_world.rank()};
  const int size{comm_world.size()};
  if (size < 1 || rank < 0 || rank >= size) {
    return EXIT_FAILURE;
  }
  return EXIT_SUCCESS;
}
