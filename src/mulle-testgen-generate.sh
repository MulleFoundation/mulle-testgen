#! /usr/bin/env bash
#
#   Copyright (c) 2019 Nat! - Mulle kybernetiK
#   All rights reserved.
#
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions are met:
#
#   Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
#   Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
#   Neither the name of Mulle kybernetiK nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#   ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
#   LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#   CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#   SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#   INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#   CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#   ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#
MULLE_TESTGEN_GENERATE_SH="included"


testgen_print_flags()
{
   echo "   -d <dir>    : test directory (test)"
   echo "   -f          : force operation"
   echo "   -l <name>   : name of library to use for includes"
   echo "   -c <class>  : restrict output to <class>"
   echo "   -m          : emit test code for each public method"
   echo "   -p          : emit test code for each property"
}


testgen_generate_usage()
{
   [ $# -ne 0 ] && log_error "$*"

   cat <<EOF >&2
Usage:
   ${MULLE_USAGE_NAME} generate [options]

   Generate Objective-C test files. This script loads and Objective-C
   static library, and emits a test file for each non-root Objective-C
   class that is defined in this library. By default existing tests are not
   overwritten.

   You should first craft your library, then setup your mulle-test folder
   and then run this script.

   Prevent generation of specific tests, by creating a '.' file of the same
   name:

      touch test/10_generated/.foo.m

   This tool currently only generates some Objective-C code that can be used
   to actually write tests. Its going to become smarter over time.

Options:
EOF
   testgen_print_flags | LC_ALL=C sort >&2

   exit 1
}


r_get_plugin_name()
{
   log_entry "emit_class_test_header" "$@"

   local signature="$1"
   local suffix="$1"

   case ${signature} in
      "")
         return 1
      ;;

      \*\*)
         is_pointer='YES'
         r_get_plugin_name "${signature%\*}" "_pointer${suffix}"
         return $?
      ;;

      @\".*\")
         RVAL="${signature#@\"}"
         RVAL="${RVAL%\"}"
         RVAL="${RVAL}${suffix}"
         return 0
      ;;

      @)
         RVAL="id"
         return 0
      ;;

      *)
         RVAL="${signature}_suffix"
         return 0
      ;;
   esac
}


emit_class_test_header()
{
   log_entry "emit_class_test_header" "$@"

   local classname="$1"
   local libraryname="$2"

   [ -z "${classname}" ] && internal_fail "classname is empty"
   [ -z "${libraryname}" ] && internal_fail "classname is empty"

   cat <<EOF
#import <${libraryname}/${libraryname}.h>
#include <stdio.h>


EOF
}


emit_class_test_footer()
{
   log_entry "emit_class_test_footer" "$@"

   cat <<EOF

static void  run_test( void (*f)( void))
{
   // wrap in mulle-testallocator
   (*f)();
}


int   main( int argc, char *argv[])
{
#ifdef __MULLE_OBJC__
   // check that no classes are "stuck"
   if( mulle_objc_global_check_universe( __MULLE_OBJC_UNIVERSENAME__) !=
         mulle_objc_universe_is_ok)
      return( 1);
#endif
EOF

   for tests in "$@"
   do
      cat <<EOF
   run_test( ${tests});
EOF
   done

   cat <<EOF

   return( 0);
}
EOF
}


emit_noleak_test()
{
   log_entry "emit_noleak_test" "$@"

   local classname="$1"

   [ -z "${classname}" ] && internal_fail "classname is empty"

   cat <<EOF
//
// noleak checks for alloc/dealloc/finalize
// and also load/unload initialize/deinitialize
// if the test environment sets MULLE_OBJC_PEDANTIC_EXIT
//
static void   test_noleak()
{
   ${classname}  *obj;

   @try
   {
      obj = [[${classname} new] autorelease];
      if( ! obj)
      {
         printf( "failed to allocate\n");
      }
   }
   @catch( NSException *exception)
   {
      printf( "Threw a %s exception\n", [[exception name] UTF8String]);
   }
}

EOF
}


emit_instancemethod_test()
{
   log_entry "emit_instancemethod_test" "$@"

   local classname="$1"
   local name="$2"
   local signature="$3"
   local identifier="$4"
   local functionname="$5"

   cat <<EOF

static void   ${functionname}()
{
   ${classname}   *obj;

   @autoreleasepool
   {
      obj = [[${classname} alloc] init];
      [obj ${name}];
      [obj release];
   }
   // TODO: lots of work
}

EOF
}


emit_classmethod_test()
{
   log_entry "emit_classmethod_test" "$@"

   local classname="$1"
   local name="$2"
   local signature="$3"
   local identifier="$4"

   cat <<EOF

static void   test_cm_${identifier}()
{
   @autoreleasepool
   {
      [${classname} ${name}];
   }
   // TODO: lots of work
}

EOF
}


