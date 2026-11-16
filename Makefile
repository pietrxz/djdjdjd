TWEAK_NAME = Ezwin
Ezwin_FILES = $(shell find src -type f \( -name '*.mm' -o -name '*.m' -o -name '*.xm' \))
Ezwin_CFLAGS = -fobjc-arc -I src -I src/core -I src/features -I src/graphics -I src/hooks -I src/legacy -I src/unity -I src/ui
Ezwin_LDFLAGS = -lsubstrate -framework UIKit -framework Foundation -framework Metal -framework MetalKit -framework QuartzCore -framework DeviceCheck -framework Security

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
