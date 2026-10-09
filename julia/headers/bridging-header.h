//
//  bluetooth-framework-header.h
//  julia
//
//  Created by Advait on 9/24/26.
//

#ifndef bridging_header_h
#define bridging_header_h

#include <CoreFoundation/CoreFoundation.h>

int IOBluetoothPreferenceGetControllerPowerState(void);
void IOBluetoothPreferenceSetControllerPowerState(int state);

// MediaRemote private API: sends a command to the system's Now Playing app.
Boolean MRMediaRemoteSendCommand(int command, CFDictionaryRef _Nullable userInfo);

#endif /* bridging_header_h */
