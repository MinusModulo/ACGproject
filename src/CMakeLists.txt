file(GLOB_RECURSE DEMO_SOURCES "*.cpp" "*.h")

add_executable(ShortMarchDemo ${DEMO_SOURCES})

target_link_libraries(ShortMarchDemo LongMarch)

PACK_SHADER_CODE(ShortMarchDemo)

# Force cmake re-run to pick up anyhit.hlsl and other new shaders


