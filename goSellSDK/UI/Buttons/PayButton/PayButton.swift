//
//  PayButton.swift
//  goSellSDK
//
//  Copyright © 2018 Tap Payments. All rights reserved.
//

import class TapNibView.TapNibView
import class UIKit.UIButton.UIButton

/// Pay button.
@objcMembers public final class PayButton: TapNibView {
    
    // MARK: - Public -
    // MARK: Properties
    
    /// Defines if the receiver is enabled.
    public var isEnabled: Bool {
        
        get {
            
            return self.ui?.isEnabled ?? false
        }
        set {
            
            self.ui?.isEnabled = newValue
        }
    }
    
    /// Payment data source.
    @IBOutlet public weak var dataSource: PaymentDataSource? {
        
        didSet {
            
            self.ui?.paymentDataSource = self.dataSource
        }
    }
    
    /// Payment delegate.
    @IBOutlet public weak var delegate: PaymentDelegate? {
     
        didSet {
            
            self.ui?.paymentDelegate = self.delegate
        }
    }
    
    /// Bundle to load nib from.
    public override class var bundle: Bundle {
        
        return .goSellSDKResources
    }
    
    // MARK: Methods
    
    /// Updates displayed state and amount.
    public func updateDisplayedStateAndAmount() {
        
        self.calculateDisplayedAmount()
    }
    
    // MARK: - Internal -
    // MARK: Properties
    
    /// Theme of the payment controller. Default is light.
    /// Currently not available for modification until we add another theme.
    internal let controllerTheme: Theme = .light
    
    // MARK: - Private -
    // MARK: Properties
    
    @IBOutlet private weak var ui: PayButtonUI? {
        
        didSet {
            
            self.ui?.delegate = self
            self.ui?.paymentDataSource = self.dataSource
        }
    }
}

// MARK: - TapButtonDelegate
extension PayButton: TapButtonDelegate {
    
    internal func securityButtonTouchUpInside() {
        
        self.buttonTouchUpInside()
    }
}

// MARK: - PayButtonInternalImplementation
extension PayButton: PayButtonInternalImplementation {
    
    internal var theme: Theme {
        
        return self.controllerTheme
    }
    
    internal var uiElement: PayButtonUI? {
        
        return self.ui
    }
}
