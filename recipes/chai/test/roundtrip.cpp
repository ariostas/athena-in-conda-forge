// Write a payload to a tag in a CREST file system database and read it back. This goes
// through the plugin that chai finds at runtime next to its library (lib/chai/plugins).
#include <chai/Container.h>
#include <chai/Database.h>

#include <cstdint>
#include <filesystem>
#include <iostream>

int main() {
  const auto dir = std::filesystem::current_path() / "chai_test_db";
  std::filesystem::remove_all(dir);
  std::filesystem::create_directories(dir);

  chai::Database db("crest_fs:" + dir.string());
  using enum chai::Type;
  chai::PayloadSpec spec(chai::FieldSpec({{"temperature", Int32}, {"status", String}}),
                         chai::ChannelSpec({{100, "Channel A"}}));
  auto tag = db.createTag(
      "TEST_TAG", "a test tag", spec,
      {.iovType = chai::Tag::IovType::RunNumberLumiBlock,
       .objectType = "crest-json-single-iov",
       .synchronization = chai::Tag::Synchronization::All,
       .status = chai::Tag::Status::Unlocked,
       .nodeDescription = chai::Tag::buildNodeDescription(
           chai::Tag::IovType::RunNumberLumiBlock, "CondAttrListCollection", 1238547719u)});
  chai::Container container = tag->buildContainer();
  container[100].push(450);
  container[100].push("ACTIVE");
  const std::uint64_t since = std::uint64_t{100} << 32 | 1;
  tag->addPayload(container, since);

  auto back = db.getTag("TEST_TAG");
  int found = 0;
  for (const auto& iov : back->getIovs(0)) {
    auto payload = back->getPayload(iov.getPayloadHash());
    for (const auto& [id, values] : payload) {
      std::cout << "since " << iov.getSince() << " channel " << id << ": "
                << values->get<std::int32_t>("temperature") << " "
                << values->get<std::string>("status") << std::endl;
      if (iov.getSince() == since && id == 100 &&
          values->get<std::int32_t>("temperature") == 450 &&
          values->get<std::string>("status") == "ACTIVE") {
        ++found;
      }
    }
  }
  return found == 1 ? 0 : 1;
}
