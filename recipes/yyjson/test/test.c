#include <yyjson.h>

int main(void) {
  yyjson_doc *doc = yyjson_read("[1, 2, 3]", 9, 0);
  if (!doc) return 1;
  yyjson_val *root = yyjson_doc_get_root(doc);
  if (!yyjson_is_arr(root)) return 1;

  size_t idx, max, n = 0;
  yyjson_val *val;
  yyjson_arr_foreach(root, idx, max, val) {
    if (!yyjson_is_uint(val)) return 1;
    n++;
  }
  if (n != 3) return 1;

  yyjson_doc_free(doc);
  return 0;
}
