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
#import <QuartzCore/QuartzCore.h>

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

static NSString * const kAPIURL = @"https://api.efigy.io";

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
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
    
    _window.backgroundColor = [NSColor whiteColor];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    // Insert code here to tear down your application
}

+ (NSString *)getBoardID
{
    // IOPlatformExpertDevice : IOService : IORegistryEntry : OSObject
    return [[self class] getIOKitData:@"IOPlatformExpertDevice" withParam:@"board-id"];
}

+ (NSString *)getMachineModel
{
    // IOPlatformExpertDevice : IOService : IORegistryEntry : OSObject
    return [[[self class] getIOKitData:@"IOPlatformExpertDevice"
                             withParam:@"model"]
  stringByReplacingOccurrencesOfString:@"\00" withString:@""];
}

+ (NSString *)getBootROMVersion
{
    // TODO: Figure out how to do this without `system_profiler`.
    // IOService : IORegistryEntry : OSObject
    NSString *outputPlist = [[self class] runCommandAndReturnOutput:@"/usr/sbin/system_profiler"
                                                           withArgs:@[@"-xml", @"SPHardwareDataType"]];
    NSArray *plist = [[self class] plistFromString:outputPlist];
    NSString *bootROMVersion = plist[0][@"_items"][0][@"boot_rom_version"];
    
    return bootROMVersion;
}

+ (NSString *)getSMCVersion
{
    // TODO: Figure out how to do this without `system_profiler`.
    NSString *outputPlist = [[self class] runCommandAndReturnOutput:@"/usr/sbin/system_profiler"
                                                           withArgs:@[@"-xml", @"SPHardwareDataType"]];
    NSArray *plist = [[self class] plistFromString:outputPlist];
    NSString *smcVersion = plist[0][@"_items"][0][@"SMC_version_system"];
    
    return smcVersion;
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
    NSString *uuid = (__bridge NSString *)uuidCf;

    // TODO: Gross gross gross gross
    NSString *py = [NSString stringWithFormat:@"import hashlib; print(hashlib.sha256('%@' + '%@').hexdigest())", macAddr, uuid];
    NSString *hash = [[self class] runCommandAndReturnOutput:@"/usr/bin/python"
                                                    withArgs:@[@"-c", [py stringByReplacingOccurrencesOfString:@"\n" withString:@""]]];
    CFRelease(uuidCf);
    
    return [hash stringByReplacingOccurrencesOfString:@"\n" withString:@""];
}

