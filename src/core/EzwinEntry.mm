#include "ui/EzwinMenu.h"

__attribute__((constructor)) static void EzwinMenuLoaded(void) {
    @autoreleasepool { EzwinStartRuntime(); }
    EzwinStartOverlay();
}
