// SPDX-License-Identifier: GPL-3.0-or-later
// Link stubs for the parts of Dolphin that DiscIO references but GalaxyVision's disc import
// never uses: emulated-NAND access, the config system, logging, directory/WIA/RVZ blobs.
#include "Common/Config/Config.h"
#include "Common/Logging/Log.h"
#include "Core/Config/MainSettings.h"
#include "Core/IOS/FS/FileSystem.h"
#include "Core/IOS/FS/FileSystemProxy.h"
#include "Core/IOS/IOS.h"
#include "DiscIO/DirectoryBlob.h"
#include "DiscIO/WIABlob.h"

namespace Common::Log {
void GenericLogFmtImpl(LogLevel, LogType, const char*, int, fmt::string_view, const fmt::format_args&) {}
}
namespace Config {
u64 GetConfigVersion() { return 1; }
std::optional<std::string> GetAsString(const Location&) { return std::nullopt; }
const Info<bool> MAIN_LOAD_GAME_INTO_MEMORY{{System::Main, "Core", "LoadGameIntoMemory"}, false};
}
namespace DiscIO {
std::unique_ptr<DirectoryBlobReader> DirectoryBlobReader::Create(const std::string&) { return nullptr; }
template <>
std::unique_ptr<WIARVZFileReader<false>> WIARVZFileReader<false>::Create(File::DirectIOFile, const std::string&) { return nullptr; }
template <>
std::unique_ptr<WIARVZFileReader<true>> WIARVZFileReader<true>::Create(File::DirectIOFile, const std::string&) { return nullptr; }
}
namespace IOS::HLE {
std::shared_ptr<FS::FileSystem> Kernel::GetFS() { return nullptr; }
FSCore::ScopedFd FSCore::Open(FS::Uid, FS::Gid, const std::string&, FS::Mode, std::optional<u32>, Ticks) { return ScopedFd{this, -1}; }
s32 FSCore::Close(u64, Ticks) { return -1; }
s32 FSCore::Read(u64, u8*, u32, std::optional<u32>, Ticks) { return -1; }
namespace FS {
FileHandle::~FileHandle() = default;
Result<u32> FileHandle::Seek(u32, SeekMode) const { return std::unexpected(ResultCode::Invalid); }
Result<FileHandle> FileSystem::CreateAndOpenFile(Uid, Gid, const std::string&, Modes) { return std::unexpected(ResultCode::Invalid); }
}
}
