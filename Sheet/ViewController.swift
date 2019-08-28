//
//  ViewController.swift
//  Sheet
//
//  Created by Guilherme Rambo on 28/08/19.
//  Copyright © 2019 Guilherme Rambo. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    private lazy var sheetContentController: UIViewController = {
        let c = UIViewController()

        c.view.backgroundColor = .red

        return c
    }()

    private lazy var sheetPresenter = SheetPresenter()

    @IBAction func showSheet(_ sender: UIButton) {
        sheetPresenter.presentSheet(from: self, with: sheetContentController)
    }

}

