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
   cat <<EOF
   -0          : dont create a subdirectory for each class
   -1          : write one test file for each method
   -e          : test code exits on error immediately
   -C <class>  : restrict output to <class>
   -d <dir>    : test directory (test)
   -i          : emit test code for init methods
   -l <name>   : name of library
   -m          : emit test code for public methods (except init)
   -M <method> : restrict output to <method>
   -p          : emit test code for properties
   -P <prefix> : emit only test code for classes with prefix
EOF
}


testgen_generate_usage()
{
   [ $# -ne 0 ] && log_error "$*"

   cat <<EOF >&2
Usage:
   ${MULLE_USAGE_NAME} generate [options]

   Generate Objective-C test files. This script loads an Objective-C static
   library. For each non-root Objective-C class that is defined in this
   library it emits a test file. By default existing tests are not overwritten.

   You should first craft your library. Then generate the test after having
   built the library. Then generate the tests and then setup your mulle-test
   folder. You can not run mulle-testgen inside the "test" folder, as
   mulle-test will not have a static library.

   So the initial sequence might be:

      mulle-sde craft
      mulle-sde run mulle-testgen generate
      mulle-sde test init

   Prevent generation of specific tests, by creating a '.' file of the same
   name:

      touch test/10_generated/.foo.m

   If no tests are selected with options a simple "noleak" test is created.

Options:
EOF
   testgen_print_flags | LC_ALL=C sort >&2

   exit 1
}




emit_test_header()
{
   log_entry "emit_test_header" "$@"

   local libraryname="$1"

   LEGACY_LIBRARY_NAME="${LEGACY_LIBRARY_NAME:-Foundation}"

   [ -z "${libraryname}" ] && internal_fail "libraryname is empty"

   cat <<EOF
#ifdef __MULLE_OBJC__
# import <${libraryname}/${libraryname}.h>
# include <mulle-testallocator/mulle-testallocator.h>
#else
# import <${LEGACY_LIBRARY_NAME}/${LEGACY_LIBRARY_NAME}.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#if defined(__unix__) || defined(__unix) || (defined(__APPLE__) && defined(__MACH__))
# include <unistd.h>
#endif


EOF
}


emit_noleak_test_footer()
{
   log_entry "emit_noleak_test_footer" "$@"

   cat <<EOF


int   main( int argc, char *argv[])
{
#ifdef __MULLE_OBJC__
   // check that no classes are "stuck"
   if( mulle_objc_global_check_universe( __MULLE_OBJC_UNIVERSENAME__) !=
         mulle_objc_universe_is_ok)
      _exit( 1);
#endif

   test_noleak();
   return( 0);
}
EOF
}


emit_class_test_footer()
{
   log_entry "emit_class_test_footer" "$@"

   if [ $# -eq 0 ]
   then
      return 1
   fi

   local onerror

   onerror="return"
   if [ "${OPTION_EXIT_ON_ERROR}" = 'YES' ]
   then
      onerror="_exit"
   fi

   local lf='\n'

   cat <<EOF

static int   run_test( int (*f)( void), char *name)
{
   mulle_testallocator_discard();  //  w
   @autoreleasepool                //  i
   {                               //  l  l
      printf( "%s${lf}", name);       //  l  e  c
      if( (*f)())                  //     a  h
         ${onerror}( 1);              //     k  e
   }                               //        c
   mulle_testallocator_reset();    //        k
   return( 0);
}


int   main( int argc, char *argv[])
{
   int   errors;

#ifdef __MULLE_OBJC__
   // check that no classes are "stuck"
   if( mulle_objc_global_check_universe( __MULLE_OBJC_UNIVERSENAME__) !=
         mulle_objc_universe_is_ok)
      _exit( 1);
#endif
   errors = 0;
EOF

   local test

   for test in "$@"
   do
      printf "   errors += run_test( ${test%%;*}, \"${test#*;}\");\n"
   done

   cat <<EOF

   mulle_testallocator_cancel();
   return( errors ? 1 : 0);
}
EOF
}


emit_method_test_footer()
{
   log_entry "emit_method_test_footer" "$@"

   local functionname="$1"

   cat <<EOF
int   main( int argc, char *argv[])
{
   int   rval;

   rval = ${functionname}();
   return( rval);
}
EOF
}



#
# the noleak test is special, its only emitted if nothing else
# is emitted. It's also not enveloped by the run_test loop
#
emit_noleak_test()
{
   log_entry "emit_noleak_test" "$@"

   local classname="$1"

   [ -z "${classname}" ] && internal_fail "classname is empty"

   local lf='\n'

#
# todo: could check for designated initializer (bits 0x30020) and
#       and use this instead of "new"
#
   cat <<EOF
//
// noleak checks for alloc/dealloc/finalize
// and also load/unload initialize/deinitialize
// if the test environment sets MULLE_OBJC_PEDANTIC_EXIT
//
static void   test_noleak( void)
{
   ${classname}  *obj;

   @autoreleasepool
   {
      @try
      {
         obj = [[${classname} new] autorelease];
         if( ! obj)
         {
            fprintf( stderr, "failed to allocate${lf}");
            _exit( 1);
         }
      }
      @catch( NSException *localException)
      {
         fprintf( stderr, "Threw a %s exception${lf}", [[localException name] UTF8String]);
         _exit( 1);
      }
   }
}


EOF
}


r_emit_param_definition()
{
   log_entry "r_emit_param_definition" "$@"

   local values="$1"
   local n="$2"
   local type="$3"
   local indent="$4"


   printf "%s%s params_%s[] =\n%s{" "${indent}" "${type}" "${n}" "${indent}"

   local prefix

   prefix=""

   local m
   local value

   m=0

   .foreachline value in ${values}
   .do
      printf "%s\n%s   %s" "${prefix}" "${indent}" "${value}"

      prefix=","
      m=$((m + 1))
   .done

   printf "\n%s};\n" "${indent}"

   RVAL="${m}"
}


emit_counter_definitions()
{
   log_entry "emit_counter_definitions" "$@"

   local n="$1"
   local type="$2"
   local indent="$3"

   printf "${indent}unsigned int   i_$n;\n"
   printf "${indent}unsigned int   n_$n = sizeof( params_$n) / sizeof( $type);\n"
}


#
#
#
testgen_collect_parameters()
{
   log_entry "testgen_collect_parameters" "$@"

   local selectorparse="$1"
   local typeparse="$2"
   local classname="$3"
   local indent="$4"

   local fragment
   local type
   local functionname
   local value
   local n

   case "${selectorparse}" in
      *:)
      ;;

      *)
         RVAL=0
         return
      ;;
   esac

   local memo_selector
   local memo_type

   memo_selector="${selectorparse}"
   memo_type="${typeparse}"

   n=0
   while [ ! -z "${selectorparse}" ]
   do
      fragment="${selectorparse%%:*}"
      selectorparse="${selectorparse#*:}"

      type="${typeparse%%,*}"
      typeparse="${typeparse#*,}"

      if [ "${MULLE_FLAG_LOG_SETTINGS}" = 'YES' ]
      then
         log_setting "fragment      = \"${fragment}\""
         log_setting "selectorparse = \"${selectorparse}\""
         log_setting "type          = \"${type}\""
         log_setting "typeparse     = \"${typeparse}\""
      fi

      while r_plugin_recode_functionname_for_type "${type}"
      do
         functionname="${RVAL}"

         if ! shell_is_function "${functionname}"
         then
            log_debug "${functionname} is not defined"
            break
         fi
         if ! "${functionname}" "${type}" \
                                "${fragment}" \
                                "${classname}" \
                                "${memo_selector}" \
                                "${memo_type}" \
                                "${n}"
         then
            log_debug "${functionname} can not recode ${type}"
            break
         fi
         if [ "${RVAL}" = "${type}" ]
         then
            internal_fail "${functionname} returned same value for ${type}"
         fi
         type="${RVAL}"
      done

      n=$((n + 1))

      values="0"
      if r_plugin_values_functionname_for_type "${type}"
      then
         functionname="${RVAL}"
         if shell_is_function "${functionname}"
         then
            values="`"${functionname}" "${type}" \
                                       "${fragment}" \
                                       "${classname}"\
                                       "${memo_selector}" \
                                       "${memo_type}" \
                                       "${n}" `"
            rval=$?
            case $rval in
               0)
                  if [ -z "${values}" ]
                  then
                     internal_fail "\"${functionname}\" returned nothing"
                  fi

                  r_emit_param_definition "${values}" "${n}" "${type}" "${indent}"
                  emit_counter_definitions "${n}" "${type}" "${indent}"
               ;;

               1)
                  r_emit_param_definition "0" "${n}" "${type}" "${indent}"
                  emit_counter_definitions "${n}" "${type}" "${indent}"
               ;;

               2)
                  sed -e "s/^/${indent}/" <<< "${values}"
               ;;
            esac
         else
            log_warning "Type \"${type}\" is not supported by a plugin \
(${functionname} is missing)"
            r_emit_param_definition "0" "${n}" "${type}" "${indent}"
            emit_counter_definitions "${n}" "${type}" "${indent}"
         fi
      fi
   done

   RVAL="$n"
}



