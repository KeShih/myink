import CoreGraphics
import Foundation

/// Decides when the shelf is shown, collapsed to its edge tab or hidden. Pure: feed it events, it
/// returns effects for the window controller to perform (and the timers to run).
///
/// The *base* state is where the shelf sits when nothing is going on. A drag can temporarily reveal
/// the shelf on top of that (`revealedForDrag`); when the drag ends without a drop, a short grace
/// period covers drops that arrive just after mouse-up, then the shelf returns to its base.
public struct VisibilityMachine: Sendable, Equatable {
    public enum Base: Sendable, Equatable {
        case hidden, collapsed, shown, pinned
    }

    /// What the shelf does when it holds items and isn't in use.
    public enum IdlePolicy: String, Codable, CaseIterable, Sendable {
        /// Stay on screen (Yoink's classic behavior).
        case stayVisible
        /// Collapse to a thin tab at the edge; hovering or dragging onto it reveals the shelf.
        case collapse
        /// Hide; a drag or the hotkey brings it back.
        case hide
    }

    public enum Placement: Sendable, Equatable {
        case edge
        case nearPointer(CGPoint)
    }

    public enum TimerKind: Sendable, Hashable {
        /// After a revealing drag ends without a drop.
        case grace
        /// After the pointer leaves a shelf that should go back to its idle state.
        case autoHide
        /// After items were added by Services, URL, AppleScript or a Dock/menu bar drop.
        case linger
    }

    public enum Effect: Sendable, Equatable {
        /// Show the shelf (or move it) at the edge or beside the pointer.
        case present(Placement)
        case collapseToTab
        case hideAll
        case startTimer(TimerKind, TimeInterval)
        case cancelTimer(TimerKind)
        /// Make the shelf key so it receives keystrokes (without activating Myink).
        case makeKey
        case restoreLatestBatch
    }

    public enum Event: Sendable, Equatable {
        /// An accepted drag started somewhere on the system.
        case externalDragBegan
        /// The trigger rules decided the shelf should appear.
        case revealTriggered(Placement)
        case externalDragEnded
        /// Something was dropped onto the shelf.
        case dropCompleted
        case pointerEntered, pointerExited
        /// The pointer hovered, or a drag entered, the collapsed tab.
        case tabActivated
        case internalDragBegan
        case internalDragEnded(pointerInside: Bool)
        case toggle, show, hide
        /// Long press of the hotkey: restore the latest removals and show.
        case longPress
        case itemCountChanged(Int)
        case itemsAddedExternally
        case timerFired(TimerKind)
        case idlePolicyChanged(IdlePolicy)
    }

    public static let graceInterval: TimeInterval = 0.3
    public static let autoHideInterval: TimeInterval = 1.5
    public static let lingerInterval: TimeInterval = 2.5

    public private(set) var base: Base = .hidden
    public private(set) var manuallyHidden = false
    public private(set) var dragActive = false
    public private(set) var revealedForDrag = false
    public private(set) var graceActive = false
    public private(set) var internalDragActive = false
    public private(set) var pointerInside = false
    public private(set) var itemCount: Int
    public private(set) var idlePolicy: IdlePolicy

    public init(itemCount: Int = 0, idlePolicy: IdlePolicy = .stayVisible) {
        self.itemCount = itemCount
        self.idlePolicy = idlePolicy
    }

    public var isVisible: Bool { revealedForDrag || base == .shown || base == .pinned }
    public var isCollapsed: Bool { !isVisible && base == .collapsed }

    /// The idle state for the current item count, policy and manual-hide flag.
    public var rest: Base {
        guard itemCount > 0 else { return .hidden }
        switch idlePolicy {
        case .stayVisible: return manuallyHidden ? .hidden : .shown
        case .collapse: return .collapsed
        case .hide: return .hidden
        }
    }

    /// Initial effects at launch.
    public mutating func start() -> [Effect] {
        base = rest
        return effects(for: base)
    }

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .externalDragBegan:
            dragActive = true
            var effects: [Effect] = [.cancelTimer(.autoHide), .cancelTimer(.linger)]
            if graceActive {
                graceActive = false
                effects.append(.cancelTimer(.grace))
            }
            return effects

