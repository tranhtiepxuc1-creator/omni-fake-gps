THEOS = /Users/runner/theos
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OmniFakeGPS
OmniFakeGPS_FILES = Tweak.x
OmniFakeGPS_FRAMEWORKS = CoreLocation UIKit

include $(THEOS)/makefiles/tweak.mk
