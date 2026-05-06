# ShortcutHUD — keyboard-shortcut cheat-sheet HUD.
#
# Release pipeline delegated to the shared `release.mk` from
# PerpetualBeta/jorvik-release. SPM project, embedded Sparkle,
# dual-ship (.zip + .pkg).

BUNDLE_NAME      := ShortcutHUD
BUNDLE_TYPE      := app
PRODUCT_NAME     := ShortcutHUD.app
BUNDLE_ID        := cc.jorviksoftware.ShortcutHUD
BUILD_SYSTEM     := spm
SPM_PRODUCT      := ShortcutHUD

PACKAGE_TYPE     := zip
ALSO_SHIP_PKG    := true
EMBEDDED_FRAMEWORKS := Sparkle
ENTITLEMENTS     := ShortcutHUD.entitlements

include ../jorvik-release/release.mk
