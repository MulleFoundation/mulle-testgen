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
MULLE_TESTGEN_PLUGIN_SH="included"


testgen_plugin_usage()
{
   [ "$#" -ne 0 ] && log_error "$1"

   cat <<EOF >&2
Usage:
   ${MULLE_USAGE_NAME} plugin <command>

   Manage the type and method plugins for mulle-testgen.
   A type plugin emits a number of values to be used as input for methods.
   A method plugin emits a complete test for a specified selector.

Commands:
   type-list                : list available type plugins
   type-filename <type>     : output plugin filename path for type
   type-functionname <type> : output bash functionname for type
   method-list              : list available method plugins
   method-filename <m>      : output plugin filename path for method
   method-functionname <m>  : output bash functionname for method
EOF

   exit 1
}



testgen_plugin_list_in_dir()
{
   log_entry "testgen_plugin_list_in_dir"

   local directory="$1"

   IFS=$'\n'
   for pluginpath in `ls -1 "${directory}/"*.sh`
   do
      basename -- "${pluginpath}" .sh
   done

   IFS="${DEFAULT_IFS}"
}


testgen_plugin_list()
{
   log_entry "testgen_plugin_list"

   local subdir="${1:-type}"

   local directory

   [ -z "${DEFAULT_IFS}" ] && internal_fail "DEFAULT_IFS not set"
   [ -z "${MULLE_TESTGEN_LIBEXEC_DIR}" ] && internal_fail "MULLE_TESTGEN_LIBEXEC_DIR not set"

   log_info "${type} plugins"

   (
      local directory

      IFS=":"
      for directory in ${MULLE_TESTGEN_PLUGIN_PATH}
      do
         IFS="${DEFAULT_IFS}"

         testgen_plugin_list_in_dir "${directory}/${type}"
      done
   ) | sort
}


#
# TYPE
#

r_plugin_name_for_type()
{
   log_entry "r_plugin_name_for_type" "$@"

   local signature="$1"
   local suffix="$2"

   # remove trailing spaces
   signature="${signature%% }"

   case "${signature}" in
      "")
         return 1
      ;;

      *\*)
         is_pointer='YES'
         r_plugin_name_for_type "${signature%\*}" "_pointer${suffix}"
         return $?
      ;;

      @\".*\")
         RVAL="${signature#@\"}"
         RVAL="${RVAL%\"}"
         RVAL="${RVAL}${suffix}"
         RVAL="${RVAL// /_}"
         log_debug "name=${RVAL}"
         return 0
      ;;

      @)
         RVAL="id"
         log_debug "name=${RVAL}"
         return 0
      ;;

      struct*)
         RVAL="struct"
         log_debug "name=${RVAL}"
         return 0
      ;;

      *)
         RVAL="${signature}${suffix}"
         RVAL="`tr -C 'A-Za-z0-9-_' _ <<< "${RVAL}" `"
         RVAL="${RVAL%?}"  # remove encoded linefeed
         log_debug "name=${RVAL}"
         return 0
      ;;
   esac
}


r_plugin_recode_functionname_for_type()
{
   log_entry "r_plugin_recode_functionname_for_type" "$@"

   if r_plugin_name_for_type "$@"
   then
      RVAL="recode_${RVAL}_type"
      log_debug "type=${RVAL}"
      return 0
   fi

   return 1
}


r_plugin_values_functionname_for_type()
{
   log_entry "r_plugin_values_functionname_for_type" "$@"

   if r_plugin_name_for_type "$@"
   then
      RVAL="emit_${RVAL}_values"
      log_debug "functionname=${RVAL}"
      return 0
   fi
   return 1
}


r_plugin_printer_functionname_for_type()
{
   log_entry "r_plugin_printer_functionname_for_type"

   if r_plugin_name_for_type "$@"
   then
      RVAL="emit_${RVAL}_printer"
      log_debug "functionname=${RVAL}"
      return 0
   fi
   return 1
}


