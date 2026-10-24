# Minimal Dolphin DiscIO subset for GalaxyVision's disc import (and a macOS test harness).
# Uses the pinned Dolphin source in ref/ModernGekko/vendor/dolphin unchanged.
cmake_minimum_required(VERSION 3.28)
project(GVDiscIO LANGUAGES C CXX)
get_filename_component(ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(D "${ROOT}/ref/ModernGekko/vendor/dolphin")
set(C "${D}/Source/Core")
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
file(GLOB MBED "${D}/Externals/mbedtls/library/*.c")
set(DISCIO_SOURCES
  ${C}/DiscIO/Blob.cpp ${C}/DiscIO/CISOBlob.cpp ${C}/DiscIO/CachedBlob.cpp
  ${C}/DiscIO/CompressedBlob.cpp ${C}/DiscIO/DiscExtractor.cpp ${C}/DiscIO/DiscUtils.cpp
  ${C}/DiscIO/Enums.cpp ${C}/DiscIO/FileBlob.cpp ${C}/DiscIO/FileSystemGCWii.cpp
  ${C}/DiscIO/Filesystem.cpp ${C}/DiscIO/NFSBlob.cpp ${C}/DiscIO/ScrubbedBlob.cpp
  ${C}/DiscIO/SplitFileBlob.cpp ${C}/DiscIO/TGCBlob.cpp ${C}/DiscIO/Volume.cpp
  ${C}/DiscIO/VolumeDisc.cpp ${C}/DiscIO/VolumeGC.cpp ${C}/DiscIO/VolumeWad.cpp
  ${C}/DiscIO/VolumeWii.cpp ${C}/DiscIO/WbfsBlob.cpp ${C}/DiscIO/WiiEncryptionCache.cpp
  ${C}/DiscIO/WiiSaveBanner.cpp ${C}/DiscIO/LaggedFibonacciGenerator.cpp
  ${C}/Core/IOS/ES/Formats.cpp ${C}/Core/IOS/IOSC.cpp
  ${C}/Common/FileUtil.cpp ${C}/Common/IOFile.cpp ${C}/Common/StringUtil.cpp
  ${C}/Common/MsgHandler.cpp ${C}/Common/Hash.cpp ${C}/Common/ColorUtil.cpp
  ${C}/Common/Crypto/AES.cpp ${C}/Common/Crypto/SHA1.cpp ${C}/Common/Crypto/bn.cpp
  ${C}/Common/Crypto/ec.cpp ${C}/Common/Crypto/HMAC.cpp
  ${C}/Common/DirectIOFile.cpp ${C}/DiscIO/DiscScrubber.cpp ${C}/Common/NandPaths.cpp
  ${C}/Common/Random.cpp ${C}/Common/MemArenaDarwin.cpp ${C}/Common/DynamicLibrary.cpp
  ${C}/Common/CommonFuncs.cpp ${C}/Common/ArmCPUDetect.cpp
  GVDiscIOStubs.cpp GVDiscIO.cpp)
add_library(gvdiscio STATIC ${DISCIO_SOURCES} ${MBED})
target_include_directories(gvdiscio PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}" "${C}" "${D}/Source"
  "${ROOT}/ref/ModernGekko/vendor/fmt/fmt/include" "${D}/Externals/mbedtls/include" "${D}/Externals/mbedtls/library" "${D}/Externals"
  "${CMAKE_CURRENT_SOURCE_DIR}/shim" "${D}/Externals/liblzma/api")
target_compile_definitions(gvdiscio PRIVATE FMT_HEADER_ONLY=1 $<$<COMPILE_LANGUAGE:CXX>:_ARCH_64=1 _M_ARM_64=1>)
target_compile_options(gvdiscio PRIVATE -w -fvisibility=hidden)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "visionOS")
  add_executable(gvdiscio-harness harness.cpp)
  target_link_libraries(gvdiscio-harness gvdiscio z iconv "-framework Foundation")
endif()
