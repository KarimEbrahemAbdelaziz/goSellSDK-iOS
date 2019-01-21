//
//  PaymentDataManager.swift
//  goSellSDK
//
//  Copyright © 2019 Tap Payments. All rights reserved.
//

import struct   TapAdditionsKit.TypeAlias
import enum     TapCardValidator.CardBrand

/// Payment data manager.
internal final class PaymentDataManager {
    
    // MARK: - Internal -
    // MARK: Properties
    
    /// All cell view models.
    internal private(set) lazy var paymentOptionsScreenCellViewModels: [CellViewModel] = []
    
    /// Currently visible cell view models.
    internal private(set) var paymentOptionCellViewModels: [CellViewModel] = [] {
        
        didSet {
            
            self.restorePaymentOptionSelection()
            NotificationCenter.default.post(name: .tap_paymentOptionsModelsUpdated, object: nil)
        }
    }
    
    internal var supportedCurrencies: [AmountedCurrency] {
        
        return self.paymentOptionsResponse?.supportedCurrenciesAmounts ?? []
    }
    
    internal var userSelectedCurrency: AmountedCurrency? {
        
        didSet {
            
            self.filterPaymentOptionCellViewModels()
            self.updatePayButtonStateAndAmount()
        }
    }
    
    internal weak var payButtonUI: PayButtonUI? {
        
        didSet {
            
            self.payButtonUI?.delegate = self
        }
    }
    
    internal var lastSelectedPaymentOption: PaymentOptionCellViewModel?
    
	internal private(set) var externalSession: SessionProtocol?
    
    internal var orderIdentifier: String? {
        
        return self.paymentOptionsResponse?.orderIdentifier
    }
    
    internal var isExecutingAPICalls = false
    
    internal var transactionCurrency: AmountedCurrency {
        
        guard let nonnullPaymentOptionsResponse = self.paymentOptionsResponse else {
            
            fatalError("Should never reach this place.")
        }
        
        let currency = nonnullPaymentOptionsResponse.currency
        
        if let amountedCurrency = nonnullPaymentOptionsResponse.supportedCurrenciesAmounts.first(where: { $0.currency == currency }) {
            
            return amountedCurrency
        }
        else {
            
            return nonnullPaymentOptionsResponse.supportedCurrenciesAmounts[0]
        }
    }
    
    internal var currentPaymentOption: PaymentOption?
    internal var currentPaymentCardBINNumber: String?
    internal var urlToLoadInWebPaymentController: URL?
    internal var currentChargeOrAuthorize: ChargeProtocol?
    
    internal var paymentOptions: [PaymentOption] {
        
        return self.paymentOptionsResponse?.paymentOptions ?? []
    }
    
    internal var selectedCurrency: AmountedCurrency {
        
        return self.userSelectedCurrency ?? self.transactionCurrency
    }
    
    internal var isInDeleteSavedCardsMode: Bool = false {
        
        didSet {
			
			guard self.isInDeleteSavedCardsMode != oldValue else { return }
			
            if self.isInDeleteSavedCardsMode {
                
                self.deselectAllPaymentOptionsModels()
            }
            
            let savedCardsModels = self.cellModels(of: CardsContainerTableViewCellModel.self).first?.collectionViewCellModels ?? []
            savedCardsModels.forEach { $0.isDeleteCellMode = self.isInDeleteSavedCardsMode }
			
			let recentGroupModel = self.cellModels(of: GroupWithButtonTableViewCellModel.self).first
			recentGroupModel?.updateButtonTitle(self.isInDeleteSavedCardsMode)
        }
    }
	
	internal var appearance: AppearanceMode = .fullscreen
	
    // MARK: Methods
    
    internal func canStart(_ session: SessionProtocol) -> Bool {
		
        if self.isLoadingPaymentOptions { return false }
        
        guard let dataSource = session.dataSource, dataSource.customer != nil else { return false }
		
		let mode = dataSource.mode ?? .default
		switch mode {
			
		case .purchase, .authorizeCapture:
			
			if dataSource.currency == nil { return false }
			return (self.calculateDisplayedAmount(for: session) ?? .zero).decimalValue > 0.0
			
		case .cardSaving:
			
			return true
		}
	}
	
