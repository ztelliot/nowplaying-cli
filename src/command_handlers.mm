#import "command_handlers.h"
#import "volume_control.h"
#import "audio_devices.h"
#import "json_utils.h"
#import "types.h"
#import "MRContent.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

void handleVolumeCommand(bool getOnly, float volumeLevel) {
    if (getOnly) {
        float volume = getSystemVolume();
        if (volume >= 0) {
            printJsonResponse(YES, @{@"volume": @(volume)}, nil);
        } else {
            printJsonResponse(NO, nil, @"Failed to get volume");
        }
    } else {
        bool success = setSystemVolume(volumeLevel);
        if (success) {
            printJsonResponse(YES, @{@"volume": @(volumeLevel)}, nil);
        } else {
            printJsonResponse(NO, nil, @"Failed to set volume");
        }
    }
}

void handleMuteCommand() {
    bool success = toggleMute();
    if (success) {
        printJsonResponse(YES, nil, nil);
    } else {
        printJsonResponse(NO, nil, @"Failed to toggle mute");
    }
}

void handleDevicesCommand() {
    int deviceCount = 0;
    AudioDeviceInfo* devices = getAudioDevices(&deviceCount);

    if (devices == NULL) {
        printJsonResponse(NO, nil, @"Failed to get audio devices");
        return;
    }

    NSMutableDictionary *deviceList = [NSMutableDictionary dictionary];
    for (int i = 0; i < deviceCount; i++) {
        NSString *deviceName = [NSString stringWithUTF8String:devices[i].name];
        [deviceList setObject:@(devices[i].deviceID) forKey:deviceName];
    }

    printJsonResponse(YES, @{@"devices": deviceList}, nil);
    free(devices);
}

void handleSetDeviceCommand(const char* deviceIDStr) {
    AudioDeviceID deviceID = (AudioDeviceID)strtoul(deviceIDStr, NULL, 10);
    bool success = setAudioOutputDevice(deviceID);

    if (success) {
        printJsonResponse(YES, @{@"msg": @"Output device changed"}, nil);
    } else {
        printJsonResponse(NO, nil, @"Failed to change output device");
    }
}

void handleMediaCommand(CFBundleRef bundle, NSString *cmdStr) {
    static NSDictionary<NSString*, NSNumber*> *cmdTranslate = nil;
    if (!cmdTranslate) {
        cmdTranslate = @{
            @"play": @(MRMediaRemoteCommandPlay),
            @"pause": @(MRMediaRemoteCommandPause),
            @"togglePlayPause": @(MRMediaRemoteCommandTogglePlayPause),
            @"next": @(MRMediaRemoteCommandNextTrack),
            @"previous": @(MRMediaRemoteCommandPreviousTrack),
        };
    }

    MRMediaRemoteSendCommandFunction MRMediaRemoteSendCommand =
        (MRMediaRemoteSendCommandFunction)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteSendCommand"));
    MRMediaRemoteSendCommand((MRMediaRemoteCommand)[cmdTranslate[cmdStr] intValue], nil);
    printJsonResponse(YES, nil, nil);
}

void handleSeekCommand(CFBundleRef bundle, double seekTime) {
    MRMediaRemoteSetElapsedTimeFunction MRMediaRemoteSetElapsedTime =
        (MRMediaRemoteSetElapsedTimeFunction)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteSetElapsedTime"));
    MRMediaRemoteSetElapsedTime(seekTime);
    printJsonResponse(YES, nil, nil);
}

