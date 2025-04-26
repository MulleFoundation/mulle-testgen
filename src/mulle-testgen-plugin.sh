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
   method-filename <m>      : output plugin filename path for method
   method-list              : list available method plugins
   printer-functionname <t> : output bash functionname to print type
   recode-functionname <t>  : output bash functionname to recode type
   type-filename <type>     : output plugin filename path for type
   type-list                : list available type plugins
   values-functionname <t>  : output bash functionname to emit values for type
EOF

   exit 1
}



testgen_plugin_list_in_dir()
{
   log_entry "testgen_plugin_list_in_dir"

   local directory="$1"

   .foreachline pluginpath in $(dir_list_files "${directory}" "*.sh" "f")
   .do
      basename -- "${pluginpath}" .sh
   .done
}


testgen_plugin_list()
{
   log_entry "testgen_plugin_list"

   local subdir="${1:-type}"

   local directory

   [ -z "${MULLE_TESTGEN_LIBEXEC_DIR}" ] && internal_fail "MULLE_TESTGEN_LIBEXEC_DIR not set"

   log_info "${subdir} plugins"

   (
      .foreachpath directory in ${MULLE_TESTGEN_PLUGIN_PATH}
      .do
         if [ -d "${directory}/${subdir}" ]
         then
            testgen_plugin_list_in_dir "${directory}/${subdir}"
         fi
      .done
   ) | sort
}


#
# TYPE
#

r_plugin_fallback_for_type()
{
   log_entry "r_plugin_fallback_for_type" "$@"

   local signature="$1"

   # remove trailing spaces
   signature="${signature%% }"

   case "${signature}" in
      # TODO: walk up the inheritance chain ?
      *)
         RVAL="id"
         log_debug "name=${RVAL}"
         return 0
      ;;
   esac

   return 1
}


r_plugin_best_name_for_type()
{
   log_entry "r_plugin_best_name_for_type" "$@"

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
         r_plugin_best_name_for_type "${signature%\*}" "_pointer"
         return $?
      ;;

      @\".*\")
         RVAL="${signature#@\"}"
         RVAL="${RVAL%\"}"
         RVAL="${RVAL// /_}"
         RVAL="${RVAL}${suffix}"  # add _pointer
         log_debug "name=${RVAL}"
         return 2  # have fallback
      ;;

      @)
         RVAL="id"
         RVAL="${RVAL}${suffix}"  # add _pointer
         log_debug "name=${RVAL}"
         return 0
      ;;

      struct*)
         RVAL="struct"
         RVAL="${RVAL}${suffix}"  # add _pointer
         log_debug "name=${RVAL}"
         return 0
      ;;

      # looks like a class ? try fallback code
      [_A-Z][A-Z][A-Z]*)
         RVAL="${signature}"
         RVAL="`tr -C 'A-Za-z0-9-_' _ <<< "${RVAL}" `"
         RVAL="${RVAL%?}"  # remove encoded linefeed
         RVAL="${RVAL}${suffix}"  # add _pointer
         log_debug "name=${RVAL}"
         return 2
      ;;

      *)
         RVAL="${signature}"
         RVAL="`tr -C 'A-Za-z0-9-_' _ <<< "${RVAL}" `"
         RVAL="${RVAL%?}"  # remove encoded linefeed
         RVAL="${RVAL}${suffix}"  # add _pointer
         log_debug "name=${RVAL}"
         return 0
      ;;
   esac
}


#
# Not very beautiful hack. Basically what we need to do is to export
# the inheritance chain of the class from mulle-objc-lista and then search for
# plugin implementations i.e. NSMutableCharacterSet -> NSCharacterSet -> NSObject -> id
# mulle-objc-lista can't do this itself, because
#
# a) its just looking at one library (not all libraries)
# b) its just looking at the loadclass not the class hierarchy
#
r_plugin_find_functionname_for_type()
{
   log_entry "r_plugin_find_functionname_for_type" "$@"

   local type="$1"
   local prefix="$2"
   local suffix="$3"

   local functionname
   local fallbackfunctionname
   local rval

   r_plugin_best_name_for_type "${type}"
   rval=$?

   functionname="${prefix}${RVAL}${suffix}"

   if [ $rval -eq 2 ]
   then
      rval=0
      if ! shell_is_function "${functionname}"
      then
         if r_plugin_fallback_for_type "$@"
         then
            fallbackfunctionname="${prefix}${RVAL}${suffix}"
            if shell_is_function "${fallbackfunctionname}"
            then
               functionname="${fallbackfunctionname}"
            fi
         fi
      fi
   fi

   RVAL=
   if [ "${rval}" -eq 0 ]
   then
      RVAL="${functionname}"
   fi

   log_debug "functionname=${RVAL}"
   return $rval
}