	internal func calculateDisplayedAmount(for session: SessionProtocol) -> NSDecimalNumber? {
		
		guard
			
			let nonnullDataSource = session.dataSource,
			nonnullDataSource.mode != .cardSaving
			
		else { return nil }
		
		var amount: Decimal
		if let optionalItems = nonnullDataSource.items, let items = optionalItems, items.count > 0 {
			
			let taxes		= nonnullDataSource.taxes		?? nil
			let shipping	= nonnullDataSource.shipping	?? nil
			
			amount = AmountCalculator.totalAmount(of: items, with: taxes, and: shipping)
		}
		else {
			
			amount = nonnullDataSource.amount ?? 0.0
		}
		
		return NSDecimalNumber(decimal: amount)
	}
	
    @discardableResult internal func start(_ session: SessionProtocol) -> Bool {
        
        guard !self.isLoadingPaymentOptions else { return false }
        
        guard let nonnullDataSource = session.dataSource else {
            
            self.showMissingInformationAlert(with: "Error", message: "Payment data source cannot be nil.")
            return false
        }
        
        guard let currency = nonnullDataSource.currency else {
            
            self.showMissingInformationAlert(with: "Error", message: "Currency must be provided.")
            return false
        }
        
        guard let customer = nonnullDataSource.customer else {
            
            self.showMissingInformationAlert(with: "Error", message: "Customer information must be provided.")
            return false
        }
        
        let itemsCount = (nonnullDataSource.items ?? [])?.count ?? 0
        guard nonnullDataSource.amount != nil || itemsCount > 0 else {
            
            self.showMissingInformationAlert(with: "Error", message: "Either amount or items should be implemented in payment data source. If items is implemented, number of items should be > 0.")
            return false
        }
		
		let appearanceMode	= nonnullDataSource.appearance	?? .default
		let transactionMode	= nonnullDataSource.mode        ?? .default
		let shipping        = nonnullDataSource.shipping    ?? nil
		let taxes           = nonnullDataSource.taxes       ?? nil
		
		self.externalSession	= session
		self.appearance			= AppearanceMode(appearanceMode, transactionMode)
		
        let paymentRequest = PaymentOptionsRequest(transactionMode: transactionMode,
                                                   amount:          nonnullDataSource.amount,
                                                   items:           nonnullDataSource.items ?? [],
                                                   shipping:        shipping,
                                                   taxes:           taxes,
                                                   currency:        currency,
                                                   customer:        customer.identifier)
        
        self.isLoadingPaymentOptions = true
		
		session.delegate?.sessionIsStarting?(session)
        
        APIClient.shared.getPaymentOptions(with: paymentRequest) { [weak self, weak session] (response, error) in
			
			guard let strongSelf = self, let nonnullSession = session else { return }
			
            strongSelf.isLoadingPaymentOptions = false
            
            if let nonnullError = error {
				
				let retryAction: TypeAlias.ArgumentlessClosure = {
					
					strongSelf.start(nonnullSession)
				}
				
				strongSelf.paymentOptionsResponse = nil
				nonnullSession.delegate?.sessionHasFailedToStart?(nonnullSession)
				
				ErrorDataManager.handle(nonnullError, retryAction: retryAction, alertDismissButtonClickHandler: nil)
			}
            else if let nonnullResponse = response {
				
                strongSelf.paymentOptionsResponse = nonnullResponse
				
				strongSelf.showPaymentController()
				
				nonnullSession.delegate?.sessionHasStarted?(nonnullSession)
            }
        }
		
		return true
    }
    
    internal func paymentOptionViewModel(at indexPath: IndexPath) -> CellViewModel {
        
        guard let model = (self.paymentOptionCellViewModels.first { $0.indexPath == indexPath }) else {
            
            fatalError("Data source is corrupted")
        }
        
        return model
    }
    
    internal func cellModels<ModelType>(of type: ModelType.Type) -> [ModelType] {
        
        guard let result = (self.paymentOptionsScreenCellViewModels.filter { $0 is ModelType }) as? [ModelType] else {
            
            fatalError("Data source is corrupted")
        }
        
        return result
    }
    
