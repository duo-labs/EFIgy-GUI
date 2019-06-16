//
//  AppDelegate.m
//  EFIgy
//
//  Created by James Barclay on 10/5/17.
//  Copyright © 2017 Duo Security. All rights reserved.
//

#import "AppDelegate.h"
#import <CommonCrypto/CommonDigest.h>
#include <IOKit/IOKitLib.h>
#import <LetsMove/PFMoveApplication.h>
#import <QuartzCore/QuartzCore.h>

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

static NSString * const kAPIURL = @"https://api.efigy.io";

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    PFMoveToApplicationsFolderIfNecessary();
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    if (![self darkModeEnabled]) {
        _window.backgroundColor = [NSColor whiteColor];
    }

    self.boardID = [[self class] getBoardID];
    self.bootROMVersion = [[self class] getBootROMVersion];
    self.machineModel = [[self class] getMachineModel];
    self.smcVersion = [[self class] getSMCVersion];
    self.osVersion = [[self class] getOSVersion];
    self.buildNumber = [[self class] getBuildNumber];
    self.hashedSysUUID = [[self class] getHashedSysUUID];

    _boardIDLabel.stringValue = self.boardID;
    _bootROMVersionLabel.stringValue = self.bootROMVersion;
    _hardwareVersionLabel.stringValue = self.machineModel;
    _smcVersionLabel.stringValue = self.smcVersion;
    _osVersionLabel.stringValue = self.osVersion;
    _buildNumberLabel.stringValue = self.buildNumber;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

- (BOOL)darkModeEnabled
{
    BOOL darkModeEnabled = NO;

    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"AppleInterfaceStyle"]) {
        darkModeEnabled = YES;
    }

    return darkModeEnabled;
}

+ (NSString *)getBoardID
{
    // IOPlatformExpertDevice : IOService : IORegistryEntry : OSObject
    return [[self class] getIOKitData:@"IOPlatformExpertDevice" withParam:@"board-id"];
}

+ (NSString *)getMachineModel
{
    // IOPlatformExpertDevice : IOService : IORegistryEntry : OSObject
    return [[self class] getIOKitData:@"IOPlatformExpertDevice" withParam:@"model"];
}

+ (NSString *)getBootROMVersion
{
    NSString *param = @"version";
    NSString *path = @"IODeviceTree:/rom";
    CFStringRef parameter = (__bridge CFStringRef)param;
    CFDataRef data;
    io_service_t sv = IORegistryEntryFromPath(kIOMasterPortDefault,
                                              (const char *)[path UTF8String]);
    data = IORegistryEntryCreateCFProperty(sv,
                                           parameter,
                                           kCFAllocatorDefault, 0);
    IOObjectRelease(sv);
    CFIndex bufferLength = CFDataGetLength(data);
    UInt8 *buffer = malloc(bufferLength);
    CFDataGetBytes(data, CFRangeMake(0, bufferLength), (UInt8 *)buffer);

    if (data != NULL) {
        CFRelease(data);
    }

    CFStringRef string = CFStringCreateWithBytes(kCFAllocatorDefault,
                                                 buffer,
                                                 bufferLength,
                                                 kCFStringEncodingUTF8,
                                                 TRUE);
    free(buffer);

    NSString *ret = nil;
    if (string != NULL) {
        NSArray *arr = [(__bridge NSString *)string componentsSeparatedByString:@"."];
        if (arr != nil && [arr count] >= 4) {
            NSString *bootROMVersion = [NSString stringWithFormat:@"%@.%@.%@", arr[0], arr[2], arr[3]];
            ret = [bootROMVersion stringByReplacingOccurrencesOfString:@"\00" withString:@""];
        }
        CFRelease(string);
    }
    
    return ret;
}