+ (NSString *)getIOKitData:(NSString *)ioService withParam:(NSString *)param
{
    CFStringRef parameter = (__bridge CFStringRef)param;
    CFDataRef data;
    io_service_t platformExpert = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                              IOServiceMatching((const char *)[ioService UTF8String]));
    data = IORegistryEntryCreateCFProperty(platformExpert,
                                           parameter,
                                           kCFAllocatorDefault, 0);
    IOObjectRelease(platformExpert);
    CFIndex bufferLength = CFDataGetLength(data);
    UInt8 *buffer = malloc(bufferLength);
    CFDataGetBytes(data, CFRangeMake(0, bufferLength), (UInt8 *)buffer);
    CFStringRef string = CFStringCreateWithBytes(kCFAllocatorDefault,
                                                 buffer,
                                                 bufferLength,
                                                 kCFStringEncodingUTF8,
                                                 TRUE);
    NSString *result = [(__bridge NSString *)string copy];
    free(buffer);
    CFRelease(data);
    CFRelease(string);
    
    return result;
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
        if (self.results[@"latest_efi_version"][@"msg"] == self.bootROMVersion) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)checkHighestBuild
{
    if ([self validateResponse:self.results[@"latest_build_number"]]) {
        if (self.results[@"latest_build_number"][@"msg"] == self.buildNumber) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)checkOSUpToDate
{
    if ([self validateResponse:self.results[@"latest_os_version"]]) {
        if (self.results[@"latest_os_version"][@"msg"] == self.osVersion) {
            return YES;
        }
    }
    return NO;
}

- (void)updateUI
{
    BOOL firmwareBeingUpdated = NO;
    BOOL firmwareUpToDate = NO;
    if ([self checkFirmwareBeingUpdated]) {
        firmwareBeingUpdated = YES;
        firmwareUpToDate = [self checkFirmwareVersions];
    }
    BOOL runningHighestBuild = [self checkHighestBuild];
    BOOL osUpToDate = [self checkOSUpToDate];

    __block NSString *firmwareUpToDateTT;
    __block NSString *buildUpToDateTT;
    __block NSString *osUpToDateTT;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (firmwareBeingUpdated && firmwareUpToDate && runningHighestBuild && osUpToDate) {
            self.logo.image = [NSImage imageNamed:@"happy"];
            firmwareUpToDateTT = [NSString stringWithFormat:
                                  @"Running expected firmware version: %@",
                                  self.bootROMVersion];
            buildUpToDateTT = [NSString stringWithFormat:
                               @"Running expected build number: %@",
                               self.buildNumber];
            osUpToDateTT = [NSString stringWithFormat:
                            @"Running latest OS version: %@",
                            self.osVersion];

            self.firmwareUpToDateLabel.stringValue = @"Firmware up-to-date";
            self.buildUpToDateLabel.stringValue = @"Running latest OS build";
            self.osUpToDateLabel.stringValue = @"Running latest OS version";

            self.firmwareUpToDateImage.image = [NSImage imageNamed:@"check-circle"];
            self.buildUpToDateImage.image = [NSImage imageNamed:@"check-circle"];
            self.osUpToDateImage.image = [NSImage imageNamed:@"check-circle"];

            self.firmwareUpToDateLabel.toolTip = firmwareUpToDateTT;
            self.firmwareUpToDateImage.toolTip = firmwareUpToDateTT;
            self.buildUpToDateLabel.toolTip = buildUpToDateTT;
            self.buildUpToDateImage.toolTip = buildUpToDateTT;
            self.osUpToDateLabel.toolTip = osUpToDateTT;
            self.osUpToDateImage.toolTip = osUpToDateTT;
        } else {
            self.logo.image = [NSImage imageNamed:@"sad"];
            
            if (!firmwareBeingUpdated || !firmwareUpToDate) {
                if (!firmwareBeingUpdated) {
                    firmwareUpToDateTT = @"Your Mac model hasn't received any firmware updates.";
                    self.firmwareUpToDateLabel.stringValue = @"EFI updates unavailable";
                    self.firmwareUpToDateImage.image = [NSImage imageNamed:NSImageNameCaution];
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

            if (!runningHighestBuild) {
                buildUpToDateTT = [NSString stringWithFormat:
                                   @"Expected build number: %@\n     Actual build number: %@",
                                   self.results[@"latest_build_number"][@"msg"],
                                   self.buildNumber];
                self.buildUpToDateLabel.stringValue = @"OS build out-of-date";
                self.buildUpToDateImage.image = [NSImage imageNamed:NSImageNameCaution];
            } else {
                buildUpToDateTT = [NSString stringWithFormat:
                                   @"Running expected build number: %@",
                                   self.buildNumber];
                self.buildUpToDateLabel.stringValue = @"Running latest OS build";
                self.buildUpToDateImage.image = [NSImage imageNamed:@"check-circle"];
            }

            self.buildUpToDateLabel.toolTip = buildUpToDateTT;
            self.buildUpToDateImage.toolTip = buildUpToDateTT;

            if (!osUpToDate) {
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
        CGColorRef color = CGColorCreateGenericRGB(0.0, 0.0, 0.0, 0.6);
        self.resultsView.layer.backgroundColor = color;
        self.resultsView.layerUsesCoreImageFilters = YES;
        CIFilter *filter = [CIFilter filterWithName:@"CIGaussianBlur"];
        [filter setDefaults];
        [filter setValue:[NSNumber numberWithFloat:5.0f] forKey:kCIInputRadiusKey];
        self.resultsView.backgroundFilters = @[filter];
        CFRelease(color);
    });
}

- (IBAction)getEFIReport:(id)sender
{
    self.getEFIReportButton.enabled = NO;
    self.progressIndicator.hidden = NO;
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