_emit_method_test_prelude()
{
   log_entry "_emit_method_test_prelude" "$@"

   local classname="$1"
   local classname_pointer="$2"
   local name="$3"
   local typeparse="$4"
   local functionname="$5"
   local returntype="$6"
   local isclassmethod="$7"
   local family="$8"

   local obj
   local n

   cat <<EOF
static int   ${functionname}( void)
{
EOF
   indent="   "

   if [ "${isclassmethod}" = 'YES' ]
   then
      obj="${classname}"
   else
      printf "%s%sobj;\n" "${indent}" "${classname_pointer}"
      obj="obj"
   fi

   if [ "${returntype}" != "void" -a "${family}" != '3' ] # init
   then
      case "${returntype}" in
         *\*)
            printf "%s%svalue;\n" "${indent}" "${returntype}"
         ;;

         *)
            printf "%s%s value;\n" "${indent}" "${returntype}"
         ;;
      esac
   fi

   #
   # generate test functions
   #

   testgen_collect_parameters "${name}" \
                              "${typeparse}" \
                              "${classname}" \
                              "${indent}"
   n=${RVAL:-0}

   # emit parameter arrays

   printf "\n"

   i=1
   while [ $i -le $n ]
   do
      printf "%sfor( i_$i = 0; i_$i < n_$i; i_$i++)\n" "${indent}"
      indent="${indent}   "
      i=$(( i + 1))
   done

   if [ $n -ne 0 ]
   then
      printf "%s{\n" "${indent#   }"
   fi

   cat <<EOF
