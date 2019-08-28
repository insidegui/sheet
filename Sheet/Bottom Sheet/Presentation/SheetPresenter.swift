//
//  SheetPresenter.swift
//  Sheet
//
//  Created by Guilherme Rambo on 05/08/19.
//  Copyright © 2019 Guilherme Rambo. All rights reserved.
//

import UIKit

/// Allows a controller to present another controller as a sheet that can be
/// snapped to different positions.
public final class SheetPresenter: NSObject {

    private var window: SheetPresentationWindow?

    private var container: SheetContainerViewController?

    private weak var presenter: UIViewController?

    private var presenterWindow: UIWindow? {
        return presenter?.view.window
    }

    /// Whether the sheet is currently being presented.
    private(set) var isPresentingSheet = false

    /// Starts the presentation of a controller as a sheet.
    /// - Parameter presenter: The view controller that's presenting the sheet.
    /// - Parameter content: The view controller that will be inside the sheet.
    /// - Parameter initialDetent: The initial position of the sheet (defaults to `.middle`)
    /// - Parameter allowedDetents: The allowed snapping positions for the sheet (defaults to all positions).
    /// - Parameter dismissWhenFlungDown: Whether the sheet can be dismissed when flung down by the user.
    /// - Parameter metrics: Metrics defining the look of the sheet (can be ommited to use default metrics).
    public func presentSheet(from presenter: UIViewController,
                      with content: UIViewController,
                      initialDetent: SheetDetent = .middle,
                      allowedDetents: [SheetDetent] = SheetDetent.allCases,
                      dismissWhenFlungDown: Bool = false,
                      metrics: SheetMetrics = .default)
    {
        guard !isPresentingSheet else { return }
        
        assert(presenter.view.window != nil, "Tried to present a sheet from a view controller that's not currently on screen!")

        guard window == nil else { return }

        self.presenter = presenter
        presenterWindow?.clipsToBounds = true

        let w = SheetPresentationWindow(frame: presenter.view.bounds)
        let c = SheetContainerViewController(
            sheetContentController: content,
            presentingSheetPresenter: self,
            initialDetent: initialDetent,
            allowedDetents: allowedDetents,
            metrics: metrics,
            dismissWhenFlungDown: dismissWhenFlungDown
        )

        w.rootViewController = c
        w.windowLevel = .alert
        w.makeKeyAndVisible()

        self.window = w
        self.container = c

        c.performSnapCompanionAnimations = { [weak self] detent in
            guard let self = self else { return }

            switch detent {
            case .maximum:
                self.animateToMaximumDetent()
            default:
                self.animateToNonMaximumDetent()
            }
        }

        c.transitionToMaximumDetentProgressDidChange = { [weak self] progress in
            self?.updateSheetAnimationStateToMaximumDetent(with: progress)
        }

        isPresentingSheet = true
    }

    /// Dismisses the sheet.
    /// - Parameter coordinator: Perform the dismissal together with an animated transition.
    /// - Parameter completion: Called when the dismissal animation has completed.
    public func dismiss(with coordinator: UIViewControllerTransitionCoordinator? = nil, completion: (() -> Void)? = nil) {
        container?.dismissSheet(duration: 0.4) { [weak self] in
            completion?()

            self?.window?.resignKey()
            self?.window?.isHidden = true
            self?.window?.removeFromSuperview()

            self?.container = nil
            self?.presenter = nil
            self?.window = nil

            self?.isPresentingSheet = false
        }
    }

    private var presenterTranslationWhenAtMaximumDetent: CGFloat {
        let safeAreaTop = container?.view.safeAreaInsets.top ?? 0

        return safeAreaTop <= 20 ? safeAreaTop + 22 : safeAreaTop + 8
    }

    private let presenterHorizontalScaleWhenAtMaximumDetent: CGFloat = 0.914

    private let presenterCornerRadiusWhenAtMaximumDetent: CGFloat = 10

    private let presenterScaleWhenAtMaximumDetent: CGFloat = 0.9

    private func updateSheetAnimationStateToMaximumDetent(with progress: CGFloat) {
        let translation = presenterTranslationWhenAtMaximumDetent * progress
        let radius = presenterCornerRadiusWhenAtMaximumDetent * progress
        let scale = min(1, 1 - progress + presenterScaleWhenAtMaximumDetent)

        let translationTransform = CATransform3DMakeTranslation(0, translation, 0)
        let scaleTransform = CATransform3DMakeScale(scale, 1, 1)

        presenterWindow?.layer.transform = CATransform3DConcat(translationTransform, scaleTransform)
        presenterWindow?.layer.cornerRadius = radius
    }

    private func animateToMaximumDetent() {
        let translationTransform = CATransform3DMakeTranslation(0, presenterTranslationWhenAtMaximumDetent, 0)
        let scaleTransform = CATransform3DMakeScale(presenterScaleWhenAtMaximumDetent, 1, 1)

        presenterWindow?.layer.transform = CATransform3DConcat(translationTransform, scaleTransform)
        presenterWindow?.layer.cornerRadius = presenterCornerRadiusWhenAtMaximumDetent
    }

    private func animateToNonMaximumDetent() {
        presenterWindow?.layer.transform = CATransform3DIdentity
        presenterWindow?.layer.cornerRadius = 0
    }

}
