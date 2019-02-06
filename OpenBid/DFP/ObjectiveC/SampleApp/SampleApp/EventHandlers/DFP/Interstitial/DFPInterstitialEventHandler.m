/*
 * PubMatic Inc. ("PubMatic") CONFIDENTIAL
 * Unpublished Copyright (c) 2006-2019 PubMatic, All Rights Reserved.
 *
 * NOTICE:  All information contained herein is, and remains the property of
 * PubMatic. The intellectual and technical concepts contained herein are
 * proprietary to PubMatic and may be covered by U.S. and Foreign Patents,
 * patents in process, and are protected by trade secret or copyright law.
 * Dissemination of this information or reproduction of this material is
 * strictly forbidden unless prior written permission is obtained from PubMatic.
 * Access to the source code contained herein is hereby forbidden to anyone
 * except current PubMatic employees, managers or contractors who have executed
 * Confidentiality and Non-disclosure agreements explicitly covering such
 * access.
 *
 * The copyright notice above does not evidence any actual or intended
 * publication or disclosure  of  this source code, which includes information
 * that is confidential and/or proprietary, and is a trade secret, of  PubMatic.
 * ANY REPRODUCTION, MODIFICATION, DISTRIBUTION, PUBLIC  PERFORMANCE, OR PUBLIC
 * DISPLAY OF OR THROUGH USE  OF THIS  SOURCE CODE  WITHOUT  THE EXPRESS WRITTEN
 * CONSENT OF PubMatic IS STRICTLY PROHIBITED, AND IN VIOLATION OF APPLICABLE
 * LAWS AND INTERNATIONAL TREATIES.  THE RECEIPT OR POSSESSION OF  THIS SOURCE
 * CODE AND/OR RELATED INFORMATION DOES NOT CONVEY OR IMPLY ANY RIGHTS TO
 * REPRODUCE, DISCLOSE OR DISTRIBUTE ITS CONTENTS, OR TO MANUFACTURE, USE, OR
 * SELL ANYTHING THAT IT  MAY DESCRIBE, IN WHOLE OR IN PART.
 */

#import "DFPInterstitialEventHandler.h"
#import <POBBid.h>

#define SYNC_TIMEOUT_INTEREVAL 0.8

@interface DFPInterstitialEventHandler () <
GADAppEventDelegate,
GADInterstitialDelegate>
@property(nonatomic, strong) DFPInterstitial *interstitial;
@property (nonatomic, weak) id<POBInterstitialEventDelegate> delegate;
@property (nonatomic, copy) NSString *adUnitId;
@property(nonatomic) NSTimer *timer;
@property (nonatomic, assign) BOOL notified;
@property(nonatomic, assign) BOOL isAppEventExpected;
@end

@implementation DFPInterstitialEventHandler
- (instancetype)initAdunitId:(NSString *)adUnitId {
    
    self = [super init];
    if (self) {
        _adUnitId = adUnitId;
    }
    return self;
}

- (void)dealloc {
    _interstitial.delegate = nil;
    _interstitial = nil;
}

- (void)setDelegate:(id<POBInterstitialEventDelegate>)delegate {
    _delegate = delegate;
}

- (void)requestAdWithBid:(POBBid *)bid {
    
    _notified = NO;
    _isAppEventExpected = NO;
    _interstitial = [[DFPInterstitial alloc]
                     initWithAdUnitID:self.adUnitId];
    _interstitial.delegate = self;
    _interstitial.appEventDelegate = self;

    DFPRequest *dfpRequest = [[DFPRequest alloc] init];
    if (bid) {
        if (bid.status.boolValue) {
            _isAppEventExpected = YES;
        }
        [dfpRequest setCustomTargeting:[bid targetingInfo]];
        NSLog(@"Bid details : %@", [bid.targetingInfo description]);
    }
    [_interstitial loadRequest:dfpRequest];
}


-(void)showFromViewController:(UIViewController *)controller{
    [self.interstitial presentFromRootViewController:controller];
}

/// Called when the interstitial receives an app event.
- (void)interstitial:(GADInterstitial *)interstitial
  didReceiveAppEvent:(NSString *)name
            withInfo:(nullable NSString *)info{
    
    if ([name isEqualToString:@"pubmaticdm"]) {
        if (_notified) {
            NSDictionary *userInfo = nil;
            NSString *errorMessage = @"App event is called unexpetedly";
            userInfo = @{NSLocalizedDescriptionKey : NSLocalizedString(errorMessage, nil)};
            NSError *error = [NSError errorWithDomain:kPOBErrorDomain
                                                 code:POBSignalingError
                                             userInfo:userInfo];
            [self.delegate failedWithError:error];
            return;
        }
        _notified = YES;
        _interstitial.delegate = nil;
        _interstitial = nil;
        [self.delegate openBidPartnerDidWin];
    }
}

- (void)interstitialDidReceiveAd:(GADInterstitial *)ad{
    if (_notified) {
        return;
    }
    
    if (!_isAppEventExpected) {
        if (!self.notified) {
            [self.delegate adServerDidWin];
            self.notified = YES;
        }
    } else {
        // Timer to synchronize did recieve and app event callback as their sequence is not fixed
        [self.timer invalidate];
        self.timer = [NSTimer scheduledTimerWithTimeInterval:SYNC_TIMEOUT_INTEREVAL target:self selector:@selector(syncTimetAction) userInfo:nil repeats:NO];
    }
}

- (void)syncTimetAction{
    if (!self.notified) {
        [self.delegate adServerDidWin];
        self.notified = YES;
    }
}

- (void)interstitial:(GADInterstitial *)ad didFailToReceiveAdWithError:(GADRequestError *)error{
    NSError *eventError = nil;
    switch (error.code) {
        case kGADErrorNoFill:
            eventError = [self eventError:error withErrorCode:POBErrorNoAds];
            break;
            
        case kGADErrorInvalidRequest:
            eventError = [self eventError:error withErrorCode:POBErrorInvalidRequest];
            break;
            
        case kGADErrorNetworkError:
            eventError = [self eventError:error withErrorCode:POBErrorNetworkError];
            break;
            
        case kGADErrorTimeout:
            eventError = [self eventError:error withErrorCode:POBErrorTimeout];
            break;
            
        case kGADErrorInternalError:
        case kGADErrorInterstitialAlreadyUsed:
        case kGADErrorMediationDataError:
        case kGADErrorMediationAdapterError:
        case kGADErrorMediationNoFill:
        case kGADErrorMediationInvalidAdSize:
        case kGADErrorInvalidArgument:
            eventError = [self eventError:error withErrorCode:POBErrorInternalError];
            break;
            
        case kGADErrorReceivedInvalidResponse:
            eventError = [self eventError:error withErrorCode:POBErrorInvalidResponse];
            break;
            
        default:
            eventError = error;
            break;
    }
    
    [_delegate failedWithError:eventError];
}

-(NSError *)eventError:(GADRequestError *)error  withErrorCode:(POBErrorCode )code{
    NSError *eventError = [NSError errorWithDomain:kPOBErrorDomain
                                              code:code
                                          userInfo:error.userInfo];
    return eventError;
}

- (void)interstitialWillPresentScreen:(GADInterstitial *)ad{
    [self.delegate willPresentAd];
}

- (void)interstitialDidDismissScreen:(GADInterstitial *)ad{
    [self.delegate didDismissAd];
}

- (void)interstitialWillLeaveApplication:(GADInterstitial *)ad{
    [self.delegate willLeaveApp];
}

@end
