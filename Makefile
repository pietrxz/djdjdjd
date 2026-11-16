TWEAK_NAME = Ezwin
Ezwin_FILES = $(shell find src -type f \( -name '*.mm' -o -name '*.m' -o -name '*.xm' -o -name '*.cpp' \))
Ezwin_CFLAGS = -fobjc-arc -std=c++17 -Wno-error -Wno-nontrivial-memcall -Wno-nontrivial-memaccess -Wno-uninitialized-const-pointer -I src -I src/core -I src/features -I src/graphics -I src/hooks -I src/legacy -I src/unity -I src/ui -I src/imgui
Ezwin_LDFLAGS = -lsubstrate -framework UIKit -framework Foundation -framework Metal -framework MetalKit -framework QuartzCore -framework DeviceCheck -framework Security

TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
