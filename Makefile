.PHONY: clean package

clean:
	$(MAKE) -C BacklightFlowProbe clean THEOS_PACKAGE_SCHEME=roothide

package:
	$(MAKE) -C BacklightFlowProbe package THEOS_PACKAGE_SCHEME=roothide THEOS_PACKAGE_DIR=../build-packages
