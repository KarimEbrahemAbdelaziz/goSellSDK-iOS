//
//  APIClient+Authorize.swift
//  goSellSDK
//
//  Copyright © 2018 Tap Payments. All rights reserved.
//

import struct   TapNetworkManager.TapBodyModel
import class    TapNetworkManager.TapNetworkRequestOperation
import enum     TapNetworkManager.TapURLModel

internal extension APIClient {
    
    // MARK: - Internal -
    // MARK: Methods
    
    internal func createAuthorize(with request: CreateAuthorizeRequest, completion: @escaping Completion<Authorize>) {
        
        guard let bodyDictionary = self.convertModelToDictionary(request, callingCompletionOnFailure: completion) else { return }
        
        let body = TapBodyModel(body: bodyDictionary)
        let operation = TapNetworkRequestOperation(path: self.authorizationRoute.rawValue, method: .POST, headers: self.staticHTTPHeaders, urlModel: nil, bodyModel: body, responseType: .json)
        
        self.performRequest(operation, using: self.authorizationRoute.decoder, completion: completion)
    }
    
    // MARK: - Private -
    // MARK: Properties
    
    private var authorizationRoute: Route {
        
        return .authorize
    }
}
