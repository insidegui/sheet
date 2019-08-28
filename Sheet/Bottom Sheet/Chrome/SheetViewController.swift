//
//  SheetViewController.swift
//  Sheet
//
//  Created by Guilherme Rambo on 05/08/19.
//  Copyright © 2019 Guilherme Rambo. All rights reserved.
//

import UIKit

class SheetViewController: UIViewController {

    let metrics: SheetMetrics

    init(metrics: SheetMetrics) {
        self.metrics = metrics

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private var container: SheetContainerViewController? {
        return parent as? SheetContainerViewController
    }

    var rubberBandingStartHandler: (() -> Void)?
    var rubberBandingUpdateHandler: ((CGFloat) -> Void)?
    var rubberBandingFinishedHandler: (() -> Void)?

    var isScrollingEnabled = true

    private let scrollViewAtTheTopDeltaThreshold: CGFloat = 3

    var isScrollViewAtTheTop: Bool {
        return abs(scrollView.contentOffset.y - scrollView.contentInset.top * -1) < scrollViewAtTheTopDeltaThreshold
    }

    private lazy var contentView: SheetContentView = {
        let v = SheetContentView(metrics: self.metrics)

        v.layer.cornerRadius = view.layer.cornerRadius
        v.layer.maskedCorners = view.layer.maskedCorners
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.clipsToBounds = true

        return v
    }()

    private(set) lazy var scrollView: UIScrollView = {
        let v = UIScrollView()

        v.translatesAutoresizingMaskIntoConstraints = false
        v.delegate = self

        return v
    }()

    override func loadView() {
        view = UIView()

        view.backgroundColor = #colorLiteral(red: 0.9411764706, green: 0.9411764706, blue: 0.9411764706, alpha: 1)
        view.layer.cornerRadius = metrics.cornerRadius
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = Float(metrics.shadowOpacity)
        view.layer.shadowRadius = metrics.shadowRadius
        view.layer.shadowOffset = CGSize(width: 0, height: -1)

        contentView.frame = view.bounds
        view.addSubview(contentView)

        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private weak var contentController: UIViewController?

    func installContent(_ content: UIViewController) {
        contentController = content

        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content.view)

        content.didMove(toParent: self)

        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: scrollView.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            content.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            content.view.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    var availableHeight: CGFloat {
        guard let parentView = parent?.view else { return 0 }

        return parentView.bounds.intersection(view.frame).height
    }

    private var scrolledUpOnFirstContentInsetUpdate = false

    private var initialContentOffset: CGPoint = .zero
    private var previousContentOffset: CGPoint = .zero

    func updateContentInsets() {
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: metrics.trueSheetHeight - availableHeight, right: 0)

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(scrollUpOnFirstContentInsetUpdateIfNeeded), object: nil)
        perform(#selector(scrollUpOnFirstContentInsetUpdateIfNeeded), with: nil, afterDelay: 0)
    }

    @objc private func scrollUpOnFirstContentInsetUpdateIfNeeded() {
        guard !scrollView.contentInset.top.isZero else { return }
        guard !scrolledUpOnFirstContentInsetUpdate else { return }
        scrolledUpOnFirstContentInsetUpdate = true

        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.contentInset.top), animated: false)
    }

    deinit {
        print("\(String(describing: type(of: self))) DEINIT")
    }
    
}

final class SheetContentView: UIView {

    let metrics: SheetMetrics

    init(metrics: SheetMetrics) {
        self.metrics = metrics

        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

}

extension SheetViewController: UIScrollViewDelegate {

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        initialContentOffset = scrollView.contentOffset
    }

    func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
        rubberBandingStartHandler?()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        rubberBandingFinishedHandler?()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        defer { previousContentOffset = scrollView.contentOffset }

        var isRubberBandingUp = false
        var bandOffset: CGFloat = 0

        if scrollView.isDecelerating {
            let effectiveOffset = scrollView.contentOffset.y + scrollView.contentInset.top

            if scrollView.contentOffset.y < initialContentOffset.y {
                if effectiveOffset < 0 {
                    isRubberBandingUp = true
                    bandOffset = effectiveOffset
                    rubberBandingUpdateHandler?(effectiveOffset)
                }
            }
        }

        if isRubberBandingUp {
            // Counteract rubber banding by shifting contents so that they are flush with the top.
            // We can't use setContentOffset here because that kills the rubber banding.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)

            contentController?.view.layer.transform = CATransform3DMakeTranslation(0, bandOffset, 0)

            CATransaction.commit()
        } else {
            let currentTransform = contentController?.view.layer.transform ?? CATransform3DIdentity

            if !CATransform3DIsIdentity(currentTransform) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                CATransaction.setAnimationDuration(0)

                contentController?.view.layer.transform = CATransform3DIdentity

                CATransaction.commit()
            }
        }

        guard isScrollingEnabled else {
            scrollView.setContentOffset(previousContentOffset, animated: false)
            return
        }
    }

}
