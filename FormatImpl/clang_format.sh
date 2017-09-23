#!/bin/bash

#  clang_format.sh
#  LNProvider
#
#  Created by John Holdsworth on 04/04/2017.
#  Copyright © 2017 John Holdsworth. All rights reserved.

INDENT=`defaults read LineNumber FormatIndent`
XCODE_STYLE="{ IndentWidth: $INDENT, TabWidth: $INDENT, ObjCBlockIndentWidth: $INDENT, ColumnLimit: 0 }"

diff -Naur <("$(dirname "$0")/clang-format" -style="$XCODE_STYLE" <"$1") "$1"
