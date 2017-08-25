set(LLVM_LINK_COMPONENTS
  Support
  )

add_clang_executable(ClangAutoStats
  ClangAutoStats.cpp
)

target_link_libraries(ClangAutoStats
    clangAST
    clangBasic
    clangDriver
    clangFormat
    clangLex
    clangParse
    clangSema
    clangFrontend
    clangTooling
    clangToolingCore
    clangRewrite
    clangRewriteFrontend
)

if(UNIX)
  set(CLANGXX_LINK_OR_COPY create_symlink)
else()
  set(CLANGXX_LINK_OR_COPY copy)
endif()
