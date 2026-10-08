//
//  bluetooth-framework-header.h
//  julia
//
//  Created by Advait on 9/24/26.
//

#ifndef bridging_header_h
#define bridging_header_h

#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>

int IOBluetoothPreferenceGetControllerPowerState(void);
void IOBluetoothPreferenceSetControllerPowerState(int state);

// MediaRemote private API: sends a command to the system's Now Playing app.
Boolean MRMediaRemoteSendCommand(int command, CFDictionaryRef _Nullable userInfo);
void MRMediaRemoteGetNowPlayingApplicationIsPlaying(dispatch_queue_t _Nonnull queue,
                                                   void (^ _Nonnull completion)(Boolean isPlaying));

#endif /* bridging_header_h */