r_plugin_filename_for_type()
{
   log_entry "r_plugin_filename_for_type"

   if r_plugin_name_for_type "$@"
   then
      RVAL="${MULLE_TESTGEN_LIBEXEC_DIR}/plugins/type/${RVAL}.sh"
      log_debug "filename=${RVAL}"
      return 0
   fi
   return 1
}


testgen_plugin_load_type()
{
   log_entry "testgen_plugin_load_type"

   local pluginpath="$1"

   local name
   local functionname
   local functionname2

   r_extensionless_basename "${pluginpath}"
   name="${RVAL}"
   functionname="emit_${name//-/_}_values"
   functionname2="recode_${name//-/_}_type"

   if [ "`type -t "${functionname}"`" != "function" ] && \
      [ "`type -t "${functionname2}"`" != "function" ]
   then
      # shellcheck source=plugins/symlink.sh
      . "${pluginpath}"

      if [ "`type -t "${functionname}"`" != "function" ] && \
         [ "`type -t "${functionname2}"`" != "function" ]
      then
         fail "Type plugin \"${pluginpath}\" has no \"${functionname}\" \
or \"${functionname2}\" function"
      fi

      log_fluff "Type plugin \"${name}\" loaded"
   fi
}


testgen_plugin_load_types_in_dir()
{
   log_entry "testgen_plugin_load_types_in_dir"

   local directory="$1"

   local functionname
   local pluginpath
   local name

   log_fluff "Loading type plugins in \"${directory}\"..."

   IFS=$'\n'
   for pluginpath in `ls -1 "${directory}/"*.sh 2> /dev/null`
   do
      IFS="${DEFAULT_IFS}"

      testgen_plugin_load_type "${pluginpath}"
   done

   IFS="${DEFAULT_IFS}"
}


testgen_plugin_load_all_types()
{
   log_entry "testgen_plugin_load_all_types"

   local directory

   [ -z "${DEFAULT_IFS}" ] && internal_fail "DEFAULT_IFS not set"
   [ -z "${MULLE_TESTGEN_PLUGIN_PATH}" ] && internal_fail "MULLE_TESTGEN_LIBEXEC_DIR not set"

   log_fluff "Loading type plugins..."

   IFS=":"
   for directory in ${MULLE_TESTGEN_PLUGIN_PATH}
   do
      IFS="${DEFAULT_IFS}"

      testgen_plugin_load_types_in_dir "${directory}/type"
   done

   IFS="${DEFAULT_IFS}"
}


#
# METHOD
#

r_plugin_name_for_method()
{
   log_entry "r_plugin_name_for_method" "$@"

   RVAL="$1"
   case "${RVAL}" in
      +*)
         RVAL="cls_${RVAL:1}"
      ;;

      -*)
         RVAL="${RVAL:1}"
      ;;
   esac
   RVAL="`tr -C 'A-Za-z0-9-_' _ <<< "${RVAL}" `"
   RVAL="${RVAL%?}"  # remove encoded linefeed

   log_debug "name=${RVAL}"
   return 0
}



r_plugin_test_functionname_for_method()
{
   log_entry "r_plugin_test_functionname_for_method" "$@"

   if r_plugin_name_for_method "$@"
   then
      RVAL="emit_${RVAL}_test"
      log_debug "functionname=${RVAL}"
      return 0
   fi
   return 1
}


r_plugin_filename_for_method()
{
   log_entry "r_plugin_filename_for_method"

   if r_plugin_name_for_method "$@"
   then
      case "${RVAL}" in
         cls_*)
            RVAL="class/${RVAL:4}"
         ;;
      esac

      RVAL="${MULLE_TESTGEN_LIBEXEC_DIR}/plugins/method/${RVAL}.sh"
      log_debug "filename=${RVAL}"
      return 0
   fi
   return 1
}


