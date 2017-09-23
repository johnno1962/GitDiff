#!/bin/bash

#  swift_format.sh
#  LNProvider
#
#  Created by John Holdsworth on 03/04/2017.
#  Copyright © 2017 John Holdsworth. All rights reserved.

# https://github.com/nicklockwood/SwiftFormat/releases/tag/0.28.2

diff -Naur <("$(dirname "$0")/swiftformat" <"$1") "$1"
