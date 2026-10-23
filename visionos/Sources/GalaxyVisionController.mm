// SPDX-License-Identifier: GPL-3.0-or-later
#import "GalaxyVisionController.h"
#import "GalaxyVisionSettings.h"
#import "GalaxyVisionStereoEngine.h"
#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <algorithm>
#include <cmath>

// Bit layout of galaxypad::Button (apple/shared/GalaxyPadInput.h). The engine routes these to the
// Wii Remote + Nunchuk: A=A, B=B (star bits / menu back), C=Nunchuk C (camera), Z=Nunchuk Z,
// Spin=Wii Remote shake (spin, pick up/throw, vines).
enum : uint32_t {
  kA = 1u << 0, kB = 1u << 1, kC = 1u << 2, kZ = 1u << 3, kPlus = 1u << 4, kMinus = 1u << 5,
  kSpin = 1u << 6, kUp = 1u << 7, kDown = 1u << 8, kLeft = 1u << 9, kRight = 1u << 10,
  kHome = 1u << 13,
};

// Same dead zone / rescale as apple/shared/GalaxyPadControllerInput.h.
static float Axis(float v) {
  if (!std::isfinite(v)) return 0;
  v = std::clamp(v, -1.f, 1.f);
  const float dz = 0.15f;
  return std::abs(v) <= dz ? 0 : std::copysign((std::abs(v) - dz) / (1 - dz), v);
}

static BOOL IsN64(GCController *c) {
  NSString *cat = c.productCategory ?: @"";
  NSString *name = c.vendorName ?: @"";
  return [cat rangeOfString:@"N64" options:NSCaseInsensitiveSearch].location != NSNotFound ||
         [name rangeOfString:@"N64" options:NSCaseInsensitiveSearch].location != NSNotFound ||
         [name rangeOfString:@"Nintendo 64" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// Nudge repeat: first press moves a fixed step, holding past kHoldDelay moves continuously and
// accelerates from kNudgeMin to kNudgeMax viewport-widths per second over kRamp seconds.
static const float kNudgeStep = 0.035f;
static const double kHoldDelay = 0.25;
static const double kRamp = 1.0;
static const float kNudgeMin = 0.30f, kNudgeMax = 1.20f;
static const float kStickPointerSpeed = 1.2f;  // viewport widths per second at full deflection

@implementation GalaxyVisionController {
  NSTimer *_timer;
  uint32_t _lastButtons;
  float _lastX, _lastY, _lastPX, _lastPY;
  int _lastPV;
  BOOL _engineSettingsApplied;
  // pointer state, 0..1 top-left origin
  float _px, _py;
  BOOL _pointerShown;
  CFTimeInterval _lastTime;
  // edge detection
  BOOL _recenterHeld, _captureHeld;
  // N64 C-button nudging: -1/0/1 per axis and when each started
  int _nudgeDirX, _nudgeDirY;
  CFTimeInterval _nudgeStartX, _nudgeStartY;
  // gyro
  GCController *_motionOwner;
  float _lastLean;  // last tilt sent to the engine (Ray surfing)
  int _lastSteering;
  // options shortcut: R1/RB press (PS/Xbox pads), or Start + Capture held (N64 pad)
  BOOL _r1Held;
  CFTimeInterval _comboStart;
  BOOL _comboFired;
  BOOL _suspended;
}

- (BOOL)inputSuspended { return _suspended; }
- (void)setInputSuspended:(BOOL)suspended {
  if (suspended == _suspended) return;
  _suspended = suspended;
  // Resuming with the shortcut buttons still down must not reopen the overlay: wait for release.
  _comboStart = 0;
  _comboFired = YES;
  _r1Held = YES;
  _lastButtons = ~0u;  // force the next poll to send the current state
  if (suspended) galaxypad_engine_input(0, 0, 0, 0, -1.0f, -1.0f);
}

- (void)applyDisplaySettingsNow {
  _engineSettingsApplied = NO;
  [self applyEngineSettings];
  if (GalaxyVisionSettings.bridgeSelected) [GVStereoEngine applySavedSettings];  // live depth / convergence
}

+ (instancetype)shared {
  static GalaxyVisionController *c;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ c = [[GalaxyVisionController alloc] init]; });
  return c;
}

- (instancetype)init {
  if ((self = [super init])) { _px = _py = 0.5f; _lastPX = _lastPY = -1; }
  return self;
}

