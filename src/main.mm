#include "app_delegate.h"

int main(int argc, char *argv[]) {
  // App app;
  // return app.Run();
  @autoreleasepool {
    AppDelegate *delegate = [[AppDelegate alloc] init];

    NSApplication *application = [NSApplication sharedApplication];
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    [application setMainMenu:[[NSMenu alloc] init]];
    [application setDelegate:delegate];
    [application activateIgnoringOtherApps:YES];
    [application run];
  }
  return 0;
}
