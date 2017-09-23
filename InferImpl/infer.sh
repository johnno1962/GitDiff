#!/bin/bash

#  infer.sh
#  LNProvider
#
#  Created by User on 22/08/2017.
#  Copyright © 2017 John Holdsworth. All rights reserved.

diff -Naur <("$(dirname "$0")/infer" "$1") "$1"

