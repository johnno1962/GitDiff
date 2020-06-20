//
//  infer.mm
//  infer
//
//  Created by John Holdsworth on 21/08/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  Makes explicit, inferred types in a Swift source.
//  Requires project to have been built & indexed.
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>
#import <regex.h>

#import "sourcekitd.h"

@interface PhaseOneFindArguemnts : NSObject
- (NSString * _Nullable)projectForSourceFile:(NSString *)sourceFile;
- (NSString * _Nullable)logDirectoryForProject:(NSString *)projectPath;
- (NSString * _Nullable)commandLineForPrimaryFile:(NSString *)sourceFile
                                   inLogDirectory:(NSString *)logDirectory;
@end

#define INError(fmt, ...) fprintf(stderr, fmt, __VA_ARGS__)
//#define INError(fmt, ...) NSLog(@fmt, __VA_ARGS__)

@interface PhaseTwoInferAssignments : NSObject
- (int)inferAssignmentsFor:(const char *)sourceFile
                 arguments:(const char **)argv into:(FILE *)output;
@end

int main(int argc, const char * argv[]) {
    const char *inferBinary = argv[0];
    if (argc < 2) {
        INError("Usage: %s <full path to swift source>\n", inferBinary);
        exit(1);
    }
    else if(argc == 2) {
        auto logReader = [PhaseOneFindArguemnts new];
        NSString *sourceFile = [NSString stringWithUTF8String:argv[1]];
        NSString *projectPath = [logReader projectForSourceFile:sourceFile];
        if (!projectPath) {
            INError("Could not find project for source file: %s\n", argv[1]);
            exit(1);
        }

        NSString *logDirectory = [logReader logDirectoryForProject:projectPath];
        NSString *compileCommand = [logReader commandLineForPrimaryFile:sourceFile
                                                         inLogDirectory:logDirectory];
        if (!compileCommand) {
            INError("Could not find compile command for '%s' in log directory: %s\n",
                    argv[1], logDirectory.UTF8String);
            exit(1);
        }

        NSTask *task = [NSTask new];
        task.launchPath = @"/bin/bash";
        task.arguments = @[@"-c", [NSString stringWithFormat:@"\"%@\" \"%@\" %@",
                                   [NSString stringWithUTF8String:inferBinary],
                                   sourceFile, compileCommand]];
        [task launch];
        [task waitUntilExit];
        exit(task.terminationStatus);
    }
    else {
        auto inferer = [PhaseTwoInferAssignments new];
        exit([inferer inferAssignmentsFor:argv[1] arguments:argv + 4 into:stdout]);
    }
}

@implementation NSTask(FILE)

- (FILE *)stdout {
    NSPipe *pipe = [NSPipe pipe];
    self.standardOutput = pipe;
    int fd = [self.standardOutput fileHandleForReading].fileDescriptor;
    [self launch];
    return fdopen(fd, "r");
}

@end

@implementation PhaseOneFindArguemnts {
    char logFile[PATH_MAX], commandBuffer[1024*1024]; // max command is 256k on Darwin
}

- (NSString *)fileWithExtension:(NSString *)extension inFiles:(NSArray<NSString *> *)files {
    for (NSString *file in files)
        if ([[file pathExtension] isEqualToString:extension])
            return file;
    return nil;
}

- (NSString *)projectForSourceFile:(NSString *)sourceFile {
    NSString *directory = sourceFile.stringByDeletingLastPathComponent;
    if ([directory isEqualToString:@"/"])
        return nil;

    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray<NSString *> *fileList = [manager contentsOfDirectoryAtPath:directory error:NULL];

    if (NSString *projectFile =
        [self fileWithExtension:@"xcworkspace" inFiles:fileList] ?:
        [self fileWithExtension:@"xcodeproj" inFiles:fileList]) {
        NSString *projectPath = [directory stringByAppendingPathComponent:projectFile];
        NSString *logDir = [self logDirectoryForProject:projectPath];
        if ([manager fileExistsAtPath:logDir])
            return projectPath;
    }

    return [self projectForSourceFile:directory];
}

- (NSString *)logDirectoryForProject:(NSString *)projectPath {
    NSString *projectName = [projectPath.lastPathComponent stringByDeletingPathExtension];
    return [NSString stringWithFormat:@"%@/Library/Developer/Xcode/DerivedData/%@-%@/Logs/Build",
            NSHomeDirectory(), [projectName stringByReplacingOccurrencesOfString:@" " withString:@"_"],
            [self hashStringForPath:projectPath]];
}