r_plugin_recode_functionname_for_type()
{
   log_entry "r_plugin_recode_functionname_for_type" "$@"

   r_plugin_find_functionname_for_type "$1" "recode_" "_type"
}


r_plugin_values_functionname_for_type()
{
   log_entry "r_plugin_values_functionname_for_type" "$@"

   r_plugin_find_functionname_for_type "$1" "emit_" "_values"
}


r_plugin_printer_functionname_for_type()
{
   log_entry "r_plugin_printer_functionname_for_type" "$@"

   r_plugin_find_functionname_for_type "$1" "emit_" "_printer"
}


# unused coz we load all anyway
#r_plugin_filename_for_type()
#{
#   log_entry "r_plugin_filename_for_type"
#
#   if r_plugin_best_name_for_type "$@"
#   then
#      RVAL="${MULLE_TESTGEN_LIBEXEC_DIR}/plugins/type/${RVAL}.sh"
#      log_debug "filename=${RVAL}"
#      return 0
#   fi
#   return 1
#}


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

   if ! shell_is_function "${functionname}" && \
      ! shell_is_function "${functionname2}"
   then
      # shellcheck source=plugins/symlink.sh
      . "${pluginpath}"

      if ! shell_is_function "${functionname}" && \
         ! shell_is_function "${functionname2}"
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

   .foreachline pluginpath in $(dir_list_files "${directory}" "*.sh" "f")
   .do
      testgen_plugin_load_type "${pluginpath}"
   .done
}


testgen_plugin_load_all_types()
{
   log_entry "testgen_plugin_load_all_types"

   local directory

   [ -z "${MULLE_TESTGEN_PLUGIN_PATH}" ] && internal_fail "MULLE_TESTGEN_LIBEXEC_DIR not set"

   log_fluff "Loading type plugins..."

   .foreachpath directory in ${MULLE_TESTGEN_PLUGIN_PATH}
   .do
      if [ -d "${directory}/type" ]
      then
         testgen_plugin_load_types_in_dir "${directory}/type"
      fi
   .done
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

   if ! shell_is_function "${functionname}"
   then
      # shellcheck source=plugins/symlink.sh
      . "${pluginpath}"

      if ! shell_is_function "${functionname}"
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

   .foreachline pluginpath in $(dir_list_files "${directory}" "*.sh" "f")
   .do
      testgen_plugin_load_method "${pluginpath}"
   .done
}


testgen_plugin_load_all_methods()
{
   log_entry "testgen_plugin_load_all_methods"

   local directory

   [ -z "${DEFAULT_IFS}" ] && internal_fail "DEFAULT_IFS not set"
   [ -z "${MULLE_TESTGEN_LIBEXEC_DIR}" ] && internal_fail "MULLE_TESTGEN_LIBEXEC_DIR not set"

   log_fluff "Loading method plugins..."

   .foreachpath directory in ${MULLE_TESTGEN_PLUGIN_PATH}
   .do
      if [ -d "${directory}/method" ]
      then
         testgen_plugin_load_methods_from_dir "${directory}/method"
         if [ -d "${directory}/method/class" ]
         then
            testgen_plugin_load_methods_from_dir "${directory}/method/class"
         fi
      fi
   .done
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

      method-filename|type-filename)
         local string

         [ $# -eq 0 ] && testgen_plugin_usage "missing parameter"

         string="$1"; shift

         [ $# -ne 0 ] && testgen_plugin_usage "superflous parameters \"$*\""

         name="${cmd%%-filename}"

         if ! "r_plugin_filename_for_${name}" "${string}"
         then
            fail "Untranslatable method"
         fi
         echo "${RVAL}"
      ;;

      recode-functionname|printer-functionname|values-functionname)
         local typestring

         [ $# -eq 0 ] && testgen_plugin_usage "missing parameter"

         typestring="$1"; shift

         [ $# -ne 0 ] && testgen_plugin_usage "superflous parameters \"$*\""

         local name

         name="${cmd%%-functionname}"

         if ! "r_plugin_${name}_functionname_for_type" "${typestring}"
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
