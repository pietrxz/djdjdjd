#pragma once
#include <mach/mach.h>
#include <stdint.h>
#include <stdbool.h>

typedef struct { uintptr_t target, replacement; } EzwinHardwareRoute;
bool EzwinRedirectHardwareState(const EzwinHardwareRoute *routes, size_t count,
    const uint32_t *oldState, uint32_t oldCount, uint32_t *newState, uint32_t *newCount);
bool EzwinHandleHardwareMessage(const mach_msg_header_t *request, mach_msg_header_t *reply,
    size_t replyCapacity, const EzwinHardwareRoute *routes, size_t count);
kern_return_t EzwinInstallHardwareRoutes(const EzwinHardwareRoute *routes, size_t count);