${indent}@try
${indent}{
EOF
   indent="${indent}   "
   if [ "${isclassmethod}" = 'NO' -a "${family}" != 3 ]
   then
      printf "${indent}obj = [[[${classname} alloc] init] autorelease];\n"
   fi

   RVAL="${obj};${indent};${n}"
}


testgen_emit_methodcall()
{
   log_entry "testgen_emit_methodcall" "$@"

   local obj="$1"
   local selectorparse="$2"
   local returntype="$3"
   local classname="$4"
   local isclassmethod="$5"
   local family="$6"
   local indent="$7"

   if [ "${returntype}" = "void" ]
   then
      printf "${indent}[${obj}"
   else
      case "${family}" in
         3)
            printf "${indent}${obj} = [[[${classname} alloc]"
         ;;

         1|2|4|5)
            printf "${indent}value = [[${obj}"
         ;;

         *)
            printf "${indent}value = [${obj}"
         ;;
      esac
   fi

   case "${selectorparse}" in
      *:)
      ;;

      *)
         case "${family}" in
            1|2|3|4|5)
               printf " %s] autorelease];\n" "${selectorparse}"
            ;;

            *)
               printf " %s];\n" "${selectorparse}"
            ;;
         esac
         return 0
      ;;
   esac

   local i
   local delim

   delim=" "
   indent="${indent}   "

   i=1
   while [ ! -z "${selectorparse}" ]
   do
      fragment="${selectorparse%%:*}"
      selectorparse="${selectorparse#*:}"

      printf "%s%s:params_%s[ i_%s]" "${delim}" "${fragment}" "$i" "$i"
      printf -v delim "\n%s          " "${indent}"  # fudged

      i=$((i + 1))
   done

   case "${family}" in
      1|2|3|4|5)
         printf "] autorelease"
      ;;
   esac

   printf "];\n"
}


testgen_emit_printer()
{
   log_entry "testgen_emit_printer" "$@"

   local type="$1"
   local name="$2"
   local family="$3"
   local indent="$4"

   local functionname
   local valuename

   valuename="value"
   if [ "${family}" = "3" ] # init
   then
      valuename="obj"
   fi

   r_plugin_printer_functionname_for_type "${type}"
   functionname="${RVAL}"

   if [ -z "${functionname}" ] || ! shell_is_function "${functionname}" ]
   then
      printf "${indent}// no plugin printer found for ${type}\n"
      printf "${indent}printf( \"${valuename} is%s0\\n\", ! ${valuename} ? \" \" : \" not \");\n"
      return
   fi

   if ! "${functionname}" "${valuename}" \
                          "${name}" \
                          "${indent}"
   then
      printf "${indent}// plugin printer didnt handle ${type}\n"
      printf "${indent}printf( \"${valuename} is%s0\\n\", ! ${valuename} ? \" \" : \" not \");\n"
      return
   fi
}


_emit_method_test_coda()
{
   log_entry "_emit_method_test_coda" "$@"

   local n="$1"
   local indent="$2"

   indent="${indent#   }"

   local lf='\\\\n'

   cat <<EOF
${indent}}
${indent}@catch( NSException *localException)
${indent}{
${indent}   printf( "Threw a %s exception\n", [[localException name] UTF8String]);
${indent}}
EOF

   if [ $n -ne 0 ]
   then
      indent="${indent#   }"
      printf "%s}\n" "${indent}"
   fi

   printf "   return( 0);\n"
   printf "}\n\n\n"
}


