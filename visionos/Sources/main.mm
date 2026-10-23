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
#import "GalaxyVisionStereoEngine.h"
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
// process exits), so the options are an overlay over the game, shown by R1 / RB (N64 pad: Start +
// Capture held) while the game's own pause menu is up. The game is held on its frame
// (galaxypad_engine_pause) and gets no input while the overlay is up.
//
// The overlay and the toast are plain subviews of the SDL game window, NOT extra UIWindows: every
// additional UIWindow in a visionOS scene gets the system's glass background material, which
// blurred the whole game picture behind it (the "fuzzy window" regression of 20ea626).
static UIWindowScene *sGameScene;
static UIViewController *sOverlayContent;
static UIView *sToastView;
static BOOL sSceneResigned;

// The engine's SDL window: the scene's first window that is not hidden.
static UIWindow *GVGameWindow(void) {
  for (UIWindow *w in sGameScene.windows) {
    if (!w.hidden) return w;
  }
  return nil;
}

static void GVHideOverlay(void) {
  if (!sOverlayContent) return;
  [sOverlayContent willMoveToParentViewController:nil];
  [sOverlayContent.view removeFromSuperview];
  [sOverlayContent removeFromParentViewController];
  sOverlayContent = nil;
  galaxypad_engine_pause(0);
  GalaxyVisionController.shared.inputSuspended = NO;
}

static void GVShowOverlay(void) {
  UIWindow *gameWindow = GVGameWindow();
  if (sOverlayContent || !gameWindow) return;
  GalaxyVisionController.shared.inputSuspended = YES;
  galaxypad_engine_pause(1);
  UIViewController *content = [GVOverlayFactory makeViewControllerOnDisplayChange:^{
    [GalaxyVisionController.shared applyDisplaySettingsNow];
  } onResume:^{ GVHideOverlay(); } onQuit:^{
    // The player confirmed in the overlay. Unpause so the game loop can see the request, then use the
    // engine's own "Stop Game" path (the Home menu's Quit). No save happens.
    GVHideOverlay();
    galaxypad_engine_quit();
  }];
  UIViewController *host = gameWindow.rootViewController;
  UIView *parent = host ? host.view : gameWindow;
  if (host) [host addChildViewController:content];
  content.view.frame = parent.bounds;
  content.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [parent addSubview:content.view];
  if (host) [content didMoveToParentViewController:host];
  sOverlayContent = content;
}

// Saving: the engine only saves through its own save sequence (startGameDataSaveSequence: story and
// Power Star autosaves, Pause > "Save your progress and quit"), which runs on the game thread over
// several frames with on-screen messages. It cannot be started safely from a lifecycle callback
// (the game is paused and the process may be suspended before it finishes), and GameData.bin is
// never written directly. So: remember that the scene lost focus and, when it comes back, remind
// the player that closing the window does not save.
static void GVShowToast(NSString *text, NSTimeInterval seconds) {
  UIWindow *gameWindow = GVGameWindow();
  UIView *parent = gameWindow.rootViewController ? gameWindow.rootViewController.view : gameWindow;
  if (sToastView || !parent) return;
  UIVisualEffectView *panel =
      [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
  panel.layer.cornerRadius = 20;
  panel.clipsToBounds = YES;
  panel.userInteractionEnabled = NO;
  UILabel *label = [[UILabel alloc] init];
  label.text = text;
  label.numberOfLines = 0;
  label.textAlignment = NSTextAlignmentCenter;
  label.textColor = UIColor.whiteColor;
  label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
  [panel.contentView addSubview:label];
  const CGFloat width = MAX(200, MIN(560, parent.bounds.size.width - 40));
  panel.frame = CGRectMake(0, 0, width, 96);
  label.frame = CGRectInset(panel.bounds, 16, 12);
  panel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
                           UIViewAutoresizingFlexibleTopMargin;
  panel.center = CGPointMake(CGRectGetMidX(parent.bounds), CGRectGetMaxY(parent.bounds) - 80);
  [parent addSubview:panel];
  sToastView = panel;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [panel removeFromSuperview];
    if (sToastView == panel) sToastView = nil;
  });
}

static void GVShowSaveToast(void) {
  GVShowToast(@"Closing the window does not save.\nUse Pause \u203A \u201CSave your progress and quit\u201D to save.", 8);
}

// --- Stereoscopic window (beta) -----------------------------------------------------------------
// Chosen in the launcher's View tab. Once the engine runs, the stereo bridge is requested (the engine
// creates the eye IOSurfaces on its render thread); when it is ready the engine starts drawing both eyes
// and a RealityKit screen (GalaxyVisionStereo.swift) is added over the game window as a child view
// controller (again: not a UIWindow). If anything fails the game simply stays in the flat window and a
// toast says why. The SDL window keeps presenting underneath, which paces the game.
static UIViewController *sStereoContent;
static NSTimer *sStereoTimer;

static void GVStereoFailed(NSString *message) {
  [sStereoTimer invalidate];
  sStereoTimer = nil;
  [GVStereoEngine applyEnabled:NO depth:1.0f convergence:1200.0f];
  [GVStereoEngine setBridgeOpen:NO];
  if (sStereoContent) {
    [sStereoContent willMoveToParentViewController:nil];
    [sStereoContent.view removeFromSuperview];
    [sStereoContent removeFromParentViewController];
    sStereoContent = nil;
  }
  fprintf(stderr, "GalaxyVision stereo: failed: %s\n", message.UTF8String);
  GVShowToast([NSString stringWithFormat:@"Stereoscopic window couldn\u2019t start:\n%@\nThe flat window stays in use.", message], 12);
}

