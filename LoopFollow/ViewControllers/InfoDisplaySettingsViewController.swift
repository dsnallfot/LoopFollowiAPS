//
//  InfoDisplaySettingsViewController.swift
//  LoopFollow
//
//  Created by Jose Paredes on 7/16/20.
//  Copyright © 2020 Jon Fawcett. All rights reserved.
//

import UIKit
import Eureka
import EventKit
import EventKitUI

class InfoDisplaySettingsViewController: FormViewController {
    var appStateController: AppStateController?

    
    override func viewDidLoad() {
        print("Display Load")
        super.viewDidLoad()
        if UserDefaultsRepository.forceDarkMode.value {
            overrideUserInterfaceStyle = .dark
        }
         
        createForm()
    }
    
    private func createForm() {
        form
        +++ Section("General")
        <<< SwitchRow("hideInfoTable"){ row in
            row.title = "Hide Information Table"
            row.tag = "hideInfoTable"
            row.value = UserDefaultsRepository.hideInfoTable.value
        }.onChange { [weak self] row in
                    guard let value = row.value else { return }
                    UserDefaultsRepository.hideInfoTable.value = value           
        }
        
        <<< SwitchRow("useDynCr"){ row in
            row.title = "Use Dynamic CR"
            row.value = UserDefaultsRepository.useDynCr.value
        }.onChange { [weak self] row in
            guard let value = row.value else { return }
            UserDefaultsRepository.useDynCr.value = value
        }
        
        +++ MultivaluedSection(multivaluedOptions: .Reorder, header: "Information Display Settings", footer: "Välj och sortera ordning på önskad information") {
        
           // TODO: add the other display values
           $0.tag = "InfoDisplay"
           
            for i in 0..<UserDefaultsRepository.infoNames.value.count {
              $0 <<< TextRow() { row in
                if(UserDefaultsRepository.infoVisible.value[UserDefaultsRepository.infoSort.value[i]]) {
                    row.title = "\u{2713}\t\(UserDefaultsRepository.infoNames.value[UserDefaultsRepository.infoSort.value[i]])"
                 } else {
                    row.title = "\u{2001}\t\(UserDefaultsRepository.infoNames.value[UserDefaultsRepository.infoSort.value[i]])"
                 }
              }.onCellSelection{(cell, row) in
                let i = row.indexPath!.row
                UserDefaultsRepository.infoVisible.value[UserDefaultsRepository.infoSort.value[i]] = !UserDefaultsRepository.infoVisible.value[UserDefaultsRepository.infoSort.value[i]]
                
                self.tableView.reloadData()
                
                //print("\(row.title)")
                //print("\(row.indexPath?.row)")
              }.cellSetup { (cell, row) in
                 cell.textField.isUserInteractionEnabled = false
              }.cellUpdate{ (cell, row) in
                if(UserDefaultsRepository.infoVisible.value[UserDefaultsRepository.infoSort.value[i]]) {
                    row.title = "\u{2713}\t\(UserDefaultsRepository.infoNames.value[UserDefaultsRepository.infoSort.value[i]])"
                 } else {
                    row.title = "\u{2001}\t\(UserDefaultsRepository.infoNames.value[UserDefaultsRepository.infoSort.value[i]])"
                 }
                  if let appStateController = self.appStateController {
                      appStateController.infoDataSettingsChanged = true
                  }
              }
           }
       }
    
    
        +++ ButtonRow() {
            $0.title = "DONE"
        }.onCellSelection { (row, arg) in
            if let navigationController = self.navigationController {
                navigationController.popViewController(animated: true)
            } else {
                // If there's no navigation controller, dismiss the current view controller
                self.dismiss(animated: true, completion: nil)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        //let view = tableView
        let sourceIndex = sourceIndexPath.row
        let destIndex = destinationIndexPath.row
        
        // new sort
        if(destIndex != sourceIndex ) {
            if let appStateController = self.appStateController {
                appStateController.infoDataSettingsChanged = true
            }
           
            let tmpVal = UserDefaultsRepository.infoSort.value[sourceIndex]
            UserDefaultsRepository.infoSort.value.remove(at:sourceIndex)
            UserDefaultsRepository.infoSort.value.insert(tmpVal, at:destIndex)
       
        }
        
    }
 }