+ (NSString *)getSMCVersion
{
    NSString *param = @"smc-version";
    NSString *ioService = @"AppleSMC";
    CFStringRef parameter = (__bridge CFStringRef)param;
    CFStringRef string;
    io_service_t sv = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                  IOServiceMatching((const char *)[ioService UTF8String]));
    string = IORegistryEntryCreateCFProperty(sv,
                                             parameter,
                                             kCFAllocatorDefault, 0);
    IOObjectRelease(sv);

    if (string != NULL) {
        NSString *smcVersion = [(__bridge NSString *)string copy];
        CFRelease(string);
        return [smcVersion stringByReplacingOccurrencesOfString:@"\00" withString:@""];
    }

    return nil;
}

+ (NSString *)getOSVersion
{
    NSProcessInfo *pInfo = [NSProcessInfo processInfo];
    NSString *versionString = [pInfo operatingSystemVersionString];
    NSArray *versionArray = [versionString componentsSeparatedByString:@" "];
    NSString *version = versionArray[1];
    
    return version;
}

+ (NSString *)getBuildNumber
{
    NSProcessInfo *pInfo = [NSProcessInfo processInfo];
    NSString *versionString = [pInfo operatingSystemVersionString];
    NSArray *versionArray = [versionString componentsSeparatedByString:@" "];
    NSString *version = versionArray[3];
    version = [version stringByReplacingOccurrencesOfString:@")" withString:@""];
    
    return version;
}

+ (NSString *)getHashedSysUUID
{
    // TODO: Gross gross gross gross
    NSString *macAddr = [[self class] runCommandAndReturnOutput:@"/usr/bin/python"
                                                       withArgs:@[@"-c", @"from uuid import getnode; print(hex(getnode()))"]];
    
    io_registry_entry_t ioRegistryRoot = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/");
    CFStringRef uuidCf = (CFStringRef)IORegistryEntryCreateCFProperty(ioRegistryRoot, CFSTR(kIOPlatformUUIDKey), kCFAllocatorDefault, 0);
    IOObjectRelease(ioRegistryRoot);

    if (uuidCf != NULL) {
        NSString *uuid = (__bridge NSString *)uuidCf;

        // TODO: Gross gross gross gross
        NSString *py = [NSString stringWithFormat:@"import hashlib; print(hashlib.sha256('%@' + '%@').hexdigest())", macAddr, uuid];
        NSString *hash = [[self class] runCommandAndReturnOutput:@"/usr/bin/python"
                                                        withArgs:@[@"-c", [py stringByReplacingOccurrencesOfString:@"\n" withString:@""]]];
        CFRelease(uuidCf);

        return [hash stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    }

    return nil;
}

+ (NSString *)getIOKitData:(NSString *)ioService withParam:(NSString *)param
{
    CFStringRef parameter = (__bridge CFStringRef)param;
    CFDataRef data;
    io_service_t sv = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                  IOServiceMatching((const char *)[ioService UTF8String]));
    data = IORegistryEntryCreateCFProperty(sv,
                                           parameter,
                                           kCFAllocatorDefault, 0);
    IOObjectRelease(sv);
    CFIndex bufferLength = CFDataGetLength(data);
    UInt8 *buffer = malloc(bufferLength);
    CFDataGetBytes(data, CFRangeMake(0, bufferLength), (UInt8 *)buffer);

    if (data != NULL) {
        CFRelease(data);
    }

    CFStringRef string = CFStringCreateWithBytes(kCFAllocatorDefault,
                                                 buffer,
                                                 bufferLength,
                                                 kCFStringEncodingUTF8,
                                                 TRUE);
    free(buffer);

    if (string != NULL) {
        NSString *result = [(__bridge NSString *)string copy];
        CFRelease(string);
    
        return [result stringByReplacingOccurrencesOfString:@"\00" withString:@""];
    }

    return nil;
}

+ (NSString *)runCommandAndReturnOutput:(NSString *)launchPath withArgs:(NSArray *)args
{
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [NSPipe pipe];
    task.launchPath = launchPath;
    task.arguments = args;
    task.standardOutput = pipe;
    task.standardError = pipe;
    [task waitUntilExit];
    [task launch];
    NSData *outData = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *outString = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
    
    return outString;
}