- (NSString *)commandLineForPrimaryFile:(NSString *)sourceFile
                         inLogDirectory:(NSString *)logDirectory {
    NSTask *lsTask = [NSTask new];
    lsTask.launchPath = @"/bin/bash";
    lsTask.arguments = @[@"-c", [NSString stringWithFormat:@"/bin/ls -t \"%@\"/*.xcactivitylog",
                                 logDirectory]];
    FILE *logsFILE = [lsTask stdout];

    while (fgets(logFile, sizeof logFile, logsFILE)) {
        logFile[strlen(logFile)-1] = '\000';

        NSTask *grepTask = [NSTask new];
        grepTask.launchPath = @"/bin/bash";
        grepTask.arguments = @[@"-c", [NSString stringWithFormat:@"/usr/bin/gunzip <'%@' | "
                                       "tr '\\r' '\\n' | /usr/bin/grep -E ' -primary-file \"?%@\"? '",
                                       [NSString stringWithUTF8String:logFile],
                                       [sourceFile stringByReplacingOccurrencesOfString:@"+" withString:@"\\+"]]];
        FILE *grepFILE = [grepTask stdout];

        if (fgets(commandBuffer, sizeof commandBuffer, grepFILE)) {
            *strstr(commandBuffer, " -o ") = '\000';
            [grepTask terminate];
            [lsTask terminate];
            return [NSString stringWithUTF8String:commandBuffer];
        }

        [grepTask waitUntilExit];
        pclose(grepFILE);
    }

    [lsTask waitUntilExit];
    pclose(logsFILE);
    return nil;
}

// Thanks to: http://samdmarshall.com/blog/xcode_deriveddata_hashes.html

// this function is used to swap byte ordering of a 64bit integer
uint64_t swap_uint64(uint64_t val) {
    val = ((val << 8) & 0xFF00FF00FF00FF00ULL) | ((val >> 8) & 0x00FF00FF00FF00FFULL);
    val = ((val << 16) & 0xFFFF0000FFFF0000ULL) | ((val >> 16) & 0x0000FFFF0000FFFFULL);
    return (val << 32) | (val >> 32);
}

/*!
 @method hashStringForPath

 Create the unique identifier string for a Xcode project path

 @param path (input) string path to the ".xcodeproj" or ".xcworkspace" file

 @result NSString* of the identifier
 */
- (NSString *)hashStringForPath:(NSString *)path;
{
    // using uint64_t[2] for ease of use, since it is the same size as char[CC_MD5_DIGEST_LENGTH]
    uint64_t digest[CC_MD2_DIGEST_LENGTH] = {0};

    // char array that will contain the identifier
    unsigned char resultStr[28] = {0};

    // setup md5 context
    CC_MD5_CTX md5;
    CC_MD5_Init(&md5);

    // get the UTF8 string of the path
    const char *c_path = [path UTF8String];

    // get length of the path string
    unsigned long length = strlen(c_path);

    // update the md5 context with the full path string
    CC_MD5_Update (&md5, c_path, (CC_LONG)length);

    // finalize working with the md5 context and store into the digest
    CC_MD5_Final ((unsigned char *)digest, &md5);

    // take the first 8 bytes of the digest and swap byte order
    uint64_t startValue = swap_uint64(digest[0]);

    // for indexes 13->0
    int index = 13;
    do {
        // take 'startValue' mod 26 (restrict to alphabetic) and add based 'a'
        resultStr[index] = (char)((startValue % 26) + 'a');

        // divide 'startValue' by 26
        startValue /= 26;

        index--;
    } while (index >= 0);

    // The second loop, this time using the last 8 bytes
    // repeating the same process as before but over indexes 27->14
    startValue = swap_uint64(digest[1]);
    index = 27;
    do {
        resultStr[index] = (char)((startValue % 26) + 'a');
        startValue /= 26;
        index--;
    } while (index > 13);

    // create a new string from the 'resultStr' char array and return
    return [[NSString alloc] initWithBytes:resultStr length:28 encoding:NSUTF8StringEncoding];
}

@end

@implementation PhaseTwoInferAssignments

