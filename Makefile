.PHONY: notarize

# Mostly cribbed from https://gist.github.com/shpakovski/31067c499d69d1d4180856be3d67e5a5.

# XCS_ARCHIVE is an environment variable typically set by Xcode Server.
# We're not using Xcode server so I'm hardcoding it here.
#
# https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/xcode_guide-continuous_integration/EnvironmentVariableReference.html
XCS_ARCHIVE := "buildArchive/EFIgy.xcarchive"

EXPORT_PATH := $(XCS_ARCHIVE)/Submissions
BUNDLE_APP := $(EXPORT_PATH)/EFIgy.app
BUNDLE_ZIP := $(EXPORT_PATH)/EFIgy.zip
UPLOAD_INFO_PLIST := $(EXPORT_PATH)/UploadInfo.plist
REQUEST_INFO_PLIST := $(EXPORT_PATH)/RequestInfo.plist
AUDIT_INFO_JSON := $(EXPORT_PATH)/AuditInfo.json
PRODUCT_DIR := $(XCS_ARCHIVE)/Products/Applications
PRODUCT_APP := $(PRODUCT_DIR)/EFIgy.app
PRIMARY_BUNDLE_ID := "com.duosecurity.EFIgy"
CODE_SIGN_IDENTITY_NAME := "Developer ID Application: Duo Security, Inc. (FNN8Z5JMFP)"

define notify
	@ /usr/bin/osascript -e 'display notification $2 with title $1'
endef

define wait_while_in_progress
	while true; do \
		/usr/bin/xcrun altool --notarization-info `/usr/libexec/PlistBuddy -c "Print :notarization-upload:RequestUUID" $(UPLOAD_INFO_PLIST)` -u $(DEVELOPER_USERNAME) -p $(DEVELOPER_PASSWORD) --output-format xml > $(REQUEST_INFO_PLIST) ;\
		if [ "`/usr/libexec/PlistBuddy -c "Print :notarization-info:Status" $(REQUEST_INFO_PLIST)`" != "in progress" ]; then \
			break ;\
		fi ;\
		/usr/bin/osascript -e 'display notification "Zzz..." with title "Notarization"' ;\
		sleep 60 ;\
	done
endef

archive:
	$(call notify, "Archiving", "Creating archive...")
	xcodebuild -workspace EFIgy.xcworkspace -scheme EFIgy -configuration Release clean archive -archivePath "$XCS_ARCHIVE" CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO

export-archive:
	$(call notify, "Archiving", "Exporting an archive...")
	/usr/bin/xcrun xcodebuild -exportArchive -archivePath $(XCS_ARCHIVE) -exportPath $(EXPORT_PATH) -exportOptionsPlist ./ExportOptions.plist -IDEPostProgressNotifications=YES -DVTAllowServerCertificates=YES -DVTProvisioningUseServerAccounts=YES -configuration Release

codesign:
	$(call notify, "Code Signing", "Code signing Sparkle AutoUpdate. Please enter PIN and touch the security key...")
	codesign --timestamp --verbose --force --deep -o runtime --sign $(CODE_SIGN_IDENTITY_NAME) $(BUNDLE_APP)/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app
	$(call notify, "Code Signing", "Code signing app. Please enter PIN and touch the security key...")
	codesign --timestamp --verbose --deep -o runtime -s $(CODE_SIGN_IDENTITY_NAME) -fv $(BUNDLE_APP)

notarize:
	$(call notify, "Notarization", "Building a ZIP archive...")
	/usr/bin/ditto -c -k --rsrc --keepParent $(BUNDLE_APP) $(BUNDLE_ZIP)
	$(call notify, "Notarization", "Uploading for notarization...")
	/usr/bin/xcrun altool --notarize-app --primary-bundle-id $(PRIMARY_BUNDLE_ID) -u $(DEVELOPER_USERNAME) -p $(DEVELOPER_PASSWORD) -f $(BUNDLE_ZIP) --output-format xml > $(UPLOAD_INFO_PLIST)
	sleep 2
	$(call notify, "Notarization", "Waiting while notarized...")
	/usr/bin/xcrun altool --notarization-info `/usr/libexec/PlistBuddy -c "Print :notarization-upload:RequestUUID" $(UPLOAD_INFO_PLIST)` -u $(DEVELOPER_USERNAME) -p $(DEVELOPER_PASSWORD) --output-format xml > $(REQUEST_INFO_PLIST)
	$(call wait_while_in_progress)
	$(call notify, "Notarization", "Downloading log file...")
	/usr/bin/curl -o $(AUDIT_INFO_JSON) `/usr/libexec/PlistBuddy -c "Print :notarization-info:LogFileURL" $(REQUEST_INFO_PLIST)`
	if [ `/usr/libexec/PlistBuddy -c "Print :notarization-info:Status" $(REQUEST_INFO_PLIST)` != "success" ]; then \
		false; \
	fi
	$(call notify, "Notarization", "Stapling...")
	/usr/bin/xcrun stapler staple $(BUNDLE_APP)
	$(call notify, "Notarization", "Replacing original product...")
	rm -rf $(PRODUCT_APP)
	mv $(BUNDLE_APP) $(PRODUCT_DIR)/
	$(call notify, "Notarization", "✅ Done!")
