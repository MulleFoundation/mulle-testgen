cmake_minimum_required (VERSION 3.0)

project( mulle-testgen NONE)
add_definitions( -DMULLE_TESTGEN_EXTERN_GLOBAL=extern)


#
# Primarily used for packaging on Linux
#
# Debian:
#
# ```
# mkdir package
# cd package
# cmake ..
# cpack -G DEB
# ```
#

execute_process( COMMAND ./mulle-testgen version
                 WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
                 OUTPUT_VARIABLE MULLE_TESTGEN_VERSION
                 OUTPUT_STRIP_TRAILING_WHITESPACE)
message( STATUS "MULLE_FOUNDATION_TESTGEN_VERSION is ${MULLE_FOUNDATION_TESTGEN_VERSION} according to mulle-foundation-testgen")


set( PROJECT_VERSION "${MULLE_FOUNDATION_TESTGEN_VERSION}")


set( SCRIPTS
mulle-testgen
)


file( GLOB LIBRARY_SCRIPTS
   "src/*.sh"
)

file( GLOB PLUGIN_SCRIPTS
   "src/plugins/*.sh"
)


INSTALL( FILES ${SCRIPTS}
PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ
            GROUP_EXECUTE GROUP_READ
            WORLD_EXECUTE WORLD_READ
DESTINATION "bin")


INSTALL( FILES ${LIBRARY_SCRIPTS}
PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ
            GROUP_EXECUTE GROUP_READ
            WORLD_EXECUTE WORLD_READ
DESTINATION "libexec/mulle-testgen")

INSTALL( FILES ${PLUGIN_SCRIPTS}
PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ
            GROUP_EXECUTE GROUP_READ
            WORLD_EXECUTE WORLD_READ
DESTINATION "libexec/mulle-testgen/plugins")


######
#
# must be after CPACK_PACKAGE_VERSION
include( CMakePackage.cmake)
include( CPack)

