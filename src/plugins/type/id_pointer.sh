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

emit_id_pointer_values()
{
   local type="$1"
   local fragment="$2"
   local classname="$3"
   local memo_selector="$4"
   local memo_type="$5"
   local n="$6"

   printf "id  _EmptyIds[] = { 0 };\n"
   printf "id  _1848Ids[]  = { @\"1848\", 0 };\n"
   printf "id  _VfLIds[]   = { @\"VfL\", @\" \", @\"Bochum\", @1848, 0 };\n"

   values="_EmptyIds
_1848Ids
_VfLIds
NULL"
   r_emit_param_definition "${values}" "${n}" "${type}" ""
   emit_counter_definitions "${n}" "${type}" ""

   return 2   # indicate we printed ourselves

}


emit_id_pointer_printer()
{
   local variable="$1"
   local name="$2"
   local indent="$3"

   echo "${indent}printf( \"%s\\n\", *${variable} ? [[*${variable} mulleTestDescription] UTF8String] : \"*nil*\");"
}

