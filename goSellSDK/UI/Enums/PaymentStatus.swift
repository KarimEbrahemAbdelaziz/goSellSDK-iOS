//
//  PaymentStatus.swift
//  goSellSDK
//
//  Copyright © 2019 Tap Payments. All rights reserved.
//

internal enum PaymentStatus {
    
    case cancelled
    case successfulCharge(Charge)
    case successfulAuthorize(Authorize)
    case chargeFailure(Charge?, TapSDKError?)
    case authorizationFailure(Authorize?, TapSDKError?)
	case cardSaveFailure(TapSDKError?)
}