+ (NSArray *)plistFromString:(NSString *)plistString
{
    NSData *plistData = [plistString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    NSPropertyListFormat format;
    NSArray *plist = [NSPropertyListSerialization
                      propertyListWithData:plistData
                      options:NSPropertyListImmutable
                      format:&format
                      error:&error];
    if (!plist) {
        NSLog(@"Error parsing property list: %@.", error.localizedDescription);
        return nil;
    }
    
    return plist;
}

+ (NSNumber *)numberFromHexString:(NSString *)aString
{
    if (aString) {
        NSScanner *scanner;
        unsigned int tmpInt;
        scanner = [NSScanner scannerWithString:aString];
        [scanner scanHexInt:&tmpInt];
        return [NSNumber numberWithInt:tmpInt];
    }
    return nil;
}

+ (NSNumber *)numberFromString:(NSString *)aString
{
    if (aString) {
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        formatter.numberStyle = NSNumberFormatterDecimalStyle;
        return [formatter numberFromString:aString];
    }
    return nil;
}

- (void)makeAPIGet:(NSString *)endpoint
           success:(void (^)(NSDictionary *responseDict))success
           failure:(void (^)(NSError *error))failure
{
    NSString *urlString = [kAPIURL stringByAppendingString:endpoint];
    NSString *escapedURLString = [urlString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    NSURLSession *session = [NSURLSession sharedSession];
    NSURL *url = [NSURL URLWithString:escapedURLString];
    
    NSURLSessionDataTask *task = [session dataTaskWithURL:url
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                            if (error) {
                                                failure(error);
                                            } else {
                                                NSError *jsonError;
                                                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                                                     options:0
                                                                                                       error:&jsonError];
                                                if (!jsonError) {
                                                    success(json);
                                                } else {
                                                    failure(jsonError);
                                                }
                                            }
                                        }];
    [task resume];
}

- (void)makeAPIPost:(NSString *)endpoint
           withData:(NSDictionary *)data
            success:(void (^)(NSDictionary *responseDict))success
            failure:(void (^)(NSError *error))failure
{
    NSString *urlString = [kAPIURL stringByAppendingString:endpoint];
    NSError *error;
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:10.0];
    [request addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    request.HTTPMethod = @"POST";
    NSData *postData = [NSJSONSerialization dataWithJSONObject:data options:0 error:&error];
    request.HTTPBody = postData;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            failure(error);
        } else {
            NSError *jsonError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:0
                                                                   error:&jsonError];
            if (!jsonError) {
                success(json);
            } else {
                failure(jsonError);
            }
        }
    }];
    [task resume];
}

- (BOOL)validateResponse:(NSDictionary *)response
{
    if (response[@"error"] && response[@"msg"]) {
        return NO;
    } else if (response[@"msg"]) {
        return YES;
    }
    return NO;
}

- (BOOL)arrayOfStringsContainsOnlyDigits:(NSArray *)arr
{
    for (NSString *part in arr) {
        NSCharacterSet *notDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if (!([part rangeOfCharacterFromSet:notDigits].location == NSNotFound)) {
            return NO;
        }
    }
    return YES;
}

- (NSNumber *)getEFIVersionFromString:(NSString *)efiVersionString
{
    NSArray *efiParts = [efiVersionString componentsSeparatedByString:@"."];
    if (efiParts && (efiParts.count > 0)) {
        NSNumber *efiVersion;
        if ([self arrayOfStringsContainsOnlyDigits:efiParts]) {
            efiVersion = [[self class] numberFromHexString:efiParts[0]];
        } else {
            efiVersion = [[self class] numberFromHexString:efiParts[1]];
        }
        return efiVersion;
    }
    return nil;
}