- (void)start {
  if (_timer) return;
  _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0 target:self selector:@selector(poll) userInfo:nil repeats:YES];
  [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

// Applies Display settings once, as soon as the game runs (these engine calls need the game's
// settings loaded). Aspect ratio is stored by the engine and takes full effect on the next start.
- (void)applyEngineSettings {
  if (_engineSettingsApplied) return;
  _engineSettingsApplied = YES;
  const NSInteger aspect = GalaxyVisionSettings.aspect;
  if (aspect == 0 || aspect == 1) {
    int now = galaxypad_engine_widescreen(-1);
    int result = galaxypad_engine_widescreen((int)aspect);
    NSLog(@"GalaxyVision: aspect ratio %d -> %d", now, result);
  }
  // Stereoscopic window: the engine owns the frame pacing and turns Smooth Motion off while it is on.
  if (GalaxyVisionSettings.bridgeSelected) return;
  if (GalaxyVisionSettings.smoothMotion) {
    NSLog(@"GalaxyVision: smooth motion -> %d", galaxypad_engine_smooth_motion(1));
  } else if (galaxypad_engine_smooth_motion(-1)) {
    galaxypad_engine_smooth_motion(0);
  }
}

- (void)recenter { _px = _py = 0.5f; _pointerShown = (GalaxyVisionSettings.pointerMode != 2); }
- (void)showPointer { if (GalaxyVisionSettings.pointerMode != 2) _pointerShown = YES; }

- (void)poll {
  if (!galaxypad_engine_started()) return;
  [self applyEngineSettings];
  if (_suspended) return;  // options overlay up: the game gets nothing

  const CFTimeInterval now = CACurrentMediaTime();
  const float dt = _lastTime > 0 ? (float)std::clamp(now - _lastTime, 0.0, 0.05) : 0.f;
  _lastTime = now;

  // Trace when the game starts or stops steering by tilt (Star Ball / Ray surfing), to tell "the game
  // never asked for tilt" from "it asked and the input did not turn it".
  const int steering = galaxypad_engine_steering();
  if (steering != _lastSteering) {
    fprintf(stderr, "galaxyvision: tilt steering %s\n", steering == 2 ? "Ray surfing" : steering == 1 ? "Star Ball" : "off");
    _lastSteering = steering;
  }

  GCController *controller = nil;
  GCExtendedGamepad *pad = nil;
  for (GCController *c in GCController.controllers) {
    if (c.extendedGamepad) { controller = c; pad = c.extendedGamepad; break; }
  }
  const BOOL n64 = controller && IsN64(controller);
  const BOOL bJumps = GalaxyVisionSettings.bButtonJumps;
  const float sens = GalaxyVisionSettings.pointerSensitivity;
  const NSInteger pointerMode = GalaxyVisionSettings.pointerMode;

  uint32_t buttons = 0;
  float x = 0, y = 0;
  BOOL recenterNow = NO;
  if (pad) {
    // --- Shared ---
    x = pad.leftThumbstick.xAxis.value;
    y = pad.leftThumbstick.yAxis.value;  // y up, as the engine expects
    if (pad.dpad.up.pressed) buttons |= kUp;
    if (pad.dpad.down.pressed) buttons |= kDown;
    if (pad.dpad.left.pressed) buttons |= kLeft;
    if (pad.dpad.right.pressed) buttons |= kRight;
    if (pad.buttonMenu.pressed) buttons |= kPlus;  // Options / Start
    if (pad.buttonHome.pressed) buttons |= kHome;
    if (pad.buttonA.pressed) buttons |= kA;        // Cross / A: jump, swim, confirm, pull stars
    if (pad.buttonB.pressed) buttons |= bJumps ? kA : kB;  // Circle / B (see settings)
    if (pad.leftTrigger.value > 0.3f || pad.leftTrigger.pressed) buttons |= kZ;  // L2 / N64 Z

    if (n64) {
      [self sendLean:0.f];  // no motion on the N64 pad: the stick steers surfing
      // Switch Online N64 pad: C buttons arrive as the right thumbstick's digital directions.
      if (pad.leftShoulder.pressed) buttons |= kC;      // L: camera reset
      if (pad.rightShoulder.pressed) buttons |= kSpin;  // R: spin / pick up / throw
      const BOOL capture = [self captureButtonPressed:controller];
      if (capture && !_captureHeld) recenterNow = YES;  // Capture: recenter pointer
      _captureHeld = capture;
      if (pad.buttonOptions.pressed && !capture) buttons |= kMinus;  // if the pad has a separate Minus
      const BOOL cu = pad.rightThumbstick.up.pressed, cd = pad.rightThumbstick.down.pressed;
      const BOOL cl = pad.rightThumbstick.left.pressed, cr = pad.rightThumbstick.right.pressed;
      // C-down shoots star bits; hold Capture to use C-down for nudging the pointer down instead.
      const BOOL cdNudge = cd && capture;
      if (cd && !capture) { buttons |= kB; [self showPointer]; }
      const int dirX = (cr ? 1 : 0) - (cl ? 1 : 0);
      const int dirY = ((cdNudge ? 1 : 0) - (cu ? 1 : 0));
      [self nudgeX:dirX y:dirY now:now sens:sens];
    } else {
      // DualSense / DualShock / Xbox-style pads.
      if (pad.buttonX.pressed || pad.buttonY.pressed) buttons |= kSpin;  // Square/Triangle
      if (pad.rightTrigger.value > 0.3f || pad.rightTrigger.pressed) { buttons |= kB; [self showPointer]; }  // R2: shoot
      if (pad.leftShoulder.pressed) buttons |= kC;   // L1: camera reset
      if (pad.buttonOptions.pressed) buttons |= kMinus;  // Create / Share / View
      const BOOL rc = pad.leftThumbstickButton.pressed ||
                      pad.rightThumbstickButton.pressed;  // L3 / R3 recenter pointer (R1 opens the options overlay)
      if (rc && !_recenterHeld) recenterNow = YES;
      _recenterHeld = rc;
      // Right stick: analog pointer.
      const float rx = Axis(pad.rightThumbstick.xAxis.value), ry = Axis(pad.rightThumbstick.yAxis.value);
      if (rx != 0 || ry != 0) {
        [self showPointer];
        _px = std::clamp(_px + rx * dt * kStickPointerSpeed * sens, 0.f, 1.f);
        _py = std::clamp(_py - ry * dt * kStickPointerSpeed * sens, 0.f, 1.f);
      }
      [self pollGyro:controller dt:dt sens:sens];
    }
  } else {
    _recenterHeld = _captureHeld = NO;
    [self sendLean:0.f];
    _r1Held = NO;
    _nudgeDirX = _nudgeDirY = 0;
  }
  if (recenterNow) [self recenter];

  // Options overlay shortcut.
  // Only while the game's own pause menu is up (galaxypad_engine_game_paused), like SM64-Vision.
  //  - PlayStation / Xbox pads: a press of the right shoulder (R1 / RB). Edge-triggered, so holding
  //    it does not reopen the overlay. R1 is never forwarded to the game. Options stays Plus (pause).
  //  - N64 pad: R is spin, so Start + Capture held for 0.5 s.
  const BOOL gamePaused = galaxypad_engine_game_paused() != 0;
  if (pad && !n64) {
    const BOOL r1 = pad.rightShoulder.pressed;
    const BOOL fire = r1 && !_r1Held && gamePaused;
    _r1Held = r1;
    if (fire && self.onOptionsRequested) { self.onOptionsRequested(); return; }
  } else {
    _r1Held = NO;
  }
  if (pad && n64 && gamePaused && pad.buttonMenu.pressed && _captureHeld) {
    buttons &= ~(kPlus | kMinus);  // do not feed the combo itself to the game
    if (_comboStart == 0) _comboStart = now;
    if (!_comboFired && now - _comboStart >= 0.5) {
      _comboFired = YES;
      if (self.onOptionsRequested) { self.onOptionsRequested(); return; }
    }
  } else {
    _comboStart = 0;
    _comboFired = NO;
  }

  const BOOL visible = pointerMode == 1 ? YES : (pointerMode == 2 ? NO : _pointerShown);
  const int pv = visible ? 1 : 0;
  if (buttons == _lastButtons && x == _lastX && y == _lastY && pv == _lastPV &&
      (!pv || (_px == _lastPX && _py == _lastPY)))
    return;
  _lastButtons = buttons; _lastX = x; _lastY = y; _lastPV = pv; _lastPX = _px; _lastPY = _py;
  galaxypad_engine_input(buttons, x, y, pv, pv ? _px : -1.0f, pv ? _py : -1.0f);
}

// N64 "Capture" button: the pad's Share button in the physical profile, else buttonOptions.
- (BOOL)captureButtonPressed:(GCController *)controller {
  GCControllerButtonInput *share = controller.physicalInputProfile.buttons[GCInputButtonShare];
  if (share) return share.pressed;
  return controller.extendedGamepad.buttonOptions.pressed;
}

// C-button nudges: a tap moves one step; holding past kHoldDelay moves continuously, accelerating.
- (void)nudgeX:(int)dirX y:(int)dirY now:(CFTimeInterval)now sens:(float)sens {
  auto step = [&](int dir, int &prev, CFTimeInterval &start, float &pos, float sign) {
    if (dir != prev) {
      prev = dir;
      start = now;
      if (dir != 0) { [self showPointer]; pos = std::clamp(pos + sign * dir * kNudgeStep * sens, 0.f, 1.f); }
    } else if (dir != 0) {
      const double held = now - start;
      if (held > kHoldDelay) {
        const float ramp = (float)std::clamp((held - kHoldDelay) / kRamp, 0.0, 1.0);
        const float speed = kNudgeMin + (kNudgeMax - kNudgeMin) * ramp;
        pos = std::clamp(pos + sign * dir * speed * sens * (1.0f / 60.0f), 0.f, 1.f);
      }
    }
  };
  step(dirX, _nudgeDirX, _nudgeStartX, _px, 1.f);
  step(dirY, _nudgeDirY, _nudgeStartY, _py, 1.f);
}

- (void)sendLean:(float)lean {
  if (lean == _lastLean) return;
  _lastLean = lean;
  galaxypad_engine_set_tilt(lean);
}

// Optional gyro aiming for pads with motion (DualSense / DualShock). Adds to the pointer.
// Axes: GCMotion rotation rate, z = yaw (turn left/right), x = pitch. Invert in the launcher if needed.
// Also (default on) the pad's lean for Ray surfing, see below.
- (void)pollGyro:(GCController *)controller dt:(float)dt sens:(float)sens {
  GCMotion *motion = controller.motion;
  const BOOL wantAim = GalaxyVisionSettings.gyroAim;
  const BOOL wantTilt = GalaxyVisionSettings.tiltSteer;
  if (_motionOwner && _motionOwner != controller) { _motionOwner.motion.sensorsActive = NO; _motionOwner = nil; }
  if ((!wantAim && !wantTilt) || !motion || !motion.hasRotationRate) {
    if (_motionOwner) { _motionOwner.motion.sensorsActive = NO; _motionOwner = nil; }
    [self sendLean:0.f];
    return;
  }
  if (!_motionOwner) { motion.sensorsActive = YES; _motionOwner = controller; return; }

  // Lean the pad left or right (like a steering wheel) to steer Ray surfing. The engine only uses it
  // while the game steers by tilt, and the left stick still works. Gravity in the pad's own frame:
  // x points to the pad's right, so leaning right (right side down) gives positive x.
  float lean = 0.f;
  if (wantTilt && motion.hasGravityAndUserAcceleration) {
    const double gx = std::clamp(motion.gravity.x, -1.0, 1.0);
    const float angle = (float)std::asin(std::abs(gx)) * (180.f / (float)M_PI);
    const float mag = std::clamp((angle - 6.f) / (25.f - 6.f), 0.f, 1.f);  // 6 deg dead zone, full at 25 deg
    lean = (gx < 0 ? -mag : mag) * (GalaxyVisionSettings.tiltInvert ? -1.f : 1.f);
  }
  [self sendLean:lean];

  if (!wantAim) return;
  GCRotationRate r = motion.rotationRate;
  auto quiet = [](double v) { return std::abs(v) < 0.012 ? 0.0 : std::clamp(v, -12.0, 12.0); };
  const double yaw = quiet(r.z), pitch = quiet(r.x);
  if (yaw == 0 && pitch == 0) return;
  const float gain = std::clamp(sens, 0.5f, 2.0f);
  const float sx = GalaxyVisionSettings.gyroInvertX ? -1.f : 1.f;
  const float sy = GalaxyVisionSettings.gyroInvertY ? -1.f : 1.f;
  [self showPointer];
  _px = std::clamp(_px - sx * (float)yaw * dt * gain, 0.f, 1.f);
  _py = std::clamp(_py - sy * (float)pitch * dt * gain, 0.f, 1.f);
}
@end
