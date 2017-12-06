
# GitDiff9  - GitDiff for Xcode 9

A port of the "GitDiff" Xcode plugin to the Xcode 9 beta now that the Source editor has been implemented in Swift. It uses an extensible framework of generalised providers of line number gutter highlights with which it communicates using JSON IPC. This version of GitDiff includes the implementations for four types of line number highlighters:

* Unstaged differences against a project's git repo
* Highlight of changes committed in the last week
* Format linting hints provided by swiftformat and clang-format
* A viewer that makes explicit inferred types in declarations.

To use, clone this project and build target "LNXcodeSupport". You'll need to [unsign your Xcode binary](https://github.com/fpg1503/MakeXcodeGr8Again) for the Xcode side of the plugin to load. The user interface is largely as it was before.

![Icon](http://johnholdsworth.com/gitdiff9.png)

Lines that have been changed relative to the repo are highlighted in amber and new lines highlighted in blue. Code lint suggestions are highlighted in dark blue and lines with a recent commit to the repo (the last 7 days by default) are highlighted in light green, fading with time.

Hovering over a change or lint highlight will overlay the previous or suggested version over the source editor and if you would like to revert the code change or apply the lint suggestion, continue hovering over the highlight until a very small button appears and click on it. The plugin runs a menubar app that contains colour preferences and allows you to turn on and off individual highlights.

![Icon](http://johnholdsworth.com/lnprovider9a.png)

### Expandability

The new implementation has been generalised to provide line number highlighting as a service from inside a new Legacy Xcode plugin. The project includes an menubar app "LNProvider" which is run to provide the default implementations using XPC. Any application can register with the plugin to provide line number highlights if it follows the Distributed Objects messaging protocol documented in "LNExtensionProtocol.h". Whenever a file is saved or reloaded, a call is made from the plugin to your application to provide JSON describing the intended highlights, their colours and any associated text. See the document "LineNumberPlugin.pages" for details about the architecture.

### Code linting

This repo includes binary releases of [swiftformat](https://github.com/nicklockwood/SwiftFormat) and [clang-format](https://clang.llvm.org/docs/ClangFormatStyleOptions.html) under their respective licenses. To modify code linting preferences, edit the files swift_format.sh and clang_format.sh in the "FormatImpl" directory and rebuild the plugin.
