// SPDX-License-Identifier: GPL-3.0-or-later
// GalaxyVision: visionOS shell for GalaxyPadEngine.framework.
//
// If game data exists at Application Support/GalaxyPad/GameData/RMGE01 (sys/main.dol),
// the process is handed to the engine, whose SDL3 window is the flat virtual screen.
// Otherwise a placeholder import screen is shown (import is not implemented yet).
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "GalaxyVisionController.h"

static NSURL *GVBase(void) {
  NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                         inDomains:NSUserDomainMask].firstObject;
  return [support URLByAppendingPathComponent:@"GalaxyPad" isDirectory:YES];
}
static NSURL *GVGameDir(void) { return [GVBase() URLByAppendingPathComponent:@"GameData/RMGE01" isDirectory:YES]; }

@interface GVPlaceholderController : UIViewController <UIDocumentPickerDelegate>
@end
@implementation GVPlaceholderController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.systemBackgroundColor;
  UILabel *label = [[UILabel alloc] init];
  label.numberOfLines = 0;
  label.textAlignment = NSTextAlignmentCenter;
  label.text = @"GalaxyVision\n\nNo game data found.\nPlace an extracted Super Mario Galaxy (RMGE01) folder in\nApplication Support/GalaxyPad/GameData/RMGE01\nor use Import (placeholder).";
  UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
  [button setTitle:@"Import game data…" forState:UIControlStateNormal];
  [button addTarget:self action:@selector(importTapped) forControlEvents:UIControlEventTouchUpInside];
  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[label, button]];
  stack.axis = UILayoutConstraintAxisVertical;
  stack.spacing = 24;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    [stack.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor multiplier:0.9],
  ]];
}
- (void)importTapped {
  UIDocumentPickerViewController *picker =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ]];
  picker.delegate = self;
  [self presentViewController:picker animated:YES completion:nil];
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
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
  const char *host = getenv("GALAXYPAD_ENGINE_HOST");
  if (host && strcmp(host, "1") == 0) {
    // Engine mode: hand the scene to the engine's SDL scene delegate.
    NSObject *app = (NSObject *)UIApplication.sharedApplication.delegate;
    id<UIWindowSceneDelegate> engine = [[app.class alloc] init];
    scene.delegate = engine;
    [engine scene:scene willConnectToSession:session options:options];
    [GalaxyVisionController.shared start];
    return;
  }
  if (![scene isKindOfClass:UIWindowScene.class]) return;
  self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
  self.window.rootViewController = [[GVPlaceholderController alloc] init];
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
    BOOL haveGame = [files fileExistsAtPath:[game URLByAppendingPathComponent:@"sys/main.dol"].path] &&
                    [files createDirectoryAtURL:user withIntermediateDirectories:YES attributes:nil error:nil];
    if (haveGame) {
      setenv("GALAXYPAD_ENGINE_HOST", "1", 1);
      NSArray<NSString *> *args = @[ @"GalaxyVision", @"--disc", game.path, @"--user", user.path ];
      char **engineArgv = (char **)calloc(args.count + 1, sizeof(char *));
      for (NSUInteger i = 0; i < args.count; ++i) engineArgv[i] = strdup(args[i].fileSystemRepresentation);
      return galaxypad_engine_main((int)args.count, engineArgv);
    }
    return UIApplicationMain(argc, argv, nil, NSStringFromClass(GalaxyVisionAppDelegate.class));
  }
}