    internal func paymentOptionsControllerKeyboardLayoutFinished() {
        
        guard let selectedModel = self.selectedPaymentOptionCellViewModel as? PaymentOptionTableCellViewModel, selectedModel.isSelected else { return }
        
        selectedModel.tableView?.scrollToRow(at: selectedModel.indexPath, at: .none, animated: false)
    }
    
    internal func closePayment(with status: PaymentStatus, fadeAnimation: Bool, force: Bool, completion: TypeAlias.ArgumentlessClosure?) {
        
        let localCompletion: TypeAlias.BooleanClosure = { (closed) in
            
            if closed {
                
                self.reportDelegateOnPaymentCompletion(with: status)
            }
            
            completion?()
        }
        
        if self.isCallingPaymentAPI || self.isChargeOrAuthorizeInProgress  {
            
            let alertDecision: TypeAlias.BooleanClosure = { (shouldClose) in
                
                if shouldClose {
                    
                    self.forceClosePayment(withFadeAnimation: fadeAnimation) {
                        
                        localCompletion(true)
                    }
                }
                else {
                    
                    localCompletion(false)
                }
            }
            
            if force {
                
                alertDecision(true)
            }
            else {
                
                self.showCancelPaymentAlert(with: alertDecision)
            }
        }
        else {
            
            self.forceClosePayment(withFadeAnimation: fadeAnimation) {
                
                localCompletion(true)
            }
        }
    }
    
    private func reportDelegateOnPaymentCompletion(with status: PaymentStatus) {
		
		guard let session = self.externalSession, let delegate = session.delegate else { return }
        
        switch status {
            
        case .cancelled:
			
			delegate.sessionCancelled?(session)
            
        case .successfulCharge(let charge):
			
			delegate.paymentSucceed?(charge, on: session)
            
        case .successfulAuthorize(let authorize):
			
			delegate.authorizationSucceed?(authorize, on: session)
            
        case .chargeFailure(let charge, let error):
			
			delegate.paymentFailed?(with: charge, error: error, on: session)
            
        case .authorizationFailure(let authorize, let error):
			
			delegate.authorizationFailed?(with: authorize, error: error, on: session)
			
		case .cardSaveFailure(let error):
			
			delegate.cardSavingFailed?(with: error, on: session)
        }
    }
    
    private func forceClosePayment(withFadeAnimation: Bool, completion: TypeAlias.ArgumentlessClosure?) {
        
        KnownStaticallyDestroyableTypes.destroyAllDelayedDestroyableInstances {
            
            if let paymentContentController = PaymentContentViewController.tap_findInHierarchy() {
                
                paymentContentController.hide(usingFadeAnimation: withFadeAnimation) {
                    
                    PaymentDataManager.paymentClosed()
                    completion?()
                }
            }
            else {
                
                PaymentDataManager.paymentClosed()
                completion?()
            }
        }
    }
    
    internal func updateUIByRemoving(_ card: SavedCard) {
        
        guard let cardIndex = self.paymentOptionsResponse?.savedCards?.index(of: card) else { return }
        self.paymentOptionsResponse?.savedCards?.remove(at: cardIndex)
		
		let remainingNumberOfCards = self.paymentOptionsResponse?.savedCards?.count ?? 0
		if remainingNumberOfCards == 0 {
			
			self.isInDeleteSavedCardsMode = false
			
			self.generatePaymentOptionCellViewModels()
		}
		else {
			
			self.cardsContainerCellModel.updateData(with: self.paymentOptionsResponse?.savedCards ?? [])
		}
	}
    
    // MARK: - Private -
    
    private struct Constants {
        
		fileprivate static let recentGroupModelKey: LocalizationKey = .payment_options_group_title_recent
		fileprivate static let othersGroupModelKey: LocalizationKey = .payment_options_group_title_others
        
        fileprivate static let spaceBeforeWebPaymentOptionsIdentifier   = "space_before_web_payment_options"
        fileprivate static let spaceBetweenWebAndCardOptionsIdentifier  = "space_between_web_and_card_options"
        
        @available(*, unavailable) private init() {}
    }
    
    // MARK: Properties
	
	private var isLoadingPaymentOptions = false
	
