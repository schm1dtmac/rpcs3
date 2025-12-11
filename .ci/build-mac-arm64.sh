#!/bin/sh -ex

# shellcheck disable=SC2086
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

brew install -f --overwrite --quiet "llvm@$LLVM_COMPILER_VER"

curl -O https://sdk.lunarg.com/sdk/download/1.4.328.1/mac/vulkan_sdk.zip
unzip vulkan_sdk.zip
sudo ./vulkansdk-macOS-1.4.328.1.app/Contents/MacOS/vulkansdk-macOS-1.4.328.1 --root ~/VulkanSDK --accept-licenses --default-answer --confirm-command install

git clone https://github.com/opencv/opencv.git
mkdir build_opencv; cd build_opencv
pip3 install numpy --break-system-packages 
cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_opencv_apps=OFF -DBUILD_SHARED_LIBS=OFF ../opencv
make -j8; cd ../

git clone https://github.com/nigels-com/glew.git
cd glew/build
cmake ./cmake -DBUILD_FRAMEWORK=ON -DCMAKE_INSTALL_PREFIX=/Library/Frameworks
make -j8; cd ../../

brew link -f --quiet "llvm@$LLVM_COMPILER_VER"

export CXX=clang++
export CC=clang

export BREW_PATH;
BREW_PATH="$(brew --prefix)"
export BREW_BIN="/opt/homebrew/bin"
export BREW_SBIN="/opt/homebrew/sbin"
export CMAKE_EXTRA_OPTS='-DLLVM_TARGETS_TO_BUILD=arm64'

export WORKDIR;
WORKDIR="$(pwd)"

# Setup ccache
if [ ! -d "$CCACHE_DIR" ]; then
  mkdir -p "$CCACHE_DIR"
fi

# Get Qt
if [ ! -d "/tmp/Qt/$QT_VER" ]; then
  mkdir -p "/tmp/Qt"
  git clone https://github.com/engnr/qt-downloader.git
  cd qt-downloader
  git checkout f52efee0f18668c6d6de2dec0234b8c4bc54c597
  sed -i '' "s/'qt{0}_{0}{1}{2}'.format(major, minor, patch)]))/'qt{0}_{0}{1}{2}'.format(major, minor, patch), 'qt{0}_{0}{1}{2}'.format(major, minor, patch)]))/g" qt-downloader
  sed -i '' "s/'{}\/{}\/qt{}_{}\/'/'{0}\/{1}\/qt{2}_{3}\/qt{2}_{3}\/'/g" qt-downloader
  cd "/tmp/Qt"
  pip3 install py7zr requests semantic_version lxml --break-system-packages --no-cache
  mkdir -p "$QT_VER/macos" ; ln -s "macos" "$QT_VER/clang_64"
  sed -i '' 's/args\.version \/ derive_toolchain_dir(args) \/ //g' "$WORKDIR/qt-downloader/qt-downloader"
  python3 "$WORKDIR/qt-downloader/qt-downloader" macos desktop "$QT_VER" clang_64 --opensource --addons qtmultimedia qtimageformats -o "$QT_VER/clang_64"
fi

cd "$WORKDIR"
ditto "/tmp/Qt/$QT_VER" "qt-downloader/$QT_VER"

export Qt6_DIR="$WORKDIR/qt-downloader/$QT_VER/clang_64/lib/cmake/Qt$QT_VER_MAIN"
export OpenCV_DIR="$WORKDIR/build_opencv"
export PATH="$BREW_PATH/opt/llvm@$LLVM_COMPILER_VER/bin:$WORKDIR/qt-downloader/$QT_VER/clang_64/bin:$BREW_BIN:$BREW_SBIN:/usr/bin:/bin:/usr/sbin:/sbin:/opt/X11/bin:/Library/Apple/usr/bin:$PATH"
export LDFLAGS="-L$BREW_PATH/lib $BREW_PATH/opt/llvm@$LLVM_COMPILER_VER/lib/c++/libc++.1.dylib $BREW_PATH/opt/llvm@$LLVM_COMPILER_VER/lib/unwind/libunwind.1.dylib -Wl,-rpath,$BREW_PATH/lib"
export CPPFLAGS="-I$BREW_PATH/include -D__MAC_OS_X_VERSION_MIN_REQUIRED=140000"
export CFLAGS="-D__MAC_OS_X_VERSION_MIN_REQUIRED=140000"
export LIBRARY_PATH="$BREW_PATH/lib"
export LD_LIBRARY_PATH="$BREW_PATH/lib"

export VULKAN_SDK
VULKAN_SDK=~/VulkanSDK/macOS
ln -s "$VULKAN_SDK/lib/libvulkan.dylib" "$VULKAN_SDK/lib/libvulkan.dylib" || true

export LLVM_DIR
LLVM_DIR="$BREW_PATH/opt/llvm@$LLVM_COMPILER_VER"
# exclude ffmpeg, LLVM, opencv, and sdl from submodule update
# shellcheck disable=SC2046
git submodule -q update --init --depth=1 --jobs=8 $(awk '/path/ && !/llvm/ && !/opencv/ && !/feralinteractive/ { print $3 }' .gitmodules)

# 3rdparty fixes
sed -i '' "s/extern const double NSAppKitVersionNumber;/const double NSAppKitVersionNumber = 1343;/g" 3rdparty/hidapi/hidapi/mac/hid.c

mkdir build && cd build || exit 1

export MACOSX_DEPLOYMENT_TARGET=14.0

"$BREW_PATH/bin/cmake" .. \
    -DBUILD_RPCS3_TESTS=OFF \
    -DRUN_RPCS3_TESTS=OFF \
    -DUSE_SDL=ON \
    -DUSE_DISCORD_RPC=ON \
    -DUSE_VULKAN=ON \
    -DUSE_ALSA=OFF \
    -DUSE_PULSE=OFF \
    -DUSE_AUDIOUNIT=ON \
    -DUSE_SYSTEM_FFMPEG=OFF \
    -DLLVM_CCACHE_BUILD=OFF \
    -DLLVM_BUILD_RUNTIME=OFF \
    -DLLVM_BUILD_TOOLS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_TOOLS=OFF \
    -DLLVM_INCLUDE_UTILS=OFF \
    -DLLVM_USE_PERF=OFF \
    -DLLVM_ENABLE_Z3_SOLVER=OFF \
    -DUSE_NATIVE_INSTRUCTIONS=OFF \
    -DUSE_SYSTEM_MVK=ON \
    -DUSE_SYSTEM_FAUDIO=OFF \
    -DUSE_SYSTEM_SDL=OFF \
    -DUSE_SYSTEM_OPENCV=ON \
    "$CMAKE_EXTRA_OPTS" \
    -DLLVM_TARGET_ARCH=arm64 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_IGNORE_PATH="$BREW_PATH/lib" \
    -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew/opt \
    -DCMAKE_CXX_FLAGS="-D__MAC_OS_X_VERSION_MIN_REQUIRED=140000" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_OSX_SYSROOT="$(xcrun --sdk macosx --show-sdk-path)" \
    -G Ninja

"$BREW_PATH/bin/ninja"; build_status=$?;

cd ..

# If it compiled succesfully let's deploy.
if [ "$build_status" -eq 0 ]; then
    .ci/deploy-mac-arm64.sh
fi
