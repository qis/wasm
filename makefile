MAKEFLAGS += --no-print-directory

URL	?= https://github.com/llvm-project/llvm-project-20170507
PREFIX	?= /opt/llvm
SHARED	?= OFF
STATIC	?= ON
WASM	?= ON
JOBS	?= 4

ifeq ($(WASM),ON)
all:
	@if [ ! -d "$(PREFIX)" ]; then \
	  make llvm; \
	fi
	@if [ ! -e "$(PREFIX)/include/c++/v1/filesystem" ]; then \
	  make filesystem; \
	fi
	@if [ ! -e "$(PREFIX)/bin/wasm" ]; then \
	  make wasm; \
	fi
	@if [ ! -e "$(PREFIX)/wasm.syms" ]; then \
	  make wasm.syms; \
	fi
	@if [ ! -e "$(PREFIX)/wasm/lib/libc.a" ]; then \
	  make musl; \
	fi
	@if [ ! -e "$(PREFIX)/wasm/lib/libclang_rt.builtins-wasm32.a" ]; then \
	  make compiler-rt; \
	fi
	@if [ ! -e "$(PREFIX)/wasm/lib/libc++abi.a" ]; then \
	  make libcxxabi; \
	fi
	@if [ ! -e "$(PREFIX)/wasm/lib/libc++.a" ]; then \
	  make libcxx; \
	fi
	@if [ "`stat -c "%A" $(PREFIX)/bin`" != "drwxr-xr-x" ]; then \
	  make permissions; \
	fi
else
all:
	@if [ ! -d "$(PREFIX)" ]; then \
	  make llvm; \
	fi
endif

src:
	git clone --depth 1 --no-checkout $(URL) src
	mkdir -p src/.git/info && cp checkout src/.git/info/sparse-checkout
	cd src && git config core.sparsecheckout true && git checkout master
	git clone -b wasm-prototype-1 https://github.com/jfbastien/musl src/musl
	cd src/musl && git apply < $(PWD)/musl.patch
	rm -rf src/.git

llvm: src
	rm -rf build/llvm; mkdir -p build/llvm && cd build/llvm && \
	  cmake -GNinja -DCMAKE_BUILD_TYPE=Release \
	    -DLLVM_ENABLE_PROJECTS="clang;clang-tools-extra;libcxx;libcxxabi;compiler-rt;libunwind;lld" \
	    -DCMAKE_INSTALL_PREFIX="$(PREFIX)" \
	    -DLLVM_TARGETS_TO_BUILD="AArch64;ARM;X86;WebAssembly" \
	    -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="WebAssembly" \
	    -DLLVM_ENABLE_ASSERTIONS=OFF \
	    -DLLVM_ENABLE_WARNINGS=OFF \
	    -DLLVM_ENABLE_PEDANTIC=OFF \
	    -DLLVM_INCLUDE_EXAMPLES=OFF \
	    -DLLVM_INCLUDE_TESTS=OFF \
	    -DLLVM_INCLUDE_DOCS=OFF \
	    -DCLANG_DEFAULT_CXX_STDLIB="libc++" \
	    -DLIBCXXABI_ENABLE_ASSERTIONS=OFF \
	    -DLIBCXXABI_ENABLE_EXCEPTIONS=ON \
	    -DLIBCXXABI_ENABLE_SHARED=$(SHARED) \
	    -DLIBCXXABI_ENABLE_STATIC=$(STATIC) \
	    -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
	    -DLIBCXX_ENABLE_ASSERTIONS=OFF \
	    -DLIBCXX_ENABLE_EXCEPTIONS=ON \
	    -DLIBCXX_ENABLE_SHARED=$(SHARED) \
	    -DLIBCXX_ENABLE_STATIC=$(STATIC) \
	    -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=$(STATIC) \
	    -DLIBCXX_ENABLE_ASSERTIONS=OFF \
	    -DLIBCXX_ENABLE_FILESYSTEM=ON \
	    -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=ON \
	    -DLIBCXX_INSTALL_EXPERIMENTAL_LIBRARY=ON \
	    -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
	    ../../src/llvm && \
	  cmake --build . --target install -- -j$(JOBS)