    private var isCallingPaymentAPI: Bool {
        
        let activeRoutes = Set(APIClient.shared.activeRequests.compactMap { Route(rawValue: $0.path) })
        let paymentAPIRoutes: Set<Route> = Set([.charges, .authorize, .token, .tokens])
        
        return activeRoutes.intersection(paymentAPIRoutes).count > 0
    }
    
    private var isChargeOrAuthorizeInProgress: Bool {
        
        guard let chargeOrAuthorize = self.currentChargeOrAuthorize else { return false }
        
        switch chargeOrAuthorize.status {
            
        case .initiated, .inProgress: return true
        default: return false
            
        }
    }
    
    private var paymentOptionsResponse: PaymentOptionsResponse? {
        
        didSet {
            
            self.generatePaymentOptionCellViewModels()
        }
    }
    
    private var cardPaymentOptionsCellModel: CardInputTableViewCellModel {
        
        let cardModels = self.cellModels(of: CardInputTableViewCellModel.self)
        
        guard cardModels.count == 1 else {
            
            fatalError("Data source is corrupted")
        }
        
        return cardModels[0]
    }
    
    private var cardsContainerCellModel: CardsContainerTableViewCellModel {
        
        let cardModels = self.cellModels(of: CardsContainerTableViewCellModel.self)
        
        guard cardModels.count == 1 else {
            
            fatalError("Data source is corrupted")
        }
        
        return cardModels[0]
    }
    
    private var recentCards: [SavedCard] {
        
        return self.paymentOptionsResponse?.savedCards ?? []
    }
    
    private static var storage: PaymentDataManager?
    
    // MARK: Methods
    
    private init() {
        
        KnownStaticallyDestroyableTypes.add(PaymentDataManager.self)
    }
    
    private func nextIndexPath(for temporaryCellModels: [CellViewModel]) -> IndexPath {
        
        return IndexPath(row: temporaryCellModels.count, section: 0)
    }
    
    private func showCancelPaymentAlert(with decision: @escaping TypeAlias.BooleanClosure) {
		
		let alert = TapAlertController(titleKey: 		.alert_cancel_payment_status_undefined_title,
									   messageKey: 		.alert_cancel_payment_status_undefined_message,
									   preferredStyle:	.alert)
		
		let cancelCancelAction = TapAlertController.Action(titleKey: .alert_cancel_payment_status_undefined_btn_no_title, style: .cancel) { [weak alert] (action) in
            
            alert?.hide()
            decision(false)
        }
		
        let confirmCancelAction = TapAlertController.Action(titleKey: .alert_cancel_payment_status_undefined_btn_confirm_title, style: .destructive) { [weak alert] (action) in
            
            alert?.hide()
            decision(true)
        }
        
        alert.addAction(cancelCancelAction)
        alert.addAction(confirmCancelAction)
        
        alert.show()
    }
    
    private func showMissingInformationAlert(with title: String, message: String) {
        
        let alert = TapAlertController(title: title, message: message, preferredStyle: .alert)
        let closeAction = TapAlertController.Action(title: "Close", style: .default) { [weak alert] (action) in
            
           alert?.hide()
        }
        
        alert.addAction(closeAction)
        
        alert.show()
    }
    
    private func paymentOptions(of type: PaymentType) -> [PaymentOption] {
        
        return self.paymentOptions.filter { $0.paymentType == type }
    }
    
