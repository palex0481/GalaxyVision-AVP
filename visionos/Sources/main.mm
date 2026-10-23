// SPDX-License-Identifier: GPL-3.0-or-later
// GalaxyVision: visionOS shell for GalaxyPadEngine.framework.
//
// If game data exists at Application Support/GalaxyPad/GameData/RMGE01 (sys/main.dol), the process
// is handed to the engine (UIApplicationMain runs inside galaxypad_engine_main). The scene first
// shows the SwiftUI launcher; Play then hands the scene to the engine's SDL3 scene delegate, whose
// window is the flat virtual screen. Without game data the launcher shows the import placeholder
// (import is not implemented yet).
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "GalaxyVisionController.h"
#import "GalaxyVisionSettings.h"
#import "GalaxyVision-Swift.h"

static NSURL *GVBase(void) {
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                         inDomains:NSUserDomainMask].firstObject;
  return [support URLByAppendingPathComponent:@"GalaxyPad" isDirectory:YES];
}
static NSURL *GVGameDir(void) { return [GVBase() URLByAppendingPathComponent:@"GameData/RMGE01" isDirectory:YES]; }
static BOOL GVHaveGame(void) {
  return [NSFileManager.defaultManager fileExistsAtPath:[GVGameDir() URLByAppendingPathComponent:@"sys/main.dol"].path];
}
static BOOL GVEngineHost(void) {
  const char *host = getenv("GALAXYPAD_ENGINE_HOST");
  return host && strcmp(host, "1") == 0;
}

// Import placeholder: presents a folder picker, does not copy anything yet.
@interface GVImportHelper : NSObject <UIDocumentPickerDelegate>
+ (void)presentFrom:(UIViewController *)presenter;
@end
@implementation GVImportHelper
+ (void)presentFrom:(UIViewController *)presenter {
  static GVImportHelper *helper;  // the picker's delegate is weak
  helper = [[GVImportHelper alloc] init];
  UIDocumentPickerViewController *picker =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ]];
  picker.delegate = helper;
  [presenter presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  // TODO: copy the picked disc-contents folder into GVGameDir() (needs sys/main.dol + files/), then relaunch.
  NSLog(@"GalaxyVision import placeholder: picked %@", urls.firstObject);
}
@end

@interface GalaxyPadSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation GalaxyPadSceneDelegate
// Hands the scene to the engine's SDL scene delegate (the app delegate class SDL registered).
// scene.delegate is weak, so keep the engine delegate alive here.
static id<UIWindowSceneDelegate> sEngineSceneDelegate;
static void GVHandOffToEngine(UIScene *scene, UISceneSession *session, UISceneConnectionOptions *options) {
  [GalaxyVisionSettings applyStartupEnvironment];  // PETARI_RENDER_SCALE etc., read at engine init
  NSObject *app = (NSObject *)UIApplication.sharedApplication.delegate;
  sEngineSceneDelegate = [[app.class alloc] init];
  scene.delegate = sEngineSceneDelegate;
  [sEngineSceneDelegate scene:scene willConnectToSession:session options:options];
  [GalaxyVisionController.shared start];
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
  if (![scene isKindOfClass:UIWindowScene.class]) return;
  [GalaxyVisionSettings registerDefaults];
  const BOOL engine = GVEngineHost();
  self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
  __block UIViewController *launcher = nil;
  __weak GalaxyPadSceneDelegate *weakSelf = self;
  launcher = [GVLauncherFactory makeViewControllerWithGameFound:engine
      onPlay:^{
        GalaxyPadSceneDelegate *strongSelf = weakSelf;
        if (!engine || !strongSelf) return;
        // Tear down the launcher window, then let the engine create its own window in the scene.
        strongSelf.window.hidden = YES;
        strongSelf.window = nil;
        GVHandOffToEngine(scene, session, options);
      }
      onImport:^{ [GVImportHelper presentFrom:launcher]; }];
  self.window.rootViewController = launcher;
  [self.window makeKeyAndVisible];
}
@end

@interface GalaxyVisionAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation GalaxyVisionAppDelegate
@end

int main(int argc, char *argv[]) {
  @autoreleasepool {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *game = GVGameDir();
    NSURL *user = [GVBase() URLByAppendingPathComponent:@"NewEngine" isDirectory:YES];
    BOOL haveGame = GVHaveGame() && [files createDirectoryAtURL:user withIntermediateDirectories:YES attributes:nil error:nil];
    [GalaxyVisionSettings registerDefaults];
    if (haveGame) {
      setenv("GALAXYPAD_ENGINE_HOST", "1", 1);
      // TARGET_OS_IPHONE is true on visionOS, so the engine would draw its phone touch controls.
      // (Also re-set in applyStartupEnvironment, together with the launcher's graphics options.)
      setenv("PETARI_TOUCH_CONTROLS", "0", 1);
      NSArray<NSString *> *args = @[ @"GalaxyVision", @"--disc", game.path, @"--user", user.path ];
      char **engineArgv = (char **)calloc(args.count + 1, sizeof(char *));
      for (NSUInteger i = 0; i < args.count; ++i) engineArgv[i] = strdup(args[i].fileSystemRepresentation);
      return galaxypad_engine_main((int)args.count, engineArgv);
    }
    return UIApplicationMain(argc, argv, nil, NSStringFromClass(GalaxyVisionAppDelegate.class));
  }
}