filesystem:
	echo "#pragma once" >> $(PREFIX)/include/c++/v1/filesystem
	echo "#include <experimental/filesystem>" >> $(PREFIX)/include/c++/v1/filesystem
	echo "namespace std {" >> $(PREFIX)/include/c++/v1/filesystem
	echo "  namespace filesystem = experimental::filesystem;" >> $(PREFIX)/include/c++/v1/filesystem
	echo "}" >> $(PREFIX)/include/c++/v1/filesystem

wasm:
	cp wasm.sh $(PREFIX)/bin/wasm
	@cd $(PREFIX)/bin && for i in cc c++ clang clang++; do \
	  echo "$(PREFIX)/bin/wasm-$$i -> wasm"; \
	  rm -f wasm-$$i; ln -s wasm wasm-$$i; \
	done
	@cd $(PREFIX)/bin && for i in ar as nm objcopy objdump ranlib readelf readobj size strings; do \
	  echo "$(PREFIX)/bin/wasm-$$i -> llvm-$$i"; \
	  rm -f wasm-$$i; ln -s llvm-$$i wasm-$$i; \
	done

wasm.syms:
	cp wasm.syms $(PREFIX)/wasm.syms

musl: src
	rm -rf build/musl; mkdir -p build/musl && cd build/musl && \
	  CROSS_COMPILE="$(PREFIX)/bin/wasm-" CFLAGS="-Wno-everything" \
	  ../../src/musl/configure --prefix=$(PREFIX)/wasm \
	    --disable-shared --enable-optimize=size && \
	  make all install -j$(JOBS)

compiler-rt: src
	rm -rf build/compiler-rt; mkdir -p build/compiler-rt && cd build/compiler-rt && \
	  LDFLAGS="-lc -nodefaultlibs -nostdlib++ -fuse-ld=lld" \
	  cmake -GNinja -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_INSTALL_PREFIX="$(PREFIX)/wasm" \
	    -DCMAKE_C_COMPILER="$(PREFIX)/bin/wasm-clang" \
	    -DCMAKE_CXX_COMPILER="$(PREFIX)/bin/wasm-clang++" \
	    -DLLVM_CONFIG_PATH="$(PREFIX)/bin/llvm-config" \
	    -DCMAKE_RANLIB="$(PREFIX)/bin/llvm-ranlib" \
	    -DCMAKE_NM="$(PREFIX)/bin/llvm-nm" \
	    -DCMAKE_AR="$(PREFIX)/bin/llvm-ar" \
	    -DCMAKE_SYSTEM_NAME="Linux" \
	    -DCOMPILER_RT_BUILD_BUILTINS=OFF \
	    -DCOMPILER_RT_SANITIZERS_TO_BUILD="" \
	    -DCOMPILER_RT_DEFAULT_TARGET_TRIPLE="wasm32-unknown-unknown-wasm" \
	    -DCOMPILER_RT_BUILD_BUILTINS=ON \
	    -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
	    -DCOMPILER_RT_BUILD_XRAY=OFF \
	    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
	    -DCOMPILER_RT_BUILD_PROFILE=OFF \
	    -DCOMPILER_RT_BAREMETAL_BUILD=ON \
	    -DCOMPILER_RT_EXCLUDE_ATOMIC_BUILTIN=ON \
	    -DCAN_TARGET_wasm32=ON \
	    ../../src/compiler-rt && \
	  cmake --build . --target install -- -j$(JOBS) && \
	  cd $(PREFIX)/wasm/lib && ln -s linux/libclang_rt.builtins-wasm32.a
  