_emit_method_test()
{
   log_entry "_emit_method_test" "$@"

   local classname="$1"
   local name="$2"
   local signature="$3"
   local identifier="$4"
   local functionname="$5"
   local isclassmethod="$6"
   local family="$7"

   # typical signature
   # 'id,NSArray *,SEL,NSArray *;
   # must have at least three entries

   case "${signature}" in
      *\,*\,*)
      ;;

      *)
         internal_fail "Broken signature \"${signature}\". Expected at least \
three comma-separated values"
      ;;
   esac

   if [ "${MULLE_FLAG_LOG_SETTINGS}" = 'YES' ]
   then
      log_setting "classname  = \"${classname}\""
   fi

   local typeparse
   local indent

   typeparse="${signature}"
   returntype="${typeparse%%,*}"
   typeparse="${typeparse#*,}"

   classname_pointer="${typeparse%%,*}"
   typeparse="${typeparse#*,}"

   # skip _cmd
   typeparse="${typeparse#*,}"

   if [ "${MULLE_FLAG_LOG_SETTINGS}" = 'YES' ]
   then
      log_setting "classname_pointer = \"${classname_pointer}\""
      log_setting "returntype = \"${returntype}\""
      log_setting "typeparse  = \"${typeparse}\""
   fi

   local plugin_functionname

   if r_plugin_test_functionname_for_method "${name}"
   then
      plugin_functionname="${RVAL}"

      if shell_is_function "${plugin_functionname}"
      then
         log_debug "Executing plugin function \"${plugin_functionname}\""
         "${plugin_functionname}" "${classname}" \
                                  "${classname_pointer}" \
                                  "${name}" \
                                  "${typeparse}" \
                                  "${functionname}" \
                                  "${returntype}" \
                                  "${isclassmethod}" \
                                  "${family}"
         return $?
      else
         log_debug "${plugin_functionname} is not defined"
      fi
   fi

   #
   # TODO: brauche eine andere testart fuer init Methoden, weil da der "value"
   # sofort released werden muss und das obj dafür nicht mehr.
   #
   # TODO:  sollte co-dependent parameters wie ...objects:count: rausfinden
   #        und die gesondert behandeln... irgendwie...
   #
   local obj
   local n

   _emit_method_test_prelude "${classname}" \
                             "${classname_pointer}" \
                             "${name}" \
                             "${typeparse}" \
                             "${functionname}" \
                             "${returntype}" \
                             "${isclassmethod}" \
                             "${family}"
   obj="${RVAL%%;*}"
   RVAL="${RVAL#*;}"
   indent="${RVAL%%;*}"
   RVAL="${RVAL#*;}"
   n="${RVAL%%;*}"

   testgen_emit_methodcall "${obj}" \
                           "${name}" \
                           "${returntype}" \
                           "${classname}" \
                           "${isclassmethod}" \
                           "${family}" \
                           "${indent}"

   if [ "${returntype}" = "void" ]
   then
      # assume obj was mutated so print it
      testgen_emit_printer "${classname_pointer}" "" "3" "${indent}"
   else
      testgen_emit_printer "${returntype}" "${name}" "${family}" "${indent}"
   fi

   _emit_method_test_coda "${n}" "${indent}"

   return 0
}


create_method_test_file()
{
   log_entry "create_method_test_file" "$@"

   local classname="$1"
   local name="$2"
   local signature="$3"
   local identifier="$4"
   local functionname="$5"
   local isclassmethod="$6"
   local family="$7"

   local text
   local filename
   local ignorefilename
   local fname
   local hash

   if [ "${isclassmethod}" = 'YES' ]
   then
      fname="c_"
   else
      fname="i_"
   fi

   if [ "${#identifier}" -lt 32 ]
   then
      fname="${fname}${identifier}.m"
   else
      hash="`"${MULLE_OBJC_UNIQUEID}" "${name:1}"`"
      fname="${fname}${identifier:0:32}-${hash}.m"
   fi

   if [ ! -z "${OPTION_TEST_DIR}" ]
   then
      if [ "${OPTION_SUBDIR_PER_CLASS}" = 'YES' ]
      then
         filename="${OPTION_TEST_DIR}/${classname}/${fname}"
         ignorefilename="${OPTION_TEST_DIR}/${classname}/.${fname}"
      else
         filename="${OPTION_TEST_DIR}/${classname}-${fname}"
         ignorefilename="${OPTION_TEST_DIR}/.${classname}-${fname}"
      fi
   fi

   if [ "${MULLE_FLAG_LOG_SETTINGS}" = 'YES' ]
   then
      log_setting "name           : ${name}"
      log_setting "fname          : ${fname}"
      log_setting "filename       : ${filename}"
      log_setting "ignorefilename : ${ignorefilename}"
   fi

   if [ "${MULLE_FLAG_MAGNUM_FORCE}" = 'NO' ]
   then
      if [ -f "${filename}" ]
      then
         log_verbose "\"${fname}\" already exists at \"${filename}\""
         return
      fi
   fi

   if [ -f "${ignorefilename}" ]
   then
      log_verbose "\"${fname}\" set to ignore by \"${ignorefilename}\""
      return
   fi


   if text="`_emit_method_test "${classname}" \
                               "${name:1}" \
                               "${signature}" \
                               "${identifier}"\
                               "${functionname}" \
                               "${isclassmethod}" \
                               "${family}"`"
   then
      text="`emit_test_header "${classname}"`


${text}


`emit_method_test_footer "${functionname}"`"

      if [ "${filename}" ]
      then
         log_info "${filename}"
         r_mkdir_parent_if_missing "${filename}"

         log_debug "Write \"${filename}\""
         redirect_exekutor "${filename}" printf "%s\n" "${text}"
      else
         printf "%s\n" "${text}"
      fi
   else
      log_verbose "No test for method ${functionname} generated"
   fi
}


