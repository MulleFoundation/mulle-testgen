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

   Manage the type plugins for mulle-testgen.
   A type plugin emits a number of values to be used as input for methods.

Commands:
   list                : list available plugins
   filename <type>     : output plugin filename path for type
   functionname <type> : output bash functionname for type
EOF

   exit 1
}


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
         return 0
      ;;

      @)
         RVAL="id"
         return 0
      ;;

      *)
         RVAL="${signature}${suffix}"
         RVAL="${RVAL// /_}"
         return 0
      ;;
   esac
}


r_plugin_values_functionname_for_type()
{
   log_entry "r_plugin_values_functionname_for_type"

   if r_plugin_name_for_type "$@"
   then
      RVAL="emit_${RVAL}_values"
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
      return 0
   fi
   return 1
}


r_plugin_filename_for_type()
{
   log_entry "r_plugin_filename_for_type"

   if r_plugin_name_for_type "$@"
   then
      RVAL="${MULLE_TESTGEN_LIBEXEC_DIR}/plugins/${RVAL}.sh"
      return 0
   fi
   return 1
}



testgen_plugin_all_names()
{
   log_entry "testgen_plugin_all_names"

   local upcase
   local plugindefine
   local pluginpath
   local name

   [ -z "${DEFAULT_IFS}" ] && internal_fail "DEFAULT_IFS not set"
   [ -z "${MULLE_TESTGEN_LIBEXEC_DIR}" ] && internal_fail "MULLE_TESTGEN_LIBEXEC_DIR not set"

   IFS=$'\n'
   for pluginpath in `ls -1 "${MULLE_TESTGEN_LIBEXEC_DIR}/plugins/"*.sh`
   do
      IFS="${DEFAULT_IFS}"

      name="`basename -- "${pluginpath}" .sh`"

      # don't load xcodebuild on non macos platforms
      case "${MULLE_UNAME}" in
         darwin)
         ;;

         *)
            case "${name}" in
               xcodebuild)
                  continue
               ;;
            esac
         ;;
      esac

      echo "${name}"
   done

   IFS="${DEFAULT_IFS}"
}


testgen_plugin_load()
{
   log_entry "testgen_plugin_load"

   local scm="$1"

   if [ ! -f "${MULLE_TESTGEN_LIBEXEC_DIR}/plugins/${scm}.sh" ]
   then
      fail "SCM \"${scm}\" is not supported (no plugin found)"
   fi

   # shellcheck source=plugins/symlink.sh
   . "${MULLE_TESTGEN_LIBEXEC_DIR}/plugins/${scm}.sh"
}


testgen_plugin_list()
{
   log_entry "testgen_plugin_list"

   local upcase
   local plugindefine
   local pluginpath
   local name

   [ -z "${DEFAULT_IFS}" ] && internal_fail "DEFAULT_IFS not set"
   [ -z "${MULLE_TESTGEN_LIBEXEC_DIR}" ] && internal_fail "MULLE_TESTGEN_LIBEXEC_DIR not set"

   log_info "Plugins"

   IFS=$'\n'
   for pluginpath in `ls -1 "${MULLE_TESTGEN_LIBEXEC_DIR}/plugins/"*.sh`
   do
      basename -- "${pluginpath}" .sh
   done

   IFS="${DEFAULT_IFS}"
}


testgen_plugin_load_all()
{
   log_entry "testgen_plugin_load_all"

   local functionname
   local pluginpath
   local name

   [ -z "${DEFAULT_IFS}" ] && internal_fail "DEFAULT_IFS not set"
   [ -z "${MULLE_TESTGEN_LIBEXEC_DIR}" ] && internal_fail "MULLE_TESTGEN_LIBEXEC_DIR not set"

   log_fluff "Loading type plugins..."

   IFS=$'\n'
   for pluginpath in `ls -1 "${MULLE_TESTGEN_LIBEXEC_DIR}/plugins/"*.sh`
   do
      IFS="${DEFAULT_IFS}"

      name="`basename -- "${pluginpath}" .sh`"
      functionname="emit_${name//-/_}_values"

      if [ "`type -t "${functionname}"`" != "function" ]
      then
         # shellcheck source=plugins/symlink.sh
         . "${pluginpath}"

         if [ "`type -t "${functionname}"`" != "function" ]
         then
            fail "Type plugin \"${pluginpath}\" has no \"${functionname}\" function"
         fi

         log_fluff "Type plugin \"${name}\" loaded"
      fi
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
      list)
         [ $# -ne 0 ] && testgen_plugin_usage "superflous parameters"
         testgen_plugin_list
      ;;

      filename|functionname)
         local typestring

         [ $# -eq 0 ] && testgen_plugin_usage "missing parameter"

         typestring="$1"; shift

         [ $# -ne 0 ] && testgen_plugin_usage "superflous parameters \"$*\""


         if [ "${cmd}" = "filename" ]
         then
            r_plugin_filename_for_type "${typestring}"
         else
            r_plugin_values_functionname_for_type "${typestring}"
         fi
         if [ $? -ne 0 ]
         then
            fail "Untranslatable type"
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
