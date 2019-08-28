//
//  SheetContainerViewController.swift
//  Sheet
//
//  Created by Guilherme Rambo on 05/08/19.
//  Copyright © 2019 Guilherme Rambo. All rights reserved.
//

import UIKit

public struct SheetMetrics {
    public static let `default` = SheetMetrics()

    public let bufferHeight: CGFloat = 400
    public let cornerRadius: CGFloat = 10
    public let shadowRadius: CGFloat = 10
    public let shadowOpacity: CGFloat = 0.12

    public var trueSheetHeight: CGFloat {
        return UIScreen.main.bounds.height + bufferHeight
    }
}

/// Defines snapping positions for the sheet.
public enum SheetDetent: String, CaseIterable {

    /// A detent where the sheet will have its maximum height and have
    /// its top edge close to the top edge of the screen.
    case maximum

    /// A detent where the sheet's height will be about half the height
    /// of the screen, with its top edge close to the middle of the screen.
    case middle

    /// A detent at which the sheet's contents are effectively hidden,
    /// but the sheet's header still peek's through the bottom of the screen,
    /// allowing the user to expand it.
    case minimum

    /// The velocity at which the sheet will ignore the middle detent and transition directly
    /// from the maximum detent to the minimum detent when swiping down.
    static let thresholdVelocityForSkippingMiddleDetent: CGFloat = 2000

    /// The velocity at which the sheet will be dismissed instead of snapping
    /// to a detent when flung down.
    static let thresholdVelocityForFlingDismissal: CGFloat = 4000

    /// The velocity at which the sheet will snap to the middle detent when flung upwards from
    /// the minimum detent, ignoring the distance between the current position and the minimum detent.
    static let thresholdVelocityForEnforcingMinimumToMiddleTransition: CGFloat = 900

}

extension SheetDetent: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .maximum: return "<Maximum Detent>"
        case .middle: return "<Middle Detent>"
        case .minimum: return "<Minimum Detent>"
        }
    }
}

class SheetContainerViewController: UIViewController {

    var transitionToMaximumDetentProgressDidChange: ((CGFloat) -> Void)?
    var performSnapCompanionAnimations: ((SheetDetent) -> Void)?

    let sheetContentController: UIViewController
    let initialDetent: SheetDetent
    let metrics: SheetMetrics

    let allowedDetents: [SheetDetent]
    let dismissWhenFlungDown: Bool

    weak var presentingSheetPresenter: SheetPresenter?

    init(sheetContentController: UIViewController,
         presentingSheetPresenter: SheetPresenter?,
         initialDetent: SheetDetent = .middle,
         allowedDetents: [SheetDetent] = SheetDetent.allCases,
         metrics: SheetMetrics = .default,
         dismissWhenFlungDown: Bool = false)
    {
        self.sheetContentController = sheetContentController
        self.presentingSheetPresenter = presentingSheetPresenter
        self.initialDetent = initialDetent
        self.metrics = metrics
        self.allowedDetents = allowedDetents
        self.dismissWhenFlungDown = dismissWhenFlungDown

        super.init(nibName: nil, bundle: nil)
    }

