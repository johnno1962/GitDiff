#!/usr/bin/env python
# -*- coding: utf-8 -*-

#  gitblame.py
#  LNProvider
#
#  Created by John Holdsworth on 31/03/2017.
#  Copyright © 2017 John Holdsworth. All rights reserved.

import subprocess
import json
import time
import math
import sys
import re

file = sys.argv[1]
parser = re.compile(r"^\^?(\S+) (?:\S+\s+)*\((.+) +(\d+) \S+ +(\d+)\)")

def readdefault( key, default ):
    value = subprocess.Popen(['/usr/bin/env', 'defaults', 'read', 'LineNumber', key],
                            stdout=subprocess.PIPE).stdout.read()
    return value if value != '' else default

recent = float(readdefault('RecentDays', '7'))*24*60*60
decay = recent

color = readdefault('RecentColor', "0.5 1.0 0.5 1")
color = re.sub(r' [\d.]+\n?$', ' %f', color)

lastcommit = None
commits = {}
output = {}

proc = subprocess.Popen(['/usr/bin/env', 'git', 'blame', '-t', file],stdout=subprocess.PIPE)
for line in iter(proc.stdout.readline,''):
    match = parser.match(line)
    commit = match.group(1)
    if commit.startswith('00000000'):
        continue

    who = match.group(2)
    when = match.group(3)
    lineno = match.group(4)

    if commit != lastcommit:
        start = lineno
    lastcommit = commit

    age = time.time() - int(when)
    seen = commits.get(commit)
    if seen:
        alias = {'alias': seen['lineno']}
        if lineno == start:
            alias['start'] = start
            seen['lineno'] = start
        output[lineno] = alias
    elif age < recent:
        log = subprocess.Popen(['/usr/bin/env', 'git', 'show', '--pretty=medium', '-s', commit],
                               stdout=subprocess.PIPE).stdout.read()
        commits[commit] = {'lineno': lineno, 'log': log}
        output[lineno] = {'text': log, 'start': start, 'color': color % math.exp(-age/decay)}

print json.dumps(output)
