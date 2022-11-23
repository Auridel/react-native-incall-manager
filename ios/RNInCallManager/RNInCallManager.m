//
//  RNInCallManager.m
//  RNInCallManager
//
//  Created by Ian Yu-Hsun Lin (@ianlin) on 05/12/2017.
//  Copyright © 2017 zxcpoiu. All rights reserved.
//

#import "RNInCallManager.h"

#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTUtils.h>

//static BOOL const automatic = YES;

@implementation RNInCallManager
{
    UIDevice *_currentDevice;

    AVAudioSession *_audioSession;

    // --- tags to indicating which observer has added
    BOOL _isAudioSessionInterruptionRegistered;
    BOOL _isAudioSessionRouteChangeRegistered;
    BOOL _isAudioSessionMediaServicesWereLostRegistered;
    BOOL _isAudioSessionMediaServicesWereResetRegistered;
    BOOL _isAudioSessionSilenceSecondaryAudioHintRegistered;

    // -- notification observers
    id _audioSessionInterruptionObserver;
    id _audioSessionRouteChangeObserver;
    id _audioSessionMediaServicesWereLostObserver;
    id _audioSessionMediaServicesWereResetObserver;
    id _audioSessionSilenceSecondaryAudioHintObserver;

    NSString *_incallAudioMode;
    NSString *_incallAudioCategory;
    NSString *_origAudioCategory;
    NSString *_origAudioMode;
    BOOL _audioSessionInitialized;
    int _forceSpeakerOn;
    NSString *_media;
}

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

RCT_EXPORT_MODULE(InCallManager)

- (instancetype)init
{
    if (self = [super init]) {
        _currentDevice = [UIDevice currentDevice];
        _audioSession = [AVAudioSession sharedInstance];

        _isAudioSessionInterruptionRegistered = NO;
        _isAudioSessionRouteChangeRegistered = NO;
        _isAudioSessionMediaServicesWereLostRegistered = NO;
        _isAudioSessionMediaServicesWereResetRegistered = NO;
        _isAudioSessionSilenceSecondaryAudioHintRegistered = NO;

        _audioSessionInterruptionObserver = nil;
        _audioSessionRouteChangeObserver = nil;
        _audioSessionMediaServicesWereLostObserver = nil;
        _audioSessionMediaServicesWereResetObserver = nil;
        _audioSessionSilenceSecondaryAudioHintObserver = nil;

        _incallAudioMode = AVAudioSessionModeVideoChat;
        _incallAudioCategory = AVAudioSessionCategoryPlayAndRecord;
        _origAudioCategory = nil;
        _origAudioMode = nil;
        _audioSessionInitialized = NO;
        _forceSpeakerOn = 0;
        _media = @"audio";

        NSLog(@"RNInCallManager.init(): initialized");
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stop];
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"WiredHeadset", @"BluetoothDevice"];
}

RCT_EXPORT_METHOD(start:(NSString *)mediaType
                   auto:(BOOL)_auto)
{
    if (_audioSessionInitialized) {
        return;
    }
    _media = mediaType;

    // --- auto is always true on ios
    if ([_media isEqualToString:@"video"]) {
        _incallAudioMode = AVAudioSessionModeVideoChat;
    } else {
        _incallAudioMode = AVAudioSessionModeVoiceChat;
    }
    NSLog(@"RNInCallManager.start() start InCallManager. media=%@, type=%@, mode=%@", _media, _media, _incallAudioMode);
    [self storeOriginalAudioSetup];
    _forceSpeakerOn = 0;
    [self startAudioSessionNotification];
    [self audioSessionSetCategory:_incallAudioCategory
                          options:(AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionDefaultToSpeaker)
                       callerMemo:NSStringFromSelector(_cmd)];
    [self audioSessionSetMode:_incallAudioMode
                   callerMemo:NSStringFromSelector(_cmd)];
    [self audioSessionSetActive:YES
                        options:0
                     callerMemo:NSStringFromSelector(_cmd)];

    [self setKeepScreenOn:YES];
    _audioSessionInitialized = YES;
    //self.debugAudioSession()
}