    private var overrideStatusBarStyle: UIStatusBarStyle? {
        didSet {
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return overrideStatusBarStyle ?? super.preferredStatusBarStyle
    }

    override var childForStatusBarStyle: UIViewController? {
        return overrideStatusBarStyle != nil ? nil : sheetContentController
    }

    override var childForStatusBarHidden: UIViewController? {
        return sheetContentController
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    #warning("TODO: Rubber band and limit maximum sheet height while interactively moving")
    private var maximumSheetHeight: CGFloat {
        return value(for: .maximum) - view.safeAreaInsets.top
    }

    #warning("TODO: Rubber band and limit minimum sheet height while interactively moving")
    private var minimumSheetHeight: CGFloat {
        return metrics.shadowRadius + view.safeAreaInsets.bottom
    }

    private func heightToBottom(constant: CGFloat) -> CGFloat {
        return metrics.trueSheetHeight - constant
    }

    private func normalize(_ value: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private lazy var availableHeightOnMiddleDetent = abs(value(for: .middle) - metrics.trueSheetHeight)
    private lazy var availableHeightOnMaximumDetent = abs(value(for: .maximum) - metrics.trueSheetHeight)

    var maximumDetentAnimationProgress: CGFloat {
        guard sheetBottomConstraint.constant < value(for: .middle) else { return 0 }

        let currentAvailableHeight = sheetController.availableHeight

        let rawMin = availableHeightOnMiddleDetent / availableHeightOnMaximumDetent
        let rawValue = currentAvailableHeight / availableHeightOnMaximumDetent

        return normalize(rawValue, range: rawMin...1)
    }

    private func value(for detent: SheetDetent) -> CGFloat {
        switch detent {
        case .maximum: return heightToBottom(constant: UIScreen.main.bounds.height * 0.92)
        case .middle: return heightToBottom(constant: UIScreen.main.bounds.height * 0.54)
        case .minimum: return heightToBottom(constant: UIScreen.main.bounds.height * 0.16)
        }
    }

    private var flingDownDismissVelocity: CGFloat?

    private var snappingCancelled = false {
        didSet {
            if snappingCancelled { view.isUserInteractionEnabled = false }
        }
    }

    private func closestSnappingDetent(for height: CGFloat, velocity: CGPoint) -> SheetDetent {
//        print("SNAP velocity = \(velocity)")

        var winner: SheetDetent = .maximum

        let validDetents: [SheetDetent]

        if dismissWhenFlungDown, velocity.y > 0, abs(velocity.y) > SheetDetent.thresholdVelocityForFlingDismissal {
            snappingCancelled = true
            flingDownDismissVelocity = velocity.y

            presentingSheetPresenter?.dismiss()

            return .minimum
        }

        if abs(velocity.y) > SheetDetent.thresholdVelocityForSkippingMiddleDetent {
            if velocity.y < 0 {
                // Swiping up really hard, force maximum detent
                validDetents = [.maximum]
            } else {
                // Swiping hard in any direction, ignore middle detent
                validDetents = allowedDetents.filter({ $0 != .middle })
            }
        } else if velocity.y < 0,
            abs(velocity.y) > SheetDetent.thresholdVelocityForEnforcingMinimumToMiddleTransition,
            sheetBottomConstraint.constant > value(for: .middle)
        {
            // Swiping up hard in between minimum and medium detent, force middle detent
            validDetents = [.middle]
        } else {
            validDetents = allowedDetents
        }

        for detent in validDetents {
            if abs(height - value(for: detent)) < abs(height - value(for: winner)) {
                winner = detent
            }
        }

        return winner
    }

    private weak var currentAnimator: UIViewPropertyAnimator?

    private func timingCurve(with velocity: CGFloat) -> FluidTimingCurve {
        let damping: CGFloat = velocity.isZero ? 100 : 30

        return FluidTimingCurve(
            velocity: CGVector(dx: velocity, dy: velocity),
            stiffness: 400,
            damping: damping
        )
    }

    private func estimateTargetDetent(with velocity: CGFloat) -> SheetDetent {
        return .maximum
    }

    private func snap(to detent: SheetDetent, with velocity: CGPoint = .zero, completion: (() -> Void)? = nil) {
        guard !snappingCancelled else { return }

        if currentAnimator?.state == .some(.active) {
            currentAnimator?.stopAnimation(true)
        }

        let targetValue = value(for: detent)
        // the 0.5 is to ensure there's always some distance for the gesture to work with
        let distanceY = (sheetBottomConstraint.constant - 0.5) - targetValue

        let effectiveVelocity = velocity.y.isInfinite || velocity.y.isNaN ? 2000 : velocity.y

        let initialVelocityY = distanceY.isZero ? 0 : effectiveVelocity/distanceY * -1

        let timing = timingCurve(with: initialVelocityY)
        let animator = UIViewPropertyAnimator(duration: 0.3, timingParameters: timing)

        animator.isUserInteractionEnabled = true

        self.sheetBottomConstraint.constant = targetValue

        animator.addAnimations {
            self.performSnapCompanionAnimations?(detent)

            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()

            self.sheetController.updateContentInsets()

            if detent == .maximum {
                self.dimmingView.alpha = self.maximumDimmingAlpha
                self.overrideStatusBarStyle = .lightContent
            } else {
                if detent == .minimum {
                    self.dimmingView.alpha = 0
                } else {
                    self.dimmingView.alpha = self.minimumDimmingAlpha
                }

                self.overrideStatusBarStyle = nil
            }
        }

        animator.addCompletion { pos in
            guard pos == .end else { return }

            completion?()
        }

        currentAnimator = animator

        animator.startAnimation()
    }

    func dismissSheet(coordinator: UIViewControllerTransitionCoordinator? = nil, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        let targetValue = metrics.trueSheetHeight

        let animationBlock = {
            self.dimmingView.alpha = 0

            self.performSnapCompanionAnimations?(.minimum)

            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()

            self.sheetController.updateContentInsets()

            self.overrideStatusBarStyle = nil
        }

        if let coordinator = coordinator {
            coordinator.animate(alongsideTransition: { _ in
                animationBlock()
            }, completion: { _ in
                completion?()
            })
        } else {
            let distanceY = sheetBottomConstraint.constant - targetValue

            let effectiveVelocity: CGFloat

            if let flingVelocity = flingDownDismissVelocity {
                effectiveVelocity = flingVelocity.isInfinite || flingVelocity.isNaN ? 2000 : flingVelocity
            } else {
                effectiveVelocity = 0
            }

            let initialVelocityY = distanceY.isZero ? 0 : effectiveVelocity/distanceY * -1

            let timing = timingCurve(with: initialVelocityY)

            let animator = UIViewPropertyAnimator(duration: duration, timingParameters: timing)

            animator.isUserInteractionEnabled = true

            self.sheetBottomConstraint.constant = targetValue

            animator.addAnimations {
                animationBlock()
            }

            animator.addCompletion { pos in
                guard pos == .end else { return }

                completion?()
            }

            animator.startAnimation()
        }
    }

    private lazy var sheetBottomConstraint: NSLayoutConstraint = {
        return sheetController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: metrics.trueSheetHeight)
    }()

    private(set) lazy var sheetController: SheetViewController = {
        let v = SheetViewController(metrics: self.metrics)

        v.rubberBandingStartHandler = { [weak self] in
            self?.registerRubberBandingStart()
        }
        v.rubberBandingUpdateHandler = { [weak self] offset in
            self?.followSheetScrollViewRubberBanding(with: offset)
        }
        v.rubberBandingFinishedHandler = { [weak self] in
            self?.rubberBandingFinished()
        }

        return v
    }()

    private lazy var dimmingView: UIView = {
        let v = UIView()

        v.backgroundColor = .black
        v.alpha = 0
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.frame = view.bounds

        return v
    }()

    private lazy var panGesture: UIPanGestureRecognizer = {
        let g = UIPanGestureRecognizer(target: self, action: #selector(handlePan))

        g.delegate = self

        return g
    }()

    override func loadView() {
        view = SheetContainerView(metrics: metrics)

        view.addSubview(dimmingView)

        addChild(sheetController)
        view.addSubview(sheetController.view)
        sheetController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            sheetController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sheetController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sheetController.view.heightAnchor.constraint(equalToConstant: metrics.trueSheetHeight),
            sheetBottomConstraint
        ])

        sheetController.installContent(sheetContentController)

        sheetController.view.addGestureRecognizer(panGesture)
    }

    private var snappedToInitialDetent = false

    private func snapToInitialDetent() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(doSnapToInitialDetent), with: nil, afterDelay: 0)
    }

    @objc private func doSnapToInitialDetent() {
        snap(to: initialDetent)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        snapToInitialDetent()
    }

    private var isDraggingSheet = false
    private var lastTranslationY: CGFloat = 0
    private var initialSheetHeightConstant: CGFloat = 0

    private var minimumDimmingAlpha: CGFloat = 0.1
    private var maximumDimmingAlpha: CGFloat = 0.5

    private func snapToClosestDetent(with velocity: CGPoint) {
        let target = closestSnappingDetent(for: sheetBottomConstraint.constant, velocity: velocity)

        snap(to: target, with: velocity)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        let velocity = recognizer.velocity(in: view)

        switch recognizer.state {
        case .began:
            isDraggingSheet = true
            initialSheetHeightConstant = sheetBottomConstraint.constant
        case .ended, .cancelled, .failed:
            isDraggingSheet = false

            if !sheetController.isScrollingEnabled {
                snapToClosestDetent(with: velocity)
            }

            lastTranslationY = 0
        case .changed:
            let newConstant = sheetBottomConstraint.constant + (translation.y - lastTranslationY)

            if sheetController.isScrollViewAtTheTop {
                if newConstant > value(for: .maximum) || translation.y > 0 {
                    sheetBottomConstraint.constant = newConstant

                    sheetController.updateContentInsets()

                    sheetController.isScrollingEnabled = false

                    progressMaximumDetentInteractiveAnimation()
                } else {
                    sheetController.isScrollingEnabled = true
                }
            } else {
                sheetController.isScrollingEnabled = true
            }

            lastTranslationY = translation.y
        default:
            break
        }
    }

    private var sheetBottomConstantAtRubberBandingStart: CGFloat = 0

    private func registerRubberBandingStart() {
        sheetBottomConstantAtRubberBandingStart = sheetBottomConstraint.constant
    }

    private func rubberBandingFinished() {
        guard currentAnimator?.state != .active else { return }
        
        snapToClosestDetent(with: .zero)
    }

    private func followSheetScrollViewRubberBanding(with offset: CGFloat) {
        guard offset < 0 else { return } // only follow rubber banding when at the top

        sheetBottomConstraint.constant = sheetBottomConstantAtRubberBandingStart - offset

        progressMaximumDetentInteractiveAnimation()
    }

    private func progressMaximumDetentInteractiveAnimation() {
        let progressToMaxDetent = maximumDetentAnimationProgress

        if progressToMaxDetent >= 0.5 {
            overrideStatusBarStyle = .lightContent
        } else {
            overrideStatusBarStyle = nil
        }

        if sheetBottomConstraint.constant < value(for: .minimum) {
            let duration: TimeInterval = dimmingView.alpha == 0 ? 0.3 : 0

            UIView.animate(withDuration: duration) {
                self.dimmingView.alpha = self.minimumDimmingAlpha + self.maximumDimmingAlpha * progressToMaxDetent
            }
        } else {
            dimmingView.alpha = 0
        }

        transitionToMaximumDetentProgressDidChange?(progressToMaxDetent)
    }

    deinit {
        print("\(String(describing: type(of: self))) DEINIT")
    }

}

private final class SheetContainerView: UIView {

    let metrics: SheetMetrics

    init(metrics: SheetMetrics) {
        self.metrics = metrics

        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let result = super.hitTest(point, with: event) else { return nil }

        return result.isSheetDescendant ? result : nil
    }

}

extension UIView {
    var isSheetDescendant: Bool {
        var currentView: UIView? = self

        repeat {
            if currentView is SheetContentView { return true }

            currentView = currentView?.superview
        } while currentView != nil

        return false
    }
}

extension SheetContainerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
