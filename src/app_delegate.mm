#include "app_delegate.h"
#include "hdr_layer.h"
#include <AppKit/AppKit.h>

@interface WindowDelegate : NSObject <NSWindowDelegate>
@property(nonatomic, strong) HDRContentLayer *contentLayer;
@end

@implementation WindowDelegate

- (void)windowDidResize:(NSNotification *)notification {
  NSWindow *window = notification.object;
  NSView *contentView = window.contentView;

  // 更新图层尺寸
  self.contentLayer.frame = contentView.bounds;

  // 可选：触发重绘
  [self.contentLayer setNeedsDisplay];
}

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  printf("Application did finish launching\n");
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 480, 480)
                styleMask:NSWindowStyleMaskClosable | NSWindowStyleMaskTitled |
                          NSWindowStyleMaskResizable
                  backing:NSBackingStoreBuffered
                    defer:NO];

  [window setTitle:@"HDR Demo"];

  NSView *view = [window contentView];
  [view setWantsLayer:YES];
  [window center];

  // CALayer *content_layer = [[CALayer alloc] init];
  HDRContentLayer *content_layer = [[HDRContentLayer alloc] init];
  content_layer.frame = CGRectMake(0, 0, 480, 480);
  content_layer.backgroundColor = [[NSColor blackColor] CGColor];

  [[[window contentView] layer] addSublayer:content_layer];

  WindowDelegate *windowDelegate = [[WindowDelegate alloc] init];
  windowDelegate.contentLayer = content_layer;
  [window setDelegate:windowDelegate];

  [window makeKeyAndOrderFront:nil];
  [[NSApplication sharedApplication]
      setActivationPolicy:NSApplicationActivationPolicyRegular];
  [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
  self.window = window;
  printf("Host: Added the layer to the view hierarchy..\n");
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES; // 窗口关闭时退出应用
}

@end