emit_method_test()
{
   log_entry "emit_method_test" "$@"

   local classname="$1"
   local name="$2"
   local signature="$3"
   local family="$4"

   [ -z "${classname}" ]    && internal_fail "classname is empty"
   [ -z "${name}" ]         && internal_fail "name is empty"
   [ -z "${signature}" ]    && internal_fail "signature is empty"
   [ -z "${family}" ]       && internal_fail "family is empty"

   local identifier

   if [ -z "${MULLE_CASE_SH}" ]
   then
      # shellcheck source=mulle-case.sh
      . "${MULLE_BASHFUNCTIONS_LIBEXEC_DIR}/mulle-case.sh" || return 1
   fi

   r_tweaked_de_camel_case "${name:1}"
   identifier="`tr "A-Z:" "a-z_" <<< "${RVAL}"`"

   local functionname
   local isclassmethod

   case "${name}" in
      ?_*)
         log_debug "Ignore methods prefixed with an underscore"
         return 0
      ;;

      -retain|-release|-autorelease|-dealloc|-finalize)
         log_debug "Ignore low level instance methods"
         return 0
      ;;

      +load|+initialize|+unload|+dependencies|+deinitialize)
         log_debug "Ignore low level class methods"
         return 0
      ;;

      \+*)
         functionname="test_c_${identifier}"
         isclassmethod='YES'
      ;;

      \-*)
         functionname="test_i_${identifier}"
         isclassmethod='NO'
      ;;

      *)
         fail "Unknown method format \"${method}\" (need -/+ prefix)"
      ;;
   esac

   if [ "${OPTION_ONE_FILE_PER_METHOD}" = 'NO' ]
   then
      _emit_method_test "${classname}" \
                        "${name:1}" \
                        "${signature}" \
                        "${identifier}"\
                        "${functionname}" \
                        "${isclassmethod}" \
                        "${family}" || return 1

      r_add_line "${TEST_FUNCTIONS}" "${functionname};${name}"
      TEST_FUNCTIONS="${RVAL}"
      return
   fi

   create_method_test_file "${classname}" \
                           "${name}" \
                           "${signature}" \
                           "${identifier}"\
                           "${functionname}" \
                           "${isclassmethod}" \
                           "${family}"
}


emit_method_tests()
{
   log_entry "emit_method_tests" "$@"

   local classname="$1"
   local classid="$2"
   local library="$3"
   local filtermethodid="$4"
   local emitinit="$5"

   local classid
   local classname
   local categoryid
   local categoryname
   local methodid
   local name
   local signature
   local variadic
   local bits
   local i

   local cmdline

   local cmdline="'${MULLE_OBJC_LISTA}' -a -f '${filterclassid}'"
   if [ ! -z "${filtermethodid}" ]
   then
      cmdline="${cmdline} -M ${filtermethodid}"
   fi
   cmdline="${cmdline} -m '${library}'"

   i=0
   while IFS=";" read -r m_classid \
                         m_classname \
                         m_categoryid \
                         m_categoryname \
                         m_methodid \
                         m_name \
                         m_variadic \
                         m_bits \
                         m_signature
   do
      if [ "${MULLE_FLAG_LOG_SETTINGS}" = 'YES' ]
      then
         log_setting "class-id:           ${m_classid}"
         log_setting "class-name:         ${m_classname}"
         log_setting "category-id:        ${m_categoryid}"
         log_setting "category-name:      ${m_categoryname}"
         log_setting "method-id:          ${m_methodid}"
         log_setting "method-name:        ${m_name}"
         log_setting "method-signature:   ${m_signature}"
         log_setting "method-variadic:    ${m_variadic}"
         log_setting "method-bits:        ${m_bits}"
      fi

      # check for 0x3nnnn
      local m_family

      m_family="${m_bits#0x}"
      m_family="${m_family%????}"

      #  1 alloc
      #  2 copy
      #  3 init
      #  4 mutableCopy
      #  5 new
      #  6 autorelease
      #  7 dealloc
      #  8 finalize
      #  9 release
      # 10 retain
      # 11 retainCount
      # 12 self
      # 13 initialize
      # 14 performSelector

      if [ "${m_family}" = "3" ]
      then
         if [ "${emitinit}" = 'YES' ]
         then
            if emit_method_test "${m_classname}" "${m_name}" "${m_signature}" "${m_family}"
            then
               i=$((i + 1))
            fi
         fi
      else
         if [ "${emitinit}" != 'YES' ]
         then
            if emit_method_test "${m_classname}" "${m_name}" "${m_signature}" "${m_family}"
            then
               i=$((i + 1))
            fi
         fi
      fi
   done < <( eval_rexekutor "${cmdline}" )

   if [ ${i} -eq 0 ]
   then
      if [ "${emitinit}" = 'YES' ]
      then
         log_warning "${classname} has no init methods"
      else
         log_warning "${classname} has no methods"
      fi
   fi
}


