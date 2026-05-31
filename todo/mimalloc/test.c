#include <mimalloc.h>

int main() {
  void* data = mi_malloc_aligned(1024, 64);
  void* data_new = mi_realloc_aligned(data, 2048, 64);
  mi_free(data_new);
}
