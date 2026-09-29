#include <mpi3/environment.hpp>
#include <mpi3/main.hpp>

#include <iostream>

namespace mpi3 = boost::mpi3;

int mpi3::main(int, char**, mpi3::communicator world) {
  std::cout << "rank " << world.rank() << " of " << world.size() << std::endl;
  return world.size() == 1 ? 0 : 1;
}