#
#
#
emit_property_test()
{
   log_entry "emit_property_test" "$@"

   local classname="$1"
   local name="$2"
   local signature="$3"

   [ -z "${classname}" ] && internal_fail "classname is empty"
   [ -z "${name}" ] && internal_fail "name is empty"
   [ -z "${signature}" ] && internal_fail "signature is empty"

   local getter
   local gettertypes
   local setter
   local settertypes
   local capitalized
   local type

   type=
   capitalized="$(tr '[:lower:]' '[:upper:]' <<< "${name:0:1}")${name:1}"
   case ",${signature}," in
      *,G*,*)
         getter="`sed 's/^.*,G\([^,]*\),.*$/\1/' <<< ",${signature}," `"
      ;;

      *)
         getter="get${capitalized}"
      ;;
   esac
   gettertypes="${signature%%,*},${classname},SEL"

   case ",${signature}," in
      *,S*,*)
         setter="`sed 's/^.*,S\([^,]*\),.*$/\1/' <<< ",${signature}," `"
      ;;

      *)
         setter="set${capitalized}:"
      ;;
   esac
   settertypes="void,${classname},SEL,${signature%%,*}"

   # todo: use setter before getter
   emit_method_test "${classname}" "-${getter}" "${gettertypes}" &&
   emit_method_test "${classname}" "-${setter}" "${settertypes}"
}


emit_property_tests()
{
   log_entry "emit_property_tests" "$@"

   local classname="$1"
   local classid="$2"
   local library="$3"
   local filtermethodid="$4"

   local p_classid
   local p_classname
   local p_id
   local p_name
   local p_signature
   local i

   i=0
   while IFS=";" read -r p_classid p_classname p_id p_name p_signature
   do
      if [ "${MULLE_FLAG_LOG_SETTINGS}" = 'YES' ]
      then
         log_setting "class-id:           ${p_classid}"
         log_setting "class-name:         ${p_classname}"
         log_setting "property-id:        ${p_id}"
         log_setting "property-name:      ${p_name}"
         log_setting "property-signature: ${p_signature}"
      fi
      i=$((i + 1))
      emit_property_test "${p_classname}" "${p_name}" "${p_signature}" || return 1
   done < <( rexekutor "${MULLE_OBJC_LISTA}" -a -f "${classid}" -p "${library}" )

   if [ ${i} -eq 0 ]
   then
      log_warning "${classname} has no properties"
   fi
}


emit_class_test()
{
   log_entry "emit_class_test" "$@"

   local classid="$1"
   local classname="$2"
   local library="$3"
   local libraryname="$4"
   local filtermethodid="$5"

   emit_test_header "${libraryname}" || return 1

   if [ "${OPTION_EMIT_PROPERTY_TESTS}" = 'NO' -a \
        "${OPTION_EMIT_METHOD_TESTS}" = 'NO' -a \
        "${OPTION_EMIT_INIT_METHOD_TESTS}" = 'NO' ]
   then
      emit_noleak_test "${classname}" || return 1
      emit_noleak_test_footer || return 1
   else
      local TEST_FUNCTIONS

      TEST_FUNCTIONS=""
      if [ "${OPTION_EMIT_PROPERTY_TESTS}" = 'YES' ]
      then
         emit_property_tests "${classname}" "${classid}" "${library}" "${filtermethodid}" || return 1
      fi
      if [ "${OPTION_EMIT_METHOD_TESTS}" = 'YES' ]
      then
         emit_method_tests "${classname}" "${classid}" "${library}" "${filtermethodid}" 'NO' || return 1
      fi
      if [ "${OPTION_EMIT_INIT_METHOD_TESTS}" = 'YES' ]
      then
         emit_method_tests "${classname}" "${classid}" "${library}" "${filtermethodid}" 'YES' || return 1
      fi
      emit_class_test_footer ${TEST_FUNCTIONS} || return 1
   fi
}