    private func generatePaymentOptionCellViewModels() {
        
        guard self.paymentOptionsResponse != nil else {
            
            self.paymentOptionsScreenCellViewModels = []
            return
        }
        
        var result: [CellViewModel] = []
        
        let currencyModel = CurrencySelectionTableViewCellViewModel(indexPath: self.nextIndexPath(for: result),
                                                                    transactionCurrency: self.transactionCurrency,
                                                                    userSelectedCurrency: self.selectedCurrency)
        result.append(currencyModel)
        
        let savedCards = self.recentCards
        
        let sortingClosure: (SortableByOrder, SortableByOrder) -> Bool = { $0.orderBy < $1.orderBy }
        
        let webPaymentOptions = self.paymentOptions(of: .web).sorted(by: sortingClosure)
        let cardPaymentOptions = self.paymentOptions(of: .card).sorted(by: sortingClosure)
        
        let hasSavedCards = savedCards.count > 0
        let hasWebPaymentOptions = webPaymentOptions.count > 0
        let hasCardPaymentOptions = cardPaymentOptions.count > 0
        let hasOtherPaymentOptions = hasWebPaymentOptions || hasCardPaymentOptions
        let displaysGroupTitles = hasSavedCards && hasOtherPaymentOptions
		
        if displaysGroupTitles {
			
			let recentGroupModel = GroupWithButtonTableViewCellModel(indexPath: self.nextIndexPath(for: result), key: Constants.recentGroupModelKey)
            result.append(recentGroupModel)
        }
        
        if hasSavedCards {
            
            let cardsContainerCellModel = CardsContainerTableViewCellModel(indexPath: self.nextIndexPath(for: result), cards: savedCards)
            result.append(cardsContainerCellModel)
        }
        
        if displaysGroupTitles {
            
            let othersGroupModel = GroupTableViewCellModel(indexPath: self.nextIndexPath(for: result), key: Constants.othersGroupModelKey)
            result.append(othersGroupModel)
        }
        
        if hasWebPaymentOptions {
            
            if !hasSavedCards {
                
                let emptyCellModel = EmptyTableViewCellModel(indexPath: self.nextIndexPath(for: result),
                                                             identifier: Constants.spaceBeforeWebPaymentOptionsIdentifier)
                result.append(emptyCellModel)
            }
            
            webPaymentOptions.forEach {
                
                let webOptionCellModel = WebPaymentOptionTableViewCellModel(indexPath: self.nextIndexPath(for: result),
                                                                            paymentOption: $0)
                result.append(webOptionCellModel)
            }
        }
        
        if hasCardPaymentOptions {
            
            if hasWebPaymentOptions || !displaysGroupTitles {
                
                let emptyCellModel = EmptyTableViewCellModel(indexPath: self.nextIndexPath(for: result),
                                                             identifier: Constants.spaceBetweenWebAndCardOptionsIdentifier)
                result.append(emptyCellModel)
            }
            
            let cardOptionsCellModel = CardInputTableViewCellModel(indexPath: self.nextIndexPath(for: result), paymentOptions: cardPaymentOptions)
            
            result.append(cardOptionsCellModel)
        }
        
        self.paymentOptionsScreenCellViewModels = result
        
        self.filterPaymentOptionCellViewModels()
    }
    
    private func filterPaymentOptionCellViewModels() {
        
        var result: [CellViewModel] = []
        result.append(self.currencyCellViewModel)
        
        let currency = self.selectedCurrency.currency
        
        let currenciesFilter: (FilterableByCurrency) -> Bool = { $0.supportedCurrencies.contains(currency) }
        let sortingClosure: (SortableByOrder, SortableByOrder) -> Bool = { $0.orderBy < $1.orderBy }
        
        let savedCards = self.recentCards.filter(currenciesFilter).sorted(by: sortingClosure)
        let webPaymentOptions = self.paymentOptions(of: .web).filter(currenciesFilter).sorted(by: sortingClosure)
        let cardPaymentOptions = self.paymentOptions(of: .card).filter(currenciesFilter).sorted(by: sortingClosure)
        
        let hasSavedCards = savedCards.count > 0
        let hasWebPaymentOptions = webPaymentOptions.count > 0
        let hasCardPaymentOptions = cardPaymentOptions.count > 0
        let hasOtherPaymentOptions = hasWebPaymentOptions || hasCardPaymentOptions
        let displaysGroupTitles = hasSavedCards && hasOtherPaymentOptions
        
        if displaysGroupTitles {
            
            let recentGroupModel = self.groupWithButtonCellModel(with: Constants.recentGroupModelKey)
            recentGroupModel.indexPath = self.nextIndexPath(for: result)
            result.append(recentGroupModel)
        }
        
        if hasSavedCards {
            
            let cardsContainerModel = self.cardsContainerCellModel
            cardsContainerModel.indexPath = self.nextIndexPath(for: result)
			cardsContainerModel.updateData(with: savedCards)
            result.append(cardsContainerModel)
        }
        
        if displaysGroupTitles {
            
            let othersGroupModel = self.groupCellModel(with: Constants.othersGroupModelKey)
            othersGroupModel.indexPath = self.nextIndexPath(for: result)
            result.append(othersGroupModel)
        }
        
        if hasWebPaymentOptions {
            
            if !hasSavedCards {
                
                let emptyModel = self.emptyCellModel(with: Constants.spaceBeforeWebPaymentOptionsIdentifier)
                emptyModel.indexPath = self.nextIndexPath(for: result)
                
                result.append(emptyModel)
            }
            
            webPaymentOptions.forEach {
                
                let webModel = self.webPaymentCellModel(with: $0)
                webModel.indexPath = self.nextIndexPath(for: result)
                
                result.append(webModel)
            }
        }
        
        if hasCardPaymentOptions {
            
            if hasWebPaymentOptions || !displaysGroupTitles {
                
                let emptyModel = self.emptyCellModel(with: Constants.spaceBetweenWebAndCardOptionsIdentifier)
                emptyModel.indexPath = self.nextIndexPath(for: result)
                
                result.append(emptyModel)
            }
            
            let cardModel = self.cardPaymentOptionsCellModel
            cardModel.indexPath = self.nextIndexPath(for: result)
            cardModel.paymentOptions = cardPaymentOptions
            
            result.append(cardModel)
        }
        
        self.paymentOptionCellViewModels = result
    }
    