RCT_EXPORT_METHOD(stop)
{
    if (!_audioSessionInitialized) {
        return;
    }

    NSLog(@"RNInCallManager.stop(): stop InCallManager");
    [self restoreOriginalAudioSetup];
    [self audioSessionSetActive:NO
                        options:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                     callerMemo:NSStringFromSelector(_cmd)];
    [self setKeepScreenOn:NO];
    [self stopAudioSessionNotification];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _forceSpeakerOn = 0;
    _audioSessionInitialized = NO;
}

RCT_EXPORT_METHOD(setKeepScreenOn:(BOOL)enable)
{
    NSLog(@"RNInCallManager.setKeepScreenOn(): enable: %@", enable ? @"YES" : @"NO");
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] setIdleTimerDisabled:enable];
    });
}

RCT_EXPORT_METHOD(setSpeakerphoneOn:(BOOL)enable)
{
    BOOL success;
    NSError *error = nil;
    NSArray* routes = [_audioSession availableInputs];

    if(!enable){
        NSLog(@"Routing audio via Earpiece");
        @try {
            success = [_audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
            if (!success)  NSLog(@"Cannot set category due to error: %@", error);
            success = [_audioSession setMode:AVAudioSessionModeVoiceChat error:&error];
            if (!success)  NSLog(@"Cannot set mode due to error: %@", error);
            [_audioSession setPreferredOutputNumberOfChannels:0 error:nil];
            if (!success)  NSLog(@"Port override failed due to: %@", error);
            [_audioSession overrideOutputAudioPort:[AVAudioSessionPortBuiltInReceiver intValue] error:&error];
            success = [_audioSession setActive:YES error:&error];
            if (!success) NSLog(@"Audio session override failed: %@", error);
            else NSLog(@"AudioSession override is successful ");

        } @catch (NSException *e) {
            NSLog(@"Error occurred while routing audio via Earpiece: %@", e.reason);
        }
    } else {
        NSLog(@"Routing audio via Loudspeaker");
        @try {
            NSLog(@"Available routes: %@", routes[0]);
            success = [_audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                        withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker
                        error:nil];
            if (!success)  NSLog(@"Cannot set category due to error: %@", error);
            success = [_audioSession setMode:AVAudioSessionModeVideoChat error: &error];
            if (!success)  NSLog(@"Cannot set mode due to error: %@", error);
            [_audioSession setPreferredOutputNumberOfChannels:0 error:nil];
            [_audioSession overrideOutputAudioPort:[AVAudioSessionPortBuiltInSpeaker intValue] error: &error];
            if (!success)  NSLog(@"Port override failed due to: %@", error);
            success = [_audioSession setActive:YES error:&error];
            if (!success) NSLog(@"Audio session override failed: %@", error);
            else NSLog(@"AudioSession override is successful ");
        } @catch (NSException *e) {
            NSLog(@"Error occurred while routing audio via Loudspeaker: %@", e.reason);
        }
    }
}

RCT_EXPORT_METHOD(setForceSpeakerphoneOn:(int)flag)
{
    _forceSpeakerOn = flag;
    NSLog(@"RNInCallManager.setForceSpeakerphoneOn(): flag: %d", flag);
    [self updateAudioRoute];
}

RCT_EXPORT_METHOD(getIsWiredHeadsetPluggedIn:(RCTPromiseResolveBlock)resolve
                                      reject:(RCTPromiseRejectBlock)reject)
{
    BOOL wiredHeadsetPluggedIn = [self isWiredHeadsetPluggedIn];
    resolve(wiredHeadsetPluggedIn ? @YES : @NO);
}

RCT_EXPORT_METHOD(forceUpdateAudioRoute)
{
    [self updateAudioRoute];
}

- (void)updateAudioRoute
{
    NSLog(@"RNInCallManager.updateAudioRoute(): [Enter] forceSpeakerOn flag=%d media=%@ category=%@ mode=%@", _forceSpeakerOn, _media, _audioSession.category, _audioSession.mode);
    //self.debugAudioSession()
    
    NSLog(@"RNInCallManager current CATEGORY %@", _audioSession.category);
    NSLog(@"RNInCallManager current MODE %@", _audioSession.mode);
    NSLog(@"RNInCallManager current OUT %@", _audioSession.outputDataSource);
    NSLog(@"RNInCallManager current OUT VOLUME %f", _audioSession.outputVolume);
    NSLog(@"RNInCallManager =====> current route: %@ ", _audioSession.currentRoute);

    //AVAudioSessionPortOverride overrideAudioPort;
    int overrideAudioPort;
    NSString *overrideAudioPortString = @"";
    NSString *audioMode = @"";

    // --- WebRTC native code will change audio mode automatically when established.
    // --- It would have some race condition if we change audio mode with webrtc at the same time.
    // --- So we should not change audio mode as possible as we can. Only when default video call which wants to force speaker off.
    // --- audio: only override speaker on/off; video: should change category
    if (_forceSpeakerOn == 1) {
        // --- force ON, override speaker only, keep audio mode remain.
        overrideAudioPort = AVAudioSessionPortOverrideSpeaker;
        overrideAudioPortString = @".Speaker";
        if ([_media isEqualToString:@"video"]) {
            audioMode = AVAudioSessionModeVideoChat;
        }
    } else if (_forceSpeakerOn == -1) {
        // --- force off
        overrideAudioPort = AVAudioSessionPortOverrideNone;
        overrideAudioPortString = @".None";
        if ([_media isEqualToString:@"video"]) {
            audioMode = AVAudioSessionModeVideoChat;
        }
    } else { // use default behavior
        overrideAudioPort = AVAudioSessionPortOverrideNone;
        overrideAudioPortString = @".None";
        if ([_media isEqualToString:@"video"]) {
            audioMode = AVAudioSessionModeVideoChat;
        }
    }

    BOOL isCurrentRouteToSpeaker;
    isCurrentRouteToSpeaker = [self checkAudioRoute:@[AVAudioSessionPortBuiltInSpeaker]
                                               routeType:@"output"];
    NSLog(@"RNInCallManager.updateAudioRoute(): IS CURRENT TO SPEAKER: (%d)", isCurrentRouteToSpeaker);
    if ((overrideAudioPort == AVAudioSessionPortOverrideSpeaker && !isCurrentRouteToSpeaker)
            || (overrideAudioPort == AVAudioSessionPortOverrideNone && isCurrentRouteToSpeaker)) {
        @try {
            [_audioSession overrideOutputAudioPort:overrideAudioPort error:nil];
            NSLog(@"RNInCallManager.updateAudioRoute(): audioSession.overrideOutputAudioPort(%@) success", overrideAudioPortString);
        } @catch (NSException *e) {
            NSLog(@"RNInCallManager.updateAudioRoute(): audioSession.overrideOutputAudioPort(%@) fail: %@", overrideAudioPortString, e.reason);
        }
    } else {
        NSLog(@"RNInCallManager.updateAudioRoute(): did NOT overrideOutputAudioPort()");
    }

    if (![_audioSession.category isEqualToString:_incallAudioCategory]) {
        [self audioSessionSetCategory:_incallAudioCategory
                              options:(AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionDefaultToSpeaker)
                           callerMemo:NSStringFromSelector(_cmd)];
        NSLog(@"RNInCallManager.updateAudioRoute() audio category has changed to %@", _incallAudioCategory);
    } else {
        NSLog(@"RNInCallManager.updateAudioRoute() did NOT change audio category");
    }

    if (audioMode.length > 0 && ![_audioSession.mode isEqualToString:audioMode]) {
        [self audioSessionSetMode:audioMode
                       callerMemo:NSStringFromSelector(_cmd)];
        NSLog(@"RNInCallManager.updateAudioRoute() audio mode has changed to %@", audioMode);
    } else {
        NSLog(@"RNInCallManager.updateAudioRoute() did NOT change audio mode");
    }
    //self.debugAudioSession()
}

- (BOOL)checkAudioRoute:(NSArray<NSString *> *)targetPortTypeArray
              routeType:(NSString *)routeType
{
    AVAudioSessionRouteDescription *currentRoute = _audioSession.currentRoute;

    if (currentRoute != nil) {
        NSArray<AVAudioSessionPortDescription *> *routes = [routeType isEqualToString:@"input"]
            ? currentRoute.inputs
            : currentRoute.outputs;
        for (AVAudioSessionPortDescription *portDescription in routes) {
            if ([targetPortTypeArray containsObject:portDescription.portType]) {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)isWiredHeadsetPluggedIn
{
    // --- only check for a audio device plugged into headset port instead bluetooth/usb/hdmi
    return [self checkAudioRoute:@[AVAudioSessionPortHeadphones]
                       routeType:@"output"]
        || [self checkAudioRoute:@[AVAudioSessionPortHeadsetMic]
                       routeType:@"input"];
}

- (void)audioSessionSetCategory:(NSString *)audioCategory
                        options:(AVAudioSessionCategoryOptions)options
                     callerMemo:(NSString *)callerMemo
{
    @try {
        if (options != 0) {
            [_audioSession setCategory:audioCategory
                           withOptions:options
                                 error:nil];
        } else {
            [_audioSession setCategory:audioCategory
                                 error:nil];
        }
        NSLog(@"RNInCallManager.%@: audioSession.setCategory: %@, withOptions: %lu success", callerMemo, audioCategory, (unsigned long)options);
    } @catch (NSException *e) {
        NSLog(@"RNInCallManager.%@: audioSession.setCategory: %@, withOptions: %lu fail: %@", callerMemo, audioCategory, (unsigned long)options, e.reason);
    }
}

- (void)audioSessionSetMode:(NSString *)audioMode
                 callerMemo:(NSString *)callerMemo
{
    @try {
        [_audioSession setMode:audioMode error:nil];
        NSLog(@"RNInCallManager.%@: audioSession.setMode(%@) success", callerMemo, audioMode);
    } @catch (NSException *e) {
        NSLog(@"RNInCallManager.%@: audioSession.setMode(%@) fail: %@", callerMemo, audioMode, e.reason);
    }
}

- (void)audioSessionSetActive:(BOOL)audioActive
                   options:(AVAudioSessionSetActiveOptions)options
                   callerMemo:(NSString *)callerMemo
{
    @try {
        if (options != 0) {
            [_audioSession setActive:audioActive
                         withOptions:options
                               error:nil];
        } else {
            [_audioSession setActive:audioActive
                               error:nil];
        }
        NSLog(@"RNInCallManager.%@: audioSession.setActive(%@), withOptions: %lu success", callerMemo, audioActive ? @"YES" : @"NO", (unsigned long)options);
    } @catch (NSException *e) {
        NSLog(@"RNInCallManager.%@: audioSession.setActive(%@), withOptions: %lu fail: %@", callerMemo, audioActive ? @"YES" : @"NO", (unsigned long)options, e.reason);
    }
}

- (void)storeOriginalAudioSetup
{
    NSLog(@"RNInCallManager.storeOriginalAudioSetup(): origAudioCategory=%@, origAudioMode=%@", _audioSession.category, _audioSession.mode);
    _origAudioCategory = _audioSession.category;
    _origAudioMode = _audioSession.mode;
}

- (void)restoreOriginalAudioSetup
{
    NSLog(@"RNInCallManager.restoreOriginalAudioSetup(): origAudioCategory=%@, origAudioMode=%@", _audioSession.category, _audioSession.mode);
    [self audioSessionSetCategory:_origAudioCategory
                          options:0
                       callerMemo:NSStringFromSelector(_cmd)];
    [self audioSessionSetMode:_origAudioMode
                   callerMemo:NSStringFromSelector(_cmd)];
}

- (void)startAudioSessionNotification
{
    NSLog(@"RNInCallManager.startAudioSessionNotification() starting...");
    [self startAudioSessionInterruptionNotification];
    [self startAudioSessionRouteChangeNotification];
    [self startAudioSessionMediaServicesWereLostNotification];
    [self startAudioSessionMediaServicesWereResetNotification];
    [self startAudioSessionSilenceSecondaryAudioHintNotification];
}

- (void)stopAudioSessionNotification
{
    NSLog(@"RNInCallManager.startAudioSessionNotification() stopping...");
    [self stopAudioSessionInterruptionNotification];
    [self stopAudioSessionRouteChangeNotification];
    [self stopAudioSessionMediaServicesWereLostNotification];
    [self stopAudioSessionMediaServicesWereResetNotification];
    [self stopAudioSessionSilenceSecondaryAudioHintNotification];
}

- (void)startAudioSessionInterruptionNotification
{
    if (_isAudioSessionInterruptionRegistered) {
        return;
    }
    NSLog(@"RNInCallManager.startAudioSessionInterruptionNotification()");

    // --- in case it didn't deallocate when ViewDidUnload
    [self stopObserve:_audioSessionInterruptionObserver
                 name:AVAudioSessionInterruptionNotification
               object:nil];

    _audioSessionInterruptionObserver = [self startObserve:AVAudioSessionInterruptionNotification
                                                    object:nil
                                                     queue:nil
                                                     block:^(NSNotification *notification) {
        if (notification.userInfo == nil
                || ![notification.name isEqualToString:AVAudioSessionInterruptionNotification]) {
            return;
        }

        //NSUInteger rawValue = notification.userInfo[AVAudioSessionInterruptionTypeKey].unsignedIntegerValue;
        NSNumber *interruptType = [notification.userInfo objectForKey:@"AVAudioSessionInterruptionTypeKey"];
        if ([interruptType unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan) {
            NSLog(@"RNInCallManager.AudioSessionInterruptionNotification: Began");
        } else if ([interruptType unsignedIntegerValue] == AVAudioSessionInterruptionTypeEnded) {
            NSLog(@"RNInCallManager.AudioSessionInterruptionNotification: Ended");
        } else {
            NSLog(@"RNInCallManager.AudioSessionInterruptionNotification: Unknow Value");
        }
        //NSLog(@"RNInCallManager.AudioSessionInterruptionNotification: could not resolve notification");
    }];

    _isAudioSessionInterruptionRegistered = YES;
}

- (void)stopAudioSessionInterruptionNotification
{
    if (!_isAudioSessionInterruptionRegistered) {
        return;
    }
    NSLog(@"RNInCallManager.stopAudioSessionInterruptionNotification()");
    // --- remove all no matter what object
    [self stopObserve:_audioSessionInterruptionObserver
                 name:AVAudioSessionInterruptionNotification
               object: nil];
    _isAudioSessionInterruptionRegistered = NO;
}

- (void)startAudioSessionRouteChangeNotification
{
        if (_isAudioSessionRouteChangeRegistered) {
            return;
        }

        NSLog(@"RNInCallManager.startAudioSessionRouteChangeNotification()");

        // --- in case it didn't deallocate when ViewDidUnload
        [self stopObserve:_audioSessionRouteChangeObserver
                     name: AVAudioSessionRouteChangeNotification
                   object: nil];

        _audioSessionRouteChangeObserver = [self startObserve:AVAudioSessionRouteChangeNotification
                                                       object: nil
                                                        queue: nil
                                                        block:^(NSNotification *notification) {
            if (notification.userInfo == nil
                    || ![notification.name isEqualToString:AVAudioSessionRouteChangeNotification]) {
                return;
            }

            NSNumber *routeChangeType = [notification.userInfo objectForKey:@"AVAudioSessionRouteChangeReasonKey"];
            NSUInteger routeChangeTypeValue = [routeChangeType unsignedIntegerValue];

            switch (routeChangeTypeValue) {
                case AVAudioSessionRouteChangeReasonUnknown:
                    NSLog(@"RNInCallManager.AudioRouteChange.Reason: Unknown");
                    break;
                case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
                    NSLog(@"RNInCallManager.AudioRouteChange.Reason: NewDeviceAvailable");
                    if ([self checkAudioRoute:@[AVAudioSessionPortHeadsetMic]
                                    routeType:@"input"]) {
                        [self sendEventWithName:@"WiredHeadset"
                                           body:@{
                                               @"isPlugged": @YES,
                                               @"hasMic": @YES,
                                               @"deviceName": AVAudioSessionPortHeadsetMic,
                                           }];
                    } else if ([self checkAudioRoute:@[AVAudioSessionPortHeadphones]
                                           routeType:@"output"]) {
                        [self sendEventWithName:@"WiredHeadset"
                                           body:@{
                                               @"isPlugged": @YES,
                                               @"hasMic": @NO,
                                               @"deviceName": AVAudioSessionPortHeadphones,
                                           }];
                    } else if ([self checkAudioRoute:@[AVAudioSessionPortBluetoothLE, AVAudioSessionPortBluetoothHFP, AVAudioSessionPortBluetoothA2DP] routeType:@"output"]) {
                        [self sendEventWithName:@"BluetoothDevice"
                                           body:@{
                            @"isConnected": @YES,
                            @"deviceType": @"BLUETOOTH"
                        }];
                    }
                    break;
                case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
                    NSLog(@"RNInCallManager.AudioRouteChange.Reason: OldDeviceUnavailable");
                    if (![self isWiredHeadsetPluggedIn]) {
                        [self sendEventWithName:@"WiredHeadset"
                                           body:@{
                                               @"isPlugged": @NO,
                                               @"hasMic": @NO,
                                               @"deviceName": @"",
                                           }];
                    } else if ([self checkAudioRoute:@[AVAudioSessionPortBluetoothLE, AVAudioSessionPortBluetoothHFP, AVAudioSessionPortBluetoothA2DP] routeType:@"output"]) {
                        [self sendEventWithName:@"BluetoothDevice" body:@{
                            @"isConnected": @NO,
                            @"deviceType": @"BLUETOOTH"
                        }];
                    }
                    break;
                case AVAudioSessionRouteChangeReasonCategoryChange:
                    NSLog(@"RNInCallManager.AudioRouteChange.Reason: CategoryChange. category=%@ mode=%@", self->_audioSession.category, self->_audioSession.mode);
                    [self updateAudioRoute];
                    break;
                case AVAudioSessionRouteChangeReasonOverride:
                    NSLog(@"RNInCallManager.AudioRouteChange.Reason: Override");
                    break;
                case AVAudioSessionRouteChangeReasonWakeFromSleep:
                    NSLog(@"RNInCallManager.AudioRouteChange.Reason: WakeFromSleep");
                    break;
                case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
                    NSLog(@"RNInCallManager.AudioRouteChange.Reason: NoSuitableRouteForCategory");
                    break;
                case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
                    NSLog(@"RNInCallManager.AudioRouteChange.Reason: RouteConfigurationChange. category=%@ mode=%@", self->_audioSession.category, self->_audioSession.mode);
                    break;
                default:
                    NSLog(@"RNInCallManager.AudioRouteChange.Reason: Unknow Value");
                    break;
            }

            NSNumber *silenceSecondaryAudioHintType = [notification.userInfo objectForKey:@"AVAudioSessionSilenceSecondaryAudioHintTypeKey"];
            NSUInteger silenceSecondaryAudioHintTypeValue = [silenceSecondaryAudioHintType unsignedIntegerValue];
            switch (silenceSecondaryAudioHintTypeValue) {
                case AVAudioSessionSilenceSecondaryAudioHintTypeBegin:
                    NSLog(@"RNInCallManager.AudioRouteChange.SilenceSecondaryAudioHint: Begin");
                case AVAudioSessionSilenceSecondaryAudioHintTypeEnd:
                    NSLog(@"RNInCallManager.AudioRouteChange.SilenceSecondaryAudioHint: End");
                default:
                    NSLog(@"RNInCallManager.AudioRouteChange.SilenceSecondaryAudioHint: Unknow Value");
            }
        }];

        _isAudioSessionRouteChangeRegistered = YES;
}

- (void)stopAudioSessionRouteChangeNotification
{
    if (!_isAudioSessionRouteChangeRegistered) {
        return;
    }

    NSLog(@"RNInCallManager.stopAudioSessionRouteChangeNotification()");
    // --- remove all no matter what object
    [self stopObserve:_audioSessionRouteChangeObserver
                 name:AVAudioSessionRouteChangeNotification
               object:nil];
    _isAudioSessionRouteChangeRegistered = NO;
}

- (void)startAudioSessionMediaServicesWereLostNotification
{
    if (_isAudioSessionMediaServicesWereLostRegistered) {
        return;
    }

    NSLog(@"RNInCallManager.startAudioSessionMediaServicesWereLostNotification()");

    // --- in case it didn't deallocate when ViewDidUnload
    [self stopObserve:_audioSessionMediaServicesWereLostObserver
                 name:AVAudioSessionMediaServicesWereLostNotification
               object:nil];

    _audioSessionMediaServicesWereLostObserver = [self startObserve:AVAudioSessionMediaServicesWereLostNotification
                                                             object:nil
                                                              queue:nil
                                                              block:^(NSNotification *notification) {
        // --- This notification has no userInfo dictionary.
        NSLog(@"RNInCallManager.AudioSessionMediaServicesWereLostNotification: Media Services Were Lost");
    }];

    _isAudioSessionMediaServicesWereLostRegistered = YES;
}

- (void)stopAudioSessionMediaServicesWereLostNotification
{
    if (!_isAudioSessionMediaServicesWereLostRegistered) {
        return;
    }

    NSLog(@"RNInCallManager.stopAudioSessionMediaServicesWereLostNotification()");

    // --- remove all no matter what object
    [self stopObserve:_audioSessionMediaServicesWereLostObserver
                 name:AVAudioSessionMediaServicesWereLostNotification
               object:nil];

    _isAudioSessionMediaServicesWereLostRegistered = NO;
}

- (void)startAudioSessionMediaServicesWereResetNotification
{
    if (_isAudioSessionMediaServicesWereResetRegistered) {
        return;
    }

    NSLog(@"RNInCallManager.startAudioSessionMediaServicesWereResetNotification()");

    // --- in case it didn't deallocate when ViewDidUnload
    [self stopObserve:_audioSessionMediaServicesWereResetObserver
                 name:AVAudioSessionMediaServicesWereResetNotification
               object:nil];

    _audioSessionMediaServicesWereResetObserver = [self startObserve:AVAudioSessionMediaServicesWereResetNotification
                                                              object:nil
                                                               queue:nil
                                                               block:^(NSNotification *notification) {
        // --- This notification has no userInfo dictionary.
        NSLog(@"RNInCallManager.AudioSessionMediaServicesWereResetNotification: Media Services Were Reset");
    }];

    _isAudioSessionMediaServicesWereResetRegistered = YES;
}

- (void)stopAudioSessionMediaServicesWereResetNotification
{
    if (!_isAudioSessionMediaServicesWereResetRegistered) {
        return;
    }

    NSLog(@"RNInCallManager.stopAudioSessionMediaServicesWereResetNotification()");

    // --- remove all no matter what object
    [self stopObserve:_audioSessionMediaServicesWereResetObserver
                 name:AVAudioSessionMediaServicesWereResetNotification
               object:nil];

    _isAudioSessionMediaServicesWereResetRegistered = NO;
}

- (void)startAudioSessionSilenceSecondaryAudioHintNotification
{
    if (_isAudioSessionSilenceSecondaryAudioHintRegistered) {
        return;
    }

    NSLog(@"RNInCallManager.startAudioSessionSilenceSecondaryAudioHintNotification()");

    // --- in case it didn't deallocate when ViewDidUnload
    [self stopObserve:_audioSessionSilenceSecondaryAudioHintObserver
                 name:AVAudioSessionSilenceSecondaryAudioHintNotification
               object:nil];

    _audioSessionSilenceSecondaryAudioHintObserver = [self startObserve:AVAudioSessionSilenceSecondaryAudioHintNotification
                                                                 object:nil
                                                                  queue:nil
                                                                  block:^(NSNotification *notification) {
        if (notification.userInfo == nil
                || ![notification.name isEqualToString:AVAudioSessionSilenceSecondaryAudioHintNotification]) {
            return;
        }

        NSNumber *silenceSecondaryAudioHintType = [notification.userInfo objectForKey:@"AVAudioSessionSilenceSecondaryAudioHintTypeKey"];
        NSUInteger silenceSecondaryAudioHintTypeValue = [silenceSecondaryAudioHintType unsignedIntegerValue];
        switch (silenceSecondaryAudioHintTypeValue) {
            case AVAudioSessionSilenceSecondaryAudioHintTypeBegin:
                NSLog(@"RNInCallManager.AVAudioSessionSilenceSecondaryAudioHintNotification: Begin");
                break;
            case AVAudioSessionSilenceSecondaryAudioHintTypeEnd:
                NSLog(@"RNInCallManager.AVAudioSessionSilenceSecondaryAudioHintNotification: End");
                break;
            default:
                NSLog(@"RNInCallManager.AVAudioSessionSilenceSecondaryAudioHintNotification: Unknow Value");
                break;
        }
    }];
    _isAudioSessionSilenceSecondaryAudioHintRegistered = YES;
}

- (void)stopAudioSessionSilenceSecondaryAudioHintNotification
{
    if (!_isAudioSessionSilenceSecondaryAudioHintRegistered) {
        return;
    }

    NSLog(@"RNInCallManager.stopAudioSessionSilenceSecondaryAudioHintNotification()");
    // --- remove all no matter what object
    [self stopObserve:_audioSessionSilenceSecondaryAudioHintObserver
                 name:AVAudioSessionSilenceSecondaryAudioHintNotification
               object:nil];

    _isAudioSessionSilenceSecondaryAudioHintRegistered = NO;
}

- (id)startObserve:(NSString *)name
            object:(id)object
             queue:(NSOperationQueue *)queue
             block:(void (^)(NSNotification *))block
{
    return [[NSNotificationCenter defaultCenter] addObserverForName:name
                                               object:object
                                                queue:queue
                                           usingBlock:block];
}

- (void)stopObserve:(id)observer
             name:(NSString *)name
           object:(id)object
{
    if (observer == nil) return;
    [[NSNotificationCenter defaultCenter] removeObserver:observer
                                                    name:name
                                                  object:object];
}

- (NSURL *)getAudioUri:(NSString *)_type
            fileBundle:(NSString *)fileBundle
         fileBundleExt:(NSString *)fileBundleExt
        fileSysWithExt:(NSString *)fileSysWithExt
           fileSysPath:(NSString *)fileSysPath
             uriBundle:(NSURL **)uriBundle
            uriDefault:(NSURL **)uriDefault
{
    NSString *type = _type;
    if ([type isEqualToString:@"_BUNDLE_"]) {
        if (*uriBundle == nil) {
            *uriBundle = [[NSBundle mainBundle] URLForResource:fileBundle withExtension:fileBundleExt];
            if (*uriBundle == nil) {
                NSLog(@"RNInCallManager.getAudioUri(): %@.%@ not found in bundle.", fileBundle, fileBundleExt);
                type = fileSysWithExt;
            } else {
                return *uriBundle;
            }
        } else {
            return *uriBundle;
        }
    }

    if (*uriDefault == nil) {
        NSString *target = [NSString stringWithFormat:@"%@/%@", fileSysPath, type];
        *uriDefault = [self getSysFileUri:target];
    }
    return *uriDefault;
}

- (NSURL *)getSysFileUri:(NSString *)target
{
    NSURL *url = [[NSURL alloc] initFileURLWithPath:target isDirectory:NO];

    if (url != nil) {
        NSString *path = url.path;
        if (path != nil) {
            NSFileManager *fileManager = [[NSFileManager alloc] init];
            BOOL isTargetDirectory;
            if ([fileManager fileExistsAtPath:path isDirectory:&isTargetDirectory]) {
                if (!isTargetDirectory) {
                    return url;
                }
            }
        }
    }
    NSLog(@"RNInCallManager.getSysFileUri(): can not get url for %@", target);
    return nil;
}

@end
