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
emit_initWithObject_varargList__test()
{
   local classname="$1"
   local classname_pointer="$2"
   local name="$3"
   local typeparse="$4"
   local functionname="$5"
   local returntype="$6"
   local isclassmethod="$7"
   local family="$8"

   local lf='\n'

   cat <<EOF
//
// c-function is va_list
//
static void   _${functionname}( id first, ...)
{
   va_list   args;
   ${classname}  *obj;

   @try
   {
      va_start( args, first);
      obj = [[[${classname} alloc] initWithObject:first
                                       arguments:args] autorelease];
      printf( "%s${lf}", obj ? [[obj mulleTestDescription] UTF8String] : "*nil*");
      va_end( args);
   }
   @catch( NSException *localException)
   {
      printf( "Threw a %s exception${lf}", [[localException name] UTF8String]);
   }
}


static int   ${functionname}( void)
{
   _${functionname}( @"nix", nil);
   _${functionname}( @"%@", @1, nil);
   _${functionname}( @"%@ %@ %@ %@ %@", @1, @2, @3, @4, @5, nil);
   return( 0);
}

EOF
}