        case let .revealTriggered(placement):
            guard dragActive else { return [] }
            if case .nearPointer = placement {
                revealedForDrag = true
                return [.present(placement)]
            }
            guard !isVisible else { return [] }
            revealedForDrag = true
            return [.present(.edge)]

        case .externalDragEnded:
            dragActive = false
            guard revealedForDrag else { return [] }
            graceActive = true
            return [.startTimer(.grace, Self.graceInterval)]

        case .dropCompleted:
            var effects: [Effect] = []
            if graceActive {
                graceActive = false
                effects.append(.cancelTimer(.grace))
            }
            revealedForDrag = false
            manuallyHidden = false
            if base != .pinned { base = .shown }
            effects.append(.present(.edge))
            return effects

        case .timerFired(.grace):
            guard graceActive else { return [] }
            graceActive = false
            revealedForDrag = false
            return effects(for: base)

        case .pointerEntered:
            pointerInside = true
            return [.cancelTimer(.autoHide)]

        case .pointerExited:
            pointerInside = false
            return shouldAutoHide ? [.startTimer(.autoHide, Self.autoHideInterval)] : []

        case .timerFired(.autoHide), .timerFired(.linger):
            guard base == .shown, !pointerInside, !dragActive, !internalDragActive, !revealedForDrag, rest != .shown else { return [] }
            base = rest
            return effects(for: base)

        case .tabActivated:
            guard base == .collapsed, !isVisible else { return [] }
            if dragActive {
                revealedForDrag = true
                return [.present(.edge)]
            }
            base = .shown
            return [.present(.edge), .startTimer(.autoHide, Self.autoHideInterval)]

        case .internalDragBegan:
            internalDragActive = true
            return [.cancelTimer(.autoHide), .cancelTimer(.linger)]

        case let .internalDragEnded(inside):
            internalDragActive = false
            pointerInside = inside
            if itemCount == 0 {
                base = .hidden
                return [.hideAll]
            }
            return shouldAutoHide ? [.startTimer(.autoHide, Self.autoHideInterval)] : []

        case .toggle:
            return isVisible ? hideManually() : showPinned()

        case .show:
            return showPinned()

        case .hide:
            return isVisible ? hideManually() : []

        case .longPress:
            return [.restoreLatestBatch] + showPinned()

        case let .itemCountChanged(count):
            let previous = itemCount
            itemCount = count
            if count == 0, previous > 0, !dragActive, !internalDragActive, !revealedForDrag, !graceActive {
                base = .hidden
                return [.cancelTimer(.autoHide), .cancelTimer(.linger), .hideAll]
            }
            if !isVisible, base == .collapsed, rest == .hidden {
                base = .hidden
                return [.hideAll]
            }
            return []

        case .itemsAddedExternally:
            guard !dragActive, !internalDragActive else { return [] }
            if base != .pinned { base = .shown }
            return [.present(.edge), .startTimer(.linger, Self.lingerInterval)]

        case let .idlePolicyChanged(policy):
            idlePolicy = policy
            guard !dragActive, !revealedForDrag, !internalDragActive, base != .pinned, base != rest else { return [] }
            base = rest
            return effects(for: base)
        }
    }

    private var shouldAutoHide: Bool {
        base == .shown && rest != .shown && !pointerInside && !dragActive && !internalDragActive && !revealedForDrag
    }

    private mutating func showPinned() -> [Effect] {
        manuallyHidden = false
        revealedForDrag = false
        graceActive = false
        base = .pinned
        return [.cancelTimer(.grace), .cancelTimer(.autoHide), .cancelTimer(.linger), .present(.edge), .makeKey]
    }

    private mutating func hideManually() -> [Effect] {
        manuallyHidden = true
        revealedForDrag = false
        graceActive = false
        base = rest
        return [.cancelTimer(.grace), .cancelTimer(.autoHide), .cancelTimer(.linger)] + effects(for: base)
    }

    private func effects(for base: Base) -> [Effect] {
        switch base {
        case .hidden: [.hideAll]
        case .collapsed: [.collapseToTab]
        case .shown, .pinned: [.present(.edge)]
        }
    }
}
