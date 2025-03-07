#ifndef NOWPLAYING_AUDIO_DEVICES_H
#define NOWPLAYING_AUDIO_DEVICES_H

#import "types.h"

// Get a list of available audio devices
AudioDeviceInfo* getAudioDevices(int* count);

// Set the default audio output device
bool setAudioOutputDevice(AudioDeviceID deviceID);

#endif // NOWPLAYING_AUDIO_DEVICES_H