    private func groupCellModel(with key: LocalizationKey) -> GroupTableViewCellModel {
		
		if let existing = self.cellModels(of: GroupTableViewCellModel.self).first(where: { $0.key == key }) {
			
			return existing
		}
		
        let newModel = GroupTableViewCellModel(indexPath: self.nextIndexPath(for: self.paymentOptionsScreenCellViewModels), key: key)
        self.paymentOptionsScreenCellViewModels.append(newModel)
        
        return newModel
    }
	
	private func groupWithButtonCellModel(with key: LocalizationKey) -> GroupWithButtonTableViewCellModel {
		
		if let existing = self.cellModels(of: GroupWithButtonTableViewCellModel.self).first(where: { $0.key == key }) {
			
			return existing
		}
		
		let newModel = GroupWithButtonTableViewCellModel(indexPath: self.nextIndexPath(for: self.paymentOptionsScreenCellViewModels), key: key)
		self.paymentOptionsScreenCellViewModels.append(newModel)
		
		return newModel
	}
    
    private func webPaymentCellModel(with paymentOption: PaymentOption) -> WebPaymentOptionTableViewCellModel {
        
        let webModels = self.cellModels(of: WebPaymentOptionTableViewCellModel.self)
        
        for model in webModels {
            
            if model.paymentOption == paymentOption {
                
                return model
            }
        }
        
        let newModel = WebPaymentOptionTableViewCellModel(indexPath: self.nextIndexPath(for: self.paymentOptionsScreenCellViewModels), paymentOption: paymentOption)
        self.paymentOptionsScreenCellViewModels.append(newModel)
        
        return newModel
    }
    
    private func emptyCellModel(with identifier: String) -> EmptyTableViewCellModel {
        
        let emptyModels = self.cellModels(of: EmptyTableViewCellModel.self)
        
        for model in emptyModels {
            
            if model.identifier == identifier {
                
                return model
            }
        }
        
        let newModel = EmptyTableViewCellModel(indexPath: self.nextIndexPath(for: self.paymentOptionsScreenCellViewModels), identifier: identifier)
        self.paymentOptionsScreenCellViewModels.append(newModel)
        
        return newModel
    }
    
    private static func paymentClosed() {
        
        KnownStaticallyDestroyableTypes.destroyAllInstances()
    }
}

// MARK: - ImmediatelyDestroyable
extension PaymentDataManager: ImmediatelyDestroyable {
    
    internal static var hasAliveInstance: Bool {
        
        return self.storage != nil
    }
    
    internal static func destroyInstance() {
        
        self.storage = nil
    }
}

// MARK: - Singleton
extension PaymentDataManager: Singleton {
    
    internal static var shared: PaymentDataManager {
        
        if let nonnullStorage = self.storage {
            
            return nonnullStorage
        }
        
        let instance = PaymentDataManager()
        self.storage = instance
        
        return instance
    }
}
