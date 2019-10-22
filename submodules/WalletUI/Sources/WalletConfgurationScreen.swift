import Foundation
import UIKit
import AppBundle
import AsyncDisplayKit
import Display
import SwiftSignalKit
import OverlayStatusController
import WalletCore

private final class WalletConfigurationScreenArguments {
    let updateState: ((WalletConfigurationScreenState) -> WalletConfigurationScreenState) -> Void
    let dismissInput: () -> Void
    
    init(updateState: @escaping ((WalletConfigurationScreenState) -> WalletConfigurationScreenState) -> Void, dismissInput: @escaping () -> Void) {
        self.updateState = updateState
        self.dismissInput = dismissInput
    }
}

private enum WalletConfigurationScreenSection: Int32 {
    case configString
}

private enum WalletConfigurationScreenEntryTag: ItemListItemTag {
    case configStringText
    
    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? WalletConfigurationScreenEntryTag {
            return self == other
        } else {
            return false
        }
    }
}

private enum WalletConfigurationScreenEntry: ItemListNodeEntry, Equatable {
    case configString(WalletTheme, String, String)
   
    var section: ItemListSectionId {
        switch self {
        case .configString:
            return WalletConfigurationScreenSection.configString.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
        case .configString:
            return 0
        }
    }
    
    static func <(lhs: WalletConfigurationScreenEntry, rhs: WalletConfigurationScreenEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(_ arguments: Any) -> ListViewItem {
        let arguments = arguments as! WalletConfigurationScreenArguments
        switch self {
        case let .configString(theme, placeholder, text):
            return ItemListMultilineInputItem(theme: theme, text: text, placeholder: placeholder, maxLength: nil, sectionId: self.section, style: .blocks, capitalization: false, autocorrection: false, returnKeyType: .done, minimalHeight: nil, textUpdated: { value in
                arguments.updateState { state in
                    var state = state
                    state.configString = value
                    return state
                }
            }, shouldUpdateText: { _ in
                return true
            }, processPaste: nil, updatedFocus: nil, tag: WalletConfigurationScreenEntryTag.configStringText, action: nil, inlineAction: nil)
        }
    }
}

private struct WalletConfigurationScreenState: Equatable {
    var configString: String
    
    var isEmpty: Bool {
        return self.configString.isEmpty
    }
}

private func walletConfigurationScreenEntries(presentationData: WalletPresentationData, state: WalletConfigurationScreenState) -> [WalletConfigurationScreenEntry] {
    var entries: [WalletConfigurationScreenEntry] = []
    
    entries.append(.configString(presentationData.theme, "", state.configString))
    
    return entries
}

protocol WalletConfigurationScreen {
}

private final class WalletConfigurationScreenImpl: ItemListController, WalletConfigurationScreen {
    override func preferredContentSizeForLayout(_ layout: ContainerViewLayout) -> CGSize? {
        return CGSize(width: layout.size.width, height: layout.size.height - 174.0)
    }
}

func walletConfigurationScreen(context: WalletContext, currentConfiguration: CustomWalletConfiguration?) -> ViewController {
    var configString = ""
    if let currentConfiguration = currentConfiguration {
        switch currentConfiguration {
        case let .string(string):
            configString = string
        }
    }
    let initialState = WalletConfigurationScreenState(configString: configString)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WalletConfigurationScreenState) -> WalletConfigurationScreenState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    
    var presentControllerImpl: ((ViewController, Any?) -> Void)?
    var pushImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?
    var dismissInputImpl: (() -> Void)?
    var ensureItemVisibleImpl: ((WalletConfigurationScreenEntryTag, Bool) -> Void)?
    
    weak var currentStatusController: ViewController?
    let arguments = WalletConfigurationScreenArguments(updateState: { f in
        updateState(f)
    }, dismissInput: {
        dismissInputImpl?()
    })
    
    let signal = combineLatest(queue: .mainQueue(), .single(context.presentationData), statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Wallet_Configuration_Apply), style: .bold, enabled: !state.isEmpty, action: {
            let state = stateValue.with { $0 }
            let configuration: CustomWalletConfiguration?
            if state.configString.isEmpty {
                configuration = nil
            } else {
                configuration = .string(state.configString)
            }
            context.storage.updateCustomWalletConfiguration(configuration)
            dismissImpl?()
        })
        
        let controllerState = ItemListControllerState(theme: presentationData.theme, title: .text(presentationData.strings.Wallet_Configuration_Title), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Wallet_Navigation_Back), animateChanges: false)
        let listState = ItemListNodeState(entries: walletConfigurationScreenEntries(presentationData: presentationData, state: state), style: .blocks, focusItemTag: nil, ensureVisibleItemTag: nil, animateChanges: false)
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = WalletConfigurationScreenImpl(theme: context.presentationData.theme, strings: context.presentationData.strings, updatedPresentationData: .single((context.presentationData.theme, context.presentationData.strings)), state: signal, tabBarItem: nil)
    controller.supportedOrientations = ViewControllerSupportedOrientations(regularSize: .all, compactSize: .portrait)
    controller.experimentalSnapScrollToItem = true
    controller.didAppear = { _ in
    }
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushImpl = { [weak controller] c in
        controller?.push(c)
    }
    dismissImpl = { [weak controller] in
        controller?.view.endEditing(true)
        let _ = controller?.dismiss()
    }
    dismissInputImpl = { [weak controller] in
        controller?.view.endEditing(true)
    }
    ensureItemVisibleImpl = { [weak controller] targetTag, animated in
        controller?.afterLayout({
            guard let controller = controller else {
                return
            }
            var resultItemNode: ListViewItemNode?
            let state = stateValue.with({ $0 })
            let _ = controller.frameForItemNode({ itemNode in
                if let itemNode = itemNode as? ItemListItemNode {
                    if let tag = itemNode.tag, tag.isEqual(to: targetTag) {
                        resultItemNode = itemNode as? ListViewItemNode
                        return true
                    }
                }
                return false
            })
            if let resultItemNode = resultItemNode {
                controller.ensureItemNodeVisible(resultItemNode, animated: animated)
            }
        })
    }
    return controller
}