libcxxabi: src
	rm -rf build/libcxxabi; mkdir -p build/libcxxabi && cd build/libcxxabi && \
	  CXXFLAGS="-I $(PWD)/src/libunwind/include" LDFLAGS="-nostdlib++ -fuse-ld=lld" \
	  cmake -GNinja -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_INSTALL_PREFIX="$(PREFIX)/wasm" \
	    -DCMAKE_C_COMPILER="$(PREFIX)/bin/wasm-clang" \
	    -DCMAKE_CXX_COMPILER="$(PREFIX)/bin/wasm-clang++" \
	    -DLLVM_CONFIG_PATH="$(PREFIX)/bin/llvm-config" \
	    -DCMAKE_RANLIB="$(PREFIX)/bin/llvm-ranlib" \
	    -DCMAKE_NM="$(PREFIX)/bin/llvm-nm" \
	    -DCMAKE_AR="$(PREFIX)/bin/llvm-ar" \
	    -DCMAKE_SYSTEM_NAME="Linux" \
	    -DLIBCXXABI_TARGET_TRIPLE="wasm32-unknown-unknown-wasm" \
	    -DLIBCXXABI_LIBCXX_PATH="$(PREFIX)/wasm" \
	    -DLIBCXXABI_ENABLE_ASSERTIONS=OFF \
	    -DLIBCXXABI_ENABLE_EXCEPTIONS=OFF \
	    -DLIBCXXABI_ENABLE_THREADS=OFF \
	    -DLIBCXXABI_ENABLE_SHARED=OFF \
	    -DLIBCXXABI_ENABLE_STATIC=ON \
	    -DLIBCXXABI_USE_COMPILER_RT=ON \
	    -DLIBCXXABI_INCLUDE_TESTS=OFF \
	    -DLIBCXXABI_SILENT_TERMINATE=ON \
	    -DLIBCXXABI_BAREMETAL=ON \
	    -DLLVM_ENABLE_LIBCXX=ON \
	    ../../src/libcxxabi && \
	  cmake --build . --target install -- -j$(JOBS)
  
libcxx: src
	rm -rf build/libcxx; mkdir -p build/libcxx && cd build/libcxx && \
	  LDFLAGS="-lc -nodefaultlibs -fuse-ld=lld" \
	  cmake -GNinja -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_INSTALL_PREFIX="$(PREFIX)/wasm" \
	    -DCMAKE_C_COMPILER="$(PREFIX)/bin/wasm-clang" \
	    -DCMAKE_CXX_COMPILER="$(PREFIX)/bin/wasm-clang++" \
	    -DLLVM_CONFIG_PATH="$(PREFIX)/bin/llvm-config" \
	    -DCMAKE_RANLIB="$(PREFIX)/bin/llvm-ranlib" \
	    -DCMAKE_NM="$(PREFIX)/bin/llvm-nm" \
	    -DCMAKE_AR="$(PREFIX)/bin/llvm-ar" \
	    -DLIBCXX_CXX_ABI_INCLUDE_PATHS="$(PWD)/src/libcxxabi/include" \
	    -DLIBCXX_CXX_ABI="libcxxabi" \
	    -DLIBCXX_ENABLE_ASSERTIONS=OFF \
	    -DLIBCXX_ENABLE_EXCEPTIONS=OFF \
	    -DLIBCXX_ENABLE_SHARED=OFF \
	    -DLIBCXX_ENABLE_STATIC=ON \
	    -DLIBCXX_ENABLE_FILESYSTEM=ON \
	    -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=ON \
	    -DLIBCXX_ENABLE_MONOTONIC_CLOCK=OFF \
	    -DLIBCXX_ENABLE_STDIN=OFF \
	    -DLIBCXX_ENABLE_STDOUT=OFF \
	    -DLIBCXX_ENABLE_THREADS=OFF \
	    -DLIBCXX_ENABLE_RTTI=OFF \
	    -DLIBCXX_INSTALL_EXPERIMENTAL_LIBRARY=ON \
	    -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
	    -DLIBCXX_INCLUDE_DOCS=OFF \
	    -DLIBCXX_INCLUDE_TESTS=OFF \
	    -DLIBCXX_HAS_ATOMIC_LIB=OFF \
	    -DLIBCXX_HAS_MUSL_LIBC=ON \
	    -DLIBCXX_USE_COMPILER_RT=ON \
	    ../../src/libcxx && \
	  cmake --build . --target install -- -j$(JOBS)

permissions:
	find $(PREFIX) -type d -exec chmod 0755 '{}' ';'

docs: docs/main

docs/main.o: docs/main.cpp
	$(PREFIX)/bin/wasm-clang++ -std=c++2a -Os -c -o $@ docs/main.cpp

docs/main: docs/main.syms docs/main.o
	$(PREFIX)/bin/wasm-clang++ -std=c++2a -Wl,--allow-undefined-file=docs/main.syms -o $@ docs/main.o

clean:
	rm -f docs/main.o

.PHONY: llvm filesystem wasm wasm.syms musl compiler-rt libcxxabi libcxx permissions docs clean
