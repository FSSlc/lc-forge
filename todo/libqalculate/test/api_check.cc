// Downstream consumer check: build against the installed libqalculate headers
// and pkg-config file, then evaluate an expression through the public API.
// The initialisation sequence follows the example in libqalculate/Calculator.h.
#include <cstdlib>
#include <iostream>
#include <string>

#include <libqalculate/qalculate.h>

int main() {
  new Calculator(false);
  CALCULATOR->loadGlobalDefinitions();
  CALCULATOR->loadLocalDefinitions();

  const std::string result = CALCULATOR->calculateAndPrint("2^10", 2000);
  std::cout << "2^10 = " << result << std::endl;

  return result.find("1024") == std::string::npos ? EXIT_FAILURE : EXIT_SUCCESS;
}