- (NSNumber *)getEFIBuildFromString:(NSString *)efiVersionString
{
    NSArray *efiParts = [efiVersionString componentsSeparatedByString:@"."];
    if (efiParts && (efiParts.count > 0)) {
        NSNumber *efiBuild;
        if ([self arrayOfStringsContainsOnlyDigits:efiParts]) {
            efiBuild = 0;
        } else {
            efiBuild = [[self class] numberFromString:
                                    [efiParts[2] stringByReplacingOccurrencesOfString:@"B"
                                                                             withString:@""]];
        }
        return efiBuild;
    }
    return nil;
}

- (BOOL)checkFirmwareBeingUpdated
{
    if ([self validateResponse:self.results[@"efi_updates_relased"]]) {
        if (!self.results[@"efi_updates_released"][@"msg"]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)checkFirmwareVersions
{
    if ([self validateResponse:self.results[@"latest_efi_version"]]) {
        // Newer EFI versions do not include a build number
        // or the Mac model code. The output will be something
        // like 256.0.0, whereas with the old format it would
        // be MBP133.0256.B00.
        NSNumber *myEFIVersion = [self getEFIVersionFromString:self.bootROMVersion];
        NSNumber *myEFIBuild = [self getEFIBuildFromString:self.bootROMVersion];
        NSNumber *apiEFIVersion = [self getEFIVersionFromString:self.results[@"latest_efi_version"][@"msg"]];
        NSNumber *apiEFIBuild = [self getEFIBuildFromString:self.bootROMVersion];
        if ([self.results[@"latest_efi_version"][@"msg"] isEqualToString:self.bootROMVersion]) {
            return YES;
        } else if (myEFIVersion == apiEFIVersion && myEFIBuild == apiEFIBuild) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)checkFirmwareVersionGreaterThanKnown
{
    if ([self validateResponse:self.results[@"latest_efi_version"]]) {
        NSNumber *myEFIVersion = [self getEFIVersionFromString:self.bootROMVersion];
        NSNumber *myEFIBuild = [self getEFIBuildFromString:self.bootROMVersion];
        NSNumber *apiEFIVersion = [self getEFIVersionFromString:self.results[@"latest_efi_version"][@"msg"]];
        NSNumber *apiEFIBuild = [self getEFIBuildFromString:self.bootROMVersion];
        if (([myEFIVersion isGreaterThan:apiEFIVersion]) || ([myEFIVersion isEqualToNumber:apiEFIVersion] && [myEFIBuild isGreaterThan:apiEFIBuild])) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)checkHighestBuild
{
    if ([self validateResponse:self.results[@"latest_build_number"]]) {
        if ([self.results[@"latest_build_number"][@"msg"] isEqualToString:self.buildNumber]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)checkBetaBuild
{
    // Current beta builds will have a higher patch level and/or security patch level, just
    // as the logic goes for determining whether a build is greater than what we know about.
    // The difference is that beta builds will always end with a letter. So, if a beta build
    // has a lower patch level or security patch level than what we know about, it's likely
    // an out-of-date beta build. Note, however, that right now we just check whether the
    // build ends with a letter.
    if ([self validateResponse:self.results[@"latest_build_number"]]) {
        // If the build number ends with a letter it's a beta/development build.
        NSString *lastCharacter = [self.buildNumber substringFromIndex:self.buildNumber.length - 1];
        NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
        letters = [letters invertedSet];
        NSRange range = [lastCharacter rangeOfCharacterFromSet:letters];
        if (range.location == NSNotFound) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)checkBuildGreaterThanKnown
{
    /*
         A = .0
         B = .1
         C = .2
         ...and so on.
         Letter in build number corresponds to the patch level, as noted above.
         Number following the letter in the build number is the build thereof. This
         can be 2, 3, 4, or 5 digits. If it's a forked build, the number following
         the letter will be 4 digits, but not all 4 digit builds are forked builds.
         Beta/development builds always end with a letter. We can determine if a
         build is newer than what's returned from the EFIgy API by first checking if
         the letter is higher, (e.g., D > C). If the letter is the same, we check if
         the build number is higher.
    */
    if ([self checkBetaBuild]) {
        return NO;
    }
    NSString *expectedBuild = self.results[@"latest_build_number"][@"msg"];
    NSRange actualRange = [self.buildNumber rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]];
    NSRange expectedRange = [expectedBuild rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]];
    if (actualRange.location != NSNotFound && expectedRange.location != NSNotFound) {
        if ([[self.buildNumber substringFromIndex:actualRange.location] length] > 1 &&
            [[expectedBuild substringFromIndex:expectedRange.location] length] > 1) {
            // Assuming the current build number is 17D47, `patchLevel` would return "D",
            // and `securityPatchLevel` would contain "47".
            NSString *patchLevel = [self.buildNumber substringWithRange:actualRange];
            NSString *securityPatchLevel = [self.buildNumber substringFromIndex:actualRange.location + 1];
            NSString *expectedPatchLevel = [expectedBuild substringWithRange:expectedRange];
            NSString *expectedSecurityPatchLevel = [expectedBuild substringFromIndex:actualRange.location + 1];
            NSInteger securityPatchLevelInt = [securityPatchLevel integerValue];
            NSInteger expectedSecurityPatchLevelInt = [expectedSecurityPatchLevel integerValue];
            if (patchLevel && securityPatchLevel && expectedPatchLevel && expectedSecurityPatchLevel) {
                if ([patchLevel compare:expectedPatchLevel] == NSOrderedDescending) {
                    // Current patch level is greater than expected patch level,
                    // (e.g., D > C).
                    return YES;
                } else if ([patchLevel isEqualToString:expectedPatchLevel] && securityPatchLevelInt > expectedSecurityPatchLevelInt) {
                    // Current patch level is equal to expected patch level,
                    // but security patch level is greater than expected security
                    // patch level, (e.g., D480 > D47, because D == D && 480 > 47).
                    return YES;
                }
            }
        }
    }
    return NO;
}

- (BOOL)checkOSUpToDate
{
    if ([self validateResponse:self.results[@"latest_os_version"]]) {
        if ([self.results[@"latest_os_version"][@"msg"] isEqualToString:self.osVersion]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)checkOSGreaterThanKnown
{
    if ([self validateResponse:self.results[@"latest_os_version"]]) {
        NSString *apiVersion = self.results[@"latest_os_version"][@"msg"];
        if ([self.osVersion compare:apiVersion options:NSNumericSearch] == NSOrderedDescending) {
            return YES;
        }
    }
    return NO;
}

- (void)updateUI
{
    BOOL firmwareBeingUpdated = NO;
    BOOL firmwareUpToDate = NO;
    BOOL firmwareVersionGreaterThanKnown = NO;
    if ([self checkFirmwareBeingUpdated]) {
        firmwareBeingUpdated = YES;
        firmwareUpToDate = [self checkFirmwareVersions];
        firmwareVersionGreaterThanKnown = [self checkFirmwareVersionGreaterThanKnown];
    }
    BOOL runningBetaBuild = [self checkBetaBuild];
    BOOL runningBuildGreaterThanKnown = [self checkBuildGreaterThanKnown];
    BOOL runningHighestBuild = [self checkHighestBuild];
    BOOL osGreaterThanKnown = [self checkOSGreaterThanKnown];
    BOOL osUpToDate = [self checkOSUpToDate];

    __block NSString *firmwareUpToDateTT;
    __block NSString *buildUpToDateTT;
    __block NSString *osUpToDateTT;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (firmwareBeingUpdated &&
            (firmwareUpToDate || firmwareVersionGreaterThanKnown) &&
            (runningHighestBuild || runningBetaBuild || runningBuildGreaterThanKnown) &&
            (osUpToDate || osGreaterThanKnown)) {

            self.logo.image = [NSImage imageNamed:@"happy"];
            if (firmwareVersionGreaterThanKnown) {
                firmwareUpToDateTT = [NSString stringWithFormat:
                                      @"Running firmware version %@, which is newer than what we know about (%@).",
                                      self.bootROMVersion,
                                      self.results[@"latest_efi_version"][@"msg"]];
            } else {
                firmwareUpToDateTT = [NSString stringWithFormat:
                                      @"Running expected firmware version: %@",
                                      self.bootROMVersion];
            }

            if (runningBetaBuild) {
                buildUpToDateTT = [NSString stringWithFormat:
                                   @"Running beta build number: %@",
                                   self.buildNumber];
            } else if (runningBuildGreaterThanKnown) {
                buildUpToDateTT = [NSString stringWithFormat:
                                   @"Running build number %@, which is newer than what we know about (%@).",
                                   self.buildNumber,
                                   self.results[@"latest_build_number"][@"msg"]];
            } else {
                buildUpToDateTT = [NSString stringWithFormat:
                                   @"Running expected build number: %@",
                                   self.buildNumber];
            }

            if (osGreaterThanKnown) {
                osUpToDateTT = [NSString stringWithFormat:
                                @"Running OS version %@, which is newer than what we know about (%@).",
                                self.osVersion,
                                self.results[@"latest_os_version"][@"msg"]];
            } else {
                osUpToDateTT = [NSString stringWithFormat:
                                @"Running latest OS version: %@",
                                self.osVersion];
            }

            if (firmwareVersionGreaterThanKnown) {
                self.firmwareUpToDateLabel.stringValue = @"Running newer firmware";
            } else {
                self.firmwareUpToDateLabel.stringValue = @"Firmware up-to-date";
            }

            if (runningBetaBuild) {
                self.buildUpToDateLabel.stringValue = @"Running beta OS build";
            } else if (runningBuildGreaterThanKnown) {
                self.buildUpToDateLabel.stringValue = @"Running newer OS build";
            } else {
                self.buildUpToDateLabel.stringValue = @"Running latest OS build";
            }

            if (osGreaterThanKnown) {
                self.osUpToDateLabel.stringValue = @"Running newer OS version";
            } else {
                self.osUpToDateLabel.stringValue = @"Running latest OS version";
            }

            if (firmwareVersionGreaterThanKnown) {
                self.firmwareUpToDateImage.image = [NSImage imageNamed:@"check-circle-blue"];
            } else {
                self.firmwareUpToDateImage.image = [NSImage imageNamed:@"check-circle"];
            }

            if (runningBetaBuild || runningBuildGreaterThanKnown) {
                self.buildUpToDateImage.image = [NSImage imageNamed:@"check-circle-blue"];
            } else {
                self.buildUpToDateImage.image = [NSImage imageNamed:@"check-circle"];
            }

            if (osGreaterThanKnown) {
                self.osUpToDateImage.image = [NSImage imageNamed:@"check-circle-blue"];
            } else {
                self.osUpToDateImage.image = [NSImage imageNamed:@"check-circle"];
            }

            self.firmwareUpToDateLabel.toolTip = firmwareUpToDateTT;
            self.firmwareUpToDateImage.toolTip = firmwareUpToDateTT;
            self.buildUpToDateLabel.toolTip = buildUpToDateTT;
            self.buildUpToDateImage.toolTip = buildUpToDateTT;
            self.osUpToDateLabel.toolTip = osUpToDateTT;
            self.osUpToDateImage.toolTip = osUpToDateTT;
        } else {
            self.logo.image = [NSImage imageNamed:@"sad"];
            if (!firmwareBeingUpdated || firmwareVersionGreaterThanKnown || !firmwareUpToDate) {
                if (!firmwareBeingUpdated) {
                    firmwareUpToDateTT = @"Your Mac model hasn't received any firmware updates.";
                    self.firmwareUpToDateLabel.stringValue = @"EFI updates unavailable";
                    self.firmwareUpToDateImage.image = [NSImage imageNamed:NSImageNameCaution];
                } else if (!firmwareUpToDate && firmwareVersionGreaterThanKnown) {
                    firmwareUpToDateTT = [NSString stringWithFormat:
                                          @"Running firmware version %@, which is newer than what we know about (%@).",
                                          self.bootROMVersion,
                                          self.results[@"latest_efi_version"][@"msg"]];
                    self.firmwareUpToDateLabel.stringValue = @"Running newer firmware";
                    self.firmwareUpToDateImage.image = [NSImage imageNamed:@"check-circle-blue"];
                } else {
                    firmwareUpToDateTT = [NSString stringWithFormat:
                                          @"Expected firmware version: %@\n     Actual firmware version: %@",
                                          self.results[@"latest_efi_version"][@"msg"],
                                          self.bootROMVersion];
                    self.firmwareUpToDateLabel.stringValue = @"EFI firmware out-of-date";
                    self.firmwareUpToDateImage.image = [NSImage imageNamed:NSImageNameCaution];
                }
            } else {
                firmwareUpToDateTT = [NSString stringWithFormat:
                                      @"Running expected firmware version: %@",
                                      self.bootROMVersion];
                self.firmwareUpToDateLabel.stringValue = @"Firmware up-to-date";
                self.firmwareUpToDateImage.image = [NSImage imageNamed:@"check-circle"];
            }

            self.firmwareUpToDateLabel.toolTip = firmwareUpToDateTT;
            self.firmwareUpToDateImage.toolTip = firmwareUpToDateTT;

            if (runningBetaBuild) {
                buildUpToDateTT = [NSString stringWithFormat:
                                   @"Running beta build number: %@",
                                   self.buildNumber];
                self.buildUpToDateLabel.stringValue = @"Running beta OS build";
                self.buildUpToDateImage.image = [NSImage imageNamed:@"check-circle-blue"];
            } else if (runningBuildGreaterThanKnown) {
                buildUpToDateTT = [NSString stringWithFormat:
                                   @"Running build number %@, which is newer than what we know about (%@).",
                                   self.buildNumber,
                                   self.results[@"latest_build_number"][@"msg"]];
                self.buildUpToDateLabel.stringValue = @"Running newer OS build";
                self.buildUpToDateImage.image = [NSImage imageNamed:@"check-circle-blue"];
            } else if (runningHighestBuild) {
                buildUpToDateTT = [NSString stringWithFormat:
                                   @"Running expected build number: %@",
                                   self.buildNumber];
                self.buildUpToDateLabel.stringValue = @"Running latest OS build";
                self.buildUpToDateImage.image = [NSImage imageNamed:@"check-circle"];
            } else {
                buildUpToDateTT = [NSString stringWithFormat:
                                   @"Expected build number: %@\n     Actual build number: %@",
                                   self.results[@"latest_build_number"][@"msg"],
                                   self.buildNumber];
                self.buildUpToDateLabel.stringValue = @"OS build out-of-date";
                self.buildUpToDateImage.image = [NSImage imageNamed:NSImageNameCaution];
            }

            self.buildUpToDateLabel.toolTip = buildUpToDateTT;
            self.buildUpToDateImage.toolTip = buildUpToDateTT;

            if (!osUpToDate && osGreaterThanKnown) {
                osUpToDateTT = [NSString stringWithFormat:
                                @"Running OS version %@, which is newer than what we know about (%@).",
                                self.osVersion,
                                self.results[@"latest_os_version"][@"msg"]];
                self.osUpToDateLabel.stringValue = @"Running newer OS version";
                self.osUpToDateImage.image = [NSImage imageNamed:@"check-circle-blue"];
            } else if (!osUpToDate && !osGreaterThanKnown) {
                osUpToDateTT = [NSString stringWithFormat:
                                @"Expected OS version: %@\n     Actual OS version: %@",
                                self.results[@"latest_os_version"][@"msg"],
                                self.osVersion];
                self.osUpToDateLabel.stringValue = @"OS out-of-date";
                self.osUpToDateImage.image = [NSImage imageNamed:NSImageNameCaution];
            } else {
                osUpToDateTT = [NSString stringWithFormat:
                                @"Running latest OS version: %@",
                                self.osVersion];
                self.osUpToDateLabel.stringValue = @"Running latest OS version";
                self.osUpToDateImage.image = [NSImage imageNamed:@"check-circle"];
            }
        }

        self.osUpToDateLabel.toolTip = osUpToDateTT;
        self.osUpToDateImage.toolTip = osUpToDateTT;

        self.getEFIReportButton.enabled = YES;
        [self.progressIndicator stopAnimation:self];
        self.progressIndicator.hidden = YES;
        [self.transparentBlackView removeFromSuperview];
        self.resultsView.hidden = NO;
        [self.resultsView setWantsLayer:YES];
        CGColorRef color;
        if ([self darkModeEnabled]) {
            self.firmwareUpToDateLabel.textColor = [NSColor whiteColor];
            self.buildUpToDateLabel.textColor = [NSColor whiteColor];
            self.osUpToDateLabel.textColor = [NSColor whiteColor];
            color = CGColorCreateGenericRGB(1.0, 1.0, 1.0, 0.3);
        } else {
            color = CGColorCreateGenericRGB(0.0, 0.0, 0.0, 0.6);
        }
        if (color != NULL) {
            self.resultsView.layer.backgroundColor = color;
            self.resultsView.layerUsesCoreImageFilters = YES;
            CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
            [filter setDefaults];
            [filter setValue:[NSNumber numberWithFloat:5.0f] forKey:kCIInputRadiusKey];
            self.resultsView.backgroundFilters = @[filter];
            CFRelease(color);
        }
    });
}

- (IBAction)getEFIReport:(id)sender
{
    self.getEFIReportButton.enabled = NO;
    self.progressIndicator.hidden = NO;
    self.progressIndicator.layer.zPosition = 5;
    [self.progressIndicator startAnimation:self];

    self.transparentBlackView = [[NSView alloc] initWithFrame:[[self.window contentView] frame]];

    CALayer *viewLayer = [CALayer layer];
    [viewLayer setBackgroundColor:CGColorCreateGenericRGB(0.0, 0.0, 0.0, 0.4)]; // RGB plus alpha channel.
    [self.transparentBlackView setWantsLayer:YES];
    [self.transparentBlackView setLayer:viewLayer];

    [[self.window contentView] addSubview:self.transparentBlackView];

    NSDictionary *dataToSubmit = @{@"hashed_uuid": self.hashedSysUUID,
                                   @"hw_ver": self.machineModel,
                                   @"rom_ver": self.bootROMVersion,
                                   @"smc_ver": self.smcVersion,
                                   @"board_id": self.boardID,
                                   @"os_ver": self.osVersion,
                                   @"build_num": self.buildNumber};

    [self makeAPIPost:@"/apple/oneshot" withData:dataToSubmit success:^(NSDictionary *responseDict) {
        self.results = responseDict;
        if (!self.results[@"efi_updates_relased"]) {
            NSString *endpoint = [NSString stringWithFormat:@"/apple/no_firmware_updates_released/%@", self.machineModel];
            [self makeAPIGet:endpoint success:^(NSDictionary *responseDict) {
                [self updateUI];
            } failure:^(NSError *error) {
                NSLog(@"Error submitting data to EFIgy API: %@", error.localizedDescription);
                self.logo.image = [NSImage imageNamed:@"doh"];
            }];
        } else {
            [self updateUI];
        }
    } failure:^(NSError *error) {
        NSLog(@"Error submitting data to EFIgy API: %@", error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logo.image = [NSImage imageNamed:@"doh"];
        });
    }];
}

@end