static void GVInstallStereoView(void) {
  UIWindow *gameWindow = GVGameWindow();
  UIViewController *host = gameWindow.rootViewController;
  UIView *parent = host ? host.view : gameWindow;
  if (!parent || sStereoContent) return;
  UIViewController *content = [GVStereoFactory makeViewControllerOnError:^(NSString *message) { GVStereoFailed(message); }];
  if (host) [host addChildViewController:content];
  content.view.frame = parent.bounds;
  content.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [parent insertSubview:content.view atIndex:0];  // under any overlay or toast
  if (host) [content didMoveToParentViewController:host];
  sStereoContent = content;
}

static void GVStartStereo(void) {
  __block BOOL requested = NO;
  __block CFTimeInterval requestedAt = 0;
  sStereoTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
    if (!GVStereoEngine.engineStarted || !GVGameWindow()) return;  // the first start prepares shaders
    if (!requested) {
      requested = YES;
      requestedAt = CACurrentMediaTime();
      [GVStereoEngine setBridgeOpen:YES];
      return;
    }
    const NSInteger status = GVStereoEngine.status;
    if (status == 1) {
      [timer invalidate];
      sStereoTimer = nil;
      [GVStereoEngine applySavedSettings];  // the engine starts drawing both eyes
      GVInstallStereoView();
    } else if (status == -1) {
      GVStereoFailed(GVStereoEngine.error);
    } else if (CACurrentMediaTime() - requestedAt > 20) {
      GVStereoFailed(@"the engine did not open the eye images in time.");
    }
  }];
}

// --- FPS counter (testing) -----------------------------------------------------------------------
// A small non-interactive label in the top-right corner of the game window (a subview, not a UIWindow, so no
// glass blur). Updated about twice a second from the game's presented frames: the engine's
// presented-frame count in the flat window; in the Stereoscopic window the engine presents twice per game
// step (once per eye), so the right eye's published frames (one per game step) are counted instead, and the
// eye resolution setting is shown too. Shown while "Show FPS counter (testing)" is on (Graphics tab).
static UILabel *sFPSLabel;
static NSTimer *sFPSTimer;
static uint64_t sFPSLastCount;
static CFTimeInterval sFPSLastTime;
static BOOL sFPSLastStereo;

static uint64_t GVFPSCount(BOOL stereo) {
  if (!stereo) return galaxypad_engine_presented_frames();
  uint64_t sequence = 0;
  [GVStereoEngine latestSlotForEye:1 sequence:&sequence];
  return sequence;
}

static void GVFPSTick(void) {
  UIWindow *gameWindow = GVGameWindow();
  UIView *parent = gameWindow.rootViewController ? gameWindow.rootViewController.view : gameWindow;
  if (!parent || !galaxypad_engine_started() || !GalaxyVisionSettings.showFPS) {
    [sFPSLabel removeFromSuperview];
    sFPSLastTime = 0;
    return;
  }
  if (!sFPSLabel) {
    sFPSLabel = [[UILabel alloc] init];
    sFPSLabel.userInteractionEnabled = NO;
    sFPSLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
    sFPSLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    sFPSLabel.layer.cornerRadius = 8;
    sFPSLabel.clipsToBounds = YES;
    sFPSLabel.textAlignment = NSTextAlignmentCenter;
    sFPSLabel.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightSemibold];
    sFPSLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
  }
  const BOOL stereo = GalaxyVisionSettings.stereoSelected && sStereoContent && GVStereoEngine.status == 1;
  const uint64_t count = GVFPSCount(stereo);
  const CFTimeInterval now = CACurrentMediaTime();
  if (sFPSLabel.superview != parent) [parent addSubview:sFPSLabel];  // (an open overlay was added later, so stays above)
  if (sFPSLastTime > 0 && stereo == sFPSLastStereo && now > sFPSLastTime && count >= sFPSLastCount) {
    const double fps = (double)(count - sFPSLastCount) / (now - sFPSLastTime);
    NSString *text = [NSString stringWithFormat:@"%.0f fps", fps];
    if (stereo) {
      const NSInteger h = GalaxyVisionSettings.stereoResolution;
      text = [text stringByAppendingFormat:@" \u00B7 eye %ldx%ld", (long)((h * 16 + 4) / 9), (long)h];
    }
    sFPSLabel.text = text;
    [sFPSLabel sizeToFit];
    CGRect frame = sFPSLabel.frame;
    frame.size.width += 16;
    frame.size.height += 6;
    frame.origin = CGPointMake(CGRectGetMaxX(parent.bounds) - frame.size.width - 16, 16);
    sFPSLabel.frame = frame;
  }
  sFPSLastCount = count;
  sFPSLastTime = now;
  sFPSLastStereo = stereo;
}

static void GVStartFPSCounter(void) {
  if (sFPSTimer) return;
  sFPSTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { GVFPSTick(); }];
}

static void GVObserveGameScene(UIWindowScene *scene) {
  sGameScene = scene;
  GalaxyVisionController.shared.onOptionsRequested = ^{ GVShowOverlay(); };
  NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
  void (^resigned)(NSNotification *) = ^(NSNotification *n) { sSceneResigned = YES; };
  [nc addObserverForName:UISceneWillDeactivateNotification object:scene queue:NSOperationQueue.mainQueue usingBlock:resigned];
  [nc addObserverForName:UISceneDidEnterBackgroundNotification object:scene queue:NSOperationQueue.mainQueue usingBlock:resigned];
  [nc addObserverForName:UISceneDidActivateNotification object:scene queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification *n) {
    if (!sSceneResigned) return;
    sSceneResigned = NO;
    if (galaxypad_engine_started() && !sOverlayContent) GVShowSaveToast();
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
  if (GalaxyVisionSettings.stereoSelected) GVStartStereo();
  GVStartFPSCounter();
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
