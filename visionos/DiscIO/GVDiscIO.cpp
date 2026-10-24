// SPDX-License-Identifier: GPL-3.0-or-later
// Adapted from upstream GalaxyPad apple/ios/GalaxyPadDiscExtractor.mm (DiscIO-based, RMGE01 rev 0 only).
#include "GVDiscIO.h"
#include <CommonCrypto/CommonDigest.h>
#include "DiscIO/DiscUtils.h"
#include "DiscIO/DiscExtractor.h"
#include "DiscIO/Filesystem.h"
#include "DiscIO/Volume.h"
#include <array>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
namespace fs = std::filesystem;

namespace {
// Identity hashes from config/galaxypad-disc.json (upstream GalaxyPadDiscIdentity).
constexpr const char *kDOLSHA256 = "2c680585a8f58e1cc9c5521b579057f12b124ff0ef409e470a57606c50a93c09";
constexpr uint64_t kDOLBytes = 6283264;
constexpr const char *kRSOSHA256 = "13dd2229f88b5af0f18875b3db15f4d3a52ea583085606a50e4b760a2e68194e";
constexpr const char *kSelSHA256 = "c37a0ff9bf9b86f8d46b0ac5c360f747add24178c2a81951ad4ecd06a65d6730";

struct Ctx { void (*progress)(void *, double); int (*cancelled)(void *); void *ctx; };
bool Cancelled(const Ctx &c) { return c.cancelled && c.cancelled(c.ctx); }

std::string SHA256(const fs::path &path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) return {};
  CC_SHA256_CTX context; CC_SHA256_Init(&context);
  std::array<char, 65536> buffer;
  while (stream.read(buffer.data(), buffer.size()) || stream.gcount())
    CC_SHA256_Update(&context, buffer.data(), (CC_LONG)stream.gcount());
  if (stream.bad() || !stream.eof()) return {};
  unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest, &context);
  constexpr char digits[] = "0123456789abcdef";
  std::string r; for (unsigned char b : digest) { r += digits[b >> 4]; r += digits[b & 15]; }
  return r;
}

bool ExportChecked(const DiscIO::Volume &volume, const DiscIO::Partition &partition,
    const DiscIO::FileInfo &directory, const fs::path &target, unsigned depth,
    uint64_t &remaining, uint64_t &done, uint64_t total, const Ctx &c) {
  if (depth > 128 || Cancelled(c)) return false;
  std::error_code error;
  if (!fs::create_directory(target, error) || error) return false;
  for (const auto &entry : directory) {
    if (Cancelled(c)) return false;
    std::string name = entry.GetName();
    if (name.empty() || name == "." || name == ".." || name.find('/') != std::string::npos ||
        name.find('\\') != std::string::npos || name.find('\0') != std::string::npos) return false;
    auto path = target / name;
    if (entry.IsDirectory()) {
      if (!ExportChecked(volume, partition, entry, path, depth + 1, remaining, done, total, c)) return false;
    } else {
      if (entry.GetSize() > remaining) return false;
      remaining -= entry.GetSize();
      if (fs::exists(path, error) || error || !DiscIO::ExportFile(volume, partition, &entry, path.string())) return false;
      if (fs::file_size(path, error) != entry.GetSize() || error) return false;
      done += entry.GetSize();
      if (c.progress) c.progress(c.ctx, std::min(1.0, (double)done / (double)total));
    }
  }
  return true;
}

uint64_t TotalBytes(const DiscIO::FileInfo &dir) {
  uint64_t t = 0;
  for (const auto &e : dir) t += e.IsDirectory() ? TotalBytes(e) : e.GetSize();
  return t;
}

const char *Extract(const char *imagePath, const char *dest, const Ctx &c) {
  fs::path image = imagePath, root = dest;
  std::error_code error;
  if (!fs::is_regular_file(image, error) || error) return "Couldn't read the selected disc image.";
  if (fs::file_size(image, error) > (5ULL << 30) || error) return "That file is too large to be a single-layer Wii disc image.";
  std::unique_ptr<DiscIO::Volume> volume = DiscIO::CreateVolume(image.string());
  if (!volume || volume->GetVolumeType() != DiscIO::Platform::WiiDisc) return "This isn't a Wii disc image DiscIO can read.";
  if (volume->GetGameID() != "RMGE01" || volume->GetRevision() != 0 || volume->GetDiscNumber() != 0)
    return "This disc isn't the USA Super Mario Galaxy (RMGE01, revision 0).";
  DiscIO::Partition partition = volume->GetGamePartition();
  if (volume->GetGameID(partition) != "RMGE01" || volume->GetRevision(partition) != 0 || volume->GetDiscNumber(partition) != 0)
    return "The game partition isn't RMGE01 revision 0.";
  auto dolOffset = DiscIO::GetBootDOLOffset(*volume, partition);
  auto dolSize = dolOffset ? DiscIO::GetBootDOLSize(*volume, partition, *dolOffset) : std::nullopt;
  auto fstSize = DiscIO::GetFSTSize(*volume, partition);
  auto apploaderSize = DiscIO::GetApploaderSize(*volume, partition);
  if (!dolSize || *dolSize != kDOLBytes || !fstSize || *fstSize > (16ULL << 20) || !apploaderSize || *apploaderSize > (16ULL << 20))
    return "Unsupported or damaged game system data.";
  const DiscIO::FileSystem *filesystem = volume->GetFileSystem(partition);
  if (!filesystem || !filesystem->IsValid() || filesystem->GetRoot().GetTotalChildren() > 10000)
    return "The disc's file table is damaged or unsupported.";
  if (Cancelled(c)) return "Import cancelled.";
  if (!fs::create_directory(root, error) || error) return "Couldn't create the private extraction folder.";
  if (!DiscIO::ExportSystemData(*volume, partition, root.string())) return "System-data extraction failed.";
  if (SHA256(root / "sys/main.dol") != kDOLSHA256) return "The game executable doesn't match RMGE01 revision 0.";
  uint64_t remaining = 4699979776ULL, done = 0;
  uint64_t total = std::max<uint64_t>(1, TotalBytes(filesystem->GetRoot()));
  if (!ExportChecked(*volume, partition, filesystem->GetRoot(), root / "files", 0, remaining, done, total, c))
    return Cancelled(c) ? "Import cancelled." : "Game-data extraction failed or was incomplete.";
  if (SHA256(root / "files/ModuleData/HomeButtonMenuWrapperRSO.rso") != kRSOSHA256 ||
      SHA256(root / "files/ModuleData/product.sel") != kSelSHA256)
    return "Home-menu data doesn't match the supported game revision.";
  return nullptr;
}
}  // namespace

extern "C" int GVDiscIOExtract(const char *image, const char *destination,
    void (*progress)(void *, double), int (*cancelled)(void *), void *ctx, char *error, size_t errorSize) {
  const char *failure = nullptr;
  try { failure = Extract(image, destination, Ctx{progress, cancelled, ctx}); }
  catch (const std::exception &) { failure = "Extraction failed."; }
  if (failure && error && errorSize) { std::strncpy(error, failure, errorSize - 1); error[errorSize - 1] = 0; }
  return failure ? 1 : 0;
}

extern "C" int GVDiscIOCanOpen(const char *image) {
  try {
    auto v = DiscIO::CreateVolume(std::string(image));
    return v && v->GetVolumeType() == DiscIO::Platform::WiiDisc;
  } catch (...) { return 0; }
}
