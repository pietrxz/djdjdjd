#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

// Four 1.90.0 managed entries use prepared static-inline hooks. These observers retain the
// original game calls and iterator results; they do not fabricate network replies.
// Metadata method pointers stay unchanged. Original calls use the saved static
// trampolines. Installation pauses peer threads through validation/commit/rollback. Residual
// routes after an incomplete rollback forward originals without observing.
typedef void (*EzwinClientFrameOriginal)(uintptr_t,uintptr_t);
typedef void (*EzwinClientBeginOriginal)(uintptr_t,uintptr_t);
typedef bool (*EzwinClientIteratorOriginal)(uintptr_t,uintptr_t);
bool EzwinInstallClientCallbacks(uintptr_t unityBase);
NSDictionary *EzwinClientCallbackStatus(void);
