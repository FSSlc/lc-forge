#include <rfl.hpp>
#include <rfl/json.hpp>
#include <rfl/yaml.hpp>

#include <iostream>
#include <string>

struct Person {
  std::string first_name;
  std::string last_name;
  int age;
};

int main() {
  const auto homer =
      Person{.first_name = "Homer", .last_name = "Simpson", .age = 45};

  const auto json_string = rfl::json::write(homer);
  if (json_string != R"({"first_name":"Homer","last_name":"Simpson","age":45})") {
    std::cerr << "unexpected JSON: " << json_string << std::endl;
    return 1;
  }

  const auto homer2 = rfl::json::read<Person>(json_string).value();
  if (homer2.first_name != "Homer" || homer2.last_name != "Simpson" ||
      homer2.age != 45) {
    std::cerr << "round-trip failed" << std::endl;
    return 1;
  }

  const auto yaml_string = rfl::yaml::write(homer);
  const auto homer3 = rfl::yaml::read<Person>(yaml_string).value();
  if (homer3.first_name != "Homer" || homer3.last_name != "Simpson" ||
      homer3.age != 45) {
    std::cerr << "YAML round-trip failed: " << yaml_string << std::endl;
    return 1;
  }

  std::cout << json_string << std::endl;
  return 0;
}
