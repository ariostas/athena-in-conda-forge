// Read back the events of an EventStorage file, as Athena's ByteStream input does.
#include <cstdint>
#include <iostream>
#include <memory>

#include "EventStorage/pickDataReader.h"
#include "eformat/eformat.h"

int main(int argc, char** argv) {
  if (argc != 3) return 2;
  const unsigned expected = std::stoul(argv[2]);
  std::unique_ptr<DataReader> reader(pickDataReader(argv[1]));
  if (!reader || !reader->good()) return 1;
  unsigned n = 0;
  while (reader->good()) {
    unsigned int size = 0;
    char* buffer = nullptr;
    if (reader->getData(size, &buffer) != EventStorage::DROK) return 1;
    std::unique_ptr<char[]> owned(buffer);
    eformat::read::FullEventFragment event(reinterpret_cast<const uint32_t*>(buffer));
    event.check_tree();
    ++n;
  }
  std::cout << "C++: " << n << " events from " << reader->fileName() << std::endl;
  return n == expected ? 0 : 1;
}