emit_method_test()
{
   log_entry "emit_classmethod_test" "$@"

   local classname="$1"
   local name="$2"
   local signature="$3"

   local identifier

   if [ -z "${MULLE_CASE_SH}" ]
   then
      # shellcheck source=mulle-case.sh
      . "${MULLE_BASHFUNCTIONS_LIBEXEC_DIR}/mulle-case.sh" || return 1
   fi

   r_tweaked_de_camel_case "${name:1}"
   identifier="`tr "A-Z:" "a-z_" <<< "${RVAL}"`"

   local functionname

   case "${name}" in
      ?_*)
         log_debug "Ignore methods prefixed with an underscore"
         return 0
      ;;

      +*)
         functionname="test_im_${identifier}"
         emit_classmethod_test "${classname}" \
                               "${name:1}" \
                               "${signature}" \
                               "${identifier}"\
                               "${functionname}"
      ;;

      -*)
         functionname="test_cm_${identifier}"
         emit_instancemethod_test "${classname}" \
                                  "${name:1}" \
                                  "${signature}" \
                                  "${identifier}" \
                                  "${functionname}"
      ;;

      *)
         fail "Unknown method format \"${method}\""
      ;;
   esac

   r_add_line "${METHOD_TEST_FUNCTIONS}" "${functionname}"
   METHOD_TEST_FUNCTIONS="${RVAL}"
}


emit_method_tests()
{
   log_entry "emit_method_tests" "$@"

   local classid="$1"
   local library="$2"

   local classid
   local classname
   local categoryid
   local categoryname
   local methodid
   local name
   local signature

   METHOD_TEST_FUNCTIONS=""

   [ "${OPTION_EMIT_METHOD_TESTS}" = 'NO' ] && return 0

   while IFS=";" read -r classid classname categoryid categoryname methodid name signature
   do
      if [ "${MULLE_FLAG_LOG_SETTINGS}" = 'YES' ]
      then
         log_trace2 "class-id:           ${classid}"
         log_trace2 "class-name:         ${classname}"
         log_trace2 "category-id:        ${categoryid}"
         log_trace2 "category-name:      ${categoryname}"
         log_trace2 "method-id:          ${methodid}"
         log_trace2 "method-name:        ${name}"
         log_trace2 "method-signature:   ${signature}"
      fi

      emit_method_test "${classname}" "${name}" "${signature}" || return 1
   done < <( rexekutor "${MULLE_OBJC_LISTA}" -f "${classid}" -m "${library}" )
}


emit_property_test()
{
   log_entry "emit_property_test" "$@"

   local classname="$1"
   local name="$2"
   local signature="$3"

   [ -z "${classname}" ] && internal_fail "classname is empty"
   [ -z "${name}" ] && internal_fail "name is empty"
   [ -z "${signature}" ] && internal_fail "signature is empty"

   cat <<EOF
//
// this checks a bit for alloc/dealloc/finalize
// and also load/unload initialize/deinitialize
// the test environment will set MULLE_OBJC_PEDANTIC_EXIT
//
static void   test_properties()
{
   // TODO: lots of work
}

EOF

   PROPERTY_TEST_FUNCTIONS="test_properties"
}


emit_property_tests()
{
   log_entry "emit_property_tests" "$@"

   local classid="$1"
   local library="$2"

   local property_classid
   local property_classname
   local property_id
   local property_name
   local property_signature

   PROPERTY_TEST_FUNCTIONS=""

   [ "${OPTION_EMIT_PROPERTY_TESTS}" = 'NO' ] && return 0

   while IFS=";" read -r property_classid property_classname property_id property_name property_signature
   do
      if [ "${MULLE_FLAG_LOG_SETTINGS}" = 'YES' ]
      then
         log_trace2 "class-id:           ${property_classid}"
         log_trace2 "class-name:         ${property_classname}"
         log_trace2 "property-id:        ${property_id}"
         log_trace2 "property-name:      ${property_name}"
         log_trace2 "property-signature: ${property_signature}"
      fi

      emit_property_test "${property_classname}" "${property_name}" "${property_signature}" || return 1
   done < <( rexekutor "${MULLE_OBJC_LISTA}" -f "${classid}" -p "${library}" )
}


emit_class_test()
{
   log_entry "emit_class_test" "$@"

   local classid="$1"
   local classname="$2"
   local library="$3"
   local libraryname="$4"

   emit_class_test_header "${classname}" "${libraryname}" &&
   emit_noleak_test "${classname}" &&
   emit_property_tests "${classid}" "${library}" &&
   emit_method_tests "${classid}" "${library}" &&
   emit_class_test_footer test_noleak ${PROPERTY_TEST_FUNCTIONS} ${METHOD_TEST_FUNCTIONS}
}