- (int)inferAssignmentsFor:(const char *)sourceFile arguments:(const char **)argv into:(FILE *)output {
    NSError *error;
    NSMutableData *sourceData = [NSMutableData dataWithContentsOfFile:[NSString stringWithUTF8String:sourceFile]
                                                              options:0 error:&error];
    if (!sourceData) {
        INError("Could not load source file '%s': %s\n",
                sourceFile, error.localizedDescription.UTF8String);
        return 1;
    }

    const char *input = (const char *)[sourceData bytes], eos = '\000', *next = input;
    [sourceData appendBytes:&eos length:sizeof eos];

    sourcekitd_initialize();

    int argc = 0, argo = 0;
    sourcekitd_object_t objects[1000];
    NSDictionary *skips = @{
        @"-primary-file": @1,
        @"-emit-module-doc-path": @2,
        @"-emit-dependencies-path": @2,
        @"-emit-reference-dependencies-path": @2,
        @"-enable-objc-interop": @1,
        @"-warn-long-function-bodies": @1,
        @"-warn-long-expression-type-checking": @1,
        @"-serialize-debugging-options": @1,
        @"-enable-anonymous-context-mangled-names": @1,
        @"-pch-disable-validation": @1,
        @"-serialize-diagnostics-path": @2,
        @"-target-sdk-version": @2,
    };
    while (argv[argc]) {
        NSString *option = [NSString stringWithUTF8String:argv[argc]];
        option = [option stringByReplacingOccurrencesOfString:@"=.*" withString:@""
                  options:NSRegularExpressionSearch range:NSMakeRange(0, option.length)];
        int skip = [skips[option] intValue];
        if (!skip)
            objects[argo++] =
                sourcekitd_request_string_create(argv[argc]);
        argc += skip ?: 1;
    }

    sourcekitd_object_t compilerArgs =
        sourcekitd_request_array_create(objects, argo);

    sourcekitd_uid_t nameID = sourcekitd_uid_get_from_cstr("key.name");
    sourcekitd_uid_t requestID = sourcekitd_uid_get_from_cstr("key.request");
    sourcekitd_uid_t sourceFileID = sourcekitd_uid_get_from_cstr("key.sourcefile");
    sourcekitd_uid_t compilerArgsID = sourcekitd_uid_get_from_cstr("key.compilerargs");
    sourcekitd_uid_t cursorRequestID = sourcekitd_uid_get_from_cstr("source.request.cursorinfo");

    sourcekitd_object_t cursorRequest = sourcekitd_request_dictionary_create(nil, nil, 0);
    sourcekitd_request_dictionary_set_uid(cursorRequest, requestID, cursorRequestID);
    sourcekitd_request_dictionary_set_string(cursorRequest, sourceFileID, sourceFile);
    sourcekitd_request_dictionary_set_string(cursorRequest, nameID, sourceFile);
    sourcekitd_request_dictionary_set_value(cursorRequest, compilerArgsID, compilerArgs);

    sourcekitd_uid_t offsetID = sourcekitd_uid_get_from_cstr("key.offset");
    sourcekitd_uid_t declID = sourcekitd_uid_get_from_cstr("key.fully_annotated_decl");

    // sourcekit cursor ops deal in byte offsets
    regex_t assigns;
    if (int err = regcomp(&assigns,
                          "[ \t\n](let|var)[ \t]+([^\n,)]+?)[ \t]=[ \t]",
                          REG_EXTENDED|REG_ENHANCED)) {
        char errbuff[1000];
        regerror(err, &assigns, errbuff, sizeof errbuff);
        INError("Regex compilation error: %s\n", errbuff);
        return 1;
    }

    regmatch_t matches[3];

    while(regexec(&assigns, next, sizeof matches/sizeof matches[0], matches, 0) != REG_NOMATCH) {
        const char *varStart = next + matches[2].rm_so, *equals = next + matches[2].rm_eo;
        ptrdiff_t byteOffset = varStart - input;

        next += fwrite((void *)next, 1, matches[1].rm_so, output);

        sourcekitd_request_dictionary_set_int64(cursorRequest, offsetID, byteOffset);

        sourcekitd_response_t response = sourcekitd_send_request_sync(cursorRequest);
        if (sourcekitd_response_is_error(response)) {
            NSLog(@"Cursor request %s",
                  sourcekitd_response_error_get_description(response));
            sourcekitd_request_description_dump(cursorRequest);
            continue;
        }
        else {
            sourcekitd_variant_t dict = sourcekitd_response_get_value(response);
            if (const char *declaration = sourcekitd_variant_dictionary_get_string(dict, declID)) {
                const char *replacement = strstr(declaration, "let</syntaxtype.keyword>") ?:
                                          strstr(declaration, "var</syntaxtype.keyword>") ?: "NODECL";
                int inTag = 0;
                while (char ch = *replacement++) {
                    switch (ch) {
                        case '<': case '{':
                            inTag++;
                            break;
                        case '>': case '}':
                            inTag--;
                            break;
                        case '&':
                            if (strncmp(replacement, "lt;", 3) == 0) {
                                fputc('<', output);
                                replacement += 3;
                                break;
                            }
                            else if (strncmp(replacement, "gt;", 3) == 0) {
                                fputc('>', output);
                                replacement += 3;
                                break;
                            }
                        default:
                            if (!inTag && !(ch == ' ' &&
                                            (*replacement == ':' || *replacement == ' ' || *replacement == '{')))
                                fputc(ch, output);
                    }
                }
            }
            else {
                fwrite((void *)next, 1, equals - next, output);
            }
        }

        sourcekitd_response_dispose(response);
        next = equals;
    }

    fwrite((void *)next, 1, strlen(next), output);
    fflush(output);
    return 0;
}

@end