generate_class_test()
{
   log_entry "generate_class_test" "$@"

   local classid="$1"
   local classname="$2"
   local library="$3"
   local libraryname="$4"
   local filtermethodid="$5"

   [ -z "${classid}" ]     && internal_fail "classid is empty"
   [ -z "${classname}" ]   && internal_fail "classname is empty"
   [ -z "${library}" ]     && internal_fail "library is empty"
   [ -z "${libraryname}" ] && internal_fail "libraryname is empty"

   local text
   local filename
   local ignorefilename
   local fname

   if [ "${OPTION_SUBDIR_PER_CLASS}" = 'YES' ]
   then
      fname="${classname}/test.m"
   else
      fname="test-${classname}.m"
   fi
   filename="${OPTION_TEST_DIR}/${fname}"
   ignorefilename="${OPTION_TEST_DIR}/.${fname}"

   if [ "${MULLE_FLAG_MAGNUM_FORCE}" = 'NO' ]
   then
      if [ -f "${filename}" ]
      then
         log_verbose "\"${fname}\" already exists at \"${filename}\""
         return
      fi
   fi

   if [ -f "${ignorefilename}" ]
   then
      log_verbose "\"${fname}\" set to ignore by \"${ignorefilename}\""
      return
   fi

   if text="`emit_class_test "${classid}" "${classname}" "${library}" "${libraryname}" "${filtermethodid}" `"
   then
      log_info "${filename}"
      r_mkdir_parent_if_missing "${filename}"

      log_debug "Write \"${filename}\""
      redirect_exekutor "${filename}" printf "%s\n" "${text}"
   else
      if [ "${OPTION_ONE_FILE_PER_METHOD}" != 'YES' ]
      then
         log_verbose "No test for class ${classname} generated"
      fi
   fi
}


generate_class_tests_from_csv()
{
   log_entry "generate_class_tests_from_csv" "$@"

   local library="$1"
   local libraryname="$2"
   local filtermethodid="$3"
   local lines="$4"

   local c_classname
   local c_classid
   local c_superid
   local c_superclassname

   while IFS=";" read -r c_classid c_classname c_superid c_superclassname
   do
      if [ "${MULLE_FLAG_LOG_SETTINGS}" = 'YES' ]
      then
         log_setting "class-id:        ${c_classid}"
         log_setting "class-name:      ${c_classname}"
         log_setting "superclass-id:   ${c_superid}"
         log_setting "superclass-name: ${c_superclassname}"
      fi

      case "${c_classname}" in
         "")
            continue
         ;;

         ${OPTION_CLASS_PREFIX}*)
         ;;

         *)
            log_fluff "Ignore non \"${OPTION_CLASS_PREFIX}\" prefixed class \"${c_classname}\""
            continue
         ;;
      esac

      if [ -z "${c_superclassname}" ]
      then
         log_fluff "Ignore '_' root class \"${c_classname}\""
         continue
      fi

      generate_class_test "${c_classid}" "${c_classname}" "${library}" "${libraryname}" "${filtermethodid}" & # || fail "failed to generate test for \"${c_classname}\""
   done < <( printf "%s\n" "${lines}")

   wait
}


generate_class_tests()
{
   log_entry "generate_class_tests" "$@"

   local library="$1"
   local libraryname="$2"
   local filterclassid="$3"
   local filtermethodid="$4"

   local lines
   local cmdline="'${MULLE_OBJC_LISTA}'"

   if [ ! -z "${filterclassid}" ]
   then
      cmdline="${cmdline} -a -f '${filterclassid}'"
   fi

   cmdline="${cmdline} -C '${library}'"

   lines="`eval_rexekutor "${cmdline}" `" || fail "mulle-objc-lista failed"
   if [ -z "${lines}" ]
   then
      log_info "No classes found in \"${library}\""
      return
   fi

   generate_class_tests_from_csv "${library}" "${libraryname}" "${filtermethodid}" "${lines}"
}


testgen_environment()
{
   log_entry "testgen_environment" "$@"

   # shellcheck source=src/mulle-fetch-commands.sh
   . "${MULLE_TESTGEN_LIBEXEC_DIR}/mulle-testgen-plugin.sh"

   testgen_plugin_load_all_types
   testgen_plugin_load_all_methods

   # prefer sibling mulle-objc-lista
   if [ -z "${MULLE_OBJC_LISTA}" ]
   then
      MULLE_OBJC_LISTA="${0%/*}/mulle-objc-lista"
      if [ ! -x "${MULLE_OBJC_LISTA}" ]
      then
         MULLE_OBJC_LISTA="`command -v mulle-objc-lista`"
         [ -z "${MULLE_OBJC_LISTA}" ] && fail "mulle-objc-lista not in PATH"
      fi
   fi

   if [ -z "${MULLE_OBJC_UNIQUEID}" ]
   then
      MULLE_OBJC_UNIQUEID="${0%/*}/mulle-objc-uniqueid"
      if [ ! -x "${MULLE_OBJC_UNIQUEID}" ]
      then
         MULLE_OBJC_UNIQUEID="`command -v mulle-objc-uniqueid`"
         [ -z "${MULLE_OBJC_UNIQUEID}" ] && fail "mulle-objc-unique not in PATH"
      fi
   fi
}



