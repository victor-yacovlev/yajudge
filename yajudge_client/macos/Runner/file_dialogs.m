#import <Cocoa/Cocoa.h>
#import <stdlib.h>
#import <string.h>
#import <limits.h>

extern __attribute__((visibility("default"))) __attribute__((used))
char* file_picker_open_file(char *pattern) {
    (void) pattern; // TODO implement pattern matching
    
    __block char* result = NULL;
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSOpenPanel* openDlg = [NSOpenPanel openPanel];
        [openDlg setCanChooseDirectories:NO];
        [openDlg setCanChooseFiles:YES];
        [openDlg setAllowsMultipleSelection:NO];

        if ([openDlg runModal] == NSModalResponseOK) {
            NSURL* url = [openDlg URL];
            NSString* path = [url path];
            const char* utf8 = [path UTF8String];
            result = calloc(PATH_MAX, sizeof(char));
            strncpy(result, utf8, PATH_MAX);
        }
    });
    
    return result;
}

extern __attribute__((visibility("default"))) __attribute__((used))
void file_picker_free_string(char *str) {
    free(str);
}