void handleNowPlayingInfo(CFBundleRef bundle, Command command, double skipSeconds) {
    NSMutableDictionary *fullInfo = [NSMutableDictionary dictionary];
    dispatch_group_t group = dispatch_group_create();

    // Get now playing info
    dispatch_group_enter(group);
    MRMediaRemoteGetNowPlayingInfoFunction MRMediaRemoteGetNowPlayingInfo =
        (MRMediaRemoteGetNowPlayingInfoFunction)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteGetNowPlayingInfo"));

    MRMediaRemoteGetNowPlayingInfo(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(NSDictionary *info) {
        if (command == SKIP) {
            double elapsedTime = [[info objectForKey:@"kMRMediaRemoteNowPlayingInfoElapsedTime"] doubleValue];
            double duration = [[info objectForKey:@"kMRMediaRemoteNowPlayingInfoDuration"] doubleValue];
            double skipTo = elapsedTime + skipSeconds;

            if (skipTo < 0) skipTo = 0;
            if (skipTo > duration) {
                printJsonResponse(NO, nil, @"Cannot skip past end of track");
                [NSApp terminate:nil];
                return;
            }

            MRMediaRemoteSetElapsedTimeFunction MRMediaRemoteSetElapsedTime =
                (MRMediaRemoteSetElapsedTimeFunction)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteSetElapsedTime"));
            MRMediaRemoteSetElapsedTime(skipTo);

            dispatch_group_leave(group);
            printJsonResponse(YES, nil, nil);
            [NSApp terminate:nil];
            return;
        }

        for (NSString *key in info) {
            NSString *simpleKey = key;
            if ([key hasPrefix:@"kMRMediaRemoteNowPlayingInfo"]) {
                simpleKey = [key substringFromIndex:[@"kMRMediaRemoteNowPlayingInfo" length]];
                if ([simpleKey length] > 0) {
                    simpleKey = [[[simpleKey substringToIndex:1] lowercaseString]
                                stringByAppendingString:[simpleKey substringFromIndex:1]];
                }
            }

            NSObject *rawValue = [info objectForKey:key];
            if (rawValue == nil) continue;

            if ([simpleKey isEqualToString:@"artworkData"] || [simpleKey isEqualToString:@"clientPropertiesData"]) {
                NSData *data = (NSData *)rawValue;
                NSString *base64 = [data base64EncodedStringWithOptions:0];
                [fullInfo setObject:base64 forKey:simpleKey];
            }
            else if ([simpleKey isEqualToString:@"elapsedTime"]) {
                MRContentItem *item = [[objc_getClass("MRContentItem") alloc] initWithNowPlayingInfo:info];
                double position = item.metadata.calculatedPlaybackPosition;
                [fullInfo setObject:@(position) forKey:simpleKey];
            }
            else if ([rawValue isKindOfClass:[NSDate class]]) {
                NSTimeInterval timestamp = [(NSDate *)rawValue timeIntervalSince1970];
                [fullInfo setObject:@(timestamp) forKey:simpleKey];
            }
            else {
                [fullInfo setObject:rawValue forKey:simpleKey];
            }
        }

        dispatch_group_leave(group);
    });

    // Get client info
    dispatch_group_enter(group);
    MRMediaRemoteGetNowPlayingClientFunction MRMediaRemoteGetNowPlayingClient =
        (MRMediaRemoteGetNowPlayingClientFunction)CFBundleGetFunctionPointerForName(bundle, CFSTR("MRMediaRemoteGetNowPlayingClient"));

    MRMediaRemoteGetNowPlayingClient(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(NSObject *info) {
        if ([info respondsToSelector:@selector(bundleIdentifier)]) {
            [fullInfo setObject:[info valueForKey:@"bundleIdentifier"] forKey:@"bundleIdentifier"];
        }

        if ([info respondsToSelector:@selector(displayName)]) {
            [fullInfo setObject:[info valueForKey:@"displayName"] forKey:@"displayName"];
        }

        dispatch_group_leave(group);
    });

    // Get playing state
    dispatch_group_enter(group);
    MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction MRMediaRemoteGetNowPlayingApplicationIsPlaying =
        (MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction)CFBundleGetFunctionPointerForName(bundle,
                                                                CFSTR("MRMediaRemoteGetNowPlayingApplicationIsPlaying"));

    MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(BOOL isPlaying) {
        [fullInfo setObject:@(isPlaying) forKey:@"isPlaying"];
        dispatch_group_leave(group);
    });

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        printJsonResponse(YES, @{@"data": fullInfo}, nil);
        [NSApp terminate:nil];
    });
}