generate_class_test()
{
   log_entry "generate_class_test" "$@"

   local classid="$1"
   local classname="$2"
   local library="$3"
   local libraryname="$4"

   [ -z "${classid}" ]     && internal_fail "classid is empty"
   [ -z "${classname}" ]   && internal_fail "classname is empty"
   [ -z "${library}" ]     && internal_fail "library is empty"
   [ -z "${libraryname}" ] && internal_fail "libraryname is empty"

   local text
   local filename
   local ignorefilename
   local fname

   fname="test-${classname}.m"
   filename="${OPTION_TEST_DIR}/10_generated/${fname}"
   ignorefilename="${OPTION_TEST_DIR}/10_generated/.${fname}"

   if [ "${MULLE_FLAG_MAGNUM_FORCE}" = 'NO' ]
   then
      if [ -f "${filename}" ]
      then
         log_fluff "\"${fname}\" already exists at \"${filename}\""
         return
      fi
   fi

   if [ -f "${ignorefilename}" ]
   then
      log_fluff "\"${fname}\" set to ignore by \"${ignorefilename}\""
      return
   fi

   log_verbose "${fname}"

   text="`emit_class_test "${classid}" "${classname}" "${library}" "${libraryname}" `" || return 1

   mkdir_parent_if_missing "${filename}"
   log_debug "Write \"${filename}\""
   echo "${text}" > "${filename}"
}


generate_class_tests()
{
   log_entry "generate_class_tests" "$@"

   local library="$1"
   local libraryname="$2"
   local filterid="$3"

   local classname
   local classid

   local lines
   local cmdline="'${MULLE_OBJC_LISTA}'"

   if [ ! -z "${filterid}" ]
   then
      cmdline="${cmdline} -f '${filterid}'"
   fi
   cmdline="${cmdline} -C '${library}'"

   lines="`eval_rexekutor "${cmdline}" `" || fail "mulle-objc-lista failed"
   if [ -z "${lines}" ]
   then
      log_info "No classes found in \"${library}\""
      return
   fi

   while IFS=";" read -r classid classname superid superclassname
   do
      if [ "${MULLE_FLAG_LOG_SETTINGS}" = 'YES' ]
      then
         log_trace2 "class-id:        ${classid}"
         log_trace2 "class-name:      ${classname}"
         log_trace2 "superclass-id:   ${superid}"
         log_trace2 "superclass-name: ${superclassname}"
      fi

      case "${classname}" in
         "")
            continue
         ;;

         _*)
            log_fluff "Ignore '_' prefixed class \"${classname}\""
            continue
         ;;
      esac

      if [ -z "${superclassname}" ]
      then
         log_fluff "Ignore '_' root class \"${classname}\""
         continue
      fi

      generate_class_test "${classid}" "${classname}" "${library}" "${libraryname}" || fail "failed to generate test for \"${classname}\""
   done < <( echo "${lines}")
}


testgen_generate_main()
{
   local library

   #
   # simple option handling
   #
   while [ $# -ne 0 ]
   do
      case "$1" in
         -h*|--help|help)
            testgen_generate_usage
         ;;

         -c|--class-name|--classname)
            shift
            OPTION_CLASS_NAME="$1"
         ;;

         -d|--test-dir)
            shift
            OPTION_TEST_DIR="$1"
         ;;

         -l|--library-name)
            shift
            OPTION_LIBRARY_NAME="$1"
         ;;

         -p|--emit-property-tests)
            OPTION_EMIT_PROPERTY_TESTS='YES'
         ;;

         -m|--emit-method-tests)
            OPTION_EMIT_METHOD_TESTS='YES'
         ;;

         --version)
            echo "${MULLE_EXECUTABLE_VERSION}"
            exit 0
         ;;

         -*)
            usage "Unknown option \"$1\""
         ;;

         *)
            break
         ;;
      esac

      shift
   done

   # shellcheck source=src/mulle-fetch-commands.sh
   . "${MULLE_TESTGEN_LIBEXEC_DIR}/mulle-testgen-plugin.sh"



   if [ $# -ne 0 ]
   then
      library="$1"
      shift
   fi

   if [ -z "${library}" ]
   then
      r_fast_basename "${MULLE_USER_PWD}"
      library="${RVAL}"
      log_fluff "Assuming \"${library}\" as name"
   fi

   log_fluff "Looking for \"${library}\" ($PWD)"
   if [ ! -f "${library}" ]
   then
      case "${library}" in
         lib*|*.a|*.lib|*/*)
         ;;

         *)
            library="lib${library%.a}.a"
         ;;
      esac

      check="build/Debug/${library}"
      log_fluff "Looking for \"${check}\""
      if [ ! -f "${check}" ]
      then
         check="build/Release/${library}"
         log_fluff "Looking for \"${check}\""
         if [ ! -f "${check}" ]
         then
            check="build/${library}"
            log_fluff "Looking for \"${check}\""
            if [ ! -f "${check}" ]
            then
               fail "Could not find a \"${library}\" static library"
            fi
         fi
      fi
      library="${check}"
   else
      log_fluff "Library \"${library}\" found "
   fi

   libraryname="${OPTION_LIBRARY_NAME}"
   if [ -z "${libraryname}" ]
   then
      r_extensionless_basename "${library}"
      libraryname="${RVAL#lib}"
   fi

   local filterid

   if [ ! -z "${OPTION_CLASS_NAME}" ]
   then
      filterid="`rexekutor "${MULLE_OBJC_UNIQUEID}" "${OPTION_CLASS_NAME}" `" || exit 1
   fi

   generate_class_tests "${library}" "${libraryname}" "${filterid}"
}
