// SPDX-License-Identifier: GPL-3.0-or-later
#import "GalaxyVisionController.h"
#import <GameController/GameController.h>
#import <UIKit/UIKit.h>

// Bit layout of galaxypad::Button (apple/shared/GalaxyPadInput.h).
enum : uint32_t {
  kA = 1u << 0, kB = 1u << 1, kC = 1u << 2, kZ = 1u << 3, kPlus = 1u << 4, kMinus = 1u << 5,
  kSpin = 1u << 6, kUp = 1u << 7, kDown = 1u << 8, kLeft = 1u << 9, kRight = 1u << 10,
  kHome = 1u << 13,
};

@implementation GalaxyVisionController {
  NSTimer *_timer;
  uint32_t _lastButtons;
  float _lastX, _lastY;
}

+ (instancetype)shared {
  static GalaxyVisionController *c;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ c = [[GalaxyVisionController alloc] init]; });
  return c;
}

- (void)start {
  if (_timer) return;
  _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0 target:self selector:@selector(poll) userInfo:nil repeats:YES];
  [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)poll {
  if (!galaxypad_engine_started()) return;
  GCExtendedGamepad *pad = nil;
  for (GCController *c in GCController.controllers) {
    if (c.extendedGamepad) { pad = c.extendedGamepad; break; }
  }
  uint32_t buttons = 0;
  float x = 0, y = 0;
  if (pad) {
    if (pad.buttonA.pressed) buttons |= kA;
    if (pad.buttonB.pressed) buttons |= kB;
    if (pad.buttonX.pressed) buttons |= kSpin;
    if (pad.buttonY.pressed) buttons |= kC;
    if (pad.leftShoulder.pressed || pad.leftTrigger.pressed) buttons |= kZ;
    if (pad.rightShoulder.pressed || pad.rightTrigger.pressed) buttons |= kSpin;
    if (pad.buttonMenu.pressed) buttons |= kPlus;
    if (pad.buttonOptions.pressed) buttons |= kMinus;
    if (pad.buttonHome.pressed) buttons |= kHome;
    if (pad.dpad.up.pressed) buttons |= kUp;
    if (pad.dpad.down.pressed) buttons |= kDown;
    if (pad.dpad.left.pressed) buttons |= kLeft;
    if (pad.dpad.right.pressed) buttons |= kRight;
    x = pad.leftThumbstick.xAxis.value;
    y = pad.leftThumbstick.yAxis.value;  // y up, as the engine expects
  }
  if (buttons == _lastButtons && x == _lastX && y == _lastY) return;
  _lastButtons = buttons; _lastX = x; _lastY = y;
  galaxypad_engine_input(buttons, x, y, 0, -1.0f, -1.0f);
}
@end
