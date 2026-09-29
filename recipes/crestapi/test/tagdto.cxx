// A CREST tag through its JSON representation and back.
#include <CrestApi/TagDto.h>

#include <iostream>

int main() {
  Crest::TagDto tag("test_tag", "time", "a test tag");
  const auto json = tag.toJson();
  const auto back = Crest::TagDto::fromJson(json);
  std::cout << json.dump() << std::endl;
  return back.getName() == "test_tag" ? 0 : 1;
}
