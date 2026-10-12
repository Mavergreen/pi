cmake_minimum_required(VERSION 3.25)

project(Pi LANGUAGES C OBJC)

find_package(MavericksShipyard REQUIRED)
mavericks_resolve_version(PI_VERSION)
include(Mavericks)
include(MavericksMode)
mavericks_build_mode(MAVERICKS_MODE)
mavericks_require_expected_mode("${MAVERICKS_MODE}")
message(STATUS "Pi for Mavericks ${PI_VERSION}: build mode ${MAVERICKS_MODE}")

option(PI_BUILD_UPDATER "Build the Sparkle updater (needs pi in the installed shipyard's product registry)" OFF)

if(PI_BUILD_UPDATER)
  include(MavericksSparkle)
  mavericks_add_updater_app(
    PRODUCT pi
    PRODUCT_NAME "Mavericks Pi"
    ALLOW_GENERIC
    VERSION "${PI_VERSION}"
    CONFIRM_TITLE "Mavericks Pi updated"
    CONFIRM_BODY "The next pi you start uses the new launcher.")
endif()
