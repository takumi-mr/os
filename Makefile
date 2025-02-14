-include config.mk

BOARD ?= rpi4
ARCH ?= arm
PLATFORM ?= v2-hdmi
SUFFIX ?=
STAGES ?= __init__ os pikvm-repo watchdog rootdelay ro no-audit pikvm __cleanup__

HOSTNAME ?= pikvm
LOCALE ?= en_US
TIMEZONE ?= Europe/Moscow
#REPO_URL ?= http://mirror.yandex.ru/archlinux-arm
REPO_URL ?= http://de3.mirror.archlinuxarm.org
BUILD_OPTS ?=
BUILDER_URL ?= https://github.com/mdevaev/pi-builder
PIKVM_REPO_URL ?= https://pikvm.org/repos
PIKVM_REPO_KEY ?= 912C773ABBD1B584

ROOT_PASSWD ?= root
WEBUI_ADMIN_PASSWD ?= admin
IPMI_ADMIN_PASSWD ?= admin

SUDO ?= sudo

CARD ?= /dev/mmcblk0
IMAGE_FILE ?= images/$(PLATFORM)-$(BOARD)-$(ARCH)$(if $(UBOOT),-$(UBOOT),).img

DEPLOY_USER ?= root


# =====
SHELL = /usr/bin/env bash
_BUILDER_DIR = ./.pi-builder/$(PLATFORM)-$(BOARD)$(SUFFIX)

define fetch_version
$(shell curl --silent "$(PIKVM_REPO_URL)/$(BOARD)-$(ARCH)/latest/$(1)")
endef


# =====
all:
	@ echo "Available commands:"
	@ echo "    make                # Print this help"
	@ echo "    make os             # Build OS with your default config"
	@ echo "    make shell          # Run Arch-ARM shell"
	@ echo "    make install        # Install rootfs to partitions on $(CARD)"
	@ echo "    make image          # Create a binary image for burning outside of make install"
	@ echo "    make scan           # Find all RPi devices in the local network"
	@ echo "    make clean          # Remove the generated rootfs"
	@ echo "    make clean-all      # Remove the generated rootfs and pi-builder toolchain"


shell: $(_BUILDER_DIR)
	$(MAKE) -C $(_BUILDER_DIR) shell


os: $(_BUILDER_DIR)
	rm -rf $(_BUILDER_DIR)/stages/{pikvm,pikvm-otg-console}
	cp -a pikvm pikvm-otg-console $(_BUILDER_DIR)/stages
	cp -a disk-$(if $(findstring v2,$(PLATFORM))$(findstring v3,$(PLATFORM))$(findstring v4,$(PLATFORM)),v2,v0).conf $(_BUILDER_DIR)/disk.conf
	$(MAKE) -C $(_BUILDER_DIR) os \
		NC=$(NC) \
		BUILD_OPTS=' $(BUILD_OPTS) \
			--build-arg PLATFORM=$(PLATFORM) \
			--build-arg VERSIONS=$(call fv,ustreamer)/$(call fv,kvmd)/$(call fv,kvmd-webterm)/$(call fv,kvmd-oled)/$(call fv,kvmd-fan) \
			--build-arg OLED=$(call optbool,$(OLED)) \
			--build-arg FAN=$(call optbool,$(FAN)) \
			--build-arg ROOT_PASSWD=$(ROOT_PASSWD) \
			--build-arg WEBUI_ADMIN_PASSWD=$(WEBUI_ADMIN_PASSWD) \
			--build-arg IPMI_ADMIN_PASSWD=$(IPMI_ADMIN_PASSWD) \
		' \
		PROJECT=pikvm-os-$(PLATFORM)$(SUFFIX) \
		BOARD=$(BOARD) \
		ARCH=$(ARCH) \
		UBOOT=$(UBOOT) \
		STAGES='$(STAGES)' \
		HOSTNAME=$(HOSTNAME) \
		LOCALE=$(LOCALE) \
		TIMEZONE=$(TIMEZONE) \
		REPO_URL=$(REPO_URL) \
		PIKVM_REPO_URL=$(PIKVM_REPO_URL) \
		PIKVM_REPO_KEY=$(PIKVM_REPO_KEY)


$(_BUILDER_DIR):
	git clone --depth=1 $(BUILDER_URL) $(_BUILDER_DIR)


update: $(_BUILDER_DIR)
	cd $(_BUILDER_DIR) && git pull --rebase
	git pull --rebase


install: $(_BUILDER_DIR)
	make -C $(_BUILDER_DIR) install \
		CARD=$(CARD) \
		BOARD=$(BOARD) \
		ARCH=$(ARCH) \
		UBOOT=$(UBOOT) \
		CARD_DATA_FS_TYPE=$(if $(findstring v2-hdmi,$(PLATFORM)),ext4,) \
		CARD_DATA_FS_FLAGS=-m0


scan: $(_BUILDER_DIR)
	$(MAKE) -C $(_BUILDER_DIR) scan


clean: $(_BUILDER_DIR)
	$(MAKE) -C $(_BUILDER_DIR) clean


clean-all:
	- $(MAKE) -C $(_BUILDER_DIR) clean-all
	rm -rf $(_BUILDER_DIR)
	- rmdir `dirname $(_BUILDER_DIR)`


_IMAGE_DATED := $(PLATFORM)-$(BOARD)$(SUFFIX)-$(shell date +%Y%m%d).img
_IMAGE_LATEST := $(PLATFORM)-$(BOARD)$(SUFFIX)-latest.img
image:
	which xz
	mkdir -p images	
	sudo bash -x -c ' \
		dd if=/dev/zero of=$(IMAGE_FILE) bs=512 count=12582912 \
		&& device=`losetup --find --show $(IMAGE_FILE)` \
		&& make install CARD=$$device BOARD=$(BOARD) ARCH=$(ARCH) UBOOT=$(UBOOT)\
		&& losetup -d $$device \
	'
	sudo chown $(shell id -u):$(shell id -g) images/$(_IMAGE_DATED)
	xz -9 --compress images/$(_IMAGE_DATED)
	sha1sum images/$(_IMAGE_DATED).xz | awk '{print $$1}' > images/$(_IMAGE_DATED).xz.sha1
	cd images && ln -sf $(_IMAGE_DATED).xz $(_IMAGE_LATEST).xz
	cd images && ln -sf $(_IMAGE_DATED).xz.sha1 $(_IMAGE_LATEST).xz.sha1


upload:
	rsync -rl --progress images/ $(DEPLOY_USER)@files.pikvm.org:/var/www/files.pikvm.org/images
