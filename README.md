# GitDiff Xcode Plugin

With thanks to the genius who suggested this plugin, GitDiff displays deltas against a git repo in the Xcode
source editor once you've saved the file. To use, copy this repo to your machine, build it and restart Xcode.
Differences should then be highlighted in orange for lines that have been modified and blue for new code.
A red line indicates code has been removed. Hover over deleted/modified line number to see original source
and after a second a button will appear allowing you to revert the change.

![Icon](http://injectionforxcode.johnholdsworth.com/gitdiff2.png)

This Plugin is also available through the [Alcatraz](http://alcatraz.io/) meta-plugin and was developed using
the [Xprobe Plugin](https://github.com/johnno1962/XprobePlugin) for Xcode plugin developers.

NOTE: GitDiff will not work if you are not showing line numbers in the Xcode Editor.

### MIT License

Copyright (C) 2014-5 John Holdsworth

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated 
documentation files (the "Software"), to deal in the Software without restriction, including without limitation 
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, 
and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial 
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT 
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### [DiffMatchPatch](https://github.com/inquisitiveSoft/DiffMatchPatch-ObjC) License

This plugin includes code from the Objective-C port of Google DiffMatchPatch under an Apache License.
