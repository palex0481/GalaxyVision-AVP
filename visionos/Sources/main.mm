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
static UIViewController *sStereoContent;  // the Stereoscopic window's RealityKit screen (set below)
static UIViewController *sImmersivePanel;  // the game window's content while the Immersive space is selected
static UIView *sToastView;
static BOOL sSceneResigned;

// The engine's SDL window: the scene's first window that is not hidden.
static UIWindow *GVGameWindow(void) {
  for (UIWindow *w in sGameScene.windows) {
    if (!w.hidden) return w;
  }
  return nil;
}

// Immersive space / portal: the game window is only a control panel, so the flat picture behind it is hidden (it is
// the same picture that is on the big screen) and the window's own glass shows. Visible again while the options
// are up (they show over the paused flat picture) and when the panel goes away. alpha, not hidden: the layer
// keeps handing out drawables to the engine either way.
static UIView *GVFindMetalView(UIView *view);
static void GVSetFlatPictureVisible(BOOL visible) {
  UIWindow *window = GVGameWindow();
  UIView *metal = window ? GVFindMetalView(window) : nil;
  if (!metal || metal == window || metal == window.rootViewController.view) return;
  metal.alpha = visible ? 1.0 : 0.0;
}

static void GVHideOverlay(void) {
  if (!sOverlayContent) return;
  [sOverlayContent willMoveToParentViewController:nil];
  [sOverlayContent.view removeFromSuperview];
  [sOverlayContent removeFromParentViewController];
  sOverlayContent = nil;
  // The stereo screen is a 3D RealityKit view; it is hidden while the options are up (the paused game's flat
  // picture shows behind them) so the 2D options can never end up behind the 3D plane.
  sStereoContent.view.hidden = NO;
  if (sImmersivePanel) { [GVImmersive setOverlay:NO]; GVSetFlatPictureVisible(NO); }  // the window shrinks back while the space is open
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
  sStereoContent.view.hidden = YES;
  if (sImmersivePanel) { [GVImmersive setOverlay:YES]; GVSetFlatPictureVisible(YES); }  // the window grows back to full size for the options
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
  const BOOL wasImmersive = sImmersivePanel != nil || GalaxyVisionSettings.spaceSelected;
  if (sImmersivePanel) {
    [GVImmersive close];
    GVSetFlatPictureVisible(YES);
    [sImmersivePanel willMoveToParentViewController:nil];
    [sImmersivePanel.view removeFromSuperview];
    [sImmersivePanel removeFromParentViewController];
    sImmersivePanel = nil;
  }
  fprintf(stderr, "GalaxyVision stereo: failed: %s\n", message.UTF8String);
  GVShowToast([NSString stringWithFormat:@"%@ couldn\u2019t start:\n%@\nThe flat window stays in use.",
               wasImmersive ? (GalaxyVisionSettings.portalSelected ? @"3D portal window" : @"Immersive space") : @"Stereoscopic window", message], 12);
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

// Immersive space (beta): the game window shows a small control panel; the screen lives in the SwiftUI
// ImmersiveSpace (GalaxyVisionImmersive.swift), activated through UIKit scene bridging.
static void GVOpenImmersive(void) {
  [GVImmersive openWithErrorHandler:^(NSString *message) { GVStereoFailed(message); }];
}

static void GVInstallImmersive(void) {
  UIWindow *gameWindow = GVGameWindow();
  UIViewController *host = gameWindow.rootViewController;
  UIView *parent = host ? host.view : gameWindow;
  if (!parent || sImmersivePanel) return;
  UIViewController *content = [GVImmersivePanelFactory makeViewControllerOnEnter:^{ GVOpenImmersive(); } onFlat:^{
    // Back to the plain flat window: close the space, drop the panel and stop the eye bridge.
    [GVImmersive close];
    GVSetFlatPictureVisible(YES);
    [GVStereoEngine applyEnabled:NO depth:1.0f convergence:1200.0f];
    [GVStereoEngine setBridgeOpen:NO];
    [sImmersivePanel willMoveToParentViewController:nil];
    [sImmersivePanel.view removeFromSuperview];
    [sImmersivePanel removeFromParentViewController];
    sImmersivePanel = nil;
  }];
  if (host) [host addChildViewController:content];
  content.view.frame = parent.bounds;
  content.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [parent addSubview:content.view];  // over the flat picture, under the options overlay and toasts added later
  if (host) [content didMoveToParentViewController:host];
  sImmersivePanel = content;
  GVSetFlatPictureVisible(NO);
  GVOpenImmersive();
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
      if (GalaxyVisionSettings.spaceSelected) GVInstallImmersive();
      else GVInstallStereoView();
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
  const BOOL stereo = GalaxyVisionSettings.bridgeSelected && (sStereoContent || sImmersivePanel) && GVStereoEngine.status == 1;
  const uint64_t count = GVFPSCount(stereo);
  const CFTimeInterval now = CACurrentMediaTime();
  if (sFPSLabel.superview != parent) [parent addSubview:sFPSLabel];  // (an open overlay was added later, so stays above)
  if (sFPSLastTime > 0 && stereo == sFPSLastStereo && now > sFPSLastTime && count >= sFPSLastCount) {
    const double fps = (double)(count - sFPSLastCount) / (now - sFPSLastTime);
    NSString *text = [NSString stringWithFormat:@"%.0f fps", fps];
    if (stereo) {
      const NSInteger h = GalaxyVisionSettings.stereoResolution;
      text = [text stringByAppendingFormat:@" \u00B7 eye %ldx%ld", (long)((h * 16 + 4) / 9), (long)h];
      if (GVStereoEngine.sharpActive) text = [text stringByAppendingString:@" sharp"];
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

// --- Ambient glow (flat window) ------------------------------------------------------------------
// A soft glow of the picture's edge colours around the game, like a TV backlight. A visionOS window cannot draw
// outside its own bounds, so while the glow is on the game's Metal view is scaled down about its centre (view
// transform only: the engine's drawable and aspect are untouched) and the glow is drawn in the border that frees
// up. The glow is a plain black view with four gradient strips, inserted directly BELOW the Metal view in the SDL
// window (not a UIWindow, so no glass material). With the switch off nothing is inserted and the Metal view's
// transform is the identity: the layout is exactly the old one.
//
// The colours come from the engine (galaxypad_engine_glow_colors: 4 edges x 16 cells, sampled about 20 times a
// second by a tiny compute pass, asynchronous readback), smoothed here and drawn at 20 Hz. The switch, strength and
// size are read from the settings every tick, so they apply live.
static const int kGlowCells = 16;
static UIView *sGlowView;
static UIView *sGlowMetalView;
static CAGradientLayer *sGlowEdges[4];  // top, right, bottom, left
static float sGlowSmooth[kGlowCells * 4 * 3];
static uint64_t sGlowSequence;
static CFTimeInterval sGlowSequenceTime;
static BOOL sGlowEngineOn;
static NSTimer *sGlowTimer;

static UIView *GVFindMetalView(UIView *view) {
  if ([view.layer isKindOfClass:CAMetalLayer.class]) return view;
  for (UIView *sub in view.subviews) {
    UIView *found = GVFindMetalView(sub);
    if (found) return found;
  }
  return nil;
}

static void GVGlowTeardown(void) {
  if (sGlowEngineOn) {
    galaxypad_engine_glow_enable(0);
    sGlowEngineOn = NO;
  }
  if (sGlowMetalView && !CGAffineTransformIsIdentity(sGlowMetalView.transform)) sGlowMetalView.transform = CGAffineTransformIdentity;
  [sGlowView removeFromSuperview];
  sGlowView = nil;
  sGlowMetalView = nil;
  for (int i = 0; i < 4; ++i) sGlowEdges[i] = nil;
  memset(sGlowSmooth, 0, sizeof sGlowSmooth);
  sGlowSequence = 0;
}

static CAGradientLayer *GVMakeGlowEdge(UIView *container) {
  CAGradientLayer *edge = [CAGradientLayer layer];
  CAGradientLayer *mask = [CAGradientLayer layer];
  mask.colors = @[ (id)[UIColor colorWithWhite:1 alpha:1.0].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.55].CGColor,
                   (id)[UIColor colorWithWhite:1 alpha:0.22].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.06].CGColor,
                   (id)[UIColor colorWithWhite:1 alpha:0.0].CGColor ];
  mask.locations = @[ @0, @0.25, @0.5, @0.75, @1 ];
  edge.mask = mask;
  [container.layer addSublayer:edge];
  return edge;
}

// Colours of one edge's cells as gradient stops. `from`/`span` map the cells onto the strip's length (points).
static void GVSetGlowEdge(CAGradientLayer *edge, int index, CGRect frame, BOOL horizontal, CGFloat from, CGFloat span,
                          CGFloat length, CGPoint maskStart, CGPoint maskEnd, float strength) {
  edge.frame = frame;
  CAGradientLayer *mask = (CAGradientLayer *)edge.mask;
  mask.frame = edge.bounds;
  mask.startPoint = maskStart;
  mask.endPoint = maskEnd;
  edge.opacity = strength;
  edge.startPoint = CGPointMake(0, 0);
  edge.endPoint = horizontal ? CGPointMake(1, 0) : CGPointMake(0, 1);
  NSMutableArray *colors = [NSMutableArray arrayWithCapacity:kGlowCells + 2];
  NSMutableArray *locations = [NSMutableArray arrayWithCapacity:kGlowCells + 2];
  for (int i = -1; i <= kGlowCells; ++i) {
    const int cell = MIN(MAX(i, 0), kGlowCells - 1);
    const float *c = &sGlowSmooth[(index * kGlowCells + cell) * 3];
    [colors addObject:(id)[UIColor colorWithRed:c[0] green:c[1] blue:c[2] alpha:1].CGColor];
    CGFloat at = i < 0 ? 0 : (i >= kGlowCells ? 1 : (from + (i + 0.5) / kGlowCells * span) / length);
    [locations addObject:@(MIN(MAX(at, 0), 1))];
  }
  // Stops must not decrease; the clamp keeps them in order.
  edge.colors = colors;
  edge.locations = locations;
}

static void GVGlowTick(void) {
  UIWindow *gameWindow = GVGameWindow();
  const BOOL wanted = GalaxyVisionSettings.ambientGlow && !GalaxyVisionSettings.bridgeSelected && gameWindow &&
                      galaxypad_engine_started();
  if (!wanted) {
    if (sGlowView || sGlowEngineOn) GVGlowTeardown();
    return;
  }
  if (!sGlowView) {
    UIView *metal = GVFindMetalView(gameWindow);
    UIView *parent = metal.superview;
    if (!metal || !parent) return;  // the engine's Metal view isn't there yet
    if (metal == gameWindow.rootViewController.view || metal == gameWindow) {
      // The picture is the window's own root view: scaling it would shrink the overlay too. Leave the layout alone.
      static BOOL logged;
      if (!logged) { logged = YES; fprintf(stderr, "GalaxyVision glow: the game's Metal view is the root view, glow not available\n"); }
      return;
    }
    sGlowMetalView = metal;
    sGlowView = [[UIView alloc] initWithFrame:parent.bounds];
    sGlowView.backgroundColor = UIColor.blackColor;
    sGlowView.userInteractionEnabled = NO;
    sGlowView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [parent insertSubview:sGlowView belowSubview:metal];
    for (int i = 0; i < 4; ++i) sGlowEdges[i] = GVMakeGlowEdge(sGlowView);
    memset(sGlowSmooth, 0, sizeof sGlowSmooth);
    sGlowSequenceTime = CACurrentMediaTime();
    fprintf(stderr, "GalaxyVision glow: on (metal view %s in %s, frame %.0fx%.0f, window %.0fx%.0f)\n", NSStringFromClass(metal.class).UTF8String,
            NSStringFromClass(parent.class).UTF8String, metal.bounds.size.width, metal.bounds.size.height, parent.bounds.size.width,
            parent.bounds.size.height);
  }
  if (!sGlowEngineOn) {
    galaxypad_engine_glow_enable(1);
    sGlowEngineOn = YES;
  }

  // Colours: newest samples, smoothed (about 0.15 s), fading to black when no new sample arrives (VI black).
  unsigned char rgb[kGlowCells * 4 * 3];
  const uint64_t sequence = galaxypad_engine_glow_colors(rgb);
  const CFTimeInterval now = CACurrentMediaTime();
  if (sequence != sGlowSequence) {
    sGlowSequence = sequence;
    sGlowSequenceTime = now;
  }
  const BOOL stale = sequence == 0 || now - sGlowSequenceTime > 0.7;
  // Trace (testing): one line about every 5 s while the glow is on, so the log shows whether the sampler delivers colours.
  static int sGlowTraceTicks;
  if (++sGlowTraceTicks >= 100) {
    sGlowTraceTicks = 0;
    int sum = 0;
    for (int i = 0; i < kGlowCells * 4 * 3; ++i) sum += rgb[i];
    fprintf(stderr, "GalaxyVision glow: samples %llu, last sample %.1f s ago, mean colour %d/255, inner picture %.0fx%.0f%s\n",
            (unsigned long long)sequence, now - sGlowSequenceTime, sum / (kGlowCells * 4 * 3), sGlowMetalView.frame.size.width,
            sGlowMetalView.frame.size.height, stale ? " (no samples: fading to black)" : "");
  }
  for (int i = 0; i < kGlowCells * 4 * 3; ++i) {
    const float target = stale ? 0.0f : rgb[i] / 255.0f;
    sGlowSmooth[i] += (target - sGlowSmooth[i]) * 0.35f;
  }

  // Layout: the game scaled about its centre, the glow strips in the border.
  const float strength = GalaxyVisionSettings.glowStrength;
  const CGFloat fraction = 0.03 + 0.09 * GalaxyVisionSettings.glowSize;  // border per side, share of the window
  const CGFloat scale = 1.0 - 2.0 * fraction;
  const CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  if (!CGAffineTransformEqualToTransform(sGlowMetalView.transform, transform)) sGlowMetalView.transform = transform;
  const CGRect bounds = sGlowView.bounds;
  const CGRect inner = sGlowMetalView.frame;  // includes the transform
  const CGFloat W = bounds.size.width, H = bounds.size.height;
  const CGFloat top = CGRectGetMinY(inner), bottom = CGRectGetMaxY(inner);
  const CGFloat left = CGRectGetMinX(inner), right = CGRectGetMaxX(inner);
  GVSetGlowEdge(sGlowEdges[0], 0, CGRectMake(0, 0, W, top), YES, left, inner.size.width, W, CGPointMake(0.5, 1), CGPointMake(0.5, 0), strength);
  GVSetGlowEdge(sGlowEdges[1], 1, CGRectMake(right, top, W - right, inner.size.height), NO, 0, inner.size.height, inner.size.height, CGPointMake(0, 0.5), CGPointMake(1, 0.5), strength);
  GVSetGlowEdge(sGlowEdges[2], 2, CGRectMake(0, bottom, W, H - bottom), YES, left, inner.size.width, W, CGPointMake(0.5, 0), CGPointMake(0.5, 1), strength);
  GVSetGlowEdge(sGlowEdges[3], 3, CGRectMake(0, top, left, inner.size.height), NO, 0, inner.size.height, inner.size.height, CGPointMake(1, 0.5), CGPointMake(0, 0.5), strength);
  [CATransaction commit];
}

static void GVStartGlow(void) {
  if (sGlowTimer) return;
  sGlowTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) { GVGlowTick(); }];
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
  if (GalaxyVisionSettings.bridgeSelected) GVStartStereo();
  GVStartFPSCounter();
  GVStartGlow();
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
