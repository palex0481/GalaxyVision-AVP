// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// GameController -> GalaxyPadEngine.framework. Polls the first extended gamepad
// at 60 Hz on the main thread and calls galaxypad_engine_input().
@interface GalaxyVisionController : NSObject
+ (instancetype)shared;
- (void)start;
@end

// GalaxyPadEngine.framework exports (ref/galaxypad-engine native/app/engine_entry.mm).
extern "C" {
int galaxypad_engine_main(int argc, char *argv[]);
void galaxypad_engine_input(uint32_t buttons, float stickX, float stickY, int pointerVisible,
                            float pointerX, float pointerY);
int galaxypad_engine_started(void);
void galaxypad_engine_pause(int paused);
void galaxypad_engine_set_volume(float volume);
int galaxypad_engine_widescreen(int value);
int galaxypad_engine_smooth_motion(int value);
}
