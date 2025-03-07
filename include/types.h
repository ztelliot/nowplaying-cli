#ifndef NOWPLAYING_TYPES_H
#define NOWPLAYING_TYPES_H

#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import "Enums.h"

// MediaRemote function typedefs
typedef void (*MRMediaRemoteGetNowPlayingClientFunction)(dispatch_queue_t queue, void (^handler)(NSObject *info));
typedef void (*MRMediaRemoteGetNowPlayingInfoFunction)(dispatch_queue_t queue, void (^handler)(NSDictionary *info));
typedef void (*MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction)(dispatch_queue_t queue, void (^handler)(BOOL isPlaying));
typedef void (*MRMediaRemoteSetElapsedTimeFunction)(double time);
typedef Boolean (*MRMediaRemoteSendCommandFunction)(MRMediaRemoteCommand cmd, NSDictionary* userInfo);

// Audio device info struct
typedef struct {
    AudioDeviceID deviceID;
    char name[128];
    bool isOutput;
} AudioDeviceInfo;

// Command types
typedef enum {
    GET,
    MEDIA_COMMAND,
    SEEK,
    SKIP,
    GET_VOLUME,
    SET_VOLUME,
    TOGGLE_MUTE,
    LIST_DEVICES,
    SET_DEVICE,
} Command;

#endif // NOWPLAYING_TYPES_H