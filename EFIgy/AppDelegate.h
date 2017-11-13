//
//  AppDelegate.h
//  EFIgy
//
//  Created by James Barclay on 10/5/17.
//  Copyright © 2017 Duo Security. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSURLSessionDelegate>

- (IBAction)getEFIReport:(id)sender;

@property (weak) IBOutlet NSTextField *hashedSysUUIDLabel;
@property (weak) IBOutlet NSTextField *hardwareVersionLabel;
@property (weak) IBOutlet NSTextField *bootROMVersionLabel;
@property (weak) IBOutlet NSTextField *smcVersionLabel;
@property (weak) IBOutlet NSTextField *boardIDLabel;
@property (weak) IBOutlet NSTextField *osVersionLabel;
@property (weak) IBOutlet NSTextField *buildNumberLabel;
@property (weak) IBOutlet NSImageView *logo;
@property (weak) IBOutlet NSProgressIndicator *progressIndicator;
@property (weak) IBOutlet NSButton *getEFIReportButton;
@property (nonatomic, strong) NSView *transparentBlackView;

@property NSDictionary *results;

@property NSString *boardID;
@property NSString *bootROMVersion;
@property NSString *machineModel;
@property NSString *smcVersion;
@property NSString *osVersion;
@property NSString *buildNumber;
@property NSString *hashedSysUUID;

@end