testgen_class_main()
{
   log_entry "testgen_class_main" "$@"

   testgen_environment

   emit_noleak_test "$@"
}



testgen_method_main()
{
   log_entry "testgen_method_main" "$@"

   testgen_environment

   emit_method_test "$@"
}



testgen_property_main()
{
   log_entry "testgen_property_main" "$@"

   testgen_environment

   emit_property_test "$@"
}


testgen_generate_main()
{
   log_entry "testgen_generate_main" "$@"

   local library

   local OPTION_CLASS_NAME
   local OPTION_METHOD_NAME
   local OPTION_EMIT_INIT_METHOD_TESTS='NO'
   local OPTION_EMIT_METHOD_TESTS='NO'
   local OPTION_EMIT_PROPERTY_TESTS='NO'
   local OPTION_SUBDIR_PER_CLASS='YES'
   local OPTION_LIBRARY_NAME
   local OPTION_TEST_DIR="test/10_generated"
   local OPTION_CLASS_PREFIX='[A-Z]'
   local OPTION_EXIT_ON_ERROR='NO'
   local OPTION_ONE_FILE_PER_METHOD='NO'

   #
   # simple option handling
   #
   while [ $# -ne 0 ]
   do
      case "$1" in
         -h*|--help|help)
            testgen_generate_usage
         ;;

         -C|--class-name|--classname)
            shift
            OPTION_CLASS_NAME="$1"
         ;;

         -M|--method-name|--methodname)
            shift
            OPTION_METHOD_NAME="$1"
         ;;

         -e|--exit-on-errror)
            OPTION_EXIT_ON_ERROR='YES'
         ;;

         -d|--test-dir)
            shift
            OPTION_TEST_DIR="$1"
         ;;

         -i|--emit-init-tests)
            OPTION_EMIT_INIT_METHOD_TESTS='YES'
         ;;

         -l|--library-name)
            shift
            OPTION_LIBRARY_NAME="$1"
         ;;

         -P|--class-prefix)
            shift
            OPTION_CLASS_PREFIX="$1"
         ;;

         -p|--emit-property-tests)
            OPTION_EMIT_PROPERTY_TESTS='YES'
         ;;

         -m|--emit-method-tests)
            OPTION_EMIT_METHOD_TESTS='YES'
         ;;

         -0|--no-subdir-per-class)
            shift
            OPTION_SUBDIR_PER_CLASS='NO'
         ;;

         -1|--one-file-per-method)
            OPTION_ONE_FILE_PER_METHOD='YES'
         ;;

         --version)
            printf "%s\n" "${MULLE_EXECUTABLE_VERSION}"
            exit 0
         ;;

         -*)
            testgen_generate_usage "Unknown option \"$1\""
         ;;

         *)
            break
         ;;
      esac

      shift
   done

   testgen_environment

   if [ $# -ne 0 ]
   then
      library="$1"
      shift
   fi

   if [ -z "${library}" ]
   then
      library="${PROJECT_NAME}"
      if [ -z "${library}" ]
      then
         r_basename "${MULLE_USER_PWD}"
         library="${RVAL}"
      fi
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

      local check
      local searched

      KITCHEN_DIR="${KITCHEN_DIR:-kitchen}"

      check="${KITCHEN_DIR}/Debug/${library}"
      log_fluff "Looking for \"${check}\""

      if [ ! -f "${check}" ]
      then
         searched="${check#${MULLE_USER_PWD}/}"
         check="${KITCHEN_DIR}/Release/${library}"
         log_fluff "Looking for \"${check}\""
         if [ ! -f "${check}" ]
         then
            searched="${searched}:${check#${MULLE_USER_PWD}/}"
            check="${KITCHEN_DIR}/${library}"
            log_fluff "Looking for \"${check}\""
            if [ ! -f "${check}" ]
            then
               searched="${searched}:${check#${MULLE_USER_PWD}/}"
               check="dependency/lib/${library}"
               log_fluff "Looking for \"${check}\""
               if [ ! -f "${check}" ]
               then
                  searched="${searched}:${check#${MULLE_USER_PWD}/}"
                  fail "Could not find a \"${library}\" static library in \"$searched\""
               fi
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

   local filterclassid
   local filtermethodid

   if [ ! -z "${OPTION_CLASS_NAME}" ]
   then
      filterclassid="`rexekutor "${MULLE_OBJC_UNIQUEID}" "${OPTION_CLASS_NAME}" `" || exit 1
   fi

   if [ ! -z "${OPTION_METHOD_NAME}" ]
   then
      filtermethodid="`rexekutor "${MULLE_OBJC_UNIQUEID}" "${OPTION_METHOD_NAME}" `" || exit 1
   fi

   generate_class_tests "${library}" "${libraryname}" "${filterclassid}" "${filtermethodid}"
}