testgen_plugin_load_method()
{
   log_entry "testgen_plugin_load_method"

   local pluginpath="$1"

   local name
   local functionname

   r_extensionless_basename "${pluginpath}"
   name="${RVAL}"
   functionname="emit_${name//-/_}_test"

   if [ "`type -t "${functionname}"`" != "function" ]
   then
      # shellcheck source=plugins/symlink.sh
      . "${pluginpath}"

      if [ "`type -t "${functionname}"`" != "function" ]
      then
         fail "Method plugin \"${pluginpath}\" has no \"${functionname}\" function"
      fi

      log_fluff "Method plugin \"${name}\" loaded"
   fi
}


testgen_plugin_load_methods_from_dir()
{
   log_entry "testgen_plugin_load_methods_from_dir"

   local directory="$1"
   local pluginpath

   IFS=$'\n'
   for pluginpath in `ls -1 "${directory}/"*.sh 2> /dev/null`
   do
      IFS="${DEFAULT_IFS}"

      testgen_plugin_load_method "${pluginpath}"
   done

   IFS="${DEFAULT_IFS}"
}


testgen_plugin_load_all_methods()
{
   log_entry "testgen_plugin_load_all_methods"

   local directory

   [ -z "${DEFAULT_IFS}" ] && internal_fail "DEFAULT_IFS not set"
   [ -z "${MULLE_TESTGEN_LIBEXEC_DIR}" ] && internal_fail "MULLE_TESTGEN_LIBEXEC_DIR not set"

   log_fluff "Loading method plugins..."

   IFS=":"
   for directory in ${MULLE_TESTGEN_PLUGIN_PATH}
   do
      IFS="${DEFAULT_IFS}"

      testgen_plugin_load_methods_from_dir "${directory}/method"
      testgen_plugin_load_methods_from_dir "${directory}/method/class"
   done

   IFS="${DEFAULT_IFS}"
}


testgen_plugin_main()
{
   log_entry "testgen_plugin_main" "$@"

   while [ $# -ne 0 ]
   do
      case "$1" in
         -h*|--help|help)
            testgen_plugin_usage
         ;;

         -*)
            testgen_plugin_usage "Unknown option \"$1\""
         ;;

         *)
            break
         ;;
      esac

      shift
   done

   [ $# -eq 0 ] && testgen_plugin_usage

   local cmd="$1"
   shift

   case "${cmd}" in
      type-list)
         [ $# -ne 0 ] && testgen_plugin_usage "superflous parameters"
         testgen_plugin_list "type"
      ;;

      method-list)
         [ $# -ne 0 ] && testgen_plugin_usage "superflous parameters"
         testgen_plugin_list "method"
      ;;

      type-filename|type-function)
         local typestring

         [ $# -eq 0 ] && testgen_plugin_usage "missing parameter"

         typestring="$1"; shift

         [ $# -ne 0 ] && testgen_plugin_usage "superflous parameters \"$*\""


         case "${cmd}" in
            *filename)
               r_plugin_filename_for_type "${typestring}"
            ;;

            *)
               r_plugin_values_functionname_for_type "${typestring}"
            ;;
         esac
         if [ $? -ne 0 ]
         then
            fail "Untranslatable type"
         fi
         echo "${RVAL}"
      ;;

      method-filename|method-function)
         local methodstring

         [ $# -eq 0 ] && testgen_plugin_usage "missing parameter"

         methodstring="$1"; shift

         [ $# -ne 0 ] && testgen_plugin_usage "superflous parameters \"$*\""


         case "${cmd}" in
            *filename)
               r_plugin_filename_for_method "${methodstring}"
            ;;

            *)
               r_plugin_test_functionname_for_method "${methodstring}"
            ;;
         esac

         if [ $? -ne 0 ]
         then
            fail "Untranslatable method"
         fi
         echo "${RVAL}"
      ;;

      "")
         testgen_plugin_usage
      ;;

      *)
         testgen_plugin_usage "Unknown command \"${cmd}\""
      ;;
   esac
}
