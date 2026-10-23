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

// --- In-game options overlay and save reminder -------------------------------------------------
// The engine cannot return to the launcher mid-game (its SDL window and render loop live until the
// process exits), so the options are an overlay window over the game: a SwiftUI view in a second
// UIWindow of the same scene, shown by the pad's options combo. The game is held on its frame
// (galaxypad_engine_pause) and gets no input while it is up.
static UIWindowScene *sGameScene;
static UIWindow *sOverlayWindow;
static UIWindow *sToastWindow;
static BOOL sSceneResigned;
static UIWindow *sPillWindow;
static void GVShowToast(NSString *text, NSTimeInterval seconds);

// A small always-visible "Options" pill over the game (top right). It sits in its own UIWindow that
// never becomes key (the engine's window keeps focus and the controller) and lets every touch that
// misses the pill through to the game. Pinch-selectable like any button.
@interface GVPassthroughWindow : UIWindow
@property(nonatomic, weak) UIView *pill;
@end
@implementation GVPassthroughWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  UIView *hit = [super hitTest:point withEvent:event];
  UIView *pill = self.pill;
  if (pill && hit && (hit == pill || [hit isDescendantOfView:pill])) return hit;
  return nil;
}
@end

static void GVShowOverlay(void);

static void GVShowPill(void) {
  if (sPillWindow || !sGameScene) return;
  GVPassthroughWindow *window = [[GVPassthroughWindow alloc] initWithWindowScene:sGameScene];
  window.windowLevel = UIWindowLevelAlert + 3;
  window.backgroundColor = UIColor.clearColor;
  UIViewController *vc = [[UIViewController alloc] init];
  vc.view.backgroundColor = UIColor.clearColor;
  UIButtonConfiguration *config = [UIButtonConfiguration borderedButtonConfiguration];
  config.title = @"Options";
  config.image = [UIImage systemImageNamed:@"gearshape.fill"];
  config.imagePadding = 6;
  config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
  config.contentInsets = NSDirectionalEdgeInsetsMake(8, 14, 8, 14);
  UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *a) {
    GVShowOverlay();
  }]];
  button.alpha = 0.6;  // subtle until looked at / pressed
  button.accessibilityLabel = @"GalaxyVision options";
  [button sizeToFit];
  CGSize size = button.bounds.size;
  button.frame = CGRectMake(CGRectGetWidth(vc.view.bounds) - size.width - 24, 24, size.width, size.height);
  button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
  [vc.view addSubview:button];
  window.pill = button;
  window.rootViewController = vc;
  window.hidden = NO;
  sPillWindow = window;
}

static void GVHideOverlay(void) {
  if (!sOverlayWindow) return;
  sOverlayWindow.hidden = YES;
  sOverlayWindow = nil;
  sPillWindow.hidden = NO;
  galaxypad_engine_pause(0);
  GalaxyVisionController.shared.inputSuspended = NO;
  for (UIWindow *w in sGameScene.windows) {
    if (!w.hidden && w != sToastWindow && w != sPillWindow) { [w makeKeyWindow]; break; }
  }
}

static void GVShowOverlay(void) {
  if (sOverlayWindow || !sGameScene) return;
  GalaxyVisionController.shared.inputSuspended = YES;
  galaxypad_engine_pause(1);
  sPillWindow.hidden = YES;
  UIViewController *content = [GVOverlayFactory makeViewControllerOnDisplayChange:^{
    [GalaxyVisionController.shared applyDisplaySettingsNow];
  } onResume:^{ GVHideOverlay(); } onQuit:^{
    // The player confirmed in the overlay. Unpause so the game loop can see the request, then use the
    // engine's own "Stop Game" path (the Home menu's Quit). No save happens.
    GVHideOverlay();
    galaxypad_engine_quit();
  }];
  UIWindow *window = [[UIWindow alloc] initWithWindowScene:sGameScene];
  window.windowLevel = UIWindowLevelAlert + 10;
  window.rootViewController = content;
  sOverlayWindow = window;
  [window makeKeyAndVisible];
}

// Saving: the engine only saves through its own save sequence (startGameDataSaveSequence: story and
// Power Star autosaves, Pause > "Save your progress and quit"), which runs on the game thread over
// several frames with on-screen messages. It cannot be started safely from a lifecycle callback
// (the game is paused and the process may be suspended before it finishes), and GameData.bin is
// never written directly. So: remember that the scene lost focus and, when it comes back, remind
// the player that closing the window does not save.
static void GVShowToast(NSString *text, NSTimeInterval seconds) {
  if (sToastWindow || !sGameScene) return;
  UIWindow *window = [[UIWindow alloc] initWithWindowScene:sGameScene];
  window.windowLevel = UIWindowLevelAlert + 5;
  window.userInteractionEnabled = NO;
  window.backgroundColor = UIColor.clearColor;
  UIViewController *vc = [[UIViewController alloc] init];
  vc.view.backgroundColor = UIColor.clearColor;
  UIVisualEffectView *panel =
      [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
  panel.layer.cornerRadius = 20;
  panel.clipsToBounds = YES;
  UILabel *label = [[UILabel alloc] init];
  label.text = text;
  label.numberOfLines = 0;
  label.textAlignment = NSTextAlignmentCenter;
  label.textColor = UIColor.whiteColor;
  label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
  [panel.contentView addSubview:label];
  [vc.view addSubview:panel];
  CGFloat width = MIN(560, vc.view.bounds.size.width - 40);
  panel.frame = CGRectMake(0, 0, width, 96);
  label.frame = CGRectInset(panel.bounds, 16, 12);
  panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                           UIViewAutoresizingFlexibleTopMargin;
  panel.center = CGPointMake(CGRectGetMidX(vc.view.bounds), CGRectGetMaxY(vc.view.bounds) - 80);
  window.rootViewController = vc;
  window.hidden = NO;
  sToastWindow = window;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    window.hidden = YES;
    if (sToastWindow == window) sToastWindow = nil;
  });
}

static void GVShowSaveToast(void) {
  GVShowToast(@"Closing the window does not save.\nUse Pause \u203A \u201CSave your progress and quit\u201D to save.", 8);
}

// Once the engine has finished preparing shaders and the game runs, show the Options pill and a
// short hint about it (the engine's own pause menu has no entry for the launcher options).
static void GVWaitForGameStart(void) {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (galaxypad_engine_started()) {
      GVShowPill();
      GVShowToast(@"Options: tap the Options button at the top right,\nor press R1 / RB on the controller.", 7);
    } else {
      GVWaitForGameStart();
    }
  });
}

static void GVObserveGameScene(UIWindowScene *scene) {
  sGameScene = scene;
  GalaxyVisionController.shared.onOptionsRequested = ^{ GVShowOverlay(); };
  GVWaitForGameStart();
  NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
  void (^resigned)(NSNotification *) = ^(NSNotification *n) { sSceneResigned = YES; };
  [nc addObserverForName:UISceneWillDeactivateNotification object:scene queue:NSOperationQueue.mainQueue usingBlock:resigned];
  [nc addObserverForName:UISceneDidEnterBackgroundNotification object:scene queue:NSOperationQueue.mainQueue usingBlock:resigned];
  [nc addObserverForName:UISceneDidActivateNotification object:scene queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *n) {
    if (!sSceneResigned) return;
    sSceneResigned = NO;
    if (galaxypad_engine_started() && !sOverlayWindow) GVShowSaveToast();
  }];
}

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
  if ([scene isKindOfClass:UIWindowScene.class]) GVObserveGameScene((UIWindowScene *)scene);
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
