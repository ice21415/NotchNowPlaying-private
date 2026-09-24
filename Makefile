.PHONY: clean package

clean:
	$(MAKE) -C BacklightFlowProbe clean

package:
	$(MAKE) -C BacklightFlowProbe package
	mkdir -p build-packages
	cp build-packages-backlight-flow-probe/*.deb build-packages/
