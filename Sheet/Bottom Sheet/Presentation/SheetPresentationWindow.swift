//
//  SheetPresentationWindow.swift
//  Sheet
//
//  Created by Guilherme Rambo on 05/08/19.
//  Copyright © 2019 Guilherme Rambo. All rights reserved.
//

import UIKit

final class SheetPresentationWindow: UIWindow {

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return rootViewController?.view.hitTest(point, with: event) != nil
    }

    deinit {
        print("\(String(describing: type(of: self))) DEINIT")
    }
    
}
